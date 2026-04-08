#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Official MTProxy (C) Module
# Проверено на Ubuntu 24.04
# ============================================================================

MTPROXY_REPO="TelegramMessenger/MTProxy"
MTPROXY_SERVICE="mtproxy"
MTPROXY_BIN="${BIN_DIR}/mtproto-proxy"
MTPROXY_BUILD_DIR="/opt/MTProxy"

# --- Установка official MTProxy ---------------------------------------------
mtproxy_install() {
    load_config
    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        log_warn "Официальный MTProxy уже установлен."
        if confirm "Переустановить с нуля?"; then
            mtproxy_uninstall
        else
            return 0
        fi
    fi

    log_info "Установка официального MTProxy (C)..."
    log_warn "Этот прокси НЕ поддерживает Fake TLS и легко блокируется DPI"

    # Зависимости для сборки
    log_info "Установка зависимостей для сборки..."
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        if ! apt-get install -y build-essential libssl-dev zlib1g-dev 2>&1; then
            log_error "Не удалось установить зависимости"
            log_info "Попробуйте вручную: apt install build-essential libssl-dev zlib1g-dev"
            return 1
        fi
    elif command -v yum &>/dev/null; then
        yum groupinstall -y "Development Tools" 2>&1 || true
        if ! yum install -y openssl-devel zlib-devel 2>&1; then
            log_error "Не удалось установить зависимости"
            return 1
        fi
    else
        log_error "Не найден пакетный менеджер (apt/yum)"
        return 1
    fi
    log_success "Зависимости установлены"

    # Клонирование и сборка
    log_info "Клонирование репозитория..."
    rm -rf "${MTPROXY_BUILD_DIR}"
    git clone --depth 1 "https://github.com/${MTPROXY_REPO}.git" "${MTPROXY_BUILD_DIR}" \
        || { log_error "Не удалось клонировать репозиторий"; return 1; }

    log_info "Сборка (может занять 1-2 минуты)..."
    cd "${MTPROXY_BUILD_DIR}" || { log_error "Не удалось перейти в директорию"; return 1; }
    if ! make -j"$(nproc)" 2>&1; then
        log_error "Ошибка сборки MTProxy"
        cd /root || true
        return 1
    fi
    cd /root || true

    cp "${MTPROXY_BUILD_DIR}/objs/bin/mtproto-proxy" "${MTPROXY_BIN}"
    chmod +x "${MTPROXY_BIN}"
    log_success "Сборка завершена"

    # Версия
    local version
    version=$(cd "${MTPROXY_BUILD_DIR}" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

    # Порт
    local port="${MTPROXY_PORT:-8888}"
    echo ""
    read -rp "$(echo -e "${CYAN}Порт для MTProxy [${port}]: ${NC}")" input_port
    port="${input_port:-$port}"

    if check_port "$port"; then
        log_warn "Порт ${port} занят: $(get_port_process "$port")"
        if ! confirm "Использовать?"; then
            read -rp "$(echo -e "${CYAN}Другой порт: ${NC}")" port
        fi
    fi

    # Секрет
    local secret
    secret=$(generate_secret)

    # Ad Tag
    local ad_tag=""
    echo ""
    if confirm "Настроить рекламный тег (Ad Tag)? (можно позже через tgp → 10)"; then
        echo ""
        echo -e "  ${BOLD}Инструкция:${NC}"
        echo -e "  1) Откройте ${CYAN}@MTProxybot${NC} в Telegram"
        echo -e "  2) Отправьте ${CYAN}/newproxy${NC}"
        echo -e "  3) Бот спросит порт — отправьте: ${YELLOW}${port}${NC}"
        echo -e "  4) Бот спросит секрет — отправьте: ${YELLOW}${secret}${NC}"
        echo -e "  5) Выберите канал для рекламы"
        echo -e "  6) Бот выдаст Ad Tag — вставьте его ниже"
        echo ""
        read -rp "$(echo -e "${CYAN}Ad Tag: ${NC}")" ad_tag
    fi

    # Получение конфига Telegram
    mkdir -p "${DATA_DIR}"
    curl -s "https://core.telegram.org/getProxySecret" -o "${DATA_DIR}/proxy-secret" 2>/dev/null || true
    curl -s "https://core.telegram.org/getProxyConfig" -o "${DATA_DIR}/proxy-multi.conf" 2>/dev/null || true

    # Внешний IP для nat-info
    local ext_ip
    ext_ip=$(get_external_ip)

    # Systemd unit
    local ad_tag_arg=""
    [[ -n "$ad_tag" ]] && ad_tag_arg="-P ${ad_tag}"

    cat > /etc/systemd/system/mtproxy.service <<EOF
[Unit]
Description=Official Telegram MTProxy
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'curl -s https://core.telegram.org/getProxySecret -o ${DATA_DIR}/proxy-secret'
ExecStartPre=/bin/sh -c 'curl -s https://core.telegram.org/getProxyConfig -o ${DATA_DIR}/proxy-multi.conf'
ExecStart=${MTPROXY_BIN} -u nobody -p 2398 -H ${port} -S ${secret} --aes-pwd ${DATA_DIR}/proxy-secret ${DATA_DIR}/proxy-multi.conf --nat-info ${ext_ip}:${ext_ip} -M 1 ${ad_tag_arg}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtproxy

[Install]
WantedBy=multi-user.target
EOF

    save_config_value "MTPROXY_INSTALLED" "true"
    save_config_value "MTPROXY_PORT" "$port"
    save_config_value "MTPROXY_SECRET" "$secret"
    save_config_value "MTPROXY_AD_TAG" "$ad_tag"
    save_config_value "MTPROXY_VERSION" "$version"

    systemctl daemon-reload
    systemctl enable mtproxy
    systemctl start mtproxy
    sleep 3

    if is_service_active mtproxy; then
        log_success "MTProxy установлен и запущен на порту ${port}"
        echo ""
        mtproxy_show_links
    else
        log_error "MTProxy не запустился. Логи: journalctl -u mtproxy -n 20"
    fi
}

# --- Удаление ---------------------------------------------------------------
mtproxy_uninstall() {
    log_info "Удаление официального MTProxy..."
    systemctl stop mtproxy 2>/dev/null || true
    systemctl disable mtproxy 2>/dev/null || true
    rm -f /etc/systemd/system/mtproxy.service
    rm -f "${MTPROXY_BIN}"
    rm -rf "${MTPROXY_BUILD_DIR}"
    systemctl daemon-reload
    save_config_value "MTPROXY_INSTALLED" "false"
    save_config_value "MTPROXY_VERSION" ""
    save_config_value "MTPROXY_SECRET" ""
    log_success "MTProxy удалён"
}

# --- Управление -------------------------------------------------------------
mtproxy_start()   { systemctl start mtproxy   && log_success "MTProxy запущен"; }
mtproxy_stop()    { systemctl stop mtproxy    && log_success "MTProxy остановлен"; }
mtproxy_restart() { systemctl restart mtproxy && log_success "MTProxy перезапущен"; }

# --- Логи -------------------------------------------------------------------
mtproxy_logs() {
    echo -e "${BOLD}Логи MTProxy (последние ${1:-50} строк):${NC}"
    journalctl -u mtproxy -n "${1:-50}" --no-pager
}

mtproxy_logs_follow() {
    echo -e "${BOLD}Логи MTProxy (live, Ctrl+C для выхода):${NC}"
    journalctl -u mtproxy -f --no-pager
}

# --- Статистика -------------------------------------------------------------
mtproxy_stats() {
    load_config
    [[ "${MTPROXY_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} MTProxy не установлен"; return; }

    echo -e "  ${BOLD}MTProxy Official (порт ${MTPROXY_PORT}):${NC}"
    if is_service_active mtproxy; then
        echo -e "    Статус:              ${GREEN}активен${NC}"
        echo -e "    Uptime:              $(get_service_uptime mtproxy)"
        echo -e "    Версия:              ${MTPROXY_VERSION:-unknown}"
        echo -e "    Активных соединений: $(ss -tnp 2>/dev/null | grep -c ":${MTPROXY_PORT} " || echo 0)"
    else
        echo -e "    Статус:              ${RED}остановлен${NC}"
    fi
}

# --- Ссылки -----------------------------------------------------------------
mtproxy_show_links() {
    load_config
    [[ "${MTPROXY_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} MTProxy не установлен"; return; }

    local server="${PROXY_DOMAIN}"
    [[ -z "$server" ]] && server=$(get_external_ip)

    local display_secret="dd${MTPROXY_SECRET}"

    echo -e "  ${BOLD}MTProxy Official (порт ${MTPROXY_PORT}):${NC}"
    echo -e "  ${GREEN}https://t.me/proxy?server=${server}&port=${MTPROXY_PORT}&secret=${display_secret}${NC}"
    echo -e "  ${DIM}tg://proxy?server=${server}&port=${MTPROXY_PORT}&secret=${display_secret}${NC}"
    echo ""
    echo -e "  🔑 Секрет для @MTProxybot: ${YELLOW}${MTPROXY_SECRET}${NC}"
    echo -e "  ⚠️  Без Fake TLS — легко детектируется DPI"
}

# --- Обновление -------------------------------------------------------------
mtproxy_update() {
    load_config
    [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return 1; }

    if confirm "Пересобрать MTProxy из последних исходников?"; then
        systemctl stop mtproxy 2>/dev/null || true
        rm -rf "${MTPROXY_BUILD_DIR}"
        git clone --depth 1 "https://github.com/${MTPROXY_REPO}.git" "${MTPROXY_BUILD_DIR}" \
            || { log_error "Не удалось клонировать"; return 1; }
        cd "${MTPROXY_BUILD_DIR}" || return 1
        make -j"$(nproc)" || { log_error "Ошибка сборки"; cd /root; return 1; }
        cp objs/bin/mtproto-proxy "${MTPROXY_BIN}"
        chmod +x "${MTPROXY_BIN}"
        local version
        version=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        save_config_value "MTPROXY_VERSION" "$version"
        cd /root || true
        systemctl start mtproxy
        sleep 2
        is_service_active mtproxy && log_success "MTProxy обновлён (${version})" \
            || log_error "Не удалось запустить"
    fi
}

mtproxy_check_update() {
    load_config
    [[ "${MTPROXY_INSTALLED}" != "true" ]] && return
    local current="${MTPROXY_VERSION:-unknown}"
    local latest
    latest=$(git ls-remote --refs "https://github.com/${MTPROXY_REPO}.git" HEAD 2>/dev/null | awk '{print substr($1,1,7)}')
    if [[ -n "$latest" && "$current" != "$latest" ]]; then
        echo -e "  ${WARN} MTProxy: ${YELLOW}${current}${NC} -> ${GREEN}${latest}${NC} (новые коммиты)"
    else
        echo -e "  ${TICK} MTProxy: ${GREEN}${current}${NC} (актуально)"
    fi
}

# --- Ad Tag -----------------------------------------------------------------
mtproxy_set_ad_tag() {
    load_config
    [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }

    echo -e "  Текущий Ad Tag: ${YELLOW}${MTPROXY_AD_TAG:-не установлен}${NC}"
    echo ""
    echo -e "  ${BOLD}Как получить Ad Tag:${NC}"
    echo -e "  1) Откройте ${CYAN}@MTProxybot${NC} в Telegram"
    echo -e "  2) Отправьте ${CYAN}/newproxy${NC}"
    echo -e "  3) Порт: ${YELLOW}${MTPROXY_PORT}${NC}"
    echo -e "  4) Секрет: ${YELLOW}${MTPROXY_SECRET}${NC}"
    echo ""
    read -rp "$(echo -e "${CYAN}Новый Ad Tag (пусто = удалить): ${NC}")" new_tag
    save_config_value "MTPROXY_AD_TAG" "$new_tag"

    local ext_ip
    ext_ip=$(get_external_ip)
    local ad_tag_arg=""
    [[ -n "$new_tag" ]] && ad_tag_arg="-P ${new_tag}"

    cat > /etc/systemd/system/mtproxy.service <<EOF
[Unit]
Description=Official Telegram MTProxy
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'curl -s https://core.telegram.org/getProxySecret -o ${DATA_DIR}/proxy-secret'
ExecStartPre=/bin/sh -c 'curl -s https://core.telegram.org/getProxyConfig -o ${DATA_DIR}/proxy-multi.conf'
ExecStart=${MTPROXY_BIN} -u nobody -p 2398 -H ${MTPROXY_PORT} -S ${MTPROXY_SECRET} --aes-pwd ${DATA_DIR}/proxy-secret ${DATA_DIR}/proxy-multi.conf --nat-info ${ext_ip}:${ext_ip} -M 1 ${ad_tag_arg}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtproxy

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl restart mtproxy
    log_success "Ad Tag обновлён для MTProxy"
}
