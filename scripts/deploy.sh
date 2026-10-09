#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]   $desc"
        ((PASS+=1))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL+=1))
    fi
}

# Проверить два условия одновременно в рамках пункта 7.2(г):
# отсутствие общедоступных для записи объектов и права 600 у TLS-ключа.
check_web_permissions() {
    local writable key_mode
    if ! writable="$(sudo find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null)"; then
        echo "error"
        return
    fi
    if ! key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)"; then
        echo "error"
        return
    fi
    if [[ -z "$writable" && "$key_mode" == "600" ]]; then
        echo "ok"
    else
        echo "error"
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" \
    "$(sudo sshd -T | awk '$1=="permitrootlogin" {print $2}')"
check "Парольная аутентификация отключена" "no" \
    "$(sudo sshd -T | awk '$1=="passwordauthentication" {print $2}')"
check "Порт SSH отличается от 22" "yes" \
    "$(sudo sshd -T | awk '$1=="port" {found=1; if ($2==22) bad=1} END {print (found && !bad) ? "yes" : "no"}')"
check "MaxAuthTries равен 3" "3" \
    "$(sudo sshd -T | awk '$1=="maxauthtries" {print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" \
    "$(sudo env LC_ALL=C ufw status | awk '/^Status:/ {print $2}')"
check "Политика входящего трафика — deny" "deny" \
    "$(sudo env LC_ALL=C ufw status verbose | awk '/^Default:/ {print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf " %s (uid=%s)\n", $1, $3}' /etc/passwd

echo "[4] Веб-сервер"
# 7.2(а): служба nginx активна.
check "Служба nginx активна" "active" "$(systemctl is-active nginx 2>/dev/null)"

# 7.2(б): синтаксическая проверка конфигурации nginx.
if sudo nginx -t >/dev/null 2>&1; then
    nginx_syntax="ok"
else
    nginx_syntax="error"
fi
check "Конфигурация nginx синтаксически корректна" "ok" "$nginx_syntax"

# 7.2(в): сертификат действителен ещё не менее 30 дней (2 592 000 секунд).
if openssl x509 -in /etc/ssl/certs/devops.crt -noout -checkend 2592000 >/dev/null 2>&1; then
    cert_valid="ok"
else
    cert_valid="error"
fi
check "Сертификат действителен минимум 30 дней" "ok" "$cert_valid"

# 7.2(г): права каталога и закрытого ключа.
check "Нет общедоступных для записи объектов; TLS-ключ имеет права 600" "ok" \
    "$(check_web_permissions)"

echo "--------------------------------"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
