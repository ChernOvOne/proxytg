#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Installer
# Установка одной командой:
#   bash <(curl -sL https://raw.githubusercontent.com/ChernOvOne/proxy/main/install.sh)
# ============================================================================

set -euo pipefail

REPO_URL="https://github.com/ChernOvOne/proxy.git"
INSTALL_DIR="/opt/mtproxy-manager"
CONFIG_DIR="/etc/mtproxy-manager"
BIN_DIR="/usr/local/bin"

# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR]${NC} Запустите с правами root: sudo bash install.sh"
    exit 1
fi

# --- Баннер ---
clear
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}${BOLD}          MTProxy Manager — Установщик                        ${NC}${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${DIM}Telegram MTProxy: telemt + mtg + Official MTProxy${NC}           ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${DIM}Fake TLS | Domain Support | Ad Tags | Auto-Update${NC}          ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}                                                              ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Проверка существующей установки ---
check_existing() {
    local found_services=()

    if systemctl list-unit-files telemt.service &>/dev/null && systemctl cat telemt &>/dev/null 2>&1; then
        found_services+=("telemt")
    fi
    if systemctl list-unit-files mtg.service &>/dev/null && systemctl cat mtg &>/dev/null 2>&1; then
        found_services+=("mtg")
    fi
    if systemctl list-unit-files mtproxy.service &>/dev/null && systemctl cat mtproxy &>/dev/null 2>&1; then
        found_services+=("mtproxy")
    fi

    if [[ ${#found_services[@]} -gt 0 ]] || [[ -d "$INSTALL_DIR" ]]; then
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}Обнаружена существующая установка!${NC}                          ${YELLOW}║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        if [[ ${#found_services[@]} -gt 0 ]]; then
            echo -e "  Найденные сервисы: ${GREEN}${found_services[*]}${NC}"
        fi
        if [[ -d "$INSTALL_DIR" ]]; then
            local ver
            ver=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")
            echo -e "  Установленная версия: ${GREEN}v${ver}${NC}"
        fi

        echo ""
        echo -e "  1) ${GREEN}Открыть меню управления${NC} (tgp)"
        echo -e "  2) ${YELLOW}Обновить менеджер${NC} (сохранить настройки)"
        echo -e "  3) ${RED}Удалить ВСЁ и установить заново${NC}"
        echo -e "  0) Выход"
        echo ""
        read -rp "$(echo -e "${CYAN}Выберите действие: ${NC}")" choice

        case "$choice" in
            1)
                exec "${INSTALL_DIR}/menu.sh"
                ;;
            2)
                log_info "Обновление менеджера..."
                update_install
                log_success "Обновлено! Запуск: tgp"
                exec "${INSTALL_DIR}/menu.sh"
                ;;
            3)
                echo ""
                echo -e "  ${RED}${BOLD}ВНИМАНИЕ: Все сервисы, конфиги и секреты будут удалены!${NC}"
                read -rp "$(echo -e "${RED}Введите 'YES' для подтверждения: ${NC}")" confirm
                if [[ "$confirm" != "YES" ]]; then
                    log_info "Отменено"
                    exit 0
                fi
                clean_install
                ;;
            0)
                exit 0
                ;;
            *)
                log_warn "Неверный выбор"
                exit 1
                ;;
        esac
        return 0
    fi
    return 1
}

# --- Полная очистка перед установкой ---
clean_install() {
    log_info "Полная очистка..."

    for svc in telemt mtg mtproxy; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}.service"
    done
    systemctl daemon-reload

    rm -f "${BIN_DIR}/telemt"
    rm -f "${BIN_DIR}/mtg"
    rm -f "${BIN_DIR}/mtproto-proxy"
    rm -f "${BIN_DIR}/tgp"
    rm -rf "${INSTALL_DIR}"
    rm -rf "${CONFIG_DIR}"
    rm -rf /opt/MTProxy
    rm -rf /var/lib/mtproxy-manager
    rm -rf /var/log/mtproxy-manager

    log_success "Очистка завершена"
    fresh_install
}

# --- Обновление установки ---
update_install() {
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        cd "${INSTALL_DIR}"
        git stash 2>/dev/null || true
        git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || {
            git fetch origin
            git reset --hard origin/main 2>/dev/null || git reset --hard origin/master
        }
        cd /root
    else
        local tmp_dir
        tmp_dir=$(mktemp -d)
        git clone "${REPO_URL}" "${tmp_dir}/proxy"
        # Сохраняем конфиг
        if [[ -d "${CONFIG_DIR}" ]]; then
            cp -r "${CONFIG_DIR}" "${tmp_dir}/config_backup"
        fi
        rm -rf "${INSTALL_DIR}"
        mv "${tmp_dir}/proxy" "${INSTALL_DIR}"
        if [[ -d "${tmp_dir}/config_backup" ]]; then
            cp -r "${tmp_dir}/config_backup"/* "${CONFIG_DIR}/" 2>/dev/null || true
        fi
        rm -rf "${tmp_dir}"
    fi

    chmod +x "${INSTALL_DIR}/menu.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}"/lib/*.sh 2>/dev/null || true
    ln -sf "${INSTALL_DIR}/menu.sh" "${BIN_DIR}/tgp"
}

# --- Свежая установка ---
fresh_install() {
    log_info "Начинаю установку MTProxy Manager..."

    # Проверка git
    if ! command -v git &>/dev/null; then
        log_info "Установка git..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && apt-get install -y -qq git > /dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q git > /dev/null 2>&1
        else
            log_error "Не удалось установить git. Установите вручную."
            exit 1
        fi
    fi

    # Клонирование
    log_info "Клонирование репозитория..."
    rm -rf "${INSTALL_DIR}"
    git clone "${REPO_URL}" "${INSTALL_DIR}" || {
        log_error "Не удалось клонировать ${REPO_URL}"
        log_info "Попытка скачать архив..."
        mkdir -p "${INSTALL_DIR}"
        curl -sL "https://github.com/ChernOvOne/proxy/archive/main.tar.gz" \
            | tar -xz --strip-components=1 -C "${INSTALL_DIR}" || {
            log_error "Не удалось скачать. Проверьте URL репозитория."
            exit 1
        }
    }

    # Права
    chmod +x "${INSTALL_DIR}/menu.sh"
    chmod +x "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}"/lib/*.sh 2>/dev/null || true

    # Симлинк команды tgp
    ln -sf "${INSTALL_DIR}/menu.sh" "${BIN_DIR}/tgp"

    # Инициализация конфига
    source "${INSTALL_DIR}/lib/common.sh"
    detect_os
    init_config
    install_deps

    # Сохраняем версию менеджера
    local version
    version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "1.0.0")
    save_config_value "MANAGER_VERSION" "$version"

    echo ""
    log_success "MTProxy Manager v${version} установлен!"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Установка завершена!${NC}                                        ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Для управления используйте команду:  ${BOLD}tgp${NC}                   ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    read -rp "$(echo -e "${CYAN}Открыть меню управления сейчас? [Y/n]: ${NC}")" yn
    yn="${yn:-y}"
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        exec "${INSTALL_DIR}/menu.sh"
    fi
}

# --- Точка входа ---
if check_existing; then
    exit 0
fi

fresh_install
