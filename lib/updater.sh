#!/usr/bin/env bash
# ============================================================================
# MTProxy Manager — Update System
# ============================================================================

# --- Проверка обновлений всех сервисов --------------------------------------
check_all_updates() {
    load_config

    echo ""
    echo -e "${BOLD}  ПРОВЕРКА ОБНОВЛЕНИЙ${NC}"
    print_separator
    echo ""

    local has_any="false"

    if [[ "${TELEMT_INSTALLED}" == "true" ]]; then
        telemt_check_update
        has_any="true"
    fi

    if [[ "${MTG_INSTALLED}" == "true" ]]; then
        mtg_check_update
        has_any="true"
    fi

    if [[ "${MTPROXY_INSTALLED}" == "true" ]]; then
        mtproxy_check_update
        has_any="true"
    fi

    [[ "$has_any" == "false" ]] && echo -e "  ${DIM}Нет установленных сервисов${NC}"

    # Проверка обновления самого менеджера
    echo ""
    manager_check_update

    echo ""
    print_separator
}

# --- Обновление сервисов (выбор) -------------------------------------------
update_services_menu() {
    load_config

    echo ""
    echo -e "${BOLD}  ОБНОВЛЕНИЕ СЕРВИСОВ${NC}"
    print_separator
    echo ""

    # Сначала показываем статус обновлений
    check_all_updates

    echo ""
    echo -e "  1) Обновить telemt"
    echo -e "  2) Обновить mtg"
    echo -e "  3) Обновить MTProxy (пересборка)"
    echo -e "  4) Обновить ВСЕ сервисы"
    echo -e "  0) Назад"
    echo ""
    read -rp "$(echo -e "${CYAN}Выберите: ${NC}")" choice

    case "$choice" in
        1)
            [[ "${TELEMT_INSTALLED}" != "true" ]] && { log_warn "telemt не установлен"; return; }
            telemt_update
            ;;
        2)
            [[ "${MTG_INSTALLED}" != "true" ]] && { log_warn "mtg не установлен"; return; }
            mtg_update
            ;;
        3)
            [[ "${MTPROXY_INSTALLED}" != "true" ]] && { log_warn "MTProxy не установлен"; return; }
            mtproxy_update
            ;;
        4)
            log_info "Обновление всех установленных сервисов..."
            [[ "${TELEMT_INSTALLED}" == "true" ]] && telemt_update
            [[ "${MTG_INSTALLED}" == "true" ]] && mtg_update
            [[ "${MTPROXY_INSTALLED}" == "true" ]] && mtproxy_update
            log_success "Обновление завершено"
            ;;
        0) return ;;
        *) log_warn "Неверный выбор" ;;
    esac
}

