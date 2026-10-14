import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db_helper.dart';
import 'main.dart' show AppColors;

class TeachersPage extends StatefulWidget {
  const TeachersPage({super.key});

  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<_TeacherSalaryTabState> _salaryTabKey =
      GlobalKey<_TeacherSalaryTabState>();

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
            'Teachers',
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
              Tab(text: 'Directory'),
              Tab(text: 'Salary'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _TeacherDirectoryTab(onTeachersChanged: _refreshSalaryData),
                _TeacherSalaryTab(key: _salaryTabKey),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _refreshSalaryData() {
    _salaryTabKey.currentState?._loadData();
  }
}

// =====================================================================
// DIRECTORY TAB
// =====================================================================

class _TeacherDirectoryTab extends StatefulWidget {
  final VoidCallback onTeachersChanged;

  const _TeacherDirectoryTab({required this.onTeachersChanged});

  @override
  State<_TeacherDirectoryTab> createState() => _TeacherDirectoryTabState();
}

class _TeacherDirectoryTabState extends State<_TeacherDirectoryTab> {
  List<Teacher> _teachers = [];
  List<Teacher> _filtered = [];
  final TextEditingController _searchController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTeachers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await DBHelper.instance.getAllTeachers();
      if (!mounted) return;
      setState(() {
        _teachers = data;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load teachers: $e')));
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = _teachers
          .where(
            (t) =>
                query.isEmpty ||
                t.fullName.toLowerCase().contains(query) ||
                t.subject.toLowerCase().contains(query),
          )
          .toList();
    });
  }

  Future<void> _deleteTeacher(Teacher t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Teacher?'),
        content: Text(
          'Delete ${t.fullName} and their saved salary payment history? This cannot be undone.',
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
            child: const Text('Delete Teacher'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await DBHelper.instance.deleteTeacher(t.id!);
      await _loadTeachers();
      if (mounted) widget.onTeachersChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete teacher: $e')));
      }
    }
  }

