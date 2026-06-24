-- ============================================================
-- MIGRATION 006 — exam_centres table + exam_students schema
-- Run this in Supabase → SQL Editor
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- TABLE 1: exam_students
-- Fields: id, seat_no, student_name, subjects, batch,
--         start_time, end_time, exam_date, centre_code,
--         photo_url, created_at
--         (entry_time + entry_photo saved in exam_attendance_marks
--          per subject — see TABLE 3 below)
-- ─────────────────────────────────────────────────────────────

-- Add new columns to existing exam_students table
ALTER TABLE exam_students
  ADD COLUMN IF NOT EXISTS seat_no      TEXT,
  ADD COLUMN IF NOT EXISTS subjects     TEXT[]      DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS batch        TEXT,
  ADD COLUMN IF NOT EXISTS start_time   TIMETZ,
  ADD COLUMN IF NOT EXISTS end_time     TIMETZ,
  ADD COLUMN IF NOT EXISTS exam_date    DATE,
  ADD COLUMN IF NOT EXISTS centre_code  TEXT;

-- Backfill seat_no from roll_number (existing data)
UPDATE exam_students
SET seat_no = roll_number
WHERE seat_no IS NULL AND roll_number IS NOT NULL;

-- Backfill exam_date and start_time from exam_time (existing data)
UPDATE exam_students
SET
  exam_date  = (exam_time AT TIME ZONE 'UTC')::DATE,
  start_time = (exam_time AT TIME ZONE 'UTC')::TIME
WHERE exam_date IS NULL AND exam_time IS NOT NULL;

-- Index for fast centre_code lookup
CREATE INDEX IF NOT EXISTS idx_exam_students_centre_code
  ON exam_students(centre_code);


-- ─────────────────────────────────────────────────────────────
-- TABLE 2: exam_centres
-- Fields: centre_code (PK / unique), centre_name, centre_address
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS exam_centres (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  centre_code    TEXT        UNIQUE NOT NULL,
  centre_name    TEXT        NOT NULL DEFAULT '',
  centre_address TEXT        DEFAULT '',
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);

-- After inserting exam_centres rows, link students:
--   UPDATE exam_students s
--   SET centre_code = ec.centre_code
--   FROM exam_centres ec
--   WHERE s.center_id = <map your existing center UUID>;

-- FK constraint (add after backfill is done)
-- ALTER TABLE exam_students
--   ADD CONSTRAINT fk_exam_students_centre_code
--   FOREIGN KEY (centre_code) REFERENCES exam_centres(centre_code);


-- ─────────────────────────────────────────────────────────────
-- TABLE 3 (update): exam_attendance_marks
-- Add subject_code + entry_time + entry_photo_path
-- One row per student per subject
-- ─────────────────────────────────────────────────────────────

ALTER TABLE exam_attendance_marks
  ADD COLUMN IF NOT EXISTS subject_code     TEXT,
  ADD COLUMN IF NOT EXISTS entry_time       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS entry_photo_path TEXT;

-- Index for per-student per-subject lookup
CREATE INDEX IF NOT EXISTS idx_exam_marks_student_subject
  ON exam_attendance_marks(exam_msce_student_id, subject_code);

-- Backfill entry_time from marked_at (existing marks)
UPDATE exam_attendance_marks
SET entry_time = marked_at
WHERE entry_time IS NULL AND marked_at IS NOT NULL;

-- Backfill entry_photo_path from present_photo_path (existing marks)
UPDATE exam_attendance_marks
SET entry_photo_path = COALESCE(exam_entry_photo_url, present_photo_path)
WHERE entry_photo_path IS NULL;


-- ─────────────────────────────────────────────────────────────
-- RLS — enable access for authenticated users
-- ─────────────────────────────────────────────────────────────

ALTER TABLE exam_centres ENABLE ROW LEVEL SECURITY;

-- Allow any authenticated user (exam centre staff) to read centres
CREATE POLICY IF NOT EXISTS "exam_centres_read"
  ON exam_centres FOR SELECT
  USING (auth.role() = 'authenticated');

-- Allow service role to insert/update centres
CREATE POLICY IF NOT EXISTS "exam_centres_write"
  ON exam_centres FOR ALL
  USING (auth.role() = 'service_role');


-- ─────────────────────────────────────────────────────────────
-- VIEW: exam_students_with_centre
-- Joins both tables — useful for admin exports
-- ─────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW exam_students_with_centre AS
SELECT
  s.id,
  s.seat_no,
  s.student_name,
  s.subjects,
  s.batch,
  s.start_time,
  s.end_time,
  s.exam_date,
  s.photo_url,
  s.centre_code,
  c.centre_name,
  c.centre_address
FROM exam_students s
LEFT JOIN exam_centres c ON c.centre_code = s.centre_code;
