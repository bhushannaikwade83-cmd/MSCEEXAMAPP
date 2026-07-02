# Photo Display Quick Start - Apply It Now

## You Already Have It! ✅

Your code has `SecureNetworkImage` widget that handles everything:
- ✅ Converts storage paths to display URLs
- ✅ Handles proxy URLs with query params
- ✅ Retries with fresh auth on 401 errors  
- ✅ Bakes EXIF orientation on web
- ✅ Falls back to `<img>` element on CORS failure

**Location:** `lib/presentation/widgets/secure_network_image.dart`

---

## How to Use It

### Simple Usage

```dart
import 'package:msceexamapp/presentation/widgets/secure_network_image.dart';

// Display entry photo from database
SecureNetworkImage(
  imageUrl: entryPhotoUrl,  // "/api/b2-upload?key=EXAM_CENTER/..." from DB
  width: 200,
  height: 200,
  fit: BoxFit.cover,
)
```

### With Error & Loading Widgets

```dart
SecureNetworkImage(
  imageUrl: entryPhotoUrl,
  width: 200,
  height: 200,
  fit: BoxFit.cover,
  placeholder: Center(
    child: CircularProgressIndicator(),
  ),
  errorWidget: Container(
    color: Colors.grey[300],
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image, color: Colors.red),
        SizedBox(height: 8),
        Text('Failed to load photo'),
      ],
    ),
  ),
)
```

### With Storage Path (Alternative)

```dart
SecureNetworkImage(
  storagePath: 'EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg',
  // Widget will fetch temp URL automatically
  width: 200,
  height: 200,
)
```

---

## In Your Home Screen

### Display Entry/Exit Photos Together

```dart
import 'package:msceexamapp/presentation/widgets/secure_network_image.dart';

class StudentPhotoCard extends StatelessWidget {
  final String? entryPhotoUrl;
  final String? exitPhotoUrl;
  final String studentName;

  const StudentPhotoCard({
    required this.entryPhotoUrl,
    required this.exitPhotoUrl,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(studentName, style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Row(
              children: [
                // Entry Photo
                Expanded(
                  child: Column(
                    children: [
                      Text('Entry'),
                      Expanded(
                        child: entryPhotoUrl == null || entryPhotoUrl!.isEmpty
                            ? Container(
                                color: Colors.grey[300],
                                child: Center(child: Text('No entry photo')),
                              )
                            : SecureNetworkImage(
                                imageUrl: entryPhotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  color: Colors.grey[300],
                                  child: Icon(Icons.error, color: Colors.red),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                // Exit Photo
                Expanded(
                  child: Column(
                    children: [
                      Text('Exit'),
                      Expanded(
                        child: exitPhotoUrl == null || exitPhotoUrl!.isEmpty
                            ? Container(
                                color: Colors.grey[300],
                                child: Center(child: Text('No exit photo')),
                              )
                            : SecureNetworkImage(
                                imageUrl: exitPhotoUrl,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  color: Colors.grey[300],
                                  child: Icon(Icons.error, color: Colors.red),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## Fetch Photos from Database

```dart
// Fetch attendance record with photos
final attendanceRecord = await supabase
    .from('attendance')
    .select('entry_photo_url, exit_photo_url, student_name')
    .eq('student_id', studentId)
    .single();

final entryUrl = attendanceRecord['entry_photo_url'] as String?;
final exitUrl = attendanceRecord['exit_photo_url'] as String?;
final name = attendanceRecord['student_name'] as String;

// Display
StudentPhotoCard(
  entryPhotoUrl: entryUrl,  // e.g., "/api/b2-upload?key=..."
  exitPhotoUrl: exitUrl,    // e.g., "/api/b2-upload?key=..."
  studentName: name,
)
```

---

## Key Points

1. **Store proxy URLs in database:**
   ```
   /api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg
   ```

2. **Pass directly to SecureNetworkImage:**
   ```dart
   SecureNetworkImage(imageUrl: entryPhotoUrl)
   ```

3. **Widget handles everything:**
   - ✅ Converts query params properly
   - ✅ Retries on 401 errors
   - ✅ Bakes EXIF on web
   - ✅ Falls back to `<img>` element on CORS failure

4. **No manual URL manipulation needed**

---

## Troubleshooting

### Photos Still Not Showing?

1. **Check database has proxy URL:**
   ```dart
   print('Stored URL: $entryPhotoUrl');
   // Should print: /api/b2-upload?key=...
   ```

2. **Check Vercel logs:**
   ```bash
   vercel logs --prod
   ```
   Should show: `✅ Upload successful, proxy URL: /api/b2-upload?key=...`

3. **Clear browser cache:**
   - DevTools → Application → Clear all site data

4. **Check if upload succeeded:**
   - Look at database `entry_photo_url` field
   - Should NOT be null/empty
   - Should start with `/api/b2-upload?key=`

---

## That's It!

You have everything. Just use `SecureNetworkImage` with proxy URLs from your database. ✅
