#!/usr/bin/env bash
#
# olcwave-manager.sh — меню управления уже установленной OLCWave.
#

# Версия менеджера. Меняй её здесь для вызова обновлений.
MANAGER_VERSION="1.2.1"

set -Eeuo pipefail

APP_DIR="${OLCWAVE_DIR:-/opt/olcwave}"

# Путь к конфигурации Caddy.
CADDYFILE="$APP_DIR/caddy/Caddyfile"

# ---------------------------------------------------------------------------
# Вывод в консоль в новом стиле
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_RED='\033[1;31m'
  C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'
  C_BLUE='\033[1;34m'
  C_WHITE='\033[1;37m'
  C_GRAY='\033[38;5;244m'
  C_LIGHT_GRAY='\033[38;5;250m'
  C_LINE='\033[38;5;8m'
else
  C_RESET=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_WHITE=''; C_GRAY=''; C_LIGHT_GRAY=''; C_LINE=''
fi

# Линия разделителя
draw_line() {
  echo -e "${C_LINE}$(printf '─%.0s' $(seq 1 45))${C_RESET}"
}

info()    { echo -e "${C_LIGHT_GRAY}ℹ️  $*${C_RESET}"; }
success() { echo -e "${C_GREEN}✅ $*${C_RESET}"; }
warn()    { echo -e "${C_YELLOW}⚠️  $*${C_RESET}"; }
error()   { echo -e "${C_RED}❌ $*${C_RESET}" >&2; }
die()     { error "$*"; exit 1; }

pause() {
  echo
  read -r -p "$(echo -e "${C_GRAY}Нажмите Enter для продолжения...${C_RESET}")" _
}

confirm() {
  local answer
  read -r -p "$(echo -e "${C_WHITE}$1 [y/N]: ${C_RESET}")" answer
  [[ "$answer" =~ ^[yYдД]$ ]]
}

# ---------------------------------------------------------------------------
# Проверка установки и автообновление
# ---------------------------------------------------------------------------
check_installation() {
  [[ $(id -u) -eq 0 ]] || die "Запустите скрипт от root."
  [[ -d "$APP_DIR" ]] || die "Каталог $APP_DIR не найден."
  [[ -f "$APP_DIR/compose.yaml" || -f "$APP_DIR/compose.yml" || \
     -f "$APP_DIR/docker-compose.yaml" || -f "$APP_DIR/docker-compose.yml" ]] || {
    error "В $APP_DIR не найден Compose-файл."
    exit 1
  }
  command -v docker >/dev/null 2>&1 || die "Docker не установлен."
  docker compose version >/dev/null 2>&1 || die "Команда docker compose недоступна."
  cd "$APP_DIR"
}

