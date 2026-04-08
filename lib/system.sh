#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — System Utilities (Firewall, BBR, Backup/Restore)
# ============================================================================

# --- Firewall ---------------------------------------------------------------
firewall_menu() {
    load_config
    echo ""
    echo -e "  🔥 ${BOLD}FIREWALL${NC}"
    print_separator
    echo ""

    # Определяем тип файрвола
    local fw_type="none"
    if command -v ufw &>/dev/null; then
        fw_type="ufw"
        local ufw_status
        ufw_status=$(ufw status 2>/dev/null | head -1)
        echo -e "  Тип: ${CYAN}UFW${NC} | ${ufw_status}"
    elif command -v firewall-cmd &>/dev/null; then
        fw_type="firewalld"
        echo -e "  Тип: ${CYAN}firewalld${NC}"
    else
        echo -e "  Тип: ${CYAN}iptables${NC} (без менеджера)"
    fi

    # Текущие порты
    echo ""
    echo -e "  Порты прокси:"
    [[ "${TELEMT_INSTALLED}" == "true" ]]  && echo -e "    telemt:  ${YELLOW}${TELEMT_PORT:-443}${NC}"
    [[ "${MTG_INSTALLED}" == "true" ]]     && echo -e "    mtg:     ${YELLOW}${MTG_PORT:-8443}${NC}"
    [[ "${MTPROXY_INSTALLED}" == "true" ]] && echo -e "    MTProxy: ${YELLOW}${MTPROXY_PORT:-8888}${NC}"
    echo ""

    echo -e "  1) 🔓 Открыть порты всех прокси"
    echo -e "  2) 🔒 Показать текущие правила"
    echo -e "  0) ↩️  Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice

    case "$choice" in
        1) firewall_open_ports ;;
        2) firewall_show ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

