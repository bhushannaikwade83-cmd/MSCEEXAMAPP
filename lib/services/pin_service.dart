import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PinService {
  static String _prefKey(String centerId) => 'exam_center_pin_hash_$centerId';

  static bool isValidLength(String pin) => pin.length == 4;

  static bool isWeakPin(String pin) {
    if (!isValidLength(pin)) return true;
    const weak = {
      '0000', '1111', '2222', '3333', '4444', '5555', '6666', '7777', '8888', '9999',
      '1234', '4321', '1212', '0123', '9876',
    };
    if (weak.contains(pin)) return true;
    if (pin.split('').toSet().length == 1) return true;
    return false;
  }

  static String _hash(String centerId, String pin) {
    final bytes = utf8.encode('$centerId:$pin:msce_exam_pin');
    return sha256.convert(bytes).toString();
  }

  static Future<bool> hasPinForCenter(String centerId) async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_prefKey(centerId));
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> savePin({
    required String centerId,
    required String pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey(centerId), _hash(centerId, pin));
  }

  static Future<bool> verifyPin({
    required String centerId,
    required String pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey(centerId));
    if (stored == null || stored.isEmpty) return false;
    return stored == _hash(centerId, pin);
  }

  static Future<void> clearPinForCenter(String centerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey(centerId));
  }
}
