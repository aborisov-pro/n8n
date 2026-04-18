# 🎙 Стенограф — Расшифровка лекций

> Загружает аудио с Яндекс Диска в S3, отправляет в СпичКит и собирает транскрипт в Supabase, склеивая части одной лекции в единый текст.

---

## Что делает

Стенограф — конвейер транскрибации длинных аудиозаписей (лекций, семинаров, вебинаров).

Файлы кладутся на Яндекс Диск в заранее подготовленном виде, предобработка делается отдельным Python-скриптом (см. раздел «Препроцессинг»). Воркфлоу обходит папку на Диске, определяет новые файлы по списку в Supabase, перекладывает их в S3-бакет Яндекс Клауда, отправляет на асинхронное распознавание в СпичКит и фиксирует `operation_id` в БД.

Вторая цепочка по расписанию опрашивает статус операций, забирает готовые транскрипты, обновляет записи и чистит S3. Если лекция была нарезана на части («_part1», «_part2», …), после готовности всех частей вызывается PL/pgSQL-функция `try_merge_lecture`, которая склеивает их в одну итоговую запись.

---

## Архитектура

```
┌─ Цепочка 1 — загрузка и отправка (Manual) ─────────────────┐
│                                                            │
│  Manual Trigger                                            │
│    → Set: Config                                           │
│    → List Disk Files (Яндекс Диск API)                     │
│    → Get Existing Paths (Supabase)                         │
│    → Filter New Files                                      │
│    → Check S3 Exists                                       │
│    → IF S3 Exists?                                         │
│        true  → Merge Branches                              │
│        false → Get Download URL                            │
│                → Download File                             │
│                → Upload to S3                              │
│                → Merge Branches                            │
│    → Submit to SpeechKit (longRunningRecognize)            │
│    → Save to Supabase (status=processing)                  │
│                                                            │
└────────────────────────────────────────────────────────────┘

┌─ Цепочка 2 — опрос и финализация (Schedule 50 мин) ────────┐
│                                                            │
│  Schedule Trigger                                          │
│    → Set: Config (Schedule)                                │
│    → Get Processing Records                                │
│    → Check Operation Status                                │
│    → Is Done?                                              │
│        → Has Error?                                        │
│            true  → Update Error (status=error)             │
│            false → Extract Transcript                      │
│                    → Update Done (status=done)             │
│                    → Delete from S3                        │
│                    → Try Merge (RPC try_merge_lecture)     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Технический стек

| Компонент | Решение |
|-----------|---------|
| Платформа | n8n (self-hosted) |
| Источник файлов | Яндекс Диск REST API |
| Объектное хранилище | Яндекс Клауд Object Storage (S3-совместимое) |
| Распознавание речи | Яндекс СпичКит, `longRunningRecognize`, модель `deferred-general` |
| БД и учёт задач | Supabase (PostgreSQL + REST) |
| Склейка частей | PL/pgSQL функция `try_merge_lecture` |
| Препроцессинг | Python 3 + FFmpeg (`merge_by_cluster.py`) |

---

## Узлы (24 ноды)

| Нода | Тип | Назначение |
|------|-----|-----------|
| Manual Trigger | Manual | Ручной запуск цепочки загрузки |
| Set: Config | Set | Параметры bucket и папки на Диске |
| List Disk Files | HTTP Request | Получить список аудиофайлов в папке на Яндекс Диске |
| Get Existing Paths | HTTP Request | Получить уже обработанные пути из Supabase |
| Filter New Files | Code | Отсев уже обработанных, парсинг `_partN.mp3` в `lecture_base` и `part_index` |
| Check S3 Exists | HTTP Request | HEAD-запрос: есть ли файл уже в бакете |
| IF S3 Exists | IF | Ветвление: грузить файл в S3 или пропустить |
| Get Download URL | HTTP Request | Запрос временной ссылки на скачивание с Диска |
| Download File | HTTP Request | Скачивание бинарника |
| Upload to S3 | S3 | Загрузка в Яндекс Object Storage с ACL `publicRead` |
| Merge Branches | Merge | Сведение ветвей «уже в S3» и «только что загружено» |
| Submit to SpeechKit | HTTP Request | Отправка на `longRunningRecognize`, ру-распознавание MP3 |
| Save to Supabase | Supabase | Создание записи со статусом `processing` и `operation_id` |
| Schedule Trigger | Schedule | Запуск опроса каждые 50 минут |
| Set: Config (Schedule) | Set | Bucket для Delete from S3 |
| Get Processing Records | Supabase | Выборка записей в статусе `processing` |
| Check Operation Status | HTTP Request | Опрос операции СпичКит по `operation_id` |
| Is Done? | IF | Завершена ли операция |
| Has Error? | IF | Есть ли поле `error` в ответе |
| Extract Transcript | Code | Склейка `chunks[].alternatives[0].text` в единый текст |
| Update Done | Supabase | Сохранение транскрипта, статус `done` |
| Delete from S3 | S3 | Удаление аудио из бакета (больше не нужно) |
| Try Merge | HTTP Request | Вызов RPC `try_merge_lecture` для склейки частей лекции |
| Update Error | Supabase | Запись сообщения об ошибке и статуса `error` |

---

## Особенности реализации

▪ **Две независимые цепочки** — ручной запуск отправляет, планировщик финализирует. Разведение по триггерам убирает блокировки: распознавание идёт часами, а n8n за это время успевает обслуживать другие воркфлоу.
▪ **Дедупликация на входе** — перед отправкой воркфлоу запрашивает у Supabase все `disk_path` со статусами `done`, `processing`, `merged` и исключает их. Повторный запуск на той же папке безопасен.
▪ **Идемпотентность S3-загрузки** — `Check S3 Exists` делает HEAD-запрос, и если объект в бакете уже лежит, скачивание и перезалив пропускаются. Восстановление после сбоя не дублирует трафик.
▪ **Нарезка по частям** — файлы с суффиксом `_partN.mp3` автоматически относятся к одной лекции через `lecture_base`. Порог 3 ч 50 мин в препроцессоре подогнан под лимит Яндекс СпичКит на одну операцию (4 часа).
▪ **Атомарная склейка через RPC** — после каждой готовой части вызывается `try_merge_lecture`. Функция проверяет, все ли части лекции в статусе `done`, склеивает транскрипты в порядке `part_index` и удаляет промежуточные строки, оставляя одну финальную со статусом `merged`.
▪ **Чистка S3 после `done`** — файл удаляется из бакета сразу после сохранения транскрипта. Бакет не разрастается, трафик СпичКит на этот файл уже не нужен.

---

## Необходимые credentials

| Credential | Назначение | Нода |
|------------|-----------|------|
| HTTP Header Auth (Яндекс Диск) | `Authorization: OAuth <token>` для доступа к Диску | List Disk Files, Get Download URL |
| HTTP Header Auth (Яндекс СпичКит) | `Authorization: Api-Key <key>` для distance-распознавания | Submit to SpeechKit, Check Operation Status |
| S3 (Яндекс Object Storage) | Static access key + secret, endpoint `storage.yandexcloud.net` | Upload to S3, Delete from S3 |
| Supabase API | URL проекта + `service_role` ключ | Get Existing Paths, Save to Supabase, Get Processing Records, Update Done, Update Error, Try Merge |

### Настройка после импорта

| Плейсхолдер | Где заменить | На что |
|-------------|--------------|--------|
| `YOUR_S3_BUCKET` | ноды `Set: Config`, `Set: Config (Schedule)` | Имя вашего бакета в Object Storage |
| `/YOUR_DISK_FOLDER/merged` | нода `Set: Config`, поле `disk_folder` | Путь к папке с готовыми MP3 на Яндекс Диске |
| `YOUR_SUPABASE_URL` | ноды `Get Existing Paths`, `Try Merge` (URL) | Хост вашего Supabase-проекта |

---

## Препроцессинг (merge_by_cluster.py)

Отдельный Python-скрипт для подготовки файлов до загрузки на Диск. Читает xlsx-маппинг «Файл ↔ Последовательность ↔ Кластер», склеивает каждый кластер через FFmpeg в единый MP3 с параметрами под Яндекс СпичКит.

▪ **Формат на выходе** — mono, 16 kHz, 64 kbps MP3. Минимальный размер при сохранении разборчивости.
▪ **Нарезка на 3 ч 50 мин** — если склеенная лекция длиннее лимита СпичКит (4 часа), FFmpeg автоматически режет её сегмент-муксером на `_part1`, `_part2`, …
▪ **Срез тишины** — `silenceremove=stop_periods=-1:stop_duration=2:stop_threshold=-40dB` убирает паузы длиннее 2 секунд.
▪ **Нормализация громкости** — `loudnorm=I=-16:TP=-1.5:LRA=11` выравнивает громкость под стандарт вещания.
▪ **Транслитерация имён** — кластер «ПауэрКвери вебинар» → `Power_Query_webinar.mp3`, чтобы S3-ключи были чистыми.
▪ **Идемпотентность** — если на выходе уже лежит файл с таким базовым именем, кластер пропускается.

Запуск:

```bash
pip install openpyxl
# ffmpeg должен быть в PATH

