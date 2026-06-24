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

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(kPrefCenterId);
    await p.remove(kPrefCenterCode);
    await p.remove(kPrefCenterName);
    await p.remove(kPrefMsceInstituteId);
  }
}
