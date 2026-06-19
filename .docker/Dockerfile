FROM debian:bookworm-slim AS gost-tunel

ARG TARGETARCH

# CERTIFICATE_PIN, CRYPTOPRO_LICENSE и CRYPTOPRO_CREDS намеренно НЕ build ARG:
# передача секрета через ARG запекает его в историю образа и слой RUN.
# Они приходят BuildKit-секретами на этапе сборки:
#   DOCKER_BUILDKIT=1 docker build \
#     --secret id=cryptopro_creds,env=CRYPTOPRO_CREDS \
#     --secret id=certificate_pin,env=CERTIFICATE_PIN \
#     --secret id=cryptopro_license,env=CRYPTOPRO_LICENSE \
#     -f .docker/Dockerfile -t rfm-tunel .
# CRYPTOPRO_CREDS — учётные данные аккаунта cryptopro.ru в формате USERNAME:PASSWORD
# для закрытого apt-репозитория CryptoPro (см. RUN установки пакетов ниже).

ENV DEBIAN_FRONTEND=noninteractive
EXPOSE 8080/tcp


# Установка CryptoPro CSP из закрытого apt-репозитория CryptoPro вместо вендорного
# .tgz. Учётные данные cryptopro.ru приходят BuildKit-секретом cryptopro_creds и НЕ
# сохраняются в слоях образа: файл sources.list с кредами создаётся и удаляется
# внутри ОДНОГО RUN, поэтому в финальный слой он не попадает. Ключ репозитория
# подключается через signed-by keyring (apt-key на bookworm удалён).
RUN --mount=type=secret,id=cryptopro_creds <<'EOF'
set -eu

echo "[FIX] installing base build deps"
apt-get update
apt-get install --reinstall -y debian-archive-keyring
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg \
    libboost-dev libxml2-dev alien libsqlite3-dev g++ unzip expect socat

echo "[FIX] configuring CryptoPro apt repo (signed-by keyring)"
install -d /etc/apt/keyrings
curl -fsSL https://www.cryptopro.ru/sites/default/files/products/csp/cryptopro_key.pub \
    | gpg --dearmor -o /etc/apt/keyrings/cryptopro.gpg

CRYPTOPRO_CREDS="$(cat /run/secrets/cryptopro_creds 2>/dev/null || true)"
if [ -z "$CRYPTOPRO_CREDS" ]; then
    echo "[FIX] ERROR: cryptopro_creds secret is empty (need USERNAME:PASSWORD for cryptopro.ru repo)"
    exit 1
fi
# Логин/пароль -> apt auth.conf.d (а НЕ в URL): корректно работает со спецсимволами
# (@ : ? % и т.п.) без URL-кодирования. Оба файла удаляются в конце этого RUN.
CRYPTOPRO_LOGIN="${CRYPTOPRO_CREDS%%:*}"
CRYPTOPRO_PASSWORD="${CRYPTOPRO_CREDS#*:}"
echo "deb [signed-by=/etc/apt/keyrings/cryptopro.gpg] https://cryptopro.ru/repo/deb 5.0-unstable main" \
    > /etc/apt/sources.list.d/cprocsp.list
install -d -m 0700 /etc/apt/auth.conf.d
{
    echo "machine cryptopro.ru/repo/deb"
    echo "login ${CRYPTOPRO_LOGIN}"
    echo "password ${CRYPTOPRO_PASSWORD}"
} > /etc/apt/auth.conf.d/cprocsp.conf
chmod 0600 /etc/apt/auth.conf.d/cprocsp.conf

echo "[FIX] installing CryptoPro packages from apt"
apt-get update
apt-get install -y \
    lsb-cprocsp-base lsb-cprocsp-rdr-64 lsb-cprocsp-kc1-64 lsb-cprocsp-capilite-64 \
    cprocsp-pki-cades-64 lsb-cprocsp-devel cprocsp-stunnel-64

cd /bin
ARCH="$(ls /opt/cprocsp/bin/)"
ln -s /opt/cprocsp/bin/$ARCH/certmgr
ln -s /opt/cprocsp/bin/$ARCH/cpverify
ln -s /opt/cprocsp/bin/$ARCH/cryptcp
ln -s /opt/cprocsp/bin/$ARCH/csptest
ln -s /opt/cprocsp/bin/$ARCH/csptestf
ln -s /opt/cprocsp/bin/$ARCH/der2xer
ln -s /opt/cprocsp/bin/$ARCH/inittst
ln -s /opt/cprocsp/bin/$ARCH/wipefile
ln -s /opt/cprocsp/sbin/$ARCH/cpconfig
ln -s /opt/cprocsp/sbin/$ARCH/stunnel_thread
cd /

