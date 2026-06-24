# MiniFASNet-V2 Class Mapping Verification Guide

## Overview

This guide helps you determine the **correct output class mapping** for your MiniFASNet-V2 TFLite model and verify whether the liveness scoring formula is correct.

---

## Why This Matters

Your model outputs 3 values (logits), but the **order of classes can vary**:

| Possibility | Output Order | Formula |
|---|---|---|
| **Current Code** | [spoof_A, spoof_B, live] | liveProb = probs[2] |
| **Reference** | [live, print_spoof, replay_spoof] | liveProb = 1 - (p[1] + p[2]) |
| **Alternative** | [live, spoof1, spoof2] | liveProb = probs[0] |

**Wrong mapping = Wrong decisions** (false positives/negatives)

---

## Test Script

File: `lib/services/minifas_class_mapping_test.dart`

### What It Does

1. ✅ Loads your MiniFAS TFLite model
2. ✅ Extracts face patch from test image (same as production code)
3. ✅ Runs inference and gets raw logits
4. ✅ Tests 3 different class mapping hypotheses
5. ✅ Provides recommendations

### Quick Start

```dart
// In your test/debug screen:
void testClassMapping() async {
  final tester = MiniFasClassMappingTester();
  await tester.runTests(photoPath: '/path/to/face.jpg');
  tester.dispose();
}
```

---

## How to Use

### Step 1: Prepare Test Images

Get **3-5 test images**:
- ✅ **GOOD**: Real face photo (clear, front-facing)
- ❌ **BAD**: Printed face photo (printed on paper)
- ❌ **BAD**: Phone screen showing face (screen replay)

### Step 2: Add Debug Screen

In your Flutter app, add a debug screen to run the test:

```dart
import 'lib/services/minifas_class_mapping_test.dart';

// In a debug/test screen:
ElevatedButton(
  onPressed: () async {
    final tester = MiniFasClassMappingTester();
    await tester.runTests(photoPath: '/path/to/good_face.jpg');
    // Check console output
    tester.dispose();
  },
  child: Text('Test MiniFAS Mapping'),
),
```

### Step 3: Run Tests

Run the app in debug mode and tap the test button. Watch the console output.

### Step 4: Interpret Results

#### Example Good Face Output:

```
🔬 MiniFASNet-V2 CLASS MAPPING TEST
════════════════════════════════════════════════════════════

Raw logits: [1.2340, 0.1234, 2.5678]
Softmax probs: [0.0234, 0.0156, 0.9610]

📋 CLASS MAPPING HYPOTHESES:
─────────────────────────────────────────────────────────────

Hypothesis 1: Output order = [spoof_A, spoof_B, live]
  → Using current code: liveProb = probs[2]
  → Live probability = 96.1%
  → Decision: ✅ LIVE

Hypothesis 2: Output order = [live, print_spoof, replay_spoof]
  → Using reference formula: liveProb = 1 - (probs[1] + probs[2])
  → Live probability = 97.5%
  → Decision: ✅ LIVE

Hypothesis 3: Output order = [live, spoof1, spoof2]
  → Using direct prob: liveProb = probs[0]
  → Live probability = 2.3%
  → Decision: ❌ SPOOF

🎯 RECOMMENDATION:
Highest probability: probs[2] = 96.1%
→ LIKELY: Hypothesis 1 (current code) is CORRECT
→ Keep current implementation: liveProb = probs[2]
```

#### What to Look For:

1. **Good face should have:**
   - One very high probability (>0.90)
   - Two very low probabilities (<0.05)
   - All hypotheses should agree: ✅ LIVE

2. **Bad face (printed/screen) should have:**
   - One very high probability (>0.90)
   - Two very low probabilities (<0.05)
   - All hypotheses should agree: ❌ SPOOF
   - **Different hypothesis than good face** indicates class order issue

---

## Decision Tree

After running tests on BOTH good and bad faces:

### All Hypotheses Agree on Both Tests ✅
```
Good face: H1=LIVE, H2=LIVE, H3=LIVE
Bad face:  H1=SPOOF, H2=SPOOF, H3=SPOOF

→ Your ONNX→TFLite conversion preserved class order
→ Keep current code
```

### Only H1 Works Correctly ✅
```
Good face: H1=LIVE, H2=SPOOF, H3=SPOOF
Bad face:  H1=SPOOF, H2=LIVE, H3=LIVE

→ Class order is: [spoof_A, spoof_B, live]
→ Keep: liveProb = probs[2]
```

### Only H3 Works Correctly ⚠️
```
Good face: H1=SPOOF, H2=SPOOF, H3=LIVE
Bad face:  H1=LIVE, H2=LIVE, H3=SPOOF

→ Class order is: [live, spoof1, spoof2]
→ Change to: liveProb = probs[0]
```

### Only H2 Works Correctly ⚠️
```
Good face: H1=SPOOF, H2=LIVE, H3=SPOOF
Bad face:  H1=LIVE, H2=SPOOF, H3=LIVE

→ Class order is: [live, print_spoof, replay_spoof]
→ Change to: liveProb = 1.0 - (probs[1] + probs[2])
```

---

## Fixing the Code

Once you determine the correct mapping, update `anti_spoof_service.dart`:

### Current Code (lines 654-664):
```dart
final logits = [
  (output[0][0] as num).toDouble(),
  (output[0][1] as num).toDouble(),
  (output[0][2] as num).toDouble(),
];
final probs = _softmax3(logits);
// Class mapping for this onnx2tf-converted MiniFASNetV2:
// index 0 = spoof type A, index 1 = spoof type B, index 2 = live.
final liveProb = probs[2];
```

### If H3 is Correct:
```dart
final liveProb = probs[0]; // Change this line
```

### If H2 is Correct:
```dart
final liveProb = 1.0 - (probs[1] + probs[2]); // Change this line
```

---

## Additional Verification

After making changes, test in production with:

1. ✅ **Staff manual confirmation** on borderline cases
2. ✅ **Metrics tracking** — count false positives/negatives
3. ✅ **A/B test** — compare old vs new thresholds
4. ✅ **Real attendance data** — verify acceptance rates improve

---

## Common Issues

**All hypotheses return SPOOF for a good face?**
- ❌ Face patch extraction may be wrong
- ❌ Normalization may be reversed
- ❌ BGR/RGB still has issues

**All hypotheses return LIVE for a bad face?**
- ❌ Model may be poorly trained
- ❌ May need different anti-spoof model
- ❌ Check if using MiniFAS vs MiniFASNetV1SE correctly

**Results are inconsistent?**
- ❌ Try multiple test images
- ❌ Ensure test faces are clear and centered
- ❌ Check lighting conditions

---

## Reference Links

- **MiniFASNet-V2 Original:** https://github.com/minivision-ai/Silent-Face-Anti-Spoofing
- **Your Preprocessing Fix:** See PREPROCESSING_REVIEW.md
- **Output Processing:** Lines 654-681 in anti_spoof_service.dart