check_for_updates() {
  local branch raw_url remote_version
  
  # Получаем текущую ветку
  branch="$(git -C "$APP_DIR" branch --show-current 2>/dev/null || echo "main")"
  raw_url="https://raw.githubusercontent.com/user14484/olcwave/${branch}/olcwave-manager.sh"
  
  # Извлекаем версию с GitHub
  remote_version="$(curl -s -m 3 "$raw_url" | grep -m1 '^MANAGER_VERSION=' | cut -d'"' -f2 || true)"

  if [[ -n "$remote_version" && "$remote_version" != "$MANAGER_VERSION" ]]; then
    echo
    warn "Доступна новая версия менеджера: $remote_version (текущая: $MANAGER_VERSION)"
    if confirm "Обновить OLCWave и менеджер сейчас?"; then
      update_panel
      pause
      # Перезапуск скрипта, чтобы использовать обновленную логику в памяти
      exec "$0" "$@"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Управление сервисами
# ---------------------------------------------------------------------------
find_service() {
  local pattern="$1"
  docker compose config --services 2>/dev/null | grep -Ei "^${pattern}$|${pattern}" | head -n1 || true
}

select_olcrtc_container() {
  local containers
  mapfile -t containers < <(docker ps -a --filter ancestor=olcrtc --format '{{.Names}}')

  if [[ ${#containers[@]} -eq 0 ]]; then
    echo ""
    return 0
  elif [[ ${#containers[@]} -eq 1 ]]; then
    echo "${containers[0]}"
    return 0
  fi

  echo -e "\n${C_WHITE}Найдены следующие контейнеры OLCRTC:${C_RESET}" >&2
  local i=1
  for c in "${containers[@]}"; do
    echo -e "   ${C_WHITE}$i)${C_RESET} $c" >&2
    ((i++))
  done
  echo -e "   ${C_GRAY}0)${C_RESET} Отмена" >&2
  echo >&2

  local choice
  read -r -p "$(echo -e "${C_WHITE}Выберите контейнер [0-$((${#containers[@]}))]: ${C_RESET}")" choice >&2

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice > 0 && choice <= ${#containers[@]} )); then
    echo "${containers[$((choice-1))]}"
  else
    echo ""
  fi
}

restart_service() {
  local title="$1" pattern="$2" is_compose="${3:-true}" service
  
  if [[ "$is_compose" == true ]]; then
    service="$(find_service "$pattern")"
    [[ -n "$service" ]] || { warn "Сервис '$pattern' не найден в Compose."; return 1; }
    info "Перезапуск $title ($service)..."
    docker compose restart "$service"
  else
    if [[ "$pattern" == "olcrtc" ]]; then
      service="$(select_olcrtc_container)"
      [[ -n "$service" ]] || { warn "Операция отменена или контейнеры OLCRTC не найдены."; return 1; }
    else
      service="$(docker ps -a --filter "name=^${pattern}$" --format '{{.Names}}' | head -n1)"
      if [[ -z "$service" ]]; then
        service="$(docker ps -a --filter "ancestor=$pattern" --format '{{.Names}}' | head -n1)"
      fi
      [[ -n "$service" ]] || { warn "Контейнер для '$title' не найден."; return 1; }
    fi
    
    info "Перезапуск $title ($service)..."
    docker restart "$service"
  fi
  
  success "$title перезапущен."
}

show_status() {
  echo -e "\033[1;37m📊 Статус контейнеров:\033[0m"
  draw_line
  docker compose ps
}

restart_all() {
  info "Перезапуск всех сервисов..."
  docker compose restart
  success "Все сервисы перезапущены."
}

show_logs() {
  local service is_compose=true
  clear
  echo -e "${C_WHITE}📋 Просмотр логов${C_RESET}"
  draw_line
  echo
  echo -e "   ${C_WHITE}1)${C_RESET} 🌍 Все сервисы (только Compose)"
  echo -e "   ${C_WHITE}2)${C_RESET} ⚙️  API/backend"
  echo -e "   ${C_WHITE}3)${C_RESET} 🌐 Caddy"
  echo -e "   ${C_WHITE}4)${C_RESET} 🛡️  XrayCore"
  echo -e "   ${C_WHITE}5)${C_RESET} 📞 OLCRTC"
  echo -e "   ${C_GRAY}0)${C_RESET} ⬅️  Назад"
  echo
  read -r -p "$(echo -e "${C_WHITE}Выберите логи [0-5]: ${C_RESET}")" choice

  case "$choice" in
    1) docker compose logs -f --tail=150; return 0 ;;
    2) service="$(find_service 'api|backend')" ;;
    3) service="$(find_service caddy)" ;;
    4) service="olcwave-xraycore"; is_compose=false ;;
    5) 
       service="$(select_olcrtc_container)"
       [[ -n "$service" ]] || { warn "Операция отменена или контейнеры OLCRTC не найдены."; return 1; }
       is_compose=false 
       ;;
    0) return 0 ;;
    *) warn "Неверный пункт."; return 0 ;;
  esac

  if [[ "$is_compose" == true ]]; then
    [[ -n "${service:-}" ]] || { warn "Сервис не найден в Compose."; return 1; }
    docker compose logs -f --tail=150 "$service"
  else
    [[ -n "${service:-}" ]] || { warn "Контейнер не найден."; return 1; }
    docker logs -f --tail=150 "$service"
  fi
}
# ---------------------------------------------------------------------------
# Обновления и бэкапы
# ---------------------------------------------------------------------------
backup_configs() {
  local backup_dir="$APP_DIR/backups/config-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"

  for file in backend/.env frontend/.env subscriptionPage/.env caddy/Caddyfile; do
    [[ -f "$file" ]] && cp --parents "$file" "$backup_dir/"
  done

  success "Резервная копия конфигов: $backup_dir"
}

update_manager_command() {
  local source="$APP_DIR/olcwave-manager.sh"
  local target="/usr/local/bin/olcwave-manager"

  [[ -f "$source" ]] || {
    warn "Файл $source не найден."
    return 0
  }

  install -m 755 "$source" "$target"
  success "Команда olcwave-manager обновлена."
}

build_node_project() {
  local directory="$1" title="$2"
  [[ -d "$directory" ]] || return 0

  info "Сборка $title..."
  (
    cd "$directory"
    
    # Оставляем только npm install для надежности
    npm install
    
    npm run build
    
    # Откатываем изменения в lock-файле сразу после сборки, чтобы Git не ругался при следующем обновлении
    git checkout -- package-lock.json 2>/dev/null || true
  )
}

update_panel() {
  command -v git >/dev/null 2>&1 || die "Git не установлен."
  command -v npm >/dev/null 2>&1 || die "npm не установлен."
  [[ -d .git ]] || die "$APP_DIR не является Git-репозиторием."

  local branch action stash_created=false
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "Не удалось определить текущую ветку Git."

  # Превентивно сбрасываем lock-файлы перед проверкой git status
  git checkout -- frontend/package-lock.json 2>/dev/null || true
  git checkout -- subscriptionPage/package-lock.json 2>/dev/null || true

  if [[ -n "$(git status --porcelain)" ]]; then
    warn "В репозитории есть локальные изменения:"
    git status --short

    echo
    echo -e "   ${C_WHITE}1)${C_RESET} Сохранить мои изменения и объединить их с обновлением"
    echo -e "   ${C_WHITE}2)${C_RESET} Полностью заменить локальные файлы версией из GitHub"
    echo -e "   ${C_WHITE}0)${C_RESET} Отменить обновление"
    echo

    read -rp "$(echo -e "${C_WHITE}Выберите действие [1-3]: ${C_RESET}")" action

    case "$action" in
      1)
        if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
          warn "Сейчас в репозитории уже есть конфликт слияния:"
          git diff --name-only --diff-filter=U
          echo
          warn "Сначала разрешите конфликт вручную либо выберите пункт 2."
          return 1
        fi
        info "Временное сохранение локальных изменений..."
        git stash push -u -m "OLCWave Manager before update"
        stash_created=true
        ;;
      2)
        warn "Все локальные изменения будут удалены."
        confirm "Продолжить и сделать файлы как в origin/$branch?" || return 0
        ;;
      0|"")
        info "Обновление отменено."
        return 0
        ;;
      *)
        warn "Неизвестный пункт."
        return 1
        ;;
    esac
  else
    action=2
  fi

  backup_configs

  info "Получение обновлений origin/$branch..."
  git fetch origin "$branch"

  if [[ "$action" == "1" ]]; then
    info "Обновление текущей ветки..."
    git merge --ff-only "origin/$branch"

    if [[ "$stash_created" == true ]]; then
      info "Возвращение локальных изменений..."
      if ! git stash pop; then
        warn "При объединении возник конфликт."
        warn "Изменения не потеряны: копия осталась в git stash."
        warn "Разрешите конфликт вручную и затем продолжите сборку."
        return 1
      fi
    fi
  else
    info "Сброс файлов до origin/$branch..."
    git reset --hard "origin/$branch"

    git clean -fd \
        -e backups/ \
        -e backend/.env \
        -e frontend/.env \
        -e subscriptionPage/.env \
        -e caddy/Caddyfile
  fi

  update_manager_command

  build_node_project frontend "панели"
  build_node_project subscriptionPage "страницы подписки"

  info "Пересборка XrayCore..."
  docker build backend/xraycore -t xraycore
  
  if docker container inspect olcwave-xraycore >/dev/null 2>&1; then
    docker rm -f olcwave-xraycore
  fi
  
  docker create --name olcwave-xraycore xraycore >/dev/null
  success "Контейнер olcwave-xraycore подготовлен."

  info "Пересборка и запуск Docker Compose..."
  docker compose up -d --build

  success "OLCWave обновлена."
  docker compose ps
}

switch_branch() {
  command -v git >/dev/null 2>&1 || die "Git не установлен."
  [[ -d .git ]] || die "$APP_DIR не является Git-репозиторием."

  info "Получение списка веток с сервера..."
  git fetch origin

  echo
  echo -e "${C_WHITE}📋 Доступные ветки:${C_RESET}"
  draw_line
  git branch -r | grep -v '\->' | sed 's|origin/||' | awk "{print \"   ${C_LIGHT_GRAY}•${C_RESET} \" \$1}"
  echo
  
  local current
  current="$(git branch --show-current)"
  info "Текущая ветка: ${C_GREEN}$current${C_RESET}"
  
  read -rp "$(echo -e "${C_WHITE}Введите имя ветки для переключения (Enter - отмена): ${C_RESET}")" target
  [[ -z "$target" ]] && return 0
  
  if [[ "$target" == "$current" ]]; then
    warn "Вы уже на этой ветке."
    return 0
  fi

  info "Переключение на ветку $target..."
  if git checkout "$target"; then
    success "Ветка успешно изменена."
    if confirm "Запустить обновление панели для применения изменений?"; then
      update_panel
    fi
  else
    error "Не удалось переключить ветку. У вас есть конфликтующие изменения."
  fi
}

# ---------------------------------------------------------------------------
# Управление Caddy
# ---------------------------------------------------------------------------
ensure_caddyfile() {
  local template="$APP_DIR/caddy/Caddyfile.template"

  if [[ -f "$CADDYFILE" ]]; then
    return 0
  fi

  if [[ -d "$CADDYFILE" ]]; then
    warn "$CADDYFILE является каталогом. Удаляю его."
    rm -rf "$CADDYFILE"
  fi

  [[ -f "$template" ]] || {
    error "Не найден шаблон $template"
    return 1
  }

  warn "Caddyfile отсутствует."
  warn "Автоматически создать его без доменов невозможно."
  warn "Запустите install.sh либо восстановите Caddyfile из backup."

  return 1
}

edit_caddy() {
  local file="caddy/Caddyfile"
  [[ -f "$file" ]] || { warn "$file не найден."; return 1; }

  cp "$file" "${file}.backup-$(date +%Y%m%d-%H%M%S)"
  "${EDITOR:-nano}" "$file"

  local caddy
  caddy="$(find_service caddy)"
  [[ -n "$caddy" ]] || { warn "Сервис Caddy не найден."; return 1; }

  info "Проверка Caddyfile..."
  if docker compose exec -T "$caddy" caddy validate --config /etc/caddy/Caddyfile; then
    docker compose restart "$caddy"
    success "Caddyfile корректен, Caddy перезапущен."
  else
    error "Caddyfile содержит ошибку. Caddy не перезапущен."
  fi
}

apply_caddy_config() {
  local caddy
  caddy="$(find_service caddy)"
  [[ -n "$caddy" ]] || { error "Сервис Caddy не найден."; return 1; }

  [[ -f "$CADDYFILE" ]] || { error "Файл $CADDYFILE не найден."; return 1; }

  info "Проверка конфигурации Caddy..."
  if ! docker compose run --rm --no-deps "$caddy" caddy validate --config /etc/caddy/Caddyfile; then
    error "Конфигурация Caddy содержит ошибку."
    warn "Caddy не был перезапущен."
    return 1
  fi

  success "Конфигурация Caddy корректна."
  info "Перезапуск Caddy..."
  docker compose up -d --force-recreate "$caddy"
  sleep 3

  if docker compose ps --status running "$caddy" | grep -q "$caddy"; then
    success "Caddy успешно запущен."
  else
    error "Caddy не смог запуститься."
    echo
    docker compose logs --tail=100 "$caddy"
    return 1
  fi
}

remove_managed_tls_block() {
  local temp_file
  temp_file="$(mktemp)"

  awk '
    /^# OLCWAVE TLS BEGIN$/ { skip=1; next }
    /^# OLCWAVE TLS END$/   { skip=0; next }
    !skip { print }
  ' "$CADDYFILE" > "$temp_file"

  mv "$temp_file" "$CADDYFILE"
}

set_managed_tls_block() {
  local content="$1"
  local temp_file
  temp_file="$(mktemp)"

  {
    echo "# OLCWAVE TLS BEGIN"
    printf '%s\n' "$content"
    echo "# OLCWAVE TLS END"
    echo
    cat "$CADDYFILE"
  } > "$temp_file"

  mv "$temp_file" "$CADDYFILE"
}

set_caddy_tls_auto() {
  ensure_caddyfile || return 1
  backup_configs
  remove_managed_tls_block
  info "Включён автоматический выбор публичного сертификата."
  apply_caddy_config
}

set_caddy_tls_letsencrypt() {
  ensure_caddyfile || return 1
  backup_configs
  remove_managed_tls_block

  set_managed_tls_block '{
  acme_ca https://acme-v02.api.letsencrypt.org/directory
}'

  info "Выбран центр сертификации Let's Encrypt."
  apply_caddy_config
}

