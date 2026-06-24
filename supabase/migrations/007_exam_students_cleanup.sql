-- ============================================================
-- MIGRATION 007 — Clean up exam_students table
-- Remove roll_number and exam_time (replaced by seat_no,
-- exam_date, start_time, end_time from migration 006)
-- Run AFTER migration 006 is applied and data is verified.
-- ============================================================

-- Drop legacy columns
ALTER TABLE exam_students
  DROP COLUMN IF EXISTS roll_number,
  DROP COLUMN IF EXISTS exam_time;

-- Ensure seat_no is NOT NULL going forward
-- (run after verifying all rows have seat_no set)
-- ALTER TABLE exam_students ALTER COLUMN seat_no SET NOT NULL;

-- Final exam_students column set after both migrations:
-- id, seat_no, student_name, subjects (fetched from students table),
-- batch, start_time, end_time, exam_date, centre_code, photo_url,
-- created_at
-- NOTE: subjects and photo_url on exam_students are optional —
-- the app always fetches the live values from the students table
-- by matching on student_name. exam_students.subjects is kept
-- as a cache / fallback only.
