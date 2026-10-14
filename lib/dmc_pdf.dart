import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'db_helper.dart' show Subject;

const String kSchoolNameDmc = 'Amaan Public High School';
const String kSchoolTaglineDmc = 'Enter to Learn, Leave to Serve';

/// Keeps fractional academic marks visible while omitting an unnecessary
/// decimal suffix for whole numbers.
String formatAcademicMark(double value) {
  final text = value.toString();
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

// A restrained navy and light-blue palette that prints clearly.
final PdfColor kDmcNavy = PdfColor.fromInt(0xFF183B5B);
final PdfColor kDmcNavyLight = PdfColor.fromInt(0xFF315C7D);
final PdfColor kDmcAccent = PdfColor.fromInt(0xFF6AAED6);
final PdfColor kDmcAccentLight = PdfColor.fromInt(0xFFEAF5FC);

/// Centered school name and teal rule; long names wrap within the page.
pw.Widget _schoolNameBanner(String schoolName, {double fontSize = 24}) {
  return pw.Column(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        schoolName.toUpperCase(),
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: pw.FontWeight.bold,
          color: kDmcNavy,
          letterSpacing: fontSize >= 20 ? 1.5 : 1.1,
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Container(width: 250, height: 1.2, color: kDmcAccent),
    ],
  );
}

// One student's computed result for a given exam.
class StudentResult {
  final String studentName;
  final String fatherName;
  final String studentClass;
  final String admissionNo;
  final Map<String, double> subjectMarks; // subjectName -> obtained
  final Map<String, double> subjectTotals; // subjectName -> max marks
  int position = 0; // filled in after ranking

  StudentResult({
    required this.studentName,
    required this.fatherName,
    required this.studentClass,
    required this.admissionNo,
    required this.subjectMarks,
    required this.subjectTotals,
  });

  double get totalObtained => subjectTotals.keys.fold(
    0,
    (sum, subjectName) => sum + (subjectMarks[subjectName] ?? 0),
  );
  double get totalMax => subjectTotals.values.fold(0, (a, b) => a + b);
  double get percentage => totalMax <= 0 ? 0 : (totalObtained / totalMax) * 100;

  String get grade {
    final p = percentage;
    if (p >= 90) return 'A+';
    if (p >= 80) return 'A';
    if (p >= 70) return 'B';
    if (p >= 60) return 'C';
    if (p >= 50) return 'D';
    if (p >= 33) return 'E';
    return 'F';
  }
}

/// Only students who meet the pass mark in every subject are eligible for a
/// position. A low mark in any paper remains visible as that subject's grade.
bool hasPassedAllSubjects(StudentResult result, List<Subject> subjects) {
  if (subjects.isEmpty) return false;
  for (final subject in subjects) {
    final obtained = result.subjectMarks[subject.subjectName];
    if (!subject.totalMarks.isFinite ||
        subject.totalMarks <= 0 ||
        obtained == null ||
        !obtained.isFinite ||
        obtained < subject.passingMarks ||
        obtained < 0 ||
        obtained > subject.totalMarks) {
      return false;
    }
  }
  return true;
}

/// Ranks eligible students by total marks using dense ranking.
/// Equal totals share a position and the next distinct total gets the next
/// position (1, 2, 2, 3).
/// Students below the pass mark in any subject keep position 0 (unranked).
void assignPositions(List<StudentResult> results, List<Subject> subjects) {
  for (final result in results) {
    result.position = 0;
  }

  final eligible =
      results.where((result) => hasPassedAllSubjects(result, subjects)).toList()
        ..sort((a, b) => b.totalObtained.compareTo(a.totalObtained));
  int rank = 0;
  double? lastTotal;
  for (int i = 0; i < eligible.length; i++) {
    if (lastTotal == null ||
        (eligible[i].totalObtained - lastTotal).abs() > 0.0000001) {
      rank++;
      lastTotal = eligible[i].totalObtained;
    }
    eligible[i].position = rank;
  }
}

List<StudentResult> _sortedByPosition(
  List<StudentResult> results,
  List<Subject> subjects,
) {
  assignPositions(results, subjects);
  return [...results]..sort((a, b) {
    if (a.position == 0 && b.position != 0) return 1;
    if (a.position != 0 && b.position == 0) return -1;
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    final byTotal = b.totalObtained.compareTo(a.totalObtained);
    if (byTotal != 0) return byTotal;
    return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
  });
}

String _ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}

