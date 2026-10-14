import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _ledgerNavy = PdfColor.fromInt(0xFF183653);
const _ledgerBlue = PdfColor.fromInt(0xFF78A9D1);
const _ledgerPaleBlue = PdfColor.fromInt(0xFFEAF3FA);
const _ledgerBorder = PdfColor.fromInt(0xFFD4E0EA);
const _ledgerText = PdfColor.fromInt(0xFF243444);

class ClassFeeLedgerCell {
  final bool studentWasInClass;
  final bool hasFeeRecord;
  final bool isPaid;
  final bool isFree;
  final double balance;

  const ClassFeeLedgerCell({
    required this.studentWasInClass,
    required this.hasFeeRecord,
    required this.isPaid,
    this.isFree = false,
    required this.balance,
  });

  double get outstanding =>
      studentWasInClass && hasFeeRecord && !isPaid && balance > 0 ? balance : 0;
}

class ClassFeeLedgerStudent {
  final String admissionNo;
  final String name;
  final double previousBalance;
  final List<ClassFeeLedgerCell> months;

  const ClassFeeLedgerStudent({
    required this.admissionNo,
    required this.name,
    required this.previousBalance,
    required this.months,
  });

  double get totalBalance =>
      previousBalance +
      months.fold<double>(0, (sum, month) => sum + month.outstanding);
}

Future<Uint8List> generateClassFeeLedgerPdf({
  required String schoolName,
  required String schoolTagline,
  required String className,
  required DateTime throughMonth,
  required List<DateTime> months,
  required List<ClassFeeLedgerStudent> students,
  Uint8List? logoBytes,
}) async {
  final pdf = pw.Document();
  final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
  final monthNames = const [
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
  final monthAbbreviations = const [
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
  final throughLabel =
      '${monthNames[throughMonth.month - 1]} ${throughMonth.year}';
  final pageWidth = PdfPageFormat.a4.landscape.width - 36;
  const admissionWidth = 52.0;
  const studentWidth = 126.0;
  const previousWidth = 72.0;
  const totalWidth = 78.0;
  final monthlyWidth =
      (pageWidth - admissionWidth - studentWidth - previousWidth - totalWidth) /
      months.length;
  final columnWidths = <int, pw.TableColumnWidth>{
    0: const pw.FixedColumnWidth(admissionWidth),
    1: const pw.FixedColumnWidth(studentWidth),
    2: const pw.FixedColumnWidth(previousWidth),
  };
  for (var i = 0; i < months.length; i++) {
    columnWidths[i + 3] = pw.FixedColumnWidth(monthlyWidth);
  }
  columnWidths[months.length + 3] = const pw.FixedColumnWidth(totalWidth);

  final monthlyTotals = List<double>.filled(months.length, 0);
  var previousBalanceTotal = 0.0;
  for (final student in students) {
    previousBalanceTotal += student.previousBalance;
    for (var i = 0; i < months.length; i++) {
      monthlyTotals[i] += student.months[i].outstanding;
    }
  }
  final classBalanceTotal =
      previousBalanceTotal +
      monthlyTotals.fold<double>(0, (sum, value) => sum + value);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.fromLTRB(18, 18, 18, 28),
      header: (context) => _ledgerHeader(
        schoolName: schoolName,
        schoolTagline: schoolTagline,
        className: className,
        throughLabel: throughLabel,
        logo: logo,
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            top: pw.BorderSide(color: _ledgerBorder, width: 0.6),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Amounts are Rs. Paid = settled. Amount = remaining due for that month. - = no fee record. Months after $throughLabel are excluded.',
              style: const pw.TextStyle(fontSize: 7, color: _ledgerText),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7, color: _ledgerText),
            ),
          ],
        ),
      ),
      build: (context) => [
        pw.Table(
          border: pw.TableBorder.all(color: _ledgerBorder, width: 0.55),
          defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
          columnWidths: columnWidths,
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: _ledgerNavy),
              children: [
                _headerCell('Adm. No.'),
                _headerCell('Student'),
                _headerCell('Previous\nBalance'),
                for (final month in months)
                  _headerCell(
                    '${monthAbbreviations[month.month - 1]}\n${month.year}',
                  ),
                _headerCell('Total\nBalance'),
              ],
            ),
            for (var rowIndex = 0; rowIndex < students.length; rowIndex++)
              _studentRow(students[rowIndex], months.length, rowIndex.isOdd),
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _ledgerPaleBlue),
              children: [
                _totalLabelCell('CLASS TOTAL'),
                _totalLabelCell('Outstanding through $throughLabel'),
                _totalMoneyCell(previousBalanceTotal),
                for (final amount in monthlyTotals) _totalMoneyCell(amount),
                _totalMoneyCell(classBalanceTotal, strong: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Previous Balance includes unpaid generated fees before January ${throughMonth.year}. Monthly amounts show only each month\'s own remaining fee; the final column adds those balances to the previous balance.',
          style: const pw.TextStyle(fontSize: 7.5, color: _ledgerText),
        ),
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _ledgerHeader({
  required String schoolName,
  required String schoolTagline,
  required String className,
  required String throughLabel,
  required pw.MemoryImage? logo,
}) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 8),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _ledgerBlue, width: 1.2)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.SizedBox(width: 32, height: 32, child: pw.Image(logo)),
          pw.SizedBox(width: 9),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                schoolName,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _ledgerNavy,
                ),
              ),
              if (schoolTagline.trim().isNotEmpty)
                pw.Text(
                  schoolTagline,
                  style: const pw.TextStyle(fontSize: 7.5, color: _ledgerText),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'CLASS FEE LEDGER',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: _ledgerNavy,
                letterSpacing: 0.7,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              '$className  |  Through $throughLabel',
              style: const pw.TextStyle(fontSize: 8.5, color: _ledgerText),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.TableRow _studentRow(
  ClassFeeLedgerStudent student,
  int monthCount,
  bool alternate,
) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(
      color: alternate ? _ledgerPaleBlue : PdfColors.white,
    ),
    children: [
      _bodyCell(student.admissionNo.isEmpty ? '-' : student.admissionNo),
      _bodyCell(student.name, align: pw.TextAlign.left),
      _moneyCell(student.previousBalance),
      for (var i = 0; i < monthCount; i++) _monthCell(student.months[i]),
      _moneyCell(student.totalBalance, emphasize: true),
    ],
  );
}

