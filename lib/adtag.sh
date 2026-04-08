#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Ad Tag Management
# ============================================================================

adtag_menu() {
    load_config

    echo ""
    echo -e "  📢 ${BOLD}РЕКЛАМНЫЙ ТЕГ (AD TAG)${NC}"
    print_separator
    echo ""

    # Показываем секреты для бота
    echo -e "  ${BOLD}Секреты для @MTProxybot:${NC}"
    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        local t_secret="${TELEMT_SECRET}"
        [[ "$t_secret" == ee* ]] && t_secret="${t_secret:2:32}"
        echo -e "    telemt:  🔑 ${YELLOW}${t_secret}${NC}  порт ${TELEMT_PORT}"
    fi
    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        echo -e "    MTProxy: 🔑 ${YELLOW}${MTPROXY_SECRET}${NC}  порт ${MTPROXY_PORT}"
    fi

    echo ""
    echo -e "  ${BOLD}Текущие теги:${NC}"
    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        echo -e "    telemt:  ${YELLOW}${TELEMT_AD_TAG:-не установлен}${NC}"
    fi
    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        echo -e "    mtg:     ${DIM}не поддерживает Ad Tag (v2)${NC}"
    fi
    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        echo -e "    MTProxy: ${YELLOW}${MTPROXY_AD_TAG:-не установлен}${NC}"
    fi

    echo ""
    print_separator
    echo ""
    echo -e "  ${BOLD}Как получить Ad Tag:${NC}"
    echo -e "  1. Откройте ${CYAN}@MTProxybot${NC} в Telegram"
    echo -e "  2. Отправьте ${CYAN}/newproxy${NC}"
    echo -e "  3. Отправьте порт прокси (см. выше)"
    echo -e "  4. Отправьте секрет 🔑 (см. выше)"
    echo -e "  5. Выберите канал для рекламы"
    echo -e "  6. Бот выдаст Ad Tag"
    echo ""
    print_separator
    echo ""
    echo -e "  1) Изменить тег для telemt"
    echo -e "  2) Изменить тег для MTProxy"
    echo -e "  3) Удалить все теги"
    echo -e "  0) ↩️  Назад"
    echo ""

    read -rp "$(echo -e "${CYAN}  Выберите: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }
            telemt_set_ad_tag
            ;;
        2)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }
            mtproxy_set_ad_tag
            ;;
        3)
            save_config_value "TELEMT_AD_TAG" ""
            save_config_value "MTPROXY_AD_TAG" ""
            load_config
            [[ "${TELEMT_INSTALLED}" == "true" ]] && { telemt_write_config; systemctl restart telemt 2>/dev/null; }
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && systemctl restart mtproxy 2>/dev/null
            log_success "Все теги удалены"
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
