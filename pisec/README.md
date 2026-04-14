# 📜 Писец — централизованный логгер всех воркфлоу

> Инфраструктурный воркфлоу. Не выполняет бизнес-логику —  
> собирает логи со всех остальных воркфлоу в одном месте.

---

## Зачем нужен

В продакшн-среде с десятками воркфлоу нужно знать: что запустилось, что упало, когда и с какой ошибкой. Писец решает это централизованно — каждый воркфлоу вызывает его в конце работы, и все логи оседают в одной таблице Supabase.

Дополнительно Писец умеет:
- перехватывать **необработанные ошибки** любого воркфлоу и слать алерт в Telegram
- делать **ежедневный бэкап** базы Supabase через pg_dump по SSH
- принимать файлы от внешних клиентов и **загружать их в Supabase Storage**

---

## Архитектура: четыре независимых ветки

```
┌─────────────────────────────────────────────────────────┐
│  ВЕТКА 1 — Штатное логирование                          │
│                                                         │
│  Execute Workflow Trigger                               │
│  ← вызов из любого воркфлоу через "Execute Workflow"    │
│  → Supabase Insert → таблица workflow_logs              │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ВЕТКА 2 — Перехват ошибок                              │
│                                                         │
│  Error Trigger                                          │
│  ← автоматически при любой необработанной ошибке        │
│  → Supabase Insert Error (статус = error)               │
│  → Telegram-алерт: имя воркфлоу + текст ошибки         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ВЕТКА 3 — Ежедневный бэкап базы                        │
│                                                         │
│  Schedule Trigger (03:00 каждую ночь)                   │
│  → Set Filename (имя файла с датой и временем)          │
│  → SSH: pg_dump на сервере → файл .dump                 │
│  → Проверка результата (__SUCCESS__ / __FAILED__)       │
│  → Supabase Insert: лог бэкапа                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  ВЕТКА 4 — Загрузка файлов в Storage                    │
│                                                         │
│  Webhook POST /upload-from-claude                       │
│  → Extract Params (filename, content, bucket, label)    │
│  → Convert to Binary                                    │
│  → HTTP Upload → Supabase Storage                       │
│  → Respond to Webhook (JSON: статус + URL файла)        │
│  → Supabase Insert: лог загрузки                        │
└─────────────────────────────────────────────────────────┘
```

---

## Технический стек

| Компонент | Решение |
|-----------|---------|
| Платформа | n8n (self-hosted) |
| БД логов | Supabase, таблица `workflow_logs` |
| Бэкап | pg_dump через SSH, файл `.dump` на сервере |
| Алерты | Telegram Bot API |
| Файловое хранилище | Supabase Storage |
| Конфиденциальные данные | Через env-переменные n8n (не хранятся в JSON) |

---

## Узлы (17 нод)

| Нода | Тип | Назначение |
|------|-----|-----------|
| Error Trigger | Триггер | Перехват необработанных ошибок |
| Supabase Insert Error | Supabase | Запись ошибки в `workflow_logs` |
| Send a text message | Telegram | Алерт об ошибке в Telegram |
| Execute Workflow Trigger | Триггер | Приём штатных логов от воркфлоу |
| Supabase Insert | Supabase | Запись штатного лога |
| Schedule | Триггер | Запуск бэкапа в 03:00 |
| Set Filename | Set | Генерация имени файла `backup_YYYY-MM-DD_HHmm.dump` |
| Run pg_dump via SSH | SSH | Выполнение дампа на сервере |
| Set Status | Set | Парсинг результата (`__SUCCESS__` / `__FAILED__`) |
| Log to Supabase | Supabase | Лог результата бэкапа |
| Webhook | Webhook | Приём файлов POST /upload-from-claude |
| Extract Params | Set | Извлечение filename, content, bucket, label |
| Convert to Binary | Convert | Подготовка файла к загрузке |
| Upload to Supabase Storage | HTTP | Загрузка файла через Storage API |
| Build Response | Set | Формирование JSON-ответа с URL файла |
| Respond to Webhook | Webhook | Отправка ответа клиенту |
| Log to Supabase (upload) | Supabase | Лог факта загрузки |

---

## Схема таблицы `workflow_logs`

```sql
CREATE TABLE workflow_logs (
  id            bigserial PRIMARY KEY,
  created_at    timestamptz DEFAULT now(),
  workflow_name text,
  workflow_id   text,
  execution_id  text,
  node_name     text,
  status        text,        -- 'success' | 'error'
  items_count   integer,
  input_data    jsonb,
  output_data   jsonb,
  error_message text,
  duration_ms   integer
);
```

---

## Как вызвать Писца из другого воркфлоу

В финальном узле добавь ноду **Execute Workflow**, укажи Писца и передай:

```json
{
  "workflow_name": "имя_воркфлоу",
  "workflow_id":   "{{ $workflow.id }}",
  "execution_id":  "{{ $execution.id }}",
  "node_name":     "название_узла",
  "status":        "success",
  "items_count":   10,
  "output_data":   {}
}
```

Ошибки перехватывать вручную не нужно — Error Trigger делает это автоматически для всех воркфлоу.

---

## Настройка после импорта

В JSON заменены на плейсхолдеры — подставь свои значения:

| Плейсхолдер | Где найти | Нода |
|-------------|-----------|------|
| `YOUR_TELEGRAM_CHAT_ID` | Узнать через [@userinfobot](https://t.me/userinfobot) | Send a text message |
| `YOUR_SUPABASE_PROJECT_REF` | Supabase Dashboard → Settings → General | Upload to Supabase Storage, Build Response |

---

## Переменные окружения n8n

Настраиваются в **Settings → Environment variables**:

| Переменная | Что содержит |
|------------|-------------|
| `SUPABASE_DB_CONN` | Connection string PostgreSQL для pg_dump |
| `SUPABASE_SERVICE_KEY` | Service Role Key для Supabase Storage API |

---

## Требования для запуска

- n8n (self-hosted)
- Supabase (таблица `workflow_logs`, Storage bucket)
- SSH-доступ к серверу с установленным `pg_dump`
- Telegram Bot Token для алертов

---

## Файлы

```
pisec/
├── README.md                  ← этот файл
├── Pisec_Log_Workflows.json   ← воркфлоу для импорта в n8n
└── screenshot.png             ← схема воркфлоу
```

---

## Порядок установки

1. Создать таблицу `workflow_logs` в Supabase (DDL выше)
2. Настроить env-переменные: `SUPABASE_DB_CONN`, `SUPABASE_SERVICE_KEY`
3. Импортировать: **Settings → Import workflow → `Pisec_Log_Workflows.json`**
4. Заменить плейсхолдеры в нодах (см. таблицу выше)
5. Настроить credentials: Supabase, Telegram, SSH
6. **Активировать первым** — до импорта остальных воркфлоу

---

## Автор

**Алексей Борисов** — предприниматель, преподаватель, разработчик.

233 сессии (4 757+ ак. часов) для 59 организаций: Госдума, ЦБ, Минфин, Минэк, ЛУКОЙЛ, Сколково, Финуниверситет, ВАВТ.
81 авторская программа: Excel, ИИ и нейросети, Power BI, n8n, Р7-Офис.
MOS Expert (Excel 2019 — 1 000/1 000).

🌐 [aborisov.pro/automation](https://aborisov.pro/automation)
🎓 [borisov.academy](https://borisov.academy)
💬 [t.me/borisov_alexey_v](https://t.me/borisov_alexey_v)

