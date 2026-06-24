# MiniFASNet-V2 Preprocessing Review
**Date:** 2026-06-14  
**File:** `lib/services/anti_spoof_service.dart`

---

## Model Specification vs. Implementation

| Requirement | Model Spec | Your Code | Status |
|---|---|---|---|
| **Input shape** | (1, 3, 80, 80) | [1, 80, 80, 3] NHWC | ✅ Correct (TFLite uses NHWC) |
| **Data type** | float32 | Float32List | ✅ ✓ |
| **Color space** | BGR | RGB (MiniFAS80) | ⚠️ **ISSUE** |
| **Normalization** | pixel / 255 → [0, 1] | Yes (line 647) | ✅ ✓ |
| **Bbox scale** | 2.7× | 2.7 (line 38) | ✅ ✓ |
| **Output** | 3-class softmax | ✓ (line 659) | ✅ ✓ |
| **Liveness formula** | 1 - (p[print] + p[replay]) | probs[2] directly | ⚠️ **ISSUE** |

---

## Critical Issues Found

### 🔴 ISSUE #1: Color Space Mismatch (MiniFAS80)

**Location:** Lines 802-804 (`_miniFasPatchFromImage`)

```dart
// CURRENT (WRONG):
patch[idx] = pixel.r.toDouble();     // R
patch[idx + 1] = pixel.g.toDouble(); // G
patch[idx + 2] = pixel.b.toDouble(); // B
```

**Problem:** 
- MiniFASNet-V2 expects **BGR** order
- Your code provides **RGB** order
- Model trained on BGR, will misinterpret colors

**Compare with MiniFASNetV1SE (CORRECT):**
```dart
// Line 698-700 (CORRECT):
patch[idx]     = pixel.b.toDouble(); // BGR ✅
patch[idx + 1] = pixel.g.toDouble();
patch[idx + 2] = pixel.r.toDouble();
```

**Fix Required:**
```dart
// _miniFasPatchFromImage (line ~810-834)
// CHANGE FROM RGB to BGR:
patch[idx]     = pixel.b.toDouble(); // BGR
patch[idx + 1] = pixel.g.toDouble();
patch[idx + 2] = pixel.r.toDouble();

// Same for _miniFasPatchFromCamera (lines ~800-806):
patch[idx]     = rgb.$3.toDouble(); // B
patch[idx + 1] = rgb.$2.toDouble(); // G  
patch[idx + 2] = rgb.$1.toDouble(); // R
```

---

### ⚠️ ISSUE #2: Output Class Mapping Ambiguity

**Location:** Lines 660-664 (`_runMiniFasInference`)

```dart
// Reference model: [live, print-attack, replay-attack]
// Your comment says: [spoof_typeA, spoof_typeB, live]
// Code uses: liveProb = probs[2]
```

**The Problem:**
- Original MiniFASNet-V2 paper: output = `[live, print_spoof, replay_spoof]` → index 2 = live ✓
- Your ONNX2TF conversion may have reordered: `[spoof_A, spoof_B, live]` → index 2 = live ✓
- But the reference formula says: `Liveness = 1 - (p[print] + p[replay])`

**Your Code Does:**
```dart
final liveProb = probs[2];  // Assumes index 2 = live probability
```

**Reference Does:**
```python
liveness = 1 - (probs[1] + probs[2])  # Sum of attack classes
```

**Action Needed:**
1. **Verify your ONNX→TFLite conversion preserved the original class order**
2. If not aligned, either:
   - Use the reference formula: `liveProb = 1.0 - (probs[1] + probs[2])`
   - Or document the actual class order from your converted model

---

### ✅ ISSUE #3: Normalization is Correct (But Verify for V1SE)

**Your code (line 232-235) correctly handles both variants:**

```dart
if (_backend == _AntiSpoofBackend.miniFas80 ||
    _backend == _AntiSpoofBackend.antispoofPrintReplay128) {
  _miniFasInputNormalized = interpreter.getInputTensor(0).type == TensorType.float32;
}
// MiniFASNetV1SE expects raw float32 pixel values [0,255] — no /255 normalization.
if (_backend == _AntiSpoofBackend.miniFasV1SE80) {
  _miniFasInputNormalized = false;  // ✅ Correct
}
```

✅ **Good:** Detects normalization requirement from model signature

---

## Summary of Required Changes

| Priority | Issue | Line(s) | Fix |
|---|---|---|---|
| 🔴 **Critical** | BGR color order wrong in MiniFAS80 | 802-804, 800-806 | Swap RGB → BGR |
| ⚠️ **Medium** | Output class mapping unclear | 661-662 | Document or verify with model |
| ✅ **Good** | Normalization logic | 647, 232-235 | No change needed |
| ✅ **Good** | Bbox scaling | 38, 815 | No change needed |
| ✅ **Good** | Input shape NHWC | 650 | No change needed |

---

## Recommended Action Plan

1. **Fix color order immediately** — this is a hard bug
2. **Verify model class order** — compare with reference Python inference
3. **Test with known good/bad faces** — validate output after fix
4. **Add debug logging** — log RGB vs BGR decision per backend

