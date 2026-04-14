# 🌅 Зорька — Ежедневный утренний дайджест

> Отправляет в 7:00 персональную сводку: погода, новости России, YouTube без повторов, письма Gmail, спорт и мониторинг ИИ-форумов.

---

## Что делает

Зорька — утренний Телеграм-бот, который собирает всё важное за ночь и присылает сводку к началу дня.

В 7:00 по расписанию (или по команде из Телеграма) бот параллельно запускает шесть независимых веток: погода от двух источников с ИИ-интерпретацией, топ новостей России из RSS с ИИ-пересказом, новое видео с YouTube (Redis исключает уже виденные), дайджест входящих писем Gmail, спортивные результаты с ИИ-комментарием и мониторинг форумов по ИИ-тематике.

Каждый блок отправляет своё сообщение в Телеграм независимо и логирует результат через Писец. Если по какому-то блоку нет новых данных — он молча пропускается.

---

## Архитектура

```
Schedule 7:00 / Telegram Trigger
  → Кнопка? → Меню (Телеграм)
  → Роутер
      ├── Погода
      │     OpenMeteo + OWM → Merge Weather
      │       → AI Погода (DeepSeek) → TG Погода → LOG
      ├── Новости России
      │     RSS Feeds List → Fetch RSS → Parse RSS
      │       → Новости России (DeepSeek) → Extract News → TG Новости → LOG
      ├── YouTube
      │     YouTube Search → Redis GET seen → Pick Video
      │       → Redis SET seen
      ├── Спорт
      │     Redis GET спорт → Parse Last Sport
      │       → AI Спорт (DeepSeek) → Format Sport → Redis SET спорт
      │         → TG Спорт → LOG
      ├── Gmail
      │     Gmail → Extract Emails
      │       → AI Gmail (DeepSeek) → Format Gmail → TG Gmail → LOG
      └── Форумы (ИИ-тематика)
            Forum GNews Feeds + Forum Yandex Queries
              → Fetch (GNews + Yandex) → Parse → Forum Merge
                → Forum Redis Get → Forum Dedup
                  → Forum: есть? → Forum Aggregate
                    → AI Фильтр форумов (DeepSeek) → Forum Build Lines
                      → TG Форумы → Forum Extract URLs → Forum Redis Set → LOG
```

---

## Технический стек

| Компонент | Решение |
|-----------|---------|
| Платформа | n8n (self-hosted) |
| Расписание | Schedule Trigger (07:00) |
| ИИ | ДипСик (LangChain LLM Chain) |
| Погода | OpenMeteo, OpenWeatherMap |
| Новости | RSS/Atom, GNews, Яндекс Поиск |
| Видео | YouTube Data API |
| Почта | Gmail |
| Дедупликация | Redis |
| Уведомления | Телеграм Bot API |
| Логирование | Писец (Execute Workflow) |

---

## Узлы (64 ноды)

| Нода | Тип | Назначение |
|------|-----|-----------|
| Schedule 7:00 | Schedule Trigger | Запуск дайджеста по расписанию |
| Telegram Trigger | Telegram | Ручной запуск из Телеграма |
| Кнопка? | IF | Проверка: запрос из Телеграм-меню или нет |
| Меню | Telegram | Отправка интерактивного меню |
| Роутер | Switch | Маршрутизация по блокам дайджеста |
| OpenMeteo | HTTP Request | Погода от OpenMeteo |
| OWM | OpenWeatherMap | Погода от OpenWeatherMap |
| Merge Weather | Merge | Объединение двух источников погоды |
| AI Погода | LLM Chain (DeepSeek) | ИИ-интерпретация погоды |
| TG Погода | Telegram | Отправка блока погоды |
| Set LOG Погода | Set | Подготовка данных для лога |
| LOG Погода | Execute Workflow | Логирование через Писец |
| RSS Feeds List | Code | Список RSS-лент новостей |
| Fetch RSS | HTTP Request | Загрузка RSS-лент |
| Parse RSS | Code | Парсинг XML и извлечение статей |
| Новости России | LLM Chain (DeepSeek) | ИИ-пересказ топ-новостей |
| Extract News | Code | Форматирование новостного блока |
| TG Новости | Telegram | Отправка блока новостей |
| Set LOG Новости | Set | Подготовка данных для лога |
| LOG Новости | Execute Workflow | Логирование через Писец |
| YouTube Search | HTTP Request | Поиск новых видео |
| Redis GET seen | Redis | Получение списка уже виденных видео |
| Pick Video | Code | Выбор нового видео (дедупликация) |
| Redis SET seen | Redis | Сохранение просмотренного видео |
| Redis GET спорт | Redis | Получение последних спортивных данных |
| Parse Last Sport | Code | Парсинг спортивных результатов |
| AI Спорт | LLM Chain (DeepSeek) | ИИ-комментарий к результатам |
| Format Sport | Code | Форматирование спортивного блока |
| Redis SET спорт | Redis | Сохранение спортивных данных в Redis |
| TG Спорт | Telegram | Отправка блока спорта |
| Set LOG Спорт | Set | Подготовка данных для лога |
| LOG Спорт | Execute Workflow | Логирование через Писец |
| Gmail | Gmail | Получение входящих писем |
| Extract Emails | Code | Извлечение и структурирование писем |
| AI Gmail | LLM Chain (DeepSeek) | ИИ-дайджест входящих |
| Format Gmail | Code | Форматирование почтового блока |
| TG Gmail | Telegram | Отправка блока Gmail |
| Set LOG Gmail | Set | Подготовка данных для лога |
| LOG Gmail | Execute Workflow | Логирование через Писец |
| Forum GNews Feeds | Code | Список GNews-запросов по ИИ-тематике |
| Forum Yandex Queries | Code | Список Яндекс-запросов по ИИ-тематике |
| Fetch Forum GNews | HTTP Request | Загрузка новостей из GNews |
| Fetch Forum Yandex | HTTP Request | Загрузка новостей из Яндекса |
| Parse Forum GNews | Code | Парсинг GNews-результатов |
| Parse Forum Yandex | Code | Парсинг Яндекс-результатов |
| Forum Merge | Merge | Объединение двух источников форумов |
| Forum Redis Get | Redis | Получение уже показанных URL |
| Forum Dedup | Code | Дедупликация по URL через Redis |
| Forum: есть? | IF | Проверка наличия новых материалов |
| Forum Aggregate | Code | Агрегация новых публикаций |
| AI Фильтр форумов | LLM Chain (DeepSeek) | ИИ-отбор релевантных материалов |
| Forum Build Lines | Code | Форматирование блока форумов |
| TG Форумы | Telegram | Отправка блока форумов |
| Forum Extract URLs | Code | Извлечение URL для дедупликации |
| Forum Redis Set | Redis | Сохранение показанных URL в Redis |
| Set LOG Форумы | Set | Подготовка данных для лога |
| LOG Форумы | Execute Workflow | Логирование через Писец |
| Code in JavaScript | Code | Вспомогательная обработка данных |
| Ожидание | Telegram | Сообщение об ожидании при ручном запуске |
| DeepSeek Chat Model (×4) | LM Chat DeepSeek | Языковая модель для LLM Chain |

