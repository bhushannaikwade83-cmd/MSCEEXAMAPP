# MSCE Exam Center App

Standalone app in **this folder only**.

## Flow

1. Centre login
2. GPS setup (15 m lock) — first time
3. Batches (1-hour slots from `exam_time`)
4. Student cards show **passport photo**
5. Tap student → staff **visually** checks seated person matches passport photo → **Yes, mark present** (no face comparison)
6. GPS checked on every mark (within 15 m)

Optional: capture a photo of the seated student for records (not used for matching).

## Database

- `photo_url` — passport photo on card
- `staff_confirmed` — true when centre staff confirmed same person
- `present_photo_path` — optional camera capture at mark time

No `face_embedding` required for this app.

## Setup

1. `app_config.env` — Supabase URL + anon key
2. Run `supabase/migrations/001_exam_center_schema.sql`
3. `flutter pub get` && `flutter run`
