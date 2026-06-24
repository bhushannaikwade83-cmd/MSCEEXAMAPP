-- Run once in Supabase SQL Editor (postgres / service role).
-- Creates exam-centre tables + dummy login:
--   Username: 001
--   Password: Dummy@001

create extension if not exists pgcrypto with schema extensions;

-- ── 001 schema ──────────────────────────────────────────────────────────────

create table if not exists exam_centers (
  id uuid primary key default gen_random_uuid(),
  center_code text not null unique,
  center_name text not null,
  login_username text not null unique,
  password_hash text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists exam_center_gps (
  center_id uuid primary key references exam_centers(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  radius_meters double precision not null default 15,
  is_locked boolean not null default false,
  locked_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists exam_students (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references exam_centers(id) on delete cascade,
  roll_number text not null,
  student_name text not null,
  exam_time timestamptz not null,
  photo_url text,
  created_at timestamptz not null default now(),
  unique (center_id, roll_number)
);

create index if not exists exam_students_center_time_idx
  on exam_students (center_id, exam_time);

create table if not exists exam_attendance_marks (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references exam_centers(id) on delete cascade,
  student_id uuid references exam_students(id) on delete cascade,
  marked_at timestamptz not null default now(),
  gps_latitude double precision,
  gps_longitude double precision,
  gps_distance_meters double precision,
  staff_confirmed boolean not null default true,
  present_photo_path text,
  unique (student_id)
);

-- ── 002 MSCE students link ───────────────────────────────────────────────────

alter table exam_centers
  add column if not exists exam_msce_institute_id text;

alter table exam_attendance_marks
  add column if not exists exam_msce_student_id text,
  add column if not exists exam_entry_photo_url text,
  add column if not exists exam_face_match_score double precision;

alter table exam_attendance_marks
  alter column student_id drop not null;

create unique index if not exists exam_attendance_center_exam_msce_student_uidx
  on exam_attendance_marks (center_id, exam_msce_student_id)
  where exam_msce_student_id is not null;

-- ── Login RPC ───────────────────────────────────────────────────────────────

create or replace function exam_center_login(p_username text, p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_center exam_centers%rowtype;
begin
  select * into v_center
  from exam_centers
  where login_username = lower(trim(p_username))
    and is_active = true
  limit 1;

  if v_center.id is null then
    return jsonb_build_object('ok', false, 'message', 'Invalid center login');
  end if;

  if v_center.password_hash <> crypt(trim(p_password), v_center.password_hash) then
    return jsonb_build_object('ok', false, 'message', 'Invalid password');
  end if;

  return jsonb_build_object(
    'ok', true,
    'center_id', v_center.id,
    'center_code', v_center.center_code,
    'center_name', v_center.center_name,
    'exam_msce_institute_id', coalesce(nullif(trim(v_center.exam_msce_institute_id), ''), v_center.center_code)
  );
end;
$$;

grant execute on function public.exam_center_login(text, text) to anon, authenticated;

alter table exam_centers enable row level security;
alter table exam_center_gps enable row level security;
alter table exam_students enable row level security;
alter table exam_attendance_marks enable row level security;

-- ── Dummy centre 001 ─────────────────────────────────────────────────────────

insert into exam_centers (
  center_code,
  center_name,
  login_username,
  password_hash,
  is_active,
  exam_msce_institute_id
)
values (
  '001',
  'Dummy Exam Centre 001',
  '001',
  crypt('Dummy@001', gen_salt('bf')),
  true,
  null
)
on conflict (login_username) do update set
  center_code = excluded.center_code,
  center_name = excluded.center_name,
  password_hash = excluded.password_hash,
  is_active = true;

-- Sanity check
select
  center_code,
  center_name,
  login_username,
  is_active,
  exam_msce_institute_id,
  'Login with username 001 / password Dummy@001' as hint
from exam_centers
where login_username = '001';
