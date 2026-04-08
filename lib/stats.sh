#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Statistics
# ============================================================================

show_stats() {
    load_config

    echo ""
    echo -e "${BOLD}  СТАТИСТИКА ПОДКЛЮЧЕНИЙ${NC}"
    print_separator
    echo ""

    local any="false"

    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        telemt_stats
        echo ""
        any="true"
    fi

    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        mtg_stats
        echo ""
        any="true"
    fi

    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        mtproxy_stats
        echo ""
        any="true"
    fi

    [[ "$any" == "false" ]] && echo -e "  ${DIM}Нет установленных сервисов${NC}"
    print_separator
}

# --- Информация о сервере --------------------------------------------------
show_server_info() {
    echo ""
    echo -e "${BOLD}  ИНФОРМАЦИЯ О СЕРВЕРЕ${NC}"
    print_separator
    echo ""
    echo -e "  OS:            ${OS_NAME:-$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)}"
    echo -e "  Kernel:        $(uname -r)"
    echo -e "  Arch:          $(uname -m)"
    echo -e "  IP:            $(get_external_ip)"
    echo -e "  Hostname:      $(hostname)"
    echo -e "  Uptime:        $(uptime -p 2>/dev/null || uptime)"
    echo ""

    # CPU
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "?")
    local cpu_model
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")
    echo -e "  CPU:           ${cpu_model} (${cpu_cores} cores)"

    # RAM
    local mem_total mem_used mem_free
    mem_total=$(free -h 2>/dev/null | awk '/^Mem:/{print $2}')
    mem_used=$(free -h 2>/dev/null | awk '/^Mem:/{print $3}')
    mem_free=$(free -h 2>/dev/null | awk '/^Mem:/{print $4}')
    echo -e "  RAM:           ${mem_used} / ${mem_total} (свободно: ${mem_free})"

    # Disk
    local disk_info
    disk_info=$(df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')
    echo -e "  Disk (/):      ${disk_info}"

    echo ""

    # Занятые порты прокси
    echo -e "  ${BOLD}Порты:${NC}"
    load_config
    for svc_port in "${TELEMT_PORT:-443}" "${MTG_PORT:-8443}" "${MTPROXY_PORT:-8888}"; do
        if check_port "$svc_port"; then
            local proc
            proc=$(get_port_process "$svc_port")
            echo -e "    :${svc_port}  ${GREEN}занят${NC}  ${DIM}${proc}${NC}"
        else
            echo -e "    :${svc_port}  ${DIM}свободен${NC}"
        fi
    done

    echo ""
    print_separator
}

# --- Показать логи (выбор сервиса) -----------------------------------------
show_logs_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  ПРОСМОТР ЛОГОВ${NC}"
    print_separator
    echo ""
    echo -e "  1) telemt — последние записи"
    echo -e "  2) telemt — live (следить)"
    echo -e "  3) mtg — последние записи"
    echo -e "  4) mtg — live (следить)"
    echo -e "  5) MTProxy — последние записи"
    echo -e "  6) MTProxy — live (следить)"
    echo -e "  7) Все сервисы — последние записи"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    echo ""
    case "$choice" in
        1)
            read -rp "$(echo -e "${CYAN}Количество строк [50]: ${NC}")" lines
            telemt_logs "${lines:-50}"
            ;;
        2) telemt_logs_follow ;;
        3)
            read -rp "$(echo -e "${CYAN}Количество строк [50]: ${NC}")" lines
            mtg_logs "${lines:-50}"
            ;;
        4) mtg_logs_follow ;;
        5)
            read -rp "$(echo -e "${CYAN}Количество строк [50]: ${NC}")" lines
            mtproxy_logs "${lines:-50}"
            ;;
        6) mtproxy_logs_follow ;;
        7)
            echo -e "${BOLD}=== telemt ===${NC}"
            telemt_logs 20
            echo ""
            echo -e "${BOLD}=== mtg ===${NC}"
            mtg_logs 20
            echo ""
            echo -e "${BOLD}=== MTProxy ===${NC}"
            mtproxy_logs 20
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
