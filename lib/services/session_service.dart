import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';

class SessionService {
  static Future<void> saveCenter({
    required String centerId,
    required String centerCode,
    required String centerName,
    String? msceInstituteId,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kPrefCenterId, centerId);
    await p.setString(kPrefCenterCode, centerCode);
    await p.setString(kPrefCenterName, centerName);
    if (msceInstituteId != null && msceInstituteId.isNotEmpty) {
      await p.setString(kPrefMsceInstituteId, msceInstituteId);
    }
  }

  static Future<String?> get centerId async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPrefCenterId);
  }

  static Future<Map<String, String>?> getCenter() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(kPrefCenterId);
    if (id == null || id.isEmpty) return null;
    return {
      'id': id,
      'code': p.getString(kPrefCenterCode) ?? '',
      'name': p.getString(kPrefCenterName) ?? '',
      'msceInstituteId': p.getString(kPrefMsceInstituteId) ?? '',
    };
  }

  /// ✅ Clear session only (keep centre locked)
  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    // DO NOT remove centre info - keep it locked!
    // Only clear PIN on logout
    await p.remove(kPrefPin);
  }

  /// ✅ Full clear (used on app uninstall - but centre stays locked via new device)
  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefCenterId);
    await p.remove(kPrefCenterCode);
    await p.remove(kPrefCenterName);
    await p.remove(kPrefMsceInstituteId);
    await p.remove(kPrefPin);
  }

  // ✅ PIN Methods for quick login
  static Future<void> savePin(String pin) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kPrefPin, pin);
  }

  static Future<String?> getPin() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(kPrefPin);
  }

  static Future<void> clearPin() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefPin);
  }

  // ✅ Session based on DATE only (resets after midnight)
  static Future<void> saveSessionDate() async {
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;  // YYYY-MM-DD
    await p.setString(kPrefSessionDate, today);
  }

  static Future<bool> isSessionValid() async {
    final p = await SharedPreferences.getInstance();
    final sessionDateStr = p.getString(kPrefSessionDate);

    if (sessionDateStr == null || sessionDateStr.isEmpty) {
      return false;  // No session date saved
    }

    try {
      final today = DateTime.now().toIso8601String().split('T').first;  // YYYY-MM-DD

      // ✅ Session valid if date matches today
      // After midnight (new date), session expires automatically
      return sessionDateStr == today;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearSessionDate() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefSessionDate);
  }
}
