# 📊 MSCE Website: Entry Marking Flow (React Admin Portal)

## Complete Flow: From Mobile App Entry → Website Display

---

## 🚀 STEP 1: Mobile App Marks Entry

**File:** `home_screen.dart::_uploadEntryPhotoInBackground()`

```
User taps "Mark Entry" on exam subject
    ↓
Photo captured + GPS coordinates recorded
    ↓
[BG-1] Photo compressed to < 1MB
    ↓
[BG-2] Upload to B2 Storage via Vercel API
       Path: CENTRE_CODE/2026/SEAT_NO/SUBJECT/DATE/SEAT_NOentry.jpg
       URL: https://f004.backblazeb2.com/file/attendance-students-photos/...
    ↓
[BG-3] Save to database (exam_students table)
       Fields updated:
       - entry_photo_url: Full B2 URL
       - entry_photo_at: Timestamp
       - entry_latitude: GPS latitude
       - entry_longitude: GPS longitude
       - entry_at: Entry time
    ↓
[BG-4] UI updates with photo thumbnail
```

---

## 💾 Database Updates (Supabase)

**Table:** `exam_students`

```sql
UPDATE exam_students SET
  entry_photo_url = 'https://f004.backblazeb2.com/file/attendance-students-photos/4305/2026/001/english_30/2026-07-06/001entry.jpg',
  entry_photo_at = '2026-07-06T01:12:11.446345',
  entry_latitude = 18.0522547,
  entry_longitude = 75.7976452,
  entry_at = '2026-07-06T01:12:07.259829'
WHERE id = '3d9a50e4-59d3-4535-851b-b69bf7b06701'
  AND exam_student_id = '...'
  AND centre_code = '4305';
```

---

## 🌐 STEP 2: Website Admin Portal Loads Students

**File:** `ExamStudentsPage.tsx::loadStudentsByCentre()`

### Loading Process:

```
1. User selects centre from dropdown (e.g., "4305")
    ↓
2. Query exam_students table:
   .from('exam_students')
   .select('*')
   .eq('centre_code', '4305')
   .order('seat_no', { ascending: true })
   .range(0, 999)  // Pagination: 1000 rows per page
    ↓
3. Fetch ALL 1000 students from database
    ↓
4. Group by student_name + institute_id to merge all subjects
    ↓
5. Store in React state: setStudents(groupedStudents)
```

### Example Data Structure:

```javascript
{
  id: "exam-student-uuid",
  student_name: "JAMADAR SURAIYYA ABDUL",
  seat_no: "4305150001",
  centre_code: "4305",
  photo_url: "https://mscepune.in/gcc/ctimages/4313969.JPG",
  
  subjectDetails: [
    {
      subject: "ENGLISH 30",
      date: "2026-07-04",
      time: "09:00",
      batch: "A1",
      entry_photo_url: "https://f004.backblazeb2.com/file/.../4305150001entry.jpg",
      entry_photo_at: "2026-07-06T01:12:11.446345",
      entry_latitude: "18.0522547",
      entry_longitude: "75.7976452",
      entry_at: "2026-07-06T01:12:07.259829",
      entry_history: "[]"  // JSON array of old entries
    }
  ]
}
```

---

## 📊 STEP 3: Website Display Entry Photo

**File:** `ExamStudentsPage.tsx::render()`

### Rendering Table Rows:

```jsx
{filteredStudents.map((student) => (
  student.subjectDetails.map((detail, sidx) => (
    <tr key={...}>
      {/* Column 1: Sr No */}
      {sidx === 0 && <td>{idx + 1}</td>}
      
      {/* Column 2: Profile Photo */}
      {sidx === 0 && (
        <td>
          {student.photo_url ? (
            <StudentDisplayPhoto
              student={student}
              size="sm"
            />
          ) : (
            <div>📸</div>
          )}
        </td>
      )}
      
      {/* Column 3: Student Name */}
      {sidx === 0 && <td>{student.student_name}</td>}
      
      {/* Column 4: Seat No */}
      {sidx === 0 && <td>{student.seat_no}</td>}
      
      {/* Column 5: Subject */}
      <td>{detail.subject}</td>
      
      {/* Column 6: ENTRY PHOTO + RESET BUTTON */}
      <td>
        {detail.entry_photo_url ? (
          <div>
            <div className="exam-photo-box">
              <StudentDisplayPhoto
                student={{ photo_url: detail.entry_photo_url }}
                displayName={`${student.student_name} - Entry`}
                size="sm"
              />
            </div>
            
            {/* 🔴 RESET BUTTON */}
            <button
              onClick={() => resetEntryPhoto(student.id, subjectIndex)}
              style={{ background: '#e74c3c', color: 'white' }}
            >
              🔄 Reset
            </button>
          </div>
        ) : (
          <div className="exam-photo-box">—</div>
        )}
      </td>
      
      {/* Column 7: OLD PHOTOS (entry_history) */}
      <td>
        {/* Show latest old photo from entry_history JSON array */}
        {JSON.parse(detail.entry_history)?.[0]?.entry_photo_url && (
          <StudentDisplayPhoto
            student={{ photo_url: latestOld.entry_photo_url }}
            displayName={`${student.student_name} - Old`}
            size="sm"
          />
        )}
      </td>
      
      {/* Column 8: ENTRY LOCATION */}
      <td>
        {detail.entry_latitude && detail.entry_longitude ? (
          <a href={`https://www.google.com/maps?q=${lat},${lng}`}>
            📍 Map
          </a>
        ) : (
          "No location"
        )}
      </td>
      
      {/* Column 9: ENTRY TIME */}
      <td>
        {new Date(detail.entry_photo_at).toLocaleTimeString('en-IN')}
      </td>
    </tr>
  ))
))}
```

---

## 🔄 STEP 4: Reset Entry Photo

**File:** `ExamStudentsPage.tsx::resetEntryPhoto()`

### Reset Process:

```
1. User clicks "🔄 Reset" button on entry photo
    ↓
