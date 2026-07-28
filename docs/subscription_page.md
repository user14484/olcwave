# Subscription Page

Одностраничное приложение, которое обслуживается Caddy по подписочному домену (`olcsub.example.org`) и показывает пользователям инструкции по установке OLCBox и добавлению подписки.

## Назначение

Когда пользователь открывает свою ссылку подписки в браузере (`https://olcsub.example.org/{uuid}`), вместо «голого» текста с конфигурациями он видит полноценную страницу с:

- кнопками скачивания OLCBox для Android / Windows / Linux
- пошаговой инструкцией по добавлению подписки
- ссылкой на подписку с кнопкой «Копировать»
- полезными советами по решению типичных проблем

## Стек

| Компонент | Технология |
| --- | --- |
| Framework | React 19 |
| Сборщик | Vite 8 |
| Стили | Tailwind CSS 4 (через Vite plugin) |
| Иконки | Heroicons 2 + собственные SVG для платформ |
| Язык | TypeScript 6 |

Сборка: `npm ci && npm run build` → `subscriptionPage/dist/`.

## Структура файлов

```
subscriptionPage/
├── src/
│   ├── App.tsx              # Основной компонент и все UI-секции
│   ├── main.tsx             # Точка входа, обёртка в LanguageProvider
│   ├── index.css            # Глобальные стили и CSS-анимации
│   ├── i18n/
│   │   ├── LanguageProvider.tsx  # React Context для языка
│   │   ├── useLanguage.ts       # Хук доступа к контексту
│   │   ├── en.ts                # Английские переводы
│   │   └── ru.ts                # Русские переводы
│   └── assets/icons/        # SVG-иконки платформ (android, windows, linux)
├── public/favicon.svg
├── index.html
├── package.json
├── vite.config.ts
├── tsconfig.json
└── tsconfig.tsbuildinfo
```

## Маршрутизация (Caddy)

Subscription page обслуживается Caddy на подписочном домене. Логика определяет тип клиента по User-Agent и URL:

```caddyfile
olcsub.example.org {
    # 1) Прямой доступ к rawData: /<id>/raw → API
    @raw path_regexp raw ^/(?P<id>[^/]+)/raw$
    handle @raw {
        rewrite * /sub/{re.id}
        reverse_proxy api:8000
    }

    # 2) Браузер (User-Agent содержит "Mozilla/") → SPA
    @browser header_regexp browser User-Agent (?i)^Mozilla/
    handle @browser {
        root * /srv/subscriptionPage/dist
        try_files {path} /index.html
        file_server
    }

    # 3) Всё остальное (клиентские приложения) → подписка в raw-формате
    handle {
        rewrite * /sub{uri}
        reverse_proxy api:8000
    }
}
```

### Порядок обработки

| Запрос | User-Agent | Маршрут | Результат |
| --- | --- | --- | --- |
| `/{uuid}/raw` | любой | `handle @raw` | Raw-текст подписки (для OLCBox и других клиентов) |
| `/{uuid}` | `Mozilla/...` (браузер) | `handle @browser` | HTML-страница subscriptionPage |
| `/{uuid}` | OLCBox / другой клиент | `handle` (fallback) | Raw-текст подписки через `GET /sub/{uuid}` |

Таким образом, один и тот же URL возвращает разный контент в зависимости от того, открывает ли его человек в браузере или клиентское приложение.

## UI-компоненты

Все компоненты определены в `App.tsx`:

### App

Корневой компонент. Определяет платформу и язык, управляет iOS-оверлеем.

### LanguageSwitcher

Фиксированная кнопка в правом верхнем углу для переключения EN/RU. Выбор сохраняется в `localStorage` (`olcwave-lang`). Язык определяется автоматически из `navigator.language`.

### IosOverlay

Полноэкранный оверлей, предупреждающий iOS-пользователей о том, что OLCBox пока не доступен для iOS. Содержит кнопку для просмотра инструкций несмотря на это.

### Hero

Заголовок страницы. Отображает имя провайдера (из заголовка `#name:` в raw-подписке) или «OLCWave» по умолчанию.

### DownloadSection

Секция скачивания OLCBox:

- автоопределение платформы пользователя (Android / Windows / Linux / macOS → Linux)
- выпадающий выбор платформы
- кнопка скачивания с прямой ссылкой на GitHub Release

### SubscribeSection

Пошаговая инструкция по добавлению подписки:

1. Откройте OLCBox
2. Нажмите «+» → «Введите ссылку»
3. Вставьте URL подписки

Отображает текущий URL страницы с кнопкой копирования.

### TipsSection

Блок полезных советов: что делать если подписка не загружается, соединение медленное, приложение показывает «expired», и куда обращаться за помощью.

## Интернационализация (i18n)

Система переводов построена на React Context:

- `LanguageProvider` — оборачивает приложение, хранит текущий язык в state и `localStorage`
- `useLanguage()` — хук, возвращает `{ language, setLanguage, t }`
- `t(key)` — функция перевода, подставляет текст из файла текущего языка
- Файлы переводов: `en.ts` (английский, базовый) и `ru.ts` (русский)
- Типизация: `TranslationKey` — общий тип ключей, `Translation` — `Record<TranslationKey, string>`

### Определение языка

1. Если в `localStorage` сохранён `olcwave-lang` → используется он
2. Если `navigator.language` начинается с `ru` → русский
3. По умолчанию → английский

## Интеграция с API

Страница извлекает `subId` из URL (`/^\/([^/]+)/`) и делает запрос к `/{subId}/raw` для получения имени провайдера из заголовка `#name:` первой строки raw-подписки. Это имя отображается в Hero и Footer.

## Сборка и деплой

### Локальная разработка

```bash
cd subscriptionPage
npm install
npm run dev    # http://localhost:5174
```

### Production

Сборка выполняется автоматически скриптом `install.sh` (шаг 5: `build_subscription_page`):

```bash
cd subscriptionPage
npm ci          # (или npm install, если нет package-lock.json)
npm run build
```

Результат — `subscriptionPage/dist/`, который монтируется в контейнер Caddy:

```yaml
# docker-compose.yaml
services:
  caddy:
    volumes:
      - ./subscriptionPage/dist:/srv/subscriptionPage:ro
```

### Добавление нового языка

1. Создайте файл `src/i18n/{lang}.ts`, импортируя тип `Translation` из `en.ts`
2. Добавьте все ключи перевода
3. В `LanguageProvider.tsx`:
   - добавьте импорт нового файла
   - расширьте тип `SupportedLanguage` на `'en' | 'ru' | '{lang}'`
   - добавьте запись в объект `translations`
4. В `LanguageSwitcher` добавьте новый код в массив `langs`

## Дизайн-система

Страница использует кастомную CSS-тему через переменные Tailwind:

| Переменная | Назначение |
| --- | --- |
| `--bg-primary` / `--bg-secondary` / `--bg-tertiary` | Фоны |
| `--text-primary` / `--text-secondary` / `--text-muted` | Текст |
| `--accent` / `--accent-hover` | Акцентный цвет |
| `--border` / `--border-light` | Границы |
| `--success` / `--danger` | Статусные цвета |

Анимации: `fade-in`, `scale-in`, `toast-in` — определены в `index.css` через `@keyframes`.
