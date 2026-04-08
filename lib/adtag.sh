#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Ad Tag Management
# ============================================================================

adtag_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  РЕКЛАМНЫЙ ТЕГ (AD TAG)${NC}"
    print_separator
    echo ""
    echo -e "  Текущие теги:"

    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        local t_tag="${TELEMT_AD_TAG:-${DIM}не установлен${NC}}"
        echo -e "    telemt:  ${YELLOW}${t_tag}${NC}"
    fi
    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        local m_tag="${MTG_AD_TAG:-${DIM}не установлен${NC}}"
        echo -e "    mtg:     ${YELLOW}${m_tag}${NC}"
    fi
    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        local o_tag="${MTPROXY_AD_TAG:-${DIM}не установлен${NC}}"
        echo -e "    MTProxy: ${YELLOW}${o_tag}${NC}"
    fi

    echo ""
    print_separator
    echo ""
    echo -e "  1) Изменить тег для telemt"
    echo -e "  2) Изменить тег для mtg"
    echo -e "  3) Изменить тег для MTProxy"
    echo -e "  4) Установить один тег для всех"
    echo -e "  5) Удалить все теги"
    echo -e "  0) Назад"
    echo ""
    echo -e "  ${DIM}Получить тег: напишите @MTProxybot в Telegram${NC}"
    echo ""

    read -rp "$(echo -e "${CYAN}Выберите действие: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }
            telemt_set_ad_tag
            ;;
        2)
            [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }
            mtg_set_ad_tag
            ;;
        3)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }
            mtproxy_set_ad_tag
            ;;
        4)
            echo ""
            read -rp "$(echo -e "${CYAN}Ad Tag для всех сервисов: ${NC}")" new_tag
            [[ "${TELEMT_INSTALLED}" == "true" ]] && {
                save_config_value "TELEMT_AD_TAG" "$new_tag"
                # Перезапись unit + restart делается через set_ad_tag
            }
            [[ "${MTG_INSTALLED}" == "true" ]] && {
                save_config_value "MTG_AD_TAG" "$new_tag"
            }
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && {
                save_config_value "MTPROXY_AD_TAG" "$new_tag"
            }
            # Перестроить unit-файлы и перезапустить
            load_config
            [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_rebuild_unit && systemctl restart telemt 2>/dev/null
            [[ "${MTG_INSTALLED}" == "true" ]] && mtg_rebuild_unit && systemctl restart mtg 2>/dev/null
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && systemctl restart mtproxy 2>/dev/null
            systemctl daemon-reload
            log_success "Ad Tag обновлён для всех сервисов"
            ;;
        5)
            save_config_value "TELEMT_AD_TAG" ""
            save_config_value "MTG_AD_TAG" ""
            save_config_value "MTPROXY_AD_TAG" ""
            load_config
            [[ "${TELEMT_INSTALLED}" == "true" ]] && systemctl restart telemt 2>/dev/null
            [[ "${MTG_INSTALLED}" == "true" ]] && systemctl restart mtg 2>/dev/null
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && systemctl restart mtproxy 2>/dev/null
            log_success "Все теги удалены"
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}
