/// Face matching thresholds for registration and attendance
/// Cosine similarity ranges from 0.0 to 1.0
/// Higher = more similar faces

class FaceMatchingThresholds {
  /// ✅ TWO-TIER DUPLICATE DETECTION SYSTEM
  /// Soft warning at 60% (admin reviews, can approve)
  /// Hard block at 88% (confirmed duplicate/fraud)
  /// Allow below 60% (genuine different students)

  /// HARD BLOCK: Same person attempting duplicate registration (confirmed duplicate/fraud)
  /// >= 88% similarity = Almost identical face = Same person definitely
  static const double DUPLICATE_HARD_BLOCK_THRESHOLD = 0.88;

  /// SOFT WARNING: Suspicious similarity but let admin decide
  /// 70-85% similarity = Similar looking, could be different people
  /// Shows warning to admin with "OK to continue?" button
  static const double DUPLICATE_REVIEW_THRESHOLD = 0.70;

  /// LEGACY: Kept for backward compatibility
  /// Now replaced by two-tier system above
  static const double DUPLICATE_DETECTION_THRESHOLD = DUPLICATE_HARD_BLOCK_THRESHOLD;

  /// Threshold for **attendance / entry / exit** face verification (probe vs enrolled embedding).
  /// Entry and exit both use [FaceRecognitionService.verifyStudent] only — no separate
  /// "exit photo vs today's entry photo" step.
  ///
  /// - Below 0.45 (45%) → ❌ HARD REJECT vs enrollment (almost certainly wrong person — no manual)
  /// - Between 0.45–0.55 (45–55%) → ⚠️ MANUAL CONFIRM (ambiguous band — staff compares to roster)
  /// - ≥ 0.55 (55%) → ✅ AUTO-ACCEPT (strong match vs enrolled embedding)
  ///
  /// Probe vs **other** students uses only rows in `students` for the same `institute_id`
  /// (no cross-institute pool).
  ///
  /// Camera factors affecting similarity:
  /// • Phone camera quality varies (0.05-0.10 drop)
  /// • Lighting conditions (0.10-0.15 drop)
  /// • Face angle/distance (0.05-0.20 drop)
  /// • Time of day differences (0.05-0.10 drop)
  static const double ATTENDANCE_VERIFICATION_THRESHOLD = 0.55;

  /// Below this vs enrollment → hard reject **when an embedding exists** (no manual in that band).
  static const double ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY = 0.45;

  /// Block attendance when another student in the **same institute** matches this face
  /// at or above this score and beats the selected student card.
  /// Raised slightly so look-alikes in the same class trigger manual confirm, not hard block.
  static const double CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD = 0.82;

  /// --- Exam centre auto-entry (stricter than daily MSCE attendance) ---
  /// 1:N best match must clear this vs any registration template (1 or 3 embeddings).
  static const double EXAM_AUTO_SCAN_MIN_CONFIDENCE = 0.72;

  /// Best roster match must lead second-best by at least this margin.
  static const double EXAM_AUTO_SCAN_MIN_MARGIN = 0.12;

  /// 1:1 probe vs matched student's MSCE `face_embedding` before marking entry.
  static const double EXAM_ENTRY_VERIFICATION_THRESHOLD = 0.68;

  /// Another roster student scoring above this with a small lead → reject (wrong person).
  static const double EXAM_CROSS_STUDENT_AMBIGUITY_SCORE = 0.62;

  /// Minimum lead of best match over the next roster student.
  static const double EXAM_CROSS_STUDENT_MIN_LEAD = 0.10;

  /// Returns a user message when another roster student is too close, else null.
  static String? examCrossStudentAmbiguityMessage({
    required double bestSim,
    required double secondBestSim,
    required String? secondBestName,
  }) {
    if (secondBestSim < EXAM_CROSS_STUDENT_AMBIGUITY_SCORE) return null;
    final lead = bestSim - secondBestSim;
    if (lead >= EXAM_CROSS_STUDENT_MIN_LEAD) return null;
    final other = secondBestName?.trim().isNotEmpty == true ? secondBestName!.trim() : 'another student';
    return 'Face is too close to $other (${(secondBestSim * 100).toStringAsFixed(0)}%). '
        'Only the registered student can enter — stand alone in front of the camera.';
  }

