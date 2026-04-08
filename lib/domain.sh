#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Domain Management
# ============================================================================

# --- Установка / изменение домена -------------------------------------------
domain_set() {
    load_config

    local current="${PROXY_DOMAIN:-не установлен (используется IP)}"
    local ip
    ip=$(get_external_ip)

    echo ""
    echo -e "${BOLD}Настройка домена для прокси-ссылок${NC}"
    print_separator
    echo -e "  Текущий домен: ${YELLOW}${current}${NC}"
    echo -e "  IP сервера:    ${CYAN}${ip}${NC}"
    echo ""
    echo -e "  ${DIM}Домен используется в ссылках вместо IP адреса.${NC}"
    echo -e "  ${DIM}Убедитесь, что DNS A-запись домена указывает на ${ip}${NC}"
    print_separator
    echo ""

    read -rp "$(echo -e "${CYAN}Введите домен (пусто = использовать IP): ${NC}")" new_domain

    if [[ -z "$new_domain" ]]; then
        save_config_value "PROXY_DOMAIN" ""
        log_success "Домен удалён. Ссылки будут с IP: ${ip}"
    else
        # Проверка формата домена
        if ! echo "$new_domain" | grep -qP '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$'; then
            log_warn "Формат домена выглядит нестандартно: ${new_domain}"
            if ! confirm "Всё равно использовать?"; then
                return
            fi
        fi

        # Проверка DNS
        echo -e "${DIM}Проверка DNS...${NC}"
        local resolved_ip
        resolved_ip=$(dig +short "$new_domain" A 2>/dev/null | head -1)

        if [[ -z "$resolved_ip" ]]; then
            log_warn "Не удалось разрешить домен ${new_domain}"
            log_warn "Убедитесь, что A-запись настроена и указывает на ${ip}"
            if ! confirm "Всё равно сохранить домен?"; then
                return
            fi
        elif [[ "$resolved_ip" != "$ip" ]]; then
            log_warn "Домен ${new_domain} указывает на ${resolved_ip}, а не на ${ip}"
            if ! confirm "Всё равно сохранить?"; then
                return
            fi
        else
            log_success "DNS проверка пройдена: ${new_domain} -> ${resolved_ip}"
        fi

        save_config_value "PROXY_DOMAIN" "$new_domain"
        log_success "Домен установлен: ${new_domain}"
    fi

    echo ""
    echo -e "${BOLD}Обновлённые ссылки:${NC}"
    print_separator
    show_all_links
}

# --- Показать все ссылки ----------------------------------------------------
show_all_links() {
    load_config

    local server="${PROXY_DOMAIN}"
    [[ -z "$server" ]] && server=$(get_external_ip)

    echo ""
    echo -e "${BOLD}  ССЫЛКИ ДЛЯ ПОДКЛЮЧЕНИЯ${NC}"
    echo -e "  ${DIM}Сервер: ${server}${NC}"
    print_separator

    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        echo ""
        telemt_show_links
    fi

    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        echo ""
        mtg_show_links
    fi

    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        echo ""
        mtproxy_show_links
    fi

    local any_installed="false"
    [[ "${TELEMT_INSTALLED}" == "true" ]] && any_installed="true"
    [[ "${MTG_INSTALLED}" == "true" ]] && any_installed="true"
    [[ "${MTPROXY_INSTALLED}" == "true" ]] && any_installed="true"

    if [[ "$any_installed" == "false" ]]; then
        echo -e "  ${DIM}Нет установленных прокси${NC}"
    fi

    echo ""
    print_separator
    echo -e "  ${WARN} Клиент Telegram должен быть обновлён:"
    echo -e "     Desktop ${GREEN}6.7.2+${NC} | Android ${GREEN}12.6.4+${NC} | iOS ${YELLOW}ожидается${NC}"
}

