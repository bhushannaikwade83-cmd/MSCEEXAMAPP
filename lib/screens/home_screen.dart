import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';

import '../core/supabase_client.dart';
import '../core/theme/app_ui.dart';
import '../presentation/widgets/secure_network_image.dart';
import '../services/exam_entry_service.dart';
import '../services/msce_student_service.dart';
import '../services/session_service.dart';
import '../services/exam_centre_student_cache.dart';
import '../services/storage_service.dart';
import 'center_login_screen.dart';
import 'pin_login_screen.dart';
import 'exam_subject_camera_screen.dart';
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
  Timer? _clockTimer;

  String? _centerName;
  String? _centerCode;
  int _rosterCount = 0;
  int _unmatchedRoster = 0;
  List<MsceStudent> _all = [];
  _Filter _filter = _Filter.all;
  bool _loading = true;
  String? _error;
  String _currentTime = '';  // ✅ Live clock

  // ✅ New filters
  String? _selectedBatch;  // ✅ Batch filter
  List<String> _allBatches = [];  // ✅ All unique batches

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clockTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _updateClock() {
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
    });
  }

  void _onSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _load() async {
    // ✅ Check if session expired (after midnight)
    final sessionValid = await SessionService.isSessionValid();
    if (!sessionValid) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PinLoginScreen()),
        );
      }
      return;
    }

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

      // ✅ Extract all unique batches from all students
      final batches = <String>{};
      for (final student in studentsList) {
        for (final subject in student.subjects) {
          batches.add(subject['batch']?.toString() ?? '');
        }
      }

      setState(() {
        _centerName = center['name'];
        _centerCode = center['code'];  // ✅ Store centre code
        _rosterCount = studentsList.length;
        _unmatchedRoster = 0;
        _all = studentsList;
        _allBatches = batches.toList()..sort();  // ✅ Sort batches
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
    // ✅ Apply status filter first
    List<MsceStudent> filtered;
    switch (_filter) {
      case _Filter.present:
        filtered = _all.where((s) => s.entryMarked).toList();
        break;
      case _Filter.absent:
        filtered = _all.where((s) => !s.entryMarked).toList();
        break;
      case _Filter.all:
        filtered = _all;
    }

    // ✅ Apply search filter (SR no or student name)
    final searchTerm = _searchCtrl.text.toLowerCase();
    if (searchTerm.isNotEmpty) {
      filtered = filtered.where((s) {
        return s.srNo.toLowerCase().contains(searchTerm) ||
               s.name.toLowerCase().contains(searchTerm) ||
               s.lastName.toLowerCase().contains(searchTerm);
      }).toList();
    }

    // ✅ Apply batch filter
    if (_selectedBatch != null && _selectedBatch!.isNotEmpty) {
      filtered = filtered.where((s) {
        return s.subjects.any((subj) => subj['batch']?.toString() == _selectedBatch);
      }).toList();
    }

    return filtered;
  }

  // ✅ Count based on VISIBLE (filtered) students, not all
  int get _present => _visible.where((s) => s.entryMarked).length;
  int get _absent => _visible.length - _present;

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

    // ✅ Clear session date only (keep PIN and centre locked)
    await SessionService.clearSessionDate();

    if (!mounted) return;

    // ✅ Go to PIN login (session expired)
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const PinLoginScreen()),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Logo Row - MSCE Logo at top-left
          Row(
            children: [
              Image.asset(
                'assets/msce_attendance_app_logo.png',
                height: 40.h,
                width: 40.w,
                fit: BoxFit.contain,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WELCOME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      _currentTime,  // ✅ Live clock
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ Centre Code & Name
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_centerCode != null)
                    Text(
                      'CODE: ${_centerCode!.toUpperCase()}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  if (_centerName != null)
                    Text(
                      _centerName!.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12.h),
          // ✅ Stats Row - Show filtered counts
          Row(
            children: [
              _chip('TOTAL', _visible.length),  // ✅ Show filtered total (by batch)
              SizedBox(width: 6.w),
              _chip('PRESENT', _present),
              SizedBox(width: 6.w),
              _chip('ABSENT', _absent),
              SizedBox(width: 8.w),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.white),
                tooltip: 'Sign out',
              ),
            ],
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
    return Column(
      children: [
        // Status filters
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip(_Filter.all, 'ALL (${_visible.length})'),  // ✅ Show visible count
                SizedBox(width: 8.w),
                _filterChip(_Filter.present, 'PRESENT ($_present)'),
                SizedBox(width: 8.w),
                _filterChip(_Filter.absent, 'ABSENT ($_absent)'),
              ],
            ),
          ),
        ),
        // ✅ Advanced filters
        if (_allBatches.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBatch,
                    hint: const Text('Filter by Batch'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All Batches')),
                      ..._allBatches.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                    ],
                    onChanged: (val) => setState(() {
                      _selectedBatch = val;
                    }),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                // Clear filter button
                ElevatedButton(
                  onPressed: () => setState(() {
                    _selectedBatch = null;
                    _searchCtrl.clear();
                  }),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    backgroundColor: Colors.grey[400],
                  ),
                  child: const Icon(Icons.clear, size: 20),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _filterChip(_Filter f, String label) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label.toUpperCase()),  // ✅ ALL CAPS
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: AppTheme.primaryBlue,
      backgroundColor: AppTheme.backgroundGrey,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.primaryBlue,
        fontWeight: FontWeight.w800,  // ✅ Bolder
        fontSize: 13.sp,  // ✅ Slightly bigger
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

    // ✅ DEBUG: Check if thumbnail photo is loaded
    if (kDebugMode) {
      print('🖼️ Student card: ${s.displayName}');
      print('   photoUrl: "${s.photoUrl}"');
      print('   hasPhoto: $hasPhoto');
    }

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
                // ✅ Tap to enlarge student photo
                GestureDetector(
                  onTap: hasPhoto ? () => _showPhotoFullscreen(s.photoUrl, s.displayName) : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 110.w,
                      height: 150.h,  // ✅ Bigger height
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hasPhoto ? AppTheme.primaryBlue : AppTheme.dividerColor,
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          hasPhoto
                              ? SecureNetworkImage(
                                  cacheKey: 'student_face_${s.id}',
                                  imageUrl: s.photoUrl,
                                  version: s.photoVersion ?? '0',
                                  width: 110.w,
                                  height: 150.h,
                                  fit: BoxFit.cover,
                                  placeholder: ColoredBox(
                                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                  ),
                                  errorWidget: _photoPlaceholder(width: 110, height: 150),
                                )
                              : _photoPlaceholder(width: 110, height: 150),
                          // ✅ Tap indicator
                          if (hasPhoto)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.zoom_in, color: Colors.white, size: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
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
            // ✅ All Subjects - SORTED by exam date/time (earliest first)
            ..._sortSubjectsByExamOrder(s.subjects).asMap().entries.map((entry) {
              final idx = entry.key;
              final subject = entry.value as Map<String, dynamic>;
              final isEnabled = _isSubjectEnabled(s, subject, idx);
              return _buildSubjectRow(s, subject, idx < s.subjects.length - 1, isEnabled);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectRow(MsceStudent s, Map<String, dynamic> subject, bool showDivider, bool isEnabled) {
    // ✅ Use subject_name (primary) or subject_code (fallback)
    final subjectCode = (subject['subject_name']?.toString() ??
                       subject['subject_code']?.toString() ??
                       '—').toUpperCase();  // ✅ ALL CAPS
    final seatNo = (subject['seat_no']?.toString() ?? '—').toUpperCase();
    final batch = (subject['batch']?.toString() ?? '—').toUpperCase();

    // ✅ CRITICAL: Only show photo if THIS specific exam_students row has entry_photo_url
    // Not just checking if ANY subject has a photo
    final isMarked = subject['entry_photo_url'] != null && subject['entry_photo_url'].toString().isNotEmpty;
    final dbIsEnabled = subject['is_enabled'] ?? true;  // ✅ Read from database

    if (kDebugMode && isMarked) {
      debugPrint('📸 Subject row: ID=${subject['id']}, subject=$subjectCode, photoUrl=${subject['entry_photo_url']}');
    }

    // ✅ Format date as dd-mm-yy
    String formatDate(String? date) {
      if (date == null || date.isEmpty) return '—';
      try {
        final parsed = DateTime.parse(date.split('T').first);
        return DateFormat('dd-MM-yy').format(parsed);
      } catch (_) {
        return date;
      }
    }

    String formatTime(String? time) {
      if (time == null || time.isEmpty) return '—';
      try {
        final parsed = DateTime.parse('2000-01-01 ${time.split('+').first.split('-').first.trim()}');
        return DateFormat('hh:mm a').format(parsed).toUpperCase();  // ✅ ALL CAPS
      } catch (_) {
        return time.split('+').first.trim().toUpperCase();
      }
    }

    final examDate = subject['exam_date']?.toString() ?? '';
    final startTime = subject['start_time']?.toString() ?? '';

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
            Text('SEAT: $seatNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
            SizedBox(width: 12.w),
            Icon(Icons.groups, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text('BATCH: $batch', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
          ],
        ),
        SizedBox(height: 4.h),
        Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text(formatDate(examDate), style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray, fontWeight: FontWeight.w600)),
            SizedBox(width: 12.w),
            Icon(Icons.access_time, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text(formatTime(startTime), style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
          ],
        ),
        SizedBox(height: 8.h),
        // ✅ Entry Photo Box (full width)
        if (isMarked && subject['entry_photo_url'] != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: double.infinity,
              height: 200.h,  // ✅ Full width height 200
              child: SecureNetworkImage(
                cacheKey: 'entry_${subject['id']}',
                imageUrl: subject['entry_photo_url'],
                fit: BoxFit.cover,
              ),
            ),
          ),
        SizedBox(height: isMarked ? 8.h : 0),
        // ✅ Show entry time only (green color)
        if (isMarked && subject['entry_at'] != null)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 14, color: AppTheme.primaryGreen),
                SizedBox(width: 4.w),
                Text(
                  'ENTRY TIME: ${_formatEntryTime(subject['entry_at']?.toString() ?? '')}',
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        // ✅ Entry Button - DISABLED if: marked OR (not logically enabled AND db says false)
        // If db says is_enabled=true, override logic and enable it
        Builder(
          builder: (_) {
            final canTap = !isMarked && (isEnabled || dbIsEnabled);
            return SizedBox(
          width: double.infinity,
          height: 56,
          child: Opacity(
            opacity: canTap ? 1.0 : 0.6,
            child: ElevatedButton.icon(
              onPressed: canTap
                  ? () async {
                      // ✅ Open camera for this subject
                      final subjectCode = subject['subject_name']?.toString() ??
                                        subject['subject_code']?.toString() ?? 'Unknown';
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ExamSubjectCameraScreen(
                            studentName: s.name,
                            subjectName: subjectCode,
                          ),
                        ),
                      );

                      if (result != null && mounted) {
                        // ✅ Handle photo with location and timestamp
                        final photo = result['photo'] as XFile;
                        final latitude = result['latitude'] as double?;
                        final longitude = result['longitude'] as double?;
                        final timestamp = result['timestamp'] as DateTime?;

                        print('📸 Photo captured: ${photo.path}');
                        print('📍 Location: $latitude, $longitude');
                        print('⏰ Timestamp: $timestamp');

                        // ✅ Upload photo to B2 and save entry to database
                        _saveEntryWithPhoto(
                          student: s,
                          subject: subject,
                          photo: photo,
                          latitude: latitude,
                          longitude: longitude,
                          timestamp: timestamp,
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isMarked ? AppTheme.primaryGreen : AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12.h),
                disabledBackgroundColor: AppTheme.primaryGreen,
              ),
              icon: Icon(isMarked ? Icons.check_circle : Icons.camera_alt, size: 24),
              label: Text(
                isMarked ? 'Marked ✓' : canTap ? 'Entry' : 'Disabled',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
              ),
            ),
          ),
            );
          },
        ),
        if (showDivider) ...[
          SizedBox(height: 10.h),
          Divider(height: 1, color: AppTheme.dividerColor),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  /// ✅ Sort subjects by exam date + time (earliest first)
  List<Map<String, dynamic>> _sortSubjectsByExamOrder(List<Map<String, dynamic>> subjects) {
    final sorted = [...subjects];
    sorted.sort((a, b) {
      final dateA = a['exam_date']?.toString() ?? '';
      final dateB = b['exam_date']?.toString() ?? '';
      final timeA = a['start_time']?.toString() ?? '';
      final timeB = b['start_time']?.toString() ?? '';

      // Parse dates
      final parsedA = DateTime.tryParse('${dateA}T${timeA.split('+').first.split('-').first.trim()}') ?? DateTime.now();
      final parsedB = DateTime.tryParse('${dateB}T${timeB.split('+').first.split('-').first.trim()}') ?? DateTime.now();

      return parsedA.compareTo(parsedB);
    });
    return sorted;
  }

  /// ✅ Check if subject should be enabled based on sequential marking
  /// First subject always enabled, rest disabled until previous is marked
  bool _isSubjectEnabled(MsceStudent student, Map<String, dynamic> subject, int subjectIndex) {
    // If only 1 subject, always enabled
    if (student.subjects.length <= 1) return true;

    // First subject always enabled
    if (subjectIndex == 0) return true;

    // Check if previous subject is marked
    final sorted = _sortSubjectsByExamOrder(student.subjects.cast<Map<String, dynamic>>());
    final prevSubject = sorted[subjectIndex - 1];
    final prevMarked = prevSubject['entry_photo_url'] != null;

    return prevMarked;
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

  /// ✅ Format entry timestamp as HH:MM:SS
  String _formatEntryTime(String isoString) {
    if (isoString.isEmpty) return '—';
    try {
      final dateTime = DateTime.parse(isoString);
      return DateFormat('HH:mm:ss').format(dateTime);
    } catch (_) {
      return '—';
    }
  }

  // ✅ Show photo fullscreen on tap
  void _showPhotoFullscreen(String photoUrl, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            // ✅ Full screen photo
            SecureNetworkImage(
              cacheKey: 'fullscreen_$photoUrl',
              imageUrl: photoUrl,
              fit: BoxFit.contain,
            ),
            // ✅ Close button
            Positioned(
              top: 16,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 24),
                ),
              ),
            ),
            // ✅ Title
            Positioned(
              top: 16,
              left: 16,
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Save entry with photo, location, and timestamp
  Future<void> _saveEntryWithPhoto({
    required MsceStudent student,
    required Map<String, dynamic> subject,
    required XFile photo,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
  }) async {
    try {
      _snack('Saving entry...', success: false);

      // ✅ Get center info
      final center = await SessionService.getCenter();
      if (center == null) {
        _snack('Center info not found', success: false);
        return;
      }

      // ✅ Get institute ID (fallback to center_id if not available)
      final instituteId = center['institute_id']?.toString() ?? center['id']?.toString() ?? '';
      if (instituteId.isEmpty) {
        _snack('Institute ID not found', success: false);
        return;
      }

      // ✅ Read photo bytes and compress to under 100KB
      // XFile.readAsBytes works on all platforms including web
      // (dart:io File does not exist on web).
      var photoBytes = await photo.readAsBytes();
      print('📸 Original photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');

      // ✅ Compress if larger than 100KB
      if (photoBytes.length > 102400) {  // 100KB
        photoBytes = await _compressPhotoToUnder100KB(photoBytes);
        print('📸 Compressed photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      // ✅ Get subject code from subject_name (primary) or subject_code (fallback)
      final subjectCode = subject['subject_name']?.toString() ??
                         subject['subject_code']?.toString() ??
                         subject['subject']?.toString() ??
                         '';

      if (subjectCode.isEmpty) {
        print('❌ Subject fields: ${subject.keys}');
        _snack('Subject name not found', success: false);
        return;
      }

      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: instituteId,
        folderYear: DateTime.now().year.toString(),
        srNo: student.srNo,
        subject: subjectCode,
        date: timestamp?.toIso8601String().split('T').first ?? DateTime.now().toIso8601String().split('T').first,
        photoBytes: photoBytes,
        photoType: 'entry',
      );

      final photoUrl = uploadResult['url'] ?? photo.path;
      print('✅ Photo uploaded: $photoUrl');

      // ✅ VERIFY: Check if seat number matches before saving
      final seatNo = subject['seat_no']?.toString() ?? '';
      if (seatNo.isEmpty) {
        _snack('❌ Seat number not found - cannot verify', success: false);
        return;
      }

      // ✅ Verify seat number from database
      final examStudents = await supabase
          .from('exam_students')
          .select('id, seat_no, exam_student_id')
          .eq('exam_student_id', student.id)
          .eq('subject_name', subjectCode);

      if (examStudents.isEmpty) {
        _snack('❌ Student subject record not found', success: false);
        return;
      }

      // ✅ Check if any record has matching seat number
      final dbSeatNo = examStudents[0]['seat_no']?.toString() ?? '';
      if (dbSeatNo != seatNo) {
        _snack('❌ Seat mismatch! Expected: $dbSeatNo, Got: $seatNo', success: false);
        print('❌ SEAT MISMATCH: Expected $dbSeatNo but got $seatNo');
        return;
      }

      print('✅ Seat verified: $seatNo matches database');

      // ✅ Save entry to database with location and timestamp
      final entryService = ExamEntryService();
      final result = await entryService.markSubjectEntry(
        centerId: center['id']!,
        studentId: student.id,
        photoPath: photoUrl,
        subjectCode: subjectCode,
        latitude: latitude,
        longitude: longitude,
        entryTimestamp: timestamp,
        seatNo: seatNo,  // ✅ Pass verified seat number
      );

      if (!mounted) return;

      if (result.ok) {
        _snack('✅ Entry marked - PRESENT ✓', success: true);

        // ✅ Update local state immediately (faster than reload)
        setState(() {
          // Find and update ONLY the specific subject for this student
          for (int i = 0; i < _all.length; i++) {
            if (_all[i].id == student.id) {
              // Update subjects in place - match by id (primary key)
              for (int j = 0; j < _all[i].subjects.length; j++) {
                final subj = _all[i].subjects[j];
                // Match by database ID (most precise)
                if (subj['id'] == subject['id']) {
                  _all[i].subjects[j]['entry_photo_url'] = photoUrl;
                  _all[i].subjects[j]['entry_photo_at'] = DateTime.now().toIso8601String();  // ✅ IST, not UTC
                  print('✅ Updated subject ${subj['id']} with photo: $photoUrl');
                  break;
                }
              }
              break;
            }
          }
        });

        // ✅ AUTO-ENABLE next subject if exists
        final sorted = _sortSubjectsByExamOrder(student.subjects.cast<Map<String, dynamic>>());
        final currentIndex = sorted.indexWhere((s) => s['subject_name'] == subjectCode);

        if (currentIndex >= 0 && currentIndex < sorted.length - 1) {
          final nextSubject = sorted[currentIndex + 1];
          final nextSubjectId = nextSubject['id']?.toString() ?? '';

          if (nextSubjectId.isNotEmpty) {
            try {
              // ✅ Set is_enabled=true for next subject
              await supabase
                  .from('exam_students')
                  .update({'is_enabled': true})
                  .eq('id', nextSubjectId);
              print('✅ Next subject auto-enabled: $nextSubjectId');
            } catch (e) {
              print('⚠️ Could not auto-enable next subject: $e');
            }
          }
        }

        // Reload students to sync database state (happens in background)
        await Future.delayed(const Duration(milliseconds: 500));
        _load();
      } else {
        _snack('❌ ${result.message}', success: false);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Save failed: $e', success: false);
      print('❌ Entry save error: $e');
    }
  }

  /// ✅ Compress photo to under 100KB
  Future<Uint8List> _compressPhotoToUnder100KB(Uint8List photoBytes) async {
    try {
      // Decode image
      final decoded = img.decodeImage(photoBytes);
      if (decoded == null) return photoBytes;

      // ✅ Bake EXIF orientation into the pixels BEFORE re-encoding.
      // encodeJpg strips EXIF metadata; without baking first, portrait
      // photos (stored by cameras as rotated pixels + EXIF tag) would be
      // saved permanently sideways.
      img.Image image = decoded;
      try {
        image = img.bakeOrientation(image);
      } catch (_) {}

      // Start with quality 90 and reduce if needed
      int quality = 90;
      Uint8List compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));

      // Keep reducing quality until under 100KB
      while (compressed.length > 102400 && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      }

      // If still over 100KB, resize image
      if (compressed.length > 102400) {
        final resized = img.copyResize(image,
            width: (image.width * 0.8).toInt(),
            height: (image.height * 0.8).toInt());
        compressed = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }

      print('✅ Compression complete: quality=$quality, size=${(compressed.length / 1024).toStringAsFixed(2)}KB');
      return compressed;
    } catch (e) {
      print('⚠️ Compression error: $e, returning original');
      return photoBytes;
    }
  }
}