---

## Логика ИИ

Каждый блок дайджеста использует отдельную ЛангЧейн-цепочку (LLM Chain) на базе ДипСика:

- **AI Погода** — сравнивает данные двух источников, даёт человекопонятный прогноз с советом по одежде
- **Новости России** — пересказывает топ-новости из RSS в 3–5 строках на каждую
- **AI Спорт** — комментирует результаты матчей, выделяет главное
- **AI Gmail** — суммирует входящие письма, выделяет требующие ответа
- **AI Фильтр форумов** — из общего потока отбирает только релевантные ИИ-тематике публикации

---

## Особенности реализации

- **Redis-дедупликация** — YouTube и форумы не повторяют уже показанные материалы; история хранится в Redis
- **Параллельные ветки** — все шесть блоков выполняются независимо; сбой одного не останавливает остальные
- **Двойной запуск** — по расписанию в 7:00 и вручную через Телеграм-меню
- **LLM Chain вместо агентов** — ИИ-обработка реализована через простые цепочки без инструментов, что делает воркфлоу стабильнее и предсказуемее
- **Логирование каждого блока** — каждая ветка передаёт результат в Писец через `Execute Workflow`

---

## Зависимость: Писец

Этот воркфлоу использует **[Писец](../pisec/)** — централизованный логгер.

| Вход Писца | Что происходит |
|------------|----------------|
| `Execute Workflow Trigger` | Штатный лог каждого блока → Supabase |
| `Error Trigger` | Перехват ошибок → Supabase + Телеграм-алерт |

> ⚠️ Импортируй и активируй Писца первым.

---

## Необходимые credentials

| Credential | Назначение | Нода |
|------------|-----------|------|
| Telegram Bot API | Приём команд и отправка всех блоков дайджеста | Telegram Trigger, Меню, TG Погода, TG Новости, TG Спорт, TG Gmail, TG Форумы, Ожидание |
| OpenWeatherMap API | Погода (второй источник) | OWM |
| Google Gmail OAuth2 | Чтение входящих писем | Gmail |
| YouTube Data API | Поиск видео | YouTube Search |
| Redis | Дедупликация YouTube и форумов | все Redis-ноды |
| DeepSeek API | Языковая модель для всех LLM Chain | все Chain-ноды |

### Настройка после импорта

| Плейсхолдер | Назначение | Нода |
|-------------|-----------|------|
| `YOUR_TELEGRAM_CHAT_ID` | ID чата для отправки дайджеста | TG Погода, TG Новости и др. |
| `YOUR_YOUTUBE_API_KEY` | API-ключ YouTube Data v3 | YouTube Search |
| `YOUR_YOUTUBE_CHANNEL_OR_QUERY` | Поисковый запрос для YouTube | YouTube Search |

---

## Файлы

```
zorka/
├── README.md                    ← этот файл
├── Zorka_Collect_News.json      ← воркфлоу для импорта в n8n
└── screenshot.png               ← схема воркфлоу
```

---

## Порядок установки

1. Импортировать и активировать **Писец**
2. Импортировать: **Settings → Import workflow → `Zorka_Collect_News.json`**
3. Настроить credentials: Telegram Bot API, OpenWeatherMap, Gmail OAuth2, YouTube Data API, DeepSeek API, Redis
4. Заменить плейсхолдеры `YOUR_TELEGRAM_CHAT_ID` и `YOUR_YOUTUBE_CHANNEL_OR_QUERY`
5. Активировать воркфлоу

---

## Автор

**Алексей Борисов** — предприниматель, преподаватель, разработчик.

233 сессии (4 757+ ак. часов) для 59 организаций: Госдума, ЦБ, Минфин, Минэк, ЛУКОЙЛ, Сколково, Финуниверситет, ВАВТ.
81 авторская программа: Excel, ИИ и нейросети, Power BI, n8n, Р7-Офис.
MOS Expert (Excel 2019 — 1 000/1 000).

🌐 [aborisov.pro/automation](https://aborisov.pro/automation)
🎓 [borisov.academy](https://borisov.academy)
💬 [t.me/borisov_alexey_v](https://t.me/borisov_alexey_v)

