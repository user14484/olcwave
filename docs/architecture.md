# Архитектура

Как части системы взаимодействуют между собой и что фактически происходит при каждом запросе.

## Компоненты

| Компонент     | Контейнер                                     | Назначение                                                                                          |
| ------------- | --------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Frontend      | (нет - статические файлы обслуживаются Caddy) | React SPA, административный интерфейс                                                               |
| Backend       | `olcwave-api`                                 | FastAPI. Вся логика. Взаимодействует с Postgres, Remnawave и Docker socket.                         |
| Database      | `olcwave-postgres`                            | PostgreSQL 16. Пользователи + профили + счетчики трафика + routing-конфигурация.                     |
| Reverse proxy | `olcwave-caddy`                               | Обслуживает SPA, проксирует API, завершает HTTPS.                                                   |
| OLCRTC        | `olcwave-<tag>-<uuid>`                        | Один на пару (профиль, пользователь). Фактический transport + SOCKS proxy, записывающий статистику. |
| XrayCore      | `olcwave-xraycore`                            | Контейнер с Xray-core. Маршрутизирует трафик OLCRTC через внешние прокси (опционально).             |

API-контейнер монтирует `/var/run/docker.sock`, поэтому он напрямую управляет Docker daemon хоста - именно так он собирает образ `olcrtc` и запускает/останавливает OLCRTC-контейнеры.

## Основной поток: запрос подписки

Когда клиент обращается к:

```
GET /sub/{short_uuid}
```

(`Subscriptions.get`):

```
1. Запросить Remnawave: является ли этот short_uuid действительным?
      └─ нет  → 404, ничего не происходит.
      └─ да   → продолжить.

2. Есть ли для него локальная запись пользователя?
      └─ нет  → создать одну (срок действия из Remnawave, лимит трафика по умолчанию).

3. Проверить трафик:
      └─ превышен → вернуть placeholder-конфигурацию "Traffic limit Exceeded", HTTP 403.

4. Какие контейнеры этого пользователя уже запущены?
      └─ прочитать их текущий config.yaml.

5. Для каждого профиля, для которого еще нет контейнера этого пользователя:
      └─ сгенерировать новый config (случайный crypto.key, имя комнаты)
      └─ запустить новый контейнер olcwave-<tag>-<short_uuid>

6. Создать OLCBox конфиг из конфигурации каждого профиля и вернуть его.
```

Таким образом, при первом открытии пользователем своей ссылки его контейнеры запускаются по требованию. Последующие запросы используют уже запущенные контейнеры.

```
Client ──GET /sub/{uuid}──► Backend ──validate──► Remnawave
                               │
                               ├─ ensure local user row (Postgres)
                               ├─ check traffic (Postgres)
                               ├─ for each missing profile:
                               │      generate config → docker run
                               └─ return OLCBox bundle
```

Если routing включён, OLCRTC-контейнеры направляют свой исходящий трафик через `olcwave-xraycore`:

```
OLCRTC ──socks5:10808──► olcwave-xraycore ──► proxy/direct/block
```

Подробнее о routing см. [routing.md](routing.md).

### Форматы вывода подписки

Код может отображать конфигурации так:

* **Sub.md `olcrtc://` URI** (`config_to_uri`) - однострочные URI, используемые для создания текста подписки с заголовками `#name` / `##icon`.

## Контейнеры

### Жизненный цикл

Панель управляет контейнерами через Docker SDK:

`backend/src/olcrtc/sdk.py`

Страница Containers в UI предоставляет запуск/остановку/перезапуск, логи, конфигурацию и live-статистику каждого контейнера (общий объем, входящие/исходящие байты, скорость загрузки/выгрузки, время работы), сгруппированные по пользователю или по config tag.

### Что находится внутри OLCRTC-контейнера

Собирается из `backend/olcrtc/Dockerfile`. Два процесса, запускаемые через `entrypoint.sh`:

