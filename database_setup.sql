-- SQL Migration: Sequential Subject Marking
-- This sets up the database to enable sequential subject marking

-- 1. Add is_enabled column if it doesn't exist
ALTER TABLE exam_students ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN DEFAULT true;

-- 2. Initialize: Only first subject per student enabled, rest disabled
-- For each student, disable all subjects except the first one (ordered by seat_no)
UPDATE exam_students
SET is_enabled = false
WHERE id NOT IN (
  SELECT DISTINCT ON (student_name, centre_code) id
  FROM exam_students
  ORDER BY student_name, centre_code, seat_no ASC
);

-- 3. Verify: Show count of enabled vs disabled subjects per centre
-- SELECT
--   centre_code,
--   COUNT(*) as total_subjects,
--   SUM(CASE WHEN is_enabled THEN 1 ELSE 0 END) as enabled_count,
--   SUM(CASE WHEN NOT is_enabled THEN 1 ELSE 0 END) as disabled_count
-- FROM exam_students
-- GROUP BY centre_code;

-- 4. Manual override if needed: Enable all subjects for a specific centre
-- UPDATE exam_students SET is_enabled = true WHERE centre_code = 'CENTRE_CODE_HERE';

-- 5. Manual override if needed: Disable all subjects except first per student
-- UPDATE exam_students SET is_enabled = false
-- WHERE id NOT IN (
--   SELECT DISTINCT ON (student_name, centre_code) id
--   FROM exam_students
--   ORDER BY student_name, centre_code, seat_no ASC
-- );
