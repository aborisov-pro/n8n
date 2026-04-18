-- ============================================================
-- Стенограф — схема Supabase
-- Таблица учёта задач транскрибации + RPC для склейки частей.
-- Применять через psql или Supabase Studio → SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Таблица lectures_transcripts
-- ------------------------------------------------------------
create table if not exists public.lectures_transcripts (
  id                uuid primary key default gen_random_uuid(),
  disk_path         text not null,
  file_name         text,
  s3_key            text,
  operation_id      text,
  status            text default 'pending',
  transcript        text,
  merged_transcript text,
  error_msg         text,
  lecture_base      text,
  part_index        integer default 1,
  parts_count       integer,
  submitted_at      timestamptz default now(),
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

comment on table  public.lectures_transcripts is 'Учёт задач транскрибации СпичКит: одна строка = один аудиофайл (или склеенная лекция).';
comment on column public.lectures_transcripts.disk_path         is 'Путь к исходному файлу на Яндекс Диске. Уникальный ключ для дедупликации.';
comment on column public.lectures_transcripts.s3_key            is 'Ключ объекта в S3-бакете (например, lectures/file_part1.mp3).';
comment on column public.lectures_transcripts.operation_id      is 'ID долгоживущей операции СпичКит.';
comment on column public.lectures_transcripts.status            is 'pending | processing | done | error | merged';
comment on column public.lectures_transcripts.lecture_base      is 'Базовое имя лекции без _partN. Объединяет части одной записи.';
comment on column public.lectures_transcripts.part_index        is 'Порядок части в исходной лекции (1, 2, 3…).';
comment on column public.lectures_transcripts.merged_transcript is 'Итоговый склеенный транскрипт после обработки всех частей.';

create index if not exists idx_lectures_status       on public.lectures_transcripts (status);
create index if not exists idx_lectures_disk_path    on public.lectures_transcripts (disk_path);
create index if not exists idx_lectures_lecture_base on public.lectures_transcripts (lecture_base);

-- ------------------------------------------------------------
-- 2. RPC try_merge_lecture
-- Склеивает все готовые части лекции в одну запись со статусом 'merged'.
-- Возвращает: merged (true/false), parts (число готовых), lecture_id (UUID итоговой строки).
-- Вызывается после успешной транскрибации каждой части.
-- ------------------------------------------------------------
create or replace function public.try_merge_lecture(p_base text)
returns table(merged boolean, parts integer, lecture_id uuid)
language plpgsql
security definer
as $$
declare
  v_total      int;
  v_done       int;
  v_transcript text;
  v_id         uuid;
begin
  -- Уже склеено
  select id into v_id
  from public.lectures_transcripts
  where lecture_base = p_base and merged_transcript is not null
  limit 1;

  if found then
    return query select false, 0, v_id;
    return;
  end if;

  -- Считаем части
  select
    count(*),
    count(*) filter (where status = 'done')
  into v_total, v_done
  from public.lectures_transcripts
  where lecture_base = p_base;

  -- Не все готовы
  if v_total = 0 or v_done < v_total then
    return query select false, v_done, null::uuid;
    return;
  end if;

  -- Склеиваем по part_index
  select string_agg(transcript, E'\n\n' order by part_index)
  into v_transcript
  from public.lectures_transcripts
  where lecture_base = p_base and status = 'done';

  -- Обновляем первую строку → финальная запись
  update public.lectures_transcripts
  set
    merged_transcript = v_transcript,
    parts_count       = v_total,
    transcript        = null,
    status            = 'merged',
    part_index        = null,
    file_name         = null,
    operation_id      = null,
    s3_key            = null,
    disk_path         = lecture_base,
    updated_at        = now()
  where id = (
    select id from public.lectures_transcripts
    where lecture_base = p_base
    order by part_index
    limit 1
  )
  returning id into v_id;

  -- Удаляем остальные части
  delete from public.lectures_transcripts
  where lecture_base = p_base
    and id != v_id;

  return query select true, v_total, v_id;
end;
$$;

comment on function public.try_merge_lecture(text) is
  'Атомарно склеивает все части лекции (lecture_base) в одну строку со статусом merged. Идемпотентна: при повторных вызовах возвращает существующую запись.';
