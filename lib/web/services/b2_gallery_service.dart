import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

class B2GalleryService {
  static const String b2ApiUrl = 'https://f004.backblazeb2.com/file/attendance-students-photos';

  /// Extract folder path from entry photo URL
  /// URL: https://f004.backblazeb2.com/file/attendance-students-photos/UUID/2026/SEAT/SUBJECT/DATE/entry.jpg
  /// Returns: UUID/2026/SEAT/SUBJECT/DATE/
  static String extractFolderPath(String entryPhotoUrl) {
    try {
      final uri = Uri.parse(entryPhotoUrl);
      final pathSegments = uri.pathSegments;

      // Find 'attendance-students-photos' index
      final startIndex = pathSegments.indexOf('attendance-students-photos');
      if (startIndex == -1) return '';

      // Get all segments after bucket name, excluding filename
      final folderSegments = pathSegments.sublist(startIndex + 1);
      if (folderSegments.isEmpty) return '';

      // Remove last segment if it's a file (entry.jpg, etc)
      if (folderSegments.last.contains('.')) {
        folderSegments.removeLast();
      }

      return folderSegments.join('/');
    } catch (e) {
      print('❌ Error extracting folder path: $e');
      return '';
    }
  }

  /// List all photos in a B2 folder using S3-style listing
  /// Returns: List of full photo URLs in the folder
  static Future<List<String>> listPhotosInFolder(String entryPhotoUrl) async {
    try {
      final folderPath = extractFolderPath(entryPhotoUrl);
      if (folderPath.isEmpty) {
        print('❌ Could not extract folder path from: $entryPhotoUrl');
        return [];
      }

      print('🔍 Listing photos in folder: $folderPath');

      // B2 S3-compatible API endpoint for listing objects
      // https://f004.backblazeb2.com/file/bucket-name/ = web UI access
      // For listing, we need to use the S3 API: https://s3.f004.backblazeb2.com/

      final listUrl =
          'https://s3.f004.backblazeb2.com/attendance-students-photos?list-type=2&prefix=$folderPath';

      final response = await http.get(Uri.parse(listUrl)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );

      if (response.statusCode == 200) {
        // Parse XML response
        final document = xml.XmlDocument.parse(response.body);
        final contents = document.findAllElements('Contents');

        final photoUrls = <String>[];
        for (final content in contents) {
          final key = content.findElements('Key').first.text;

          // Filter image files only
          if (_isImageFile(key)) {
            final fullUrl = '$b2ApiUrl/$key';
            photoUrls.add(fullUrl);
            print('✅ Found photo: $key');
          }
        }

        print('📸 Total photos found: ${photoUrls.length}');
        return photoUrls;
      } else {
        print('❌ Failed to list photos: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error listing photos: $e');
      return [];
    }
  }

  /// Check if file is an image
  static bool _isImageFile(String filename) {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
    final ext = filename.split('.').last.toLowerCase();
    return imageExtensions.contains(ext);
  }

  /// Get folder info (for debugging)
  static String getFolderInfo(String entryPhotoUrl) {
    final folderPath = extractFolderPath(entryPhotoUrl);
    return '$b2ApiUrl/$folderPath';
  }
}
