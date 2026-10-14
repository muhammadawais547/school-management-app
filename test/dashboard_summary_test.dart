import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/db_helper.dart';

void main() {
  test('main dashboard sums all class dues and receipt-month collections', () async {
    final db = await DBHelper.instance.database;

    Future<int> addStudent({
      required String name,
      required String studentClass,
      required double openingBalance,
      required double openingBalancePaid,
    }) {
      return db.insert('students', {
        'fullName': name,
        'fatherName': 'Test Father',
        'dob': '2015-01-01',
        'phone': '',
        'address': '',
        'studentClass': studentClass,
        'openingBalance': openingBalance,
        'openingBalancePaid': openingBalancePaid,
      });
    }

    Future<void> addFee(
      int studentId,
      String month,
      double due,
      double paid, {
      bool generated = true,
    }) async {
      await db.insert('fee_payments', {
        'studentId': studentId,
        'month': month,
        'amountDue': due,
        'amountPaid': paid,
        'isGenerated': generated ? 1 : 0,
      });
    }

    Future<void> addReceipt(int studentId, String date, double amount) async {
      await db.insert('fee_transactions', {
        'studentId': studentId,
        'transactionMonth': date.substring(0, 7),
        'amount': amount,
        'date': date,
      });
    }

    final nurseryId = await addStudent(
      name: 'Nursery student',
      studentClass: 'Nursery',
      openingBalance: 100,
      openingBalancePaid: 20,
    );
    final prepId = await addStudent(
      name: 'Prep student',
      studentClass: 'Prep',
      openingBalance: 50,
      openingBalancePaid: 0,
    );

    await addFee(nurseryId, '2026-09', 1000, 200);
    await addFee(nurseryId, '2026-10', 2000, 500);
    await addFee(nurseryId, '2026-11', 500, 0, generated: false);
    await addFee(prepId, '2026-09', 500, 400);
    await addFee(prepId, '2026-10', 1000, 0);

    await addReceipt(nurseryId, '2026-10-09', 650);
    await addReceipt(prepId, '2026-10-10', 600);
    await addReceipt(prepId, '2026-09-30', 999);

    final summary = await DBHelper.instance.getDashboardSummary(
      onDate: DateTime(2026, 10, 10),
    );

    expect(summary['feesPending'], 3530);
    expect(summary['feesCollected'], 1250);
  });
}
