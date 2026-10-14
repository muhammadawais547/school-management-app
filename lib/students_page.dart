import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'main.dart' show AppColors;
import 'ui_motion.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});

  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  List<Student> _allStudents = [];
  List<Student> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;
  String? _loadError;

  String _selectedClass = 'All';

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await DBHelper.instance.getAllStudents();
      if (!mounted) return;
      setState(() {
        _allStudents = data;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = _allStudents.where((s) {
        // Active students stay in class lists. Archived students have their
        // own lists so issuing a certificate does not clutter active classes.
        final matchesClass = _selectedClass == 'All'
            ? s.studentClass != kCertificateIssuedLabel &&
                  s.studentClass != kGraduatedLabel
            : s.studentClass == _selectedClass;
        final matchesSearch =
            query.isEmpty ||
            s.fullName.toLowerCase().contains(query) ||
            s.fatherName.toLowerCase().contains(query) ||
            s.admissionNo.toLowerCase().contains(query) ||
            s.phone.toLowerCase().contains(query);
        return matchesClass && matchesSearch;
      }).toList();
    });
  }

  Future<void> _showStudentDetails(Student student) async {
    final isArchived =
        student.studentClass == kCertificateIssuedLabel ||
        student.studentClass == kGraduatedLabel;
    var feeHistory = <Map<String, Object?>>[];
    var receiptHistory = <Map<String, Object?>>[];
    var resultHistory = <Map<String, Object?>>[];
    if (isArchived && student.id != null) {
      try {
        feeHistory = await DBHelper.instance.getStudentFeeHistory(student.id!);
        receiptHistory = await DBHelper.instance.getStudentReceiptHistory(
          student.id!,
        );
        resultHistory = await DBHelper.instance.getStudentResultHistory(
          student.id!,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load archived history: $error')),
          );
        }
      }
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          student.fullName,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _studentDetailRow(
                  'Admission Number',
                  student.admissionNo.isEmpty ? '-' : student.admissionNo,
                ),
                _studentDetailRow("Father's Name", student.fatherName),
                _studentDetailRow('Date of Birth', _displayDob(student.dob)),
                _studentDetailRow(
                  'Date of Admission',
                  student.admissionDate.isEmpty
                      ? 'Not recorded'
                      : _displayDob(student.admissionDate),
                ),
                _studentDetailRow('Phone Number', student.phone),
                _studentDetailRow('Address', student.address),
                _studentDetailRow(
                  'Admitted in Class',
                  student.admittedClass.isEmpty
                      ? 'Not recorded (edit this student to add it)'
                      : student.admittedClass,
                ),
                _studentDetailRow(
                  isArchived ? 'School Status' : 'Current Class',
                  student.studentClass,
                ),
                _studentDetailRow(
                  'Monthly Fee',
                  'Rs ${student.monthlyFee.toStringAsFixed(0)}',
                ),
                _studentDetailRow(
                  'Monthly Concession',
                  'Rs ${student.concession.toStringAsFixed(0)}',
                ),
                _studentDetailRow(
                  'Fee After Concession',
                  'Rs ${student.effectiveMonthlyFee.toStringAsFixed(0)}',
                ),
                if (student.openingBalanceRemaining > 0)
                  _studentDetailRow(
                    'Unpaid Opening Balance',
                    'Rs ${student.openingBalanceRemaining.toStringAsFixed(0)}',
                  ),
                if (isArchived) ...[
                  const SizedBox(height: 14),
                  _archiveSectionTitle('Fee history'),
                  if (feeHistory.isEmpty)
                    _archiveEmptyMessage('No generated fee history.')
                  else
                    for (final record in feeHistory) _archiveFeeRow(record),
                  const SizedBox(height: 12),
                  _archiveSectionTitle('Cash receipts'),
                  if (receiptHistory.isEmpty)
                    _archiveEmptyMessage('No cash receipts recorded.')
                  else
                    for (final receipt in receiptHistory)
                      _archiveReceiptRow(receipt),
                  const SizedBox(height: 12),
                  _archiveSectionTitle('Exam results'),
                  if (resultHistory.isEmpty)
                    _archiveEmptyMessage('No saved exam marks.')
                  else
                    for (final result in resultHistory)
                      _archiveResultRow(result),
                  const SizedBox(height: 8),
                  Text(
                    'These are the existing school records. Opening this archive does not create copies or change fee or result data.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          if (!isArchived)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                _showStudentDialog(existing: student);
              },
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit Student'),
            ),
        ],
      ),
    );
  }

  String _displayDob(String value) {
    if (value.isEmpty) return '-';
    try {
      final parts = value.split('-');
      return _formatDob(
        DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2])),
      );
    } catch (_) {
      return value;
    }
  }

  Widget _archiveSectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
        ),
      ),
    ),
  );

  Widget _archiveEmptyMessage(String text) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(text, style: TextStyle(color: Colors.grey.shade600)),
    ),
  );

  Widget _archiveFeeRow(Map<String, Object?> record) {
    final month = record['month'] as String? ?? '-';
    final due = (record['amountDue'] as num?)?.toDouble() ?? 0;
    final paid = (record['amountPaid'] as num?)?.toDouble() ?? 0;
    final concession =
        ((record['concessionSnapshot'] as num?)?.toDouble() ?? 0) +
        ((record['manualAdjustment'] as num?)?.toDouble() ?? 0);
    final generated = ((record['isGenerated'] as num?)?.toInt() ?? 1) != 0;
    final balance = (due - paid).clamp(0, double.infinity).toDouble();
    final status = !generated
        ? 'Not generated'
        : due + ((record['manualAdjustment'] as num?)?.toDouble() ?? 0) <= 0
        ? 'Free'
        : balance <= 0
        ? 'Paid'
        : 'Balance Rs ${balance.toStringAsFixed(0)}';
    return _archiveHistoryLine(
      _displayMonthKey(month),
      'Class ${record['classSnapshot'] ?? '-'} • Fee Rs ${due.toStringAsFixed(0)} • Paid Rs ${paid.toStringAsFixed(0)} • Concession Rs ${concession.toStringAsFixed(0)} • $status',
    );
  }

  Widget _archiveReceiptRow(
    Map<String, Object?> receipt,
  ) => _archiveHistoryLine(
    receipt['date'] as String? ?? '-',
    'Rs ${((receipt['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} received',
  );

  Widget _archiveResultRow(Map<String, Object?> result) => _archiveHistoryLine(
    '${result['examName'] ?? 'Exam'} • ${result['className'] ?? 'Class'}',
    '${result['subjectName'] ?? 'Subject'}: ${((result['obtainedMarks'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)} / ${((result['totalMarks'] as num?)?.toDouble() ?? 0).toStringAsFixed(1)}',
  );

  Widget _archiveHistoryLine(String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          style: const TextStyle(fontSize: 12, color: AppColors.textDark),
          children: [
            TextSpan(
              text: '$title  ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: detail),
          ],
        ),
      ),
    ),
  );

  String _displayMonthKey(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return value;
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[0]);
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (month == null || year == null || month < 1 || month > 12) return value;
    return '${monthNames[month - 1]} $year';
  }

  Future<void> _deleteStudent(Student s) async {
    try {
      final deletedCount = await DBHelper.instance.deleteStudent(s.id!);
      if (!mounted) return;
      if (deletedCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This student record was not found.')),
        );
        await _loadStudents();
        return;
      }
      await _loadStudents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${s.fullName} and related records were deleted.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete ${s.fullName}: $e'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteStudent(Student s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Student?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to delete "${s.fullName}"? This will permanently remove the student, fee payment history, marks, and issued certificate records. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await _deleteStudent(s);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _countForClass(String cls) {
    if (cls == 'All') {
      return _allStudents
          .where(
            (student) =>
                student.studentClass != kCertificateIssuedLabel &&
                student.studentClass != kGraduatedLabel,
          )
          .length;
    }
    return _allStudents.where((s) => s.studentClass == cls).length;
  }

  // Shared dialog for both Add and Edit. If [existing] is provided, the
  // form is pre-filled and Save updates that student instead of creating one.
  Future<void> _showStudentDialog({Student? existing}) async {
    final isEditing = existing != null;
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final admissionNoCtrl = TextEditingController(
      text: existing?.admissionNo ?? '',
    );
    final fatherCtrl = TextEditingController(text: existing?.fatherName ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final feeAmountCtrl = TextEditingController(
      text: existing != null ? existing.monthlyFee.toStringAsFixed(0) : '',
    );
    final concessionCtrl = TextEditingController(
      text: existing != null ? existing.concession.toStringAsFixed(0) : '0',
    );
    final openingBalanceCtrl = TextEditingController(
      text: existing != null ? existing.openingBalance.toStringAsFixed(0) : '0',
    );

    DateTime? selectedDob;
    if (existing != null && existing.dob.isNotEmpty) {
      try {
        final parts = existing.dob.split('-');
        selectedDob = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      } catch (_) {}
    }
    DateTime? selectedAdmissionDate;
    if (existing != null && existing.admissionDate.isNotEmpty) {
      try {
        final parts = existing.admissionDate.split('-');
        selectedAdmissionDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      } catch (_) {}
    }
    String? dobError;
    String? admissionDateError;
    var isSaving = false;
    String selectedClass =
        existing?.studentClass ??
        (kClassList.contains(_selectedClass)
            ? _selectedClass
            : kClassList.first);
    String? selectedAdmittedClass = isEditing
        ? (existing.admittedClass.isEmpty ? null : existing.admittedClass)
        : selectedClass;
    var admissionClassWasEdited = isEditing && selectedAdmittedClass != null;
    final classOptions = [
      ...kClassList,
      if (!kClassList.contains(selectedClass)) selectedClass,
    ];

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return PopScope(
                canPop: !isSaving,
                child: AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                    isEditing ? 'Edit Student' : 'Add New Student',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  content: AbsorbPointer(
                    absorbing: isSaving,
                    child: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _field(
                                nameCtrl,
                                'Full Name',
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Full name is required';
                                  }
                                  if (val.trim().length < 3) {
                                    return 'Enter the full name (min 3 letters)';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                admissionNoCtrl,
                                'Admission Number',
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Admission number is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                fatherCtrl,
                                "Father's Name",
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return "Father's name is required";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              // Date of birth picker
                              InkWell(
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        selectedDob ?? DateTime(2015, 1, 1),
                                    firstDate: DateTime(1995, 1, 1),
                                    lastDate: DateTime.now(),
                                    helpText: 'Select Date of Birth',
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedDob = picked;
                                      dobError = null;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Date of Birth',
                                    filled: true,
                                    fillColor: const Color(0xFFF5F7FA),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorText: dobError,
                                    suffixIcon: const Icon(
                                      Icons.calendar_today,
                                      size: 18,
                                    ),
                                  ),
                                  child: Text(
                                    selectedDob == null
                                        ? 'Select date'
                                        : _formatDob(selectedDob!),
                                    style: TextStyle(
                                      color: selectedDob == null
                                          ? Colors.grey.shade500
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Phone — no strict format, since international numbers are used too
                              _field(
                                phoneCtrl,
                                'Phone Number',
                                keyboardType: TextInputType.phone,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Phone number is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                addressCtrl,
                                'Address',
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Address is required';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: selectedAdmittedClass,
                                decoration: InputDecoration(
                                  labelText: 'Admitted in Class',
                                  helperText:
                                      "The student's original class when first admitted to this school. Promotion will not change it.",
                                  helperMaxLines: 2,
                                  filled: true,
                                  fillColor: const Color(0xFFF5F7FA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: kClassList
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  setDialogState(() {
                                    selectedAdmittedClass = val;
                                    admissionClassWasEdited = val != null;
                                  });
                                },
                                hint: const Text('Select original class'),
                                validator: (value) => value == null
                                    ? 'Select the class the student was admitted in'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              // Store the original admission date so it can
                              // be printed accurately on a leaving certificate.
                              InkWell(
                                onTap: () async {
                                  final today = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: selectedAdmissionDate ?? today,
                                    firstDate: DateTime(1990, 1, 1),
                                    lastDate: today,
                                    helpText: 'Select Date of Admission',
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      selectedAdmissionDate = picked;
                                      admissionDateError = null;
                                    });
                                  }
                                },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Date of Admission',
                                    helperText:
                                        'This original date stays the same when the student is promoted.',
                                    helperMaxLines: 2,
                                    filled: true,
                                    fillColor: const Color(0xFFF5F7FA),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                    errorText: admissionDateError,
                                    suffixIcon: const Icon(
                                      Icons.calendar_today,
                                      size: 18,
                                    ),
                                  ),
                                  child: Text(
                                    selectedAdmissionDate == null
                                        ? 'Select date'
                                        : _formatDob(selectedAdmissionDate!),
                                    style: TextStyle(
                                      color: selectedAdmissionDate == null
                                          ? Colors.grey.shade500
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String>(
                                initialValue: selectedClass,
                                decoration: InputDecoration(
                                  labelText: 'Current Class',
                                  filled: true,
                                  fillColor: const Color(0xFFF5F7FA),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                items: classOptions
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() {
                                      selectedClass = val;
                                      if (!isEditing &&
                                          !admissionClassWasEdited) {
                                        selectedAdmittedClass = val;
                                      }
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                feeAmountCtrl,
                                'Monthly Fee (Rs)',
                                isNumber: true,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Monthly fee is required';
                                  }
                                  if (double.tryParse(val.trim()) == null) {
                                    return 'Enter a valid number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                concessionCtrl,
                                'Concession (Rs) — leave 0 if none',
                                isNumber: true,
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Enter 0 if there is no concession';
                                  }
                                  if (double.tryParse(val.trim()) == null) {
                                    return 'Enter a valid number';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                openingBalanceCtrl,
                                'Previous / Opening Balance (Rs) — leave 0 if none',
                                isNumber: true,
                                helperText:
                                    'Use this once, when first entering a student who already owed fees before using this software.',
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Enter 0 if there is no previous balance';
                                  }
                                  if (double.tryParse(val.trim()) == null) {
                                    return 'Enter a valid number';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final formValid =
                                  formKey.currentState?.validate() ?? false;
                              final dobValid = selectedDob != null;
                              final admissionDateValid =
                                  selectedAdmissionDate != null;
                              if (!dobValid) {
                                setDialogState(
                                  () => dobError = 'Date of birth is required',
                                );
                              }
                              if (!admissionDateValid) {
                                setDialogState(
                                  () => admissionDateError =
                                      'Date of admission is required',
                                );
                              }
                              if (!formValid ||
                                  !dobValid ||
                                  !admissionDateValid) {
                                return;
                              }

                              setDialogState(() => isSaving = true);
                              final admissionNo = admissionNoCtrl.text.trim();
                              try {
                                final taken = await DBHelper.instance
                                    .isAdmissionNoTaken(
                                      admissionNo,
                                      excludeId: existing?.id,
                                    );
                                if (taken) {
                                  if (context.mounted) {
                                    setDialogState(() => isSaving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Admission number "$admissionNo" is already assigned to another student.',
                                        ),
                                        backgroundColor: AppColors.red,
                                      ),
                                    );
                                  }
                                  return;
                                }

                                final student = Student(
                                  id: existing?.id,
                                  fullName: nameCtrl.text.trim(),
                                  fatherName: fatherCtrl.text.trim(),
                                  dob: _isoDob(selectedDob!),
                                  phone: phoneCtrl.text.trim(),
                                  address: addressCtrl.text.trim(),
                                  studentClass: selectedClass,
                                  admittedClass:
                                      selectedAdmittedClass ??
                                      existing?.admittedClass ??
                                      '',
                                  admissionDate: _isoDob(
                                    selectedAdmissionDate!,
                                  ),
                                  admissionNo: admissionNo,
                                  monthlyFee:
                                      double.tryParse(
                                        feeAmountCtrl.text.trim(),
                                      ) ??
                                      0,
                                  concession:
                                      double.tryParse(
                                        concessionCtrl.text.trim(),
                                      ) ??
                                      0,
                                  openingBalance:
                                      double.tryParse(
                                        openingBalanceCtrl.text.trim(),
                                      ) ??
                                      0,
                                );

                                if (isEditing) {
                                  await DBHelper.instance.updateStudent(
                                    student,
                                  );
                                } else {
                                  await DBHelper.instance.addStudent(student);
                                }
                                if (context.mounted) Navigator.pop(context);
                                if (!mounted) return;
                                setState(
                                  () => _selectedClass =
                                      kClassList.contains(selectedClass)
                                      ? selectedClass
                                      : 'All',
                                );
                                await _loadStudents();
                              } catch (e) {
                                if (!context.mounted) return;
                                setDialogState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing
                                          ? 'Could not save student changes: $e'
                                          : 'Could not add student: $e',
                                    ),
                                    backgroundColor: AppColors.red,
                                  ),
                                );
                              }
                            },
                      child: Text(
                        isSaving
                            ? 'Saving...'
                            : isEditing
                            ? 'Save Changes'
                            : 'Add Student',
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      nameCtrl.dispose();
      admissionNoCtrl.dispose();
      fatherCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      feeAmountCtrl.dispose();
      concessionCtrl.dispose();
      openingBalanceCtrl.dispose();
    }
  }

  // Internal storage format: 'YYYY-MM-DD' (sortable)
  String _isoDob(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // Display format: '12 Jan 2015' (professional, human-readable)
  String _formatDob(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool isNumber = false,
    TextInputType? keyboardType,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType:
          keyboardType ??
          (isNumber ? TextInputType.number : TextInputType.text),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 2,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _studentDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Students',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showStudentDialog(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Student'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ClassChip(
                  label: 'All',
                  count: _countForClass('All'),
                  selected: _selectedClass == 'All',
                  onTap: () {
                    setState(() => _selectedClass = 'All');
                    _applyFilters();
                  },
                ),
                for (final c in kClassList)
                  _ClassChip(
                    label: c,
                    count: _countForClass(c),
                    selected: _selectedClass == c,
                    onTap: () {
                      setState(() => _selectedClass = c);
                      _applyFilters();
                    },
                  ),
                _ClassChip(
                  label: kCertificateIssuedLabel,
                  count: _countForClass(kCertificateIssuedLabel),
                  selected: _selectedClass == kCertificateIssuedLabel,
                  onTap: () {
                    setState(() => _selectedClass = kCertificateIssuedLabel);
                    _applyFilters();
                  },
                ),
                _ClassChip(
                  label: kGraduatedLabel,
                  count: _countForClass(kGraduatedLabel),
                  selected: _selectedClass == kGraduatedLabel,
                  onTap: () {
                    setState(() => _selectedClass = kGraduatedLabel);
                    _applyFilters();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _searchController,
            onChanged: (value) {
              _applyFilters();
            },
            decoration: InputDecoration(
              hintText:
                  'Search this list by student name or admission number...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load students.'),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
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
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      _allStudents.isEmpty
                          ? 'No students yet. Click "Add Student" to begin.'
                          : _selectedClass == 'All'
                          ? 'No active students found. Check the Left School or Graduated list for archived records.'
                          : 'No students found for this class/search.',
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
                        final s = _filtered[index];
                        final isArchived =
                            s.studentClass == kCertificateIssuedLabel ||
                            s.studentClass == kGraduatedLabel;
                        return ListTile(
                          onTap: () => _showStudentDetails(s),
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
                          // Highlighted name — colored badge background instead of plain text
                          title: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Container(
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
                                  fontSize: 14.5,
                                  color: AppColors.tealDark,
                                ),
                              ),
                            ),
                          ),
                          subtitle: Text(
                            "Adm# ${s.admissionNo.isEmpty ? '-' : s.admissionNo}  •  Father: ${s.fatherName}  •  DOB: ${s.dob.isEmpty ? '-' : s.dob}  •  ${s.phone}",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (s.concession > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (s.effectiveMonthlyFee == 0
                                                  ? Colors.grey.shade600
                                                  : AppColors.amber)
                                              .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      s.effectiveMonthlyFee == 0
                                          ? 'Free'
                                          : 'Concession: Rs ${s.concession.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        color: s.effectiveMonthlyFee == 0
                                            ? Colors.grey.shade600
                                            : AppColors.amber,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              if (s.openingBalanceRemaining > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.red.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Previous Due: Rs ${s.openingBalanceRemaining.toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        color: AppColors.red,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.teal.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  s.studentClass,
                                  style: const TextStyle(
                                    color: AppColors.tealDark,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'View full student details',
                                icon: const Icon(
                                  Icons.info_outline,
                                  color: AppColors.tealDark,
                                ),
                                onPressed: () => _showStudentDetails(s),
                              ),
                              if (!isArchived) ...[
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    color: AppColors.navyLight,
                                  ),
                                  onPressed: () =>
                                      _showStudentDialog(existing: s),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.red,
                                  ),
                                  onPressed: () => _confirmDeleteStudent(s),
                                ),
                              ],
                            ],
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

class _ClassChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _ClassChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverMotion(
      hoverScale: 1.025,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Material(
          color: selected ? AppColors.teal : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppColors.teal : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withOpacity(0.25)
                            : AppColors.teal.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : AppColors.tealDark,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
