# Website Photo Loading Architecture

## **Overview**
Website loads student photos from database using a multi-layer approach with automatic B2 signing, Supabase storage support, and intelligent caching.

---

## **1. Database Fields (Field Detection)**

**QuickSearchSection** loads students with:
```typescript
const raw = await fetchAllPaged<QuickStudent>((rangeFrom, rangeTo) =>
  sb.from('students')
    .select('*')
    .eq('institute_id', selectedInstituteId)
    .order('id', { ascending: true })
    .range(rangeFrom, rangeTo),
)
```

**Photo column detection order** (`photoUrl.ts`):
```typescript
// Tries these fields in order:
'face_photo_url',              // ✅ Primary
'facePhotoUrl',
'photo_url',                   // ✅ Alternative
'photoUrl',
'profile_photo',
'avatar_url',
'image_url',
'face_image_url',
'student_photo_url',
'registration_photo_url',

// Also checks storage paths:
'registration_photo_path',
'photo_path',
'photoPath',
```

---

## **2. Photo URL Resolution (3 Layers)**

### **Layer 1: Immediate URLs** (No signing needed)
- Direct HTTP/HTTPS from public CDNs
- Example: `https://cdn.example.com/photo.jpg`
- **Check:** `immediateImgSrc()` - returns URL if it's not B2

### **Layer 2: B2 Cloud Storage** (Needs signing)
```typescript
// Requests via Supabase Function
await sb.functions.invoke('b2-storage-proxy', {
  body: { 
    action: 'download_auth',
    objectPath: 'path/to/photo.jpg',
    validSeconds: 3600
  },
})
// Returns: { authorizationToken, downloadUrl, bucketName }
// Result: https://f001.backblazeb2.com/file/bucket/path?Authorization=xxx
```

**Fallback:** `/api/b2-sign-photo` Vite endpoint (dev)

### **Layer 3: Supabase Storage** (Internal paths)
```typescript
// For raw storage paths like "student-photos/123.jpg"
const { data } = await sb.storage
  .from('bucket-name')
  .createSignedUrl('student-photos/123.jpg', 3600)
// Returns signed URL valid for 1 hour
```

---

## **3. Caching Strategy**

### **Memory Cache** (Fastest)
```typescript
signedUrlMemoryCache.set(cacheKey, url)
// Example: signedUrlMemoryCache.set('student_face_abc123', 'https://...')
```

### **Persistent Cache** (localStorage)
```typescript
localStorage.setItem('msce_photo_url_cache', JSON.stringify({
  'student_photos/123.jpg': { 
    url: 'https://...', 
    timestamp: 1234567890 
  }
}))
// TTL: 1 hour (3600000ms)
```

### **Request Deduplication**
Multiple simultaneous requests for same URL return same Promise (avoid duplicate API calls)

---

## **4. React Component Flow**

```
QuickSearchSection
  ├─ Loads students from 'students' table
  │  └─ Each student has photo_url / registration_photo_path
  │
  └─ Renders table with StudentDisplayPhoto for each photo
     └─ <StudentDisplayPhoto student={student} size="sm" />
        │
        ├─ Calls studentPhotoSources(student)
        │  └─ Extracts: photoUrl, storagePath, version, thumbnail
        │
        └─ Renders <SecureNetworkImage />
           │
           └─ Calls getTemporaryPhotoUrl({ photoUrl, storagePath })
              │
              ├─ Check memory cache ✓ (if cached, return immediately)
              ├─ Check request dedup cache ✓ (if pending, await)
              ├─ Else: Trigger resolution:
              │  ├─ If storagePath → Try B2 signing + Supabase signing
              │  └─ If photoUrl → Try B2 signing (if B2 URL) + HTTP passthrough
              │
              └─ Return signed URL → <img src={signedUrl} />
```

---

## **5. Table Display** (QuickSearchSection - Line 430-454)

