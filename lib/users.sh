#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Multi-User Management (telemt)
# ============================================================================

TELEMT_TOML="${CONFIG_DIR}/telemt/config.toml"

# --- Список пользователей --------------------------------------------------
users_list() {
    load_config
    if [[ "${TELEMT_INSTALLED}" != "true" ]]; then
        echo -e "  ${RED}telemt не установлен${NC}"
        return
    fi

    echo ""
    echo -e "  👥 ${BOLD}ПОЛЬЗОВАТЕЛИ TELEMT${NC}"
    print_separator
    echo ""

    # Из API
    local api_data
    api_data=$(curl -s --max-time 3 http://127.0.0.1:9091/v1/users 2>/dev/null)

    if [[ -n "$api_data" && "$api_data" == *'"ok":true'* ]]; then
        local count
        count=$(echo "$api_data" | jq '.data | length' 2>/dev/null)
        echo -e "  Всего пользователей: ${GREEN}${count}${NC}"
        echo ""

        echo "$api_data" | jq -r '.data[] | @base64' 2>/dev/null | while read -r row; do
            local decoded
            decoded=$(echo "$row" | base64 -d 2>/dev/null)
            local username conns ips traffic ad_tag link
            username=$(echo "$decoded" | jq -r '.username')
            conns=$(echo "$decoded" | jq -r '.current_connections')
            ips=$(echo "$decoded" | jq -r '.active_unique_ips')
            traffic=$(echo "$decoded" | jq -r '.total_octets')
            ad_tag=$(echo "$decoded" | jq -r '.user_ad_tag // "нет"')
            link=$(echo "$decoded" | jq -r '.links.tls[0] // "нет"')

            # Форматируем трафик
            local traffic_fmt
            if [[ "$traffic" -gt 1073741824 ]]; then
                traffic_fmt="$(echo "scale=1; $traffic/1073741824" | bc) GB"
            elif [[ "$traffic" -gt 1048576 ]]; then
                traffic_fmt="$(echo "scale=1; $traffic/1048576" | bc) MB"
            elif [[ "$traffic" -gt 1024 ]]; then
                traffic_fmt="$(echo "scale=1; $traffic/1024" | bc) KB"
            else
                traffic_fmt="${traffic} B"
            fi

            echo -e "  📌 ${BOLD}${username}${NC}"
            echo -e "     Подключений: ${CYAN}${conns}${NC} | IP: ${CYAN}${ips}${NC} | Трафик: ${CYAN}${traffic_fmt}${NC}"
            echo -e "     Ad Tag: ${DIM}${ad_tag}${NC}"
            echo -e "     🔗 ${GREEN}${link/tg:\/\//https:\/\/t.me\/}${NC}"
            echo ""
        done
    else
        # Fallback — из конфига
        echo -e "  ${DIM}API недоступен, чтение из конфига...${NC}"
        echo ""
        grep -A50 '^\[access.users\]' "${TELEMT_TOML}" 2>/dev/null | grep -E '^[a-zA-Z0-9_-]+ =' | while read -r line; do
            local name secret
            name=$(echo "$line" | cut -d'=' -f1 | xargs)
            secret=$(echo "$line" | cut -d'"' -f2)
            local hex_domain
            hex_domain=$(echo -n "${TELEMT_FAKETLS_DOMAIN:-max.ru}" | xxd -p | tr -d '\n')
            local server="${PROXY_DOMAIN:-$(get_external_ip)}"
            echo -e "  📌 ${BOLD}${name}${NC}"
            echo -e "     🔗 https://t.me/proxy?server=${server}&port=${TELEMT_PORT}&secret=ee${secret}${hex_domain}"
            echo ""
        done
    fi
    print_separator
}

# --- Добавить пользователя -------------------------------------------------
users_add() {
    load_config
    if [[ "${TELEMT_INSTALLED}" != "true" ]]; then
        echo -e "  ${RED}telemt не установлен${NC}"
        return
    fi

    echo ""
    echo -e "  ➕ ${BOLD}ДОБАВИТЬ ПОЛЬЗОВАТЕЛЯ${NC}"
    print_separator
    echo ""
    echo -e "  ${DIM}Имя — латиница, цифры, _ (без пробелов)${NC}"
    echo -e "  ${DIM}Примеры: friends, channel_crypto, vip${NC}"
    echo ""

    read -rp "$(echo -e "${CYAN}  Имя пользователя: ${NC}")" username

    # Валидация
    if [[ -z "$username" ]]; then
        log_warn "Имя не может быть пустым"
        return
    fi
    if ! echo "$username" | grep -qE '^[a-zA-Z0-9_-]+$'; then
        log_warn "Только латиница, цифры, _ и -"
        return
    fi

    # Проверка дубликата
    if grep -q "^${username} = " "${TELEMT_TOML}" 2>/dev/null; then
        log_warn "Пользователь '${username}' уже существует"
        return
    fi

    # Генерация секрета
    local secret
    secret=$(openssl rand -hex 16)

    # Ad Tag
    local ad_tag=""
    echo ""
    if confirm "  Настроить Ad Tag для ${username}?"; then
        echo -e "  ${DIM}Получите тег у @MTProxybot в Telegram${NC}"
        read -rp "$(echo -e "${CYAN}  Ad Tag: ${NC}")" ad_tag
    fi

    # Добавляем в [access.users]
    sed -i "/^\[access.users\]/a ${username} = \"${secret}\"" "${TELEMT_TOML}"

    # Добавляем ad_tag если есть
    if [[ -n "$ad_tag" ]]; then
        # Добавляем секцию user_ad_tags если нет
        if ! grep -q '^\[access.user_ad_tags\]' "${TELEMT_TOML}" 2>/dev/null; then
            # Вставляем перед [[upstreams]]
            sed -i "/^\[\[upstreams\]\]/i [access.user_ad_tags]\n${username} = \"${ad_tag}\"\n" "${TELEMT_TOML}"
        else
            sed -i "/^\[access.user_ad_tags\]/a ${username} = \"${ad_tag}\"" "${TELEMT_TOML}"
        fi
    fi

    # Перезапуск
    systemctl restart telemt
    sleep 2

    if is_service_active telemt; then
        local hex_domain
        hex_domain=$(echo -n "${TELEMT_FAKETLS_DOMAIN:-max.ru}" | xxd -p | tr -d '\n')
        local server="${PROXY_DOMAIN:-$(get_external_ip)}"
        local ee_secret="ee${secret}${hex_domain}"

        echo ""
        log_success "Пользователь '${username}' добавлен"
        echo ""
        echo -e "  🔗 Ссылка:"
        echo -e "  ${GREEN}https://t.me/proxy?server=${server}&port=${TELEMT_PORT}&secret=${ee_secret}${NC}"
        echo ""
        if [[ -n "$ad_tag" ]]; then
            echo -e "  📢 Ad Tag: ${YELLOW}${ad_tag}${NC}"
        fi
    else
        log_error "telemt не запустился после добавления пользователя"
        echo -e "  ${DIM}journalctl -u telemt -n 20${NC}"
    fi
}

# --- Удалить пользователя --------------------------------------------------
users_remove() {
    load_config
    if [[ "${TELEMT_INSTALLED}" != "true" ]]; then
        echo -e "  ${RED}telemt не установлен${NC}"
        return
    fi

    echo ""
    echo -e "  ➖ ${BOLD}УДАЛИТЬ ПОЛЬЗОВАТЕЛЯ${NC}"
    print_separator
    echo ""

    # Показываем текущих
    local users_list_raw
    users_list_raw=$(grep -A50 '^\[access.users\]' "${TELEMT_TOML}" 2>/dev/null | grep -E '^[a-zA-Z0-9_-]+ =' | awk -F'=' '{print $1}' | xargs)

    if [[ -z "$users_list_raw" ]]; then
        echo -e "  ${DIM}Нет пользователей${NC}"
        return
    fi

    local i=1
    for u in $users_list_raw; do
        echo -e "  ${i}) ${u}"
        i=$((i+1))
    done
    echo -e "  0) Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите пользователя: ${NC}")" choice

    [[ "$choice" == "0" ]] && return

    local target
    target=$(echo "$users_list_raw" | tr ' ' '\n' | sed -n "${choice}p")

    if [[ -z "$target" ]]; then
        log_warn "Неверный выбор"
        return
    fi

    # Не удаляем последнего
    local count
    count=$(echo "$users_list_raw" | wc -w)
    if [[ "$count" -le 1 ]]; then
        log_warn "Нельзя удалить последнего пользователя"
        return
    fi

    if confirm "  Удалить пользователя '${target}'?"; then
        sed -i "/^${target} = /d" "${TELEMT_TOML}"
        # Удаляем ad_tag если есть
        sed -i "/^\[access.user_ad_tags\]/,/^\[/{/^${target} = /d}" "${TELEMT_TOML}" 2>/dev/null

        systemctl restart telemt
        sleep 2
        is_service_active telemt && log_success "Пользователь '${target}' удалён" \
            || log_error "telemt не запустился"
    fi
}

# --- Меню пользователей ----------------------------------------------------
users_menu() {
    load_config
    if [[ "${TELEMT_INSTALLED}" != "true" ]]; then
        echo ""
        echo -e "  ${RED}⚠ telemt не установлен. Мульти-юзер доступен только для telemt.${NC}"
        return
    fi

    echo ""
    echo -e "  👥 ${BOLD}УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ (telemt)${NC}"
    print_separator
    echo ""
    echo -e "  ${DIM}Каждый пользователь получает свою ссылку, статистику и Ad Tag${NC}"
    echo ""
    echo -e "  1) 📋 Список пользователей и статистика"
    echo -e "  2) ➕ Добавить пользователя"
    echo -e "  3) ➖ Удалить пользователя"
    echo -e "  0) ↩️  Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice

    case "$choice" in
        1) users_list ;;
        2) users_add ;;
        3) users_remove ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