1. **olcrtc** - клонируется и собирается из upstream-репозитория [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc). Запускается с `/tmp/olcwave/config.yaml`.
2. **proxy** - небольшой Go SOCKS5 proxy (`proxy.go`). OLCRTC подключается к нему через добавленный блок `socks:`. Каждый байт через proxy подсчитывается и раз в секунду записывается в `stats.json` (атомарная запись).

Entry point записывает переменную окружения `CONFIG` в `config.yaml`, добавляет блок `socks:`, запускает proxy, затем запускает olcrtc и завершает proxy после выхода olcrtc.

## Система трафика

Трафик измеряется SOCKS proxy и агрегируется backend.

### Внутри контейнера: `stats.json`

`proxy.go` оборачивает каждое принятое соединение в counting reader/writer. Он периодически записывает `/var/lib/olcwave/stats.json`:

```json
{
  "upload_bytes": 12345,
  "download_bytes": 67890,
  "total_bytes": 80235,
  "upload_rate_bps": 1024,
  "download_rate_bps": 4096,
  "connections_open": 2,
  "connections_total": 40,
  "started_at": "...",
  "updated_at": "..."
}
```

`total_bytes` = upload + download. Это значение сбрасывается в 0 при каждом перезапуске контейнера.

### В backend: цикл сбора данных

`TrafficManager` запускается в FastAPI lifespan каждые `TRAFFIC_COLLECT_INTERVAL` секунд:

1. Для каждого работающего контейнера `olcwave-*` прочитать `stats.json` и получить `total_bytes`.
2. Вычислить **delta** с момента последнего тика. (Если счетчик уменьшился - контейнер был перезапущен - новый total считается delta, чтобы рестарты не приводили к недоучету.)
3. Добавить delta к `traffic_used_bytes` владельца пользователя в Postgres. Владелец определяется из имени контейнера (`olcwave-<tag>-<owner>`).
4. Если пользователь теперь превысил свой лимит, **остановить все контейнеры этого пользователя**.

Забытые контейнеры (которых больше не существует) удаляются из внутренней карты "last totals", чтобы будущий контейнер с таким же именем начинал учет с чистого состояния.

### Контроль ограничений

* **Превышение лимита** → цикл останавливает контейнеры пользователя. Попытка запустить контейнер для пользователя с превышенным лимитом через `POST /containers/run` возвращает `403 traffic_limit_exceeded`.
* **Подписка при превышенном лимите** → `GET /sub/{uuid}` возвращает placeholder-конфигурацию с именем "Traffic limit Exceeded" и HTTP 403, поэтому клиент видит причину вместо неработающего подключения.

### Поля лимитов

Для пользователя (см. `TrafficInfoSchema`):

* `limit` - `traffic_limit_bytes`; `0` = безлимит.
* `used` - `traffic_used_bytes`.
* `remaining` - `max(0, limit - used)` (0 при безлимитном режиме).
* `unlimited` - `limit == 0`.
* `exceeded` - не безлимитный **и** `used >= limit`.

### Сброс

`POST /users/traffic/reset` (кнопка в модальном окне редактирования пользователя) устанавливает `traffic_used_bytes` обратно в 0. Вместе с изменением лимита или срока действия это используется для "продления" пользователя. Обратите внимание: счетчик внутри контейнера не сбрасывается - логика delta обработает это при следующем тике.

## Routing

Routing - опциональная функция, маршрутизирующая трафик OLCRTC-контейнеров через внешние прокси. Подробное описание см. в [routing.md](routing.md).

### Компоненты

* **XrayCore** (`backend/xray_core/sdk.py`) - Docker SDK wrapper для контейнера `olcwave-xraycore`. Управляет запуском/остановкой Xray-core.
* **Routing service** (`backend/src/routing/service.py`) - бизнес-логика: сборка полной конфигурации Xray из пользовательского JSON (добавление `dns` и `inbounds`), управление записью в БД, перезапуск контейнеров.
* **Routing DB** (`backend/src/routing/db.py`) - хранение конфигурации в таблице `routing` (одна запись `id=1`).
* **Routing router** (`backend/src/routing/router.py`) - API-эндпоинты `/api/routing/*`.

