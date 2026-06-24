import '../core/supabase_client.dart';

class AuthService {
  Future<
      ({
        bool ok,
        String? centerId,
        String? code,
        String? name,
        String? msceInstituteId,
        String? message,
      })> login(String username, String password) async {
    if (!isSupabaseConfigured) {
      return (
        ok: false,
        centerId: null,
        code: null,
        name: null,
        msceInstituteId: null,
        message: 'Supabase not configured. Fill app_config.env',
      );
    }

    try {
      final res = await supabase.rpc('exam_centre_login', params: {
        'p_username': username.trim().toLowerCase(),
        'p_password': password,
      });

      // RPC returns a list, get first element
      final list = res as List;
      if (list.isEmpty) {
        return (
          ok: false,
          centerId: null,
          code: null,
          name: null,
          msceInstituteId: null,
          message: 'Login failed',
        );
      }
      
      final map = Map<String, dynamic>.from(list[0] as Map);
      if (map['ok'] != true) {
        return (
          ok: false,
          centerId: null,
          code: null,
          name: null,
          msceInstituteId: null,
          message: map['message']?.toString() ?? 'Login failed',
        );
      }

      return (
        ok: true,
        centerId: map['centre_id']?.toString(),
        code: map['centre_code']?.toString(),
        name: map['centre_name']?.toString(),
        msceInstituteId: map['exam_msce_institute_id']?.toString(),
        message: null,
      );
    } catch (e) {
      return (
        ok: false,
        centerId: null,
        code: null,
        name: null,
        msceInstituteId: null,
        message: e.toString(),
      );
    }
  }
}
