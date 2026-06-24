-- Dummy exam centre for testing.
-- Login: 001  |  Password: Dummy@001

create extension if not exists pgcrypto with schema extensions;

grant execute on function public.exam_center_login(text, text) to anon, authenticated;

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

-- Optional: link to an MSCE institute so the home screen loads students.
-- update exam_centers
-- set exam_msce_institute_id = '<your-institute-uuid>'
-- where login_username = '001';
