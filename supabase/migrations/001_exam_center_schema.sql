-- MSCE Exam Center App schema
-- Centers (~100) log in; GPS locked at 15m; students grouped by 1-hour exam batch.

create extension if not exists pgcrypto with schema extensions;

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
  -- Passport-size photo shown on card; staff visually confirms seated student matches.
  photo_url text,
  created_at timestamptz not null default now(),
  unique (center_id, roll_number)
);

create index if not exists exam_students_center_time_idx
  on exam_students (center_id, exam_time);

create table if not exists exam_attendance_marks (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references exam_centers(id) on delete cascade,
  student_id uuid not null references exam_students(id) on delete cascade,
  marked_at timestamptz not null default now(),
  gps_latitude double precision,
  gps_longitude double precision,
  gps_distance_meters double precision,
  staff_confirmed boolean not null default true,
  present_photo_path text,
  unique (student_id)
);

-- RPC: center login (use service role to seed centers; app calls with anon + RLS policies)
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
    'center_name', v_center.center_name
  );
end;
$$;

grant execute on function public.exam_center_login(text, text) to anon, authenticated;

alter table exam_centers enable row level security;
alter table exam_center_gps enable row level security;
alter table exam_students enable row level security;
alter table exam_attendance_marks enable row level security;
