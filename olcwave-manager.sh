#!/usr/bin/env bash
#
# olcwave-manager.sh — простое меню управления уже установленной OLCWave.
#
# По умолчанию проект находится в /opt/olcwave.
# Другой путь можно передать так:
#   OLCWAVE_DIR=/opt/olcwave-test ./olcwave-manager.sh
#

set -Eeuo pipefail

APP_DIR="${OLCWAVE_DIR:-/opt/olcwave}"

# Путь к конфигурации Caddy.
CADDYFILE="$APP_DIR/caddy/Caddyfile"

# Цвета отключаются автоматически, когда вывод перенаправлен в файл.
if [[ -t 1 ]]; then
  RESET=$'\033[0m'; BOLD=$'\033[1m'
  BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
else
  RESET=''; BOLD=''; BLUE=''; GREEN=''; YELLOW=''; RED=''
fi

info()    { printf '%s[*]%s %s\n' "$BLUE" "$RESET" "$*"; }
success() { printf '%s[+]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()    { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
error()   { printf '%s[x]%s %s\n' "$RED" "$RESET" "$*" >&2; }
die()     { error "$*"; exit 1; }

pause() {
  printf '\nНажмите Enter, чтобы вернуться в меню...'
  read -r _
}

confirm() {
  local answer
  read -r -p "$1 [y/N]: " answer
  [[ "$answer" =~ ^[yYдД]$ ]]
}

# Все команды выполняются из корня проекта.
check_installation() {
  [[ $(id -u) -eq 0 ]] || die "Запустите скрипт от root."
  [[ -d "$APP_DIR" ]] || die "Каталог $APP_DIR не найден."
  # Docker Compose распознаёт четыре стандартных имени файла.
  [[ -f "$APP_DIR/compose.yaml" || -f "$APP_DIR/compose.yml" || \
     -f "$APP_DIR/docker-compose.yaml" || -f "$APP_DIR/docker-compose.yml" ]] || {
    error "В $APP_DIR не найден Compose-файл."
    error "Ожидался один из файлов: compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml"
    error "Содержимое каталога:"
    ls -la "$APP_DIR" >&2
    exit 1
  }
  command -v docker >/dev/null 2>&1 || die "Docker не установлен."
  docker compose version >/dev/null 2>&1 || die "Команда docker compose недоступна."
  cd "$APP_DIR"
}

# Возвращает имя сервиса Compose по части имени.
# Это позволяет скрипту пережить небольшое переименование сервисов.
find_service() {
  local pattern="$1"
  docker compose config --services 2>/dev/null | grep -Ei "^${pattern}$|${pattern}" | head -n1 || true
}

restart_service() {
  local title="$1" pattern="$2" service
  service="$(find_service "$pattern")"
  [[ -n "$service" ]] || { warn "Сервис '$pattern' не найден."; return 1; }

  info "Перезапуск $title ($service)..."
  docker compose restart "$service"
  success "$title перезапущен."
}

show_status() {
  docker compose ps
}

restart_all() {
  info "Перезапуск всех сервисов..."
  docker compose restart
  success "Все сервисы перезапущены."
}

# Сохраняем пользовательские конфиги перед обновлением исходников.
backup_configs() {
  local backup_dir="$APP_DIR/backups/config-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_dir"

  for file in backend/.env frontend/.env caddy/Caddyfile; do
    [[ -f "$file" ]] && cp --parents "$file" "$backup_dir/"
  done

  success "Резервная копия конфигов: $backup_dir"
}

build_node_project() {
  local directory="$1" title="$2"
  [[ -d "$directory" ]] || return 0

  info "Сборка $title..."
  (
    cd "$directory"
    if [[ -f package-lock.json ]]; then
      npm ci
    else
      npm install
    fi
    npm run build
  )
}

update_panel() {
  command -v git >/dev/null 2>&1 || die "Git не установлен."
  command -v npm >/dev/null 2>&1 || die "npm не установлен."
  [[ -d .git ]] || die "$APP_DIR не является Git-репозиторием."

  local branch action stash_created=false
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "Не удалось определить текущую ветку Git."

  # Если есть локальные изменения или незавершённый конфликт,
  # предлагаем выбрать способ обновления.
  if [[ -n "$(git status --porcelain)" ]]; then
    warn "В репозитории есть локальные изменения:"
    git status --short

    echo
    echo "1) Сохранить мои изменения и объединить их с обновлением"
    echo "2) Полностью заменить локальные файлы версией из GitHub"
    echo "3) Отменить обновление"
    echo

    read -rp "Выберите действие [1-3]: " action

    case "$action" in
      1)
        # При уже существующем конфликте stash создать нельзя.
        if [[ -n "$(git diff --name-only --diff-filter=U)" ]]; then
          warn "Сейчас в репозитории уже есть конфликт слияния:"
          git diff --name-only --diff-filter=U
          echo
          warn "Сначала разрешите конфликт вручную либо выберите пункт 2."
          return 1
        fi

        # Временно убираем изменённые и новые файлы.
        info "Временное сохранение локальных изменений..."
        git stash push -u -m "OLCWave Manager before update"
        stash_created=true
        ;;

      2)
        warn "Все локальные изменения будут удалены."
        confirm "Продолжить и сделать файлы как в origin/$branch?" || return 0
        ;;

      3|"")
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

  # Сохраняем конфигурационные файлы перед обновлением.
  backup_configs

  info "Получение обновлений origin/$branch..."
  git fetch origin "$branch"

  if [[ "$action" == "1" ]]; then
    # Обновляем чистую рабочую копию без удаления локальных коммитов.
    info "Обновление текущей ветки..."
    git merge --ff-only "origin/$branch"

    # Возвращаем локальные изменения поверх новой версии.
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
    # Полностью приводим отслеживаемые файлы к состоянию GitHub.
    info "Сброс файлов до origin/$branch..."
    git reset --hard "origin/$branch"

    # Удаляем неотслеживаемые файлы и каталоги.
    # Каталог backups сохраняем.
    git clean -fd -e backups/
  fi

  # Фронтенд собирается вне Docker и затем раздаётся Caddy.
  build_node_project frontend "панели"
  build_node_project subscriptionPage "страницы подписки"

  info "Пересборка и запуск Docker Compose..."
  docker compose up -d --build

  success "OLCWave обновлена."
  docker compose ps
}

