import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey, rootBundle;
import 'package:printing/printing.dart';
import 'db_helper.dart';
import 'dmc_pdf.dart';
import 'main.dart' show AppColors;
import 'ui_motion.dart';

class DmcPage extends StatefulWidget {
  const DmcPage({super.key});

  @override
  State<DmcPage> createState() => _DmcPageState();
}

class _DmcPageState extends State<DmcPage> {
  String _selectedClass = kClassList.first;
  final TextEditingController _examController = TextEditingController();
  List<String> _pastExamNames = [];

  List<Subject> _subjects = [];
  List<Student> _students = [];
  String _loadedExamName = '';
  // studentId -> subjectId -> controller
  final Map<int, Map<int, TextEditingController>> _markControllers = {};
  // Kept beside each controller so spreadsheet-style keys can move around
  // the grid without changing the saved exam data.
  final Map<int, Map<int, FocusNode>> _markFocusNodes = {};

  bool _loading = true;
  bool _saving = false;
  String? _printingAction;
  String? _loadError;
  int _classLoadVersion = 0;
  int _marksLoadVersion = 0;

  bool get _printing => _printingAction != null;

  Uint8List? _logoBytes;
  String _schoolName = kSchoolNameDmc;
  String _schoolTagline = kSchoolTaglineDmc;

  @override
  void initState() {
    super.initState();
    _loadLogo();
    _loadSchoolInfo();
    _loadClassData();
  }

  @override
  void dispose() {
    _classLoadVersion++;
    _marksLoadVersion++;
    _examController.dispose();
    _disposeMarkControllers();
    super.dispose();
  }

  void _disposeMarkControllers() {
    for (final controllersBySubject in _markControllers.values) {
      for (final controller in controllersBySubject.values) {
        controller.dispose();
      }
    }
    _markControllers.clear();
    for (final nodesBySubject in _markFocusNodes.values) {
      for (final node in nodesBySubject.values) {
        node.dispose();
      }
    }
    _markFocusNodes.clear();
  }

