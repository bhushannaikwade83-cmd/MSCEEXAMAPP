# 📋 Full Debug Trace: Entry Photo Marking Flow

## Overview
This document traces the complete flow from marking entry to photo displaying back. All debug points are logged with detailed information.

---

## STEP 1️⃣: Entry Marking Started (`home_screen.dart::_saveEntryWithPhoto`)

```
═══════════════════════════════════════════════════════════
🚀 [STEP 1] Entry marking started for: {STUDENT_NAME}
═══════════════════════════════════════════════════════════
✅ [STEP 1] Center retrieved: {CENTER_NAME} (ID: {CENTER_UUID})
✅ [STEP 1] Centre code extracted: {CENTRE_CODE}  ← 🔑 KEY: This should be "4305" not UUID!
✅ [STEP 1] Subject: {SUBJECT_NAME}
✅ [STEP 1] Exam student ID: {EXAM_STUDENT_UUID}
```

**What's happening:**
- Gets center info from SessionService
- Extracts centre_code from center['code'] ← **FIXED** to use code instead of id
- Gets subject details
- Gets exam_student_id

**Debug Watch:**
- ✅ Centre code should be numeric (e.g., "4305")
- ❌ If centre code is UUID, the fix didn't work

---

## STEP 2️⃣: UI Placeholder Updated (`home_screen.dart`)

```
═══════════════════════════════════════════════════════════
🎨 [STEP 2] Updating UI with placeholder...
═══════════════════════════════════════════════════════════
✅ [STEP 2] Found subject in state at index [i][j]
✅ [STEP 2] UI placeholder updated
🔄 Snackbar shown: "✅ Entry marked - PRESENT ✓"
```

**What's happening:**
- UI is updated immediately with placeholder
- Snackbar confirms entry marked
- User sees instant feedback

**Debug Watch:**
- State index should be found (not skipped)
- "marking..." placeholder should appear in UI

---

## STEP 3️⃣: Background Photo Upload Started (`home_screen.dart::_uploadEntryPhotoInBackground`)

```
═══════════════════════════════════════════════════════════
📸 [BG-UPLOAD] Background upload started
   Student: {STUDENT_NAME} ({SEAT_NO})
   Subject: {SUBJECT_CODE}
   Centre Code: {CENTRE_CODE}  ← 🔑 Should match STEP 1
═══════════════════════════════════════════════════════════
📸 [BG-1] Original photo size: {SIZE} KB
✅ [BG-1] Photo size OK ({SIZE} KB < 1MB)
   OR
⚠️ [BG-1] Photo exceeds 1MB, compressing...
✅ [BG-1] Compressed photo size: {SIZE} KB
```

**What's happening:**
- Read photo from camera file
- Check file size (1MB limit)
- Compress if needed

**Debug Watch:**
- Photo size should be logged correctly
- Centre code should match STEP 1
- Compression ratio should be visible if needed

---

## STEP 4️⃣: Storage Service Upload (`b2b_storage_service.dart::uploadAttendancePhoto`)

### Part A: Validation

```
═══════════════════════════════════════════════════════════
📤 [STORAGE-1] uploadAttendancePhoto called
   instituteId: {CENTRE_CODE}  ← 🔑 KEY: Check this is "4305"
   folderYear: 2026
   rollNumber: {SEAT_NO}
   subject: {SUBJECT_CODE}
   date: 2026-07-06
   photoType: entry
═══════════════════════════════════════════════════════════
✅ [STORAGE-1] Validation passed
```

**What's happening:**
- Validate all parameters
- instituteId is the centre_code passed from BG-1

**Debug Watch:**
- ✅ If instituteId is "4305" → CORRECT ✅
- ❌ If instituteId is UUID → FIX FAILED ❌

### Part B: Path Generation

```
═══════════════════════════════════════════════════════════
📤 [STORAGE-2] Generated storage path: {CENTRE_CODE}/2026/{SEAT_NO}/{SUBJECT}/{DATE}/{SEAT_NOentry.jpg}
═══════════════════════════════════════════════════════════
```

**Example of CORRECT path:**
```
4305/2026/4305150873/english_30/2026-07-06/4305150873entry.jpg
```

**Example of WRONG path:**
```
c87594da-67a4-4d0d-96bf-19b122f0648c/2026/001/english_30/2026-07-06/001entry.jpg  ❌
```

**Debug Watch:**
- Path should start with centre_code ("4305...")
- Should NOT start with UUID

### Part C: Vercel API Upload

```
═══════════════════════════════════════════════════════════
📤 [STORAGE-3] Uploading to Vercel API...
   Endpoint: https://msceexamapp.vercel.app/api/b2-upload
   File size: {SIZE} KB
   Path header: {STORAGE_PATH}
═══════════════════════════════════════════════════════════
✅ [STORAGE-3] HTTP response received: 200
✅ [STORAGE-3] fileId extracted: {FILE_ID}
```

**What's happening:**
- Send photo to Vercel API
- Vercel uploads to BackBlaze B2
- Get fileId back

**Debug Watch:**
- Status should be 200
- fileId should be returned