### При включении routing

1. Backend собирает полную Xray-конфигурацию из JSON пользователя.
2. Запускается контейнер `olcwave-xraycore` на порту `10808`.
3. Все OLCRTC-контейнеры перезапускаются с `UPSTREAM_SOCKS=host.docker.internal:10808`.
4. В `RuntimeSettings` устанавливается `xray_routing_enabled=True`.

### При отключении routing

1. Контейнер `olcwave-xraycore` останавливается.
2. Все OLCRTC-контейнеры перезапускаются без `UPSTREAM_SOCKS`.
3. В `RuntimeSettings` устанавливается `xray_routing_enabled=False`.

## Caddy

Caddy - единственный компонент, доступный из интернета. Он выполняет три задачи из `caddy/Caddyfile`:

```caddyfile
panel.example.org {
    handle_path /api/* {
        reverse_proxy api:8000          # API traffic → backend, /api stripped
    }
    handle {
        root * /srv/frontend/dist        # everything else → the SPA
        try_files {path} /index.html
        file_server
    }
}

olcsub.example.org {
    handle {
        rewrite * /sub{uri}              # olcsub.example.org/<uuid>
        reverse_proxy olcwave.example.org  #   → olcwave.example.org/sub/<uuid>
    }
}
```

* **reverse_proxy** - пересылает запросы в сервис `api` (`api:8000`) внутри Compose network. `handle_path` удаляет префикс `/api`, поэтому браузер вызывает `https://panel.example.org/api/auth/login`, а backend получает `/auth/login`. Поэтому `VITE_API_URL` заканчивается на `/api`. Frontend `dist` монтируется только для чтения в контейнер Caddy по пути `/srv/frontend/dist`.
* **HTTPS / certificates / SSL** - Caddy автоматически получает и обновляет сертификаты Let's Encrypt для любого настроенного реального домена. Compose-файл публикует порты **80** и **443**, которые ему необходимы; DNS домена должен указывать на сервер.
* **SPA routing** - `try_files {path} /index.html` позволяет клиентским маршрутам (например `/users`) загружать SPA вместо получения ошибки 404.

### Маршрутизация на подписочном домене

Подписочный домен (`olcsub.example.org`) обрабатывает три типа запросов:

```caddyfile
olcsub.example.org {
    @raw path_regexp raw ^/(?P<id>[^/]+)/raw$
    handle @raw {
        rewrite * /sub/{re.id}
        reverse_proxy api:8000
    }

    @browser header_regexp browser User-Agent (?i)^Mozilla/
    handle @browser {
        root * /srv/subscriptionPage/dist
        try_files {path} /index.html
        file_server
    }

    handle {
        rewrite * /sub{uri}
        reverse_proxy api:8000
    }
}
```

1. **`/{uuid}/raw`** — прямой доступ к raw-тексту подписки. Caddy реврайтит на `/sub/{uuid}` и проксирует в API
2. **`/{uuid}` с User-Agent `Mozilla/...`** — браузерный запрос. Caddy отдаёт статику `subscriptionPage/dist` (HTML-страница с инструкциями по установке). SPA-роутинг обеспечивается через `try_files`.
3. **`/{uuid}` без `Mozilla/`** — клиентский запрос (OLCBox). Реврайт на `/sub{uri}` и проксирование в API, возвращающий raw-подписку.

Статика subscription page монтируется в контейнер Caddy:

```yaml
volumes:
  - ./subscriptionPage/dist:/srv/subscriptionPage:ro
```

Подробнее о subscription page см. [subscription_page.md](subscription_page.md).

Для локальной настройки без сертификатов используйте обычный site block с портом (например, `:80 { ... }`) вместо домена, и Caddy будет обслуживать HTTP без сертификатов.