```jsx
{filteredStudents.map((student) => (
  <tr key={student.id}>
    {/* Original Photo - if exists */}
    <td className="students-photo-cell">
      {hasOriginalPhoto(student) ? (
        <StudentDisplayPhoto
          student={{...student, 
            face_photo_url: student.original_face_photo_url,
            registration_photo_path: student.original_registration_photo_path
          }}
          displayName={`${name} original`}
          size="sm"
          clickable
        />
      ) : (
        <span className="muted small">No old photo</span>
      )}
    </td>

    {/* Current Photo */}
    <td className="students-photo-cell">
      {hasCurrentPhoto(student) ? (
        <StudentDisplayPhoto 
          student={student} 
          displayName={name} 
          size="sm" 
          clickable 
        />
      ) : (
        <span className="muted small">No photo</span>
      )}
    </td>
  </tr>
))}
```

---

## **6. Database Schema (exam_students)**

For **ExamStudentsPage**, use same pattern:

```sql
-- Expected columns
photo_url              -- Direct URL or B2 path
-- OR
registration_photo_path -- Supabase storage path
-- Optional
photo_thumbnail        -- Base64 thumbnail for instant display
photo_version          -- Cache busting version
```

---

## **7. Implementation for ExamStudentsPage**

**Option A: Use Website's StudentDisplayPhoto Component** ✅ Recommended
```jsx
import { StudentDisplayPhoto } from '@/admin/components/StudentDisplayPhoto'

// In your table
<td>
  {student.photo_url ? (
    <StudentDisplayPhoto 
      student={student}
      displayName={student.student_name}
      size="sm"
      clickable
    />
  ) : (
    <div>📸</div>
  )}
</td>
```

**Option B: Use SecureNetworkImage Directly**
```jsx
import { SecureNetworkImage } from '@/admin/components/SecureNetworkImage'

<SecureNetworkImage
  imageUrl={student.photo_url}
  storagePath={student.registration_photo_path}
  cacheKey={`exam_student_${student.id}`}
  alt={student.student_name}
  className="photo-thumb"
  errorWidget={<div>📸</div>}
/>
```

**Option C: Manual Resolution** (if component unavailable)
```jsx
import { getTemporaryPhotoUrl } from '@/admin/lib/photoUrl'

const [photoUrl, setPhotoUrl] = useState<string | null>(null)

useEffect(() => {
  (async () => {
    const url = await getTemporaryPhotoUrl({
      photoUrl: student.photo_url,
      storagePath: student.registration_photo_path
    })
    setPhotoUrl(url)
  })()
}, [student.photo_url, student.registration_photo_path])

<img src={photoUrl || ''} alt={student.student_name} />
```

---

## **8. Key Features**

✅ **Automatic B2 Signing** - B2 URLs get fresh temp access tokens via Supabase Function  
✅ **Supabase Storage Support** - Raw paths signed automatically  
✅ **Multi-layer Caching** - Memory + localStorage + request dedup  
✅ **CORS-Safe** - No direct B2 access, all via Supabase proxy  
✅ **Fallback Thumbnails** - Base64 thumbnail shown while loading  
✅ **Retry Logic** - 2 retries on img load failure  
✅ **Lazy Loading** - Images load async, decoding="async"  
✅ **Photo Comparison** - Original vs current face photos in QuickSearch  

---

## **9. Testing Photos**

In website's QuickSearchSection:
1. Select a district
2. Select institute  
3. Photos load in 2 columns: "Original photo" & "Current photo"
4. Click any photo to view full size
5. Check browser DevTools → Network → see B2 signed URLs being fetched

---

## **10. Common Issues & Solutions**

| Issue | Cause | Solution |
|-------|-------|----------|
| Photos won't load | B2 signing failed | Check `b2-storage-proxy` function is deployed |
| Blurry photos | Using small thumbnail | Increase image size, load full resolution |
| Cache too old | 1-hour TTL expired | Clear localStorage: `localStorage.removeItem('msce_photo_url_cache')` |
| 403/401 errors | B2 token expired | B2 auth renewal is automatic every request |
| CORS errors | Direct B2 access attempted | Use `getTemporaryPhotoUrl()` not direct fetch |

