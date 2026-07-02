# StudioArch Image Upload & Fetch Pattern ✅

## How StudioArch Does It Correctly

### 1. **UPLOAD FLOW**

```typescript
// File: src/utils/b2-upload.ts
// Sanitize filename → Compress image → Upload via /api/b2-upload → Get proxy URL → Save to database
```

**Step-by-step:**

```typescript
async function uploadToB2(file: File, fileName: string): Promise<{url?: string}> {
  // 1. Sanitize filename
  const sanitizedFileName = fileName.replace(/\s+/g, '_');
  
  // 2. Upload to Vercel API endpoint
  const response = await fetch('/api/b2-upload', {
    method: 'POST',
    headers: {
      'X-File-Name': sanitizedFileName,
      'Content-Type': file.type,
    },
    body: file,
  });
  
  // 3. Get response (proxy URL)
  const data = await response.json();
  return { url: data.url }; // e.g., "/api/b2-upload?key=images/123_photo.jpg"
}
```

**In Admin.tsx:**

```typescript
// Upload compressed image
const uploadResult = await uploadToB2(compressedFile, `images/${Date.now()}_${name}`);

if (uploadResult.success) {
  // Save PROXY URL to database (not direct B2 URL)
  await insertGalleryItem('gallery_items', {
    image_url: uploadResult.url,  // ✅ Save this: /api/b2-upload?key=...
    title: newImageTitle,
    folder_id: folderId
  });
}
```

---

### 2. **STORAGE IN DATABASE**

| Field | Value | Format |
|-------|-------|--------|
| `image_url` | `/api/b2-upload?key=images/123_photo.jpg` | Proxy URL |
| `url` (videos) | `/api/b2-upload?key=videos/456_video.mp4` | Proxy URL |

**Never store:**
- Direct B2 URLs (https://f004.backblazeb2.com/...)
- Raw object paths
- Signed URLs (they expire)

---

### 3. **FETCH FROM DATABASE**

```typescript
// In useGallery() hook - fetches from Supabase
const { data: galleryFolders } = useGallery();

// Loop through folders
galleryFolders.forEach((folder) => {
  folder.gallery_items.forEach((item) => {
    allImages.push({
      id: item.id,
      url: item.image_url,  // Already a proxy URL from database
      title: item.title
    });
  });
});
```

---

### 4. **DISPLAY IMAGES**

```typescript
// File: src/components/AdminImageDisplay.tsx
export function AdminImageDisplay({ src, alt, className }: Props) {
  const [hasError, setHasError] = useState(false);
  
  return (
    <img
      src={src}  // src = "/api/b2-upload?key=images/123_photo.jpg" (proxy URL)
      alt={alt}
      onError={() => {
        console.error('Image failed to load:', src);
        setHasError(true);
      }}
    />
  );
}
```

**The browser requests:** `GET /api/b2-upload?key=images/123_photo.jpg`
**Vercel API handler handles:**
1. Get B2 auth token
2. Download file from B2
3. Return it with proper CORS headers

---

### 5. **URL MANIPULATION (b2MediaUrls.js)**

```typescript
/**
 * Build proxy URL for displaying images
 */
export function buildB2DisplayUrl(stored) {
  const key = extractB2ObjectKey(stored);
  if (!key) return stored;
  return `/api/b2-upload?key=${encodeURIComponent(key)}`;
}

/**
 * Extract object key from any format
 */
export function extractB2ObjectKey(stored) {
  // Handle direct paths: "images/123.jpg"
  if (/^(images|videos)\//.test(stored)) {
    return stored;
  }
  
  // Handle proxy URLs: "/api/b2-upload?key=images/123.jpg"
  if (stored.includes('/api/b2-upload?')) {
    const url = new URL(stored, window.location.origin);
    return url.searchParams.get('key');
  }
  
  // Handle full B2 URLs
  // Extract object key and return it
  return null;
}
```

---

## Key Differences (StudioArch vs MSCEEXAMAPP)

| Aspect | StudioArch ✅ | MSCEEXAMAPP ❌ |
|--------|-------------|----------------|
| **Upload endpoint** | `/api/b2-upload` (Vercel) | Calling Supabase function |
| **Store in DB** | Proxy URL `/api/b2-upload?key=...` | Same (but build is stale) |
| **Display** | Browser requests proxy URL | Can't display (API blocked) |
| **Web build** | Fresh & updated | Stale (old compiled Dart) |
| **CORS handling** | Vercel API handles it | Supabase blocked CORS |

---

## SOLUTION FOR MSCEEXAMAPP

1. **Rebuild Flutter web** (on your Mac):
   ```bash
   cd ~/Desktop/PROJECTS/MSCEEXAMAPP
   flutter clean
   flutter build web --release
   ```

2. **Verify code is updated:**
   - `lib/services/b2b_storage_service.dart` already uses `https://msceexamapp.vercel.app/api/b2-upload` ✅
   - The web build will include this

3. **Commit & deploy:**
   ```bash
   git add .
   git commit -m "Rebuild web with Vercel API integration"
   git push
   vercel --prod
   ```

4. **Clear browser cache** and reload
   - Old compiled JavaScript blocked the new uploads

---

## Verify Vercel API Works

**Check function logs:**
```bash
vercel logs --prod
```

**Should see:**
```
✅ Authorizing with B2...
📍 Getting upload URL...
⬆️ Uploading to B2...
✅ Upload successful, proxy URL: /api/b2-upload?key=EXAM_CENTER/2026/...
```

Then web app should display photos without CORS errors.
