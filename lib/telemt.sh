#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — telemt (Rust) Module
# Проверено на telemt 3.3.39, Ubuntu 24.04
# ============================================================================

TELEMT_REPO="telemt/telemt"
TELEMT_SERVICE="telemt"
TELEMT_BIN="${BIN_DIR}/telemt"
TELEMT_CONF_DIR="${CONFIG_DIR}/telemt"
TELEMT_TOML="${TELEMT_CONF_DIR}/config.toml"

# --- Генерация toml конфига -------------------------------------------------
telemt_write_config() {
    load_config
    mkdir -p "${TELEMT_CONF_DIR}"

    # Извлекаем чистый 32-hex секрет из ee-секрета
    local raw_secret="${TELEMT_SECRET}"
    if [[ "$raw_secret" == ee* ]]; then
        raw_secret="${raw_secret:2:32}"
    fi

    local ad_tag_line=""
    if [[ -n "${TELEMT_AD_TAG}" ]]; then
        ad_tag_line="ad_tag = \"${TELEMT_AD_TAG}\""
    fi

    cat > "${TELEMT_TOML}" <<EOF
# Telemt MTProxy — managed by MTProxy Manager (tgp)
show_link = ["user"]

[general]
prefer_ipv6 = false
fast_mode = true
use_middle_proxy = false
log_level = "normal"
${ad_tag_line}

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "${PROXY_DOMAIN:-}"
public_port = ${TELEMT_PORT:-443}

[network]
ipv4 = true
ipv6 = true
prefer = 4

[server]
port = ${TELEMT_PORT:-443}
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"

[server.api]
enabled = true
listen = "0.0.0.0:9091"
whitelist = ["127.0.0.0/8"]

[[server.listeners]]
ip = "0.0.0.0"

[[server.listeners]]
ip = "::"

[timeouts]
client_first_byte_idle_secs = 300
client_handshake = 60
client_keepalive = 60
client_ack = 300

[censorship]
tls_domain = "${TELEMT_FAKETLS_DOMAIN:-max.ru}"
mask = true
mask_port = 443
tls_emulation = true
unknown_sni_action = "mask"

[access]
user_max_tcp_conns_global_each = 0
replay_check_len = 65536

[access.users]
user = "${raw_secret}"

[[upstreams]]
type = "direct"
enabled = true
weight = 10
EOF
}

# --- Установка telemt -------------------------------------------------------
telemt_install() {
    load_config
    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        log_warn "telemt уже установлен."
        if confirm "Переустановить с нуля?"; then
            telemt_uninstall
        else
            return 0
        fi
    fi

    log_info "Установка telemt (Rust MTProxy)..."

    local arch
    arch=$(detect_arch)
    local latest_version
    latest_version=$(get_latest_github_release "${TELEMT_REPO}")
    [[ -z "$latest_version" ]] && latest_version=$(get_latest_github_tag "${TELEMT_REPO}")
    [[ -z "$latest_version" ]] && die "Не удалось определить последнюю версию telemt"

    log_info "Версия: ${latest_version}"

    # Формат: telemt-x86_64-linux-gnu.tar.gz / telemt-aarch64-linux-gnu.tar.gz
    local arch_name
    case "$arch" in
        amd64)  arch_name="x86_64" ;;
        arm64)  arch_name="aarch64" ;;
        *)      die "Архитектура ${arch} не поддерживается" ;;
    esac

    local download_url="https://github.com/${TELEMT_REPO}/releases/download/${latest_version}/telemt-${arch_name}-linux-gnu.tar.gz"
    log_info "Скачивание..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    curl -L --fail --progress-bar -o "${tmp_dir}/telemt.tar.gz" "${download_url}" \
        || die "Не удалось скачать telemt"
    tar -xzf "${tmp_dir}/telemt.tar.gz" -C "${tmp_dir}"
    cp "${tmp_dir}/telemt" "${TELEMT_BIN}"
    rm -rf "${tmp_dir}"
    chmod +x "${TELEMT_BIN}"

    # Порт
    local port="${TELEMT_PORT:-443}"
    echo ""
    read -rp "$(echo -e "${CYAN}Порт для telemt [${port}]: ${NC}")" input_port
    port="${input_port:-$port}"

    if check_port "$port"; then
        log_warn "Порт ${port} занят: $(get_port_process "$port")"
        if ! confirm "Всё равно использовать?"; then
            read -rp "$(echo -e "${CYAN}Другой порт: ${NC}")" port
        fi
    fi

    # SNI домен (Fake TLS маскировка)
    local faketls_domain="${TELEMT_FAKETLS_DOMAIN:-max.ru}"
    echo ""
    echo -e "${CYAN}SNI домен для маскировки (DPI видит HTTPS к этому сайту)${NC}"
    echo -e "${DIM}Рекомендуется короткий домен: max.ru, ya.ru, vk.com${NC}"
    read -rp "$(echo -e "${CYAN}SNI домен [${faketls_domain}]: ${NC}")" input_domain
    faketls_domain="${input_domain:-$faketls_domain}"

    # Генерация секрета
    local secret
    secret=$(openssl rand -hex 16)
    local hex_domain
    hex_domain=$(echo -n "$faketls_domain" | xxd -p | tr -d '\n')
    local ee_secret="ee${secret}${hex_domain}"

    # Рекламный тег
    local ad_tag=""
    echo ""
    if confirm "Настроить рекламный тег (Ad Tag)?"; then
        echo -e "${DIM}Получите тег у @MTProxybot в Telegram${NC}"
        read -rp "$(echo -e "${CYAN}Ad Tag: ${NC}")" ad_tag
    fi

    # Сохраняем конфиг
    save_config_value "TELEMT_INSTALLED" "true"
    save_config_value "TELEMT_PORT" "$port"
    save_config_value "TELEMT_SECRET" "$ee_secret"
    save_config_value "TELEMT_FAKETLS_DOMAIN" "$faketls_domain"
    save_config_value "TELEMT_AD_TAG" "$ad_tag"
    save_config_value "TELEMT_VERSION" "$latest_version"

    # Генерируем toml
    load_config
    telemt_write_config

    # Systemd unit
    cat > /etc/systemd/system/telemt.service <<EOF
