import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_db.dart';

/// Resolve `institutes.institute_code` for an institute primary key (or pass-through if already a code).
Future<String> instituteCodeForId(String instituteId) async {
  final row = await appDb.from('institutes').select('institute_code').eq('id', instituteId).maybeSingle();
  final code = row?['institute_code'] as String?;
  if (code != null && code.isNotEmpty) return code;
  return instituteId;
}

/// Resolve institutes.id (UUID) from either primary key or numeric institute_code.
Future<String?> resolveCanonicalInstituteId(String instituteKey) async {
  final key = instituteKey.trim();
  if (key.isEmpty) return null;
  final row = await appDb
      .from('institutes')
      .select('id')
      .or('id.eq.$key,institute_code.eq.$key')
      .maybeSingle();
  final id = row?['id']?.toString().trim();
  return (id != null && id.isNotEmpty) ? id : null;
}

/// Lets existing code use `.uid` like Firebase (`User.id` in GoTrue).
extension SupabaseUserUid on User {
  String get uid => id;
}

/// Maps a `profiles` row to the shape the UI used with Firestore (`userData`).
Map<String, dynamic> profileRowToUserData(Map<String, dynamic> row) {
  return {
    'uid': row['id']?.toString(),
    'userId': row['user_id'],
    'email': row['email'],
    'name': row['name'],
    'role': row['role'],
    'instituteId': row['institute_id'],
    'instituteName': row['institute_name'],
    'phoneNumber': row['phone_number'],
    'status': row['status'],
    'pinHash': row['pin_hash'],
    'encryptedPassword': row['encrypted_password'],
    'hasPIN': row['has_pin'] == true,
    'pinSetAt': row['pin_set_at'],
    'createdAt': row['created_at'],
    'lastLogin': row['last_login'],
    'lastLoginIP': row['last_login_ip'],
  };
}

/// Maps institute row to Firestore-style map.
Map<String, dynamic> instituteRowToMap(Map<String, dynamic> row) {
  return {
    'instituteId': row['id'],
    'instituteCode': row['institute_code'],
    'name': row['name'],
    'location': row['location'],
    'address': row['address'],
    'city': row['city'],
    'district': row['district'],
    'taluka': row['taluka'],
    'state': row['state'],
    'country': row['country'],
    'mobileNo': row['mobile_no'],
    'isActive': row['is_active'],
    'userCount': row['user_count'],
    'studentCount': row['student_count'],
    'srNoMigrationCompleted': row['sr_no_migration_completed'],
    'srNoMigrationDate': row['sr_no_migration_date'],
    'srNoMigrationCount': row['sr_no_migration_count'],
    'createdAt': row['created_at'],
  };
}

User? get currentSupabaseUser => Supabase.instance.client.auth.currentUser;

String? get currentUserId => currentSupabaseUser?.id;
