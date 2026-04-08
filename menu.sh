#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Main CLI Menu
# Вызов: tgp
# ============================================================================

set -euo pipefail

# Определяем директорию скрипта
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

# --- Инициализация ----------------------------------------------------------
check_root
detect_os
init_config
load_config

# --- Меню управления сервисом (start/stop/restart) --------------------------
service_control_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  УПРАВЛЕНИЕ СЕРВИСАМИ${NC}"
    print_separator
    echo ""
    print_all_status
    echo ""
    echo -e "  ${BOLD}Запуск / Остановка:${NC}"
    echo -e "   1) Запустить telemt       5) Остановить telemt"
    echo -e "   2) Запустить mtg          6) Остановить mtg"
    echo -e "   3) Запустить MTProxy      7) Остановить MTProxy"
    echo -e "   4) Запустить ВСЕ          8) Остановить ВСЕ"
    echo ""
    echo -e "  ${BOLD}Перезапуск:${NC}"
    echo -e "   9) Перезапустить telemt"
    echo -e "  10) Перезапустить mtg"
    echo -e "  11) Перезапустить MTProxy"
    echo -e "  12) Перезапустить ВСЕ"
    echo ""
    echo -e "   0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите действие: ${NC}")" choice

    case "$choice" in
        1)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_start   || log_warn "telemt не установлен" ;;
        2)  [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_start      || log_warn "mtg не установлен" ;;
        3)  [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_start  || log_warn "MTProxy не установлен" ;;
        4)
            [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_start
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_start
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_start
            ;;
        5)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_stop    || log_warn "telemt не установлен" ;;
        6)  [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_stop       || log_warn "mtg не установлен" ;;
        7)  [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_stop   || log_warn "MTProxy не установлен" ;;
        8)
            [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_stop
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_stop
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_stop
            ;;
        9)  [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_restart  || log_warn "telemt не установлен" ;;
        10) [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_restart     || log_warn "mtg не установлен" ;;
        11) [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_restart || log_warn "MTProxy не установлен" ;;
        12)
            [[ "${TELEMT_INSTALLED}" == "true" ]]  && telemt_restart
            [[ "${MTG_INSTALLED}" == "true" ]]     && mtg_restart
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_restart
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Меню переустановки ----------------------------------------------------
reinstall_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  ПЕРЕУСТАНОВКА СЕРВИСА${NC}"
    print_separator
    echo ""
    echo -e "  1) Переустановить telemt"
    echo -e "  2) Переустановить mtg"
    echo -e "  3) Переустановить MTProxy"
    echo -e "  4) Переустановить ВСЕ"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall
            telemt_install
            ;;
        2)
            [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall
            mtg_install
            ;;
        3)
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall
            mtproxy_install
            ;;
        4)
            if confirm "Переустановить ВСЕ прокси с нуля?"; then
                [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall
                [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall
                [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall
                telemt_install
                mtg_install
                mtproxy_install
            fi
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Меню удаления ----------------------------------------------------------
remove_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  УДАЛЕНИЕ СЕРВИСОВ${NC}"
    print_separator
    echo ""
    echo -e "  1) Удалить telemt"
    echo -e "  2) Удалить mtg"
    echo -e "  3) Удалить MTProxy"
    echo -e "  4) Удалить ВСЕ прокси"
    echo -e "  5) ${RED}Полное удаление (включая менеджер)${NC}"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }
            confirm "Удалить telemt?" && telemt_uninstall
            ;;
        2)
            [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }
            confirm "Удалить mtg?" && mtg_uninstall
            ;;
        3)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }
            confirm "Удалить MTProxy?" && mtproxy_uninstall
            ;;
        4)
            if confirm "Удалить ВСЕ прокси-сервисы?"; then
                [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_uninstall
                [[ "${MTG_INSTALLED}" == "true" ]] && mtg_uninstall
                [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_uninstall
            fi
            ;;
        5) uninstall_all ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Меню изменения секрета -------------------------------------------------
regenerate_secret_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  ПЕРЕГЕНЕРАЦИЯ СЕКРЕТА${NC}"
    print_separator
    echo ""
    echo -e "  ${WARN} После перегенерации все текущие ссылки перестанут работать!"
    echo ""
    echo -e "  1) telemt  — текущий: ${DIM}${TELEMT_SECRET:0:20}...${NC}"
    echo -e "  2) mtg     — текущий: ${DIM}${MTG_SECRET:0:20}...${NC}"
    echo -e "  3) MTProxy — текущий: ${DIM}${MTPROXY_SECRET:0:20}...${NC}"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }
            if confirm "Перегенерировать секрет telemt? Старые ссылки перестанут работать"; then
                local new_secret
                new_secret=$(generate_ee_secret "${TELEMT_FAKETLS_DOMAIN}")
                save_config_value "TELEMT_SECRET" "$new_secret"
                sed -i "s/--secret [^ ]*/--secret ${new_secret}/" /etc/systemd/system/telemt.service
                systemctl daemon-reload
                systemctl restart telemt
                log_success "Секрет telemt обновлён"
                load_config
                telemt_show_links
            fi
            ;;
        2)
            [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }
            if confirm "Перегенерировать секрет mtg?"; then
                local new_secret
                new_secret=$("${MTG_BIN}" generate-secret --hex "${MTG_FAKETLS_DOMAIN}" 2>/dev/null) \
                    || new_secret=$(generate_ee_secret "${MTG_FAKETLS_DOMAIN}")
                save_config_value "MTG_SECRET" "$new_secret"
                sed -i "s/--secret [^ ]*/--secret ${new_secret}/" /etc/systemd/system/mtg.service
                systemctl daemon-reload
                systemctl restart mtg
                log_success "Секрет mtg обновлён"
                load_config
                mtg_show_links
            fi
            ;;
        3)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }
            if confirm "Перегенерировать секрет MTProxy?"; then
                local new_secret
                new_secret=$(generate_secret)
                save_config_value "MTPROXY_SECRET" "$new_secret"
                sed -i "s/-S [a-f0-9]*/-S ${new_secret}/" /etc/systemd/system/mtproxy.service
                systemctl daemon-reload
                systemctl restart mtproxy
                log_success "Секрет MTProxy обновлён"
                load_config
                mtproxy_show_links
            fi
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Главное меню -----------------------------------------------------------
main_menu() {
    while true; do
        clear
        print_header
        print_all_status
        print_separator

        echo -e "  ${BOLD}УСТАНОВКА${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   1) Установить ${GREEN}telemt${NC} (Rust)          ${DIM}— рекомендуется${NC}"
        echo -e "   2) Установить ${BLUE}mtg${NC} (Go)              ${DIM}— альтернатива${NC}"
        echo -e "   3) Установить ${YELLOW}MTProxy${NC} (Official)    ${DIM}— базовый${NC}"
        echo -e "   4) Установить ВСЕ прокси"
        echo ""
        echo -e "  ${BOLD}УПРАВЛЕНИЕ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   5) Запуск / Остановка / Перезапуск"
        echo -e "   6) Переустановить сервис"
        echo -e "   7) Удалить сервис"
        echo ""
        echo -e "  ${BOLD}НАСТРОЙКИ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "   8) Изменить домен (вместо IP)"
        echo -e "   9) Изменить порт"
        echo -e "  10) Рекламный тег (Ad Tag)"
        echo -e "  11) Перегенерировать секрет"
        echo -e "  12) Изменить SNI домен (маскировка трафика)"
        echo ""
        echo -e "  ${BOLD}ИНФОРМАЦИЯ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  13) Показать ссылки для подключения"
        echo -e "  14) Статистика подключений"
        echo -e "  15) Просмотр логов"
        echo -e "  16) Информация о сервере"
        echo ""
        echo -e "  ${BOLD}ОБНОВЛЕНИЯ${NC}"
        echo -e "  ─────────────────────────────────────"
        echo -e "  17) Проверить обновления"
        echo -e "  18) Обновить прокси-сервисы"
        echo -e "  19) Обновить менеджер (self-update)"
        echo ""
        echo -e "   0) Выход"
        echo ""
        print_separator

        read -rp "$(echo -e "${CYAN}  Выберите действие [0-19]: ${NC}")" choice

        case "$choice" in
            # --- Установка ---
            1)  telemt_install;  press_enter ;;
            2)  mtg_install;     press_enter ;;
            3)  mtproxy_install; press_enter ;;
            4)
                log_info "Установка всех прокси-сервисов..."
                telemt_install
                mtg_install
                mtproxy_install
                press_enter
                ;;

            # --- Управление ---
            5)  service_control_menu; press_enter ;;
            6)  reinstall_menu;       press_enter ;;
            7)  remove_menu;          press_enter ;;

            # --- Настройки ---
            8)  domain_set;              press_enter ;;
            9)  change_port;             press_enter ;;
            10) adtag_menu;              press_enter ;;
            11) regenerate_secret_menu;  press_enter ;;
            12) change_sni_domain;       press_enter ;;

            # --- Информация ---
            13) show_all_links;    press_enter ;;
            14) show_stats;        press_enter ;;
            15) show_logs_menu;    press_enter ;;
            16) show_server_info;  press_enter ;;

            # --- Обновления ---
            17) check_all_updates;       press_enter ;;
            18) update_services_menu;    press_enter ;;
            19) manager_self_update;     press_enter ;;

            # --- Выход ---
            0|q|Q|exit)
                echo ""
                echo -e "${GREEN}До свидания!${NC}"
                echo ""
                exit 0
                ;;

            *)
                log_warn "Неверный выбор: ${choice}"
                sleep 1
                ;;
        esac
    done
}

# --- Точка входа ------------------------------------------------------------
main_menu
