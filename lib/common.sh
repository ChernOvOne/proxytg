#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Common Functions
# ============================================================================

set -euo pipefail

# --- Пути -------------------------------------------------------------------
INSTALL_DIR="/opt/mtproxy-manager"
CONFIG_DIR="/etc/mtproxy-manager"
CONFIG_FILE="${CONFIG_DIR}/config"
LOG_DIR="/var/log/mtproxy-manager"
DATA_DIR="/var/lib/mtproxy-manager"
BIN_DIR="/usr/local/bin"
REPO_URL="https://github.com/ChernOvOne/proxytg.git"

# --- Цвета и символы --------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

TICK="${GREEN}●${NC}"
CROSS="${RED}○${NC}"
WARN="${YELLOW}▲${NC}"
ARROW="${CYAN}▶${NC}"

# --- Логирование ------------------------------------------------------------
log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_debug()   { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${GRAY}[DEBUG] $*${NC}"; }

# --- Утилиты ----------------------------------------------------------------
die() { log_error "$@"; exit 1; }

confirm() {
    local prompt="${1:-Продолжить?}"
    local default="${2:-n}"
    local yn
    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${YELLOW}${prompt} [Y/n]: ${NC}")" yn
        yn="${yn:-y}"
    else
        read -rp "$(echo -e "${YELLOW}${prompt} [y/N]: ${NC}")" yn
        yn="${yn:-n}"
    fi
    [[ "$yn" =~ ^[Yy]$ ]]
}

press_enter() {
    echo ""
    read -rp "$(echo -e "${DIM}Нажмите Enter для продолжения...${NC}")" _
}

# --- Проверка root -----------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Этот скрипт требует root привилегий. Запустите с sudo."
    fi
}

# --- Определение ОС ---------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-${ID}}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="centos"
        OS_VERSION="$(rpm -q --queryformat '%{VERSION}' centos-release 2>/dev/null || echo unknown)"
        OS_NAME="CentOS ${OS_VERSION}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="Unknown OS"
    fi
    export OS_ID OS_VERSION OS_NAME
}

# --- Установка зависимостей -------------------------------------------------
install_deps() {
    log_info "Установка зависимостей..."
    case "${OS_ID}" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq curl wget jq openssl git net-tools bc > /dev/null 2>&1
            ;;
        centos|rhel|fedora|rocky|alma*)
            yum install -y -q curl wget jq openssl git net-tools bc > /dev/null 2>&1
            ;;
        *)
            log_warn "Неизвестная ОС: ${OS_ID}. Попытка установить зависимости..."
            apt-get update -qq && apt-get install -y -qq curl wget jq openssl git net-tools bc > /dev/null 2>&1 \
                || yum install -y -q curl wget jq openssl git net-tools bc > /dev/null 2>&1 \
                || die "Не удалось установить зависимости"
            ;;
    esac
    log_success "Зависимости установлены"
}

# --- Определение архитектуры ------------------------------------------------
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l)        echo "armv7" ;;
        *)             echo "$arch" ;;
    esac
}

