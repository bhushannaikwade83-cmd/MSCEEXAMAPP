# How to Display Photos in Flutter - StudioArch Pattern

## The Key Insight

**StudioArch stores PROXY URLs in database:**
```
/api/b2-upload?key=images/123_photo.jpg
```

**When displaying:**
```
<img src="/api/b2-upload?key=images/123_photo.jpg" />
```

Browser requests: `GET /api/b2-upload?key=images/123_photo.jpg`
Vercel API handler: Fetches from B2 + returns with CORS headers ✅

---

## Flutter Display Code

### 1. **Store PROXY URL in Database**

When you upload and get back:
```dart
{
  "url": "/api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg",
  "path": "EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg",
  "fileId": "xyz123"
}
```

**Save `url` field to database (the proxy URL)** ✅

---

### 2. **Fetch Photo URLs from Database**

```dart
// In your Flutter code
final attendanceRecord = await supabase
    .from('attendance')
    .select('entry_photo_url, exit_photo_url')
    .eq('student_id', studentId)
    .single();

final entryPhotoUrl = attendanceRecord['entry_photo_url'] as String?;
// e.g., "/api/b2-upload?key=EXAM_CENTER/2026/..."
```

---

### 3. **Display Photos Without Errors**

**❌ WRONG - Don't do this:**
```dart
// This tries to fetch relative URL from Flutter app
CachedNetworkImage(
  imageUrl: entryPhotoUrl,  // "/api/b2-upload?key=..."
  // ERROR: Can't load relative URL in mobile/web
)
```

**✅ RIGHT - Do this:**
```dart
// For web & mobile: Convert to absolute URL
String getPhotoDisplayUrl(String? photoUrl) {
  if (photoUrl == null || photoUrl.isEmpty) return '';
  
  // Already absolute (from studioarch)
  if (photoUrl.startsWith('http')) {
    return photoUrl;
  }
  
  // Proxy URL - convert to absolute
  if (photoUrl.startsWith('/api/b2-upload')) {
    return 'https://msceexamapp.vercel.app$photoUrl';
  }
  
  // Plain object path - convert to proxy URL
  if (photoUrl.contains('/')) {
    final encoded = Uri.encodeComponent(photoUrl);
    return 'https://msceexamapp.vercel.app/api/b2-upload?key=$encoded';
  }
  
  return '';
}

// Use it:
CachedNetworkImage(
  imageUrl: getPhotoDisplayUrl(entryPhotoUrl),
  // Now it's: https://msceexamapp.vercel.app/api/b2-upload?key=EXAM_CENTER/...
  placeholder: (context, url) => Placeholder(),
  errorWidget: (context, url, error) => Icon(Icons.error),
)
```

---

### 4. **Full Example - Display Entry/Exit Photos**

```dart
import 'package:cached_network_image/cached_network_image.dart';

class AttendancePhotoDisplay extends StatelessWidget {
  final String? entryPhotoUrl;
  final String? exitPhotoUrl;

  const AttendancePhotoDisplay({
    required this.entryPhotoUrl,
    required this.exitPhotoUrl,
  });

  String _getAbsoluteUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http')) return url;
    if (url.startsWith('/api/b2-upload')) {
      return 'https://msceexamapp.vercel.app$url';
    }
    // Object path
    final encoded = Uri.encodeComponent(url);
    return 'https://msceexamapp.vercel.app/api/b2-upload?key=$encoded';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Entry Photo
        Expanded(
          child: Column(
            children: [
              Text('Entry Photo'),
              Container(
                height: 200,
                color: Colors.grey[300],
                child: entryPhotoUrl == null || entryPhotoUrl!.isEmpty
                    ? Center(child: Text('No entry photo'))
                    : CachedNetworkImage(
                        imageUrl: _getAbsoluteUrl(entryPhotoUrl),
                        placeholder: (ctx, url) => CircularProgressIndicator(),
                        errorWidget: (ctx, url, error) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            Text('Failed to load'),
                            Text(error.toString(), style: TextStyle(fontSize: 10)),
                          ],
                        ),
                        fit: BoxFit.cover,
                      ),
              ),
            ],
          ),
        ),
        SizedBox(width: 16),
        // Exit Photo
        Expanded(
          child: Column(
            children: [
              Text('Exit Photo'),
              Container(
                height: 200,
                color: Colors.grey[300],
                child: exitPhotoUrl == null || exitPhotoUrl!.isEmpty
                    ? Center(child: Text('No exit photo'))
                    : CachedNetworkImage(
                        imageUrl: _getAbsoluteUrl(exitPhotoUrl),
                        placeholder: (ctx, url) => CircularProgressIndicator(),
                        errorWidget: (ctx, url, error) => Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            Text('Failed to load'),
                          ],
                        ),
                        fit: BoxFit.cover,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

---

## Storage Format Comparison

| Source | Format | Usage |
|--------|--------|-------|
| **Vercel API response** | `/api/b2-upload?key=...` | Save this to DB ✅ |
| **Database stored** | `/api/b2-upload?key=...` | Fetch and use this |
| **Display in web** | `https://msceexamapp.vercel.app/api/b2-upload?key=...` | Absolute URL |
| **Display in mobile** | Same | Works on iOS/Android too |

---

## Why This Works

1. **No temp URLs** - Proxy URL never expires
2. **No CORS issues** - Vercel API handles CORS for all platforms
3. **No extra API calls** - Just store once, display directly
4. **Works everywhere** - Web, iOS, Android all use same URL

---

## Debugging Checklist

**If photos don't show:**

1. ✅ Check database has proxy URL:
   ```dart
   final record = await supabase
     .from('attendance')
     .select('entry_photo_url')
     .eq('id', attendanceId)
     .single();
   print('Stored URL: ${record['entry_photo_url']}');
   ```
   Should print: `/api/b2-upload?key=...`

2. ✅ Convert to absolute URL:
   ```dart
   final url = 'https://msceexamapp.vercel.app${record['entry_photo_url']}';
   print('Display URL: $url');
   ```

3. ✅ Test in browser:
   - Open DevTools
   - Paste the URL in address bar
   - Should show image (not CORS error)

4. ✅ If still error, check Vercel logs:
   ```bash
   vercel logs --prod
   ```

---

## Upload + Store Flow (Complete)

```dart
// 1. UPLOAD
final uploadResult = await StorageService.uploadAttendancePhoto(
  instituteId: '123',
  folderYear: '2026',
  rollNumber: '2307160093',
  subject: 'English',
  date: '2026-07-02',
  photoBytes: photoFile.readAsBytesSync(),
  photoType: 'entry',
);

// uploadResult.url = "/api/b2-upload?key=EXAM_CENTER/2026/..."

// 2. STORE in database
await supabase.from('attendance').update({
  'entry_photo_url': uploadResult['url'],  // ✅ Store proxy URL
  'entry_photo_path': uploadResult['path'],
}).eq('id', attendanceId);

// 3. FETCH from database
final record = await supabase
  .from('attendance')
  .select('entry_photo_url')
  .eq('id', attendanceId)
  .single();

// 4. DISPLAY
final displayUrl = 'https://msceexamapp.vercel.app${record['entry_photo_url']}';
CachedNetworkImage(imageUrl: displayUrl);
```

That's it! No temp URLs, no expiration, no extra complexity. ✅
