#!/bin/bash
# Скрипт запуска. Вся настройка CSP/сертификатов выполнена на этапе сборки
# образа (см. .docker/Dockerfile): импорт CA, установка контейнера ключа и
# сертификата, экспорт /etc/stunnel/client.crt. Здесь остаётся только то, что
# зависит от переменных окружения.

# подстановка уровня отладки stunnel из окружения (если задан)
if [[ -n "${STUNNEL_DEBUG_LEVEL:-}" ]]; then
    sed -i "s/^debug=.*$/debug=${STUNNEL_DEBUG_LEVEL}/g" /etc/stunnel/stunnel.conf
fi

# запуск socat (зависит от STUNNEL_HOST / STUNNEL_HTTP_PROXY*)
echo "Starting socat..."
nohup bash /scripts/stunnel-socat.sh </dev/null >/dev/null 2>&1 &

# запуск stunnel в foreground
echo "Starting stunnel"
exec "$@"
