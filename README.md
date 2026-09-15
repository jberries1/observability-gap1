# ДЗ GAP-1. Prometheus и экспортеры для CMS

Задание: поднять CMS на nginx + php-fpm + БД, повесить на неё экспортеры и
собирать метрики Prometheus раз в 5 секунд. Со звёздочкой — убрать открытые
наружу порты экспортеров за один вход с авторизацией и SSL.

## Что и где

Всё поднимается через docker compose, конфиги лежат в каталоге `GAP-1`.

CMS — WordPress: nginx отдаёт статику и проксирует php в php-fpm, данные в
MariaDB. То есть ровно тот стек, который требует задание.

Экспортеры:

- node_exporter — метрики машины: CPU, память, диск, сеть;
- nginx-prometheus-exporter — запросы и соединения nginx, берёт их из `stub_status`;
- php-fpm_exporter — воркеры, очередь запросов, упирание в `max_children`;
- mysqld_exporter — состояние БД, коннекты, запросы;
- blackbox_exporter — проверка снаружи: HTTP на главную и на `/wp-login.php`,
  плюс TCP до php-fpm и MariaDB.

Prometheus скрейпит всё это с `scrape_interval: 5s`, правила алертов лежат в
`GAP-1/prometheus/rules/alerts.yml`, Alertmanager настроен на маршрутизацию по
severity: critical будит сразу, info уходит в заглушку.

## Звёздочка: один порт вместо пяти

Изначально каждый экспортер слушал свой порт и был доступен всем. Сделал так:

- экспортеры вообще не публикуют порты на хост, живут только внутри docker-сети;
- наружу смотрит один порт 9443 — nginx-шлюз `exporters-gw`;
- на шлюзе TLS (свой CA, сертификат выписывается скриптом `tls/gen-certs.sh`) и
  basic auth;
- каждый экспортер доступен по своему пути: `/node/metrics`, `/nginx/metrics`,
  `/phpfpm/metrics`, `/mysql/metrics`, `/blackbox/probe`, остальное отдаёт 404;
- Prometheus ходит по https, проверяет сертификат по `ca.crt`, пароль читает из
  файла, в самом конфиге пароля нет.

Проверка:

```
$ curl -sk -o /dev/null -w "%{http_code}\n" https://localhost:9443/node/metrics
401
$ curl -sk -u prometheus:ПАРОЛЬ -o /dev/null -w "%{http_code}\n" https://localhost:9443/node/metrics
200
$ curl -sk -u prometheus:ПАРОЛЬ -o /dev/null -w "%{http_code}\n" https://localhost:9443/secret
404
```

## Как запускал

```
cd GAP-1
bash tls/gen-certs.sh
docker compose up -d
```

Дальше прошёл установщик WordPress на http://localhost:8080 — без этого главная
отдаёт редирект на установку, и проверка доступности выглядит криво.

Итог: 11 контейнеров в Up, 9 таргетов в Prometheus в состоянии up, главная
сайта отдаёт 200.

```
$ docker compose ps --format "table {{.Name}}\t{{.Status}}"
NAME                     STATUS
gap1-alertmanager        Up About an hour
gap1-blackbox-exporter   Up About an hour
gap1-db                  Up About an hour
gap1-exporters-gw        Up 2 minutes
gap1-mysqld-exporter     Up About an hour
gap1-nginx-exporter      Up About an hour
gap1-node-exporter       Up 49 minutes
gap1-php                 Up About an hour
gap1-phpfpm-exporter     Up About an hour
gap1-prometheus          Up 49 minutes
gap1-web                 Up About an hour

$ curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
      9 "health":"up"

$ curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080
200
```

Джобы: node, nginx, php-fpm, mysql, blackbox-http, blackbox-tcp, prometheus.