pw.Widget _headerCell(String value) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 5),
  alignment: pw.Alignment.center,
  child: pw.Text(
    value,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      fontSize: 6.8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
  ),
);

pw.Widget _bodyCell(String value, {pw.TextAlign align = pw.TextAlign.center}) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      alignment: align == pw.TextAlign.left
          ? pw.Alignment.centerLeft
          : pw.Alignment.center,
      child: pw.Text(
        value,
        maxLines: 2,
        overflow: pw.TextOverflow.clip,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 6.8, color: _ledgerText),
      ),
    );

pw.Widget _monthCell(ClassFeeLedgerCell cell) {
  final label = !cell.studentWasInClass || !cell.hasFeeRecord
      ? '-'
      : cell.isFree
      ? 'Free'
      : cell.isPaid
      ? 'Paid'
      : _formatAmount(cell.balance);
  final color = cell.outstanding > 0
      ? const PdfColor.fromInt(0xFF9E3D45)
      : _ledgerText;
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 1.5, vertical: 4),
    alignment: pw.Alignment.center,
    child: pw.Text(
      label,
      textAlign: pw.TextAlign.center,
      maxLines: 2,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        fontSize: 6.4,
        fontWeight: cell.isPaid || cell.isFree || cell.outstanding > 0
            ? pw.FontWeight.bold
            : pw.FontWeight.normal,
        color: color,
      ),
    ),
  );
}

pw.Widget _moneyCell(double amount, {bool emphasize = false}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
  alignment: pw.Alignment.center,
  child: pw.Text(
    _formatAmount(amount),
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      fontSize: 6.6,
      fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: emphasize && amount > 0
          ? const PdfColor.fromInt(0xFF9E3D45)
          : _ledgerText,
    ),
  ),
);

pw.Widget _totalLabelCell(String value) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 6),
  alignment: pw.Alignment.centerLeft,
  child: pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: 6.8,
      fontWeight: pw.FontWeight.bold,
      color: _ledgerNavy,
    ),
  ),
);

pw.Widget _totalMoneyCell(double amount, {bool strong = false}) => pw.Container(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 6),
  alignment: pw.Alignment.center,
  child: pw.Text(
    _formatAmount(amount),
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      fontSize: 6.7,
      fontWeight: pw.FontWeight.bold,
      color: strong && amount > 0
          ? const PdfColor.fromInt(0xFF9E3D45)
          : _ledgerNavy,
    ),
  ),
);

String _formatAmount(double amount) {
  final isNegative = amount < 0;
  final fixed = amount.abs().toStringAsFixed(2).split('.');
  final whole = fixed.first;
  final fractional = fixed[1].replaceFirst(RegExp(r'0+$'), '');
  final result = StringBuffer();
  if (isNegative) result.write('-');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) result.write(',');
    result.write(whole[i]);
  }
  if (fractional.isNotEmpty) result.write('.$fractional');
  return result.toString();
}