2. Save current entry to entry_history JSON array:
   {
     id: "entry_1720272331446",
     entry_photo_url: "https://f004.backblazeb2.com/file/...",
     entry_photo_at: "2026-07-06T01:12:11.446345",
     entry_latitude: "18.0522547",
     entry_longitude: "75.7976452",
     entry_at: "2026-07-06T01:12:07.259829",
     reset_at: "2026-07-06T01:15:00.000Z"
   }
    ↓
3. Clear current entry fields in database:
   UPDATE exam_students SET
     entry_photo_url = NULL,
     entry_photo_at = NULL,
     entry_latitude = NULL,
     entry_longitude = NULL,
     entry_at = NULL,
     entry_history = JSON.stringify([...oldHistory, newEntry])
    ↓
4. Update React state:
   setStudents(students.map(s => ({
     ...s,
     subjectDetails: s.subjectDetails.map(d => ({
       ...d,
       entry_photo_url: null,
       entry_photo_at: null,
       entry_latitude: null,
       entry_longitude: null,
       entry_at: null,
       entry_history: JSON.stringify(entryHistory)
     }))
   })))
    ↓
5. UI updates: Entry photo disappears, old photo appears in "Old Photos" column
```

---

## 📸 Photo Resolution Strategy

**File:** `StudentDisplayPhoto.tsx`

### How Photos Load:

```
1. Check component props for photo_url
    ↓
2. Determine photo type:
   - B2 URL: https://f004.backblazeb2.com/file/... 
     → Use direct (already signed if needed)
   - Supabase path: just/the/path
     → Get signed URL via b2-storage-proxy edge function
   - Full HTTPS URL: https://mscepune.in/gcc/...
     → Use as-is
    ↓
3. Apply memory cache + localStorage (1-hour TTL)
    ↓
4. Render using <SecureNetworkImage> component
    (handles 404, fallback to placeholder)
```

---

## 🎯 Complete User Journey

```
MOBILE APP:
1. Teacher taps "Mark Entry" → Photo captured + GPS
2. System uploads to B2 (via Vercel API)
3. Database updated with entry_photo_url + location
4. UI shows "✅ Entry Marked" snackbar
5. Photo thumbnail appears in app

↓ (Data synced via Supabase)

WEBSITE ADMIN PORTAL:
1. Admin selects centre → Students load from database
2. Table displays students with entry photos
3. Admin can see:
   - Student profile photo
   - Entry photo (if marked)
   - GPS location (clickable map link)
   - Entry timestamp
   - Old entry photos (history)
4. Admin clicks "🔄 Reset" → Entry moved to history
5. Next entry marked by teacher shows in table

↓ (Real-time sync via Supabase)

BACK TO MOBILE APP:
(If data reloaded)
1. Entry photo appears after reload
2. Shows in StudentSubjectsScreen
3. Next subject auto-enabled
```

---

## 📋 Database Schema (Relevant Fields)

```sql
CREATE TABLE exam_students (
  id UUID PRIMARY KEY,
  exam_student_id VARCHAR,
  student_name VARCHAR,
  seat_no VARCHAR,           -- Exam hall seat (001, 002, etc)
  sr_no VARCHAR,             -- Registration SR no
  centre_code VARCHAR,       -- Centre code (4305, etc)
  photo_url TEXT,            -- Profile photo from registration
  entry_photo_url TEXT,      -- Current entry photo URL
  entry_photo_at TIMESTAMP,  -- When photo was taken
  entry_latitude FLOAT,      -- GPS latitude
  entry_longitude FLOAT,     -- GPS longitude
  entry_at TIMESTAMP,        -- When entry was marked
  entry_history JSONB,       -- Array of past entries
  is_enabled BOOLEAN,        -- Can mark entry for this subject
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

---

## ✅ Summary

| Component | Saves To | Displays From | Update Mechanism |
|-----------|----------|---------------|------------------|
| **Mobile App** | exam_students (entry_photo_url) | Local state + database | Background upload |
| **Website Admin** | entry_history JSON | Database rows | React state |
| **Reset** | entry_history array | Old Photos column | Database update + state sync |