# --- Self-update менеджера --------------------------------------------------
manager_check_update() {
    local current_version
    current_version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")

    # Проверяем последний тег в репозитории
    local latest_version
    latest_version=$(git ls-remote --tags "${REPO_URL}" 2>/dev/null \
        | awk '{print $2}' \
        | sed 's|refs/tags/||' \
        | grep -E '^v?[0-9]+\.[0-9]+' \
        | sort -V \
        | tail -1)

    if [[ -z "$latest_version" ]]; then
        # Нет тегов — проверяем по коммитам
        local local_hash remote_hash
        local_hash=$(cd "${INSTALL_DIR}" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        remote_hash=$(git ls-remote "${REPO_URL}" HEAD 2>/dev/null | awk '{print substr($1,1,7)}')

        if [[ -n "$remote_hash" && "$local_hash" != "$remote_hash" ]]; then
            echo -e "  ${WARN} Менеджер: ${YELLOW}${local_hash}${NC} -> ${GREEN}${remote_hash}${NC} (новые коммиты)"
        else
            echo -e "  ${TICK} Менеджер: ${GREEN}v${current_version}${NC} (актуально)"
        fi
    else
        if [[ "v${current_version}" != "${latest_version}" && "${current_version}" != "${latest_version}" ]]; then
            echo -e "  ${WARN} Менеджер: ${YELLOW}v${current_version}${NC} -> ${GREEN}${latest_version}${NC} (обновление)"
        else
            echo -e "  ${TICK} Менеджер: ${GREEN}v${current_version}${NC} (актуально)"
        fi
    fi
}

manager_self_update() {
    local current_version
    current_version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")

    echo ""
    echo -e "${BOLD}  ОБНОВЛЕНИЕ УСТАНОВЩИКА${NC}"
    print_separator
    echo -e "  Текущая версия: ${YELLOW}v${current_version}${NC}"
    echo ""

    if [[ ! -d "${INSTALL_DIR}/.git" ]]; then
        log_warn "Репозиторий не найден. Выполняю полное клонирование..."
        local tmp_dir
        tmp_dir=$(mktemp -d)
        if git clone "${REPO_URL}" "${tmp_dir}/proxy"; then
            rsync -a --delete \
                --exclude='config/' \
                "${tmp_dir}/proxy/" "${INSTALL_DIR}/"
            rm -rf "${tmp_dir}"
        else
            rm -rf "${tmp_dir}"
            die "Не удалось клонировать репозиторий"
        fi
    else
        cd "${INSTALL_DIR}" || die "Не удалось перейти в ${INSTALL_DIR}"

        # Сохраняем локальные изменения
        git stash 2>/dev/null || true

        # Получаем обновления
        if ! git pull origin main 2>/dev/null && ! git pull origin master 2>/dev/null; then
            log_warn "git pull не удался, пробую fetch + reset..."
            git fetch origin
            local default_branch
            default_branch=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
            default_branch="${default_branch:-main}"
            git reset --hard "origin/${default_branch}"
        fi

        cd /root || true
    fi

    # Обновляем симлинк команды tgp
    ln -sf "${INSTALL_DIR}/menu.sh" "${BIN_DIR}/tgp"
    chmod +x "${INSTALL_DIR}/menu.sh" "${INSTALL_DIR}/install.sh"
    chmod +x "${INSTALL_DIR}"/lib/*.sh 2>/dev/null || true

    local new_version
    new_version=$(cat "${INSTALL_DIR}/VERSION" 2>/dev/null || echo "unknown")
    save_config_value "MANAGER_VERSION" "$new_version"

    log_success "Менеджер обновлён: v${current_version} -> v${new_version}"
}

# --- Удаление всего ---------------------------------------------------------
uninstall_all() {
    echo ""
    echo -e "${RED}${BOLD}  ПОЛНОЕ УДАЛЕНИЕ MTPROXY MANAGER${NC}"
    print_separator
    echo ""
    echo -e "  Будут удалены:"
    echo -e "    - Все прокси-сервисы (telemt, mtg, MTProxy)"
    echo -e "    - Конфигурация (${CONFIG_DIR})"
    echo -e "    - Бинарные файлы"
    echo -e "    - Systemd сервисы"
    echo -e "    - Команда tgp"
    echo ""

    if ! confirm "Вы уверены? Это действие необратимо"; then
        log_info "Отменено"
        return
    fi

    echo ""
    if ! confirm "Точно уверены? Введите y ещё раз"; then
        log_info "Отменено"
        return
    fi

    log_info "Удаление всех сервисов..."

    # Остановка и удаление сервисов
    for svc in telemt mtg mtproxy; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
        rm -f "/etc/systemd/system/${svc}.service"
    done
    systemctl daemon-reload

    # Удаление бинарников
    rm -f "${BIN_DIR}/telemt"
    rm -f "${BIN_DIR}/mtg"
    rm -f "${BIN_DIR}/mtproto-proxy"
    rm -f "${BIN_DIR}/tgp"

    # Удаление директорий
    rm -rf "${MTPROXY_BUILD_DIR:-/opt/MTProxy}"
    rm -rf "${CONFIG_DIR}"
    rm -rf "${LOG_DIR}"
    rm -rf "${DATA_DIR}"

    # Не удаляем INSTALL_DIR чтобы можно было переустановить
    log_success "Всё удалено. Для переустановки запустите: bash <(curl -sL ...)/install.sh"
}
