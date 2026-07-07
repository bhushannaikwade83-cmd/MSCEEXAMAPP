# SR NO Database Fetch Implementation - Summary

## Objective
Fetch SR NO directly from the database (`exam_students.sr_no`) instead of using student object properties across all screens in MSCEEXAMAPP.

## Changes Made

### 1. **HomeScreen** (`lib/screens/home_screen.dart`)

#### New Helper Function
```dart
String _getSrNoFromSubjects(List<Map<String, dynamic>> subjects, String? filterSubject) {
  if (subjects.isEmpty) return '';

  // If filtering by subject, get sr_no from that subject
  if (filterSubject != null && filterSubject.isNotEmpty) {
    final subject = subjects.firstWhere(
      (s) => (s['subject_name']?.toString() ?? s['subject_code']?.toString() ?? '') == filterSubject,
      orElse: () => <String, dynamic>{},
    );
    return subject['sr_no']?.toString() ?? '';
  }

  // Otherwise return from first subject
  return subjects.isNotEmpty ? (subjects.first['sr_no']?.toString() ?? '') : '';
}
```

#### Modified SR NO Display (Student Card)
- **Location:** `_studentCard()` function, line ~861
- **Before:** `'SR NO: ${_formatSr(s.srNo)}'` (from student object)
- **After:** `'SR NO: ${_formatSr(_getSrNoFromSubjects(s.subjects, filterSubject))}'` (from database)

#### Updated Subject Row Display
- **Location:** `_buildSubjectRow()` function
- **Added:** Extract `sr_no` from subject data
- **Display:** Shows "SR: {srNo}" in details row alongside seat and batch

### 2. **StudentSubjectsScreen** (`lib/screens/student_subjects_screen.dart`)

#### Updated Subject Row Display
- **Location:** `_buildSubjectRow()` function
- **Added:** Extract `sr_no` from subject map: `final srNo = subject['sr_no']?.toString() ?? '—';`
- **Display:** Shows "SR: {srNo}" in the details row (Details Row 1a)
- **Icons:** Uses `Icons.assignment` for SR NO display

### 3. **QR Code Scanner** (`lib/screens/qr_code_scanner_screen.dart`)

#### Enhanced Database Query
- **Location:** `_fetchStudentByQr()` function, line ~180
- **Before:** Limited `.select()` with only: `'subject_name, exam_date, start_time, exam_student_id, seat_no'`
- **After:** Comprehensive `.select()` including all fields needed:
  ```dart
  .select('id, subject_name, exam_date, start_time, exam_student_id, seat_no, sr_no, batch, entry_photo_url, is_enabled')
  ```
- **Benefit:** When QR scanner passes data to StudentSubjectsScreen, SR NO is now available for display

## Key Implementation Details

1. **Database Source:** All SR NO values now come directly from `exam_students.sr_no` field
2. **Subject Filtering:** When filtering by subject, SR NO is fetched from the matching subject
3. **Fallback Handling:** If SR NO is not available, displays '—' (dash)
4. **Formatting:** Uses existing `_formatSr()` function which pads numeric values with leading zeros
5. **Consistency:** Same approach across all three screens

## Database Table Structure
```
exam_students table:
- id: PK (unique per subject per student)
- sr_no: Serial number from database (NEW SOURCE)
- subject_name: Subject name
- seat_no: Seat number
- batch: Exam batch
- entry_photo_url: Entry photo URL
- is_enabled: Whether marking is enabled
- ... other fields
```

## Display Locations

| Screen | Location | Format | Icon |
|--------|----------|--------|------|
| HomeScreen | Student Card Header | "SR NO: {formatted_value}" | — |
| HomeScreen | Subject Row | "SR: {value}" + "SEAT: {value}" + "BATCH: {value}" | assignment |
| StudentSubjectsScreen | Subject Row | "SR: {value}" + "Seat: {value}" | assignment |
| QR Scanner | Auto-inherited via StudentSubjectsScreen | "SR: {value}" | assignment |

## Testing Checklist

- [x] SR NO appears in HomeScreen student card
- [x] SR NO appears in HomeScreen subject rows with filtering
- [x] SR NO appears in StudentSubjectsScreen subject rows
- [x] QR Scanner query includes sr_no field
- [x] SR NO displays correctly when subjects are filtered
- [x] Empty/null SR NO displays as '—'

## Files Modified

1. `/lib/screens/home_screen.dart`
   - Added `_getSrNoFromSubjects()` function
   - Updated SR NO display in `_studentCard()`
   - Updated SR NO display in `_buildSubjectRow()`

2. `/lib/screens/student_subjects_screen.dart`
   - Added SR NO extraction in `_buildSubjectRow()`
   - Added SR NO UI display in details row

3. `/lib/screens/qr_code_scanner_screen.dart`
   - Enhanced `.select()` query to include all required fields including `sr_no`

## Notes

- Changes are ONLY for MSCEEXAMAPP (as per requirements)
- MSCEAPP is not affected
- All existing photo loading and caching functionality remains unchanged
- Subject filtering still works correctly with SR NO
