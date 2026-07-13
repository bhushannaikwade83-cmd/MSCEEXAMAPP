import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_ui.dart';
import '../../core/supabase_client.dart';
import '../../services/msce_student_service.dart';
import '../../services/session_service.dart';
import 'web_center_login_screen.dart';
import 'web_student_subjects_screen.dart';
import 'web_qr_camera_scanner_screen.dart';
import 'web_camera_dialog.dart';
import '../services/web_storage_service.dart';

enum _Filter { all, present, absent }

class WebHomeScreen extends StatefulWidget {
  const WebHomeScreen({super.key});

  @override
  State<WebHomeScreen> createState() => _WebHomeScreenState();
}

class _WebHomeScreenState extends State<WebHomeScreen> {
  final _students = MsceStudentService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _clockTimer;

  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _visible = [];
  List<String> _allBatches = [];
  List<String> _allSubjects = [];

  String? _centerName;
  String? _centerCode;
  String _currentTime = '';
  bool _loading = true;
  String? _error;

  int _currentPage = 1;
  final int _itemsPerPage = 20;

  String? _selectedBatch;
  String? _selectedSubject;
  _Filter _filter = _Filter.all;

  int get _present =>
      _visible.where((s) => s['entry_marked'] == true).length;
  int get _absent =>
      _visible.where((s) => s['entry_marked'] != true).length;

