import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class CacheClearService {
  /// Clear all app caches - images, disk, memory
  /// ✅ CRITICAL: Call on every app start + every entry photo mark
  /// Prevents stale data on shared devices/multiple logins
  static Future<void> clearAllCaches() async {
    try {
      // 1. Clear Flutter image cache (memory)
      imageCache.clear();
      imageCache.clearLiveImages();
      debugPrint('✅ Image cache cleared');

      // 2. Clear disk cache (flutter_cache_manager)
      await DefaultCacheManager().emptyCache();
      debugPrint('✅ Disk cache cleared');

      // 3. Clear custom caches if any
      debugPrint('✅ All caches cleared successfully!');
    } catch (e) {
      debugPrint('❌ Error clearing caches: $e');
    }
  }

  /// Clear caches on app startup (ESSENTIAL for multi-device/shared devices)
  static Future<void> clearCachesOnAppStart() async {
    debugPrint('🧹 CLEARING CACHES ON APP START - Multi-device fix');
    await clearAllCaches();
  }

  /// Aggressive cache clear for entry photo marking
  /// Clears both memory and disk to ensure fresh data
  static Future<void> aggressiveCacheClear() async {
    try {
      debugPrint('🔥 AGGRESSIVE CACHE CLEAR - Entry photo marking');

      // Force clear multiple times to ensure
      for (int i = 0; i < 3; i++) {
        imageCache.clear();
        imageCache.clearLiveImages();
        await DefaultCacheManager().emptyCache();
      }

      debugPrint('✅ Aggressive cache clear complete');
    } catch (e) {
      debugPrint('❌ Aggressive cache clear error: $e');
    }
  }

  /// Clear only image cache
  static Future<void> clearImageCache() async {
    try {
      imageCache.clear();
      imageCache.clearLiveImages();
      debugPrint('✅ Image cache cleared');
    } catch (e) {
      debugPrint('❌ Error clearing image cache: $e');
    }
  }

  /// Clear only disk cache
  static Future<void> clearDiskCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      debugPrint('✅ Disk cache cleared');
    } catch (e) {
      debugPrint('❌ Error clearing disk cache: $e');
    }
  }

  /// Clear cache on app startup
  static Future<void> initializeCacheClear() async {
    debugPrint('🧹 Initializing cache clear on startup...');
    await clearAllCaches();
  }
}