  /// Another student's score must exceed the selected student's by at least this margin
  /// to treat the face as belonging to the other enrolled student.
  /// Increased from 0.06 to 0.15 to reduce false positives for genuine students
  /// with appearance changes while still blocking obvious fraud (same-person at 88%+).
  static const double CROSS_STUDENT_DOMINANCE_MARGIN = 0.15;

  /// Near-duplicate / same-person fraud block (always reject; no manual override).
  static const double CROSS_STUDENT_MANUAL_CEILING_OTHER = 0.88;

  /// Minimum confidence for face detection itself
  /// 0.5 = 50% confidence the detected face is a real face (vs noise)
  static const double MINIMUM_FACE_CONFIDENCE = 0.5;

  /// Print thresholds for debugging
  static void printThresholds() {
    print('''
╔════════════════════════════════════════════════════════════════╗
║    FACE MATCHING THRESHOLDS - TWO-TIER DUPLICATE DETECTION     ║
╠════════════════════════════════════════════════════════════════╣
║ HARD BLOCK (confirmed duplicate):  >= ${(DUPLICATE_HARD_BLOCK_THRESHOLD * 100).toStringAsFixed(0)}% similar
║ SOFT WARNING (admin review):       60-85% similar
║ ALLOW (genuine students):          < 60% similar
║
║ ATTENDANCE AUTO-ACCEPT:            >= ${(ATTENDANCE_VERIFICATION_THRESHOLD * 100).toStringAsFixed(0)}% vs enrollment (same institute roster only)
║ APPEARANCE-MANUAL BAND:            ${(ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY * 100).toStringAsFixed(0)}-${(ATTENDANCE_VERIFICATION_THRESHOLD * 100).toStringAsFixed(0)}% vs enrollment (staff confirm)
║ CROSS-STUDENT BLOCK (other wins):  >= ${(CROSS_STUDENT_ATTENDANCE_BLOCK_THRESHOLD * 100).toStringAsFixed(0)}% and beats selected card
║ CROSS-STUDENT FRAUD BLOCK:        >= ${(CROSS_STUDENT_MANUAL_CEILING_OTHER * 100).toStringAsFixed(0)}% (near-duplicate, likely same person)
║ FACE CONFIDENCE:                   >= 50%
╚════════════════════════════════════════════════════════════════╝

TWO-TIER SYSTEM BEHAVIOR:
├─ >= 88% (confirmed duplicate)  → ❌ HARD BLOCK "This is same person"
├─ 60-88% (suspicious)           → ⚠️ SOFT WARNING (allow but log for admin)
└─ < 60% (genuine different)     → ✅ ALLOW registration

HOW TO TUNE:
✅ Genuine students stuck below staff-confirm band (<45%) too often?
   → Lower ATTENDANCE_MANUAL_APPEARANCE_MIN_SIMILARITY slightly.

✅ Too many fraudsters passing (same person registering twice)?
   → Raise DUPLICATE_HARD_BLOCK_THRESHOLD from 0.88 to 0.92
   → Stricter on confirmed duplicates during registration
    ''');
  }

  /// Calculate similarity percentage for user display
  static String similarityPercentage(double similarity) {
    return '${(similarity * 100).toStringAsFixed(1)}%';
  }

  /// Check if two faces are too similar (duplicate)
  static bool isDuplicate(double similarity) {
    return similarity >= DUPLICATE_DETECTION_THRESHOLD;
  }

  /// Check if face matches for attendance
  static bool isMatch(double similarity) {
    return similarity >= ATTENDANCE_VERIFICATION_THRESHOLD;
  }
}
