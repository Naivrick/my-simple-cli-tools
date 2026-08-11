#!/bin/bash

# ==============================================================================
# УНИВЕРСАЛЬНЫЙ СКРИПТ ЭКСПРЕСС-ДИАГНОСТИКИ И БЕЗОПАСНОСТИ ДЛЯ UBUNTU/DEBIAN
# ==============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

echo "========================================"
echo "  Экспресс-диагностика сервера"
echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "========================================"
echo ""

# --- 1. СИСТЕМА ---
echo "─── СИСТЕМА ───"
echo "Hostname: $(hostname)"
echo "Kernel:   $(uname -r)"
echo "Uptime:   $(uptime -p 2>/dev/null || uptime)"
echo ""

echo "CPU / RAM:"
uptime
free -h
echo ""

echo "Диск:"
df -h -x tmpfs -x devtmpfs -x overlay 2>/dev/null
echo ""

# --- 2. DOCKER ---
echo "─── DOCKER ───"
if command -v docker &>/dev/null && docker info &>/dev/null; then
    echo "Контейнеры:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    echo "Ресурсы Docker (RAM / CPU):"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null
    echo ""

    echo "Логи активных контейнеров (последние важные события):"
    RUNNING_CONTAINERS=$(docker ps --format "{{.Names}}")
    if [ -n "$RUNNING_CONTAINERS" ]; then
        for container in $RUNNING_CONTAINERS; do
            echo "  [$container]:"
            # Ошибки за последние 20 строк
            ERR_LOGS=$(docker logs --tail 20 "$container" 2>&1 | grep -iE "error|warn|fail|fatal|critical" | tail -3)
            if [ -n "$ERR_LOGS" ]; then
                echo "$ERR_LOGS"
            else
                echo "    [Ошибок и предупреждений не обнаружено]"
            fi
            # Самая последняя строчка лога
            echo "    Последняя строка: $(docker logs --tail 1 "$container" 2>&1)"
            echo ""
        done
    else
        echo "  Нет запущенных контейнеров."
        echo ""
    fi
else
    echo "Docker не запущен или у текущего пользователя нет прав на docker.sock"
    echo ""
fi

# --- 3. POSTGRESQL (Автопоиск контейнеров) ---
echo "─── POSTGRESQL (DOCKER) ───"
if command -v docker &>/dev/null && docker info &>/dev/null; then
    PG_CONTAINER=$(docker ps --format "{{.Names}}" | grep -E "postgres|pg|db" | head -1)
    if [ -n "$PG_CONTAINER" ]; then
        echo "Обнаружен контейнер PostgreSQL: [$PG_CONTAINER]"
        PG_USER=$(docker exec "$PG_CONTAINER" env 2>/dev/null | grep POSTGRES_USER | cut -d= -f2)
        PG_USER=${PG_USER:-postgres}

        echo "Версия и статус:"
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -c "SELECT version();" 2>/dev/null || echo "Не удалось подключиться к psql"
        echo ""

        echo "Базы данных:"
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -c "\l" 2>/dev/null
        echo ""

        echo "Активные соединения:"
        docker exec "$PG_CONTAINER" psql -U "$PG_USER" -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;" 2>/dev/null
        echo ""
    else
        echo "Контейнеры с PostgreSQL не найдены."
        echo ""
    fi
else
    echo "Docker недоступен."
    echo ""
fi

# --- 4. СЕТЬ ---
echo "─── СЕТЬ ───"
echo "Открытые порты (LISTEN):"
if command -v ss &>/dev/null; then
    ss -tlnp | grep LISTEN
elif command -v netstat &>/dev/null; then
    netstat -tlnp | grep LISTEN
else
    echo "Утилиты ss/netstat не найдены"
fi
echo ""

echo "Активные подключения (топ IP):"
if command -v ss &>/dev/null; then
    ss -tnp state established 2>/dev/null | awk '{print $5}' | cut -d: -f1 | grep -vE "^127\.|^$" | sort | uniq -c | sort -rn | head -10
fi
echo ""

# --- 5. БЕЗОПАСНОСТЬ И FAIL2BAN ---
echo "─── БЕЗОПАСНОСТЬ ───"
echo "Пользователи с привилегиями (sudo / wheel):"
getent group sudo wheel 2>/dev/null || echo "Группы sudo/wheel не найдены"
echo ""

echo "Последние 5 входов:"
last -5 2>/dev/null | head -5
echo ""

echo "Неудачные попытки SSH (последние 10):"
if [ -f /var/log/auth.log ]; then
    FAILED=$(grep -iE "failed password|invalid user" /var/log/auth.log 2>/dev/null | tail -10)
else
    FAILED=$(journalctl -u ssh -u sshd -n 50 --no-pager 2>/dev/null | grep -iE "failed password|invalid user" | tail -10)
fi

if [ -z "$FAILED" ]; then
    echo "  Нет неудачных попыток"
else
    echo "$FAILED"
fi
echo ""

# Проверка Fail2Ban
echo "Статус Fail2Ban:"
if command -v fail2ban-client &>/dev/null; then
    F2B_STATUS=$(sudo fail2ban-client status 2>/dev/null || fail2ban-client status 2>/dev/null)
    if [ -n "$F2B_STATUS" ]; then
        echo "$F2B_STATUS"
        echo ""
        JAILS=$(echo "$F2B_STATUS" | grep "Jail list:" | sed 's/.*Jail list://; s/,//g')
        for jail in $JAILS; do
            echo "  --> Статус Jail [$jail]:"
            sudo fail2ban-client status "$jail" 2>/dev/null | grep -E "(Currently banned|Total banned|Banned IP list)" | sed 's/^/      /'
        done
    else
        echo "  Fail2Ban установлен, но служба не запущена или требуются права sudo"
    fi
else
    echo "  Fail2ban не установлен"
fi
echo ""

echo "Доступные обновления системы:"
if command -v apt &>/dev/null; then
    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "^Listing")
    if [ -z "$UPGRADABLE" ]; then
        echo "  Система полностью обновлена"
    else
        echo "$UPGRADABLE" | head -10
        TOTAL=$(echo "$UPGRADABLE" | wc -l)
        [ "$TOTAL" -gt 10 ] && echo "  ... и ещё $((TOTAL - 10)) пакетов"
    fi
else
    echo "  Пакетный менеджер apt не найден"
fi
echo ""

# --- 6. SSL-СЕРТИФИКАТЫ ---
echo "─── SSL-СЕРТИФИКАТЫ ───"
if command -v openssl &>/dev/null; then
    # Автоматический поиск локальных сертификатов Certbot / Let's Encrypt
    CERTS=$(find /etc/letsencrypt/live/ -name "cert.pem" 2>/dev/null)
    if [ -n "$CERTS" ]; then
        for cert in $CERTS; do
            DOMAIN=$(basename "$(dirname "$cert")")
            echo "Сертификат для домена [$DOMAIN]:"
            openssl x509 -in "$cert" -noout -dates -issuer | sed 's/^/  /'
            echo ""
        done
    else
        echo "Локальные сертификаты Let's Encrypt в /etc/letsencrypt/live не найдены."
        echo "Попытка проверки активного HTTPS на localhost:443..."
        CERT_INFO=$(echo | openssl s_client -connect 127.0.0.1:443 -servername localhost 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
        if [ -n "$CERT_INFO" ]; then
            echo "$CERT_INFO"
        else
            echo "  На порту 443 не ответил рабочий SSL-сертификат"
        fi
    fi
else
    echo "  openssl не установлен"
fi
echo ""

echo "========================================"
echo "  Диагностика завершена"
echo "========================================"
