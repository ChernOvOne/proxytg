#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Main CLI Menu
# Вызов: tgp
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загрузка модулей
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/telemt.sh"
source "${SCRIPT_DIR}/lib/mtg.sh"
source "${SCRIPT_DIR}/lib/mtproxy.sh"
source "${SCRIPT_DIR}/lib/domain.sh"
source "${SCRIPT_DIR}/lib/adtag.sh"
source "${SCRIPT_DIR}/lib/stats.sh"
source "${SCRIPT_DIR}/lib/updater.sh"
source "${SCRIPT_DIR}/lib/users.sh"
source "${SCRIPT_DIR}/lib/system.sh"

check_root
detect_os
init_config
load_config

# --- Управление сервисами --------------------------------------------------
service_control_menu() {
    load_config
    echo ""
    echo -e "  ⚙️  ${BOLD}УПРАВЛЕНИЕ СЕРВИСАМИ${NC}"
    print_separator
    print_all_status
    echo ""
    echo -e "  ${BOLD}▶️  Запуск:${NC}                    ${BOLD}⏹  Остановка:${NC}"
    echo -e "   1) Запустить telemt         5) Остановить telemt"
    echo -e "   2) Запустить mtg            6) Остановить mtg"
    echo -e "   3) Запустить MTProxy        7) Остановить MTProxy"
    echo -e "   4) Запустить ВСЕ            8) Остановить ВСЕ"
    echo ""
    echo -e "  ${BOLD}🔄 Перезапуск:${NC}"
    echo -e "   9) Перезапустить telemt"
    echo -e "  10) Перезапустить mtg"
    echo -e "  11) Перезапустить MTProxy"
    echo -e "  12) Перезапустить ВСЕ"
    echo ""
    echo -e "   0) ↩️  Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice

    case "$choice" in
        1)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_start   || log_warn "Не установлен" ;;
        2)  [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_start      || log_warn "Не установлен" ;;
        3)  [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_start  || log_warn "Не установлен" ;;
        4)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_start
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_start
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_start ;;
        5)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_stop    || log_warn "Не установлен" ;;
        6)  [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_stop       || log_warn "Не установлен" ;;
        7)  [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_stop   || log_warn "Не установлен" ;;
        8)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_stop
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_stop
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_stop ;;
        9)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_restart  || log_warn "Не установлен" ;;
        10) [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_restart     || log_warn "Не установлен" ;;
        11) [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_restart || log_warn "Не установлен" ;;
        12) [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_restart
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_restart
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_restart ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Переустановка ----------------------------------------------------------
reinstall_menu() {
    load_config
    echo ""
    echo -e "  🔄 ${BOLD}ПЕРЕУСТАНОВКА${NC}"
    print_separator
    echo ""
    echo -e "  1) telemt    2) mtg    3) MTProxy    4) ВСЕ    0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice
    case "$choice" in
        1) [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall; telemt_install ;;
        2) [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall; mtg_install ;;
        3) [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall; mtproxy_install ;;
        4) if confirm "Переустановить ВСЕ с нуля?"; then
               [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall
               [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall
               [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall
               telemt_install; mtg_install; mtproxy_install
           fi ;;
        0) return ;; *) log_warn "Неверный выбор" ;;
    esac
}

# --- Удаление ---------------------------------------------------------------
remove_menu() {
    load_config
    echo ""
    echo -e "  🗑  ${BOLD}УДАЛЕНИЕ${NC}"
    print_separator
    echo ""
    echo -e "  1) telemt     2) mtg     3) MTProxy"
    echo -e "  4) Все прокси"
    echo -e "  5) ${RED}Полное удаление (включая менеджер)${NC}"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice
    case "$choice" in
        1) confirm "Удалить telemt?" && telemt_uninstall ;;
        2) confirm "Удалить mtg?" && mtg_uninstall ;;
        3) confirm "Удалить MTProxy?" && mtproxy_uninstall ;;
        4) if confirm "Удалить ВСЕ прокси?"; then
               [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall
               [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall
               [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall
           fi ;;
        5) uninstall_all ;;
        0) return ;; *) log_warn "Неверный выбор" ;;
    esac
}

# --- Перегенерация секрета --------------------------------------------------
regenerate_secret_menu() {
    load_config
    echo ""
    echo -e "  🔑 ${BOLD}ПЕРЕГЕНЕРАЦИЯ СЕКРЕТА${NC}"
    print_separator
    echo ""
    echo -e "  ⚠️  После смены все текущие ссылки перестанут работать!"
    echo -e "  ${DIM}Пользователям нужно будет удалить старый прокси и добавить новый${NC}"
    echo ""
    echo -e "  1) telemt    2) mtg    3) MTProxy    0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice
    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "Не установлен"; return; }
            if confirm "Перегенерировать секрет telemt?"; then
                local new_secret hex_domain
                new_secret=$(openssl rand -hex 16)
                hex_domain=$(echo -n "${TELEMT_FAKETLS_DOMAIN}" | xxd -p | tr -d '\n')
                save_config_value "TELEMT_SECRET" "ee${new_secret}${hex_domain}"
                load_config; telemt_write_config
                systemctl restart telemt
                log_success "Секрет обновлён"; load_config; telemt_show_links
            fi ;;
        2)
            [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "Не установлен"; return; }
            if confirm "Перегенерировать секрет mtg?"; then
                local new_secret
                new_secret=$("${MTG_BIN}" generate-secret --hex "${MTG_FAKETLS_DOMAIN}" 2>/dev/null) \
                    || new_secret=$(generate_ee_secret "${MTG_FAKETLS_DOMAIN}")
                save_config_value "MTG_SECRET" "$new_secret"
                load_config; mtg_write_config
                systemctl restart mtg
                log_success "Секрет обновлён"; load_config; mtg_show_links
            fi ;;
        3)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "Не установлен"; return; }
            if confirm "Перегенерировать секрет MTProxy?"; then
                local new_secret
                new_secret=$(generate_secret)
                save_config_value "MTPROXY_SECRET" "$new_secret"
                sed -i "s/-S [a-f0-9]*/-S ${new_secret}/" /etc/systemd/system/mtproxy.service
                systemctl daemon-reload; systemctl restart mtproxy
                log_success "Секрет обновлён"; load_config; mtproxy_show_links
            fi ;;
        0) return ;; *) log_warn "Неверный выбор" ;;
    esac
}

