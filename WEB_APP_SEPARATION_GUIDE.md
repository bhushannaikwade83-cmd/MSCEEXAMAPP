# Web & App Separation Guide - MSCEEXAMAPP

## Overview
MSCEEXAMAPP now has complete separation between Web and Android versions while maintaining shared core functionality.

---

## Architecture

```
MSCEEXAMAPP/
├── lib/
│   ├── (SHARED) Core features
│   │   ├── screens/
│   │   │   ├── home_screen.dart (Android/iOS)
│   │   │   ├── student_subjects_screen.dart (Android/iOS)
│   │   │   └── qr_code_scanner_screen.dart (Android only)
│   │   ├── models/
│   │   │   └── exam_student.dart
│   │   ├── services/
│   │   │   ├── storage_service.dart (Wrapper)
│   │   │   ├── b2b_storage_service.dart (Android/iOS)
│   │   │   └── session_service.dart
│   │   └── presentation/
│   │       └── widgets/
│   │           └── secure_network_image.dart (Shared)
│   │
│   └── web/ (WEB ONLY)
│       ├── screens/
│       │   └── web_student_subjects_screen.dart ⭐
│       └── services/
│           └── web_storage_service.dart ⭐
├── supabase/
│   └── functions/
│       └── b2-storage-proxy/
│           └── index.ts (Used by both app & web)
```

---

## Key Differences

### 1. Photo Upload

| Feature | Android/iOS | Web |
|---------|------------|-----|
| **Upload Method** | Direct B2 bucket | Supabase Edge Function API |
| **Service** | `StorageService` + `B2BStorageService` | `WebStorageService` |
| **Path Format** | `EXAM_CENTER/2026/SEAT_NO/SUBJECT/DATE/TIMESTAMP/entry.jpg` | Same |
| **File Size Limit** | ~100KB (compressed) | ~1MB (web upload allowed) |
| **Security** | B2 bucket configured | API gateway via Supabase |

### 2. Photo Display

| Feature | Both Web & App |
|---------|----------------|
| **Widget** | `SecureNetworkImage` (shared) |
| **Caching** | Version-based cache keys |
| **Profile Photos** | `cachePhotos: false` (always fresh) |
| **Entry Photos** | `cachePhotos: false` (always fresh) |
| **SR NO** | Fetched from database |

---

## File Mapping

### Shared Between Web & App
```
✅ lib/models/exam_student.dart
✅ lib/services/storage_service.dart (wrapper)
✅ lib/services/session_service.dart
✅ lib/core/supabase_client.dart
✅ lib/presentation/widgets/secure_network_image.dart
✅ lib/core/theme/app_ui.dart
```

### Android/iOS Only
```
📱 lib/screens/home_screen.dart
📱 lib/screens/student_subjects_screen.dart
📱 lib/screens/qr_code_scanner_screen.dart
📱 lib/services/b2b_storage_service.dart
```

### Web Only
```
🌐 lib/web/screens/web_student_subjects_screen.dart
🌐 lib/web/services/web_storage_service.dart
```

---

## Upload Flow Comparison

### Android/iOS Upload Flow
```
1. Capture photo (Camera)
2. Compress to <100KB (B2BStorageService)
3. Upload directly to B2 bucket (B2 API)
4. B2 returns file URL
5. Save URL to database
6. Display photo with SecureNetworkImage (cachePhotos: false)
```

**Code Location:** `lib/services/b2b_storage_service.dart` → `uploadAttendancePhoto()`

### Web Upload Flow
```
1. Capture photo (Web Canvas/File API)
2. Compress to <1MB (web_storage_service.dart)
3. Call Supabase Edge Function API
4. Edge function uploads to B2 on behalf of web client
5. Edge function returns file URL
6. Save URL to database
7. Display photo with SecureNetworkImage (cachePhotos: false)
```

**Code Location:** `lib/web/services/web_storage_service.dart` → `uploadEntryPhotoWeb()`

---

## Web Storage Service Details

### Upload Endpoint
```
POST /functions/v1/b2-storage-proxy

Headers:
  Content-Type: application/json
  Authorization: Bearer {SUPABASE_ANON_KEY}

Body:
{
  "action": "upload_file",
  "storagePath": "EXAM_CENTER/2026/SEAT_NO/SUBJECT/DATE/TIMESTAMP/entry.jpg",
  "photoData": "base64_encoded_photo_bytes"
}

Response:
{
  "url": "https://f004.backblazeb2.com/file/attendance-students-photos/...",
  "fileId": "file_id_for_deletion",
  "path": "EXAM_CENTER/2026/SEAT_NO/SUBJECT/DATE/TIMESTAMP/entry.jpg"
}
```

### Key Features
- ✅ Base64 encoding for photo transmission
- ✅ Timeout: 30 seconds
- ✅ Same path format as Android/iOS
- ✅ Uses Supabase authentication
- ✅ Supports deletion via fileId

---

## Platform Detection

### Using kIsWeb
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (kIsWeb) {
  // Use WebStorageService
  await WebStorageService.uploadEntryPhotoWeb(...);
} else {
  // Use B2BStorageService (Android/iOS)
  await StorageService.uploadAttendancePhoto(...);
}
```

### Platform-Specific Screens
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

// In navigation logic:
if (kIsWeb) {
  Navigator.push(context, 
    MaterialPageRoute(builder: (_) => WebStudentSubjectsScreen(student: student))
  );
} else {
  Navigator.push(context, 
    MaterialPageRoute(builder: (_) => StudentSubjectsScreen(student: student))
  );
}
```

