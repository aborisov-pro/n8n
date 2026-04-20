# Экспорт и «санитизация» workflow перед коммитом

Цель: хранить в репо **переносимые** JSON-экспорты, которые нормально импортируются в *любой* инстанс n8n.

## Как экспортировать

1. В n8n открой workflow.
2. Сделай экспорт в JSON (Download).
3. Сохрани файл в нужную папку воркфлоу (например `zorka/Zorka_Collect_News.json`).

## Что нужно убрать из экспортов

Перед коммитом в репо JSON должен быть нейтральным:

- `"active": false`
- без `webhookId` у нод
- без `id` у нод
- без `credentials.*.id` (оставляем только `name`)
- без `versionId`, `meta` и прочих instance-specific полей
- без `settings.errorWorkflow` (это ссылка на другой workflow в конкретной инстанции)

## Автоматическая санитизация

В репо есть скрипт:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts\sanitize_workflows.ps1
```

Он пройдётся по всем `*.json`, **пропуская** намеренно пустые заглушки:

- `pisec/Pisec_Log_Workflows.json`
- `voron/Voron_Check_RSS.json`
- `pozdravlyator/Pozdravlyator_Generate_Greeting.json`

## Проверки в CI

GitHub Actions на `push`/`PR` валидирует:

- JSON не битый
- похоже на n8n workflow (`name`, `nodes`, `connections`)
- нет instance-specific полей (см. выше)

## Скриншоты

Если добавляешь/обновляешь `screenshot.*`, предпочитай `screenshot.webp` вместо PNG (обычно заметно меньше вес).
