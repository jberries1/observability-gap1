#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

USER="${METRICS_USER:-prometheus}"
PASS="${METRICS_PASS:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)}"

openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout ca.key -out ca.crt \
  -subj "/CN=gap1-local-ca" 2>/dev/null

openssl req -newkey rsa:2048 -nodes \
  -keyout gw.key -out gw.csr \
  -subj "/CN=exporters-gw" 2>/dev/null

cat > gw.ext <<EXT
subjectAltName = DNS:exporters-gw, DNS:localhost, IP:127.0.0.1
extendedKeyUsage = serverAuth
EXT

openssl x509 -req -in gw.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out gw.crt -days 365 -extfile gw.ext 2>/dev/null

rm -f gw.csr gw.ext ca.srl

printf '%s:%s\n' "$USER" "$(openssl passwd -apr1 "$PASS")" > htpasswd

printf '%s' "$PASS" > gw_password

chmod 600 ca.key gw.key
chmod 644 htpasswd gw_password ca.crt gw.crt

echo "Готово. Логин: $USER"
echo "Пароль лежит в $(pwd)/gw_password"
