# ДЗ GAP-4. Дашборды и алерты в Grafana

Задание: поставить рядом с Prometheus последнюю Grafana, сделать папки `infra`
и `app`, в `infra` — сводный дашборд по машине, в `app` — по CMS. Со
звёздочкой — алерты средствами самой Grafana и drilldown-дашборд.

Стенд тот же, что в GAP-3: WordPress на nginx + php-fpm + MariaDB, экспортеры
за TLS-шлюзом, Prometheus с remote write в VictoriaMetrics, Alertmanager с
отправкой в Telegram. Добавилась Grafana и поменялся node_exporter.

## Grafana

Образ `grafana/grafana:13.2.2` — последний релиз на момент сдачи. Сервис
`grafana` в `docker-compose.yml`, UI на http://localhost:3000.

Всё настраивается через provisioning, руками в UI ничего не создавал —
стенд поднимается с нуля одной командой и выглядит одинаково:

```
grafana/
├── provisioning/
│   ├── datasources/datasources.yml   # Prometheus (по умолчанию) и VictoriaMetrics
│   ├── dashboards/dashboards.yml     # две папки: infra и app
│   └── alerting/                     # контакт, политика, правила
└── dashboards/
    ├── infra/
    │   ├── infra-overview.json       # сводка по машине
    │   ├── infra-drilldown.json      # все хосты, клик → подробно
    │   └── infra-host.json           # полная информация по хосту
    └── app/
        └── cms-overview.json         # состояние CMS
```

Папки создаются из поля `folder` у провайдеров дашбордов. Дашборды
read-only: исходник в репозитории, при рестарте Grafana подтягивает версию из
файла.

Пароль админа Grafana читает из `secrets/grafana_admin_password`
(`GF_SECURITY_ADMIN_PASSWORD__FILE`), файл в `.gitignore`. Регистрация,
анонимный доступ и походы Grafana в интернет за обновлениями выключены.

Главной страницей Grafana сделан дашборд CMS — руководство открывает
Grafana и сразу видит, работает ли булочная.

## node_exporter теперь смотрит на хост

В прошлых ДЗ node_exporter жил в своём контейнере и видел в основном себя:
сеть — только свой `eth0`, диски — overlay контейнера. Для дашборда по
инфраструктуре это не годится, поэтому:

- `network_mode: host`, `pid: host`, корень хоста смонтирован в `/host` и
  передан через `--path.rootfs`;
- слушает не на всех интерфейсах, а только на шлюзе docker-сети
  `172.28.4.1:9100` (подсеть сети `gap4` зафиксирована в compose). Снаружи порт
  не виден, ходит к нему только `exporters-gw` — идея GAP-1 «один порт наружу»
  сохранилась;
- из сетевых интерфейсов выкинуты `lo`, `veth*`, `br-*`, `docker*`, из
  файловых систем — `/proc`, `/sys`, `/run` и слои docker.

## Дашборд infra: «Инфраструктура: сводка»

Всё про машину на одном экране. Сверху — статус хоста, аптайм, число ядер и
объём памяти, три спидометра CPU / память / диск `/`, load average на ядро и
текущий трафик. Ниже графики: CPU с iowait, память и swap, сеть по
интерфейсам (вход вверх, выход вниз), чтение/запись дисков, load average с
линией числа ядер и заполненность всех ФС. На графиках нарисованы пороги —
те же, что в алертах из GAP-3.

## Дашборд app: «CMS «Булочная №17»: состояние»

Сделан под вопрос руководства «можно одним экраном?». Верхний ряд читается
без знания Prometheus:

- **Сайт** — «Работает» / «Не работает», зелёным или красным;
- **Доступность за 24 часа**, %;
- **Ответ сайта** — сколько секунд ждёт покупатель;
- **Запросов в секунду**, **HTTP-код главной**, **горящих алертов**.

Дальше отдельной плашкой каждый компонент: главная, вход в админку, nginx,
PHP-FPM, база, и под ними timeline доступности — видно, что и когда лежало.
Та самая история, когда база висела 17 минут, на нём выглядит как красная
полоса в строке «База данных».

Остальное — для инженеров: время ответа страниц и разбивка ответа главной по
фазам (connect, tls, processing, transfer), TCP до php-fpm и базы, запросы и
соединения nginx, процессы и очередь php-fpm, упирание в `max_children`,
соединения MariaDB против лимита, запросы и медленные запросы.

