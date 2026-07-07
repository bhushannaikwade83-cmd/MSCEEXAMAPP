# ExamStudentsPage - Console Debug Output Guide

## **What You'll See in Console**

When you navigate to **Exam Students** and select a centre, the console will show detailed debug info about photo loading:

---

## **1. INITIAL LOAD** (Selecting a Centre)

```
🚀 LOADING STUDENTS FOR CENTRE
▼ {
    centreCode: "10101",
    timestamp: "2:34:56 PM"
  }

📊 Page 1: 1000 rows (total so far: 1000)
📊 Page 2: 1000 rows (total so far: 2000)
📊 Page 3: 874 rows (total so far: 2874)

✅ LOADED 2874 TOTAL STUDENTS
▼ {
    centreCode: "10101",
    totalCount: 2874,
    pagesScanned: 3
  }
```

---

## **2. PHOTO STATISTICS** (After grouping by student)

```
🎯 PHOTO LOADING DEBUG - ExamStudentsPage
✅ Grouped into 474 unique students

📊 Photo Statistics:
▼ {
    totalStudents: 474,
    withPhotos: "156 (32.9%)",
    withoutPhotos: "318 (67.1%)",
    photoTypeBreakdown: {
      "b2-url": 120,
      "supabase-url": 28,
      "http-url": 8
    }
  }
```

---

## **3. SAMPLE DATA** (First 5 students)

```
🔍 Sample Student Data (first 5):
  [1] Ramesh Kumar
    ▼ {
        photo_url: "https://f001.backblazeb2.com/file/msce-exams/students/ramesh_123.jpg...",
        institute_id: "INST001",
        centre_code: "10101",
        subjects: 3,
        seat_no: "A-001"
      }
  
  [2] Priya Singh
    ▼ {
        photo_url: "https://app.supabase.co/storage/v1/object/public/exams/priya_456.jpg...",
        institute_id: "INST002",
        centre_code: "10101",
        subjects: 2,
        seat_no: "A-002"
      }
  
  [3] Anisha Verma
    ▼ {
        photo_url: "❌ NO PHOTO",
        institute_id: "INST001",
        centre_code: "10101",
        subjects: 1,
        seat_no: "A-003"
      }
```

---

## **4. PHOTO RESOLUTION STRATEGY**

```
⚙️ Photo Resolution Strategy:
  Layer 1: Direct HTTP/HTTPS URLs (if available immediately)
  Layer 2: B2 Cloud Storage (needs b2-storage-proxy Supabase Function)
  Layer 3: Supabase Storage paths (createSignedUrl with 1-hour TTL)
  Caching: Memory cache + localStorage (1-hour TTL)
```

---

## **5. CACHE INFORMATION**

```
💾 Cache Info:
▼ {
    memoryCache: "signedUrlMemoryCache (built-in)",
    persistentCache: "localStorage key: msce_photo_url_cache",
    cacheTTL: "1 hour (3600000ms)",
    requestDedup: "Same URL requests await single Promise"
  }
```

---

## **6. TABLE RENDERING** (When you see the table)

```
🔍 TABLE RENDERING
▼ {
    selectedCentre: "10101",
    loading: false,
    totalStudents: 474,
    filteredStudents: 474,
    search: "(no filter)",
    timestamp: "2:35:12 PM"
  }
```

---

## **7. INDIVIDUAL STUDENT PHOTOS** (First 3 only)

```
📷 Student 1: Ramesh Kumar
▼ {
    photo_url: "https://f001.backblazeb2.com/file/msce-exams/studen...",
    hasPhoto: true,
    subjectsCount: 3,
    seatNo: "A-001",
    centreCode: "10101"
  }

📷 Student 2: Priya Singh
▼ {
    photo_url: "https://app.supabase.co/storage/v1/object/public...",
    hasPhoto: true,
    subjectsCount: 2,
    seatNo: "A-002",
    centreCode: "10101"
  }

📷 Student 3: Anisha Verma
▼ {
    photo_url: "❌ NO PHOTO",
    hasPhoto: false,
    subjectsCount: 1,
    seatNo: "A-003",
    centreCode: "10101"
  }
```

---

## **8. PHOTO LOAD SUCCESS** (As images load)

```
✅ Photo Loaded: Ramesh Kumar
▼ {
    url: "https://f001.backblazeb2.com/file/msce-exams/studen...",
    student: "Ramesh Kumar"
  }

✅ Photo Loaded: Priya Singh
▼ {
    url: "https://app.supabase.co/storage/v1/object/public...",
    student: "Priya Singh"
  }
```

---

## **9. PHOTO LOAD FAILURES** (If images fail)

```
❌ Photo Failed to Load: John Doe
▼ {
    url: "https://f001.backblazeb2.com/file/msce-exams/john_999.jpg",
    student: "John Doe",
    error: "error"
  }
```

---

## **How to Read the Console**

### **Open Developer Tools**
- **Chrome/Edge/Firefox:** Press `F12` or `Cmd+Opt+I` (Mac)
- **Safari:** `Cmd+Opt+J` (Mac)

### **Go to Console Tab**
Click the "Console" tab to see all the logs

### **Color Guide**
- 🟢 **Green**: Successful loading
- 🔵 **Blue**: Data loaded from database
- 🟣 **Purple**: Individual student rendering
- 🟡 **Yellow**: Cache information
- 🟠 **Orange**: Photo resolution strategy
- 🔴 **Red**: Photo load failures

---

## **Common Debugging Scenarios**

### **Scenario 1: Photos not showing but console shows URLs**
✓ Photos loaded successfully but failed at render
→ Check browser console for load errors
→ Check if URLs are actually valid

### **Scenario 2: Very few photos loaded (30-40%)**
✓ Only 30% of students have photos in database
→ This is normal - not all students have photos yet
→ Check `withPhotos` count in statistics

### **Scenario 3: Photos loading very slowly**
✓ Likely B2 signing requests are slow
→ B2-storage-proxy function may be overloaded
→ Check network tab for request times

### **Scenario 4: Photos load from cache on second visit**
✓ localStorage cache is working correctly
→ Look for memory cache hits
→ Photos load instantly (no B2 signing needed)

---

## **What the Logs Tell You**

| Log | Meaning |
|-----|---------|
| `Page X: 1000 rows` | Successfully loaded 1000 students from DB |
| `Grouped into 474 students` | After merging duplicates, found 474 unique students |
| `withPhotos: "156 (32.9%)"` | 156 of 474 students have photo URLs |
| `photoTypeBreakdown` | Which types of photo URLs are being used |
| `✅ Photo Loaded` | Image successfully downloaded and rendered |
| `❌ Photo Failed` | Image download failed (CORS, 404, or invalid URL) |
| `Photo URL: ...` | The actual URL being used to load the photo |

---

## **Pro Tips**

✅ **Right-click a URL in console** → "Open in new tab" to test it directly  
✅ **Check Network tab** → See actual HTTP requests for photos  
✅ **Look for B2 URLs** → These get signed by Supabase Function  
✅ **Check Cache** → `localStorage.getItem('msce_photo_url_cache')` to see what's cached  
✅ **Test a single URL** → Paste it in browser to see if it's valid  

---

## **Summary**

When you go to Exam Students page and select a centre, you'll see:
1. ✅ Students loading from database (pagination)
2. ✅ Students grouped into unique records
3. ✅ Photo statistics breakdown
4. ✅ Sample student data (first 5)
5. ✅ Photo resolution strategy explanation
6. ✅ Cache configuration info
7. ✅ Table rendering status
8. ✅ Individual photo load success/failures as they render

This gives you full visibility into how photos are being loaded from the database to the frontend!
