# ДЗ GAP-3. Алертинг в Telegram

Задание: настроить Alertmanager так, чтобы алерты с severity critical уходили в
один канал, а warning — в другой.

Стенд тот же, что в GAP-2: WordPress, экспортеры за TLS-шлюзом, Prometheus с
remote write в VictoriaMetrics. Поменялись правила алертов и конфиг
Alertmanager.

## Каналы

Оба канала — Telegram: один бот и две группы.

- «Булочная №17 — critical» — сюда падает то, что надо чинить прямо сейчас,
  в том числе ночью;
- «Булочная №17 — warning» — то, что можно посмотреть утром.

Разделение на две группы нужно, чтобы на critical можно было поставить звук
и не выключать уведомления, а warning держать без звука и не привыкать
игнорировать алерты.

Токен бота Alertmanager читает из файла `secrets/telegram_token` через
`bot_token_file`, файл в `.gitignore`.

## Маршрутизация

`alertmanager/alertmanager.yml`:

- `severity = critical` → `telegram-critical`, `group_wait: 10s`,
  повтор каждые 30 минут, пока не починят;
- `severity = warning` → `telegram-warning`, повтор раз в 4 часа;
- всё без severity по умолчанию тоже уходит в warning, чтобы ничего не
  потерялось.

Группировка по `alertname` и `instance`. `send_resolved: true` — когда проблема
уходит, в чат приходит RESOLVED.

Подавление: пока горит `CmsDown`, не шлём `CmsSlowResponse` по тому же
instance, а при `MysqlDown` не шлём `MysqlConnectionsNearLimit` — это
следствия, а не отдельные проблемы.

Текст сообщения задаётся шаблоном `alertmanager/templates/telegram.tmpl`:
статус, severity, имя алерта, описание, instance и время начала/конца.

## Правила

`prometheus/rules/alerts.yml`, только warning и critical.

critical:

- `CmsDown` — сайт не отвечает 2xx 30 секунд;
- `MysqlDown` — MariaDB недоступна больше минуты. Ровно тот случай из истории,
  когда база висела 17 минут и никто не узнал;
- `PhpFpmDown` — php-fpm не принимает соединения, сайт отдаёт 502;
- `HostDiskCritical` — меньше 5% места на диске.

warning:

- `CmsSlowResponse` — сайт отвечает дольше 2 секунд;
- `ExporterDown` — какой-то таргет не скрейпится;
- `HostHighCpu`, `HostLowMemory`, `HostLowDisk` — ресурсы машины;
- `PhpFpmQueueGrowing`, `PhpFpmMaxChildrenReached` — php-fpm не справляется;
- `MysqlConnectionsNearLimit` — занято больше 80% коннектов к БД.

## Запуск

```
cd GAP-3
bash tls/gen-certs.sh
docker compose up -d
```

## Проверка

Маршрутизация без отправки сообщений:

```
docker exec gap3-alertmanager amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=critical
docker exec gap3-alertmanager amtool config routes test --config.file=/etc/alertmanager/alertmanager.yml severity=warning
```

Должно вывести `telegram-critical` и `telegram-warning`.

Отправить тестовые алерты в Alertmanager руками:

```
docker exec gap3-alertmanager amtool --alertmanager.url=http://localhost:9093 alert add TestCritical severity=critical instance=test --annotation=summary="тест critical"
docker exec gap3-alertmanager amtool --alertmanager.url=http://localhost:9093 alert add TestWarning severity=warning instance=test --annotation=summary="тест warning"
```

Первый должен прийти в группу critical, второй — в warning.

Живой вариант — положить базу:

```
docker compose stop db
```

Через минуту-полторы в critical придёт `MysqlDown`. После
`docker compose start db` — RESOLVED.