edit_caddy() {
  local file="caddy/Caddyfile"
  [[ -f "$file" ]] || { warn "$file не найден."; return 1; }

  cp "$file" "${file}.backup-$(date +%Y%m%d-%H%M%S)"
  "${EDITOR:-nano}" "$file"

  local caddy
  caddy="$(find_service caddy)"
  [[ -n "$caddy" ]] || { warn "Сервис Caddy не найден."; return 1; }

  # Проверяем конфиг внутри контейнера до перезапуска.
  info "Проверка Caddyfile..."
  if docker compose exec -T "$caddy" caddy validate --config /etc/caddy/Caddyfile; then
    docker compose restart "$caddy"
    success "Caddyfile корректен, Caddy перезапущен."
  else
    error "Caddyfile содержит ошибку. Caddy не перезапущен."
  fi
}

# Проверяет Caddyfile и перезапускает Caddy.
apply_caddy_config() {
  info "Проверка конфигурации Caddy..."

  # Проверяем Caddyfile во временном контейнере.
  # Это работает, даже если основной контейнер Caddy остановлен
  # или находится в цикле перезапуска.
  if ! docker compose run --rm --no-deps \
    caddy \
    caddy validate --config /etc/caddy/Caddyfile; then

    error "Конфигурация Caddy содержит ошибку."
    warn "Caddy не был перезапущен."
    return 1
  fi

  success "Конфигурация Caddy корректна."

  info "Перезапуск Caddy..."
  docker compose up -d --force-recreate caddy

  # Даём контейнеру несколько секунд на запуск.
  sleep 3

  if docker compose ps --status running caddy | grep -q caddy; then
    success "Caddy успешно запущен."
  else
    error "Caddy не смог запуститься."
    echo
    docker compose logs --tail=100 caddy
    return 1
  fi
}


# Удаляет TLS-настройки, добавленные менеджером.
remove_managed_tls_block() {
  local temp_file

  temp_file="$(mktemp)"

  # Удаляем строки между специальными комментариями.
  awk '
    /^# OLCWAVE TLS BEGIN$/ { skip=1; next }
    /^# OLCWAVE TLS END$/   { skip=0; next }
    !skip { print }
  ' "$CADDYFILE" > "$temp_file"

  mv "$temp_file" "$CADDYFILE"
}


