import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import 'db_helper.dart';
import 'certificate_pdf.dart';
import 'main.dart' show AppColors;

class CertificatePage extends StatefulWidget {
  const CertificatePage({super.key});

  @override
  State<CertificatePage> createState() => _CertificatePageState();
}

class _CertificatePageState extends State<CertificatePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leaving Certificates',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: AppColors.teal,
            unselectedLabelColor: AppColors.textGrey,
            indicatorColor: AppColors.teal,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Issue Certificate'),
              Tab(text: 'Certificate History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                const _IssueTab(),
                _HistoryTab(tabController: _tabController),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ISSUE TAB
// =====================================================================

class _IssueTab extends StatefulWidget {
  const _IssueTab();

  @override
  State<_IssueTab> createState() => _IssueTabState();
}

class _IssueTabState extends State<_IssueTab> {
  String _selectedClass = kClassList.first;
  List<Student> _students = [];
  bool _loading = true;
  bool _issuingCertificate = false;
  String? _studentsLoadError;
  int _studentsLoadVersion = 0;
  Uint8List? _logoBytes;
  String? _schoolName;
  String? _schoolTagline;

  @override
  void initState() {
    super.initState();
    _loadLogo();
    _loadSchoolInfo();
    _loadStudents();
  }

  Future<void> _loadLogo() async {
    try {
      final schoolLogo = await DBHelper.instance.getSchoolLogoBytes();
      if (schoolLogo != null) {
        if (mounted) setState(() => _logoBytes = schoolLogo);
        return;
      }
      final data = await rootBundle.load('assets/logo.jpg');
      if (mounted) setState(() => _logoBytes = data.buffer.asUint8List());
    } catch (_) {
      // No logo asset yet.
    }
  }

  Future<void> _loadSchoolInfo() async {
    try {
      final info = await DBHelper.instance.getSchoolInfo();
      if (!mounted) return;
      setState(() {
        _schoolName = info['name'];
        _schoolTagline = info['tagline'];
      });
    } catch (_) {
      // Falls back to the built-in default.
    }
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    final loadVersion = ++_studentsLoadVersion;
    final selectedClass = _selectedClass;
    setState(() {
      _loading = true;
      _studentsLoadError = null;
    });
    try {
      final students = await DBHelper.instance.getStudentsByClass(
        selectedClass,
      );
      if (!mounted || loadVersion != _studentsLoadVersion) return;
      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || loadVersion != _studentsLoadVersion) return;
      setState(() {
        _loading = false;
        _studentsLoadError = '$e';
      });
    }
  }

  Future<void> _confirmIssue(Student student) async {
    final isBonafide = student.studentClass == kClassList.first;
    if (!isBonafide &&
        (student.admittedClass.isEmpty || student.admissionDate.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add the student’s original admitted class and admission date in the student form before issuing a leaving certificate.',
          ),
        ),
      );
      return;
    }
    final admittedClass = student.admittedClass.isEmpty
        ? 'not recorded'
        : student.admittedClass;
    final lastPassedClass =
        DBHelper.instance.getPreviousClass(student.studentClass) ??
        'not recorded';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isBonafide
              ? 'Issue Bonafide Certificate?'
              : 'Issue Leaving Certificate?',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          isBonafide
              ? 'This will issue a Bonafide Certificate for "${student.fullName}". They were admitted in $admittedClass and are currently studying in ${student.studentClass}. The student stays active and their record is unchanged.'
              : 'This will issue a Leaving Certificate for "${student.fullName}". They were admitted in $admittedClass, last passed $lastPassedClass, and are currently in ${student.studentClass}.\n\n'
                    'The student will be archived from active class lists. Their fee and academic history will remain saved. This action cannot be undone here.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Issue Certificate'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true || _issuingCertificate) return;
    setState(() => _issuingCertificate = true);
    try {
      late final Certificate certificate;
      try {
        certificate = await DBHelper.instance.issueCertificate(student);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the certificate record: $e'),
            backgroundColor: AppColors.red,
          ),
        );
        return;
      }

      if (!mounted) return;
      await _loadStudents();

      try {
        final bytes = await generateCertificatePdf(
          certificate,
          logoBytes: _logoBytes,
          schoolName: _schoolName,
          schoolTagline: _schoolTagline,
        );
        await Printing.layoutPdf(
          onLayout: (format) async => bytes,
          name: 'Certificate_${student.fullName}.pdf',
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The certificate is saved in Certificate History, but its PDF could not be generated or opened for printing. You can reprint it from History. Details: $e',
            ),
            backgroundColor: AppColors.red,
            duration: const Duration(seconds: 7),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _issuingCertificate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select a class, then issue a certificate for a student. A leaving certificate records their current enrolled class.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in kClassList)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Material(
                      color: _selectedClass == c
                          ? AppColors.teal
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          setState(() => _selectedClass = c);
                          _loadStudents();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _selectedClass == c
                                  ? AppColors.teal
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: _selectedClass == c
                                  ? Colors.white
                                  : AppColors.textDark,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _studentsLoadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load students for certificates.'),
                        const SizedBox(height: 8),
                        Text(
                          _studentsLoadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadStudents,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _students.isEmpty
                ? Center(
                    child: Text(
                      'No students in $_selectedClass.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = _students[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.teal.withOpacity(0.12),
                            child: Text(
                              s.fullName.isNotEmpty ? s.fullName[0] : '?',
                              style: const TextStyle(
                                color: AppColors.tealDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.teal.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              s.fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.tealDark,
                              ),
                            ),
                          ),
                          subtitle: Text(
                            "Father: ${s.fatherName}  •  Adm# ${s.admissionNo.isEmpty ? '-' : s.admissionNo}",
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: _issuingCertificate
                                ? null
                                : () => _confirmIssue(s),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.navy,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(
                              Icons.workspace_premium_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _issuingCertificate
                                  ? 'Processing...'
                                  : 'Issue Certificate',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// HISTORY TAB
// =====================================================================

class _HistoryTab extends StatefulWidget {
  final TabController tabController;

  const _HistoryTab({required this.tabController});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<Certificate> _certificates = [];
  bool _loading = true;
  Uint8List? _logoBytes;
  String? _schoolName;
  String? _schoolTagline;
  final TextEditingController _searchController = TextEditingController();
  List<Certificate> _filtered = [];
  String? _loadError;
  int _loadVersion = 0;
  late int _lastTabIndex;

  @override
  void initState() {
    super.initState();
    _lastTabIndex = widget.tabController.index;
    widget.tabController.addListener(_handleTabChange);
    _loadLogo();
    _loadSchoolInfo();
    _loadCertificates();
  }

  void _handleTabChange() {
    final currentIndex = widget.tabController.index;
    if (currentIndex == _lastTabIndex) return;
    _lastTabIndex = currentIndex;
    if (currentIndex == 1) _loadCertificates();
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_handleTabChange);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLogo() async {
    try {
      final schoolLogo = await DBHelper.instance.getSchoolLogoBytes();
      if (schoolLogo != null) {
        if (mounted) setState(() => _logoBytes = schoolLogo);
        return;
      }
      final data = await rootBundle.load('assets/logo.jpg');
      if (mounted) setState(() => _logoBytes = data.buffer.asUint8List());
    } catch (_) {}
  }

  Future<void> _loadSchoolInfo() async {
    try {
      final info = await DBHelper.instance.getSchoolInfo();
      if (!mounted) return;
      setState(() {
        _schoolName = info['name'];
        _schoolTagline = info['tagline'];
      });
    } catch (_) {}
  }

  Future<void> _loadCertificates() async {
    if (!mounted) return;
    final loadVersion = ++_loadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final certs = await DBHelper.instance.getAllCertificates();
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _certificates = certs;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _certificates.where((c) {
        return query.isEmpty ||
            c.studentName.toLowerCase().contains(query) ||
            c.admissionNo.toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _reprint(Certificate certificate) async {
    try {
      final bytes = await generateCertificatePdf(
        certificate,
        logoBytes: _logoBytes,
        schoolName: _schoolName,
        schoolTagline: _schoolTagline,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'Certificate_${certificate.studentName}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not reprint: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (_) => _applyFilter(),
            decoration: InputDecoration(
              hintText: 'Search by student name or admission number...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load certificate history.'),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadCertificates,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      _certificates.isEmpty
                          ? 'No certificates issued yet.'
                          : 'No matches found.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = _filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navyLight.withOpacity(
                              0.12,
                            ),
                            child: const Icon(
                              Icons.workspace_premium_rounded,
                              color: AppColors.navyLight,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            c.studentName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${c.certificateNumber} | Admitted: ${c.admittedClass.isEmpty ? 'not recorded' : c.admittedClass} | Passed: ${c.lastPassedClass.isEmpty ? 'not recorded' : c.lastPassedClass} | Class at issue: ${c.classPassed} | Issued ${c.issueDate}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: OutlinedButton.icon(
                            onPressed: () => _reprint(c),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.navy,
                              side: const BorderSide(color: AppColors.navy),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.print_rounded, size: 16),
                            label: const Text(
                              'Reprint',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