  // Loads assets/logo.jpg if it's been added to the project. Silently
  // falls back to the drawn emblem in the PDFs if the asset isn't there.
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
      // No logo asset yet — PDFs will use the drawn placeholder emblem.
    }
  }

  Future<void> _loadSchoolInfo() async {
    final info = await DBHelper.instance.getSchoolInfo();
    if (!mounted) return;
    setState(() {
      _schoolName = info['name'] ?? kSchoolNameDmc;
      _schoolTagline = info['tagline'] ?? kSchoolTaglineDmc;
    });
  }

  Future<void> _loadClassData() async {
    if (!mounted) return;
    final loadVersion = ++_classLoadVersion;
    final selectedClass = _selectedClass;
    _marksLoadVersion++;
    setState(() {
      _loading = true;
      _loadError = null;
    });

    List<Subject> subjects = [];
    List<Student> students = [];
    List<String> pastExams = [];

    try {
      subjects = await DBHelper.instance.getSubjectsForClass(selectedClass);
      if (!mounted || loadVersion != _classLoadVersion) return;
    } catch (e) {
      if (!mounted || loadVersion != _classLoadVersion) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load subjects: $e';
      });
      return;
    }

    try {
      students = await DBHelper.instance.getStudentsByClass(selectedClass);
      if (!mounted || loadVersion != _classLoadVersion) return;
    } catch (e) {
      if (!mounted || loadVersion != _classLoadVersion) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load students: $e';
      });
      return;
    }

    try {
      pastExams = await DBHelper.instance.getExamNamesForClass(selectedClass);
      if (!mounted || loadVersion != _classLoadVersion) return;
    } catch (_) {
      // Non-critical — just means the "past exams" quick-select chips won't show.
    }

    if (!mounted || loadVersion != _classLoadVersion) return;
    setState(() {
      _subjects = subjects;
      _students = students;
      _pastExamNames = pastExams;
    });

    if (_examController.text.trim().isEmpty && pastExams.isNotEmpty) {
      _examController.text = pastExams.last;
    }
    try {
      final marksLoaded = await _loadMarksIntoControllers();
      if (!marksLoaded || !mounted || loadVersion != _classLoadVersion) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || loadVersion != _classLoadVersion) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load saved marks: $e';
      });
    }
  }

  Future<bool> _loadMarksIntoControllers() async {
    final loadVersion = ++_marksLoadVersion;
    final selectedClass = _selectedClass;
    final examName = _examController.text.trim();
    final students = List<Student>.of(_students);
    final subjects = List<Subject>.of(_subjects);
    Map<int, Map<int, double>> existingMarks = {};
    if (examName.isNotEmpty) {
      existingMarks = await DBHelper.instance.getMarksForClassExam(
        selectedClass,
        examName,
      );
    }

    if (!mounted ||
        loadVersion != _marksLoadVersion ||
        selectedClass != _selectedClass ||
        examName != _examController.text.trim()) {
      return false;
    }

    _loadedExamName = examName;

    final loadedControllers = <int, Map<int, TextEditingController>>{};
    final loadedFocusNodes = <int, Map<int, FocusNode>>{};
    for (var studentIndex = 0; studentIndex < students.length; studentIndex++) {
      final currentStudentIndex = studentIndex;
      final s = students[studentIndex];
      loadedControllers[s.id!] = {};
      loadedFocusNodes[s.id!] = {};
      for (
        var subjectIndex = 0;
        subjectIndex < subjects.length;
        subjectIndex++
      ) {
        final currentSubjectIndex = subjectIndex;
        final subj = subjects[subjectIndex];
        final savedMark = existingMarks[s.id]?[subj.id];
        loadedControllers[s.id!]![subj.id!] = TextEditingController(
          text: savedMark == null ? '' : formatAcademicMark(savedMark),
        );
        loadedFocusNodes[s.id!]![subj.id!] = FocusNode(
          debugLabel: '${s.fullName} - ${subj.subjectName}',
          onKeyEvent: (node, event) => _handleMarkGridKey(
            event,
            currentStudentIndex,
            currentSubjectIndex,
          ),
        );
      }
    }

    _disposeMarkControllers();
    _markControllers.addAll(loadedControllers);
    _markFocusNodes.addAll(loadedFocusNodes);
    setState(() {});
    return true;
  }

  Future<void> _loadSelectedExamMarks() async {
    if (!mounted) return;
    final classLoadVersion = _classLoadVersion;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final marksLoaded = await _loadMarksIntoControllers();
      if (!mounted || classLoadVersion != _classLoadVersion || !marksLoaded) {
        return;
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || classLoadVersion != _classLoadVersion) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load saved marks: $e';
      });
    }
  }

  Future<void> _startNewExam() async {
    if (_saving || _printing) return;
    final hasMarksOnScreen = _markControllers.values.any(
      (controllersBySubject) => controllersBySubject.values.any(
        (controller) => controller.text.trim().isNotEmpty,
      ),
    );
    if (hasMarksOnScreen && !await _saveCurrentMarksBeforeNewExam()) return;

    setState(() {
      _examController.clear();
      _loadedExamName = '';
      for (final controllersBySubject in _markControllers.values) {
        for (final controller in controllersBySubject.values) {
          controller.clear();
        }
      }
    });
  }

  Future<void> _deleteExamResult(String examName) async {
    if (_saving || _printing) return;
    final className = _selectedClass;
    final isOpenExam = _loadedExamName == examName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Exam Results?'),
        content: Text(
          'Delete "$examName" results for $className? This removes the saved '
          'marks for every student in this class.'
          '${isOpenExam ? ' The marks currently shown will also be cleared.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete Results'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || className != _selectedClass) return;

    try {
      await DBHelper.instance.deleteMarksForClassExam(className, examName);
      if (!mounted || className != _selectedClass) return;
      setState(() {
        _pastExamNames.remove(examName);
        if (_loadedExamName == examName) {
          _examController.clear();
          _loadedExamName = '';
          for (final controllersBySubject in _markControllers.values) {
            for (final controller in controllersBySubject.values) {
              controller.clear();
            }
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $examName results for $className.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete the exam results: $error'),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }

  Future<bool> _saveCurrentMarksBeforeNewExam() async {
    final examName = _examController.text.trim();
    if (examName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter this exam name before saving.')),
      );
      return false;
    }
    if (!_isExamNameReady(examName)) return false;
    if (_students.isEmpty || _subjects.isEmpty || !_validateAllMarksFilled()) {
      return false;
    }

    setState(() => _saving = true);
    try {
      await DBHelper.instance.upsertMarksBatch(_collectMarkEntries(examName));
      if (!mounted) return false;
      _loadedExamName = examName;
      if (!_pastExamNames.contains(examName)) {
        setState(() {
          _pastExamNames = [..._pastExamNames, examName]..sort();
        });
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Marks saved for $examName.')));
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save current marks: $error'),
            backgroundColor: AppColors.red,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  KeyEventResult _handleMarkGridKey(
    KeyEvent event,
    int studentIndex,
    int subjectIndex,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_students.isEmpty || _subjects.isEmpty) {
      return KeyEventResult.handled;
    }
    var targetStudentIndex = studentIndex;
    var targetSubjectIndex = subjectIndex;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageUp) {
      targetStudentIndex = (studentIndex - 1)
          .clamp(0, _students.length - 1)
          .toInt();
    } else if (key == LogicalKeyboardKey.pageDown) {
      targetStudentIndex = (studentIndex + 1)
          .clamp(0, _students.length - 1)
          .toInt();
    } else if (key == LogicalKeyboardKey.home) {
      targetSubjectIndex = 0;
    } else if (key == LogicalKeyboardKey.end) {
      targetSubjectIndex = _subjects.length - 1;
    } else {
      return KeyEventResult.ignored;
    }
    final studentId = _students[targetStudentIndex].id;
    final subjectId = _subjects[targetSubjectIndex].id;
    final target = _markFocusNodes[studentId]?[subjectId];
    if (target == null) return KeyEventResult.handled;
    target.requestFocus();
    final controller = _markControllers[studentId]?[subjectId];
    if (controller != null && controller.text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }
    final targetContext = target.context;
    if (targetContext != null) {
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.45,
          duration: const Duration(milliseconds: 120),
        ),
      );
    }
    return KeyEventResult.handled;
  }

  // Rejects marks above the subject's total — clears the field and asks
  // the user to re-enter, rather than silently adjusting the value.
  void _onMarkChanged(String value, Subject subj, TextEditingController ctrl) {
    final entered = double.tryParse(value.trim());
    if (entered != null &&
        (!entered.isFinite || entered < 0 || entered > subj.totalMarks)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            entered.isFinite && entered < 0
                ? '${subj.subjectName} marks cannot be negative.'
                : entered.isFinite
                ? '${subj.subjectName} has a maximum of ${formatAcademicMark(subj.totalMarks)} marks. Please re-enter.'
                : 'Enter a valid number for ${subj.subjectName}.',
          ),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      ctrl.clear();
    }
  }

  Future<void> _addSubjectDialog() async {
    final nameCtrl = TextEditingController();
    final totalCtrl = TextEditingController(text: '100');
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Subject',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Subject Name',
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
                controller: totalCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Total Marks',
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
              final name = nameCtrl.text.trim();
              final total = double.tryParse(totalCtrl.text.trim());
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter a subject name.')),
                );
                return;
              }
              if (total == null || !total.isFinite || total <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Total marks must be a valid number above 0.',
                    ),
                  ),
                );
                return;
              }
              try {
                final added = await DBHelper.instance.addSubject(
                  Subject(
                    className: _selectedClass,
                    subjectName: name,
                    totalMarks: total,
                  ),
                );
                if (context.mounted) Navigator.pop(context);
                if (!added && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'That subject already exists for this class.',
                      ),
                    ),
                  );
                }
                _loadClassData();
              } catch (e) {
                if (context.mounted) Navigator.pop(context);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not add subject: $e')),
                  );
                }
              }
            },
            child: const Text('Add Subject'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSubject(Subject s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Subject?'),
        content: Text(
          'Delete ${s.subjectName} from ${s.className}? This also permanently removes its saved marks for every exam.',
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
            child: const Text('Delete Subject'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      await DBHelper.instance.deleteSubject(s.id!);
      await _loadClassData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete subject: $e')));
      }
    }
  }

  /// Checks every mark cell is filled and valid (0 <= value <= total).
  /// Returns true if all good; otherwise shows an error and returns false.
  /// Used by Save AND both Print buttons — leaving a box blank should
  /// never silently slip through as a 0 in any of them.
  bool _validateAllMarksFilled() {
    for (final subject in _subjects) {
      if (!subject.totalMarks.isFinite ||
          subject.totalMarks <= 0 ||
          !subject.passingMarks.isFinite ||
          subject.passingMarks < 0 ||
          subject.passingMarks > subject.totalMarks) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'The marks or passing marks for ${subject.subjectName} are invalid. Correct the subject settings first.',
            ),
            backgroundColor: AppColors.red,
          ),
        );
        return false;
      }
    }
    for (final s in _students) {
      for (final subj in _subjects) {
        final ctrl = _markControllers[s.id!]?[subj.id!];
        if (ctrl == null || ctrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please fill in every mark first — ${s.fullName}\'s "${subj.subjectName}" mark is missing.',
              ),
              backgroundColor: AppColors.red,
            ),
          );
          return false;
        }
        final value = double.tryParse(ctrl.text.trim());
        if (value == null ||
            !value.isFinite ||
            value > subj.totalMarks ||
            value < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${s.fullName}\'s "${subj.subjectName}" mark is invalid. Please check it.',
              ),
              backgroundColor: AppColors.red,
            ),
          );
          return false;
        }
      }
    }
    return true;
  }

  bool _isExamNameReady(String examName) {
    if (examName == _loadedExamName) return true;
    // A new, never-used name is safe only after the user has started a blank
    // sheet. Reusing an existing name requires loading its saved marks first.
    if (_loadedExamName.isEmpty && !_pastExamNames.contains(examName)) {
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'The visible marks belong to "${_loadedExamName.isEmpty ? 'a blank new sheet' : _loadedExamName}". Use Start New Exam for a fresh sheet, or select the saved exam to load its marks.',
        ),
        backgroundColor: AppColors.red,
      ),
    );
    return false;
  }

  List<MarkEntry> _collectMarkEntries(String examName) {
    return [
      for (final student in _students)
        for (final subject in _subjects)
          MarkEntry(
            studentId: student.id!,
            subjectId: subject.id!,
            examName: examName,
            obtainedMarks: double.parse(
              _markControllers[student.id!]![subject.id!]!.text.trim(),
            ),
          ),
    ];
  }

  Future<void> _saveAllMarks() async {
    if (_saving) return;
    final examName = _examController.text.trim();
    if (examName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter an exam name first (e.g. "Final Term 2026").'),
        ),
      );
      return;
    }
    if (!_isExamNameReady(examName)) return;

    if (_students.isEmpty || _subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add students and subjects to this class before saving marks.',
          ),
        ),
      );
      return;
    }

    if (!_validateAllMarksFilled()) return;

    final marks = _collectMarkEntries(examName);

    setState(() => _saving = true);
    try {
      await DBHelper.instance.upsertMarksBatch(marks);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marks saved.')));
      await _loadClassData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save marks. No partial save was kept: $e'),
          backgroundColor: AppColors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<StudentResult> _buildResults() {
    final subjectTotals = {
      for (final s in _subjects) s.subjectName: s.totalMarks,
    };
    return _students.map((s) {
      final marksMap = <String, double>{};
      for (final subj in _subjects) {
        final ctrl = _markControllers[s.id]?[subj.id];
        marksMap[subj.subjectName] =
            double.tryParse(ctrl?.text.trim() ?? '') ?? 0;
      }
      return StudentResult(
        studentName: s.fullName,
        fatherName: s.fatherName,
        studentClass: s.studentClass,
        admissionNo: s.admissionNo,
        subjectMarks: marksMap,
        subjectTotals: subjectTotals,
      );
    }).toList();
  }

  bool _hasCompleteValidMarkGrid() {
    if (_examController.text.trim().isEmpty ||
        _students.isEmpty ||
        _subjects.isEmpty) {
      return false;
    }
    for (final student in _students) {
      for (final subject in _subjects) {
        if (!subject.totalMarks.isFinite ||
            subject.totalMarks <= 0 ||
            !subject.passingMarks.isFinite ||
            subject.passingMarks < 0 ||
            subject.passingMarks > subject.totalMarks) {
          return false;
        }
        final controller = _markControllers[student.id!]?[subject.id!];
        final mark = double.tryParse(controller?.text.trim() ?? '');
        if (mark == null ||
            !mark.isFinite ||
            mark < 0 ||
            mark > subject.totalMarks) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _printClassSheet() async {
    if (_printing || _saving) return;
    if (_subjects.isEmpty || _students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add subjects and students first.')),
      );
      return;
    }
    final examName = _examController.text.trim();
    if (examName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an exam name first.')),
      );
      return;
    }
    if (!_isExamNameReady(examName)) return;
    if (!_validateAllMarksFilled()) return;
    final className = _selectedClass;
    final results = _buildResults();
    final marks = _collectMarkEntries(examName);
    setState(() => _printingAction = 'classSheet');
    try {
      // Keep the saved mark sheet identical to the one sent to the printer.
      await DBHelper.instance.upsertMarksBatch(marks);
      _loadedExamName = examName;
      if (!_pastExamNames.contains(examName) && mounted) {
        setState(() => _pastExamNames = [..._pastExamNames, examName]..sort());
      }
      final bytes = await generateClassResultSheetPdf(
        className: className,
        examName: examName,
        subjects: _subjects,
        results: results,
        logoBytes: _logoBytes,
        schoolName: _schoolName,
        schoolTagline: _schoolTagline,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'ClassResult_${className}_$examName.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not generate or print the class sheet: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printingAction = null);
    }
  }

  Future<void> _printIndividualDmcs() async {
    if (_printing || _saving) return;
    if (_subjects.isEmpty || _students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add subjects and students first.')),
      );
      return;
    }
    final examName = _examController.text.trim();
    if (examName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an exam name first.')),
      );
      return;
    }
    if (!_isExamNameReady(examName)) return;
    if (!_validateAllMarksFilled()) return;
    final className = _selectedClass;
    final results = _buildResults();
    final marks = _collectMarkEntries(examName);
    setState(() => _printingAction = 'individualDmcs');
    try {
      // Keep the saved mark sheet identical to the DMCs sent to the printer.
      await DBHelper.instance.upsertMarksBatch(marks);
      _loadedExamName = examName;
      if (!_pastExamNames.contains(examName) && mounted) {
        setState(() => _pastExamNames = [..._pastExamNames, examName]..sort());
      }
      final bytes = await generateIndividualDmcsPdf(
        className: className,
        examName: examName,
        subjects: _subjects,
        results: results,
        logoBytes: _logoBytes,
        schoolName: _schoolName,
        schoolTagline: _schoolTagline,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: 'DMCs_${className}_$examName.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not generate or print the DMCs: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printingAction = null);
    }
  }

  Future<void> _showPromoteDialog() async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No students in this class.')),
      );
      return;
    }

    // Only use complete valid marks for the current exam. Missing marks
    // must not be mistaken for failures or automatic passes.
    final hasCompleteResults = _hasCompleteValidMarkGrid();
    final currentIndex = kClassList.indexOf(_selectedClass);
    String targetClass =
        (currentIndex >= 0 && currentIndex < kClassList.length - 1)
        ? kClassList[currentIndex + 1]
        : kGraduatedLabel;

    final Map<int, bool> selected = {for (final s in _students) s.id!: false};
    var isPromoting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return PopScope(
            canPop: !isPromoting,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Promote Students',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              content: AbsorbPointer(
                absorbing: isPromoting,
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Promote to:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: targetClass,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFFF5F7FA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: [...kClassList, kGraduatedLabel]
                                  .where((c) => c != _selectedClass)
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null)
                                  setDialogState(() => targetClass = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Select students manually. A low mark in one subject does not automatically decide promotion.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 320,
                        child: ListView(
                          children: _students.map((s) {
                            return CheckboxListTile(
                              dense: true,
                              value: selected[s.id!] ?? false,
                              onChanged: (val) => setDialogState(
                                () => selected[s.id!] = val ?? false,
                              ),
                              title: Text(
                                s.fullName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "s/o ${s.fatherName}",
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isPromoting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isPromoting
                      ? null
                      : () async {
                          final idsToPromote = selected.entries
                              .where((e) => e.value)
                              .map((e) => e.key)
                              .toList();
                          if (idsToPromote.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No students selected.'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() => isPromoting = true);
                          try {
                            if (hasCompleteResults) {
                              await DBHelper.instance.upsertMarksBatch(
                                _collectMarkEntries(
                                  _examController.text.trim(),
                                ),
                              );
                            }
                            await DBHelper.instance.promoteStudents(
                              idsToPromote,
                              targetClass,
                            );
                            if (context.mounted) Navigator.pop(context);
                            if (!mounted) return;
                            await _loadClassData();
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${idsToPromote.length} student(s) promoted to $targetClass.',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              setDialogState(() => isPromoting = false);
                            }
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Promotion failed; no students were changed. Details: $e',
                                  ),
                                  backgroundColor: AppColors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: Text(
                    isPromoting ? 'Promoting...' : 'Promote Selected',
                  ),
                ),
              ],
            ),
          );
        },
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
          const Text(
            'DMC — Result Cards',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
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
                          _examController.clear();
                          _loadClassData();
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

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_loadError != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.red),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loadClassData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Exam name + subjects — in proper cards for a polished look
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(
                                      Icons.event_note_rounded,
                                      size: 18,
                                      color: AppColors.teal,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Exam Name',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _examController,
                                  decoration: InputDecoration(
                                    hintText:
                                        'e.g. Final Term Examination 2026',
                                    filled: true,
                                    fillColor: const Color(0xFFF5F7FA),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  onSubmitted: (value) {
                                    final name = value.trim();
                                    if (_pastExamNames.contains(name) &&
                                        name != _loadedExamName) {
                                      _loadSelectedExamMarks();
                                    }
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: _saving || _printing
                                        ? null
                                        : _startNewExam,
                                    icon: const Icon(
                                      Icons.add_circle_outline_rounded,
                                      size: 17,
                                    ),
                                    label: const Text('Start New Exam'),
                                  ),
                                ),
                                if (_pastExamNames.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'Saved Exams',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _pastExamNames
                                        .map(
                                          (e) => HoverMotion(
                                            hoverScale: 1.025,
                                            child: InputChip(
                                              label: Text(
                                                e,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                              selected: e == _loadedExamName,
                                              showCheckmark: false,
                                              backgroundColor: const Color(
                                                0xFFF5F7FA,
                                              ),
                                              deleteIcon: const Icon(
                                                Icons.close_rounded,
                                                size: 16,
                                              ),
                                              deleteButtonTooltipMessage:
                                                  'Delete $e results',
                                              onPressed: () {
                                                _examController.text = e;
                                                _loadSelectedExamMarks();
                                              },
                                              onDeleted: _saving || _printing
                                                  ? null
                                                  : () => _deleteExamResult(e),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: const [
                                        Icon(
                                          Icons.menu_book_rounded,
                                          size: 18,
                                          color: AppColors.teal,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Subjects for this Class',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    TextButton.icon(
                                      onPressed: _addSubjectDialog,
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Add Subject'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: _subjects
                                      .map(
                                        (s) => Chip(
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 0,
                                          ),
                                          label: Text(
                                            '${s.subjectName} /${formatAcademicMark(s.totalMarks)}',
                                          ),
                                          onDeleted: () => _deleteSubject(s),
                                          backgroundColor: AppColors.teal
                                              .withOpacity(0.1),
                                          labelStyle: const TextStyle(
                                            color: AppColors.tealDark,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Marks entry grid
                    if (_subjects.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'Add subjects for $_selectedClass to begin entering marks.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else if (_students.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No students in $_selectedClass yet.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.edit_note_rounded,
                                size: 18,
                                color: AppColors.teal,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Enter Marks',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(4),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  AppColors.teal.withOpacity(0.08),
                                ),
                                columnSpacing: 14,
                                horizontalMargin: 12,
                                dataRowMinHeight: 46,
                                dataRowMaxHeight: 58,
                                headingRowHeight: 44,
                                columns: [
                                  const DataColumn(
                                    label: Text(
                                      'Student',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                  for (final subj in _subjects)
                                    DataColumn(
                                      label: Text(
                                        '${subj.subjectName}\n/${formatAcademicMark(subj.totalMarks)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                                rows: _students.map((s) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.teal
                                                    .withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                s.fullName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13,
                                                  color: AppColors.tealDark,
                                                ),
                                              ),
                                            ),
                                            // Small father's name — helps tell apart
                                            // two students with the same first name.
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                                left: 4,
                                              ),
                                              child: Text(
                                                "s/o ${s.fatherName}",
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ...List<DataCell>.generate(
                                        _subjects.length,
                                        (subjectIndex) {
                                          final subject =
                                              _subjects[subjectIndex];
                                          return DataCell(
                                            SizedBox(
                                              width: 44,
                                              child: TextField(
                                                controller:
                                                    _markControllers[s
                                                        .id!]?[subject.id!],
                                                focusNode:
                                                    _markFocusNodes[s
                                                        .id!]?[subject.id!],
                                                keyboardType:
                                                    TextInputType.number,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                ),
                                                onChanged: (val) =>
                                                    _onMarkChanged(
                                                      val,
                                                      subject,
                                                      _markControllers[s
                                                          .id!]![subject.id!]!,
                                                    ),
                                                decoration:
                                                    const InputDecoration(
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 8,
                                                            horizontal: 4,
                                                          ),
                                                      border:
                                                          OutlineInputBorder(),
                                                    ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saving || _printing
                              ? null
                              : _saveAllMarks,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_rounded, size: 18),
                          label: const Text('Save Marks'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _saving || _printing
                              ? null
                              : _printClassSheet,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.navy,
                            side: const BorderSide(color: AppColors.navy),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _printingAction == 'classSheet'
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.grid_on_rounded, size: 18),
                          label: Text(
                            _printingAction == 'classSheet'
                                ? 'Printing...'
                                : 'Print Class Result Sheet',
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _saving || _printing
                              ? null
                              : _printIndividualDmcs,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.navy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: _printingAction == 'individualDmcs'
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.badge_outlined, size: 18),
                          label: Text(
                            _printingAction == 'individualDmcs'
                                ? 'Printing...'
                                : 'Print Individual DMCs',
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _showPromoteDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.green,
                            side: const BorderSide(color: AppColors.green),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.arrow_upward_rounded,
                            size: 18,
                          ),
                          label: const Text('Promote Students'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
