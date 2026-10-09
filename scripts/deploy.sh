#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"             # Псевдоним из ~/.ssh/config
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

error() {
    printf 'Ошибка: %s\n' "$1" >&2
    exit 1
}

# 1. Разбор аргумента --dry-run
DRY_RUN=false
if (( $# > 1 )); then
    error 'Использование: scripts/deploy.sh [--dry-run]'
fi
if (( $# == 1 )); then
    [[ "$1" == "--dry-run" ]] || error 'Допустимый аргумент: --dry-run'
    DRY_RUN=true
fi

# 2. Проверки: наличие главной страницы и чистота рабочего дерева Git
REPO_ROOT="$(git rev-parse --show-toplevel)" \
    || error 'Запускайте сценарий из репозитория Git'
LOCAL_DIR="${REPO_ROOT}/site/"

[[ -f "${LOCAL_DIR}index.html" ]] \
    || error "Файл ${LOCAL_DIR}index.html отсутствует; доставка отменена"

GIT_CHANGES="$(git -C "$REPO_ROOT" status --porcelain)" \
    || error 'Не удалось проверить состояние репозитория'
[[ -z "$GIT_CHANGES" ]] \
    || error 'Есть незафиксированные изменения Git (включая индекс и новые файлы); доставка отменена'

COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)" \
    || error 'Не удалось определить хеш коммита'

RSYNC_CMD="${RSYNC_BIN:-rsync}"
if [[ -z "${RSYNC_BIN:-}" ]] && command -v brew >/dev/null 2>&1; then
    BREW_RSYNC_PREFIX="$(brew --prefix rsync 2>/dev/null || true)"
    if [[ -n "$BREW_RSYNC_PREFIX" && -x "$BREW_RSYNC_PREFIX/bin/rsync" ]]; then
        RSYNC_CMD="$BREW_RSYNC_PREFIX/bin/rsync"
    fi
fi
command -v "$RSYNC_CMD" >/dev/null 2>&1 \
    || error 'Утилита rsync не найдена (macOS: brew install rsync)'

# Проверка сертификата требуется только для реальной доставки.
if [[ "$DRY_RUN" == false ]]; then
    [[ -r "$CA_CERT" ]] \
        || error "Сертификат ${CA_CERT} отсутствует или не читается"
fi

# 3. Одно SSH-соединение через rsync, без запроса пароля.
RSYNC_ARGS=(-avz --delete --chmod=D755,F644)
if [[ "$DRY_RUN" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
    echo 'Пробный запуск: изменения на сервере не выполняются.'
fi

if ! "$RSYNC_CMD" "${RSYNC_ARGS[@]}" \
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5' \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    error 'Синхронизация rsync не выполнена (на macOS установите GNU rsync: brew install rsync)'
fi

# 4. В режиме --dry-run проверка доступности не выполняется.
if [[ "$DRY_RUN" == true ]]; then
    echo "План доставки коммита ${COMMIT} выведен успешно."
    exit 0
fi

# 5. Проверка HTTPS с проверкой сертификата (без -k).
if ! curl --fail --silent --show-error \
    --cacert "$CA_CERT" \
    --output /dev/null "$SITE_URL"; then
    error "Ресурс ${SITE_URL} недоступен или проверка TLS не пройдена"
fi

echo "Доставка коммита ${COMMIT} выполнена успешно: ${SITE_URL}"
exit 0