pw.Widget _logoWidget(pw.MemoryImage? logoImage, double size) {
  if (logoImage != null) {
    return pw.Container(width: size, height: size, child: pw.Image(logoImage));
  }
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      gradient: pw.LinearGradient(
        colors: [kDmcNavy, kDmcNavyLight],
        begin: pw.Alignment.topLeft,
        end: pw.Alignment.bottomRight,
      ),
    ),
    alignment: pw.Alignment.center,
    child: pw.Text(
      'A',
      style: pw.TextStyle(
        fontSize: size * 0.45,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
    ),
  );
}

pw.Widget _header(
  String className,
  String examName,
  pw.MemoryImage? logoImage,
  String schoolName,
  String schoolTagline,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Center(child: _logoWidget(logoImage, 42)),
      pw.SizedBox(height: 4),
      pw.Center(child: _schoolNameBanner(schoolName, fontSize: 17)),
      pw.SizedBox(height: 3),
      pw.Text(
        schoolTagline,
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(
          fontSize: 8.5,
          fontStyle: pw.FontStyle.italic,
          color: PdfColors.grey600,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
        decoration: pw.BoxDecoration(
          color: kDmcNavy,
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'CLASS RESULT - $className',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
            pw.Text(
              examName,
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Generates the whole-class result sheet: one table showing every
/// student's marks per subject, total, percentage, and position.
Future<Uint8List> generateClassResultSheetPdf({
  required String className,
  required String examName,
  required List<Subject> subjects,
  required List<StudentResult> results,
  Uint8List? logoBytes,
  String schoolName = kSchoolNameDmc,
  String schoolTagline = kSchoolTaglineDmc,
}) async {
  final sorted = _sortedByPosition(results, subjects);
  final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

  final pdf = pw.Document();
  final headers = [
    'S#',
    'Student Name',
    "Father's Name",
    ...subjects.map(
      (s) => '${s.subjectName}\n(${formatAcademicMark(s.totalMarks)})',
    ),
    'Total',
    '%',
    'Position',
  ];

  final rows = <List<String>>[];
  for (int i = 0; i < sorted.length; i++) {
    final r = sorted[i];
    rows.add([
      '${i + 1}',
      r.studentName,
      r.fatherName.isEmpty ? '-' : r.fatherName,
      ...subjects.map(
        (s) => formatAcademicMark(r.subjectMarks[s.subjectName] ?? 0),
      ),
      formatAcademicMark(r.totalObtained),
      '${r.percentage.toStringAsFixed(1)}%',
      r.position == 0 ? '-' : _ordinal(r.position),
    ]);
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) {
        if (context.pageNumber == 1) {
          return _header(
            className,
            examName,
            logoImage,
            schoolName,
            schoolTagline,
          );
        }
        return pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                schoolName,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: kDmcNavy,
                ),
              ),
              pw.Text(
                'CLASS RESULT - $className | $examName',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        );
      },
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300)),
        ),
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerDecoration: pw.BoxDecoration(color: kDmcAccentLight),
          headerStyle: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: kDmcNavy,
          ),
          cellStyle: pw.TextStyle(fontSize: subjects.length <= 8 ? 9.5 : 8),
          cellAlignment: pw.Alignment.center,
          cellAlignments: {1: pw.Alignment.centerLeft},
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.6),
          cellPadding: pw.EdgeInsets.symmetric(
            vertical: subjects.length <= 8 ? 7 : 5,
            horizontal: 4,
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

/// Generates individual DMCs — one full page per student, designed to use
/// the whole page (framed border, grading scale reference, remarks line).
Future<Uint8List> generateIndividualDmcsPdf({
  required String className,
  required String examName,
  required List<Subject> subjects,
  required List<StudentResult> results,
  Uint8List? logoBytes,
  String schoolName = kSchoolNameDmc,
  String schoolTagline = kSchoolTaglineDmc,
}) async {
  final sorted = _sortedByPosition(results, subjects);
  final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

  final pdf = pw.Document();

  for (final r in sorted) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        build: (context) {
          // Outer frame gives the certificate a finished, formal look and
          // helps the page feel intentionally filled rather than sparse.
          return pw.Container(
            margin: const pw.EdgeInsets.all(24),
            padding: const pw.EdgeInsets.all(28),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kDmcAccent, width: 1.8),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header — logo centered above a clean, letter-spaced school name
                pw.Center(child: _logoWidget(logoImage, 68)),
                pw.SizedBox(height: 8),
                pw.Center(child: _schoolNameBanner(schoolName, fontSize: 19)),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    schoolTagline,
                    style: const pw.TextStyle(
                      fontSize: 9,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
                pw.SizedBox(height: 9),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: kDmcNavy,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'DETAILED MARKS CERTIFICATE',
                    style: pw.TextStyle(
                      fontSize: 13.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                pw.SizedBox(height: 11),

                // Admission number is the first student detail, as requested.
                _dmcInfo(
                  'Admission Number',
                  r.admissionNo.isEmpty ? '-' : r.admissionNo,
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _dmcInfo('Student Name', r.studentName)),
                    pw.Expanded(child: _dmcInfo('Class', r.studentClass)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  children: [
                    pw.Expanded(child: _dmcInfo("Father's Name", r.fatherName)),
                    pw.Expanded(child: _dmcInfo('Examination', examName)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.SizedBox(height: 14),

                // Marks table — sizes itself to the number of subjects, so
                // a class with only 4-5 subjects gets bigger, easier-to-read
                // rows instead of leaving blank space at the bottom.
                pw.TableHelper.fromTextArray(
                  headers: const [
                    'Subject',
                    'Total Marks',
                    'Obtained Marks',
                    'Grade',
                  ],
                  data: subjects
                      .map(
                        (s) => [
                          s.subjectName,
                          formatAcademicMark(s.totalMarks),
                          formatAcademicMark(
                            r.subjectMarks[s.subjectName] ?? 0,
                          ),
                          _subjectGrade(
                            r.subjectMarks[s.subjectName] ?? 0,
                            s.totalMarks,
                            s.passingMarks,
                          ),
                        ],
                      )
                      .toList(),
                  headerDecoration: pw.BoxDecoration(color: kDmcAccentLight),
                  headerStyle: pw.TextStyle(
                    fontSize: subjects.length <= 5 ? 12 : 10,
                    fontWeight: pw.FontWeight.bold,
                    color: kDmcNavy,
                  ),
                  cellStyle: pw.TextStyle(
                    fontSize: subjects.length <= 5 ? 12 : 10,
                  ),
                  cellAlignment: pw.Alignment.center,
                  cellAlignments: {0: pw.Alignment.centerLeft},
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.6,
                  ),
                  cellPadding: pw.EdgeInsets.symmetric(
                    vertical: subjects.length <= 4
                        ? 13
                        : subjects.length <= 6
                        ? 9
                        : 6,
                    horizontal: 7,
                  ),
                ),
                pw.SizedBox(height: 8),

                // Summary
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _summaryBox(
                        'Total Marks',
                        '${formatAcademicMark(r.totalObtained)} / ${formatAcademicMark(r.totalMax)}',
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: _summaryBox(
                        'Percentage',
                        '${r.percentage.toStringAsFixed(1)}%',
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _summaryBox('Grade (by %)', r.grade)),
                  ],
                ),
                pw.SizedBox(height: 8),

                if (r.position > 0) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 7),
                    decoration: pw.BoxDecoration(
                      color: kDmcAccentLight,
                      border: pw.Border.all(color: kDmcAccent, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'Position in Class: ${_ordinal(r.position)}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: kDmcNavy,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                ],

                // Remarks — one generous writing area for the teacher to
                // fill by hand (a single bigger space, not two thin lines).
                pw.Text(
                  'Remarks',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Container(
                  width: double.infinity,
                  height: 38,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                ),

                pw.Spacer(),

                // Footer: signatures
                pw.Divider(color: PdfColors.grey300, height: 1, thickness: 1),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _signatureLine('Class Teacher'),
                    _signatureLine('Principal'),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  return pdf.save();
}

String _subjectGrade(double obtained, double total, double passingMark) {
  if (total <= 0 || !obtained.isFinite || obtained < 0 || obtained > total) {
    return '-';
  }
  if (obtained < passingMark) return 'F';
  final p = (obtained / total) * 100;
  if (p >= 90) return 'A+';
  if (p >= 80) return 'A';
  if (p >= 70) return 'B';
  if (p >= 60) return 'C';
  if (p >= 50) return 'D';
  return 'E';
}

// ---- Typography: only normal/bold used throughout, for a consistent,
// non-cluttered look — labels normal+grey, values bold+dark.
pw.Widget _dmcInfo(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey600),
      ),
      pw.SizedBox(height: 3),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

pw.Widget _summaryBox(String label, String value) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 6),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey100,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
            color: kDmcNavy,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _signatureLine(String label) {
  return pw.Column(
    children: [
      pw.Container(width: 188, height: 1, color: kDmcNavyLight),
      pw.SizedBox(height: 5),
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: kDmcNavyLight,
        ),
      ),
    ],
  );
}
