import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'db_helper.dart' show Certificate;

const String kSchoolNameCert = 'Amaan Public High School';
const String kSchoolTaglineCert = 'Enter to Learn, Leave to Serve';

final PdfColor kCertNavy = PdfColor.fromInt(0xFF16213E);
final PdfColor kCertAccent = PdfColor.fromInt(0xFF397780);
final PdfColor kCertPaleBlue = PdfColor.fromInt(0xFFEAF3FA);
final PdfColor kCertPaper = PdfColor.fromInt(0xFFF9FAFC);
final PdfColor kCertBorder = PdfColor.fromInt(0xFFD8DCE4);

pw.Widget _logoWidget(pw.MemoryImage? logoImage, double size) {
  if (logoImage != null) {
    return pw.SizedBox(
      width: size,
      height: size,
      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
    );
  }
  return pw.Container(
    width: size,
    height: size,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      gradient: pw.LinearGradient(
        colors: [kCertNavy, kCertAccent],
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

pw.Widget _certificateLogoSeal(pw.MemoryImage? logoImage) {
  return pw.Container(
    width: 126,
    height: 126,
    padding: const pw.EdgeInsets.all(5),
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      color: PdfColors.white,
      border: pw.Border.all(color: kCertAccent, width: 1.4),
    ),
    child: pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: kCertPaleBlue, width: 2),
      ),
      child: _logoWidget(logoImage, 106),
    ),
  );
}

/// Places the school name on a centered, shallow upward arch.
double _glyphAdvanceFactor(String character) {
  if (character == ' ') return 0.28;
  if (character == 'I') return 0.28;
  if (character == 'M') return 0.84;
  if (character == 'W') return 0.95;
  if ('BCDHKNU'.contains(character)) return 0.72;
  if ('GOQ'.contains(character)) return 0.77;
  if ('ABPRSVXY'.contains(character)) return 0.67;
  if ('J'.contains(character)) return 0.47;
  if ('EFL'.contains(character)) return 0.56;
  if ('TZ'.contains(character)) return 0.59;
  return 0.65;
}

/// Places each glyph using its approximate width to keep word spacing even.
pw.Widget _curvedSchoolName(String text, {double fontSize = 19}) {
  final chars = text.trim().toUpperCase().split('');
  if (chars.isEmpty) return pw.SizedBox();

  const radius = 230.0;
  const stackWidth = radius * 2;
  const maxArcAngle = 1.3;
  final totalAdvanceFactor = chars.fold<double>(
    0,
    (sum, character) => sum + _glyphAdvanceFactor(character),
  );
  final fittedFontSize = math.min(
    fontSize,
    radius * maxArcAngle / totalAdvanceFactor,
  );
  final totalAdvance = totalAdvanceFactor * fittedFontSize;
  // Keep only the height needed by the curved letters. The old fixed
  // reserve left a large visual gap before the logo seal.
  final stackHeight = radius * (1 - math.cos(maxArcAngle / 2)) + 2;
  var currentAdvance = -totalAdvance / 2;
  final children = <pw.Widget>[];

  for (final character in chars) {
    final glyphWidth = _glyphAdvanceFactor(character) * fittedFontSize;
    final centerOffset = currentAdvance + glyphWidth / 2;
    currentAdvance += glyphWidth;
    if (character.trim().isEmpty) continue;

    final angle = centerOffset / radius;
    children.add(
      pw.Positioned(
        left: stackWidth / 2 + radius * math.sin(angle) - glyphWidth / 2,
        top: radius * (1 - math.cos(angle)),
        child: pw.Transform.rotate(
          angle: -angle,
          child: pw.Text(
            character,
            style: pw.TextStyle(
              fontSize: fittedFontSize,
              fontWeight: pw.FontWeight.bold,
              color: kCertNavy,
            ),
          ),
        ),
      ),
    );
  }

  return pw.SizedBox(
    width: stackWidth,
    height: stackHeight + fittedFontSize,
    child: pw.Stack(children: children),
  );
}

String _formatDate(String isoDate) {
  if (isoDate.isEmpty) return '-';
  try {
    final parts = isoDate.split('-');
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
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return '$day ${months[month - 1]} $year';
  } catch (_) {
    return isoDate;
  }
}

