# MiniFASNet-V2 Color Space Fixes Applied
**Date:** 2026-06-14  
**File:** `lib/services/anti_spoof_service.dart`

---

## Summary
Fixed critical RGB→BGR color order bug in MiniFAS80 preprocessing. The model expects BGR but the code was providing RGB, causing color channel misinterpretation.

---

## Changes Made

### Fix #1: `_miniFasPatchFromImage()` (lines 810-834)
**Before:**
```dart
patch[idx] = pixel.r.toDouble();     // R
patch[idx + 1] = pixel.g.toDouble(); // G
patch[idx + 2] = pixel.b.toDouble(); // B
```

**After:**
```dart
patch[idx]     = pixel.b.toDouble(); // BGR
patch[idx + 1] = pixel.g.toDouble();
patch[idx + 2] = pixel.r.toDouble();
```

---

### Fix #2: `_miniFasPatchFromCamera()` (lines 784-808)
**Before:**
```dart
patch[idx] = rgb.$1.toDouble();     // R
patch[idx + 1] = rgb.$2.toDouble(); // G
patch[idx + 2] = rgb.$3.toDouble(); // B
```

**After:**
```dart
patch[idx]     = rgb.$3.toDouble(); // BGR
patch[idx + 1] = rgb.$2.toDouble();
patch[idx + 2] = rgb.$1.toDouble();
```

---

### Fix #3: `_miniFasPatchFromFaceCrop()` (lines 421-438)
**Before:**
```dart
patch[idx] = p.r.toDouble();     // R
patch[idx + 1] = p.g.toDouble(); // G
patch[idx + 2] = p.b.toDouble(); // B
```

**After:**
```dart
patch[idx]     = p.b.toDouble(); // BGR
patch[idx + 1] = p.g.toDouble();
patch[idx + 2] = p.r.toDouble();
```

---

## Why This Matters

**MiniFASNet-V2 Specification:**
- Input format: (1, 3, 80, 80) float32 **BGR** normalized to [0, 1]
- Trained on BGR images from OpenCV

**Previous Bug:**
- Code extracted pixels as RGB (Red, Green, Blue order)
- Passed to model expecting BGR (Blue, Green, Red order)
- Model received swapped red/blue channels
- Results: Reduced accuracy, false positives/negatives

**Now Aligned:**
- All three MiniFAS80 preprocessing paths now correctly produce BGR
- Matches model training and reference implementations
- Consistent with MiniFASNetV1SE (which was already correct)

---

## Verification

✅ All three preprocessing paths updated:
- Still image from file: `_miniFasPatchFromImage()`
- Live camera stream: `_miniFasPatchFromCamera()`
- Camera crop fallback: `_miniFasPatchFromFaceCrop()`

✅ MiniFASNetV1SE remains correct (was already BGR)

✅ Normalization unchanged (pixel/255 is correct)

✅ Bbox scaling unchanged (2.7× is correct)

---

## Next Steps (Optional)

1. **Test with known faces** — validate output improved
2. **Check output class mapping** — verify class order matches your ONNX2TF conversion
3. **Consider liveness formula** — reference uses `1 - (p[print] + p[replay])`, current uses `probs[2]`