set_caddy_tls_internal() {
  ensure_caddyfile || return 1
  backup_configs
  remove_managed_tls_block

  set_managed_tls_block '{
  local_certs
}'

  warn "Выбран внутренний сертификат Caddy."
  warn "Браузеры не будут доверять ему без установки корневого сертификата."
  apply_caddy_config
}

caddy_menu() {
  local caddy
  ensure_caddyfile || { pause; return 1; }

  while true; do
    clear
    echo -e "\033[1;37m🌐 Управление Caddy Reverse Proxy\033[0m"
    draw_line
    echo
    echo -e "   \033[38;5;15m1)\033[0m 🔒 Автоматический сертификат (По умолчанию)"
    echo -e "   \033[38;5;15m2)\033[0m 🛡️  Принудительно Let's Encrypt"
    echo -e "   \033[38;5;15m3)\033[0m ⚠️  Самоподписанный сертификат Caddy"
    echo -e "   \033[38;5;15m4)\033[0m 📝 Изменить Caddyfile"
    echo -e "   \033[38;5;15m5)\033[0m 🔄 Перезапустить Caddy"
    echo -e "   \033[38;5;15m6)\033[0m 📋 Показать логи Caddy"
    echo
    echo -e "   \033[38;5;244m0)\033[0m ⬅️  Назад"
    echo

    read -rp "$(echo -e "\033[1;37mВыберите пункт [0-6]: \033[0m")" choice

    case "$choice" in
      1) set_caddy_tls_auto ;;
      2) set_caddy_tls_letsencrypt ;;
      3) set_caddy_tls_internal ;;
      4) edit_caddy ;;
      5) restart_service "Caddy" "caddy" ;;
      6)
        caddy="$(find_service caddy)"
        if [[ -z "$caddy" ]]; then
          warn "Сервис Caddy не найден."
        else
          docker compose logs -f --tail=100 "$caddy"
        fi
        ;;
      0) return 0 ;;
      *) warn "Неизвестный пункт." ;;
    esac

    pause
  done
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------
print_menu() {
  clear
  echo -e "${C_WHITE}🌊 OLCWave Manager (v${MANAGER_VERSION})${C_RESET}"
  draw_line
  printf "   ${C_WHITE}%-15s${C_RESET} ${C_LIGHT_GRAY}%s${C_RESET}\n" "Каталог:" "$APP_DIR"
  printf "   ${C_WHITE}%-15s${C_RESET} ${C_LIGHT_GRAY}%s${C_RESET}\n" "Ветка Git:" "$(git branch --show-current 2>/dev/null || echo "неизвестно")"
  echo

  echo -e "${C_WHITE}📋 Основные действия:${C_RESET}"
  echo -e "   ${C_WHITE}1)${C_RESET} 📊 Статус контейнеров"
  echo -e "   ${C_WHITE}2)${C_RESET} 🔄 Обновить панель (текущая ветка)"
  echo -e "   ${C_WHITE}3)${C_RESET} 🔀 Сменить ветку Git"
  echo -e "   ${C_WHITE}4)${C_RESET} ▶️  Перезапустить все сервисы"
  echo -e "   ${C_WHITE}5)${C_RESET} ⚙️  Перезапустить API/backend"
  echo -e "   ${C_WHITE}6)${C_RESET} 🛡️  Перезапустить XrayCore"
  echo -e "   ${C_WHITE}7)${C_RESET} 📞 Перезапустить OLCRTC"
  echo -e "   ${C_WHITE}8)${C_RESET} 🌐 Управление Caddy"
  echo -e "   ${C_WHITE}9)${C_RESET} 📋 Посмотреть логи"
  echo
  echo -e "   ${C_GRAY}0)${C_RESET} ⬅️  Выход в терминал"
  echo
}

main() {
  check_installation
  check_for_updates

  while true; do
    print_menu
    read -r -p "$(echo -e "${C_WHITE}Выберите пункт [0-9]: ${C_RESET}")" choice
    echo

    case "$choice" in
      1) show_status; pause ;;
      2) update_panel; pause ;;
      3) switch_branch; pause ;;
      4) restart_all; pause ;;
      5) restart_service "API/backend" 'api|backend'; pause ;;
      6) restart_service "XrayCore" 'olcwave-xraycore' false; pause ;;
      7) restart_service "OLCRTC" 'olcrtc' false; pause ;;
      8) caddy_menu ;;
      9) show_logs || true; pause ;;
      0) exit 0 ;;
      *) warn "Неверный пункт."; sleep 1 ;;
    esac
  done
}

main "$@"