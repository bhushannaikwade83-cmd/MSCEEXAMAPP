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
  String? _selectedSubject;  // ✅ Subject filter
  List<String> _allSubjects = [];  // ✅ All unique subjects

  // ✅ Pagination
  int _currentPage = 1;
  int _itemsPerPage = 20;  // ✅ 20 students per page
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();  // ✅ Initialize pagination
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
    _pageController.dispose();  // ✅ Dispose pagination controller
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

        // ✅ Extract all unique subjects
        final subjects = <String>{};
        for (final student in studentsList) {
          for (final subject in student.subjects) {
            final subjectName = subject['subject_name']?.toString() ??
                subject['subject_code']?.toString() ??
                subject['subject']?.toString() ??
                '';
            if (subjectName.isNotEmpty) {
              subjects.add(subjectName);
            }
          }
        }
        _allSubjects = subjects.toList()..sort();  // ✅ Sort subjects
        _currentPage = 1;  // ✅ Reset pagination on load
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
        // Check student name/SR NO
        final nameMatch = s.name.toLowerCase().contains(searchTerm) ||
                         s.lastName.toLowerCase().contains(searchTerm) ||
                         s.srNo.toLowerCase().contains(searchTerm);

        // ✅ Also check SR NO in all subjects (each subject can have different SR NO)
        final subjectMatch = s.subjects.any((subject) {
          final srNo = subject['sr_no']?.toString().toLowerCase() ?? '';
          final seatNo = subject['seat_no']?.toString().toLowerCase() ?? '';
          return srNo.contains(searchTerm) || seatNo.contains(searchTerm);
        });

        return nameMatch || subjectMatch;
      }).toList();
    }

    // ✅ Apply batch filter
    if (_selectedBatch != null && _selectedBatch!.isNotEmpty) {
      filtered = filtered.where((s) {
        return s.subjects.any((subj) => subj['batch']?.toString() == _selectedBatch);
      }).toList();
    }

    // ✅ Apply subject filter and sort by seat number
    if (_selectedSubject != null && _selectedSubject!.isNotEmpty) {
      filtered = filtered.where((s) {
        return s.subjects.any((subj) {
          final subjectName = subj['subject_name']?.toString() ??
              subj['subject_code']?.toString() ??
              subj['subject']?.toString() ??
              '';
          return subjectName == _selectedSubject;
        });
      }).toList();

      // ✅ Sort by seat number in ascending order
      filtered.sort((a, b) {
        final aSeat = a.subjects.firstWhere(
          (s) => (s['subject_name']?.toString() ?? s['subject_code']?.toString() ?? s['subject']?.toString() ?? '') == _selectedSubject,
          orElse: () => {},
        )['seat_no']?.toString() ?? '';

        final bSeat = b.subjects.firstWhere(
          (s) => (s['subject_name']?.toString() ?? s['subject_code']?.toString() ?? s['subject']?.toString() ?? '') == _selectedSubject,
          orElse: () => {},
        )['seat_no']?.toString() ?? '';

        return aSeat.compareTo(bSeat);
      });
    }

    return filtered;
  }

  /// ✅ Fetch SR NO from database (exam_students table) for the student
  /// Returns sr_no from the first matching subject
  String _getSrNoFromSubjects(List<Map<String, dynamic>> subjects, String? filterSubject) {
    if (subjects.isEmpty) return '';

    // If filtering by subject, get sr_no from that subject
    if (filterSubject != null && filterSubject.isNotEmpty) {
      final subject = subjects.firstWhere(
        (s) => (s['subject_name']?.toString() ?? s['subject_code']?.toString() ?? '') == filterSubject,
        orElse: () => <String, dynamic>{},
      );
      return subject['sr_no']?.toString() ?? '';
    }

    // Otherwise return from first subject
    return subjects.isNotEmpty ? (subjects.first['sr_no']?.toString() ?? '') : '';
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

  // ✅ Pagination helper methods
  int get _totalPages => (_visible.length / _itemsPerPage).ceil();

  List<MsceStudent> get _paginatedStudents {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end = start + _itemsPerPage;
    return _visible.sublist(start, end > _visible.length ? _visible.length : end);
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages) return;
    setState(() => _currentPage = page);
  }

  void _nextPage() {
    if (_currentPage < _totalPages) {
      _goToPage(_currentPage + 1);
    }
  }

  void _previousPage() {
    if (_currentPage > 1) {
      _goToPage(_currentPage - 1);
    }
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
            // ✅ Status filter buttons (ALL, PRESENT, ABSENT) - moved to top
            _buildStatusFilters(),
            // ✅ All Batches + All Subjects filters below status buttons
            _buildAdvancedFilters(),
            _buildSearch(),
            Expanded(child: _buildBody()),
            // ✅ Pagination fixed at bottom (only if multiple pages)
            if (_totalPages > 1) _buildPaginationBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.primaryBlueDark,
      padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ Top Row: Logo + Center Info (Right side)
          Row(
            children: [
              // ✅ MSCE Logo Badge - Shows actual logo image
              Container(
                height: 36.h,
                width: 36.w,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/msce_attendance_app_logo.png',
                    fit: BoxFit.contain,
                    scale: 1.0,
                    errorBuilder: (context, error, stackTrace) {
                      print('❌ Logo image failed to load: $error');
                      // Fallback: Show MSCE text if image not found
                      return Container(
                        color: Colors.white,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'MSCE',
                                style: TextStyle(
                                  color: AppTheme.primaryBlue,
                                  fontSize: 8.sp,
                                  fontWeight: FontWeight.w900,
                                  height: 0.9,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              // ✅ Center Code & Name (Expanded, Right side)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    if (_centerCode != null)
                      Text(
                        'CODE: ${_centerCode!}',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 8.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (_centerName != null)
                      Text(
                        _centerName!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.sp,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // ✅ Logout button
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.white, size: 18),
                tooltip: 'Sign out',
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(minWidth: 30.w, minHeight: 30.h),
              ),
            ],
          ),
          SizedBox(height: 2.h),
          // ✅ Welcome + Clock (Same line, left + right)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WELCOME',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                _currentTime,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }



  // ✅ NEW: Advanced filters (Batch + Subject) on SAME line - AUTO RESPONSIVE
  Widget _buildAdvancedFilters() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final horizontalPad = isMobile ? 8.w : 10.w;
    final verticalPad = isMobile ? 4.h : 6.h;
    final innerHPad = isMobile ? 6.w : 8.w;
    final innerVPad = isMobile ? 4.h : 5.h;
    final gap = isMobile ? 4.w : 6.w;
    final borderRad = isMobile ? 4.r : 5.r;
    final fontSize = isMobile ? 8.5.sp : 9.sp;
    final iconSize = isMobile ? 14.0 : 15.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, verticalPad, horizontalPad, verticalPad),
      child: Row(
        children: [
          // Batch filter (LEFT)
          if (_allBatches.isNotEmpty)
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedBatch,
                isExpanded: true, // ✅ Prevent horizontal pixel overflow
                hint: Text('Batches',
                    style: TextStyle(fontSize: fontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('All Batches',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ..._allBatches.map((b) => DropdownMenuItem(
                      value: b,
                      child:
                          Text(b, maxLines: 1, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() {
                  _selectedBatch = val;
                  _currentPage = 1;
                }),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRad)),
                  contentPadding: EdgeInsets.symmetric(horizontal: innerHPad, vertical: innerVPad),
                  isDense: true,
                  suffixIcon: _selectedBatch != null
                      ? IconButton(
                          icon: Icon(Icons.clear, size: iconSize),
                          onPressed: () => setState(() {
                            _selectedBatch = null;
                            _currentPage = 1;
                          }),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(minWidth: isMobile ? 24.w : 26.w),
                        )
                      : null,
                ),
              ),
            ),
          SizedBox(width: gap),
          // Subject filter (RIGHT)
          if (_allSubjects.isNotEmpty)
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedSubject,
                isExpanded: true, // ✅ Prevent horizontal pixel overflow
                hint: Text('Subjects',
                    style: TextStyle(fontSize: fontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                items: [
                  const DropdownMenuItem(
                      value: null,
                      child: Text('All Subjects',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ..._allSubjects.map((s) => DropdownMenuItem(
                      value: s,
                      child:
                          Text(s, maxLines: 1, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) => setState(() {
                  _selectedSubject = val;
                  _currentPage = 1;
                }),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRad)),
                  contentPadding: EdgeInsets.symmetric(horizontal: innerHPad, vertical: innerVPad),
                  isDense: true,
                  suffixIcon: _selectedSubject != null
                      ? IconButton(
                          icon: Icon(Icons.clear, size: iconSize),
                          onPressed: () => setState(() {
                            _selectedSubject = null;
                            _currentPage = 1;
                          }),
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(minWidth: isMobile ? 24.w : 26.w),
                        )
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ✅ NEW: Status filters (moved below search)
  Widget _buildStatusFilters() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip(_Filter.all, 'ALL (${_visible.length})'),
            SizedBox(width: 8.w),
            _filterChip(_Filter.present, 'PRESENT ($_present)'),
            SizedBox(width: 8.w),
            _filterChip(_Filter.absent, 'ABSENT ($_absent)'),
          ],
        ),
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
      onRefresh: () async {
        await _load();
        _goToPage(1);  // ✅ Reset to first page on refresh
      },
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
        itemCount: _paginatedStudents.length + (_unmatchedRoster > 0 ? 1 : 0),
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
          // ✅ Pass selected subject to student card (shows full view with only that subject's button)
          return _studentCard(_paginatedStudents[idx], _selectedSubject);
        },
      ),
    );
  }

  // ✅ Subject-specific card (when subject filter is selected)
  Widget _studentSubjectCard(MsceStudent s, String selectedSubject) {
    // Find the selected subject row for this student
    final subjectRow = s.subjects.firstWhere(
      (subj) {
        final subjName = subj['subject_name']?.toString() ??
            subj['subject_code']?.toString() ??
            subj['subject']?.toString() ??
            '';
        return subjName == selectedSubject;
      },
      orElse: () => {},
    );

    if (subjectRow.isEmpty) {
      return const SizedBox.shrink();  // Skip if student doesn't have this subject
    }

    final seatNo = subjectRow['seat_no']?.toString() ?? '—';
    final batch = subjectRow['batch']?.toString() ?? '—';
    final isMarked = subjectRow['entry_photo_url'] != null &&
                     subjectRow['entry_photo_url'].toString().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GovElevatedCard(
        padding: EdgeInsets.all(12.w),
        child: Row(
          children: [
            // Student name + seat no
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.displayName,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'SEAT: $seatNo | BATCH: $batch',
                    style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray),
                  ),
                  if (isMarked) ...[
                    SizedBox(height: 8.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✓ Entry Marked',
                        style: TextStyle(color: AppTheme.primaryGreen, fontSize: 11.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: 12.w),
            // Entry button
            ElevatedButton(
              onPressed: isMarked ? null : () => _onMarkEntry(context, s, subjectRow, selectedSubject),
              style: ElevatedButton.styleFrom(
                backgroundColor: isMarked ? Colors.grey[300] : AppTheme.primaryGreen,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              ),
              child: Text(
                isMarked ? '✓ Done' : 'Mark Entry',
                style: TextStyle(
                  color: isMarked ? Colors.grey[600] : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Handle marking entry (extracted for reuse)
  Future<void> _onMarkEntry(BuildContext context, MsceStudent student, Map<String, dynamic> subject, String subjectCode) async {
    // Implement same logic as home_screen entry marking
    print('Marking entry for ${student.displayName} - $subjectCode');
    // TODO: Call actual entry marking logic
  }

  Widget _studentCard(MsceStudent s, [String? filterSubject]) {
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
                                  cachePhotos: false,  // ✅ Always fetch fresh profile photo
                                  cacheKey: 'student_face_${s.id}_${s.photoVersion ?? '0'}',
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
                      // ✅ Get SR NO from database (first subject's sr_no)
                      Text(
                        'SR NO: ${_formatSr(_getSrNoFromSubjects(s.subjects, filterSubject))}',
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
            // ✅ Subjects - filtered by selected subject if any
            ...(() {
              var subjectsToShow = _sortSubjectsByExamOrder(s.subjects);

              // ✅ If subject filter selected, show only that subject
              if (filterSubject != null && filterSubject!.isNotEmpty) {
                subjectsToShow = subjectsToShow.where((subj) {
                  final subjName = subj['subject_name']?.toString() ??
                      subj['subject_code']?.toString() ??
                      subj['subject']?.toString() ??
                      '';
                  return subjName == filterSubject;
                }).toList();
              }

              return subjectsToShow.asMap().entries.map((entry) {
                final idx = entry.key;
                final subject = entry.value as Map<String, dynamic>;
                final isEnabled = _isSubjectEnabled(s, subject, idx);
                return _buildSubjectRow(s, subject, false, isEnabled);  // ✅ No divider for single subject
              });
            })(),
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
    final srNo = (subject['sr_no']?.toString() ?? '—');  // ✅ Get SR NO from database
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
            // ✅ SR NO from database
            Icon(Icons.assignment, size: 14, color: AppTheme.textGray),
            SizedBox(width: 4.w),
            Text('SR: $srNo', style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
          ],
        ),
        SizedBox(height: 4.h),
        Row(
          children: [
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
        // ✅ Entry Photo Box (full width + clickable for zoom)
        if (isMarked && subject['entry_photo_url'] != null)
          GestureDetector(
            onTap: () => _showPhotoFullscreen(subject['entry_photo_url'], 'Entry - $subjectCode'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 300.h,  // ✅ INCREASED: Better visibility
                child: Stack(
                  children: [
                    SecureNetworkImage(
                      // ✅ ALWAYS FRESH: Disable cache, fetch from B2 every time
                      // Entry photos update frequently, so always get latest from database
                      cachePhotos: false,
                      cacheKey: 'entry_${subject['id']}_${subject['entry_photo_url']?.hashCode ?? ''}',
                      imageUrl: subject['entry_photo_url'],
                      fit: BoxFit.cover,
                    ),
                  ],
                ),
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
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    disabledBackgroundColor: AppTheme.primaryGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: Icon(isMarked ? Icons.check_circle : Icons.camera_alt, size: 20),
                  label: Text(
                    isMarked ? 'Marked ✓' : (canTap ? 'Entry' : 'Disabled'),
                    style: TextStyle(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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

  // ✅ Build pagination bar (responsive for mobile/tablet)
  Widget _buildPaginationBar() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Page info on top
                Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Column(
                    children: [
                      Text(
                        'Page $_currentPage of $_totalPages',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                      ),
                      Text(
                        '${_paginatedStudents.length} of ${_visible.length} students',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: AppTheme.textGray,
                        ),
                      ),
                    ],
                  ),
                ),
                // Buttons row on bottom
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Previous button
                    Expanded(
                      child: SizedBox(
                        height: 40.h,
                        child: ElevatedButton.icon(
                          onPressed: _currentPage > 1 ? _previousPage : null,
                          icon: const Icon(Icons.chevron_left, size: 18),
                          label: const Text('Prev'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            disabledBackgroundColor: AppTheme.dividerColor,
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    // Next button
                    Expanded(
                      child: SizedBox(
                        height: 40.h,
                        child: ElevatedButton.icon(
                          onPressed: _currentPage < _totalPages ? _nextPage : null,
                          icon: const Icon(Icons.chevron_right, size: 18),
                          label: const Text('Next'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            disabledBackgroundColor: AppTheme.dividerColor,
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous button
                ElevatedButton.icon(
                  onPressed: _currentPage > 1 ? _previousPage : null,
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Previous'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    disabledBackgroundColor: AppTheme.dividerColor,
                  ),
                ),

                // Page info
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Page $_currentPage of $_totalPages',
                          style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textDark,
                          ),
                        ),
                        Text(
                          '${_paginatedStudents.length} of ${_visible.length} students',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: AppTheme.textGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Next button
                ElevatedButton.icon(
                  onPressed: _currentPage < _totalPages ? _nextPage : null,
                  icon: const Icon(Icons.chevron_right),
                  label: const Text('Next'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    disabledBackgroundColor: AppTheme.dividerColor,
                  ),
                ),
              ],
            ),
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
            // ✅ Full screen photo - ALWAYS FRESH (same as thumbnail)
            SecureNetworkImage(
              cachePhotos: false,  // ✅ Always fetch fresh, never use cache
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
      print('═══════════════════════════════════════════════════════════');
      print('🚀 [STEP 1] Entry marking started for: ${student.name}');
      print('═══════════════════════════════════════════════════════════');

      // ✅ Get center info immediately
      final center = await SessionService.getCenter();
      if (center == null) {
        print('❌ [STEP 1] Center info not found');
        _snack('Center info not found', success: false);
        return;
      }
      print('✅ [STEP 1] Center retrieved: ${center['name']} (ID: ${center['id']})');

      // ✅ Get centre code (NOT institute_id which is UUID)
      final centreCode = center['code']?.toString() ?? '';
      if (centreCode.isEmpty) {
        print('❌ [STEP 1] Centre code not found in center: $center');
        _snack('Centre code not found', success: false);
        return;
      }
      print('✅ [STEP 1] Centre code extracted: $centreCode');

      // ✅ Get subject code and exam_student_id FIRST (needed for UI update)
      final subjectCode = subject['subject_name']?.toString() ??
                         subject['subject_code']?.toString() ??
                         subject['subject']?.toString() ??
                         '';

      if (subjectCode.isEmpty) {
        print('❌ [STEP 1] Subject name not found. Available fields: ${subject.keys}');
        _snack('Subject name not found', success: false);
        return;
      }
      print('✅ [STEP 1] Subject: $subjectCode');

      final examStudentId = subject['exam_student_id']?.toString() ?? subject['id']?.toString() ?? '';
      if (examStudentId.isEmpty) {
        print('❌ [STEP 1] Exam student ID not found in subject: ${subject.keys}');
        _snack('❌ Exam student ID not found', success: false);
        return;
      }
      print('✅ [STEP 1] Exam student ID: $examStudentId');

      // ✅ INSTANT SUCCESS: Update UI immediately with placeholder
      print('═══════════════════════════════════════════════════════════');
      print('🎨 [STEP 2] Updating UI with placeholder...');
      print('═══════════════════════════════════════════════════════════');
      _snack('✅ Entry marked - PRESENT ✓', success: true);

      setState(() {
        for (int i = 0; i < _all.length; i++) {
          if (_all[i].id == student.id) {
            for (int j = 0; j < _all[i].subjects.length; j++) {
              if (_all[i].subjects[j]['id'] == subject['id']) {
                print('✅ [STEP 2] Found subject in state at index [$i][$j]');
                _all[i].subjects[j]['entry_photo_url'] = 'marking...';  // ✅ Show placeholder
                _all[i].subjects[j]['entry_photo_at'] = DateTime.now().toIso8601String();
                break;
              }
            }
            break;
          }
        }
      });
      print('✅ [STEP 2] UI placeholder updated');

      // ✅ BACKGROUND: Upload photo asynchronously (don't await)
      print('═══════════════════════════════════════════════════════════');
      print('📤 [STEP 3] Starting background photo upload...');
      print('═══════════════════════════════════════════════════════════');
      _uploadEntryPhotoInBackground(
        photo: photo,
        student: student,
        subject: subject,
        subjectCode: subjectCode,
        examStudentId: examStudentId,
        centreCode: centreCode,
        center: center,
        latitude: latitude,
        longitude: longitude,
        timestamp: timestamp,
      );

      return;
    } catch (e) {
      if (!mounted) return;
      print('═══════════════════════════════════════════════════════════');
      print('❌ [ERROR] Entry save error: $e');
      print('═══════════════════════════════════════════════════════════');
      _snack('Error: $e', success: false);
    }
  }

  /// ✅ Background upload - runs independently without blocking UI
  Future<void> _uploadEntryPhotoInBackground({
    required XFile photo,
    required MsceStudent student,
    required Map<String, dynamic> subject,
    required String subjectCode,
    required String examStudentId,
    required String centreCode,
    required Map<String, dynamic> center,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
  }) async {
    try {
      // ✅ Extract seat_no from subject (exam_students row)
      final seatNo = subject['seat_no']?.toString() ?? student.srNo;

      print('═══════════════════════════════════════════════════════════');
      print('📸 [BG-UPLOAD] Background upload started');
      print('   Student: ${student.name} (Seat: $seatNo)');
      print('   Subject: $subjectCode');
      print('   Centre Code: $centreCode');
      print('═══════════════════════════════════════════════════════════');

      // ✅ Read and compress photo
      var photoBytes = await photo.readAsBytes();
      print('📸 [BG-1] Original photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');

      if (photoBytes.length > 1048576) {  // ✅ 1MB limit (increased from 100KB)
        print('⚠️ [BG-1] Photo exceeds 1MB, compressing...');
        photoBytes = await _compressPhotoToUnder100KB(photoBytes);
        print('✅ [BG-1] Compressed photo size: ${(photoBytes.length / 1024).toStringAsFixed(2)} KB');
      } else {
        print('✅ [BG-1] Photo size OK (${(photoBytes.length / 1024).toStringAsFixed(2)} KB < 1MB)');
      }

      // ✅ Upload to B2
      print('═══════════════════════════════════════════════════════════');
      print('📤 [BG-2] Uploading to B2 Storage Service...');
      print('   centreCode: $centreCode');
      print('   folderYear: ${DateTime.now().year}');
      print('   seatNo: $seatNo');
      print('   subject: $subjectCode');
      print('═══════════════════════════════════════════════════════════');

      // ✅ Generate timestamp folder for versioning (Unix timestamp in milliseconds)
      final timestampFolder = DateTime.now().millisecondsSinceEpoch.toString();

      final uploadResult = await StorageService.uploadAttendancePhoto(
        instituteId: centreCode,  // ✅ Exam centre code (e.g., "4305")
        folderYear: DateTime.now().year.toString(),
        srNo: seatNo,  // ✅ Seat number from exam_students table
        subject: subjectCode,
        date: timestamp?.toIso8601String().split('T').first ?? DateTime.now().toIso8601String().split('T').first,
        photoBytes: photoBytes,
        photoType: 'entry',
        timestamp: timestampFolder,  // ✅ NEW: Add timestamp folder
      );

      var photoUrl = uploadResult['url'] ?? photo.path;
      print('✅ [BG-2] Upload successful!');
      print('   URL: $photoUrl');
      print('   Path: ${uploadResult['path']}');

      // ✅ Convert proxy URL to direct B2 URL if needed
      if (photoUrl.startsWith('/api/b2-upload')) {
        final uri = Uri.parse('http://dummy.com$photoUrl');
        final key = uri.queryParameters['key'];
        if (key != null && key.isNotEmpty) {
          photoUrl = 'https://f004.backblazeb2.com/file/attendance-students-photos/$key';
          print('🔄 [BG-2] Converted proxy URL to direct B2 URL: $photoUrl');
        }
      }

      print('═══════════════════════════════════════════════════════════');
      print('✅ [BG-2] Photo uploaded to B2: $photoUrl');
      print('═══════════════════════════════════════════════════════════');

      // ✅ Save to database
      print('═══════════════════════════════════════════════════════════');
      print('💾 [BG-3] Saving to database...');
      print('   centerId: ${center['id']}');
      print('   studentId: $examStudentId');
      print('   photoPath: $photoUrl');
      print('   subjectCode: $subjectCode');
      print('   latitude: $latitude, longitude: $longitude');
      print('═══════════════════════════════════════════════════════════');

      final entryService = ExamEntryService();
      final result = await entryService.markSubjectEntry(
        centerId: center['id']!,
        studentId: examStudentId,
        photoPath: photoUrl,
        subjectCode: subjectCode,
        latitude: latitude,
        longitude: longitude,
        entryTimestamp: timestamp,
        seatNo: subject['seat_no']?.toString() ?? '',
      );

      print('✅ [BG-3] Database save result: $result');

      if (mounted) {
        // ✅ FETCH FRESH from database to ensure we have correct URL
        print('═══════════════════════════════════════════════════════════');
        print('📥 [BG-4] Fetching fresh data from database...');
        print('═══════════════════════════════════════════════════════════');

        try {
          // Fetch the saved exam_students row to get the actual saved URL
          final freshData = await supabase
              .from('exam_students')
              .select('id, entry_photo_url, entry_photo_at')
              .eq('id', subject['id'])
              .maybeSingle();

          if (freshData != null) {
            final dbPhotoUrl = freshData['entry_photo_url']?.toString() ?? photoUrl;
            print('✅ [BG-4] Fresh data from DB:');
            print('   URL: $dbPhotoUrl');
            print('   At: ${freshData['entry_photo_at']}');

            setState(() {
              for (int i = 0; i < _all.length; i++) {
                if (_all[i].id == student.id) {
                  for (int j = 0; j < _all[i].subjects.length; j++) {
                    if (_all[i].subjects[j]['id'] == subject['id']) {
                      print('✅ [BG-4] Updating state with FRESH DB data at index [$i][$j]');
                      print('   OLD: ${_all[i].subjects[j]['entry_photo_url']}');
                      print('   NEW: $dbPhotoUrl');
                      _all[i].subjects[j]['entry_photo_url'] = dbPhotoUrl;
                      _all[i].subjects[j]['entry_photo_at'] = freshData['entry_photo_at'];
                      print('✅ [BG-4] State updated successfully');
                      print('   Thumbnail will now fetch fresh URL: $dbPhotoUrl');
                      break;
                    }
                  }
                  break;
                }
              }
            });

            // ✅ Force clear image cache for entry photo URL
            if (mounted && dbPhotoUrl.isNotEmpty) {
              await Future.delayed(const Duration(milliseconds: 50));
              // Clear Flutter's image cache
              imageCache.evict(Uri.parse(dbPhotoUrl));
              imageCache.clear();
              imageCache.clearLiveImages();
              print('🔄 [BG-4] Cleared image cache for: $dbPhotoUrl');
            }
          } else {
            print('⚠️ [BG-4] Could not fetch fresh data, using upload result URL');
            setState(() {
              for (int i = 0; i < _all.length; i++) {
                if (_all[i].id == student.id) {
                  for (int j = 0; j < _all[i].subjects.length; j++) {
                    if (_all[i].subjects[j]['id'] == subject['id']) {
                      _all[i].subjects[j]['entry_photo_url'] = photoUrl;
                      _all[i].subjects[j]['entry_photo_at'] = DateTime.now().toIso8601String();
                      break;
                    }
                  }
                  break;
                }
              }
            });
          }
        } catch (e) {
          print('❌ [BG-4] Error fetching fresh data: $e');
          setState(() {
            for (int i = 0; i < _all.length; i++) {
              if (_all[i].id == student.id) {
                for (int j = 0; j < _all[i].subjects.length; j++) {
                  if (_all[i].subjects[j]['id'] == subject['id']) {
                    _all[i].subjects[j]['entry_photo_url'] = photoUrl;
                    _all[i].subjects[j]['entry_photo_at'] = DateTime.now().toIso8601String();
                    break;
                  }
                }
                break;
              }
            }
          });
        }

        // ✅ AUTO-ENABLE next subject
        print('═══════════════════════════════════════════════════════════');
        print('🔄 [BG-5] Auto-enabling next subject...');
        print('═══════════════════════════════════════════════════════════');

        final sorted = _sortSubjectsByExamOrder(student.subjects.cast<Map<String, dynamic>>());
        final currentIndex = sorted.indexWhere((s) => s['subject_name'] == subjectCode);

        if (currentIndex >= 0 && currentIndex < sorted.length - 1) {
          final nextSubject = sorted[currentIndex + 1];
          final nextSubjectId = nextSubject['id']?.toString() ?? '';

          if (nextSubjectId.isNotEmpty) {
            try {
              await supabase
                  .from('exam_students')
                  .update({'is_enabled': true})
                  .eq('id', nextSubjectId);
              print('✅ [BG-5] Next subject auto-enabled: $nextSubjectId');
            } catch (e) {
              print('⚠️ [BG-5] Could not auto-enable next subject: $e');
            }
          }
        } else {
          print('ℹ️ [BG-5] No next subject to enable (current: $currentIndex of ${sorted.length})');
        }
      }

      // ✅ Reload in background (don't await)
      print('═══════════════════════════════════════════════════════════');
      print('📱 [BG-6] Reloading data in 500ms...');
      print('═══════════════════════════════════════════════════════════');
      await Future.delayed(const Duration(milliseconds: 500));
      _load();
      print('✅ [BG-6] Data reload triggered');

    } catch (e) {
      if (!mounted) return;
      print('═══════════════════════════════════════════════════════════');
      print('❌ [BG-ERROR] Background upload error: $e');
      print('═══════════════════════════════════════════════════════════');
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

      // Keep reducing quality until under 1MB
      while (compressed.length > 1048576 && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      }

      // If still over 1MB, resize image
      if (compressed.length > 1048576) {
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
