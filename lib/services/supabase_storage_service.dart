import 'package:flutter/foundation.dart' show debugPrint;
import '../core/supabase_client.dart';

/// Simple Supabase Storage Service for attendance photos
/// Much simpler than B2, uses Supabase's built-in storage
class SupabaseStorageService {
  static const String _bucketName = 'attendance-photos';

  /// Upload photo to Supabase Storage
  /// Returns the public URL
  static Future<String> uploadPhoto({
    required String instituteId,
    required String folderYear,
    required String srNo,
    required String subject,
    required String date,
    required List<int> photoBytes,
    String photoType = 'entry',
  }) async {
    try {
      // Generate path: institute_id/year/srNo/subject/date/entry.jpg
      final cleanSubject = subject
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
          .toLowerCase();
      final cleanSrNo = srNo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final filePath =
          '$instituteId/$folderYear/$cleanSrNo/$cleanSubject/$date/$photoType.jpg';

      debugPrint('📤 Uploading to Supabase Storage: $filePath');

      // Upload to Supabase Storage
      await supabase.storage.from(_bucketName).uploadBinary(
            filePath,
            photoBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true,
            ),
          );

      // Get public URL
      final publicUrl =
          supabase.storage.from(_bucketName).getPublicUrl(filePath);

      debugPrint('✅ Photo uploaded: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ Supabase Storage upload failed: $e');
      rethrow;
    }
  }

  /// Delete photo from Supabase Storage
  static Future<void> deletePhoto(String filePath) async {
    try {
      await supabase.storage.from(_bucketName).remove([filePath]);
      debugPrint('✅ Photo deleted: $filePath');
    } catch (e) {
      debugPrint('❌ Delete failed: $e');
      rethrow;
    }
  }
}