/// Creates a one-page, print-ready bonafide or school leaving certificate.
Future<Uint8List> generateCertificatePdf(
  Certificate certificate, {
  Uint8List? logoBytes,
  String? schoolName,
  String? schoolTagline,
}) async {
  final logoImage = logoBytes == null ? null : pw.MemoryImage(logoBytes);
  final name = schoolName?.trim().isNotEmpty == true
      ? schoolName!.trim()
      : kSchoolNameCert;
  final tagline = schoolTagline?.trim().isNotEmpty == true
      ? schoolTagline!.trim()
      : kSchoolTaglineCert;
  final isBonafide = certificate.certificateType == 'bonafide';

  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) => pw.Container(
        margin: const pw.EdgeInsets.all(16),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: kCertAccent, width: 1.5),
        ),
        child: pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 30, vertical: 18),
          decoration: pw.BoxDecoration(
            color: kCertPaper,
            border: pw.Border.all(color: kCertNavy, width: 1.2),
          ),
          child: pw.Stack(
            children: [
              pw.Positioned.fill(
                child: pw.Center(
                  child: pw.Opacity(
                    opacity: 0.045,
                    child: _logoWidget(logoImage, 300),
                  ),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Center(child: _curvedSchoolName(name, fontSize: 22)),
                  pw.SizedBox(height: 4),
                  pw.Center(child: _certificateLogoSeal(logoImage)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    tagline,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(
                      fontSize: 9.5,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(height: 9),
                  pw.Container(height: 1.4, color: kCertAccent),
                  pw.SizedBox(height: 13),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    decoration: pw.BoxDecoration(
                      color: kCertPaleBlue,
                      border: pw.Border.all(color: kCertAccent, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(height: 0.7, color: kCertAccent),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          child: pw.Text(
                            'SCHOOL LEAVING CERTIFICATE',
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              font: pw.Font.timesBold(),
                              fontSize: 15,
                              color: kCertNavy,
                              letterSpacing: 1.05,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Container(height: 0.7, color: kCertAccent),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 13),
                  pw.Container(
                    width: double.infinity,
                    height: 315,
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 15,
                    ),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: kCertAccent, width: 1),
                      borderRadius: pw.BorderRadius.circular(5),
                    ),
                    child: _leavingCertificateForm(
                      certificate,
                      isBonafide: isBonafide,
                    ),
                  ),
                  pw.Spacer(),
                  pw.SizedBox(height: 15),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _signatureLine('Office'),
                      _signatureLine('Principal'),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return pdf.save();
}

pw.Widget _leavingCertificateForm(
  Certificate certificate, {
  required bool isBonafide,
}) {
  return pw.Column(
    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _certificateInlineField(
        'Admission No.',
        certificate.admissionNo.isEmpty ? '-' : certificate.admissionNo,
      ),
      _certificatePairedFields(
        'Name',
        certificate.studentName,
        "Father's Name",
        certificate.fatherName,
      ),
      _certificatePairedFields(
        'Date of Birth',
        _formatDate(certificate.dob),
        'Admitted Class',
        _classLabel(certificate.admittedClass),
      ),
      _certificatePairedFields(
        'Admission Date',
        certificate.admissionDate.isEmpty
            ? '-'
            : _formatDate(certificate.admissionDate),
        isBonafide ? 'Current Class' : 'Passed Class',
        _classLabel(
          isBonafide ? certificate.classPassed : certificate.lastPassedClass,
        ),
      ),
      _certificateInlineField(
        'Date of Issue',
        _formatDate(certificate.issueDate),
      ),
    ],
  );
}

pw.Widget _certificatePairedFields(
  String firstLabel,
  String firstValue,
  String secondLabel,
  String secondValue,
) {
  return pw.Row(
    children: [
      pw.Expanded(child: _certificateInlineField(firstLabel, firstValue)),
      pw.SizedBox(width: 18),
      pw.Expanded(child: _certificateInlineField(secondLabel, secondValue)),
    ],
  );
}

pw.Widget _certificateInlineField(String label, String value) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: kCertAccent,
        ),
      ),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: kCertBorder, width: 0.7),
            ),
          ),
          child: pw.Text(
            value.trim().isEmpty ? '-' : value,
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              fontSize: 11.2,
              fontWeight: pw.FontWeight.bold,
              color: kCertNavy,
            ),
          ),
        ),
      ),
    ],
  );
}

String _classLabel(String value) =>
    value.trim().isEmpty ? 'Not recorded' : value.trim();

pw.Widget _signatureLine(String label) {
  return pw.Container(
    width: 150,
    padding: const pw.EdgeInsets.only(top: 28),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: kCertBorder, width: 0.8)),
    ),
    alignment: pw.Alignment.center,
    child: pw.Text(
      label,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
  );
}
