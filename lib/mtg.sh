#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — mtg (Go) Module
# Проверено на mtg 2.2.8, Ubuntu 24.04
# ============================================================================

MTG_REPO="9seconds/mtg"
MTG_SERVICE="mtg"
MTG_BIN="${BIN_DIR}/mtg"
MTG_CONF_DIR="${CONFIG_DIR}/mtg"
MTG_TOML="${MTG_CONF_DIR}/config.toml"

# --- Генерация toml конфига -------------------------------------------------
mtg_write_config() {
    load_config
    mkdir -p "${MTG_CONF_DIR}"

    cat > "${MTG_TOML}" <<EOF
# mtg MTProxy — managed by MTProxy Manager (tgp)
debug = false
secret = "${MTG_SECRET}"
bind-to = "0.0.0.0:${MTG_PORT:-8443}"
prefer-ip = "prefer-ipv4"
concurrency = 8192
tolerate-time-skewness = "24h"

[network]
dns = "https://1.1.1.1"

[network.timeout]
tcp = "5s"
http = "10s"
idle = "5m"

[defense.anti-replay]
enabled = true
max-size = "1mib"

[stats.prometheus]
enabled = true
bind-to = "127.0.0.1:3129"
http-path = "/"
metric-prefix = "mtg"
EOF
}

# --- Установка mtg ----------------------------------------------------------
mtg_install() {
    load_config
    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        log_warn "mtg уже установлен."
        if confirm "Переустановить с нуля?"; then
            mtg_uninstall
        else
            return 0
        fi
    fi

    log_info "Установка mtg (Go MTProxy)..."

    local arch
    arch=$(detect_arch)
    local latest_version
    latest_version=$(get_latest_github_release "${MTG_REPO}")
    [[ -z "$latest_version" ]] && latest_version=$(get_latest_github_tag "${MTG_REPO}")
    [[ -z "$latest_version" ]] && die "Не удалось определить версию mtg"

    log_info "Версия: ${latest_version}"

    # Формат: mtg-2.2.8-linux-amd64.tar.gz
    local version_num="${latest_version#v}"
    local download_url="https://github.com/${MTG_REPO}/releases/download/${latest_version}/mtg-${version_num}-linux-${arch}.tar.gz"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    log_info "Скачивание..."
    curl -L --fail --progress-bar -o "${tmp_dir}/mtg.tar.gz" "${download_url}" \
        || die "Не удалось скачать mtg"
    tar -xzf "${tmp_dir}/mtg.tar.gz" -C "${tmp_dir}"
    local found_bin
    found_bin=$(find "${tmp_dir}" -name "mtg" -type f -executable 2>/dev/null | head -1)
    [[ -z "$found_bin" ]] && found_bin=$(find "${tmp_dir}" -name "mtg" -type f 2>/dev/null | head -1)
    [[ -n "$found_bin" ]] && cp "$found_bin" "${MTG_BIN}" || die "Бинарник mtg не найден"
    rm -rf "${tmp_dir}"
    chmod +x "${MTG_BIN}"

    # Порт
    local port="${MTG_PORT:-8443}"
    echo ""
    read -rp "$(echo -e "${CYAN}Порт для mtg [${port}]: ${NC}")" input_port
    port="${input_port:-$port}"

    if check_port "$port"; then
        log_warn "Порт ${port} занят: $(get_port_process "$port")"
        if ! confirm "Использовать?"; then
            read -rp "$(echo -e "${CYAN}Другой порт: ${NC}")" port
        fi
    fi

    # SNI домен
    local faketls_domain="${MTG_FAKETLS_DOMAIN:-max.ru}"
    echo ""
    echo -e "${CYAN}SNI домен для маскировки (DPI видит HTTPS к этому сайту)${NC}"
    echo -e "${DIM}Рекомендуется короткий домен: max.ru, ya.ru, vk.com${NC}"
    read -rp "$(echo -e "${CYAN}SNI домен [${faketls_domain}]: ${NC}")" input_domain
    faketls_domain="${input_domain:-$faketls_domain}"

    # Генерация секрета
    local secret
    secret=$("${MTG_BIN}" generate-secret --hex "${faketls_domain}" 2>/dev/null) \
        || secret=$(generate_ee_secret "$faketls_domain")

    # Рекламный тег (mtg не поддерживает ad-tag в toml — игнорируем)
    local ad_tag=""
    echo ""
    echo -e "${DIM}Примечание: mtg v2 не поддерживает рекламные теги${NC}"

    # Сохранение
    save_config_value "MTG_INSTALLED" "true"
    save_config_value "MTG_PORT" "$port"
    save_config_value "MTG_SECRET" "$secret"
    save_config_value "MTG_FAKETLS_DOMAIN" "$faketls_domain"
    save_config_value "MTG_AD_TAG" "$ad_tag"
    save_config_value "MTG_VERSION" "$latest_version"

    load_config
    mtg_write_config

    # Systemd unit
    cat > /etc/systemd/system/mtg.service <<EOF
[Unit]
Description=mtg MTProxy for Telegram
After=network.target

[Service]
Type=simple
ExecStart=${MTG_BIN} run ${MTG_TOML}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=mtg

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable mtg
    systemctl start mtg
    sleep 3

    if is_service_active mtg; then
        log_success "mtg установлен и запущен на порту ${port}"
        echo ""
        mtg_show_links
    else
        log_error "mtg не запустился. journalctl -u mtg -n 20"
    fi
}

