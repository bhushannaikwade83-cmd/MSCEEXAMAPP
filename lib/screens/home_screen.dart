import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_ui.dart';
import '../presentation/widgets/secure_network_image.dart';
import '../services/msce_student_service.dart';
import '../services/session_service.dart';
import '../services/exam_centre_student_cache.dart';
import 'center_login_screen.dart';
import 'qr_code_scanner_screen.dart';

enum _Filter { all, present, absent }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _students = MsceStudentService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String? _centerName;
  int _rosterCount = 0;
  int _unmatchedRoster = 0;
  List<MsceStudent> _all = [];
  _Filter _filter = _Filter.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final center = await SessionService.getCenter();
    if (center == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CenterLoginScreen()),
      );
      return;
    }

    try {
      // Load directly from exam_students table
      final studentsList = await _students.loadFromExamStudentsTable(
        centerId: center['id']!,
        centerCode: center['code'],
        search: _searchCtrl.text,
      );

      if (!mounted) return;

      setState(() {
        _centerName = center['name'];
        _rosterCount = studentsList.length;
        _unmatchedRoster = 0;
        _all = studentsList;
        _loading = false;

        if (studentsList.isEmpty) {
          _error = 'No students allocated to this exam center. Check exam_students table.';
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load students: ${e.toString()}';
      });
    }
  }

  List<MsceStudent> get _visible {
    switch (_filter) {
      case _Filter.present:
        return _all.where((s) => s.entryMarked).toList();
      case _Filter.absent:
        return _all.where((s) => !s.entryMarked).toList();
      case _Filter.all:
        return _all;
    }
  }

  int get _present => _all.where((s) => s.entryMarked).length;
  int get _absent => _all.length - _present;

  void _snack(String msg, {required bool success}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: success ? AppTheme.accentGreen : AppTheme.accentRed,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _logout() async {
    ExamCentreStudentCache.clear();
    await SessionService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const CenterLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QrCodeScannerScreen()),
          );
        },
        backgroundColor: AppTheme.primaryBlue,
        tooltip: 'Scan student QR code',
        child: const Icon(Icons.qr_code_2, color: Colors.white),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildSearch(),
            _buildFilters(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.primaryBlueDark,
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      child: Row(
        children: [
          Icon(Icons.school_rounded, color: Colors.white.withValues(alpha: 0.95), size: 22.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Students',
                  style: TextStyle(color: Colors.white, fontSize: 17.sp, fontWeight: FontWeight.w800),
                ),
                if (_centerName != null)
                  Text(
                    _centerName!,
                    style: TextStyle(color: Colors.white70, fontSize: 11.sp),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          _chip('Total', _all.length),
          SizedBox(width: 6.w),
          _chip('In', _present),
          SizedBox(width: 6.w),
          _chip('Out', _absent),
          SizedBox(width: 8.w),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int n) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Text(
        '$label $n',
        style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search by name, surname, SR no…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 0),
      child: Wrap(
        spacing: 8,
        children: [
          _filterChip(_Filter.all, 'All (${_all.length})'),
          _filterChip(_Filter.present, 'Present ($_present)'),
          _filterChip(_Filter.absent, 'Absent ($_absent)'),
        ],
      ),
    );
  }

  Widget _filterChip(_Filter f, String label) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: AppTheme.primaryBlue,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.primaryBlue,
        fontWeight: FontWeight.w700,
        fontSize: 12.sp,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryBlue));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _rosterCount > 0
                ? 'No matched students for this centre ($_rosterCount allotted).'
                : 'No students found for this centre.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 88.h),
        itemCount: visible.length + (_unmatchedRoster > 0 ? 1 : 0),
        itemBuilder: (_, i) {
          if (_unmatchedRoster > 0 && i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppTheme.accentRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '$_unmatchedRoster allotted name(s) could not be matched in MSCE — check spelling / institute id.',
                    style: TextStyle(color: AppTheme.accentRed, fontSize: 12.sp),
                  ),
                ),
              ),
            );
          }
          final idx = i - (_unmatchedRoster > 0 ? 1 : 0);
          return _studentCard(visible[idx]);
        },
      ),
    );
  }

  Widget _studentCard(MsceStudent s) {
    final hasPhoto = s.photoUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GovElevatedCard(
        padding: EdgeInsets.fromLTRB(10.w, 10.h, 6.w, 10.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Student Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 110,
                    height: 140,
                    child: hasPhoto
                        ? SecureNetworkImage(
                            cacheKey: 'student_face_${s.id}',
                            imageUrl: s.photoUrl,
                            version: s.photoVersion ?? '0',
                            width: 110,
                            height: 140,
                            fit: BoxFit.cover,
                            placeholder: ColoredBox(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                            errorWidget: _photoPlaceholder(width: 110, height: 140),
                          )
                        : _photoPlaceholder(width: 110, height: 140),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.sp,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.lastName.isNotEmpty)
                        Text(
                          s.lastName,
                          style: TextStyle(fontSize: 12.sp, color: AppTheme.textGray),
                        ),
                      SizedBox(height: 4.h),
                      Text(
                        'SR NO: ${_formatSr(s.srNo)}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Divider(height: 1, color: AppTheme.dividerColor),
            SizedBox(height: 8.h),
            // All Subjects
            ...s.subjects.asMap().entries.map((entry) {
              final idx = entry.key;
              final subject = entry.value as Map<String, dynamic>;
              return _buildSubjectRow(s, subject, idx < s.subjects.length - 1);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectRow(MsceStudent s, Map<String, dynamic> subject, bool showDivider) {
    final subjectCode = subject['subject_code']?.toString() ?? '—';
    final seatNo = subject['seat_no']?.toString() ?? '—';
    final examDate = subject['exam_date']?.toString() ?? '—';
    final startTime = subject['start_time']?.toString() ?? '—';
    final batch = subject['batch']?.toString() ?? '—';
    final isMarked = subject['entry_photo_url'] != null;

    String formatTime(String? time) {
      if (time == null || time.isEmpty) return '—';
      try {
        final parsed = DateTime.parse('2000-01-01 ${time.split('+').first.split('-').first.trim()}');
        return DateFormat('hh:mm a').format(parsed);
      } catch (_) {
        return time.split('+').first.trim();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subject Info
        Text(
          subjectCode,
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppTheme.primaryBlue),
        ),
        SizedBox(height: 6.h),
        Row(
          children: [
            Icon(Icons.event_seat, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text('Seat: $seatNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
            SizedBox(width: 12.w),
            Icon(Icons.groups, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text('Batch: $batch', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
          ],
        ),
        SizedBox(height: 4.h),
        Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text(examDate, style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
            SizedBox(width: 12.w),
            Icon(Icons.access_time, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text(formatTime(startTime), style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
          ],
        ),
        SizedBox(height: 8.h),
        // Entry Photo Box & Button
        if (isMarked && subject['entry_photo_url'] != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 100,
              child: SecureNetworkImage(
                cacheKey: 'entry_${subject['id']}',
                imageUrl: subject['entry_photo_url'],
                fit: BoxFit.cover,
              ),
            ),
          ),
        SizedBox(height: isMarked ? 8.h : 0),
        // Entry Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () {},  // TODO: Implement entry marking
            style: ElevatedButton.styleFrom(
              backgroundColor: isMarked ? AppTheme.primaryGreen : AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 12.h),
            ),
            icon: Icon(isMarked ? Icons.check_circle : Icons.camera_alt, size: 24),
            label: Text(isMarked ? 'Marked ✓' : 'Entry',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (showDivider) ...[
          SizedBox(height: 10.h),
          Divider(height: 1, color: AppTheme.dividerColor),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget _photoPlaceholder({double width = 110, double height = 140}) {
    return Container(
      width: width,
      height: height,
      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
      child: Icon(Icons.person, color: AppTheme.primaryBlue, size: height * 0.5),
    );
  }

  String _formatSr(String sr) {
    final n = int.tryParse(sr.trim());
    if (n != null) return n.toString().padLeft(3, '0');
    return sr.isEmpty ? '—' : sr;
  }
}
