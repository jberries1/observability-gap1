# ДЗ GAP-2. Долговременное хранилище метрик

Задание: подключить к Prometheus отдельное хранилище метрик, при записи
добавлять к метрикам лейбл `site: prod`, срок хранения — 2 недели.

За основу взят стенд из GAP-1: WordPress на nginx + php-fpm + MariaDB,
экспортеры за TLS-шлюзом с basic auth, Prometheus и Alertmanager.

## Хранилище

Выбрал VictoriaMetrics в single-node варианте. Для одного Prometheus этого
хватает с запасом: один бинарник, принимает remote write из коробки, отвечает
на PromQL, поднимается одним контейнером без отдельного объектного хранилища,
в отличие от Thanos и Mimir.

Настройки в `docker-compose.yml`, сервис `victoriametrics`:

- `-retentionPeriod=2w` — данные хранятся две недели;
- `-storageDataPath=/storage` — данные лежат в отдельном volume `vm-data` и
  переживают пересоздание контейнера;
- наружу опубликован порт 8428, по нему доступны API и веб-интерфейс vmui.

## Prometheus

В `prometheus/prometheus.yml` добавлен блок `remote_write`:

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    write_relabel_configs:
      - target_label: site
        replacement: prod
```

Prometheus по-прежнему скрейпит экспортеры раз в 5 секунд и хранит данные у
себя, но параллельно отправляет всё в VictoriaMetrics.

Лейбл `site` добавляется через `write_relabel_configs`, а не через
`external_labels`. Разница в том, что `write_relabel_configs` срабатывает
только на отправке в хранилище: в самом Prometheus лейбла нет, в
VictoriaMetrics есть. Задание просит именно так — добавлять лейбл во время
записи.

## Запуск

```
cd GAP-2
bash tls/gen-certs.sh
docker compose up -d
```

После запуска пройти установщик WordPress на http://localhost:8080.

## Проверка

Значения лейбла `site` в хранилище, должно быть `["prod"]`:

```
curl -s http://localhost:8428/api/v1/label/site/values
```

Сколько таргетов лежит в VictoriaMetrics с `site="prod"`, должно совпадать с
числом таргетов в Prometheus:

```
curl -s 'http://localhost:8428/api/v1/query?query=count(up{site="prod"})'
```

Тот же запрос в самом Prometheus должен вернуть пустой результат — лейбл
появляется только при записи:

```
curl -s 'http://localhost:9090/api/v1/query?query=count(up{site="prod"})'
```

Срок хранения:

```
curl -s http://localhost:8428/flags | grep retention
```

Данные в VictoriaMetrics появляются с задержкой около 30 секунд, это
нормальное поведение — свежие точки она отдаёт не сразу.
