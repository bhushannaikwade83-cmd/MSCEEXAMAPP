import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:http/http.dart' as http;
import 'dart:convert' show base64Encode, jsonDecode, jsonEncode;
import '../../core/supabase_client.dart';

/// Web-specific storage service for entry photo uploads
/// Uses Supabase Edge Function API for uploads (not direct B2)
class WebStorageService {
  /// Upload entry photo via web API using Supabase Edge Function
  /// Path format: EXAM_CENTER/2026/SEAT_NO/SUBJECT/DATE/TIMESTAMP/entry.jpg
  static Future<Map<String, String>> uploadEntryPhotoWeb({
    required String centreCode,  // ✅ EXAM_CENTER
    required String folderYear,
    required String seatNo,
    required String subject,
    required String date,
    required List<int> photoBytes,
  }) async {
    try {
      debugPrint('📤 Web Upload: Starting entry photo upload...');

      // ✅ Generate timestamp folder for versioning
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // ✅ Clean subject name: replace spaces/special chars
      final cleanSubject = subject
          .replaceAll(' ', '_')
          .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
          .toLowerCase();

      // ✅ Correct path format: EXAM_CENTER/2026/SEAT_NO/SUBJECT/DATE/TIMESTAMP/entry.jpg
      final storagePath = '$centreCode/$folderYear/$seatNo/$cleanSubject/$date/$timestamp/entry.jpg';

      debugPrint('📤 Web Upload Path: $storagePath');
      debugPrint('📤 Photo size: ${photoBytes.length} bytes');

      // ✅ Call web API endpoint (Supabase Edge Function)
      final response = await _uploadViaAPI(
        storagePath: storagePath,
        photoBytes: photoBytes,
      );

      final photoUrl = response['url'] ?? '';
      if (photoUrl.isEmpty) {
        throw Exception('No URL returned from upload');
      }

      debugPrint('✅ Web upload successful: $photoUrl');

      return {
        'url': photoUrl,
        'path': storagePath,
      };
    } catch (e) {
      debugPrint('❌ Web upload failed: $e');
      rethrow;
    }
  }

  /// Call Supabase Edge Function API for upload
  /// Endpoint: /functions/v1/b2-storage-proxy
  /// Action: upload_url (returns presigned URL for client to upload)
  static Future<Map<String, dynamic>> _uploadViaAPI({
    required String storagePath,
    required List<int> photoBytes,
  }) async {
    try {
      debugPrint('🌐 Calling Supabase Edge Function for upload...');

      // Get Supabase URL and API key from supabase_flutter
      final client = supabase;
      final supabaseUrl = 'https://snxcrqgodamoxwgkkqez.supabase.co';  // Supabase project URL (from app_config.env)
      final session = client.auth.currentSession;
      final token = session?.accessToken ?? '';

      if (token.isEmpty) {
        throw Exception('Not authenticated - no Supabase session');
      }

      // ✅ Call edge function endpoint using correct functions URL
      final functionUrl = '$supabaseUrl/functions/v1/b2-storage-proxy';

      debugPrint('🌐 Edge Function URL: $functionUrl');

      final requestBody = {
        'action': 'upload_file',
        'storagePath': storagePath,
        'photoData': base64Encode(photoBytes).toString(),
      };

      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Upload timeout'),
      );

      debugPrint('🌐 Edge Function Response: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('❌ Edge function error: ${response.body}');
        throw Exception('Edge function error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (!data.containsKey('url')) {
        throw Exception('No URL in response: $data');
      }

      return {
        'url': data['url'],
        'fileId': data['fileId'],
        'path': storagePath,
      };
    } catch (e) {
      debugPrint('❌ API call failed: $e');
      rethrow;
    }
  }
}
