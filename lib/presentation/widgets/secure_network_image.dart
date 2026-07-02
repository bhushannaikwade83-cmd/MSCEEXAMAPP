import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../services/storage_service.dart';
import 'shimmer_effect.dart';

/// Clear image cache to force refresh of all cached photos
void clearImageCache() {
  try {
    imageCache.clear();
    imageCache.clearLiveImages();
    if (kDebugMode) debugPrint('✅ Image cache cleared');
  } catch (e) {
    if (kDebugMode) debugPrint('❌ Error clearing image cache: $e');
  }
}

/// Add cache-busting query parameter to URL to force fresh load
/// Returns original URL with ?t=timestamp appended
String addCacheBuster(String? url) {
  if (url == null || url.isEmpty) return '';

  final separator = url.contains('?') ? '&' : '?';
  final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
  return '$url${separator}t=$timestamp';
}

/// Add cache-busting to image URL for specific use case
/// Use this when you need guaranteed fresh image, not cached version
String cacheBustImageUrl(String? url) {
  if (url == null || url.isEmpty) return '';
  return addCacheBuster(url);
}

/// Secure network image widget that handles B2 signed URLs and 401 errors
/// Automatically retries with fresh authorization if URL is unsigned or returns 401
class SecureNetworkImage extends StatefulWidget {
  final String? imageUrl;
  final String? storagePath; // Alternative: storage path to generate URL from
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final Color? backgroundColor;
  final bool cachePhotos; // Set to false to always fetch fresh from backend
  final String? version; // Bust cache when photo updates (e.g. photo_version)
  /// Stable per-row key (e.g. student UUID). Prevents disk cache / list reuse mix-ups.
  final String? cacheKey;

  const SecureNetworkImage({
    super.key,
    this.imageUrl,
    this.storagePath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.backgroundColor,
    this.cachePhotos = true,
    this.version,
    this.cacheKey,
  }) : assert(imageUrl != null || storagePath != null, 'Either imageUrl or storagePath must be provided');

  @override
  State<SecureNetworkImage> createState() => _SecureNetworkImageState();
}

class _SecureNetworkImageState extends State<SecureNetworkImage> {
  String? _currentUrl;
  bool _isRetrying = false;
  bool _isLoadingImageBytes = false;
  bool _webFetchFailed = false;
  int _retryCount = 0;
  Uint8List? _imageBytes;
  static const int _maxRetries = 2;

  /// Web-only in-memory cache of orientation-baked bytes, so photos are not
  /// re-fetched/re-decoded on every list scroll rebuild.
  static final Map<String, Uint8List> _webBakedCache = {};
  static const int _webBakedCacheMaxEntries = 300;

  /// Stable cache key so disk cache works across refreshed signed URLs.
  /// [cacheKey] (student id) always wins — never share cache entries between rows.
  String? get _diskCacheKey {
    final explicit = widget.cacheKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final v = widget.version?.trim();
      if (v != null && v.isNotEmpty) return '${explicit}_$v';
      return explicit;
    }

    String? baseKey;
    final u = widget.imageUrl?.trim();
    if (u != null && u.isNotEmpty) {
      baseKey = StorageService.b2ObjectPathFromPhotoUrl(u);
    }

    if (baseKey == null || baseKey.isEmpty) {
      final p = widget.storagePath?.trim();
      if (p != null && p.isNotEmpty) baseKey = p;
    }

