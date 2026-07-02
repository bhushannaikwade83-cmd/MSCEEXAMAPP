import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../core/supabase_client.dart';

class LocationService {
  /// Request location permission
  /// Returns true if permission granted, false otherwise
  static Future<bool> requestLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        return result == LocationPermission.whileInUse ||
               result == LocationPermission.always;
      } else if (permission == LocationPermission.deniedForever) {
        print('❌ Location permission denied forever');
        return false;
      }

      return permission == LocationPermission.whileInUse ||
             permission == LocationPermission.always;
    } catch (e) {
      print('❌ Location permission error: $e');
      return false;
    }
  }

  /// Get current GPS location (fast, with fallback to last known position)
  static Future<Map<String, double>?> getCurrentLocation() async {
    try {
      // Try best accuracy first with short timeout
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 5),
        );

        return {
          'latitude': position.latitude,
          'longitude': position.longitude,
        };
      } catch (_) {
        // Fallback to last known position (instant, no wait)
        final position = await Geolocator.getLastKnownPosition();
        if (position != null) {
          return {
            'latitude': position.latitude,
            'longitude': position.longitude,
          };
        }
        return null;
      }
    } catch (e) {
      // Silent - location is optional
      return null;
    }
  }

  /// Save location to database for centre login (keep history in JSON)
  static Future<bool> saveLoginLocation({
    required String centreId,
    required String centreCode,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // First, get current history
      final currentData = await supabase
          .from('exam_centres')
          .select('login_history')
          .eq('id', centreId)
          .maybeSingle();

      List<dynamic> history = [];
      if (currentData != null && currentData['login_history'] != null) {
        history = List<dynamic>.from(currentData['login_history'] as List);
      }

      // Add new entry to history
      final newEntry = {
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': now,
      };
      history.add(newEntry);

      // Save both latest values and history
      await supabase.from('exam_centres').update({
        'login_latitude': latitude,
        'login_longitude': longitude,
        'login_at': now,
        'login_history': history,
      }).eq('id', centreId);

      return true;
    } catch (e) {
      // Silent - location save failure doesn't affect app
      return false;
    }
  }

  /// Save location to database for student entry (one time only, no history)
  static Future<bool> saveEntryLocation({
    required String examStudentId,
    required String subjectName,
    required String seatNo,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final now = DateTime.now().toIso8601String();

      // Save entry location (one time only, no history needed)
      await supabase.from('exam_students').update({
        'entry_latitude': latitude,
        'entry_longitude': longitude,
        'entry_at': now,
      }).eq('id', examStudentId);

      return true;
    } catch (e) {
      // Silent - location save failure doesn't affect attendance marking
      return false;
    }
  }

  /// Get latest login location for a centre
  static Future<Map<String, dynamic>?> getCentreLoginLocation(String centreId) async {
    try {
      final result = await supabase
          .from('exam_centres')
          .select('login_latitude, login_longitude, login_at')
          .eq('id', centreId)
          .single();

      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('⚠️ No login location found: $e');
      return null;
    }
  }

  /// Get latest entry location for a student
  static Future<Map<String, dynamic>?> getStudentEntryLocation(String examStudentId) async {
    try {
      final result = await supabase
          .from('exam_students')
          .select('entry_latitude, entry_longitude, entry_at')
          .eq('id', examStudentId)
          .single();

      return Map<String, dynamic>.from(result);
    } catch (e) {
      print('⚠️ No entry location found: $e');
      return null;
    }
  }
}