## Звёздочка 1: алерты в Grafana

Правила в `grafana/provisioning/alerting/rules.yml`, лежат в тех же папках,
что и дашборды:

- `app` / `GrafanaCmsComponentDown` — любой компонент CMS не отвечает
  blackbox-у 30 секунд: главная, вход в админку, php-fpm (`php:9000`) или
  MariaDB (`db:3306`). В лейбле `instance` видно, что именно легло;
- `infra` / `GrafanaHostDown` — node_exporter не скрейпится минуту, машину
  не видно.

Оба с `severity: critical` и `source: grafana`, к алертам привязаны
дашборды — из уведомления можно перейти на нужную панель.

В Telegram Grafana сама не пишет. Контакт-поинт типа Alertmanager
(`contact-points.yml`) отдаёт алерты в Alertmanager из GAP-3, а там уже есть
маршрут по severity, шаблон сообщения и две группы. Второй раз настраивать
Telegram и держать токен ещё и в Grafana не захотел.

Минус: при падении CMS в critical придут два алерта — `CmsDown` из
Prometheus и `GrafanaCmsComponentDown` из Grafana. Для ДЗ оставил оба
специально, чтобы было видно, что работают обе схемы. В жизни оставил бы
одну.

## Звёздочка 2: drilldown

`infra` / «Инфраструктура: все хосты (drilldown)» — таблица всех машин, у
которых есть node_exporter: статус, CPU, память, диск, load на ядро, трафик,
аптайм. Хосты берутся из метрик, новый появится в таблице сам, как только
Prometheus начнёт его скрейпить.

Клик по имени хоста открывает «Инфраструктура: хост подробно» с этим хостом в
переменной `instance` и тем же интервалом времени. Графики CPU / память /
сеть / диск по хостам ниже таблицы кликаются так же — по линии.

На подробном дашборде: система и ядро, CPU по режимам и по ядрам, load,
переключения контекста, процессы, распределение памяти, swap и page faults,
заполненность ФС, IO и IOPS по дискам, таблица файловых систем, трафик,
пакеты, ошибки и дропы, TCP. Обратно — ссылкой «← Все хосты» в шапке.

На стенде одна машина, поэтому в таблице одна строка `cms-vm`.

## Запуск

```
cd GAP-4
bash tls/gen-certs.sh
openssl rand -base64 18 > secrets/grafana_admin_password
# токен бота, как в GAP-3
echo -n 'TOKEN' > secrets/telegram_token
docker compose up -d
```

WordPress — установщик на http://localhost:8080, Grafana —
http://localhost:3000, логин `admin`, пароль из
`secrets/grafana_admin_password`.

Если node_exporter не скрейпится (`up{job="node"} == 0`), первым делом
проверить, что файрвол хоста пускает трафик из docker-сети на
`172.28.4.1:9100`.

## Проверка

Версия и что подхватилось из provisioning:

```
$ curl -s http://localhost:3000/api/health
$ curl -s -u admin:$(cat secrets/grafana_admin_password) http://localhost:3000/api/folders
$ curl -s -u admin:$(cat secrets/grafana_admin_password) 'http://localhost:3000/api/search?type=dash-db'
$ curl -s -u admin:$(cat secrets/grafana_admin_password) http://localhost:3000/api/v1/provisioning/alert-rules
```

Алерт по CMS — положить базу:

```
docker compose stop db
```

Через ~30 секунд `GrafanaCmsComponentDown` для `db:3306` переходит в Firing
(Alerting → Alert rules), ещё через ~10 секунд сообщение в Telegram-группе
critical. На дашборде CMS плашка «База данных» красная, в timeline красная
полоса. `docker compose start db` — RESOLVED.

Алерт по инфраструктуре — остановить node_exporter:

```
docker compose stop node-exporter
```

Через минуту — `GrafanaHostDown` по `cms-vm`.

## Скриншоты

Лежат в `screenshots/`:

- `01-folders.png` — папки infra и app с дашбордами;
- `02-infra-overview.png` — сводка по инфраструктуре;
- `03-cms-overview.png` — дашборд CMS;
- `04-cms-db-down.png` — дашборд CMS, когда база остановлена;
- `05-alert-rules.png` — правила алертинга в Grafana;
- `06-alert-firing.png` — сработавший алерт и сообщение в Telegram;
- `07-drilldown.png` — таблица хостов;
- `08-host-details.png` — подробный дашборд после клика по хосту.