python merge_by_cluster.py \
  --folder "путь/к/папке/с/источниками" \
  --mapping "путь/к/Распределение файлов.xlsx" \
  --out    "путь/к/папке/вывода"
```

Флаги: `--dry-run`, `--no-silence-remove`, `--no-loudnorm`, `--bitrate`, `--sample-rate`, `--jobs`. Готовые файлы из `--out` загружаются на Яндекс Диск в папку, указанную в `Set: Config.disk_folder`.

---

## Схема Supabase

### Таблица `lectures_transcripts`

| Колонка | Тип | Назначение |
|---------|-----|-----------|
| `id` | uuid | Первичный ключ |
| `disk_path` | text | Путь файла на Яндекс Диске. После склейки заменяется на `lecture_base` |
| `file_name` | text | Имя исходного mp3 |
| `s3_key` | text | Ключ объекта в бакете |
| `operation_id` | text | ID долгоживущей операции СпичКит |
| `status` | text | `pending` → `processing` → `done` → `merged` (или `error`) |
| `transcript` | text | Транскрипт части (до склейки) |
| `merged_transcript` | text | Итоговый склеенный транскрипт лекции |
| `error_msg` | text | Текст ошибки от СпичКит |
| `lecture_base` | text | Базовое имя лекции без `_partN` |
| `part_index` | integer | Порядок части в лекции |
| `parts_count` | integer | Сколько частей было склеено |

### RPC `try_merge_lecture(p_base text)`

Атомарно собирает все части лекции с указанным `lecture_base` в одну строку. Возвращает `(merged, parts, lecture_id)`. Идемпотентна: повторный вызов на уже склеенной лекции просто вернёт существующий `id`.

Схема и функция разворачиваются одним прогоном файла `supabase.sql`.

---

## Файлы

```
stenograf/
├── README.md                              ← этот файл
├── Stenograf_Lectures_Transcription.json  ← воркфлоу для импорта в n8n
├── supabase.sql                           ← таблица и RPC для Supabase
└── merge_by_cluster.py                    ← препроцессинг аудио перед загрузкой
```

---

## Порядок установки

1. Применить `supabase.sql` в вашем проекте Supabase (SQL Editor или psql). Создаст таблицу и RPC.
2. Создать бакет в Яндекс Object Storage. Сгенерировать статический ключ доступа.
3. Получить OAuth-токен Яндекс Диска и API-ключ Яндекс СпичКит.
4. В n8n завести четыре credential из таблицы выше.
5. Импортировать: **Settings → Import workflow → `Stenograf_Lectures_Transcription.json`**.
6. Заменить плейсхолдеры `YOUR_S3_BUCKET`, `/YOUR_DISK_FOLDER/merged`, `YOUR_SUPABASE_URL` в соответствующих нодах.
7. Привязать credentials к нодам HTTP Request, S3 и Supabase.
8. Активировать воркфлоу. Первый запуск — вручную через Manual Trigger на одном файле для проверки.

---

## Автор

**Алексей Борисов** — предприниматель, преподаватель, разработчик.

233 сессии (4 757+ ак. часов) в 17 городах для 59 организаций: Госдума, ЦБ, Минфин, Минэк, ЛУКОЙЛ, Сколково, Финуниверситет, ВАВТ.
39 выступлений. 81 авторская программа: Excel, ИИ и нейросети, Power BI, n8n, Р7-Офис.
MOS Expert (Excel 2019 — 1 000/1 000).

🌐 [aborisov.pro/automation](https://aborisov.pro/automation)
🎓 [borisov.academy](https://borisov.academy)
💬 [t.me/borisov_alexey_v](https://t.me/borisov_alexey_v)