  Future<void> _showAddDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final subjectCtrl = TextEditingController();
    final qualificationCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    var isSaving = false;
    var saved = false;
    String? saveError;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return PopScope(
              canPop: !isSaving,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Add New Teacher',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Form(
                      key: formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (saveError != null) ...[
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                saveError!,
                                style: const TextStyle(
                                  color: AppColors.red,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _field(
                            nameCtrl,
                            'Full Name',
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Full name is required';
                              if (v.trim().length < 3)
                                return 'Enter the full name';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _field(
                            phoneCtrl,
                            'Phone Number (03XXXXXXXXX)',
                            isNumber: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(11),
                            ],
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Phone number is required';
                              if (v.trim().length != 11)
                                return 'Must be exactly 11 digits';
                              if (!v.trim().startsWith('0')) {
                                return "Pakistani numbers start with '0'";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _field(
                            addressCtrl,
                            'Address',
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Address is required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _field(
                            subjectCtrl,
                            'Subject Taught',
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Subject is required';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _field(
                            qualificationCtrl,
                            'Qualification (e.g. B.Ed, M.A)',
                          ),
                          const SizedBox(height: 12),
                          _field(
                            salaryCtrl,
                            'Monthly Salary (Rs)',
                            isNumber: true,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty)
                                return 'Monthly salary is required';
                              final salary = double.tryParse(v.trim());
                              if (salary == null || !salary.isFinite)
                                return 'Enter a valid number';
                              if (salary < 0) {
                                return 'Salary cannot be negative';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
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
                            if (!(formKey.currentState?.validate() ?? false))
                              return;
                            setDialogState(() {
                              isSaving = true;
                              saveError = null;
                            });
                            final teacher = Teacher(
                              fullName: nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              address: addressCtrl.text.trim(),
                              subject: subjectCtrl.text.trim(),
                              qualification: qualificationCtrl.text.trim(),
                              monthlySalary:
                                  double.tryParse(salaryCtrl.text.trim()) ?? 0,
                            );
                            try {
                              await DBHelper.instance.addTeacher(teacher);
                              saved = true;
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            } catch (e) {
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  isSaving = false;
                                  saveError = 'Could not add teacher: $e';
                                });
                              }
                            }
                          },
                    child: Text(isSaving ? 'Saving...' : 'Add Teacher'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (saved && mounted) {
        await _loadTeachers();
        if (mounted) widget.onTeachersChanged();
      }
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      subjectCtrl.dispose();
      qualificationCtrl.dispose();
      salaryCtrl.dispose();
    }
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool isNumber = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => _applyFilter(),
                  decoration: InputDecoration(
                    hintText: 'Search by name or subject...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _showAddDialog,
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
                label: const Text('Add Teacher'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
                    child: Text(
                      _teachers.isEmpty
                          ? 'No teachers yet. Click "Add Teacher" to begin.'
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
                        final t = _filtered[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.navyLight.withOpacity(
                              0.12,
                            ),
                            child: Text(
                              t.fullName.isNotEmpty ? t.fullName[0] : '?',
                              style: const TextStyle(
                                color: AppColors.navyLight,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            t.fullName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${t.subject}${t.qualification.isNotEmpty ? " • ${t.qualification}" : ""}  •  ${t.phone}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Rs ${t.monthlySalary.toStringAsFixed(0)}/mo',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: AppColors.red,
                                ),
                                onPressed: () => _deleteTeacher(t),
                              ),
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

// =====================================================================
// SALARY TAB
// =====================================================================

class _SalaryRow {
  final Teacher teacher;
  final SalaryRecord? record;
  final double previousBalance;

  _SalaryRow({
    required this.teacher,
    required this.record,
    required this.previousBalance,
  });

  bool get isGenerated => record != null;
  double get thisMonthDue => record?.amountDue ?? teacher.monthlySalary;
  double get thisMonthPaid => record?.amountPaid ?? 0;
  double get totalDue => thisMonthDue + previousBalance;
  double get balance => totalDue - thisMonthPaid;
  bool get isFullyPaid => isGenerated && balance <= 0;
}

class _TeacherSalaryTab extends StatefulWidget {
  const _TeacherSalaryTab({super.key});

  @override
  State<_TeacherSalaryTab> createState() => _TeacherSalaryTabState();
}

class _TeacherSalaryTabState extends State<_TeacherSalaryTab> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  List<_SalaryRow> _rows = [];
  bool _loading = true;
  bool _generatingSalaries = false;
  String? _loadError;
  int _loadVersion = 0;

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final loadVersion = ++_loadVersion;
    final selectedMonth = _monthKey;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final teachers = await DBHelper.instance.getAllTeachers();
      final rows = <_SalaryRow>[];
      for (final t in teachers) {
        final record = await DBHelper.instance.getSalaryRecord(
          t.id!,
          selectedMonth,
        );
        final prevBalance = await DBHelper.instance.getPreviousSalaryBalance(
          t.id!,
          selectedMonth,
        );
        rows.add(
          _SalaryRow(teacher: t, record: record, previousBalance: prevBalance),
        );
      }
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || loadVersion != _loadVersion) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
    _loadData();
  }

  Future<void> _generateSalaries() async {
    if (_generatingSalaries) return;
    final month = _monthKey;
    final monthLabel = _monthLabel;
    setState(() => _generatingSalaries = true);
    try {
      await DBHelper.instance.generateSalariesForMonth(month);
      if (!mounted) return;
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Salaries generated for $monthLabel')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not generate salaries: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingSalaries = false);
    }
  }

  Future<void> _showPaymentDialog(_SalaryRow row) async {
    final amountCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var isSaving = false;
    String? saveError;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return PopScope(
              canPop: !isSaving,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(
                  row.teacher.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _summaryLine('Previous Balance', row.previousBalance),
                      _summaryLine('This Month Salary', row.thisMonthDue),
                      _summaryLine('Total Payable', row.totalDue),
                      _summaryLine('Already Paid', row.thisMonthPaid),
                      const Divider(height: 24),
                      _summaryLine(
                        'Balance Remaining',
                        row.balance,
                        bold: true,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          final amount = double.tryParse(value?.trim() ?? '');
                          if (amount == null ||
                              !amount.isFinite ||
                              amount <= 0) {
                            return 'Enter a valid amount greater than zero.';
                          }
                          if (amount > row.balance + 0.000001) {
                            return 'Amount cannot exceed the total balance of Rs ${row.balance.toStringAsFixed(2)}.';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          labelText: 'Amount Paid Now (Rs)',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (saveError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          saveError!,
                          style: const TextStyle(color: AppColors.red),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
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
                            if (!(formKey.currentState?.validate() ?? false))
                              return;
                            final record = row.record;
                            if (record == null) {
                              setDialogState(() {
                                saveError =
                                    'Generate this month’s salary record first.';
                              });
                              return;
                            }
                            final amount = double.parse(amountCtrl.text.trim());
                            setDialogState(() {
                              isSaving = true;
                              saveError = null;
                            });
                            try {
                              await DBHelper.instance.recordSalaryPayment(
                                record.id!,
                                amount,
                              );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                              await _loadData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Salary payment recorded.'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  isSaving = false;
                                  saveError = 'Could not record payment: $e';
                                });
                              }
                            }
                          },
                    child: Text(isSaving ? 'Saving...' : 'Record Payment'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      amountCtrl.dispose();
    }
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
    final totalExpected = _rows.fold<double>(0, (sum, r) => sum + r.totalDue);
    final totalPaid = _rows.fold<double>(0, (sum, r) => sum + r.thisMonthPaid);
    final totalPending = totalExpected - totalPaid;

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
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
              OutlinedButton.icon(
                onPressed: _generatingSalaries ? null : _generateSalaries,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.teal,
                  side: const BorderSide(color: AppColors.teal),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _generatingSalaries
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  _generatingSalaries
                      ? 'Generating...'
                      : 'Generate Salaries for this Month',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                  'Paid',
                  totalPaid,
                  AppColors.green,
                  Icons.check_circle_rounded,
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load salary records.'),
                        const SizedBox(height: 8),
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
                  )
                : _rows.isEmpty
                ? Center(
                    child: Text(
                      'No teachers added yet.',
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
                      itemBuilder: (context, index) =>
                          _salaryTile(_rows[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double value, Color color, IconData icon) {
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
  }

  Widget _salaryTile(_SalaryRow row) {
    Color statusColor;
    String statusLabel;
    if (!row.isGenerated) {
      statusColor = Colors.grey.shade400;
      statusLabel = 'Not Generated';
    } else if (row.isFullyPaid) {
      statusColor = AppColors.green;
      statusLabel = 'Paid';
    } else if (row.thisMonthPaid > 0) {
      statusColor = AppColors.amber;
      statusLabel = 'Partial';
    } else {
      statusColor = AppColors.red;
      statusLabel = 'Unpaid';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.navyLight.withOpacity(0.12),
        child: Text(
          row.teacher.fullName.isNotEmpty ? row.teacher.fullName[0] : '?',
          style: const TextStyle(
            color: AppColors.navyLight,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        row.teacher.fullName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: row.previousBalance > 0
          ? Text(
              'Previous balance: Rs ${row.previousBalance.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.red, fontSize: 12),
            )
          : Text('Rs ${row.thisMonthDue.toStringAsFixed(0)}/month'),
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
        ],
      ),
    );
  }
}
