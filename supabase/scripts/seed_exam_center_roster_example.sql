-- Example: allot MSCE students to exam centre 001 by full name + institute id.
-- Run in Supabase SQL Editor after migration 005.

-- insert into exam_center_student_roster (
--   center_id,
--   exam_msce_institute_id,
--   exam_student_full_name,
--   exam_roll_number
-- )
-- select
--   c.id,
--   '63111',                              -- MSCE institutes.id
--   'priyanka sanjay kalone',             -- normalized: first middle last (lowercase ok)
--   'EXAM-ROLL-001'                       -- optional exam hall roll
-- from exam_centers c
-- where c.login_username = '001';

-- Bulk import pattern (CSV → temp table → insert):
--   center_code, institute_id, student_full_name, exam_roll_number
-- Match key in app: lower(trim(full_name)) + institute_id