# --- Удаление ---------------------------------------------------------------
mtg_uninstall() {
    log_info "Удаление mtg..."
    systemctl stop mtg 2>/dev/null || true
    systemctl disable mtg 2>/dev/null || true
    rm -f /etc/systemd/system/mtg.service
    rm -f "${MTG_BIN}"
    rm -rf "${MTG_CONF_DIR}"
    systemctl daemon-reload
    save_config_value "MTG_INSTALLED" "false"
    save_config_value "MTG_VERSION" ""
    save_config_value "MTG_SECRET" ""
    log_success "mtg удалён"
}

# --- Управление -------------------------------------------------------------
mtg_start()   { systemctl start mtg   && log_success "mtg запущен"; }
mtg_stop()    { systemctl stop mtg    && log_success "mtg остановлен"; }
mtg_restart() { systemctl restart mtg && log_success "mtg перезапущен"; }

# --- Логи -------------------------------------------------------------------
mtg_logs() {
    echo -e "${BOLD}Логи mtg (последние ${1:-50} строк):${NC}"
    journalctl -u mtg -n "${1:-50}" --no-pager
}

mtg_logs_follow() {
    echo -e "${BOLD}Логи mtg (live, Ctrl+C для выхода):${NC}"
    journalctl -u mtg -f --no-pager
}

# --- Статистика -------------------------------------------------------------
mtg_stats() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} mtg не установлен"; return; }

    echo -e "  ${BOLD}mtg (порт ${MTG_PORT}):${NC}"
    if is_service_active mtg; then
        echo -e "    Статус:              ${GREEN}активен${NC}"
        echo -e "    Uptime:              $(get_service_uptime mtg)"
        echo -e "    Версия:              ${MTG_VERSION:-unknown}"
        echo -e "    SNI домен:           ${MTG_FAKETLS_DOMAIN:-unknown}"
        echo -e "    Активных соединений: $(ss -tnp 2>/dev/null | grep -c ":${MTG_PORT} " || echo 0)"

        # Prometheus metrics
        local prom
        prom=$(curl -s --max-time 2 http://127.0.0.1:3129/ 2>/dev/null)
        if [[ -n "$prom" ]]; then
            local active
            active=$(echo "$prom" | grep 'mtg_active_connections ' | awk '{print $2}')
            [[ -n "$active" ]] && echo -e "    Активные (prometheus): ${active}"
        fi
    else
        echo -e "    Статус:              ${RED}остановлен${NC}"
    fi
}

# --- Ссылки -----------------------------------------------------------------
mtg_show_links() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && { echo -e "  ${CROSS} mtg не установлен"; return; }

    local server="${PROXY_DOMAIN}"
    [[ -z "$server" ]] && server=$(get_external_ip)

    echo -e "  ${BOLD}mtg (порт ${MTG_PORT}) | SNI: ${MTG_FAKETLS_DOMAIN}${NC}"
    echo -e "  ${GREEN}https://t.me/proxy?server=${server}&port=${MTG_PORT}&secret=${MTG_SECRET}${NC}"
    echo ""
    echo -e "  ${DIM}tg://proxy?server=${server}&port=${MTG_PORT}&secret=${MTG_SECRET}${NC}"
}