# --- Получение внешнего IP ---------------------------------------------------
get_external_ip() {
    local ip
    ip=$(curl -s -4 --max-time 5 https://api.ipify.org 2>/dev/null) \
        || ip=$(curl -s -4 --max-time 5 https://ifconfig.me 2>/dev/null) \
        || ip=$(curl -s -4 --max-time 5 https://icanhazip.com 2>/dev/null) \
        || ip="не определён"
    echo "$ip"
}

# --- Конфигурация -----------------------------------------------------------
init_config() {
    mkdir -p "${CONFIG_DIR}" "${LOG_DIR}" "${DATA_DIR}"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat > "${CONFIG_FILE}" <<'CONF'
# MTProxy Manager Configuration
# Автосгенерировано при установке

# Домен для ссылок (если пусто — используется IP)
PROXY_DOMAIN=""

# --- telemt ---
TELEMT_INSTALLED="false"
TELEMT_PORT="443"
TELEMT_SECRET=""
TELEMT_FAKETLS_DOMAIN="max.ru"
TELEMT_AD_TAG=""
TELEMT_VERSION=""

# --- mtg ---
MTG_INSTALLED="false"
MTG_PORT="8443"
MTG_SECRET=""
MTG_FAKETLS_DOMAIN="max.ru"
MTG_AD_TAG=""
MTG_VERSION=""

# --- official mtproxy ---
MTPROXY_INSTALLED="false"
MTPROXY_PORT="8888"
MTPROXY_SECRET=""
MTPROXY_AD_TAG=""
MTPROXY_VERSION=""

# --- общие ---
MANAGER_VERSION=""
CONF
        log_info "Конфигурация создана: ${CONFIG_FILE}"
    fi
}

load_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${CONFIG_FILE}"
    fi
}

save_config_value() {
    local key="$1" value="$2"
    if grep -q "^${key}=" "${CONFIG_FILE}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "${CONFIG_FILE}"
    else
        echo "${key}=\"${value}\"" >> "${CONFIG_FILE}"
    fi
}

# --- Генерация секрета ------------------------------------------------------
generate_secret() {
    openssl rand -hex 16
}

generate_ee_secret() {
    local domain="${1:-max.ru}"
    local secret
    secret="$(openssl rand -hex 16)"
    local hex_domain
    hex_domain="$(echo -n "$domain" | xxd -p | tr -d '\n')"
    echo "ee${secret}${hex_domain}"
}

# --- Проверка занятости порта -----------------------------------------------
check_port() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        return 0  # порт занят
    fi
    return 1  # порт свободен
}

get_port_process() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' | head -1
}

# --- Проверка systemd сервиса ----------------------------------------------
is_service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

is_service_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

get_service_uptime() {
    local svc="$1"
    if is_service_active "$svc"; then
        local started
        started=$(systemctl show "$svc" --property=ActiveEnterTimestamp --value 2>/dev/null)
        if [[ -n "$started" && "$started" != "n/a" ]]; then
            local started_epoch now_epoch diff
            started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            diff=$((now_epoch - started_epoch))
            local days=$((diff / 86400))
            local hours=$(( (diff % 86400) / 3600 ))
            local mins=$(( (diff % 3600) / 60 ))
            echo "${days}d ${hours}h ${mins}m"
            return
        fi
    fi
    echo "—"
}

# --- Статус сервиса (красиво) -----------------------------------------------
print_service_status() {
    local name="$1" svc_name="$2" installed="$3" port="$4"
    if [[ "$installed" != "true" ]]; then
        printf "  ${CROSS} %-22s — ${DIM}не установлен${NC}\n" "$name"
        return
    fi
    if is_service_active "$svc_name"; then
        local uptime
        uptime=$(get_service_uptime "$svc_name")
        printf "  ${TICK} %-22s — ${GREEN}активен${NC} | порт %-5s | uptime %s\n" "$name" "$port" "$uptime"
    else
        printf "  ${RED}●${NC} %-22s — ${RED}остановлен${NC} | порт %-5s\n" "$name" "$port"
    fi
}

# --- Хедер ------------------------------------------------------------------
print_header() {
    local version
    version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "dev")
    local ip
    ip=$(get_external_ip)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${BOLD}              MTProxy Manager v${version}                        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${DIM}IP: ${ip} | OS: ${OS_NAME:-unknown}${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# --- Статус всех сервисов ---------------------------------------------------
print_all_status() {
    load_config
    echo ""
    echo -e "  ${BOLD}Статус сервисов:${NC}"
    print_service_status "telemt (Rust)"       "telemt"       "${TELEMT_INSTALLED:-false}"  "${TELEMT_PORT:-443}"
    print_service_status "mtg (Go)"            "mtg"          "${MTG_INSTALLED:-false}"     "${MTG_PORT:-8443}"
    print_service_status "MTProxy (Official)"  "mtproxy"      "${MTPROXY_INSTALLED:-false}" "${MTPROXY_PORT:-8888}"
    echo ""
}

# --- Разделитель ------------------------------------------------------------
print_separator() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# --- Версия из GitHub -------------------------------------------------------
get_latest_github_release() {
    local repo="$1"
    curl -s "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null
}

get_latest_github_tag() {
    local repo="$1"
    curl -s "https://api.github.com/repos/${repo}/tags" 2>/dev/null \
        | jq -r '.[0].name // empty' 2>/dev/null
}