echo "[FIX] removing credentials files and cleaning apt cache"
rm -f /etc/apt/sources.list.d/cprocsp.list /etc/apt/auth.conf.d/cprocsp.conf
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

COPY .docker/scripts scripts/
COPY .docker/stunnel.conf /etc/stunnel/stunnel.conf
COPY resource/root.zip /root.zip
COPY resource/root.cer /root.cer

# Настройка CryptoPro на этапе сборки (design B), инлайн вместо бывших setup_*:
#   1. доверие к корневому CA (импорт в uroot спрашивает "(o)OK"; -silent его НЕ
#      подавляет, поэтому отвечаем через expect)
#   2. установка контейнера закрытого ключа + сертификата из root.zip
#   3. регистрация клиентского сертификата (с привязкой к ключу) в хранилище CSP,
#      чтобы CryptoPro stunnel нашёл его через CertFindCertificateInStore, и экспорт
#      DER-селектора /etc/stunnel/client.crt.
# PIN приходит BuildKit-секретом и не попадает в слои образа.
# Лицензия устанавливается отдельным финальным слоем ниже (RUN с
# cryptopro_license перед HEALTHCHECK).
RUN --mount=type=secret,id=certificate_pin <<'EOF'
CERTIFICATE_PIN="$(cat /run/secrets/certificate_pin 2>/dev/null || true)"

expect <<'EXP'
spawn certmgr -inst -all -store uroot -file /root.cer
set timeout 30
expect {
  "(o)OK, (c)Cancel" { send -- "o\r"; exp_continue }
  eof
}
EXP

TMP="$(mktemp -d)"
unzip -q /root.zip -d "$TMP"
certFile="$(find "$TMP" -maxdepth 1 -mindepth 1 -type f -printf '%f\n' | head -n1)"
contDir="$(find "$TMP" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | head -n1)"
contFull="$(tail -c+5 "$TMP/$contDir/name.key")"
cp -R "$TMP/$contDir" /var/opt/cprocsp/keys/root/
if [ -n "$certFile" ]; then
  if [ -n "$CERTIFICATE_PIN" ]; then
    certmgr -inst -store uMy -file "$TMP/$certFile" -pin "$CERTIFICATE_PIN" -cont '\\.\HDIMAGE\'"$contFull"
  else
    certmgr -inst -store uMy -file "$TMP/$certFile" -cont '\\.\HDIMAGE\'"$contFull"
  fi
fi
rm -rf "$TMP"

CN="$(csptest -keys -enum -verifyc -fqcn -un | grep HDIMAGE | awk -F'|' '{print $2}' | head -1)"
if [ -z "$CN" ]; then echo "Keys container not found at build"; exit 1; fi
certmgr -inst -cont "$CN" -silent || { echo "cert install into store failed"; exit 1; }
certmgr -export -dest /etc/stunnel/client.crt -container "$CN"
if [ ! -s /etc/stunnel/client.crt ]; then echo "client.crt export failed"; exit 1; fi
EOF


RUN chmod +x scripts/entrypoint.sh
RUN chmod +x scripts/stunnel-socat.sh

# Лицензия CryptoPro — отдельным финальным слоём, чтобы её повторная установка не
# инвалидировала тяжёлые слои выше (установка пакетов, импорт сертификатов).
# Ключ приходит BuildKit-секретом cryptopro_license и не попадает в историю образа.
# Пустой секрет -> CryptoPro работает в trial-режиме (сборка не падает).
RUN --mount=type=secret,id=cryptopro_license <<'EOF'
CRYPTOPRO_LICENSE="$(cat /run/secrets/cryptopro_license 2>/dev/null || true)"
if [ -n "$CRYPTOPRO_LICENSE" ]; then
  echo "[FIX] applying CryptoPro license (final layer)"
  cpconfig -license -set "$CRYPTOPRO_LICENSE"
else
  echo "[FIX] No license provided, using trial"
fi
cpconfig -license -view
EOF

# Liveness: stunnel must be accepting connections on 8080.
# Uses bash's /dev/tcp (no extra packages needed in the image).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080' || exit 1

ENTRYPOINT ["scripts/entrypoint.sh"]
# entrypoint.sh выполняет `exec "$@"` → запускает ГОСТ-stunnel CryptoPro в foreground.
# stunnel_thread из пакета cprocsp-stunnel-64 умеет ГОСТ через CryptoPro CSP
# (Debian stunnel ГОСТ не поддерживает).
CMD ["stunnel_thread", "/etc/stunnel/stunnel.conf"]