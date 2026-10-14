import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/db_helper.dart' show Subject;
import 'package:my_app/dmc_pdf.dart' show StudentResult, assignPositions;

StudentResult _result(
  String name, {
  required double mathematics,
  required double english,
}) {
  return StudentResult(
    studentName: name,
    fatherName: 'Parent',
    studentClass: '5th',
    admissionNo: name,
    subjectMarks: {'Mathematics': mathematics, 'English': english},
    subjectTotals: {'Mathematics': 100, 'English': 100},
  );
}

void main() {
  test(
    'ties share a place and the next distinct total gets the next place',
    () {
      final subjects = [
        Subject(className: '5th', subjectName: 'Mathematics'),
        Subject(className: '5th', subjectName: 'English'),
      ];
      final results = [
        _result('Top', mathematics: 95, english: 95),
        _result('Tie A', mathematics: 90, english: 90),
        _result('Tie B', mathematics: 100, english: 80),
        _result('Tie C', mathematics: 85, english: 95),
        _result('Next', mathematics: 85, english: 85),
        _result('After Next', mathematics: 80, english: 80),
        _result('Failed Paper', mathematics: 32, english: 100),
      ];

      assignPositions(results, subjects);

      expect(results.map((result) => result.position).toList(), [
        1,
        2,
        2,
        2,
        3,
        4,
        0,
      ]);
    },
  );
}
