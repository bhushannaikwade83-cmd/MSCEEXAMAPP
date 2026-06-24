-- Exam app only: which exam centre a student is allotted to.
-- MSCE APP 2 ignores this nullable column. Set via SQL (e.g. exam_centre_code = '001').

alter table students
  add column if not exists exam_centre_code text;

comment on column students.exam_centre_code is
  'Exam centre code (matches exam_centers.center_code). When set, the exam app shows this student at that centre without a roster row.';

create index if not exists students_exam_centre_code_idx
  on students (exam_centre_code)
  where exam_centre_code is not null and trim(exam_centre_code) <> '';

create index if not exists students_exam_centre_institute_idx
  on students (exam_centre_code, institute_id)
  where exam_centre_code is not null and trim(exam_centre_code) <> '';
