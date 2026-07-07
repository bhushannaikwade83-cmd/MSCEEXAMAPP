import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Web-specific storage service for entry photo uploads
/// Handles centre_code properly for web platform
class WebStorageService {
  static const String VERCEL_API_URL = 'https://your-vercel-domain.com/api/upload';

  /// Upload entry photo via web endpoint with correct centre_code
  static Future<Map<String, String>> uploadEntryPhotoWeb({
    required String centreCode,  // ✅ Centre code (EXAM_CENTER)
    required String folderYear,
    required String seatNo,
    required String subject,
    required String date,
    required List<int> photoBytes,
  }) async {
    try {
      // ✅ Generate correct path with centre_code
      final storagePath = '$centreCode/$folderYear/$seatNo/${subject.replaceAll(' ', '_').toLowerCase()}/$date/${seatNo}entry.jpg';

      debugPrint('📤 Web Upload: $storagePath');

      // ✅ Call Vercel API with correct path
      final response = await _uploadViaVercelAPI(
        storagePath: storagePath,
        photoBytes: photoBytes,
      );

      return {
        'url': response['url'] ?? '',
        'path': storagePath,
      };
    } catch (e) {
      debugPrint('❌ Web upload failed: $e');
      rethrow;
    }
  }

  /// Internal: Call Vercel API endpoint
  static Future<Map<String, dynamic>> _uploadViaVercelAPI({
    required String storagePath,
    required List<int> photoBytes,
  }) async {
    // TODO: Implement actual Vercel API call
    // This should return: { 'url': 'https://...', 'path': '...' }

    debugPrint('🌐 Calling Vercel API for: $storagePath');

    // Placeholder return
    return {
      'url': 'https://f004.backblazeb2.com/file/attendance-students-photos/$storagePath',
      'path': storagePath,
    };
  }
}
