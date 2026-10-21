#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo " [OK] $desc"
        ((PASS+=1))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL+=1))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"

check "Вход от имени root запрещён" "no" \
"$(sudo sshd -T | awk '$1=="permitrootlogin" {print $2}')"

check "Парольная аутентификация отключена" "no" \
"$(sudo sshd -T | awk '$1=="passwordauthentication" {print $2}')"

# TODO 1: Проверка, что порт SSH отличается от 22
check "Порт SSH отличается от 22" "yes" \
"$(sudo sshd -T | awk '$1=="port" {found=1; if ($2==22) bad=1} END {print (found && !bad) ? "yes" : "no"}')"

# TODO 2: Проверка maxauthtries = 3
check "Максимальное число попыток аутентификации равно 3" "3" \
"$(sudo sshd -T | awk '$1=="maxauthtries" {print $2}')"

echo "[2] Межсетевой экран"

check "Межсетевой экран активен" "active" \
"$(sudo env LC_ALL=C ufw status | awk '/^Status:/ {print $2}')"

# TODO 3: Проверка политики входящего трафика = deny
check "Входящий трафик по умолчанию запрещён" "deny" \
"$(sudo env LC_ALL=C ufw status verbose | awk '/^Default:/ {print $2}')"

echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {
    printf " %s (uid=%s)\n", $1, $3
}' /etc/passwd

echo "[5] Контейнеризация"

check "Служба Docker активна" "active" \
"$(systemctl is-active docker 2>/dev/null || true)"

check "Контейнер PostgreSQL app-db-1 в состоянии healthy" "healthy" \
"$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || true)"

ports_status="error"
if listeners="$(ss -tlnH 2>/dev/null)"; then
    ports_status="$(awk '
        $4 ~ /:(5000|5432)$/ &&
        $4 !~ /^127[.]0[.]0[.]1:(5000|5432)$/ { forbidden=1 }
        END { print forbidden ? "no" : "yes" }
    ' <<< "$listeners")"
fi
check "Порты 5000 и 5432 прослушиваются только на 127.0.0.1" "yes" "$ports_status"

check "Права файла /home/devops/app/.env равны 600" "600" \
"$(stat -c '%a' /home/devops/app/.env 2>/dev/null || true)"

echo "--------------------------------"
echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1

