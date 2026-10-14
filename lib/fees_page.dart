import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:file_selector/file_selector.dart';
import 'class_fee_ledger_pdf.dart';
import 'db_helper.dart';
import 'fee_slip_pdf.dart';
import 'main.dart' show AppColors;
import 'ui_motion.dart';

class FeesPage extends StatefulWidget {
  const FeesPage({super.key});

  @override
  State<FeesPage> createState() => _FeesPageState();
}

// Combines a Student with their computed fee numbers for the selected month
class _FeeRow {
  final Student student;
  final List<FeeRecord?> records; // one fee row per month in the billing cycle
  final double previousBalance;

  _FeeRow({
    required this.student,
    required this.records,
    required this.previousBalance,
  });

  bool get isGenerated =>
      records.isNotEmpty &&
      records.every((record) => record?.isGenerated ?? false);
  bool get hasAllRecords =>
      records.isNotEmpty && records.every((record) => record != null);
  double get thisMonthDue =>
      records.fold<double>(0, (sum, record) => sum + (record?.amountDue ?? 0));
  double get thisMonthExpected => records.fold<double>(0, (sum, record) {
    if (record == null || !record.isGenerated) return sum;
    return sum + record.amountDue + record.manualAdjustment;
  });
  double get thisMonthPaid =>
      records.fold<double>(0, (sum, record) => sum + (record?.amountPaid ?? 0));
  double get thisMonthBalance => records.fold<double>(0, (sum, record) {
    if (record == null || !record.isGenerated) return sum;
    final due = record.amountDue;
    final paid = record.amountPaid;
    return sum + (due > paid ? due - paid : 0);
  });

  double get expectedAtGeneration =>
      thisMonthExpected +
      (records.first?.previousBalanceSnapshot ?? previousBalance);
  double get totalDue => thisMonthExpected + previousBalance;
  double get balance => previousBalance + thisMonthBalance;
  bool get isFullyPaid =>
      hasAllRecords &&
      balance <= 0 &&
      records.every(
        (record) =>
            record != null &&
            (record.isGenerated || record.amountPaid >= record.amountDue),
      );
  bool get isFree {
    if (previousBalance > 0) return false;
    return isGenerated
        ? thisMonthExpected <= 0
        : student.effectiveMonthlyFee <= 0;
  }
}

class _FeesPageState extends State<FeesPage> with WidgetsBindingObserver {
  String _selectedClass = kClassList.first;
  DateTime _selectedMonth = _initialBillingMonth(DateTime.now());
  List<_FeeRow> _rows = [];
  bool _loading = true;
  String? _loadError;
  int _loadVersion = 0;
  Timer? _monthBoundaryTimer;
  late String _observedCalendarMonthKey;