# --- Изменение порта --------------------------------------------------------
change_port() {
    load_config

    echo ""
    echo -e "${BOLD}Изменение порта сервиса${NC}"
    print_separator
    echo ""
    echo -e "  1) telemt      — порт ${YELLOW}${TELEMT_PORT:-443}${NC}   [${TELEMT_INSTALLED:-false}]"
    echo -e "  2) mtg         — порт ${YELLOW}${MTG_PORT:-8443}${NC}  [${MTG_INSTALLED:-false}]"
    echo -e "  3) MTProxy     — порт ${YELLOW}${MTPROXY_PORT:-8888}${NC}  [${MTPROXY_INSTALLED:-false}]"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите сервис: ${NC}")" choice

    local svc_name config_key service_unit
    case "$choice" in
        1) svc_name="telemt";  config_key="TELEMT_PORT";  service_unit="telemt" ;;
        2) svc_name="mtg";     config_key="MTG_PORT";     service_unit="mtg" ;;
        3) svc_name="mtproxy"; config_key="MTPROXY_PORT"; service_unit="mtproxy" ;;
        0) return ;;
        *) log_warn "Неверный выбор"; return ;;
    esac

    local current_port
    current_port=$(eval echo "\$${config_key}")
    read -rp "$(echo -e "${CYAN}Новый порт для ${svc_name} [${current_port}]: ${NC}")" new_port
    new_port="${new_port:-$current_port}"

    if [[ "$new_port" == "$current_port" ]]; then
        log_info "Порт не изменён"
        return
    fi

    if check_port "$new_port"; then
        log_warn "Порт ${new_port} занят: $(get_port_process "$new_port")"
        if ! confirm "Всё равно использовать?"; then
            return
        fi
    fi

    save_config_value "$config_key" "$new_port"

    # Пересоздаём конфиг (toml) и перезапускаем
    load_config
    case "$svc_name" in
        telemt) telemt_write_config ;;
        mtg)    mtg_write_config ;;
        mtproxy)
            local unit_file="/etc/systemd/system/mtproxy.service"
            [[ -f "$unit_file" ]] && sed -i "s/-H [0-9]*/-H ${new_port}/" "$unit_file"
            ;;
    esac

    systemctl daemon-reload
    if is_service_active "$service_unit"; then
        systemctl restart "$service_unit"
        log_success "Порт ${svc_name} изменён на ${new_port}, сервис перезапущен"
    else
        log_success "Порт ${svc_name} изменён на ${new_port}"
    fi
}

# --- Изменение SNI домена (выбор сервиса) -----------------------------------
change_sni_domain() {
    load_config

    echo ""
    echo -e "${BOLD}Изменение SNI домена (маскировка трафика)${NC}"
    print_separator
    echo ""
    echo -e "  ${DIM}SNI домен — сайт, под который маскируется трафик.${NC}"
    echo -e "  ${DIM}DPI видит HTTPS к этому домену вместо Telegram.${NC}"
    echo -e "  ${DIM}Рекомендуется короткий домен: max.ru, ya.ru, vk.com${NC}"
    echo ""
    echo -e "  Текущие SNI домены:"
    [[ "${TELEMT_INSTALLED}" == "true" ]] && echo -e "    telemt:  ${YELLOW}${TELEMT_FAKETLS_DOMAIN:-не задан}${NC}"
    [[ "${MTG_INSTALLED}" == "true" ]]    && echo -e "    mtg:     ${YELLOW}${MTG_FAKETLS_DOMAIN:-не задан}${NC}"
    echo ""
    echo -e "  1) Изменить для telemt"
    echo -e "  2) Изменить для mtg"
    echo -e "  3) Установить один SNI для всех"
    echo -e "  0) Назад"
    echo ""
    echo -e "  ${DIM}Официальный MTProxy не поддерживает SNI маскировку${NC}"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    case "$choice" in
        1) telemt_set_faketls_domain ;;
        2) mtg_set_faketls_domain ;;
        3)
            echo ""
            echo -e "  ${DIM}Примеры: max.ru, ya.ru, vk.com, ok.ru${NC}"
            read -rp "$(echo -e "${CYAN}SNI домен для всех сервисов: ${NC}")" domain
            [[ -z "$domain" ]] && { log_warn "Домен не может быть пустым"; return; }

            if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
                # Обновляем telemt
                local raw_secret="${TELEMT_SECRET}"
                [[ "$raw_secret" == ee* ]] && raw_secret="${raw_secret:2:32}"
                local hex_domain
                hex_domain=$(echo -n "$domain" | xxd -p | tr -d '\n')
                save_config_value "TELEMT_FAKETLS_DOMAIN" "$domain"
                save_config_value "TELEMT_SECRET" "ee${raw_secret}${hex_domain}"
                load_config
                telemt_write_config
                systemctl restart telemt 2>/dev/null
                log_success "telemt SNI -> ${domain}"
            fi

            if [[ "${MTG_INSTALLED}" == "true" ]]; then
                local new_secret
                new_secret=$("${MTG_BIN}" generate-secret --hex "${domain}" 2>/dev/null) \
                    || new_secret=$(generate_ee_secret "$domain")
                save_config_value "MTG_FAKETLS_DOMAIN" "$domain"
                save_config_value "MTG_SECRET" "$new_secret"
                load_config
                mtg_write_config
                systemctl restart mtg 2>/dev/null
                log_success "mtg SNI -> ${domain}"
            fi

            echo ""
            log_warn "Ссылки изменились! Удалите старые прокси в Telegram и добавьте заново."
            show_all_links
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