[Unit]
Description=telemt MTProxy for Telegram
After=network.target

[Service]
Type=simple
ExecStart=${TELEMT_BIN} run --foreground ${TELEMT_TOML}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=telemt

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable telemt
    systemctl start telemt
    sleep 3

    if is_service_active telemt; then
        log_success "telemt установлен и запущен на порту ${port}"
        echo ""
        telemt_show_links
    else
        log_error "telemt не запустился"
        echo -e "${DIM}journalctl -u telemt -n 20${NC}"
    fi
}

# --- Удаление ---------------------------------------------------------------
telemt_uninstall() {
    log_info "Удаление telemt..."
    systemctl stop telemt 2>/dev/null || true
    systemctl disable telemt 2>/dev/null || true
    rm -f /etc/systemd/system/telemt.service
    rm -f "${TELEMT_BIN}"
    rm -rf "${TELEMT_CONF_DIR}"
    systemctl daemon-reload
    save_config_value "TELEMT_INSTALLED" "false"
    save_config_value "TELEMT_VERSION" ""
    save_config_value "TELEMT_SECRET" ""
    log_success "telemt удалён"
}

# --- Управление -------------------------------------------------------------
telemt_start()   { systemctl start telemt   && log_success "telemt запущен"; }
telemt_stop()    { systemctl stop telemt    && log_success "telemt остановлен"; }
telemt_restart() { systemctl restart telemt && log_success "telemt перезапущен"; }

# --- Логи -------------------------------------------------------------------
telemt_logs() {
    echo -e "${BOLD}Логи telemt (последние ${1:-50} строк):${NC}"
    journalctl -u telemt -n "${1:-50}" --no-pager
}

telemt_logs_follow() {
    echo -e "${BOLD}Логи telemt (live, Ctrl+C для выхода):${NC}"
    journalctl -u telemt -f --no-pager
}

# --- Статистика -------------------------------------------------------------
telemt_stats() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} telemt не установлен"; return; }

    echo -e "  ${BOLD}telemt (порт ${TELEMT_PORT}):${NC}"
    if is_service_active telemt; then
        echo -e "    Статус:              ${GREEN}активен${NC}"
        echo -e "    Uptime:              $(get_service_uptime telemt)"
        echo -e "    Версия:              ${TELEMT_VERSION:-unknown}"
        echo -e "    SNI домен:           ${TELEMT_FAKETLS_DOMAIN:-unknown}"
        echo -e "    Активных соединений: $(ss -tnp 2>/dev/null | grep -c ":${TELEMT_PORT} " || echo 0)"

        # API stats если доступен
        local api_stats
        api_stats=$(curl -s --max-time 2 http://127.0.0.1:9091/v1/stats 2>/dev/null)
        if [[ -n "$api_stats" && "$api_stats" != *"not_found"* ]]; then
            echo -e "    API Stats:           ${DIM}${api_stats}${NC}"
        fi
    else
        echo -e "    Статус:              ${RED}остановлен${NC}"
    fi
}

# --- Показать ссылки -------------------------------------------------------
telemt_show_links() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} telemt не установлен"; return; }

    local server="${PROXY_DOMAIN}"
    [[ -z "$server" ]] && server=$(get_external_ip)

    echo -e "  ${BOLD}telemt (порт ${TELEMT_PORT}) | SNI: ${TELEMT_FAKETLS_DOMAIN}${NC}"
    echo -e "  ${GREEN}https://t.me/proxy?server=${server}&port=${TELEMT_PORT}&secret=${TELEMT_SECRET}${NC}"
    echo ""
    echo -e "  ${DIM}tg://proxy?server=${server}&port=${TELEMT_PORT}&secret=${TELEMT_SECRET}${NC}"
}

