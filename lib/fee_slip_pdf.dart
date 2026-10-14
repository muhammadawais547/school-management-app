import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// Change this if the school name/motto ever changes.
const String kSchoolName = 'Amaan Public High School';
const String kSchoolTagline = 'Enter to Learn, Leave to Serve';

final PdfColor kFeeNavy = PdfColor.fromInt(0xFF16213E);
final PdfColor kFeeBorder = PdfColor.fromInt(0xFFD9DDE5);

class SlipData {
  final String studentName;
  final String fatherName;
  final String studentClass;
  final String admissionNo;
  final double previousBalance;
  final double currentFee;
  final String currentFeeLabel;
  final String monthLabel;

  SlipData({
    required this.studentName,
    required this.fatherName,
    required this.studentClass,
    required this.admissionNo,
    required this.previousBalance,
    required this.currentFee,
    this.currentFeeLabel = 'Current Month Fee',
    required this.monthLabel,
  });

  double get total => previousBalance + currentFee;
}

/// Builds a PDF with 4 fee slips per A4 page (2x2 grid) to save paper.
/// [logoBytes] is the school's real logo (PNG/JPG). Falls back to a drawn
/// placeholder emblem if not provided.
Future<Uint8List> generateFeeSlipsPdf(
  List<SlipData> slips, {
  Uint8List? logoBytes,
  String? schoolName,
  String? schoolTagline,
}) async {
  final pdf = pw.Document();
  final logoImage = logoBytes != null ? pw.MemoryImage(logoBytes) : null;
  final name = schoolName ?? kSchoolName;
  final tagline = schoolTagline ?? kSchoolTagline;

  for (int i = 0; i < slips.length; i += 4) {
    final end = (i + 4 > slips.length) ? slips.length : i + 4;
    final group = slips.sublist(i, end);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (context) {
          return pw.Column(
            children: [
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: _slipCard(
                        group.isNotEmpty ? group[0] : null,
                        logoImage,
                        name,
                        tagline,
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: _slipCard(
                        group.length > 1 ? group[1] : null,
                        logoImage,
                        name,
                        tagline,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: _slipCard(
                        group.length > 2 ? group[2] : null,
                        logoImage,
                        name,
                        tagline,
                      ),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: _slipCard(
                        group.length > 3 ? group[3] : null,
                        logoImage,
                        name,
                        tagline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  return pdf.save();
}

// A simple drawn emblem, used only if no real logo has been provided.
pw.Widget _logoEmblem() {
  return pw.Container(
    width: 42,
    height: 42,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      color: PdfColors.white,
      border: pw.Border.all(color: kFeeNavy, width: 1.2),
    ),
    alignment: pw.Alignment.center,
    child: pw.Text(
      'A',
      style: pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: kFeeNavy,
      ),
    ),
  );
}

pw.Widget _slipCard(
  SlipData? slip,
  pw.MemoryImage? logoImage,
  String schoolName,
  String schoolTagline,
) {
  if (slip == null) {
    // Keeps the 2x2 grid aligned even if the last page has fewer than 4.
    return pw.Container();
  }

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: kFeeNavy, width: 1.1),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    padding: const pw.EdgeInsets.all(9),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(height: 2, color: kFeeBorder),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            logoImage != null
                ? pw.Container(
                    width: 34,
                    height: 34,
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                : _logoEmblem(),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    schoolName,
                    maxLines: 2,
                    style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight: pw.FontWeight.bold,
                      color: kFeeNavy,
                    ),
                  ),
                  pw.Text(
                    schoolTagline,
                    maxLines: 1,
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey600,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1, color: kFeeBorder),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: kFeeNavy, width: 0.8),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'FEE SLIP',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: kFeeNavy,
                  letterSpacing: 0.8,
                ),
              ),
              pw.Text(
                slip.monthLabel,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: kFeeNavy,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        _infoRow(
          'Admission No',
          slip.admissionNo.isEmpty ? '-' : slip.admissionNo,
        ),
        _infoRow('Student Name', slip.studentName),
        _infoRow("Father's Name", slip.fatherName),
        _infoRow('Class', slip.studentClass),
        pw.SizedBox(height: 3),
        pw.Divider(color: kFeeBorder, height: 1, thickness: 1),
        pw.SizedBox(height: 3),
        _amountRow('Previous Balance', slip.previousBalance),
        _amountRow(slip.currentFeeLabel, slip.currentFee),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: kFeeBorder, width: 0.8),
              bottom: pw.BorderSide(color: kFeeNavy, width: 1.2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PAYABLE',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                  color: kFeeNavy,
                ),
              ),
              pw.Text(
                'Rs ${slip.total.toStringAsFixed(0)}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: kFeeNavy,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Expanded(
          child: pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: kFeeBorder, width: 0.8),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                pw.Text(
                  'PAYMENT RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: kFeeNavy,
                    letterSpacing: 0.4,
                  ),
                ),
                _receiptField('Amount received', prefix: 'Rs'),
                _receiptField('Balance remaining', prefix: 'Rs'),
                pw.Row(
                  children: [
                    pw.Expanded(child: _receiptField('Received by')),
                    pw.SizedBox(width: 10),
                    pw.Expanded(child: _receiptField('Date')),
                  ],
                ),
                _receiptField('Office Stamp'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

// ---- Typography: only two weights used throughout (normal / bold) —
// labels are normal + grey, values are bold + dark, for a clean, consistent look.
pw.Widget _receiptField(String label, {String prefix = ''}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: kFeeNavy,
        ),
      ),
      if (prefix.isNotEmpty) ...[
        pw.Text('$prefix ', style: const pw.TextStyle(fontSize: 8.5)),
      ],
      pw.Expanded(
        child: pw.Container(
          height: 21,
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: kFeeNavy, width: 0.8),
            ),
          ),
        ),
      ),
    ],
  );
}

pw.Widget _infoRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 78,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        pw.Text(
          ': ',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            maxLines: 1,
            style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _amountRow(String label, double value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700),
        ),
        pw.Text(
          'Rs ${value.toStringAsFixed(0)}',
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
        ),
      ],
    ),
  );
}
