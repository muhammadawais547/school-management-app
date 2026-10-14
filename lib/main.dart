import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'students_page.dart';
import 'fees_page.dart';
import 'teachers_page.dart';
import 'dmc_page.dart';
import 'settings_page.dart';
import 'certificate_page.dart';
import 'auth_gate.dart';
import 'ui_motion.dart';

void main() {
  runApp(const SchoolApp());
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'School Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA99F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        fontFamily: 'Segoe UI',
        filledButtonTheme: const FilledButtonThemeData(
          style: ButtonStyle(animationDuration: Duration(milliseconds: 160)),
        ),
        elevatedButtonTheme: const ElevatedButtonThemeData(
          style: ButtonStyle(animationDuration: Duration(milliseconds: 160)),
        ),
        outlinedButtonTheme: const OutlinedButtonThemeData(
          style: ButtonStyle(animationDuration: Duration(milliseconds: 160)),
        ),
        textButtonTheme: const TextButtonThemeData(
          style: ButtonStyle(animationDuration: Duration(milliseconds: 160)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// ---------- Colors (change these to rebrand the whole app) ----------
class AppColors {
  static const navy = Color(0xFF16213E);
  static const navyLight = Color(0xFF1F2C4F);
  static const teal = Color(0xFF0EA99F);
  static const tealDark = Color(0xFF0B8A82);
  static const green = Color(0xFF22C55E);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const textDark = Color(0xFF1E2536);
  static const textGrey = Color(0xFF6B7280);
}

// ---------- App shell: sidebar + page switching ----------
class AppShell extends StatefulWidget {
  final VoidCallback? onLogout;
  const AppShell({super.key, this.onLogout});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  String _schoolName = 'Amaan Public High School';
  Uint8List? _schoolLogoBytes;

  @override
  void initState() {
    super.initState();
    _loadSchoolName();
  }

  Future<void> _loadSchoolName() async {
    final info = await DBHelper.instance.getSchoolInfo();
    final logo = await DBHelper.instance.getSchoolLogoBytes();
    if (!mounted) return;
    setState(() {
      _schoolName = info['name'] ?? 'School Manager';
      _schoolLogoBytes = logo;
    });
  }

  final List<_NavItem> _navItems = const [
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('Students', Icons.school_rounded),
    _NavItem('Teachers', Icons.badge_rounded),
    _NavItem('Fees', Icons.payments_rounded),
    _NavItem('DMC / Results', Icons.grade_rounded),
    _NavItem('Certificates', Icons.workspace_premium_rounded),
    _NavItem('Settings', Icons.settings_rounded),
  ];

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return DashboardPage(
          onNavigate: (i) => setState(() => _selectedIndex = i),
        );
      case 1:
        return const StudentsPage();
      case 2:
        return const TeachersPage();
      case 3:
        return const FeesPage();
      case 4:
        return const DmcPage();
      case 5:
        return const CertificatePage();
      case 6:
        return SettingsPage(onBrandingChanged: _loadSchoolName);
      default:
        return _ComingSoonPage(title: _navItems[index].label);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 240,
            color: AppColors.navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _schoolLogoBytes == null
                              ? AppColors.teal
                              : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _schoolLogoBytes == null
                            ? const Icon(
                                Icons.school,
                                color: Colors.white,
                                size: 20,
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _schoolLogoBytes!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.school),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _schoolName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                for (int i = 0; i < _navItems.length; i++)
                  HoverMotion(
                    hoverScale: 1.008,
                    child: _SidebarTile(
                      item: _navItems[i],
                      selected: _selectedIndex == i,
                      onTap: () => setState(() => _selectedIndex = i),
                    ),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Material(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => widget.onLogout?.call(),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.teal,
                              child: Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Admin',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.logout_rounded,
                              color: Colors.white.withOpacity(0.6),
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final position = Tween<Offset>(
                    begin: const Offset(0.012, 0),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: position, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<int>(_selectedIndex),
                  child: _buildPage(_selectedIndex),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

class _SidebarTile extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.teal.withOpacity(0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedScale(
                    scale: selected ? 1.06 : 1,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      item.icon,
                      size: 20,
                      color: selected ? AppColors.teal : Colors.white70,
                    ),
                  ),
                  const SizedBox(width: 14),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                    child: Text(item.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Dashboard page ----------
class DashboardPage extends StatefulWidget {
  final void Function(int index)? onNavigate;
  const DashboardPage({super.key, this.onNavigate});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  bool _loading = true;
  String? _loadError;
  int _totalStudents = 0;
  int _totalTeachers = 0;
  double _feesCollected = 0;
  double _feesPending = 0;
  List<Map<String, dynamic>> _recentPayments = [];
  Timer? _monthBoundaryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboard();
    _scheduleMonthBoundaryRefresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadDashboard();
      _scheduleMonthBoundaryRefresh();
    }
  }

  void _scheduleMonthBoundaryRefresh() {
    _monthBoundaryTimer?.cancel();
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    _monthBoundaryTimer = Timer(
      nextMonth.difference(now) + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        _loadDashboard();
        _scheduleMonthBoundaryRefresh();
      },
    );
  }

  @override
  void dispose() {
    _monthBoundaryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _currentMonthLabel() {
    const months = [
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
    final now = DateTime.now();
    return months[now.month - 1] + ' ' + now.year.toString();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // Both dashboard sections use the same date snapshot so a refresh at
      // midnight cannot mix two different calendar months.
      final snapshotDate = DateTime.now();
      final summary = await DBHelper.instance.getDashboardSummary(
        onDate: snapshotDate,
      );
      final recent = await DBHelper.instance.getRecentPaymentsForCurrentMonth(
        onDate: snapshotDate,
      );
      if (!mounted) return;
      setState(() {
        _totalStudents = summary['totalStudents'] as int;
        _totalTeachers = summary['totalTeachers'] as int;
        _feesCollected = summary['feesCollected'] as double;
        _feesPending = summary['feesPending'] as double;
        _recentPayments = recent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  String _formatMoney(double v) {
    if (v >= 1000000) return 'Rs ${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return 'Rs ${(v / 1000).toStringAsFixed(1)}K';
    return 'Rs ${v.toStringAsFixed(0)}';
  }

  String _formatPaymentDate(String value) {
    try {
      final date = DateTime.parse(value);
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
      return '${date.day} ${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return value.isEmpty ? 'Date not recorded' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Could not load the dashboard.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Overview of your school today',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 14),
                  ),
                ],
              ),
              IconButton(
                onPressed: _loadDashboard,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textGrey,
                ),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 28),

          // KPI cards row — now reflects real data from the database
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: 'Total Students',
                  value: '$_totalStudents',
                  icon: Icons.groups_rounded,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _KpiCard(
                  label: 'Total Teachers',
                  value: '$_totalTeachers',
                  icon: Icons.badge_rounded,
                  color: AppColors.navyLight,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _KpiCard(
                  label: 'Fees Collected (This Month)',
                  value: _formatMoney(_feesCollected),
                  icon: Icons.check_circle_rounded,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _KpiCard(
                  label: 'Outstanding Fees',
                  value: _formatMoney(_feesPending),
                  icon: Icons.hourglass_bottom_rounded,
                  color: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recent activity — real recent payments
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fee payments this month - ' + _currentMonthLabel(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_recentPayments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No payments recorded this month.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      else
                        SizedBox(
                          height: 360,
                          child: ListView.separated(
                            itemCount: _recentPayments.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFE5E7EB),
                            ),
                            itemBuilder: (context, index) {
                              final payment = _recentPayments[index];
                              return _PaymentRow(
                                name: payment['fullName'] as String,
                                grade: payment['studentClass'] as String,
                                date: _formatPaymentDate(
                                  payment['date'] as String? ?? '',
                                ),
                                amount:
                                    'Rs ${(payment['amount'] as num).toStringAsFixed(0)}',
                                status: 'Received',
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              // Quick actions
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quick actions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _QuickAction(
                        icon: Icons.person_add_rounded,
                        label: 'Add new student',
                        onTap: () => widget.onNavigate?.call(1),
                      ),
                      _QuickAction(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Add new teacher',
                        onTap: () => widget.onNavigate?.call(2),
                      ),
                      _QuickAction(
                        icon: Icons.receipt_long_rounded,
                        label: 'Record fee payment',
                        onTap: () => widget.onNavigate?.call(3),
                      ),
                      _QuickAction(
                        icon: Icons.grade_rounded,
                        label: 'View DMC / Results',
                        onTap: () => widget.onNavigate?.call(4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              value,
              key: ValueKey<String>(value),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String name;
  final String grade;
  final String date;
  final String amount;
  final String status;

  const _PaymentRow({
    required this.name,
    required this.grade,
    required this.date,
    required this.amount,
    required this.status,
  });

  Color get _statusColor {
    switch (status) {
      case 'Paid':
      case 'Received':
        return AppColors.green;
      case 'Pending':
        return AppColors.amber;
      default:
        return AppColors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.teal.withOpacity(0.12),
            child: Text(
              name.isEmpty ? '?' : name[0],
              style: const TextStyle(
                color: AppColors.tealDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$grade  |  $date',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: _statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickAction({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return HoverMotion(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap:
                onTap ??
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This feature is coming in a later step'),
                    ),
                  );
                },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.teal, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Placeholder page for tabs we haven't built yet ----------
class _ComingSoonPage extends StatelessWidget {
  final String title;
  const _ComingSoonPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_rounded,
            size: 60,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            '$title — coming in the next step',
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