    if (baseKey != null && baseKey.isNotEmpty) {
      final v = widget.version?.trim();
      if (v != null && v.isNotEmpty) return '${baseKey}_$v';
      return baseKey;
    }
    return null;
  }

  void _resetImageState() {
    _currentUrl = null;
    _imageBytes = null;
    _isLoadingImageBytes = false;
    _isRetrying = false;
    _webFetchFailed = false;
    _retryCount = 0;
  }

  @override
  void initState() {
    super.initState();
    _loadPhotoUrl();
  }

  @override
  void didUpdateWidget(SecureNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.version != widget.version ||
        oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.cachePhotos != widget.cachePhotos) {
      setState(_resetImageState);
      _loadPhotoUrl();
    }
  }

  Future<void> _loadPhotoUrl() async {
    // ✅ For proxy URLs (/api/b2-upload?key=...), use directly (no API call needed)
    // For other URLs, generate temporary signed URL via API
    try {
      String? urlToUse;

      // Priority 1: Proxy URLs (already valid, never expire)
      if (widget.imageUrl != null && widget.imageUrl!.startsWith('/api/b2-upload')) {
        urlToUse = widget.imageUrl; // Use proxy URL directly ✅
      }
      // Priority 2: Generate temporary URL for storage paths or unsigned URLs
      else {
        urlToUse = await StorageService.getTemporaryPhotoUrl(
          photoUrl: widget.imageUrl,
          storagePath: widget.storagePath,
        );
      }

      if (mounted) {
        setState(() {
          _currentUrl = urlToUse;
          _isRetrying = false;
        });
      }

      if (urlToUse != null && urlToUse.isNotEmpty) {
        if (kIsWeb) {
          // Web: fetch bytes and bake EXIF orientation into the pixels so
          // photos render upright on ALL browsers (Safari's decoder ignores
          // EXIF). Falls back to an <img> element if the fetch is blocked.
          await _loadWebImageBytes(urlToUse);
        } else {
          await _loadAndValidateImageBytes(urlToUse);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error generating temporary photo URL: $e');
      if (mounted) {
        setState(() {
          _currentUrl = null;
          _isRetrying = false;
          _imageBytes = null;
          _isLoadingImageBytes = false;
        });
      }
    }
  }

  /// Web-only: fetch photo bytes and bake EXIF orientation into the pixels.
  ///
  /// Safari (and Chrome on iOS, which uses Safari's engine) decodes images in
  /// CanvasKit ignoring EXIF rotation, showing portrait photos sideways. By
  /// physically rotating the pixels once here, the displayed image is
  /// identical and upright on every browser. Results are cached in memory.
  Future<void> _loadWebImageBytes(String url) async {
    final cacheKey = _diskCacheKey ?? url;

    final cached = _webBakedCache[cacheKey];
    if (cached != null) {
      if (!mounted) return;
      setState(() {
        _imageBytes = cached;
        _isLoadingImageBytes = false;
        _webFetchFailed = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingImageBytes = true;
        _imageBytes = null;
        _webFetchFailed = false;
      });
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      var bytes = response.bodyBytes;

      // Bake EXIF orientation into pixels (only re-encode when needed).
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          int orientation = 1;
          try {
            orientation =
                decoded.exif.imageIfd['Orientation']?.toInt() ?? 1;
          } catch (_) {}
          if (orientation != 1) {
            final baked = img.bakeOrientation(decoded);
            bytes = Uint8List.fromList(img.encodeJpg(baked, quality: 90));
          } else if (decoded.width > decoded.height) {
            // Recovery heuristic: student photos are portrait. A photo that
            // is physically landscape with no EXIF tag was corrupted by an
            // earlier upload pipeline that stripped EXIF without rotating
            // the pixels. Rotate 90° CW (EXIF orientation 6 — by far the
            // most common camera orientation) to restore portrait.
            final rotated = img.copyRotate(decoded, angle: 90);
            bytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 90));
          }
        }
      } catch (e) {
        // Decode failed — keep raw bytes; Image.memory may still render them.
        if (kDebugMode) debugPrint('⚠️ Web EXIF bake skipped: $e');
      }

      if (_webBakedCache.length >= _webBakedCacheMaxEntries) {
        _webBakedCache.clear();
      }
      _webBakedCache[cacheKey] = bytes;

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _isLoadingImageBytes = false;
        _webFetchFailed = false;
      });
    } catch (e) {
      // Network/CORS failure — build() falls back to an <img> element, which
      // browsers can display cross-origin and which applies EXIF natively.
      if (kDebugMode) debugPrint('⚠️ Web byte fetch failed, using <img>: $e');
      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _isLoadingImageBytes = false;
        _webFetchFailed = true;
      });
    }
  }

  Future<void> _loadAndValidateImageBytes(String url) async {
    if (mounted) {
      setState(() {
        _isLoadingImageBytes = true;
        _imageBytes = null;
      });
    }

    try {
      Uint8List bytes;

      if (widget.cachePhotos) {
        final cacheKey = _diskCacheKey ?? url;
        final file = await DefaultCacheManager().getSingleFile(
          url,
          key: cacheKey,
        );
        bytes = await file.readAsBytes();
      } else {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }
        bytes = response.bodyBytes;
      }

      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        throw Exception('Invalid or unsupported image bytes');
      }

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _isLoadingImageBytes = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Image byte validation failed: $e');

      if (!mounted) return;
      setState(() {
        _imageBytes = null;
        _isLoadingImageBytes = false;
      });

      final errorStr = e.toString();
      final isAuthError =
          errorStr.contains('401') || errorStr.contains('403') || errorStr.contains('unauthorized');
      if (isAuthError && _retryCount < _maxRetries) {
        await _retryWithFreshAuth(url);
      }
    }
  }

  Future<void> _retryWithFreshAuth(String? failedUrl) async {
    if (_retryCount >= _maxRetries || _isRetrying) return;

    setState(() {
      _isRetrying = true;
      _retryCount++;
    });

    try {
      // Minimal delay for retry
      await Future.delayed(const Duration(milliseconds: 100));

      // Clear URL cache for fresh signing
      if (widget.storagePath != null && widget.storagePath!.isNotEmpty) {
        await StorageService.clearUrlCache();
      }

      // Use the automatic temporary URL generation method for retry
      // This handles all cases automatically
      final urlToRetry = await StorageService.getTemporaryPhotoUrl(
        photoUrl: failedUrl ?? widget.imageUrl,
        storagePath: widget.storagePath,
      );

      if (urlToRetry != null && urlToRetry.isNotEmpty && mounted) {
        setState(() {
          _currentUrl = urlToRetry;
          _isRetrying = false;
        });
        await _loadAndValidateImageBytes(urlToRetry);
      } else if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Retry failed (attempt $_retryCount/$_maxRetries): $e');
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  Widget _buildErrorWidget() {
    return widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1),
          child: const Center(
            child: Icon(
              Icons.broken_image,
              color: Colors.white,
              size: 40,
            ),
          ),
        );
  }

  Widget _buildPlaceholder() {
    return widget.placeholder ??
        ShimmerEffect(
          width: widget.width ?? double.infinity,
          height: widget.height ?? double.infinity,
          borderRadius: BorderRadius.circular(8),
        );
  }

  @override
  Widget build(BuildContext context) {
    // Web rendering:
    // 1) Preferred: orientation-baked bytes via Image.memory — pixels are
    //    physically upright, so every browser (incl. iOS Safari/Chrome)
    //    shows them identically.
    // 2) Fallback (fetch blocked by CORS): HTML <img> element, which
    //    displays cross-origin images and applies EXIF natively.
    if (kIsWeb) {
      if (_currentUrl == null || _currentUrl!.isEmpty || _isRetrying) {
        return _buildPlaceholder();
      }
      if (_isLoadingImageBytes) {
        return _buildPlaceholder();
      }
      if (_imageBytes != null && _imageBytes!.isNotEmpty) {
        return Image.memory(
          _imageBytes!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) debugPrint('❌ Web image decode failed: $error');
            return _buildErrorWidget();
          },
        );
      }
      if (_webFetchFailed) {
        return Image.network(
          _currentUrl!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _buildPlaceholder(),
          errorBuilder: (context, error, stackTrace) {
            if (kDebugMode) debugPrint('❌ Web image load failed: $error');
            return _buildErrorWidget();
          },
        );
      }
      return _buildPlaceholder();
    }

    // Show placeholder while loading or retrying
    if (_currentUrl == null ||
        _currentUrl!.isEmpty ||
        _isRetrying ||
        _isLoadingImageBytes) {
      return widget.placeholder ??
          ShimmerEffect(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            borderRadius: BorderRadius.circular(8),
          );
    }

    if (_imageBytes == null || _imageBytes!.isEmpty) {
      return widget.errorWidget ??
          Container(
            width: widget.width,
            height: widget.height,
            color: widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Invalid image',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
    }

    return Image.memory(
      _imageBytes!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) debugPrint('❌ Flutter image decode failed: $error');
        return widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1),
              child: const Center(
                child: Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            );
      },
    );
  }
}
