# MiniFASNet-V2 Verification Checklist

## ✅ Completed Fixes

- [x] **Color space bug fixed** — RGB → BGR in 3 preprocessing functions
  - `_miniFasPatchFromImage()`
  - `_miniFasPatchFromCamera()`
  - `_miniFasPatchFromFaceCrop()`

## 📋 Verification Tasks (TODO)

### Phase 1: Class Mapping Verification

- [ ] **Review test script** — `minifas_class_mapping_test.dart`
- [ ] **Prepare test images:**
  - [ ] 1 good face (real person, clear, front-facing)
  - [ ] 1 bad face (printed photo)
  - [ ] 1 bad face (phone screen)
  - [ ] 2-3 additional faces (various conditions)
- [ ] **Add debug screen** to test with `MiniFasClassMappingTester`
- [ ] **Run tests** and capture console output
- [ ] **Analyze results:**
  - [ ] Hypothesis 1 (current code) works?
  - [ ] Hypothesis 2 (reference formula) works?
  - [ ] Hypothesis 3 (alternative) works?
- [ ] **Document findings** in a results file

### Phase 2: Code Updates (if needed)

- [ ] **Determine correct mapping** from test results
- [ ] **Update `_runMiniFasInference()`** if mapping is wrong
  - If H3: Change `liveProb = probs[0]`
  - If H2: Change `liveProb = 1.0 - (probs[1] + probs[2])`
- [ ] **Update thresholds** if formula changed:
  - [ ] Verify `liveThreshold` value (currently 0.85)
  - [ ] Test with new formula before deploying

### Phase 3: Production Validation

- [ ] **Run attendance tests:**
  - [ ] Test with known good faces
  - [ ] Test with known fake faces (printed/screen)
  - [ ] Check false positive rate
  - [ ] Check false negative rate
- [ ] **Monitor metrics:**
  - [ ] Track acceptance rate
  - [ ] Track rejection rate
  - [ ] Track manual overrides
- [ ] **Compare before/after:**
  - [ ] Accuracy improvement from BGR fix
  - [ ] Consistency of decisions

---

## Testing Commands

### Test on Single Image:
```dart
final tester = MiniFasClassMappingTester();
await tester.runTests(photoPath: '/path/to/test/face.jpg');
tester.dispose();
```

### Expected Output Format:
```
🔬 MiniFASNet-V2 CLASS MAPPING TEST
════════════════════════════════════════════════════════════
Test Image: /path/to/test/face.jpg
Image Size: 1080×1440

📊 Raw Inference Results:
─────────────────────────────────────────────────────────────
Raw logits: [1.2340, 0.1234, 2.5678]
Softmax probs: [0.0234, 0.0156, 0.9610]

📋 CLASS MAPPING HYPOTHESES:
─────────────────────────────────────────────────────────────
Hypothesis 1: Output order = [spoof_A, spoof_B, live]
  → Live probability = 96.1%
  → Decision: ✅ LIVE

Hypothesis 2: Output order = [live, print_spoof, replay_spoof]
  → Live probability = 97.5%
  → Decision: ✅ LIVE

Hypothesis 3: Output order = [live, spoof1, spoof2]
  → Live probability = 2.3%
  → Decision: ❌ SPOOF

🎯 RECOMMENDATION:
Highest probability: probs[2] = 96.1%
→ LIKELY: Hypothesis 1 (current code) is CORRECT
```

---

## Success Criteria

✅ **Pass if:**
1. Good face test: All or most hypotheses show ✅ LIVE
2. Bad face test: All or most hypotheses show ❌ SPOOF
3. Same hypothesis works for both good and bad faces
4. High confidence (prob > 0.90) for all tests

❌ **Fail if:**
1. Good face shows ❌ SPOOF
2. Bad face shows ✅ LIVE
3. Different hypotheses work for good vs bad (inconsistent)
4. Low confidence (prob < 0.50) for any test

---

## Files Related to This Task

| File | Purpose |
|---|---|
| `PREPROCESSING_REVIEW.md` | Initial bug analysis |
| `FIXES_APPLIED.md` | BGR fix documentation |
| `CLASS_MAPPING_TEST_GUIDE.md` | Detailed testing guide |
| `minifas_class_mapping_test.dart` | Test script |
| `anti_spoof_service.dart` | Main implementation |

---

## Timeline

- **Week 1:** Complete class mapping tests
- **Week 2:** Apply fixes if needed, run production validation
- **Week 3:** Monitor metrics and confirm improvement

---

## Questions to Answer

1. **What is the actual output class order of your model?**
   - Determined by: Class mapping tests

2. **Is the liveness formula correct?**
   - Current: `probs[2]`
   - Reference: `1 - (probs[1] + probs[2])`

3. **What threshold values are optimal?**
   - Currently: 0.85 for auto-attendance
   - May need adjustment based on formula

4. **What's the improvement from BGR fix?**
   - Baseline: Current accuracy without fix
   - After fix: Accuracy with BGR correction
   - Expected: Significant improvement in edge cases

