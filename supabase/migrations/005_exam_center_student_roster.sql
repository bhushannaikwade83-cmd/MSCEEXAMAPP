-- Allotted students per exam centre (same institute can split across centres).
-- Match roster full name + institute id → MSCE public.students row in the app.

create table if not exists exam_center_student_roster (
  id uuid primary key default gen_random_uuid(),
  center_id uuid not null references exam_centers(id) on delete cascade,
  exam_msce_institute_id text not null,
  exam_student_full_name text not null,
  exam_msce_student_id text,
  exam_roll_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (center_id, exam_msce_institute_id, exam_student_full_name)
);

create index if not exists exam_roster_center_idx
  on exam_center_student_roster (center_id);

create index if not exists exam_roster_institute_idx
  on exam_center_student_roster (exam_msce_institute_id);

comment on table exam_center_student_roster is
  'Students allotted to an exam centre. App matches exam_student_full_name + exam_msce_institute_id to MSCE students.';

alter table exam_center_student_roster enable row level security;

drop policy if exists "exam_roster_anon_select" on exam_center_student_roster;
create policy "exam_roster_anon_select"
  on exam_center_student_roster for select to anon using (true);

drop policy if exists "exam_roster_anon_update_link" on exam_center_student_roster;
create policy "exam_roster_anon_update_link"
  on exam_center_student_roster for update to anon
  using (true)
  with check (true);

drop policy if exists "exam_marks_anon_all" on exam_attendance_marks;
create policy "exam_marks_anon_all"
  on exam_attendance_marks for all to anon using (true) with check (true);

drop policy if exists "exam_gps_anon_all" on exam_center_gps;
create policy "exam_gps_anon_all"
  on exam_center_gps for all to anon using (true) with check (true);