### Part D: URL Generation

```
═══════════════════════════════════════════════════════════
✅ [STORAGE-4] Upload COMPLETE (MOBILE ONLY)
   Storage path: {STORAGE_PATH}
   File ID: {FILE_ID}
   Final URL: https://f004.backblazeb2.com/file/attendance-students-photos/{STORAGE_PATH}
═══════════════════════════════════════════════════════════
```

**Example of CORRECT URL:**
```
https://f004.backblazeb2.com/file/attendance-students-photos/4305/2026/4305150873/english_30/2026-07-06/4305150873entry.jpg
```

---

## STEP 5️⃣: Database Update (`home_screen.dart::_uploadEntryPhotoInBackground`)

```
═══════════════════════════════════════════════════════════
📤 [BG-2] Upload successful!
   URL: {FINAL_URL}
   Path: {STORAGE_PATH}
═══════════════════════════════════════════════════════════

═══════════════════════════════════════════════════════════
💾 [BG-3] Saving to database...
   centerId: {CENTER_UUID}
   studentId: {EXAM_STUDENT_UUID}
   photoPath: {FINAL_URL}
   subjectCode: {SUBJECT_CODE}
   latitude: {LAT}, longitude: {LON}
═══════════════════════════════════════════════════════════
✅ [BG-3] Database save result: {RESULT}
```

**What's happening:**
- Call ExamEntryService.markSubjectEntry()
- Save URL and metadata to exam_students table
- Update: entry_photo_url, entry_photo_at, entry_latitude, entry_longitude, entry_at

**Debug Watch:**
- URL passed to database should match STORAGE-4
- Database result should indicate success

---

## STEP 6️⃣: UI Update with Photo (`home_screen.dart`)

```
═══════════════════════════════════════════════════════════
🎨 [BG-4] Updating UI with actual photo URL...
═══════════════════════════════════════════════════════════
✅ [BG-4] Updating state at index [i][j]
   OLD: marking...
   NEW: {FINAL_URL}
✅ [BG-4] State updated successfully
```

**What's happening:**
- Replace "marking..." placeholder with actual URL
- Photo should now display in UI

**Debug Watch:**
- OLD should be "marking..."
- NEW should be the full B2 URL
- Both indices should be found correctly

---

## STEP 7️⃣: Auto-enable Next Subject (`home_screen.dart`)

```
═══════════════════════════════════════════════════════════
🔄 [BG-5] Auto-enabling next subject...
═══════════════════════════════════════════════════════════
✅ [BG-5] Next subject auto-enabled: {NEXT_SUBJECT_ID}
   OR
ℹ️ [BG-5] No next subject to enable (current: {INDEX} of {TOTAL})
```

**What's happening:**
- Find next subject in exam order
- Enable is_enabled flag

**Debug Watch:**
- Should show which subject was auto-enabled
- Or confirm no more subjects

---

## STEP 8️⃣: Data Reload (`home_screen.dart`)

```
═══════════════════════════════════════════════════════════
📱 [BG-6] Reloading data in 500ms...
═══════════════════════════════════════════════════════════
✅ [BG-6] Data reload triggered
```

**What's happening:**
- Calls _load() to refresh data from database
- Photo should persist (already saved in DB)

---

## ✅ Complete Flow Verified When:

1. ✅ STEP 1: Centre code is correct (not UUID)
2. ✅ STORAGE-1: instituteId matches STEP 1 centre code
3. ✅ STORAGE-2: Path starts with centre_code
4. ✅ STORAGE-3: HTTP 200 response
5. ✅ STORAGE-4: URL includes correct path
6. ✅ BG-3: Database save successful
7. ✅ BG-4: UI updated from "marking..." to real URL
8. ✅ Photo displays in subject card

---

## 🔴 Troubleshooting

### Issue: UUID appears instead of centre_code

**Check STEP 1:**
- Centre code extracted correctly?
- If showing UUID, SessionService.getCenter() returning wrong data

**Check STORAGE-1:**
- instituteId parameter is UUID instead of centre code
- Fix: Check home_screen.dart line 1009 - should use center['code']

### Issue: Photo not showing after marking

**Check STEP 2:**
- Placeholder "marking..." appears? → Step 3+ issue
- No placeholder? → State update issue

**Check BG-4:**
- Old value shown? → Photo save failed (check BG-3)
- Missing state index? → Subject ID mismatch in state array

### Issue: Photo visible but disappears after reload

**Check BG-6:**
- Database reload completing?
- Photo URL not persisting in database?
- Check exam_students table for entry_photo_url

---

## 🧪 Test Checklist

- [ ] Mark entry for student
- [ ] Verify all debug steps from STEP 1 to BG-6
- [ ] Centre code shown (not UUID) in STEP 1 and STORAGE-1
- [ ] Storage path starts with centre_code in STORAGE-2
- [ ] Photo URL contains correct path in STORAGE-4
- [ ] Photo displays in UI after BG-4
- [ ] Photo persists after BG-6 reload
- [ ] Next subject auto-enabled (if more subjects exist)

