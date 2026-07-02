import 'package:flutter/foundation.dart';
import '../core/supabase_client.dart';

/// Service to manage subject enable/disable status from database
class SubjectEnableService {
  /// Enable a subject (allow marking)
  static Future<bool> enableSubject({
    required String examStudentId,
  }) async {
    try {
      await supabase.from('exam_students').update({
        'is_enabled': true,
      }).eq('id', examStudentId);

      if (kDebugMode) {
        debugPrint('✅ Subject enabled: $examStudentId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error enabling subject: $e');
      }
      return false;
    }
  }

  /// Disable a subject (prevent marking)
  static Future<bool> disableSubject({
    required String examStudentId,
  }) async {
    try {
      await supabase.from('exam_students').update({
        'is_enabled': false,
      }).eq('id', examStudentId);

      if (kDebugMode) {
        debugPrint('✅ Subject disabled: $examStudentId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error disabling subject: $e');
      }
      return false;
    }
  }

  /// Enable multiple subjects at once (by centre)
  static Future<bool> enableSubjectsByStudentId({
    required String studentId,
  }) async {
    try {
      await supabase.from('exam_students').update({
        'is_enabled': true,
      }).eq('id', studentId);

      if (kDebugMode) {
        debugPrint('✅ All subjects enabled for student: $studentId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error enabling subjects: $e');
      }
      return false;
    }
  }

  /// Disable multiple subjects at once (by centre)
  static Future<bool> disableSubjectsByStudentId({
    required String studentId,
  }) async {
    try {
      await supabase.from('exam_students').update({
        'is_enabled': false,
      }).eq('id', studentId);

      if (kDebugMode) {
        debugPrint('✅ All subjects disabled for student: $studentId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error disabling subjects: $e');
      }
      return false;
    }
  }

  /// Get subject enable/disable status
  static Future<bool?> getSubjectStatus({
    required String examStudentId,
  }) async {
    try {
      final result = await supabase
          .from('exam_students')
          .select('is_enabled')
          .eq('id', examStudentId)
          .maybeSingle();

      if (result != null) {
        return result['is_enabled'] as bool? ?? true;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting subject status: $e');
      }
      return null;
    }
  }
}