---

## Database Schema (Shared)

Both web and app save to the same `exam_students` table:

```sql
- id: UUID (primary key)
- student_name: text
- seat_no: text
- sr_no: text  -- ✅ Fetched from database
- subject_name: text
- exam_date: date
- start_time: time
- batch: text
- centre_code: text
- entry_photo_url: text  -- ✅ Same format from both web & app
- entry_at: timestamp
- entry_latitude: float (app only)
- entry_longitude: float (app only)
- photo_url: text (passport photo)
- is_enabled: boolean
```

---

## Cache Keys (Shared Strategy)

### Profile Photo Cache Key
```dart
'student_face_${id}_${photoVersion}'
```
- Includes student ID
- Includes version for cache busting
- When version changes, old cache is ignored

### Entry Photo Cache Key
```dart
'entry_${examStudentId}_${photoUrl?.hashCode ?? ''}'
```
- Unique per subject
- Includes URL hash
- Automatically busts when URL changes

### No Disk Caching for Entry/Profile Photos
```dart
SecureNetworkImage(
  cachePhotos: false,  // Always fetch fresh
  ...
)
```

---

## Screenshot & Camera (Platform-Specific)

### Android/iOS
```dart
// Uses camera package
import 'package:camera/camera.dart';

// Capture directly from camera
final XFile photo = await controller.takePicture();
List<int> bytes = await photo.readAsBytes();
```

**Location:** `lib/screens/student_subjects_screen.dart` → `_onEntryTap()`

### Web
```dart
// TODO: Implement web camera via HTML5 Canvas API
// Options:
// 1. getUserMedia() for webcam
// 2. Canvas for drawing/cropping
// 3. File upload fallback

// Currently shows placeholder message
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Camera not yet implemented for web'))
);
```

**Location:** `lib/web/screens/web_student_subjects_screen.dart` → `_onEntryTap()`

---

## QR Scanner (Android Only)

```dart
import 'package:mobile_scanner/mobile_scanner.dart';

// Only available on Android/iOS
if (!kIsWeb) {
  // Show QR scanner
  Navigator.push(context, 
    MaterialPageRoute(builder: (_) => QrCodeScannerScreen())
  );
} else {
  // Web: show manual student search instead
  // TODO: Implement web student search screen
}
```

**Location:** `lib/screens/qr_code_scanner_screen.dart`

---

## API Endpoints Comparison

### Android/iOS (Direct B2)
```
PUT https://pod000.backblazeb2.com/b2api/v2/b2_upload_file/...
  (Direct B2 upload with auth token)
```

### Web (Via Edge Function)
```
POST https://{supabase-url}/functions/v1/b2-storage-proxy
  (Supabase Edge Function relays upload to B2)
```

---

## Testing Checklist

### Shared Features (Both Web & App)
- [x] SR NO displays correctly
- [x] Subject data loads from database
- [x] Photo caching with version keys works
- [x] Entry photos always fresh (cachePhotos: false)
- [x] Profile photos always fresh
- [x] Secure network image handles missing photos
- [x] URL generation works for B2 photos

### Android/iOS Specific
- [x] Direct B2 upload works
- [x] Camera capture works
- [x] QR scanner works
- [x] Photos compress to <100KB
- [x] GPS coordinates save correctly

### Web Specific
- [ ] Edge Function API upload works
- [ ] Base64 encoding/decoding works
- [ ] Photos handle <1MB size
- [ ] Web camera capture (TODO)
- [ ] File upload fallback (TODO)

---

## Build Commands

### Build for Android
```bash
flutter build apk --target=lib/main.dart
```

### Build for Web
```bash
flutter build web --target=lib/main.dart
```

Note: Platform detection is automatic via `kIsWeb`

---

## Environment Variables

Both web and app use same Supabase config:
```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
```

B2 configuration is in:
```
lib/config/b2b_storage_config.dart
```

---

## Future Enhancements

### Web Camera Implementation
```dart
// In lib/web/screens/web_student_subjects_screen.dart
// TODO: Add getUserMedia() for webcam access
// TODO: Add Canvas API for photo capture
// TODO: Add file upload fallback for drag-drop
```

### Web Search Screen
```dart
// In lib/web/screens/
// TODO: Create web_home_screen.dart (student search instead of QR)
// TODO: Create web_qr_search_screen.dart (manual QR entry)
```

---

## Troubleshooting

### Photo shows old image on web
- Clear browser cache
- Check version key in cache key
- Verify `cachePhotos: false` is set

### Upload fails on web
- Check Supabase anon key
- Verify Edge Function is running
- Check console for CORS errors
- Verify photo size < 1MB

### Upload works but photo doesn't display
- Check database entry_photo_url field
- Verify B2 bucket permissions
- Check SecureNetworkImage error logs
- Clear app cache and retry

---

## Summary

✅ **Web & App Separation Complete**
- Platform-specific upload services
- Shared display & caching logic
- Same database schema
- Version-based cache keys prevent old photos
- Web uploads via API, App uploads direct to B2
