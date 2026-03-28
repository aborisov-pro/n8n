# 🐦‍⬛ Ворон — Проверка здоровья RSS-лент

> Принимает список URL, проверяет каждый фид и возвращает отчёт: что живо, что упало и почему.

---

## Что делает

Ворон — инструмент мониторинга RSS и Atom лент.

Принимает список URL из чата или Telegram, загружает каждый фид, парсит XML и проверяет свежесть последней записи. Ленты старше 100 дней считаются проблемными. Итог — отчёт с двумя списками: рабочие и проблемные, с кодом причины для каждой.

---

## Структура воркфлоу

```
Chat Trigger / Telegram Trigger
  → Extract URLs from Text
  → Fetch RSS
  → Parse & Report
  → Is Telegram?
      true  → Send to Telegram
      false → Return Result
```

### Узлы (8 нод)

| Нода | Тип | Назначение |
|------|-----|-----------|
| When chat message received | Chat Trigger | Приём URL из чата n8n |
| Telegram Trigger | Telegram | Приём URL из Telegram |
| Extract URLs from Text | Code | Извлечение всех URL из сообщения |
| Fetch RSS | HTTP Request | Загрузка каждого фида (таймаут 15 с) |
| Parse & Report | Code | Парсинг XML, проверка даты, формирование отчёта |
| Is Telegram? | IF | Маршрутизация по источнику запроса |
| Send to Telegram | Telegram | Отправка отчёта обратно в Telegram |
| Return Result | Code | Возврат результата в чат n8n |

---

## Стек

| Компонент | Решение |
|-----------|---------|
| Платформа | n8n (self-hosted) |
| Парсинг | JavaScript (Code node), нативный XML |
| Уведомления | Telegram Bot API |
| Форматирование | HTML-теги Telegram (`<b>`, `&lt;`, `&gt;`) |

---

## Формат отчёта

```
✅ Рабочие (N)
✅ 3д — example.com/feed
✅ 12д — another.org/rss

❌ Проблемные (N)
❌ Таймаут — slow-site.net/feed
❌ 210д — stale-blog.com/rss.xml
❌ Cloudflare — blocked-source.com/feed
```

### Коды ошибок

| Код | Значение |
|-----|---------|
| `Таймаут` | Нет ответа за 15 секунд |
| `Cloudflare` | Доступ заблокирован |
| `Пусто` | Ответ короче 50 символов |
| `Нет записей` | Не найден `<item>` / `<entry>` |
| `Дата` | Поле даты отсутствует или не парсится |
| `Nд` | Лента не обновлялась N дней (> 100) |
| `4xx / 5xx` | HTTP-ошибка |

---

## Необходимые credentials

| Credential | Назначение | Нода |
|------------|-----------|------|
| Telegram Bot API | Приём сообщений и отправка отчёта | Telegram Trigger, Send to Telegram |

> В JSON credential-имя задано как **RSS check** — переименуй или создай с таким же именем.

---

## Файлы

```
voron/
├── README.md              ← этот файл
├── Voron_Check_RSS.json   ← воркфлоу для импорта в n8n
└── screenshot.png         ← схема воркфлоу
```

---

## Порядок установки

1. Импортировать: **Settings → Import workflow → `Voron_Check_RSS.json`**
2. Настроить credential **Telegram Bot API** (название: RSS check)
3. Активировать воркфлоу

---

## Автор

**Алексей Борисов** — предприниматель, преподаватель.

- 🌐 [aborisov.pro/automation](https://aborisov.pro/automation)
- 💬 [t.me/borisov_alexey_v](https://t.me/borisov_alexey_v)