  static const _monthNames = [
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

  String get _monthKey =>
      '${_selectedMonth.year}-${_selectedMonth.month.toString().padLeft(2, '0')}';

  String get _monthLabel =>
      '${_monthNames[_selectedMonth.month - 1]} ${_selectedMonth.year}';

  String _calendarMonthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  static DateTime _initialBillingMonth(DateTime now) {
    if (now.month == 7) return DateTime(now.year, 6);
    if (now.month == 9) return DateTime(now.year, 8);
    return DateTime(now.year, now.month);
  }

  static DateTime _stepVisibleBillingMonth(DateTime month, int delta) {
    var next = DateTime(month.year, month.month + delta);
    while (next.month == 7 || next.month == 9) {
      next = DateTime(next.year, next.month + delta);
    }
    return next;
  }

  List<DateTime> _monthsCoveredBySlip(DateTime selectedMonth) {
    final first = DateTime(selectedMonth.year, selectedMonth.month);
    if (first.month == 6 || first.month == 8) {
      return [first, DateTime(first.year, first.month + 1)];
    }
    return [first];
  }

  String _labelForMonth(DateTime month) =>
      '${_monthNames[month.month - 1]} ${month.year}';

  String _keyForMonth(DateTime month) =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  String _combinedMonthLabel(List<DateTime> months) =>
      months.map(_labelForMonth).join(' + ');

  DateTime get _ledgerThroughMonth {
    final selected = DateTime(_selectedMonth.year, _selectedMonth.month);
    final current = DateTime.now();
    final currentMonth = DateTime(current.year, current.month);
    return selected.isAfter(currentMonth) ? currentMonth : selected;
  }

  Uint8List? _logoBytes;
  String? _schoolName;
  String? _schoolTagline;
  double _collectedThisMonth = 0;
  double _concessionThisMonth = 0;
  List<Map<String, Object?>> _collectionTransactions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _observedCalendarMonthKey = _calendarMonthKey(DateTime.now());
    _loadLogo();
    _loadSchoolInfo();
    _loadData();
    _scheduleMonthBoundaryRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshForCurrentCalendarMonth(reloadIfUnchanged: true);
    }
  }

  void _scheduleMonthBoundaryRefresh() {
    _monthBoundaryTimer?.cancel();
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    _monthBoundaryTimer = Timer(
      nextMonth.difference(now) + const Duration(seconds: 1),
      () => _refreshForCurrentCalendarMonth(reloadIfUnchanged: true),
    );
  }

  void _refreshForCurrentCalendarMonth({required bool reloadIfUnchanged}) {
    if (!mounted) return;
    final now = DateTime.now();
    final currentMonthKey = _calendarMonthKey(now);
    final monthChanged = currentMonthKey != _observedCalendarMonthKey;
    _observedCalendarMonthKey = currentMonthKey;
    if (monthChanged) {
      setState(() => _selectedMonth = _initialBillingMonth(now));
    }
    if (monthChanged || reloadIfUnchanged) _loadData();
    _scheduleMonthBoundaryRefresh();
  }

  @override
  void dispose() {
    _monthBoundaryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
      // Settings table not ready yet (e.g. stale database after an update)
      // — printing will just fall back to the built-in default name.
    }
  }

  // Loads assets/logo.jpg if it's been added to the project. Silently
  // falls back to the drawn placeholder emblem in the PDF if not found.
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

  Future<void> _loadData() async {
    if (!mounted) return;

    final requestVersion = ++_loadVersion;
    final selectedClass = _selectedClass;
    final monthKey = _monthKey;
    final monthKeys = _monthsCoveredBySlip(
      _selectedMonth,
    ).map(_keyForMonth).toList();
    setState(() {
      _loading = true;
      _loadError = null;
      _rows = [];
      _collectedThisMonth = 0;
      _concessionThisMonth = 0;
      _collectionTransactions = [];
    });

    try {
      final students = await DBHelper.instance.getStudentsByClassForMonth(
        selectedClass,
        monthKey,
      );
      // Archived students stay out of the visible fee list, but their
      // existing receipts and concessions still count in class accounting.
      final accountingStudents = await DBHelper.instance
          .getStudentsByClassForMonth(
            selectedClass,
            monthKey,
            includeArchived: true,
          );
      final rows = <_FeeRow>[];
      for (final s in students) {
        final records = <FeeRecord?>[];
        for (final key in monthKeys) {
          records.add(await DBHelper.instance.getFeeRecord(s.id!, key));
        }
        final dynamicPrevBalance = await DBHelper.instance.getPreviousBalance(
          s.id!,
          monthKeys.first,
        );
        // Use what's ACTUALLY still owed from the opening balance — this
        // shrinks as payments are applied to it (see recordPaymentWithWaterfall),
        // instead of the raw openingBalance which never changes on its own.
        final prevBalance = s.openingBalanceRemaining + dynamicPrevBalance;
        rows.add(
          _FeeRow(student: s, records: records, previousBalance: prevBalance),
        );
      }
      // Combined summer billing cycles include actual receipts from either
      // calendar month. Other billing cycles contain only the selected month.
      final studentIds = accountingStudents.map((s) => s.id!).toList();
      final transactions = await DBHelper.instance.getTransactionsForMonths(
        monthKeys,
        studentIds: studentIds,
      );
      final collected = transactions.fold<double>(
        0,
        (sum, transaction) =>
            sum + ((transaction['amount'] as num?)?.toDouble() ?? 0),
      );
      final concessions = await DBHelper.instance.getFeeConcessionTotalForMonth(
        monthKey,
        studentIds: studentIds,
        reportMonths: monthKeys,
      );
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() {
        _rows = rows;
        _collectedThisMonth = collected;
        _concessionThisMonth = concessions;
        _collectionTransactions = transactions;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestVersion != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = _stepVisibleBillingMonth(_selectedMonth, delta);
    });
    _loadData();
  }

  Future<void> _generateFees() async {
    final selectedClass = _selectedClass;
    final months = _monthsCoveredBySlip(_selectedMonth);
    for (final month in months) {
      await DBHelper.instance.generateFeesForClassMonth(
        selectedClass,
        _keyForMonth(month),
      );
    }
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Fees generated for $selectedClass — ${_combinedMonthLabel(months)}',
        ),
      ),
    );
  }

  Future<void> _downloadFeeSlips() async {
    final selectedClass = _selectedClass;
    final months = _monthsCoveredBySlip(_selectedMonth);
    final monthKeys = months.map(_keyForMonth).toList();

    // Slip downloads must not silently generate fees or change dashboard
    // figures. Staff generate the selected billing cycle explicitly first.
    final students = await DBHelper.instance.getStudentsByClassForMonth(
      selectedClass,
      monthKeys.first,
    );
    if (students.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No students in this class to print slips for.'),
          ),
        );
      }
      return;
    }

    for (final student in students) {
      for (final monthKey in monthKeys) {
        final record = await DBHelper.instance.getFeeRecord(
          student.id!,
          monthKey,
        );
        if (record == null || !record.isGenerated) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Generate fees for $selectedClass — ${_combinedMonthLabel(months)} before downloading slips.',
                ),
              ),
            );
          }
          return;
        }
      }
    }

    final slips = <SlipData>[];
    for (final student in students) {
      final previousMonthBalance = await DBHelper.instance.getPreviousBalance(
        student.id!,
        monthKeys.first,
      );
      final previousBalance =
          student.openingBalanceRemaining + previousMonthBalance;

      double currentFee = 0;
      for (final monthKey in monthKeys) {
        final record = await DBHelper.instance.getFeeRecord(
          student.id!,
          monthKey,
        );
        if (record == null) continue;
        final remaining = record.amountDue - record.amountPaid;
        if (remaining > 0) currentFee += remaining;
      }

      if (previousBalance + currentFee <= 0) continue;
      slips.add(
        SlipData(
          studentName: student.fullName,
          fatherName: student.fatherName,
          studentClass: student.studentClass,
          admissionNo: student.admissionNo,
          previousBalance: previousBalance,
          currentFee: currentFee,
          currentFeeLabel: months.length > 1
              ? '${_monthNames[months.first.month - 1]} + ${_monthNames[months.last.month - 1]} Fees'
              : 'Current Month Fee',
          monthLabel: _combinedMonthLabel(months),
        ),
      );
    }

    if (slips.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Everyone in this class is already fully paid — no slips needed.',
            ),
          ),
        );
      }
      return;
    }

    final bytes = await generateFeeSlipsPdf(
      slips,
      logoBytes: _logoBytes,
      schoolName: _schoolName,
      schoolTagline: _schoolTagline,
    );

    final safeClass = selectedClass.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final fileName = 'FeeSlips_${safeClass}_${monthKeys.join('_')}.pdf';
    try {
      final destination = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF document', extensions: ['pdf']),
        ],
      );
      if (destination == null) return;
      final path = destination.path.toLowerCase().endsWith('.pdf')
          ? destination.path
          : '${destination.path}.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fee slips saved as $path')));
      _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the PDF: $error')));
    }
  }

  /// Exports the selected class's existing fee history through the selected
  /// month. This report is read-only: it never generates fees or changes
  /// payments, concessions, or dashboard totals.
  Future<void> _downloadClassFeeLedger() async {
    final selectedClass = _selectedClass;
    final throughMonth = _ledgerThroughMonth;
    final months = List<DateTime>.generate(
      throughMonth.month,
      (index) => DateTime(throughMonth.year, index + 1),
    );
    final monthKeys = months.map(_keyForMonth).toList();

    try {
      final studentsById = <int, Student>{};
      final studentIdsByMonth = <Set<int>>[];
      for (final monthKey in monthKeys) {
        final students = await DBHelper.instance.getStudentsByClassForMonth(
          selectedClass,
          monthKey,
        );
        final monthIds = <int>{};
        for (final student in students) {
          final id = student.id;
          if (id == null) continue;
          studentsById[id] = student;
          monthIds.add(id);
        }
        studentIdsByMonth.add(monthIds);
      }

      if (studentsById.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No students found for $selectedClass.')),
          );
        }
        return;
      }

      final orderedStudents = studentsById.values.toList()
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
      final ledgerStudents = <ClassFeeLedgerStudent>[];
      final januaryKey = monthKeys.first;

      for (final student in orderedStudents) {
        final studentId = student.id!;
        final oldGeneratedBalance = await DBHelper.instance.getPreviousBalance(
          studentId,
          januaryKey,
        );
        final previousBalance =
            student.openingBalanceRemaining + oldGeneratedBalance;
        final cells = <ClassFeeLedgerCell>[];

        for (var monthIndex = 0; monthIndex < months.length; monthIndex++) {
          final wasInClass = studentIdsByMonth[monthIndex].contains(studentId);
          final record = await DBHelper.instance.getFeeRecord(
            studentId,
            monthKeys[monthIndex],
          );
          final paid =
              record != null &&
              ((record.isGenerated && record.amountDue <= 0) ||
                  (record.amountDue > 0 &&
                      record.amountPaid >= record.amountDue));
          // An ungenerated advance row is meaningful only after it is paid.
          // Unbilled rows are shown as a dash so the ledger never invents dues.
          final recordBelongsInLedger =
              record != null && (record.isGenerated || paid);
          final balance = record == null || !recordBelongsInLedger
              ? 0.0
              : (record.amountDue - record.amountPaid)
                    .clamp(0, double.infinity)
                    .toDouble();
          cells.add(
            ClassFeeLedgerCell(
              studentWasInClass: wasInClass,
              hasFeeRecord: recordBelongsInLedger,
              isPaid: paid,
              isFree:
                  recordBelongsInLedger &&
                  record != null &&
                  record.isGenerated &&
                  record.amountDue + record.manualAdjustment <= 0,
              balance: balance,
            ),
          );
        }

        ledgerStudents.add(
          ClassFeeLedgerStudent(
            admissionNo: student.admissionNo,
            name: student.fullName,
            previousBalance: previousBalance,
            months: cells,
          ),
        );
      }

      final bytes = await generateClassFeeLedgerPdf(
        schoolName: _schoolName?.trim().isNotEmpty == true
            ? _schoolName!.trim()
            : 'Amaan Public High School',
        schoolTagline: _schoolTagline ?? '',
        className: selectedClass,
        throughMonth: throughMonth,
        months: months,
        students: ledgerStudents,
        logoBytes: _logoBytes,
      );
      final safeClass = selectedClass.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]+'),
        '_',
      );
      final fileName =
          'ClassFeeLedger_${safeClass}_${_keyForMonth(throughMonth)}.pdf';
      final destination = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: 'PDF document', extensions: ['pdf']),
        ],
      );
      if (destination == null) return;
      final path = destination.path.toLowerCase().endsWith('.pdf')
          ? destination.path
          : '${destination.path}.pdf';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Class fee ledger saved as $path')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create class fee ledger: $error')),
      );
    }
  }

  void _showPaymentDialog(_FeeRow row) {
    final amountCtrl = TextEditingController();
    final concessionCtrl = TextEditingController();
    final receiptDateCtrl = TextEditingController(
      text: _defaultReceiptDate().toIso8601String().split('T').first,
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            row.student.fullName,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryLine('Previous Balance', row.previousBalance),
                _summaryLine('Billing Cycle Fee', row.thisMonthExpected),
                _summaryLine('Total Payable', row.totalDue),
                _summaryLine('Already Paid', row.thisMonthPaid),
                const Divider(height: 24),
                _summaryLine('Balance Remaining', row.balance, bold: true),
                const SizedBox(height: 16),
                _receiptDateField(context, receiptDateCtrl),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Amount Received Now (Rs)',
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: concessionCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText:
                        'Extra Concession on ${_monthLabel} (Rs) — optional',
                    helperText:
                        'One-time discount on the first month of this billing cycle only. It is not printed on the fee slip.',
                    helperMaxLines: 2,
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                final extraConcession =
                    double.tryParse(concessionCtrl.text.trim()) ?? 0;
                final receivedAt = DateTime.tryParse(
                  receiptDateCtrl.text.trim(),
                );
                if (!amount.isFinite || !extraConcession.isFinite) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter valid finite amounts only.'),
                    ),
                  );
                  return;
                }
                if (amount > 0 && receivedAt == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Choose a valid cash receipt date.'),
                    ),
                  );
                  return;
                }
                if (amount > 0 &&
                    !await _confirmReceiptMonthIfDifferent(
                      receivedAt!,
                      context,
                    )) {
                  return;
                }
                if (amount <= 0 && extraConcession <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Enter an amount received or a concession.',
                      ),
                    ),
                  );
                  return;
                }
                // A payment or one-off concession creates a real fee charge.
                // Freeze the selected billing cycle before applying either,
                // so its Expected total and opening balance stay stable.
                final cycleMonthKeys = _monthsCoveredBySlip(
                  _selectedMonth,
                ).map(_keyForMonth).toList();
                for (final cycleMonth in cycleMonthKeys) {
                  await DBHelper.instance.generateFeeForStudentMonth(
                    row.student,
                    cycleMonth,
                  );
                }

                final firstCycleRecord = await DBHelper.instance.getFeeRecord(
                  row.student.id!,
                  cycleMonthKeys.first,
                );
                // A combined billing cycle's one-off concession is applied
                // to its visible first month (June or August) only.
                if (extraConcession > 0 && firstCycleRecord != null) {
                  await DBHelper.instance.applyExtraConcession(
                    firstCycleRecord.id!,
                    extraConcession,
                  );
                }
                // Payments settle older balances first, while the receipt is
                // recorded in the actual cash-receipt month.
                if (amount > 0) {
                  await DBHelper.instance.recordPaymentWithWaterfall(
                    student: row.student,
                    viewedMonth: _monthKey,
                    amount: amount,
                    receivedAt: receivedAt!,
                  );
                }
                if (context.mounted) Navigator.pop(context);
                await _loadData();
                if (amount > 0 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Cash recorded in ${_monthNames[receivedAt!.month - 1]} ${receivedAt.year} collection.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _receiptDateField(
    BuildContext dialogContext,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () async {
            final today = DateUtils.dateOnly(DateTime.now());
            final visibleCalendarYear = _selectedMonth.year > today.year
                ? _selectedMonth.year
                : today.year;
            final lastDate = DateTime(visibleCalendarYear, 12, 31);
            var initialDate =
                DateTime.tryParse(controller.text) ?? _defaultReceiptDate();
            if (initialDate.isAfter(today)) initialDate = today;
            final selectedDate = await showDatePicker(
              context: dialogContext,
              initialDate: initialDate,
              firstDate: DateTime(1990),
              // Keep every month of the year reachable in the calendar, while
              // still preventing a future day from being recorded as cash received.
              lastDate: lastDate,
              selectableDayPredicate: (day) =>
                  !DateUtils.dateOnly(day).isAfter(today),
            );
            if (selectedDate != null) {
              controller.text = selectedDate.toIso8601String().split('T').first;
            }
          },
          decoration: InputDecoration(
            labelText: 'Cash received on',
            helperText: 'Choose the actual date cash was received.',
            helperMaxLines: 2,
            suffixIcon: const Icon(Icons.calendar_month_rounded),
            filled: true,
            fillColor: const Color(0xFFF5F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final receiptDate = DateTime.tryParse(value.text.trim());
            if (receiptDate == null) return const SizedBox.shrink();
            return Text(
              'This cash will be counted in ${_labelForMonth(receiptDate)} Cash Collected.',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            );
          },
        ),
      ],
    );
  }

  Future<bool> _confirmReceiptMonthIfDifferent(
    DateTime receiptDate,
    BuildContext dialogContext,
  ) async {
    final receiptMonth = DateTime(receiptDate.year, receiptDate.month);
    final cycleMonths = _monthsCoveredBySlip(_selectedMonth);
    final receiptMatchesCycle = cycleMonths.any(
      (month) =>
          month.year == receiptMonth.year && month.month == receiptMonth.month,
    );
    if (receiptMatchesCycle) return true;

    final receiptMonthLabel = _labelForMonth(receiptMonth);
    final billingCycleLabel = _combinedMonthLabel(cycleMonths);
    return await showDialog<bool>(
          context: dialogContext,
          builder: (confirmContext) => AlertDialog(
            title: const Text('Check the receipt month'),
            content: Text(
              'The fee screen is showing $billingCycleLabel, but the cash date is ${receiptDate.year}-${receiptDate.month.toString().padLeft(2, '0')}-${receiptDate.day.toString().padLeft(2, '0')}. '
              'This payment will be counted in $receiptMonthLabel Cash Collected, not $billingCycleLabel. Continue with this receipt date?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(confirmContext, false),
                child: const Text('Review date'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(confirmContext, true),
                child: const Text('Use this date'),
              ),
            ],
          ),
        ) ??
        false;
  }

  DateTime _defaultReceiptDate() {
    // Cash belongs to the month it was actually received, even when it pays
    // an older billing cycle. Default to the computer's current local date.
    return DateUtils.dateOnly(DateTime.now());
  }

  Widget _summaryLine(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              fontSize: bold ? 15 : 13.5,
            ),
          ),
          Text(
            'Rs ${value.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              fontSize: bold ? 15 : 13.5,
              color: bold
                  ? (value > 0 ? AppColors.red : AppColors.green)
                  : AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalExpected = _rows.fold<double>(
      0,
      (sum, row) => sum + (row.isGenerated ? row.expectedAtGeneration : 0),
    );
    // "Collected" is the cash received in this calendar month (from the
    // transaction ledger), regardless of which due-month it pays.
    final totalPaid = _collectedThisMonth;
    final totalPending = _rows.fold<double>(
      0,
      (sum, r) => sum + (r.balance > 0 ? r.balance : 0),
    );
    final freeCount = _rows
        .where((r) => r.student.effectiveMonthlyFee == 0)
        .length;
    // Concessions reported for this selected month. Each fee record keeps
    // its original snapshot; advance-paid future records are assigned to
    // the cash-receipt month so their concession appears only once.
    final concessionThisMonth = _concessionThisMonth;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fee Management',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              // Month switcher
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _changeMonth(-1),
                    ),
                    SizedBox(
                      width: 160,
                      child: Text(
                        _monthLabel,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _changeMonth(1),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Class chips
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
                          _loadData();
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

          // Summary cards
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'Total Expected',
                  totalExpected,
                  AppColors.navyLight,
                  Icons.account_balance_wallet_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _summaryCard(
                  'Cash Collected in ${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))}',
                  totalPaid,
                  AppColors.green,
                  Icons.check_circle_rounded,
                  onTap: _showCollectedReceipts,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _summaryCard(
                  'Pending',
                  totalPending,
                  AppColors.red,
                  Icons.hourglass_bottom_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'Concession: ${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))}',
                  concessionThisMonth,
                  AppColors.amber,
                  Icons.percent_rounded,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _summaryCardInt(
                  'Free Students',
                  freeCount,
                  Colors.grey.shade600,
                  Icons.card_giftcard_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_selectedClass — $_monthLabel',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _generateFees,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      side: const BorderSide(color: AppColors.teal),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      'Generate Fees: ${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))}',
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _downloadFeeSlips,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Download PDF — ${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _downloadClassFeeLedger,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.table_view_rounded, size: 18),
                    label: Text(
                      'Download Class Ledger through ${_labelForMonth(_ledgerThroughMonth)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.red,
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Could not load fee records.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _loadError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _loadData,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _rows.isEmpty
                ? Center(
                    child: Text(
                      'No students in $_selectedClass yet.',
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
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _feeTile(_rows[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String label,
    double value,
    Color color,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rs ${value.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return HoverMotion(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: card,
        ),
      ),
    );
  }

  void _showCollectedReceipts() {
    final transactions = _collectionTransactions;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Cash Collected — ${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))}',
        ),
        content: SizedBox(
          width: 460,
          height: 360,
          child: transactions.isEmpty
              ? const Center(
                  child: Text(
                    'No fee payments were received in this billing cycle.',
                  ),
                )
              : Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Total: Rs ${_collectedThisMonth.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Cash is counted in the month of its receipt date. Use the calendar button to correct a date.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.separated(
                        itemCount: transactions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          final amount =
                              (transaction['amount'] as num?)?.toDouble() ?? 0;
                          final canCorrectDate =
                              ((transaction['sameDayReceiptCount'] as num?)
                                      ?.toInt() ??
                                  1) ==
                              1;
                          return ListTile(
                            dense: true,
                            title: Text(
                              (transaction['fullName'] as String?) ?? 'Student',
                            ),
                            subtitle: Text(
                              '${(transaction['studentClass'] as String?) ?? ''} • ${(transaction['date'] as String?) ?? ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Rs ${amount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  tooltip: canCorrectDate
                                      ? 'Correct receipt date'
                                      : 'Several receipts share this date; individual correction is unsafe',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.edit_calendar_rounded),
                                  onPressed: canCorrectDate
                                      ? () => _correctReceiptDate(
                                          transaction,
                                          context,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _correctReceiptDate(
    Map<String, Object?> transaction,
    BuildContext dialogContext,
  ) async {
    final transactionId = transaction['id'] as int?;
    if (transactionId == null) return;
    final oldDate = DateTime.tryParse((transaction['date'] as String?) ?? '');
    final selectedDate = await showDatePicker(
      context: dialogContext,
      initialDate: oldDate == null || oldDate.isAfter(DateTime.now())
          ? DateTime.now()
          : oldDate,
      firstDate: DateTime(1990),
      lastDate: DateTime(DateTime.now().year, 12, 31),
      selectableDayPredicate: (day) =>
          !DateUtils.dateOnly(day).isAfter(DateUtils.dateOnly(DateTime.now())),
    );
    if (selectedDate == null || !mounted || !dialogContext.mounted) return;

    final dateText = selectedDate.toIso8601String().split('T').first;
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Correct receipt date?'),
        content: Text(
          'This will move Rs ${((transaction['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} to the ${_monthNames[selectedDate.month - 1]} ${selectedDate.year} Cash Collected total and update the linked receipt dates. The amount and paid/unpaid status will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(confirmContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(confirmContext, true),
            child: const Text('Correct date'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !dialogContext.mounted) return;

    try {
      await DBHelper.instance.updateFeeTransactionReceiptDate(
        transactionId,
        selectedDate,
      );
    } catch (error) {
      if (!mounted) return;
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not correct the receipt date: $error')),
      );
      return;
    }
    if (!mounted || !dialogContext.mounted) return;
    Navigator.pop(dialogContext);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(content: Text('Receipt date corrected to $dateText.')),
    );
  }

  Widget _summaryCardInt(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeTile(_FeeRow row) {
    final isFree = row.isFree;
    Color statusColor;
    String statusLabel;
    if (isFree) {
      statusColor = Colors.grey.shade600;
      statusLabel = 'Free';
    } else if (row.isFullyPaid) {
      statusColor = AppColors.green;
      statusLabel = 'Paid';
    } else if (!row.isGenerated) {
      statusColor = Colors.grey.shade400;
      statusLabel = 'Not Generated';
    } else if (row.thisMonthPaid > 0) {
      statusColor = AppColors.amber;
      statusLabel = 'Partial';
    } else {
      statusColor = AppColors.red;
      statusLabel = 'Unpaid';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.teal.withOpacity(0.12),
        child: Text(
          row.student.fullName.isNotEmpty ? row.student.fullName[0] : '?',
          style: const TextStyle(
            color: AppColors.tealDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.teal.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          row.student.fullName,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
            color: AppColors.tealDark,
          ),
        ),
      ),
      subtitle: Text(
        [
          if (row.isGenerated && !isFree)
            '${_combinedMonthLabel(_monthsCoveredBySlip(_selectedMonth))} fee: Rs ${row.thisMonthExpected.toStringAsFixed(0)}',
          if (row.previousBalance > 0)
            'Previous balance: Rs ${row.previousBalance.toStringAsFixed(0)}',
          if (isFree) 'No fee applicable',
        ].join('  •  '),
        style: TextStyle(
          color: row.previousBalance > 0 ? AppColors.red : null,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (row.isGenerated && !row.isFullyPaid)
            ElevatedButton(
              onPressed: () => _showPaymentDialog(row),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Record Payment',
                style: TextStyle(fontSize: 12),
              ),
            ),
          if (!isFree) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _showAdvancePaymentDialog(row.student),
              icon: const Icon(
                Icons.event_available_rounded,
                color: AppColors.navy,
              ),
              tooltip: 'Pay months in advance',
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showAdvancePaymentDialog(Student student) async {
    // Advance payment choices follow the visible billing cycles. June includes
    // July, and August includes September, so hidden months are never offered
    // as separate billing choices.
    final firstCycle = _stepVisibleBillingMonth(_selectedMonth, 1);
    final options = List.generate(12, (i) {
      var d = firstCycle;
      for (var step = 0; step < i; step++) {
        d = _stepVisibleBillingMonth(d, 1);
      }
      final key = _keyForMonth(d);
      final label = _combinedMonthLabel(_monthsCoveredBySlip(d));
      return MapEntry(key, label);
    });
    final selected = <String>{};
    final receiptDateCtrl = TextEditingController(
      text: _defaultReceiptDate().toIso8601String().split('T').first,
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final cyclesListHeight = (MediaQuery.sizeOf(context).height * 0.34)
              .clamp(150.0, 280.0)
              .toDouble();
          return AlertDialog(
            scrollable: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Pay in Advance — ${student.fullName}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _receiptDateField(context, receiptDateCtrl),
                  const SizedBox(height: 12),
                  Text(
                    'Select upcoming billing cycles. June includes July, and August includes September. '
                    'These cycles will show as paid when generated.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: cyclesListHeight,
                    child: ListView(
                      children: options.map((entry) {
                        return CheckboxListTile(
                          dense: true,
                          value: selected.contains(entry.key),
                          onChanged: (val) => setDialogState(() {
                            if (val == true) {
                              selected.add(entry.key);
                            } else {
                              selected.remove(entry.key);
                            }
                          }),
                          title: Text(entry.value),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (selected.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select at least one billing cycle.'),
                      ),
                    );
                    return;
                  }
                  // The database records this cash in its actual receipt
                  // month. Selected cycles only identify which future fees
                  // are being marked paid.
                  final selectedCycles = selected.toList()..sort();
                  final dueMonths = <String>{};
                  for (final key in selectedCycles) {
                    final parts = key.split('-');
                    final cycle = DateTime(
                      int.parse(parts[0]),
                      int.parse(parts[1]),
                    );
                    dueMonths.addAll(
                      _monthsCoveredBySlip(cycle).map(_keyForMonth),
                    );
                  }
                  final receivedAt = DateTime.tryParse(
                    receiptDateCtrl.text.trim(),
                  );
                  if (receivedAt == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Choose a valid cash receipt date.'),
                      ),
                    );
                    return;
                  }
                  final advanceAmount = await DBHelper.instance
                      .payMonthsInAdvanceWithTransaction(
                        student,
                        dueMonths.toList()..sort(),
                        receivedAt: receivedAt,
                      );
                  if (context.mounted) Navigator.pop(context);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          advanceAmount > 0
                              ? 'Rs ${advanceAmount.toStringAsFixed(0)} recorded in ${_monthNames[receivedAt.month - 1]} ${receivedAt.year} collections; selected cycles marked Paid.'
                              : 'Selected cycles were already paid; no new cash was recorded.',
                        ),
                      ),
                    );
                  }
                  await _loadData();
                },
                child: const Text('Confirm Advance Payment'),
              ),
            ],
          );
        },
      ),
    );
  }
}
