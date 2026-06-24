-- Exam-app columns use exam_* prefix.
-- Shared MSCE tables (students, institutes, …) are NOT modified.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'exam_centers'
      and column_name = 'msce_institute_id'
  ) then
    alter table exam_centers rename column msce_institute_id to exam_msce_institute_id;
  end if;
end $$;

comment on column exam_centers.exam_msce_institute_id is
  'MSCE APP 2 institutes.id — students loaded from public.students for this institute.';

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'exam_attendance_marks'
      and column_name = 'msce_student_id'
  ) then
    alter table exam_attendance_marks rename column msce_student_id to exam_msce_student_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'exam_attendance_marks'
      and column_name = 'entry_photo_url'
  ) then
    alter table exam_attendance_marks rename column entry_photo_url to exam_entry_photo_url;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'exam_attendance_marks'
      and column_name = 'face_match_score'
  ) then
    alter table exam_attendance_marks rename column face_match_score to exam_face_match_score;
  end if;
end $$;

drop index if exists exam_attendance_center_msce_student_uidx;

create unique index if not exists exam_attendance_center_exam_msce_student_uidx
  on exam_attendance_marks (center_id, exam_msce_student_id)
  where exam_msce_student_id is not null;

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
