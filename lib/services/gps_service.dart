import 'package:geolocator/geolocator.dart';

import '../core/constants.dart';
import '../core/gps_attendance_constants.dart';
import '../core/supabase_client.dart';

class GpsCheckResult {
  GpsCheckResult({
    required this.allowed,
    required this.message,
    this.distanceMeters,
    this.latitude,
    this.longitude,
  });

  final bool allowed;
  final String message;
  final double? distanceMeters;
  final double? latitude;
  final double? longitude;
}

class GpsService {
  Future<bool> isGpsLockedForCenter(String centerId) async {
    if (!isSupabaseConfigured) return false;
    final row = await supabase
        .from('exam_center_gps')
        .select('is_locked, latitude, longitude')
        .eq('center_id', centerId)
        .maybeSingle();
    if (row == null) return false;
    final lat = (row['latitude'] as num?)?.toDouble();
    final lng = (row['longitude'] as num?)?.toDouble();
    return row['is_locked'] == true &&
        lat != null &&
        lng != null &&
        lat != 0 &&
        lng != 0;
  }

  Future<({double? lat, double? lng, bool locked})?> fetchConfig(String centerId) async {
    if (!isSupabaseConfigured) return null;
    final row = await supabase
        .from('exam_center_gps')
        .select()
        .eq('center_id', centerId)
        .maybeSingle();
    if (row == null) return null;
    return (
      lat: (row['latitude'] as num?)?.toDouble(),
      lng: (row['longitude'] as num?)?.toDouble(),
      locked: row['is_locked'] == true,
    );
  }

  Future<String?> saveAndLock({
    required String centerId,
    required double latitude,
    required double longitude,
  }) async {
    if (!isSupabaseConfigured) return 'Supabase not configured';
    try {
      await supabase.from('exam_center_gps').upsert({
        'center_id': centerId,
        'latitude': latitude,
        'longitude': longitude,
        'radius_meters': kExamFenceRadiusMeters,
        'is_locked': true,
        'locked_at': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<GpsCheckResult> verifyWithinFence(String centerId) async {
    if (!isSupabaseConfigured) {
      return GpsCheckResult(allowed: false, message: 'Backend not configured');
    }

    final cfg = await fetchConfig(centerId);
    if (cfg == null || !cfg.locked || cfg.lat == null || cfg.lng == null) {
      return GpsCheckResult(
        allowed: false,
        message: 'Centre GPS not set. Set latitude, longitude and save (15 m radius).',
      );
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return GpsCheckResult(allowed: false, message: 'Turn on GPS / location services.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return GpsCheckResult(allowed: false, message: 'Location permission required.');
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (pos.isMocked) {
        return GpsCheckResult(allowed: false, message: 'Mock / fake GPS detected. Disable it.');
      }

      final dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        cfg.lat!,
        cfg.lng!,
      );

      final limit = attendanceEffectiveFenceRadiusMeters(
        pos.accuracy,
        nominalRadiusMeters: kExamFenceRadiusMeters,
      );

      if (dist <= limit) {
        return GpsCheckResult(
          allowed: true,
          message: 'Within centre radius',
          distanceMeters: dist,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
      }

      return GpsCheckResult(
        allowed: false,
        message:
            'Outside ${kExamFenceRadiusMeters.toStringAsFixed(0)} m radius (~${dist.toStringAsFixed(0)} m away).',
        distanceMeters: dist,
      );
    } catch (e) {
      return GpsCheckResult(allowed: false, message: 'GPS error: $e');
    }
  }
}