# --- Обновление -------------------------------------------------------------
mtg_update() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return 1; }

    local current="${MTG_VERSION:-unknown}"
    local latest
    latest=$(get_latest_github_release "${MTG_REPO}")
    [[ -z "$latest" ]] && latest=$(get_latest_github_tag "${MTG_REPO}")

    echo -e "  Текущая: ${YELLOW}${current}${NC} | Последняя: ${GREEN}${latest}${NC}"

    [[ "$current" == "$latest" ]] && { log_info "mtg актуален"; return 0; }

    if confirm "Обновить mtg ${current} -> ${latest}?"; then
        systemctl stop mtg 2>/dev/null || true
        local arch version_num tmp_dir
        arch=$(detect_arch)
        version_num="${latest#v}"
        tmp_dir=$(mktemp -d)
        curl -L --fail --progress-bar -o "${tmp_dir}/mtg.tar.gz" \
            "https://github.com/${MTG_REPO}/releases/download/${latest}/mtg-${version_num}-linux-${arch}.tar.gz" \
            || die "Не удалось скачать"
        tar -xzf "${tmp_dir}/mtg.tar.gz" -C "${tmp_dir}"
        local found_bin
        found_bin=$(find "${tmp_dir}" -name "mtg" -type f -executable 2>/dev/null | head -1)
        [[ -n "$found_bin" ]] && cp "$found_bin" "${MTG_BIN}"
        rm -rf "${tmp_dir}"
        chmod +x "${MTG_BIN}"
        save_config_value "MTG_VERSION" "$latest"
        systemctl start mtg
        sleep 2
        is_service_active mtg && log_success "mtg обновлён до ${latest}" \
            || log_error "Не удалось запустить"
    fi
}

mtg_check_update() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && return
    local current="${MTG_VERSION:-unknown}"
    local latest
    latest=$(get_latest_github_release "${MTG_REPO}" 2>/dev/null)
    [[ -z "$latest" ]] && latest=$(get_latest_github_tag "${MTG_REPO}" 2>/dev/null)
    if [[ -n "$latest" && "$current" != "$latest" ]]; then
        echo -e "  ${WARN} mtg: ${YELLOW}${current}${NC} -> ${GREEN}${latest}${NC} (обновление)"
    else
        echo -e "  ${TICK} mtg: ${GREEN}${current}${NC} (актуально)"
    fi
}

# --- Изменение SNI домена ---------------------------------------------------
mtg_set_faketls_domain() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }

    echo -e "  Текущий SNI домен: ${YELLOW}${MTG_FAKETLS_DOMAIN:-не установлен}${NC}"
    echo -e "  ${DIM}Рекомендуется короткий домен: max.ru, ya.ru, vk.com${NC}"
    echo ""
    read -rp "$(echo -e "${CYAN}Новый SNI домен: ${NC}")" new_domain
    [[ -z "$new_domain" ]] && { log_warn "Домен не может быть пустым"; return; }

    # Перегенерация секрета
    local new_secret
    new_secret=$("${MTG_BIN}" generate-secret --hex "${new_domain}" 2>/dev/null) \
        || new_secret=$(generate_ee_secret "$new_domain")

    save_config_value "MTG_FAKETLS_DOMAIN" "$new_domain"
    save_config_value "MTG_SECRET" "$new_secret"
    load_config
    mtg_write_config

    systemctl restart mtg
    sleep 2

    if is_service_active mtg; then
        log_success "SNI домен изменён на ${new_domain}"
        echo ""
        log_warn "Ссылки изменились! Удалите старый прокси в Telegram и добавьте заново."
        mtg_show_links
    else
        log_error "mtg не запустился"
    fi
}

# --- Изменение Ad Tag -------------------------------------------------------
mtg_set_ad_tag() {
    load_config
    [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }
    echo -e "  ${DIM}mtg v2 не поддерживает рекламные теги${NC}"
}