# Добавляет глобальный блок в самое начало Caddyfile.
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


# Автоматический публичный сертификат.
set_caddy_tls_auto() {
  backup_configs

  # Убираем созданные менеджером TLS-настройки.
  remove_managed_tls_block

  info "Включён автоматический выбор публичного сертификата."
  apply_caddy_config
}


# Принудительно использовать Let's Encrypt.
set_caddy_tls_letsencrypt() {
  backup_configs
  remove_managed_tls_block

  set_managed_tls_block '{
  acme_ca https://acme-v02.api.letsencrypt.org/directory
}'

  info "Выбран центр сертификации Let's Encrypt."
  apply_caddy_config
}


# Использовать внутренний самоподписанный сертификат Caddy.
set_caddy_tls_internal() {
  backup_configs
  remove_managed_tls_block

  set_managed_tls_block '{
  local_certs
}'

  warn "Выбран внутренний сертификат Caddy."
  warn "Браузеры не будут доверять ему без установки корневого сертификата."

  apply_caddy_config
}


# Подменю управления Caddy.
caddy_menu() {
  while true; do
    clear

    echo "======================================"
    echo "          Управление Caddy"
    echo "======================================"
    echo
    echo "  1) Автоматический публичный сертификат"
    echo "  2) Сертификат Let's Encrypt"
    echo "  3) Самоподписанный сертификат Caddy"
    echo "  4) Изменить Caddyfile"
    echo "  5) Перезапустить Caddy"
    echo "  6) Показать логи Caddy"
    echo "  0) Назад"
    echo

    read -rp "Выберите пункт: " choice

    case "$choice" in
      1)
        set_caddy_tls_auto
        ;;
      2)
        set_caddy_tls_letsencrypt
        ;;
      3)
        set_caddy_tls_internal
        ;;
      4)
        edit_caddyfile
        ;;
      5)
        docker compose restart caddy
        success "Caddy перезапущен."
        ;;
      6)
        docker compose logs -f --tail=100 caddy
        ;;
      0)
        return 0
        ;;
      *)
        warn "Неизвестный пункт."
        ;;
    esac

    echo
    read -rp "Нажмите Enter для продолжения..."
  done
}

show_logs() {
  local service
  printf '\n1) Все сервисы\n2) API/backend\n3) Caddy\n4) XrayCore\n5) OLCRTC\n0) Назад\n\n'
  read -r -p "Выберите логи: " choice

  case "$choice" in
    1) docker compose logs -f --tail=150 ;;
    2) service="$(find_service 'api|backend')" ;;
    3) service="$(find_service caddy)" ;;
    4) service="$(find_service xray)" ;;
    5) service="$(find_service olcrtc)" ;;
    0) return 0 ;;
    *) warn "Неверный пункт."; return 0 ;;
  esac

  [[ "$choice" == 1 ]] && return 0
  [[ -n "${service:-}" ]] || { warn "Сервис не найден."; return 1; }
  docker compose logs -f --tail=150 "$service"
}

print_menu() {
  clear
  printf '%s%sOLCWave Manager%s\n' "$BOLD" "$GREEN" "$RESET"
  printf 'Каталог: %s\n\n' "$APP_DIR"
  printf '  1) Статус контейнеров\n'
  printf '  2) Обновить панель из GitHub\n'
  printf '  3) Перезапустить все сервисы\n'
  printf '  4) Перезапустить API/backend\n'
  printf '  5) Перезапустить XrayCore\n'
  printf '  6) Перезапустить OLCRTC\n'
  printf '  7) Управление Caddy\n'
  printf '  8) Посмотреть логи\n'
  printf '  0) Выход\n\n'
}

main() {
  check_installation

  while true; do
    print_menu
    read -r -p "Выберите пункт: " choice
    printf '\n'

    case "$choice" in
      1) show_status; pause ;;
      2) update_panel; pause ;;
      3) restart_all; pause ;;
      4) restart_service "API/backend" 'api|backend'; pause ;;
      5) restart_service "XrayCore" 'xray'; pause ;;
      6) restart_service "OLCRTC" 'olcrtc'; pause ;;
      7) caddy_menu; pause ;;
      8) show_logs || true; pause ;;
      0) exit 0 ;;
      *) warn "Неверный пункт."; sleep 1 ;;
    esac
  done
}

main "$@"