  int get _totalPages => (_visible.length / _itemsPerPage).ceil();
  List<Map<String, dynamic>> get _paginatedStudents {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end = start + _itemsPerPage;
    return _visible.sublist(
      start,
      end > _visible.length ? _visible.length : end,
    );
  }

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
    final valid = await SessionService.isSessionValid();
    if (!valid) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      );
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
        MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      );
      return;
    }

    try {
      final msceStudents = await _students.loadFromExamStudentsTable(
        centerId: center['id']!,
        centerCode: center['code'],
        search: _searchCtrl.text,
      );

      if (!mounted) return;

      // Convert MsceStudent objects to Map<String, dynamic>
      final studentsList = msceStudents.map((student) {
        return {
          'id': student.id,
          'name': student.name,
          'sr_no': student.srNo,
          'seat_no': student.srNo,
          'photo_url': student.photoUrl,
          'entry_marked': student.entryMarked,
          'entry_photo_url': student.entryPhotoUrl,
          'entry_photo_at': student.entryMarkedAt,
          'subjects': student.subjects,
        };
      }).toList();

      final batches = <String>{};
      for (final row in studentsList) {
        final subjects = row['subjects'] as List?;
        if (subjects != null) {
          for (final subject in subjects) {
            batches.add(subject['batch']?.toString() ?? '');
          }
        }
      }

      final subjects = <String>{};
      for (final row in studentsList) {
        final subjectsList = row['subjects'] as List?;
        if (subjectsList != null) {
          for (final subject in subjectsList) {
            final subjectName = subject['subject_name']?.toString() ??
                subject['subject_code']?.toString() ??
                '';
            if (subjectName.isNotEmpty) {
              subjects.add(subjectName);
            }
          }
        }
      }

      setState(() {
        _centerName = center['name'];
        _centerCode = center['code'];
        _all = studentsList;
        _allBatches = batches.toList()..sort();
        _allSubjects = subjects.toList()..sort();
        _currentPage = 1;
        _loading = false;
        _filter = _Filter.all;
        _applyFilters();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error loading students: $e';
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    _visible = _all.where((student) {
      // Filter by attendance
      final entryMarked = student['entry_marked'] == true;
      if (_filter == _Filter.present && !entryMarked) return false;
      if (_filter == _Filter.absent && entryMarked) return false;

      // Filter by batch
      if (_selectedBatch != null) {
        final subjects = student['subjects'] as List?;
        final hasBatch = subjects?.any((s) =>
                s['batch']?.toString() == _selectedBatch) ??
            false;
        if (!hasBatch) return false;
      }

      // Filter by subject
      if (_selectedSubject != null) {
        final subjects = student['subjects'] as List?;
        final hasSubject = subjects?.any((s) =>
                s['subject_name']?.toString() == _selectedSubject) ??
            false;
        if (!hasSubject) return false;
      }

      // Filter by search
      final searchTerm = _searchCtrl.text.toLowerCase();
      if (searchTerm.isNotEmpty) {
        final name = student['name']?.toString().toLowerCase() ?? '';
        final seatNo = student['seat_no']?.toString().toLowerCase() ?? '';
        final srNo = student['sr_no']?.toString().toLowerCase() ?? '';
        if (!name.contains(searchTerm) &&
            !seatNo.contains(searchTerm) &&
            !srNo.contains(searchTerm)) {
          return false;
        }
      }

      return true;
    }).toList();

    if (_currentPage > _totalPages && _totalPages > 0) {
      _currentPage = _totalPages;
    }
  }

  Future<void> _logout() async {
    await SessionService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WebCenterLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      floatingActionButton: FloatingActionButton(
        onPressed: _showQrScannerDialog,
        backgroundColor: AppTheme.primaryBlue,
        tooltip: 'Scan QR / Search Seat',
        child: const Icon(Icons.qr_code_2, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                _buildHeader(),
                // Status filters
                _buildStatusFilters(),
                // Batch + Subject filters
                _buildAdvancedFilters(),
                // Search
                _buildSearch(),
                // Student list
                Expanded(child: _buildBody()),
                // Pagination
                if (_totalPages > 1) _buildPaginationBar(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppTheme.primaryBlueDark,
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top: Logo + Centre Info + Logout
          Row(
            children: [
              Container(
                height: 36.h,
                width: 36.w,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/msce_attendance_app_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
          // Welcome + Clock
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

  Widget _buildAdvancedFilters() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final horizontalPad = isMobile ? 8.w : 10.w;
    final verticalPad = isMobile ? 4.h : 6.h;
    final innerHPad = isMobile ? 6.w : 8.w;
    final innerVPad = isMobile ? 4.h : 5.h;
    final gap = isMobile ? 4.w : 6.w;
    final borderRad = isMobile ? 4.r : 5.r;
    final fontSize = isMobile ? 8.5.sp : 9.sp;

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPad, verticalPad, horizontalPad, verticalPad),
      child: Row(
        children: [
          if (_allBatches.isNotEmpty)
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedBatch,
                hint: Text('Batches', style: TextStyle(fontSize: fontSize)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Batches')),
                  ..._allBatches.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                ],
                onChanged: (val) => setState(() {
                  _selectedBatch = val;
                  _currentPage = 1;
                  _applyFilters();
                }),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRad)),
                  contentPadding: EdgeInsets.symmetric(horizontal: innerHPad, vertical: innerVPad),
                  isDense: true,
                ),
              ),
            ),
          SizedBox(width: gap),
          if (_allSubjects.isNotEmpty)
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _selectedSubject,
                hint: Text('Subjects', style: TextStyle(fontSize: fontSize)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Subjects')),
                  ..._allSubjects.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (val) => setState(() {
                  _selectedSubject = val;
                  _currentPage = 1;
                  _applyFilters();
                }),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(borderRad)),
                  contentPadding: EdgeInsets.symmetric(horizontal: innerHPad, vertical: innerVPad),
                  isDense: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Search by name, SR no…',
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

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _all.isEmpty ? 'No students found for this centre.' : 'No matched students.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
        itemCount: _paginatedStudents.length,
        itemBuilder: (_, i) => _studentCard(_paginatedStudents[i]),
      ),
    );
  }

  Widget _studentCard(Map<String, dynamic> student) {
    final name = student['name'] ?? '—';
    final srNo = student['sr_no'] ?? '—';
    final photoUrl = student['photo_url'] ?? '';
    final entryPhotoUrl = student['entry_photo_url'] ?? '';
    final isMarked = student['entry_marked'] == true;
    final subjects = student['subjects'] as List? ?? [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Photo + Name + SR NO
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Thumbnail photo (110x150)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 110.w,
                      height: 150.h,
                      color: Colors.grey[300],
                      child: photoUrl.isNotEmpty
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(Icons.person, size: 40),
                            )
                          : Icon(Icons.person, size: 40),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // Right: Name + SR NO
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'SR NO: $srNo',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.sp,
                            color: Colors.grey[600],
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
              // Subjects list
              ...subjects.map((subject) {
                final subjectName = subject['subject_name']?.toString() ??
                    subject['subject_code']?.toString() ??
                    '—';
                final seatNo = subject['seat_no']?.toString() ?? '—';
                final batch = subject['batch']?.toString() ?? '—';
                final subjectMarked = subject['entry_photo_url'] != null &&
                    subject['entry_photo_url'].toString().isNotEmpty;
                final subjectEntryPhotoUrl = subject['entry_photo_url'] ?? '';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject name
                    Text(
                      subjectName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    // SEAT, SR NO, BATCH
                    Row(
                      children: [
                        Icon(Icons.event_seat, size: 14, color: AppTheme.textGray),
                        SizedBox(width: 4.w),
                        Text('SEAT: $seatNo',
                            style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                        SizedBox(width: 12.w),
                        Icon(Icons.assignment, size: 14, color: AppTheme.textGray),
                        SizedBox(width: 4.w),
                        Text('SR: $srNo',
                            style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(Icons.groups, size: 14, color: AppTheme.textGray),
                        SizedBox(width: 4.w),
                        Text('BATCH: $batch',
                            style: TextStyle(fontSize: 11.sp, color: AppTheme.textGray)),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    // Entry photo (if marked)
                    if (subjectMarked && subjectEntryPhotoUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          height: 300.h,
                          color: Colors.grey[300],
                          child: Image.network(
                            subjectEntryPhotoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                Icon(Icons.camera_alt, size: 40),
                          ),
                        ),
                      ),
                    if (subjectMarked) SizedBox(height: 8.h),
                    // Entry Button (if NOT marked)
                    if (!subjectMarked)
                      SizedBox(
                        width: double.infinity,
                        height: 44.h,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            _onMarkEntryWeb(
                              student: student,
                              subject: subject,
                              subjectName: subjectName,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: Text(
                            'Mark Entry',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    SizedBox(height: subjectMarked ? 8.h : 12.h),
                    if (subjects.indexOf(subject) < subjects.length - 1) ...[
                      Divider(height: 12, color: AppTheme.dividerColor),
                      SizedBox(height: 8.h),
                    ],
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationBar() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton.icon(
            onPressed: _currentPage > 1
                ? () => setState(() => _currentPage--)
                : null,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Previous'),
          ),
          Text(
            'Page $_currentPage of $_totalPages',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.sp),
          ),
          ElevatedButton.icon(
            onPressed: _currentPage < _totalPages
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(_Filter f, String label) {
    final selected = _filter == f;
    return ChoiceChip(
      label: Text(label.toUpperCase()),
      selected: selected,
      onSelected: (_) => setState(() {
        _filter = f;
        _currentPage = 1;
        _applyFilters();
      }),
      selectedColor: AppTheme.primaryBlue,
      backgroundColor: AppTheme.backgroundGrey,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.primaryBlue,
        fontWeight: FontWeight.w800,
        fontSize: 13.sp,
      ),
    );
  }

  // Convert Map back to MsceStudent object
  _convertMapToMsceStudent(Map<String, dynamic> map) {
    return _students.convertMapToMsceStudent(map);
  }

  // Handle entry marking from home screen - open camera directly
  Future<void> _onMarkEntryWeb({
    required Map<String, dynamic> student,
    required Map<String, dynamic> subject,
    required String subjectName,
  }) async {
    final examStudentId = subject['id']?.toString() ?? '';
    final seatNo = subject['seat_no']?.toString() ?? '';
    final studentName = student['name'] ?? 'Unknown';

    if (examStudentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subject info missing'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get centre code
    final center = await SessionService.getCenter();
    final centreCode = center?['code']?.toString() ?? '';

    if (centreCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Centre not configured'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Open camera dialog directly
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => WebCameraDialog(
        studentName: studentName,
        subjectName: subjectName,
        onPhotoCapture: (photoBytes) async {
          // Upload captured photo directly
          try {
            // Upload via API
            final uploadResult = await WebStorageService.uploadEntryPhotoWeb(
              centreCode: centreCode,
              folderYear: DateTime.now().year.toString(),
              seatNo: seatNo,
              subject: subjectName,
              date: DateTime.now().toIso8601String().split('T').first,
              photoBytes: photoBytes,
            );

            final photoUrl = uploadResult['url'] ?? '';
            if (photoUrl.isEmpty) {
              throw Exception('No URL returned from upload');
            }

            // Update database
            await supabase.from('exam_students').update({
              'entry_photo_url': photoUrl,
              'entry_at': DateTime.now().toIso8601String(),
              'entry_photo_at': DateTime.now().toIso8601String(),
              'is_enabled': true,
            }).eq('id', examStudentId);

            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Entry marked for $subjectName'),
                backgroundColor: AppTheme.primaryGreen,
                duration: const Duration(seconds: 2),
              ),
            );

            // Refresh home screen
            _load();
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Upload failed: $e'),
                backgroundColor: AppTheme.accentRed,
              ),
            );
          }
        },
      ),
    );
  }

  // Show QR scanner (camera scan → student details → mark entry)
  void _showQrScannerDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WebQrCameraScannerScreen(),
      ),
    ).then((_) {
      _load();
    });
  }
}
