# Debug Photo Display - Complete Checklist

Your code is **100% correct**! Photos not showing means one of these steps failed.

---

## Step 1: Verify Upload

**In home_screen.dart line 972:**
```dart
final photoUrl = uploadResult['url'] ?? photo.path;
print('✅ Photo uploaded: $photoUrl');
```

**Check console output:**
```
✅ Photo uploaded: /api/b2-upload?key=EXAM_CENTER/2026/...
```

❌ If you see `photo.path` instead of `/api/b2-upload`, upload failed.

---

## Step 2: Verify Database Storage

**Query the database directly:**

```dart
// In your debug code or Firebase console
final record = await supabase
    .from('exam_students')
    .select('id, entry_photo_url')
    .eq('exam_student_id', 'student_id_here')
    .eq('subject_name', 'subject_code_here')
    .single();

print('📸 Stored URL: ${record['entry_photo_url']}');
```

**Should print:**
```
📸 Stored URL: /api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg
```

❌ If null or empty → Upload wasn't called
❌ If starts with `http` → Direct B2 URL (expired, won't work)

---

## Step 3: Verify Widget Displays

**In home_screen.dart around line 704:**

```dart
if (isMarked && subject['entry_photo_url'] != null)
  SecureNetworkImage(
    cacheKey: 'entry_${subject['id']}',
    imageUrl: subject['entry_photo_url'],  // ← Proxy URL from DB
    fit: BoxFit.cover,
  )
```

**Check:**
- ✅ `isMarked` is `true` (line 633: checks `entry_photo_url` is not null/empty)
- ✅ `subject['entry_photo_url']` is not null
- ✅ Value starts with `/api/b2-upload?key=`

**If widget not showing:**

```dart
// Add debug output
print('isMarked=$isMarked');
print('entry_photo_url=${subject['entry_photo_url']}');
print('photoUrl type: ${subject['entry_photo_url'].runtimeType}');
```

---

## Step 4: Verify Vercel API

**Manually test the proxy URL in browser:**

```
https://msceexamapp.vercel.app/api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg
```

**Should:**
- ✅ Show the image directly in browser
- ❌ NOT show CORS error
- ❌ NOT show 401/403 error

**If CORS error:**
```
Access to fetch at '...' from origin '...' has been blocked by CORS policy
```
→ Vercel API not returning CORS headers. Check `/api/b2-upload.js`.

**If 404:**
→ File not in B2. Check if B2 credentials are correct.

---

## Step 5: Full Debugging Code

Add this to your home_screen to debug:

```dart
// In _SubjectEntryRow or wherever you display photo
void _debugPhotoDisplay(Map<String, dynamic> subject) {
  final isMarked = subject['entry_photo_url'] != null && 
                   subject['entry_photo_url'].toString().isNotEmpty;
  final photoUrl = subject['entry_photo_url']?.toString() ?? '';
  
  print('=== PHOTO DEBUG ===');
  print('ID: ${subject['id']}');
  print('isMarked: $isMarked');
  print('photoUrl: $photoUrl');
  print('photoUrl starts with /api: ${photoUrl.startsWith('/api/b2-upload')}');
  print('photoUrl type: ${photoUrl.runtimeType}');
  print('photoUrl length: ${photoUrl.length}');
  
  if (photoUrl.isNotEmpty) {
    print('Full URL would be: https://msceexamapp.vercel.app$photoUrl');
  }
  print('==================');
}

// Call in build method
_debugPhotoDisplay(subject);
```

**Expected console output:**
```
=== PHOTO DEBUG ===
ID: 12345
isMarked: true
photoUrl: /api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg
photoUrl starts with /api: true
photoUrl type: String
photoUrl length: 95
Full URL would be: https://msceexamapp.vercel.app/api/b2-upload?key=EXAM_CENTER/2026/2307160093/english_40/2026-07-02/entry.jpg
==================
```

---

## Step 6: Check SecureNetworkImage Logs

**In secure_network_image.dart, it prints debug messages:**

```dart
if (kDebugMode) debugPrint('Error generating temporary photo URL: $e');
if (kDebugMode) debugPrint('⚠️ Web byte fetch failed, using <img>: $e');
if (kDebugMode) debugPrint('❌ Image byte validation failed: $e');
```

**Look for these in console.**

---

## Step 7: Browser Cache

**If everything above passes but photos still not showing:**

1. **Clear cache:**
   - DevTools → Application → Clear all site data
   - Hard refresh: Cmd+Shift+R (Mac) or Ctrl+Shift+R (Windows)

2. **Check Network tab:**
   - Open DevTools → Network
   - Take photo and upload
   - Look for requests to `/api/b2-upload?key=...`
   - Should show 200 status
   - Response should be image binary data

---

## Complete Test Flow

```dart
// 1. Upload photo
final uploadResult = await StorageService.uploadAttendancePhoto(...);
final photoUrl = uploadResult['url'];
debugPrint('1️⃣ Upload result: $photoUrl');

// 2. Save to database
await entryService.markSubjectEntry(..., photoPath: photoUrl);
debugPrint('2️⃣ Saved to database');

// 3. Fetch from database
final record = await supabase
    .from('exam_students')
    .select('entry_photo_url')
    .single();
debugPrint('3️⃣ Fetched from DB: ${record['entry_photo_url']}');

// 4. Display in widget
// SecureNetworkImage(imageUrl: record['entry_photo_url'])
debugPrint('4️⃣ Displaying in widget');
```

**All 4 steps should show `/api/b2-upload?key=...`**

---

## Most Common Issues

| Issue | Check | Fix |
|-------|-------|-----|
| Photos not showing | Step 2: DB storage | Is `entry_photo_url` column being updated? |
| Widget says "Failed to load" | Step 4: Vercel API | Is `/api/b2-upload.js` deployed? |
| Blank space where photo should be | Step 1: Upload | Did upload return proxy URL or fallback to `photo.path`? |
| Photo shows for 1 second then disappears | Browser cache | Hard refresh cache |
| CORS error in console | Step 4: API headers | Check Vercel API returns `Access-Control-Allow-Origin: *` |

---

## If Nothing Works

1. **Check Vercel deployment:**
   ```bash
   vercel list-deployments
   vercel logs --prod
   ```

2. **Check B2 is configured:**
   ```bash
   vercel env list --prod
   ```
   Should show: `B2_KEY_ID`, `B2_MASTER_KEY`, `B2_BUCKET_NAME`, `B2_BUCKET_ID`

3. **Check database column exists:**
   ```sql
   SELECT column_name FROM information_schema.columns 
   WHERE table_name='exam_students' AND column_name='entry_photo_url';
   ```

4. **Check Flutter build is fresh:**
   ```bash
   flutter clean
   flutter build web --release
   git status
   ```

---

**Run the debug code above and share the console output.**