# --- Обновление -------------------------------------------------------------
telemt_update() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return 1; }

    local current="${TELEMT_VERSION:-unknown}"
    local latest
    latest=$(get_latest_github_release "${TELEMT_REPO}")
    [[ -z "$latest" ]] && latest=$(get_latest_github_tag "${TELEMT_REPO}")

    echo -e "  Текущая: ${YELLOW}${current}${NC} | Последняя: ${GREEN}${latest}${NC}"

    if [[ "$current" == "$latest" ]]; then
        log_info "telemt уже последней версии"
        return 0
    fi

    if confirm "Обновить telemt ${current} -> ${latest}?"; then
        systemctl stop telemt 2>/dev/null || true
        local arch arch_name tmp_dir
        arch=$(detect_arch)
        case "$arch" in amd64) arch_name="x86_64" ;; arm64) arch_name="aarch64" ;; *) arch_name="$arch" ;; esac
        tmp_dir=$(mktemp -d)
        curl -L --fail --progress-bar -o "${tmp_dir}/telemt.tar.gz" \
            "https://github.com/${TELEMT_REPO}/releases/download/${latest}/telemt-${arch_name}-linux-gnu.tar.gz" \
            || die "Не удалось скачать"
        tar -xzf "${tmp_dir}/telemt.tar.gz" -C "${tmp_dir}"
        cp "${tmp_dir}/telemt" "${TELEMT_BIN}"
        rm -rf "${tmp_dir}"
        chmod +x "${TELEMT_BIN}"
        save_config_value "TELEMT_VERSION" "$latest"
        systemctl start telemt
        sleep 2
        is_service_active telemt && log_success "telemt обновлён до ${latest}" \
            || log_error "Не удалось запустить"
    fi
}

telemt_check_update() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && return
    local current="${TELEMT_VERSION:-unknown}"
    local latest
    latest=$(get_latest_github_release "${TELEMT_REPO}" 2>/dev/null)
    [[ -z "$latest" ]] && latest=$(get_latest_github_tag "${TELEMT_REPO}" 2>/dev/null)
    if [[ -n "$latest" && "$current" != "$latest" ]]; then
        echo -e "  ${WARN} telemt: ${YELLOW}${current}${NC} -> ${GREEN}${latest}${NC} (обновление)"
    else
        echo -e "  ${TICK} telemt: ${GREEN}${current}${NC} (актуально)"
    fi
}

# --- Изменение SNI домена ---------------------------------------------------
telemt_set_faketls_domain() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }

    echo -e "  Текущий SNI домен: ${YELLOW}${TELEMT_FAKETLS_DOMAIN:-не установлен}${NC}"
    echo -e "  ${DIM}Рекомендуется короткий домен: max.ru, ya.ru, vk.com${NC}"
    echo ""
    read -rp "$(echo -e "${CYAN}Новый SNI домен: ${NC}")" new_domain
    [[ -z "$new_domain" ]] && { log_warn "Домен не может быть пустым"; return; }

    # Перегенерация ee-секрета с новым доменом
    local raw_secret="${TELEMT_SECRET}"
    [[ "$raw_secret" == ee* ]] && raw_secret="${raw_secret:2:32}"
    local hex_domain
    hex_domain=$(echo -n "$new_domain" | xxd -p | tr -d '\n')
    local new_ee_secret="ee${raw_secret}${hex_domain}"

    save_config_value "TELEMT_FAKETLS_DOMAIN" "$new_domain"
    save_config_value "TELEMT_SECRET" "$new_ee_secret"
    load_config
    telemt_write_config

    systemctl restart telemt
    sleep 2

    if is_service_active telemt; then
        log_success "SNI домен изменён на ${new_domain}"
        echo ""
        log_warn "Ссылки изменились! Удалите старый прокси в Telegram и добавьте заново."
        telemt_show_links
    else
        log_error "telemt не запустился после смены домена"
    fi
}

# --- Изменение Ad Tag -------------------------------------------------------
telemt_set_ad_tag() {
    load_config
    [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }

    echo -e "  Текущий Ad Tag: ${YELLOW}${TELEMT_AD_TAG:-не установлен}${NC}"
    echo ""
    read -rp "$(echo -e "${CYAN}Новый Ad Tag (пусто = удалить): ${NC}")" new_tag

    save_config_value "TELEMT_AD_TAG" "$new_tag"
    load_config
    telemt_write_config

    systemctl restart telemt
    [[ -n "$new_tag" ]] && log_success "Ad Tag обновлён" || log_success "Ad Tag удалён"
}