# --- Главное меню -----------------------------------------------------------
main_menu() {
    while true; do
        clear
        load_config

        local version
        version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "dev")
        local ip
        ip=$(get_external_ip)
        local domain_display="${PROXY_DOMAIN:-${ip}}"

        # Хедер
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  🔧 ${BOLD}MTProxy Manager${NC} v${version}                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  🌐 ${domain_display} | 🖥  ${OS_NAME:-Linux}            ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

        # Статус
        echo ""
        echo -e "  📊 ${BOLD}Статус сервисов:${NC}"
        print_service_status "telemt (Rust)"       "telemt"  "${TELEMT_INSTALLED:-false}"  "${TELEMT_PORT:-443}"
        print_service_status "mtg (Go)"            "mtg"     "${MTG_INSTALLED:-false}"     "${MTG_PORT:-8443}"
        print_service_status "MTProxy (Official)"  "mtproxy" "${MTPROXY_INSTALLED:-false}" "${MTPROXY_PORT:-8888}"

        echo ""
        print_separator
        echo ""
        echo -e "  📦 ${BOLD}УСТАНОВКА${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   1) 🚀 telemt (Rust)             ${DIM}— рекомендуется${NC}"
        echo -e "   2) 🔷 mtg (Go)                  ${DIM}— альтернатива${NC}"
        echo -e "   3) 📡 MTProxy (Official)         ${DIM}— базовый${NC}"
        echo -e "   4) ⚡ Установить ВСЕ"
        echo ""
        echo -e "  ⚙️  ${BOLD}УПРАВЛЕНИЕ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   5) ▶️  Запуск / Остановка / Перезапуск"
        echo -e "   6) 🔄 Переустановить сервис"
        echo -e "   7) 🗑  Удалить сервис"
        echo ""
        echo -e "  🎯 ${BOLD}НАСТРОЙКИ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   8) 🌍 Домен (вместо IP)"
        echo -e "   9) 🔌 Порт"
        echo -e "  10) 📢 Рекламный тег (Ad Tag)"
        echo -e "  11) 🔑 Перегенерировать секрет"
        echo -e "  12) 🎭 SNI домен (маскировка трафика)"
        echo ""
        echo -e "  👥 ${BOLD}ПОЛЬЗОВАТЕЛИ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  13) 👥 Управление пользователями (telemt)"
        echo ""
        echo -e "  📊 ${BOLD}МОНИТОРИНГ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  14) 🔗 Ссылки для подключения"
        echo -e "  15) 📈 Статистика подключений"
        echo -e "  16) 📜 Логи"
        echo -e "  17) 🖥  Инфо о сервере"
        echo ""
        echo -e "  🔄 ${BOLD}ОБНОВЛЕНИЯ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  18) 🔍 Проверить обновления"
        echo -e "  19) ⬆️  Обновить сервисы"
        echo -e "  20) 🔧 Обновить менеджер (self-update)"
        echo ""
        echo -e "  🛡 ${BOLD}СИСТЕМА${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  21) 🛡 Firewall / BBR / Backup"
        echo ""
        echo -e "   0) 🚪 Выход"
        echo ""
        print_separator

        read -rp "$(echo -e "${CYAN}  Выберите [0-21]: ${NC}")" choice

        case "$choice" in
            1)  telemt_install;  press_enter ;;
            2)  mtg_install;     press_enter ;;
            3)  mtproxy_install; press_enter ;;
            4)  telemt_install; mtg_install; mtproxy_install; press_enter ;;
            5)  service_control_menu; press_enter ;;
            6)  reinstall_menu;       press_enter ;;
            7)  remove_menu;          press_enter ;;
            8)  domain_set;              press_enter ;;
            9)  change_port;             press_enter ;;
            10) adtag_menu;              press_enter ;;
            11) regenerate_secret_menu;  press_enter ;;
            12) change_sni_domain;       press_enter ;;
            13) users_menu;              press_enter ;;
            14) show_all_links;    press_enter ;;
            15) show_stats;        press_enter ;;
            16) show_logs_menu;    press_enter ;;
            17) show_server_info;  press_enter ;;
            18) check_all_updates;       press_enter ;;
            19) update_services_menu;    press_enter ;;
            20) manager_self_update;     press_enter ;;
            21) system_menu;             press_enter ;;
            0|q|Q|exit)
                echo ""
                echo -e "  👋 ${GREEN}До свидания!${NC}"
                echo ""
                exit 0 ;;
            *) log_warn "Неверный выбор: ${choice}"; sleep 1 ;;
        esac
    done
}

main_menu