firewall_open_ports() {
    load_config
    local ports=()
    [[ "${TELEMT_INSTALLED}" == "true" ]]  && ports+=("${TELEMT_PORT:-443}")
    [[ "${MTG_INSTALLED}" == "true" ]]     && ports+=("${MTG_PORT:-8443}")
    [[ "${MTPROXY_INSTALLED}" == "true" ]] && ports+=("${MTPROXY_PORT:-8888}")

    if [[ ${#ports[@]} -eq 0 ]]; then
        log_warn "Нет установленных прокси"
        return
    fi

    if command -v ufw &>/dev/null; then
        for p in "${ports[@]}"; do
            ufw allow "$p"/tcp comment "MTProxy" 2>/dev/null
            echo -e "  ✅ UFW: порт ${p}/tcp открыт"
        done
        ufw --force enable 2>/dev/null
    elif command -v firewall-cmd &>/dev/null; then
        for p in "${ports[@]}"; do
            firewall-cmd --permanent --add-port="${p}/tcp" 2>/dev/null
            echo -e "  ✅ firewalld: порт ${p}/tcp открыт"
        done
        firewall-cmd --reload 2>/dev/null
    else
        for p in "${ports[@]}"; do
            iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
                || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT
            echo -e "  ✅ iptables: порт ${p}/tcp открыт"
        done
    fi

    log_success "Порты открыты"
}

firewall_show() {
    echo ""
    if command -v ufw &>/dev/null; then
        ufw status verbose 2>/dev/null
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --list-all 2>/dev/null
    else
        iptables -L -n --line-numbers 2>/dev/null | head -30
    fi
}

# --- TCP BBR ----------------------------------------------------------------
bbr_menu() {
    echo ""
    echo -e "  🚄 ${BOLD}TCP BBR (ускорение сети)${NC}"
    print_separator
    echo ""

    # Проверяем текущее состояние
    local current_cc
    current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local bbr_available
    bbr_available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null)

    echo -e "  Текущий алгоритм:  ${YELLOW}${current_cc}${NC}"
    echo -e "  Доступные:         ${DIM}${bbr_available}${NC}"
    echo ""

    if [[ "$current_cc" == "bbr" ]]; then
        echo -e "  ✅ ${GREEN}BBR уже включён${NC}"
        return
    fi

    echo -e "  ${DIM}BBR — алгоритм управления TCP от Google.${NC}"
    echo -e "  ${DIM}Улучшает скорость на нестабильных каналах.${NC}"
    echo ""

    if confirm "  Включить BBR?"; then
        # Проверяем доступность модуля
        if ! echo "$bbr_available" | grep -q "bbr"; then
            modprobe tcp_bbr 2>/dev/null || true
        fi

        # Включаем BBR
        sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
        sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1

        # Сохраняем на постоянку
        if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf 2>/dev/null; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        fi
        if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        fi

        local new_cc
        new_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
        if [[ "$new_cc" == "bbr" ]]; then
            log_success "BBR включён"
        else
            log_error "Не удалось включить BBR"
        fi
    fi
}

# --- Backup -----------------------------------------------------------------
backup_create() {
    load_config
    local backup_dir="/root/mtproxy-backup"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/backup_${timestamp}.tar.gz"

    mkdir -p "${backup_dir}"

    echo ""
    echo -e "  💾 ${BOLD}СОЗДАНИЕ BACKUP${NC}"
    print_separator
    echo ""

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Копируем конфиги
    cp -r "${CONFIG_DIR}" "${tmp_dir}/config" 2>/dev/null || true
    cp -r "${CONFIG_DIR}/telemt" "${tmp_dir}/telemt" 2>/dev/null || true
    cp -r "${CONFIG_DIR}/mtg" "${tmp_dir}/mtg" 2>/dev/null || true

    # Копируем systemd units
    mkdir -p "${tmp_dir}/systemd"
    cp /etc/systemd/system/telemt.service "${tmp_dir}/systemd/" 2>/dev/null || true
    cp /etc/systemd/system/mtg.service "${tmp_dir}/systemd/" 2>/dev/null || true
    cp /etc/systemd/system/mtproxy.service "${tmp_dir}/systemd/" 2>/dev/null || true

    # Версия
    echo "${MANAGER_VERSION:-1.0.0}" > "${tmp_dir}/version"
    date > "${tmp_dir}/created"

    tar -czf "${backup_file}" -C "${tmp_dir}" .
    rm -rf "${tmp_dir}"

    local size
    size=$(du -h "${backup_file}" | awk '{print $1}')

    echo -e "  ✅ Backup создан: ${GREEN}${backup_file}${NC} (${size})"
    echo ""
    echo -e "  Содержимое:"
    echo -e "    📁 Конфигурация менеджера"
    [[ "${TELEMT_INSTALLED}" == "true" ]]  && echo -e "    📁 telemt конфиг + секреты"
    [[ "${MTG_INSTALLED}" == "true" ]]     && echo -e "    📁 mtg конфиг + секреты"
    [[ "${MTPROXY_INSTALLED}" == "true" ]] && echo -e "    📁 mtproxy systemd unit"
    echo ""
    echo -e "  ${DIM}Для восстановления: tgp -> Система -> Restore${NC}"
}

# --- Restore ----------------------------------------------------------------
backup_restore() {
    local backup_dir="/root/mtproxy-backup"

    echo ""
    echo -e "  📥 ${BOLD}ВОССТАНОВЛЕНИЕ BACKUP${NC}"
    print_separator
    echo ""

    if [[ ! -d "$backup_dir" ]]; then
        echo -e "  ${DIM}Нет бэкапов в ${backup_dir}${NC}"
        return
    fi

    local backups
    backups=$(ls -t "${backup_dir}"/backup_*.tar.gz 2>/dev/null)

    if [[ -z "$backups" ]]; then
        echo -e "  ${DIM}Нет бэкапов${NC}"
        return
    fi

    local i=1
    while IFS= read -r f; do
        local name size date_str
        name=$(basename "$f")
        size=$(du -h "$f" | awk '{print $1}')
        date_str=$(echo "$name" | sed 's/backup_//;s/.tar.gz//' | sed 's/_/ /')
        echo -e "  ${i}) ${name} (${size}) — ${date_str}"
        i=$((i+1))
    done <<< "$backups"
    echo -e "  0) Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите бэкап: ${NC}")" choice
    [[ "$choice" == "0" ]] && return

    local target
    target=$(echo "$backups" | sed -n "${choice}p")

    if [[ -z "$target" || ! -f "$target" ]]; then
        log_warn "Неверный выбор"
        return
    fi

    if confirm "  Восстановить из $(basename "$target")? Текущие конфиги будут заменены"; then
        local tmp_dir
        tmp_dir=$(mktemp -d)
        tar -xzf "$target" -C "${tmp_dir}"

        # Останавливаем сервисы
        systemctl stop telemt mtg mtproxy 2>/dev/null || true

        # Восстанавливаем конфиги
        [[ -d "${tmp_dir}/config" ]] && cp -r "${tmp_dir}/config/"* "${CONFIG_DIR}/" 2>/dev/null
        [[ -d "${tmp_dir}/telemt" ]] && { mkdir -p "${CONFIG_DIR}/telemt"; cp -r "${tmp_dir}/telemt/"* "${CONFIG_DIR}/telemt/" 2>/dev/null; }
        [[ -d "${tmp_dir}/mtg" ]] && { mkdir -p "${CONFIG_DIR}/mtg"; cp -r "${tmp_dir}/mtg/"* "${CONFIG_DIR}/mtg/" 2>/dev/null; }

        # Восстанавливаем systemd units
        [[ -d "${tmp_dir}/systemd" ]] && cp "${tmp_dir}/systemd/"*.service /etc/systemd/system/ 2>/dev/null

        rm -rf "${tmp_dir}"

        systemctl daemon-reload
        load_config

        # Перезапускаем что было установлено
        [[ "${TELEMT_INSTALLED}" == "true" ]] && systemctl start telemt 2>/dev/null
        [[ "${MTG_INSTALLED}" == "true" ]] && systemctl start mtg 2>/dev/null
        [[ "${MTPROXY_INSTALLED}" == "true" ]] && systemctl start mtproxy 2>/dev/null

        log_success "Конфигурация восстановлена из бэкапа"
    fi
}

# --- Системное меню ---------------------------------------------------------
system_menu() {
    echo ""
    echo -e "  🛡 ${BOLD}СИСТЕМА${NC}"
    print_separator
    echo ""
    echo -e "  1) 🔥 Firewall (открыть порты)"
    echo -e "  2) 🚄 TCP BBR (ускорение)"
    echo -e "  3) 💾 Создать Backup"
    echo -e "  4) 📥 Восстановить из Backup"
    echo -e "  0) ↩️  Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice

    case "$choice" in
        1) firewall_menu ;;
        2) bbr_menu ;;
        3) backup_create ;;
        4) backup_restore ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
