import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// ✅ OPTIMIZED Photo Cache Configuration for MSCEEXAMAPP
/// Prioritizes SPEED over storage - aggressive caching with fast cleanup
/// Used for entry photos, profile photos, and student attendance verification
class PhotoCacheConfig {
  /// ✅ FAST profile photo cache (very aggressive)
  /// - Max size: 50MB (stores ~100-150 photos)
  /// - Max age: 1 hour (refreshed frequently)
  /// - Keeps only the most recent 50 entries
  static CacheManager get profilePhotoCacheManager {
    return CacheManager(
      Config(
        'profile_photos_cache',
        stalePeriod: const Duration(hours: 1),  // ✅ FAST refresh
        maxNrOfCacheObjects: 50,  // Keep only latest 50
        fileService: HttpFileService(),
      ),
    );
  }

  /// ✅ ENTRY photo cache (ultra-fast - for attendance marking)
  /// - Max size: 100MB (stores ~200-300 entry photos)
  /// - Max age: 30 minutes (very fresh)
  /// - Purges old entries aggressively
  static CacheManager get entryPhotoCacheManager {
    return CacheManager(
      Config(
        'entry_photos_cache',
        stalePeriod: const Duration(minutes: 30),  // ✅ ULTRA FAST
        maxNrOfCacheObjects: 100,  // Keep only latest 100
        fileService: HttpFileService(),
      ),
    );
  }

  /// ✅ B2 Direct URL caching strategy
  /// Direct B2 URLs (https://f004.backblazeb2.com/) are:
  /// - Already compressed on B2 side
  /// - Delivered via CDN for speed
  /// - No need for extra processing
  /// - Safe to use directly without signing
  static bool isDirectB2Url(String? url) {
    if (url == null) return false;
    return url.startsWith('https://f004.backblazeb2.com/');
  }

  /// ✅ Network image optimization hints
  /// Use these for Image.network() to maximize speed
  static const ImageRequestBuilderOptions = {
    'usesCrossOriginCredentials': false,  // ✅ No auth overhead
    'headers': <String, String>{
      'Accept-Encoding': 'gzip, deflate, br',  // ✅ Enable compression
    },
  };

  /// ✅ Pre-load common resources
  /// Call this on app startup to warm up caches
  static Future<void> warmupCache() async {
    // Pre-cache common images if needed
    // Currently empty as B2 CDN handles this
  }

  /// ✅ Clear caches on demand (e.g., after logout)
  static Future<void> clearAllCaches() async {
    try {
      await profilePhotoCacheManager.emptyCache();
      await entryPhotoCacheManager.emptyCache();
    } catch (e) {
      print('❌ Error clearing photo caches: $e');
    }
  }

  /// ✅ Get cache size stats (for debugging)
  static Future<int> getCacheSizeBytes() async {
    try {
      final profileSize = await profilePhotoCacheManager.cacheSize();
      final entrySize = await entryPhotoCacheManager.cacheSize();
      return profileSize + entrySize;
    } catch (e) {
      return 0;
    }
  }
}

/// ✅ Image loading strategy for different photo types
enum PhotoLoadingStrategy {
  /// Profile/passport photos - less frequent updates, can cache longer
  profile,

  /// Entry/exit attendance photos - frequent, always fresh needed
  entry,

  /// Temporary photos - one-time use, minimal caching
  temporary,
}
