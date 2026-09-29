# ДЗ GAP-4. Дашборды и алерты в Grafana

Задание: поставить Grafana рядом с Prometheus, сделать папки `infra` и `app`,
в infra — дашборд по машине, в app — по CMS. Со звёздочкой — алерты в самой
Grafana и drilldown по хостам.

Стенд взял из GAP-3 (WordPress, экспортеры за TLS-шлюзом, Prometheus,
VictoriaMetrics, Alertmanager с Telegram) и добавил Grafana.

## Что сделал

Grafana `13.2.2` — последняя на момент сдачи, порт 3000. Руками в UI ничего
не создавал, всё через provisioning в `grafana/`: источники данных, папки,
дашборды, алерты. Поднял compose — всё уже на месте. Пароль админа берётся
из `secrets/grafana_admin_password`, файл в `.gitignore`.

node_exporter пришлось переделать: в контейнере он видел только сам себя.
Теперь он в `network_mode: host` с примонтированным `/`, слушает на шлюзе
docker-сети `172.28.4.1:9100`, так что наружу по-прежнему торчит только
9443 через шлюз.

Дашборды:

- **infra / Инфраструктура: сводка** — CPU, память, диск, load, сеть, IO.
  Пороги на графиках те же, что в алертах.
- **app / CMS «Булочная №17»** — сделал под руководство: сверху плашки
  «Работает / Не работает», доступность за сутки, время ответа, RPS. Ниже
  статус каждого компонента (главная, админка, nginx, php-fpm, база) и
  timeline, где видно, что и когда падало. Ещё ниже — графики для нас:
  nginx, очередь php-fpm, коннекты к MariaDB. Этот дашборд стоит домашним.
- **infra / все хосты (drilldown)** — таблица хостов, клик по имени
  открывает **хост подробно**: CPU по ядрам, память, ФС, диски, сеть, TCP.
  Хост одна штука, но новые появятся в таблице сами.

Алерты (`grafana/provisioning/alerting/rules.yml`):

- `GrafanaCmsComponentDown` — любой компонент CMS не отвечает blackbox'у 30 сек;
- `GrafanaHostDown` — node_exporter не скрейпится минуту.

Отправляются в Alertmanager из GAP-3, а он уже раскидывает по Telegram-группам.
Второй раз настраивать Telegram в Grafana не стал.

## Грабли

- Grafana падала на старте: интервал группы алертов должен делиться на 10s,
  а у меня было 15s.
- На Docker Desktop под Windows не работает `rslave` у монтирования `/`,
  убрал.
- В Git Bash `grafana cli` не находит homepath — Git Bash переписывает пути.
  Помогло `sh -c 'cd /usr/share/grafana && grafana cli ...'`.

## Запуск

```
cd GAP-4
bash tls/gen-certs.sh
openssl rand -hex 12 > secrets/grafana_admin_password
echo -n 'ТОКЕН' > secrets/telegram_token
docker compose up -d
```

WordPress — http://localhost:8080 (пройти установку), Grafana —
http://localhost:3000, `admin` / пароль из файла.

Проверить алерт: `docker compose stop db`, через ~30 сек
`GrafanaCmsComponentDown` в Firing, база на дашборде CMS красная.

## Скриншоты

В `GAP-2/screenshots/` (и копия в `GAP-4/screenshots/`):

1. папки infra и app;
2. сводка по инфраструктуре;
3. дашборд CMS;
4. он же с остановленной базой;
5. алерты в Grafana;
6. drilldown по хостам;
7. хост подробно.
