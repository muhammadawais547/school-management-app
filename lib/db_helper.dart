import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

// Special "class" used when a student finishes the last class (10th) and
// graduates — keeps all their history intact but moves them out of the
// active class chips shown on Students/Fees/DMC pages.
const String kGraduatedLabel = 'Graduated';

// Used the same way as kGraduatedLabel — a student who has been issued
// their leaving certificate is archived here, out of active class views,
// with their full history preserved.
const String kCertificateIssuedLabel = 'Left School';

// ---------- Standard class list used across the app ----------
const List<String> kClassList = [
  'Nursery',
  'Prep',
  '1st',
  '2nd',
  '3rd',
  '4th',
  '5th',
  '6th',
  '7th',
  '8th',
  '9th',
  '10th',
];

// Fee category options

// ---------- Student model ----------
class Student {
  final int? id;
  final String fullName;
  final String fatherName;
  final String dob; // stored as 'YYYY-MM-DD'
  final String phone;
  final String address;
  final String studentClass;
  final String admittedClass;
  final String admissionDate;
  final String admissionNo;
  final double monthlyFee; // full/standard monthly fee before any concession
  final double concession; // flat Rs amount deducted every month (0 if none)
  final double
  openingBalance; // any dues owed BEFORE this software was used (original amount, never changes)
  final double
  openingBalancePaid; // how much of openingBalance has actually been paid off so far

  Student({
    this.id,
    required this.fullName,
    required this.fatherName,
    required this.dob,
    required this.phone,
    required this.address,
    required this.studentClass,
    this.admittedClass = '',
    this.admissionDate = '',
    this.admissionNo = '',
    this.monthlyFee = 0,
    this.concession = 0,
    this.openingBalance = 0,
    this.openingBalancePaid = 0,
  });

  // The actual amount owed per month after subtracting the concession.
  // Clamped so it never goes below zero even if concession > monthlyFee.
  double get effectiveMonthlyFee {
    final value = monthlyFee - concession;
    return value < 0 ? 0 : value;
  }

  // What's ACTUALLY still owed from the opening balance — this shrinks as
  // payments are applied to it, unlike the original openingBalance which
  // never changes. This is what should be shown/used everywhere, never
  // the raw openingBalance field.
  double get openingBalanceRemaining {
    final value = openingBalance - openingBalancePaid;
    return value < 0 ? 0 : value;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'fatherName': fatherName,
      'dob': dob,
      'phone': phone,
      'address': address,
      'studentClass': studentClass,
      'admittedClass': admittedClass,
      'admissionDate': admissionDate,
      'admissionNo': admissionNo,
      'monthlyFee': monthlyFee,
      'concession': concession,
      'openingBalance': openingBalance,
      'openingBalancePaid': openingBalancePaid,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int?,
      fullName: map['fullName'] as String,
      fatherName: map['fatherName'] as String,
      dob: map['dob'] as String,
      phone: map['phone'] as String,
      address: map['address'] as String,
      studentClass: map['studentClass'] as String,
      admittedClass: (map['admittedClass'] as String?) ?? '',
      admissionDate: (map['admissionDate'] as String?) ?? '',
      admissionNo: (map['admissionNo'] as String?) ?? '',
      monthlyFee: ((map['monthlyFee'] as num?) ?? 0).toDouble(),
      concession: ((map['concession'] as num?) ?? 0).toDouble(),
      openingBalance: ((map['openingBalance'] as num?) ?? 0).toDouble(),
      openingBalancePaid: ((map['openingBalancePaid'] as num?) ?? 0).toDouble(),
    );
  }
}

// ---------- Fee record model (one row = one student's fee for one month) ----------
class FeeRecord {
  final int? id;
  final int studentId;
  final String month; // 'YYYY-MM'
  final double
  amountDue; // this month's due (category-adjusted), NOT including previous balance
  final double amountPaid; // paid so far against this month's row
  final double
  manualAdjustment; // one-time extra concession applied THIS month only
  final double
  concessionSnapshot; // the student's standing concession AT THE TIME this month was generated — frozen, so editing the student later never rewrites past months
  final String
  classSnapshot; // the student's class when this month's fee was generated
  final String? paidDate;
  final String concessionReportMonth;
  final bool isGenerated;
  final double previousBalanceSnapshot;

  FeeRecord({
    this.id,
    required this.studentId,
    required this.month,
    required this.amountDue,
    this.amountPaid = 0,
    this.manualAdjustment = 0,
    this.concessionSnapshot = 0,
    this.classSnapshot = '',
    this.paidDate,
    this.isGenerated = true,
    this.previousBalanceSnapshot = 0,
    String? concessionReportMonth,
  }) : concessionReportMonth = concessionReportMonth ?? month;

  double get balance => amountDue - amountPaid;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'month': month,
      'amountDue': amountDue,
      'amountPaid': amountPaid,
      'manualAdjustment': manualAdjustment,
      'concessionSnapshot': concessionSnapshot,
      'classSnapshot': classSnapshot,
      'paidDate': paidDate,
      'concessionReportMonth': concessionReportMonth,
      'isGenerated': isGenerated ? 1 : 0,
      'previousBalanceSnapshot': previousBalanceSnapshot,
    };
  }

  factory FeeRecord.fromMap(Map<String, dynamic> map) {
    return FeeRecord(
      id: map['id'] as int?,
      studentId: map['studentId'] as int,
      month: map['month'] as String,
      amountDue: (map['amountDue'] as num).toDouble(),
      amountPaid: (map['amountPaid'] as num).toDouble(),
      manualAdjustment: ((map['manualAdjustment'] as num?) ?? 0).toDouble(),
      concessionSnapshot: ((map['concessionSnapshot'] as num?) ?? 0).toDouble(),
      classSnapshot: (map['classSnapshot'] as String?) ?? '',
      paidDate: map['paidDate'] as String?,
      isGenerated: (((map['isGenerated'] as num?) ?? 1).toInt() != 0),
      previousBalanceSnapshot: ((map['previousBalanceSnapshot'] as num?) ?? 0)
          .toDouble(),
      concessionReportMonth:
          (map['concessionReportMonth'] as String?) ?? (map['month'] as String),
    );
  }
}

// One real-money payment event — tracks the REAL calendar month the cash
// actually arrived in, separate from which due-month(s) it settles. This
// is what dashboards sum, so "collected this month" always reflects real
// cash-in-hand for that month, never money that got applied backward to
// clear an older unpaid month.
class FeeTransaction {
  final int? id;
  final int studentId;
  final String transactionMonth; // the month the money was actually received
  final double amount;
  final String date;

  FeeTransaction({
    this.id,
    required this.studentId,
    required this.transactionMonth,
    required this.amount,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'transactionMonth': transactionMonth,
      'amount': amount,
      'date': date,
    };
  }

  factory FeeTransaction.fromMap(Map<String, dynamic> map) {
    return FeeTransaction(
      id: map['id'] as int?,
      studentId: map['studentId'] as int,
      transactionMonth: map['transactionMonth'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
    );
  }
}

// ---------- Teacher model ----------
class Teacher {
  final int? id;
  final String fullName;
  final String phone;
  final String address;
  final String subject;
  final String qualification;
  final double monthlySalary;

  Teacher({
    this.id,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.subject,
    required this.qualification,
    required this.monthlySalary,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'phone': phone,
      'address': address,
      'subject': subject,
      'qualification': qualification,
      'monthlySalary': monthlySalary,
    };
  }

  factory Teacher.fromMap(Map<String, dynamic> map) {
    return Teacher(
      id: map['id'] as int?,
      fullName: map['fullName'] as String,
      phone: map['phone'] as String,
      address: map['address'] as String,
      subject: map['subject'] as String,
      qualification: (map['qualification'] as String?) ?? '',
      monthlySalary: ((map['monthlySalary'] as num?) ?? 0).toDouble(),
    );
  }
}

// ---------- Salary record model (one row = one teacher's salary for one month) ----------
class SalaryRecord {
  final int? id;
  final int teacherId;
  final String month; // 'YYYY-MM'
  final double amountDue;
  final double amountPaid;
  final String? paidDate;

  SalaryRecord({
    this.id,
    required this.teacherId,
    required this.month,
    required this.amountDue,
    this.amountPaid = 0,
    this.paidDate,
  });

  double get balance => amountDue - amountPaid;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'teacherId': teacherId,
      'month': month,
      'amountDue': amountDue,
      'amountPaid': amountPaid,
      'paidDate': paidDate,
    };
  }

  factory SalaryRecord.fromMap(Map<String, dynamic> map) {
    return SalaryRecord(
      id: map['id'] as int?,
      teacherId: map['teacherId'] as int,
      month: map['month'] as String,
      amountDue: (map['amountDue'] as num).toDouble(),
      amountPaid: (map['amountPaid'] as num).toDouble(),
      paidDate: map['paidDate'] as String?,
    );
  }
}

// ---------- Subject model (subjects are defined per class) ----------
class Subject {
  final int? id;
  final String className;
  final String subjectName;
  final double totalMarks;

  /// The pass threshold is always 33% of this subject's configured maximum.
  /// The database column is retained for compatibility with existing files.
  double get passingMarks => totalMarks * 0.33;

  Subject({
    this.id,
    required this.className,
    required this.subjectName,
    this.totalMarks = 100,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'className': className,
      'subjectName': subjectName,
      'totalMarks': totalMarks,
      'passingMarks': passingMarks,
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map) {
    return Subject(
      id: map['id'] as int?,
      className: map['className'] as String,
      subjectName: map['subjectName'] as String,
      totalMarks: ((map['totalMarks'] as num?) ?? 100).toDouble(),
    );
  }
}

// ---------- Mark entry model (one row = one student's marks in one subject, for one exam) ----------
class MarkEntry {
  final int? id;
  final int studentId;
  final int subjectId;
  final String examName;
  final double obtainedMarks;

  MarkEntry({
    this.id,
    required this.studentId,
    required this.subjectId,
    required this.examName,
    required this.obtainedMarks,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'subjectId': subjectId,
      'examName': examName,
      'obtainedMarks': obtainedMarks,
    };
  }

  factory MarkEntry.fromMap(Map<String, dynamic> map) {
    return MarkEntry(
      id: map['id'] as int?,
      studentId: map['studentId'] as int,
      subjectId: map['subjectId'] as int,
      examName: map['examName'] as String,
      obtainedMarks: ((map['obtainedMarks'] as num?) ?? 0).toDouble(),
    );
  }
}

// ---------- Certificate model ----------
// Stores a SNAPSHOT of the student's details at the moment the certificate
// was issued — so reprinting later always shows exactly what was printed
// originally, even if the student record changes or is archived afterward.
class Certificate {
  final int? id;
  final int studentId;
  final String studentName;
  final String fatherName;
  final String admissionNo;
  final String dob;
  final String admissionDate;
  final String
  classPassed; // Legacy name: class printed on the saved certificate.
  final String admittedClass;
  final String lastPassedClass;
  final String issueDate;
  final String certificateType; // 'leaving' or 'bonafide'

  Certificate({
    this.id,
    required this.studentId,
    required this.studentName,
    required this.fatherName,
    required this.admissionNo,
    required this.dob,
    this.admissionDate = '',
    required this.classPassed,
    this.admittedClass = '',
    this.lastPassedClass = '',
    required this.issueDate,
    this.certificateType = 'leaving',
  });

  // Display number shown on the certificate itself, e.g. "SLC-0007" or "BFC-0007".
  String get certificateNumber {
    final prefix = certificateType == 'bonafide' ? 'BFC' : 'SLC';
    return '$prefix-${(id ?? 0).toString().padLeft(4, '0')}';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'studentName': studentName,
      'fatherName': fatherName,
      'admissionNo': admissionNo,
      'dob': dob,
      'admissionDate': admissionDate,
      'classPassed': classPassed,
      'admittedClass': admittedClass,
      'lastPassedClass': lastPassedClass,
      'issueDate': issueDate,
      'certificateType': certificateType,
    };
  }

  factory Certificate.fromMap(Map<String, dynamic> map) {
    return Certificate(
      id: map['id'] as int?,
      studentId: map['studentId'] as int,
      studentName: map['studentName'] as String,
      fatherName: map['fatherName'] as String,
      admissionNo: map['admissionNo'] as String,
      dob: map['dob'] as String,
      admissionDate: (map['admissionDate'] as String?) ?? '',
      classPassed: map['classPassed'] as String,
      admittedClass: (map['admittedClass'] as String?) ?? '',
      lastPassedClass: (map['lastPassedClass'] as String?) ?? '',
      issueDate: map['issueDate'] as String,
      certificateType: (map['certificateType'] as String?) ?? 'leaving',
    );
  }
}

// ---------- Database helper (singleton) ----------
class DBHelper {
  static final DBHelper instance = DBHelper._internal();
  DBHelper._internal();

  static const int _currentDatabaseVersion = 29;
  static const int _maxLocalBackupCount = 10;
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  /// The actual folder the database file lives in — useful for showing
  /// the user exactly where it is, since it isn't always the real
  /// "Documents" folder they'd expect on Windows.
  Future<String> getDatabaseFolderPath() async {
    final db = await database; // ensure the stable database is initialized
    return dirname(db.path);
  }

  Future<String> getDatabaseFilePath() async {
    final db = await database;
    return db.path;
  }

  String _stableDatabaseDirectory() {
    final environment = Platform.environment;
    String? root;
    if (Platform.isWindows) {
      root = environment['LOCALAPPDATA'] ?? environment['APPDATA'];
      root ??= join(
        environment['USERPROFILE'] ?? Directory.current.path,
        'AppData',
        'Local',
      );
    } else if (Platform.isMacOS) {
      root = join(
        environment['HOME'] ?? Directory.current.path,
        'Library',
        'Application Support',
      );
    } else {
      root = environment['XDG_DATA_HOME'];
      root ??= join(
        environment['HOME'] ?? Directory.current.path,
        '.local',
        'share',
      );
    }
    return join(root, 'SchoolManager');
  }

  Future<void> _importLegacyDatabaseIfNeeded(String targetPath) async {
    if (await File(targetPath).exists()) return;

    const legacyRelativePath =
        '.dart_tool/sqflite_common_ffi/databases/school_manager.db';
    final candidates = <String>{};

    void addCandidateForDirectory(Directory directory) {
      candidates.add(
        normalize(absolute(join(directory.path, legacyRelativePath))),
      );
    }

    addCandidateForDirectory(Directory.current);
    var currentDirectory = Directory.current.absolute;
    for (var depth = 0; depth < 10; depth++) {
      addCandidateForDirectory(currentDirectory);
      final parent = currentDirectory.parent;
      if (parent.path == currentDirectory.path) break;
      currentDirectory = parent;
    }

    var executableDirectory = File(Platform.resolvedExecutable).parent.absolute;
    for (var depth = 0; depth < 10; depth++) {
      addCandidateForDirectory(executableDirectory);
      final parent = executableDirectory.parent;
      if (parent.path == executableDirectory.path) break;
      executableDirectory = parent;
    }

    final normalizedTarget = normalize(absolute(targetPath)).toLowerCase();
    for (final candidatePath in candidates) {
      if (candidatePath.toLowerCase() == normalizedTarget) continue;
      final source = File(candidatePath);
      if (!await source.exists() || await source.length() == 0) continue;

      final stagingPath =
          '$targetPath.importing-${DateTime.now().microsecondsSinceEpoch}';
      final stagingFile = File(stagingPath);
      final stagingWalFile = File('$stagingPath-wal');
      try {
        await source.copy(stagingPath);
        final sourceWalFile = File('$candidatePath-wal');
        if (await sourceWalFile.exists() && await sourceWalFile.length() > 0) {
          await sourceWalFile.copy(stagingWalFile.path);
        }
        await stagingFile.rename(targetPath);
        if (await stagingWalFile.exists()) {
          await stagingWalFile.rename('$targetPath-wal');
        }
        final oldBackups = Directory(join(dirname(candidatePath), 'backups'));
        if (await oldBackups.exists()) {
          final newBackups = Directory(join(dirname(targetPath), 'backups'));
          await newBackups.create(recursive: true);
          await for (final entity in oldBackups.list()) {
            if (entity is! File || !entity.path.toLowerCase().endsWith('.db')) {
              continue;
            }
            final backupCopy = File(
              join(newBackups.path, basename(entity.path)),
            );
            if (!await backupCopy.exists()) await entity.copy(backupCopy.path);
          }
        }
        return;
      } catch (_) {
        if (await stagingFile.exists()) await stagingFile.delete();
        if (await stagingWalFile.exists()) await stagingWalFile.delete();
        final incompleteTarget = File(targetPath);
        if (await incompleteTarget.exists()) await incompleteTarget.delete();
        final incompleteWal = File('$targetPath-wal');
        if (await incompleteWal.exists()) await incompleteWal.delete();
        rethrow;
      }
    }
  }

  Future<Database> _initDB() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbFolder = _stableDatabaseDirectory();
    await Directory(dbFolder).create(recursive: true);
    final path = join(dbFolder, 'school_manager.db');
    await _importLegacyDatabaseIfNeeded(path);

    final existingFile = File(path);
    if (await existingFile.exists()) {
      final oldDb = await databaseFactory.openDatabase(path);
      final oldVersion = await oldDb.getVersion();
      await oldDb.close();
      if (oldVersion < _currentDatabaseVersion) {
        final backupsDir = Directory(join(dbFolder, 'backups'));
        await backupsDir.create(recursive: true);
        final now = DateTime.now();
        final stamp =
            '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
            '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
        await existingFile.copy(
          join(backupsDir.path, 'backup_pre_upgrade_$stamp.db'),
        );
      }
    }

    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _currentDatabaseVersion,
        onCreate: (db, version) async {
          await _createTables(db);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_fee_transactions_month_student
            ON fee_transactions(transactionMonth, studentId)
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _createTables(db);
          await _ensureCurrentColumns(db);
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_fee_transactions_month_student
            ON fee_transactions(transactionMonth, studentId)
          ''');
          await _copyLegacyStudentFields(db);
          if (oldVersion < 26) {
            // Rebuild actual receipt-month keys from ISO receipt dates where
            // possible. For older rows with a different date format, preserve
            // their existing transactionMonth rather than dropping the cash.
            await db.execute('''
              UPDATE fee_transactions
              SET transactionMonth = substr(date, 1, 7)
              WHERE length(date) >= 10
                AND substr(date, 5, 1) = '-'
                AND substr(date, 8, 1) = '-'
            ''');
            await db.execute('''
              UPDATE fee_payments
              SET concessionReportMonth = CASE
                WHEN substr(month, 6, 2) = '07'
                  THEN substr(month, 1, 4) || '-06'
                WHEN substr(month, 6, 2) = '09'
                  THEN substr(month, 1, 4) || '-08'
                ELSE month
              END
              WHERE concessionReportMonth > month
            ''');
          }
          if (oldVersion < 27) {
            // Repair receipt-month keys again when moving older local files
            // into the stable per-user data folder. The saved receipt date is
            // the source of truth for where collected cash belongs.
            await db.execute('''
              UPDATE fee_transactions
              SET transactionMonth = substr(date, 1, 7)
              WHERE length(date) >= 10
                AND substr(date, 5, 1) = '-'
                AND substr(date, 8, 1) = '-'
            ''');
          }
          if (oldVersion < 28) {
            // Earlier migration code only repaired concession report months
            // for databases older than v26. A v26 database therefore kept
            // past fee rows incorrectly assigned to a later report month
            // (for example, March concessions appearing in October). Keep
            // true advance concessions assigned to an earlier receipt month,
            // but restore past rows to the month in which the fee was due.
            await db.execute('''
              UPDATE fee_payments
              SET concessionReportMonth = CASE
                WHEN substr(month, 6, 2) = '07'
                  THEN substr(month, 1, 4) || '-06'
                WHEN substr(month, 6, 2) = '09'
                  THEN substr(month, 1, 4) || '-08'
                ELSE month
              END
              WHERE concessionReportMonth > month
                OR (
                  substr(month, 6, 2) = '07'
                  AND concessionReportMonth = month
                )
                OR (
                  substr(month, 6, 2) = '09'
                  AND concessionReportMonth = month
                )
            ''');
          }
          if (oldVersion < 22) {
            // Older app versions could assign a receipt to the fee month
            // selected on the Fees page instead of the month cash arrived.
            // Rebuild the collection month from the saved receipt date.
            await db.execute('''
              UPDATE fee_transactions
              SET transactionMonth = substr(date, 1, 7)
              WHERE length(date) >= 10
                AND substr(date, 5, 1) = '-'
                AND substr(date, 8, 1) = '-'
            ''');
          }
          if (oldVersion < 20) {
            await db.execute('''
              UPDATE fee_payments
              SET concessionReportMonth = month
              WHERE concessionReportMonth = ''
            ''');
          }
          if (oldVersion < 22) {
            // July and September are billed in the June and August cycles.
            // Keep their concession reports on the visible billing month.
            await db.execute('''
              UPDATE fee_payments
              SET concessionReportMonth = substr(month, 1, 4) || '-06'
              WHERE substr(month, 6, 2) = '07'
                AND concessionReportMonth = month
            ''');
            await db.execute('''
              UPDATE fee_payments
              SET concessionReportMonth = substr(month, 1, 4) || '-08'
              WHERE substr(month, 6, 2) = '09'
                AND concessionReportMonth = month
            ''');
          }
          if (oldVersion < 23) {
            // Older versions did not distinguish a generated fee row from a
            // row created only to apply an advance payment. Future rows paid
            // before their due month are treated as advances until staff
            // explicitly generates that billing cycle.
            await db.execute('''
              UPDATE fee_payments
              SET isGenerated = 0
              WHERE month > strftime('%Y-%m', 'now', 'localtime')
                AND paidDate IS NOT NULL
                AND paidDate < (month || '-01')
                AND amountPaid > 0
            ''');
          }
          if (oldVersion < 24) {
            // Keep the receipt-month key consistent with the recorded receipt
            // date, then freeze each generated month's opening arrears using
            // the best remaining-balance data available during this upgrade.
            await db.execute('''
              UPDATE fee_transactions
              SET transactionMonth = substr(date, 1, 7)
              WHERE length(date) >= 10
                AND substr(date, 5, 1) = '-'
                AND substr(date, 8, 1) = '-'
            ''');
            await db.execute('''
              UPDATE fee_payments
              SET previousBalanceSnapshot =
                COALESCE((
                  SELECT MAX(
                    COALESCE(s.openingBalance, 0) -
                    COALESCE(s.openingBalancePaid, 0),
                    0
                  )
                  FROM students s
                  WHERE s.id = fee_payments.studentId
                ), 0)
                + COALESCE((
                  SELECT SUM(
                    CASE
                      WHEN p.amountDue > p.amountPaid
                      THEN p.amountDue - p.amountPaid
                      ELSE 0
                    END
                  )
                  FROM fee_payments p
                  WHERE p.studentId = fee_payments.studentId
                    AND p.month < fee_payments.month
                    AND p.isGenerated = 1
                ), 0)
              WHERE isGenerated = 1
            ''');
          }
        },
      ),
    );
    // Collection totals are derived from the receipt's actual date, not from
    // a cached month label. This index keeps those date-range lookups quick
    // even after many years of locally stored receipts.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_fee_transactions_date_student
      ON fee_transactions(date, studentId)
    ''');
    await _pruneLocalBackupHistory(Directory(join(dbFolder, 'backups')));
    return db;
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fullName TEXT NOT NULL,
        fatherName TEXT NOT NULL,
        dob TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        studentClass TEXT NOT NULL,
        admittedClass TEXT NOT NULL DEFAULT '',
        admissionDate TEXT NOT NULL DEFAULT '',
        admissionNo TEXT NOT NULL DEFAULT '',
        monthlyFee REAL NOT NULL DEFAULT 0,
        concession REAL NOT NULL DEFAULT 0,
        openingBalance REAL NOT NULL DEFAULT 0,
        openingBalancePaid REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fee_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        month TEXT NOT NULL,
        amountDue REAL NOT NULL,
        amountPaid REAL NOT NULL DEFAULT 0,
        manualAdjustment REAL NOT NULL DEFAULT 0,
        concessionSnapshot REAL NOT NULL DEFAULT 0,
        classSnapshot TEXT NOT NULL DEFAULT '',
        concessionReportMonth TEXT NOT NULL DEFAULT '',
        paidDate TEXT,
        isGenerated INTEGER NOT NULL DEFAULT 1,
        previousBalanceSnapshot REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS fee_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        transactionMonth TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS certificates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        studentName TEXT NOT NULL,
        fatherName TEXT NOT NULL,
        admissionNo TEXT NOT NULL,
        dob TEXT NOT NULL,
        admissionDate TEXT NOT NULL DEFAULT '',
        classPassed TEXT NOT NULL,
        admittedClass TEXT NOT NULL DEFAULT '',
        lastPassedClass TEXT NOT NULL DEFAULT '',
        issueDate TEXT NOT NULL,
        certificateType TEXT NOT NULL DEFAULT 'leaving'
      )
    ''');
    // Safe migration for anyone whose certificates table already existed
    // before certificateType was added — SQLite has no "ADD COLUMN IF NOT
    // EXISTS", so we just try it and ignore the error if it's already there.
    try {
      await db.execute(
        "ALTER TABLE certificates ADD COLUMN certificateType TEXT NOT NULL DEFAULT 'leaving'",
      );
    } catch (_) {
      // Column already exists — nothing to do.
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teachers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fullName TEXT NOT NULL,
        phone TEXT NOT NULL,
        address TEXT NOT NULL,
        subject TEXT NOT NULL,
        qualification TEXT NOT NULL DEFAULT '',
        monthlySalary REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salary_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        teacherId INTEGER NOT NULL,
        month TEXT NOT NULL,
        amountDue REAL NOT NULL,
        amountPaid REAL NOT NULL DEFAULT 0,
        paidDate TEXT,
        FOREIGN KEY (teacherId) REFERENCES teachers (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        className TEXT NOT NULL,
        subjectName TEXT NOT NULL,
        totalMarks REAL NOT NULL DEFAULT 100,
        passingMarks REAL NOT NULL DEFAULT 33,
        UNIQUE(className, subjectName)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS marks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        studentId INTEGER NOT NULL,
        subjectId INTEGER NOT NULL,
        examName TEXT NOT NULL,
        obtainedMarks REAL NOT NULL DEFAULT 0,
        UNIQUE(studentId, subjectId, examName),
        FOREIGN KEY (studentId) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (subjectId) REFERENCES subjects (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String declaration,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info("$table")');
    if (columns.any((row) => row['name'] == column)) return;
    await db.execute('ALTER TABLE "$table" ADD COLUMN "$column" $declaration');
  }

  Future<void> _ensureCurrentColumns(Database db) async {
    const columns = <String, Map<String, String>>{
      'students': {
        'fullName': "TEXT NOT NULL DEFAULT ''",
        'fatherName': "TEXT NOT NULL DEFAULT ''",
        'dob': "TEXT NOT NULL DEFAULT ''",
        'phone': "TEXT NOT NULL DEFAULT ''",
        'address': "TEXT NOT NULL DEFAULT ''",
        'studentClass': "TEXT NOT NULL DEFAULT ''",
        'admittedClass': "TEXT NOT NULL DEFAULT ''",
        'admissionDate': "TEXT NOT NULL DEFAULT ''",
        'admissionNo': "TEXT NOT NULL DEFAULT ''",
        'monthlyFee': 'REAL NOT NULL DEFAULT 0',
        'concession': 'REAL NOT NULL DEFAULT 0',
        'openingBalance': 'REAL NOT NULL DEFAULT 0',
        'openingBalancePaid': 'REAL NOT NULL DEFAULT 0',
      },
      'fee_payments': {
        'studentId': 'INTEGER NOT NULL DEFAULT 0',
        'month': "TEXT NOT NULL DEFAULT ''",
        'amountDue': 'REAL NOT NULL DEFAULT 0',
        'amountPaid': 'REAL NOT NULL DEFAULT 0',
        'manualAdjustment': 'REAL NOT NULL DEFAULT 0',
        'concessionSnapshot': 'REAL NOT NULL DEFAULT 0',
        'classSnapshot': "TEXT NOT NULL DEFAULT ''",
        'concessionReportMonth': "TEXT NOT NULL DEFAULT ''",
        'paidDate': 'TEXT',
        'isGenerated': 'INTEGER NOT NULL DEFAULT 1',
        'previousBalanceSnapshot': 'REAL NOT NULL DEFAULT 0',
      },
      'fee_transactions': {
        'studentId': 'INTEGER NOT NULL DEFAULT 0',
        'transactionMonth': "TEXT NOT NULL DEFAULT ''",
        'amount': 'REAL NOT NULL DEFAULT 0',
        'date': "TEXT NOT NULL DEFAULT ''",
      },
      'settings': {
        'key': "TEXT NOT NULL DEFAULT ''",
        'value': "TEXT NOT NULL DEFAULT ''",
      },
      'certificates': {
        'studentId': 'INTEGER NOT NULL DEFAULT 0',
        'studentName': "TEXT NOT NULL DEFAULT ''",
        'fatherName': "TEXT NOT NULL DEFAULT ''",
        'admissionNo': "TEXT NOT NULL DEFAULT ''",
        'dob': "TEXT NOT NULL DEFAULT ''",
        'admissionDate': "TEXT NOT NULL DEFAULT ''",
        'classPassed': "TEXT NOT NULL DEFAULT ''",
        'admittedClass': "TEXT NOT NULL DEFAULT ''",
        'lastPassedClass': "TEXT NOT NULL DEFAULT ''",
        'issueDate': "TEXT NOT NULL DEFAULT ''",
        'certificateType': "TEXT NOT NULL DEFAULT 'leaving'",
      },
      'teachers': {
        'fullName': "TEXT NOT NULL DEFAULT ''",
        'phone': "TEXT NOT NULL DEFAULT ''",
        'address': "TEXT NOT NULL DEFAULT ''",
        'subject': "TEXT NOT NULL DEFAULT ''",
        'qualification': "TEXT NOT NULL DEFAULT ''",
        'monthlySalary': 'REAL NOT NULL DEFAULT 0',
      },
      'salary_payments': {
        'teacherId': 'INTEGER NOT NULL DEFAULT 0',
        'month': "TEXT NOT NULL DEFAULT ''",
        'amountDue': 'REAL NOT NULL DEFAULT 0',
        'amountPaid': 'REAL NOT NULL DEFAULT 0',
        'paidDate': 'TEXT',
      },
      'subjects': {
        'className': "TEXT NOT NULL DEFAULT ''",
        'subjectName': "TEXT NOT NULL DEFAULT ''",
        'totalMarks': 'REAL NOT NULL DEFAULT 100',
        'passingMarks': 'REAL NOT NULL DEFAULT 33',
      },
      'marks': {
        'studentId': 'INTEGER NOT NULL DEFAULT 0',
        'subjectId': 'INTEGER NOT NULL DEFAULT 0',
        'examName': "TEXT NOT NULL DEFAULT ''",
        'obtainedMarks': 'REAL NOT NULL DEFAULT 0',
      },
    };

    for (final table in columns.entries) {
      for (final column in table.value.entries) {
        await _ensureColumn(db, table.key, column.key, column.value);
      }
    }
  }

  Future<void> _copyLegacyStudentFields(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info("students")');
    final names = columns.map((row) => row['name']).whereType<String>().toSet();
    const legacyToCurrent = {
      'name': 'fullName',
      'grade': 'studentClass',
      'parentPhone': 'phone',
      'feeAmount': 'monthlyFee',
    };
    for (final entry in legacyToCurrent.entries) {
      if (names.contains(entry.key)) {
        await db.execute(
          'UPDATE students SET "${entry.value}" = "${entry.key}" '
          'WHERE "${entry.value}" = \'\' OR "${entry.value}" = 0',
        );
      }
    }
  }

  Future<Map<String, Object?>> _includeLegacyStudentColumns(
    Database db,
    Map<String, Object?> values,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info("students")');
    final names = columns.map((row) => row['name']).whereType<String>().toSet();
    final result = Map<String, Object?>.from(values);
    const legacyToCurrent = {
      'name': 'fullName',
      'grade': 'studentClass',
      'parentPhone': 'phone',
      'feeAmount': 'monthlyFee',
    };
    for (final entry in legacyToCurrent.entries) {
      if (names.contains(entry.key)) result[entry.key] = values[entry.value];
    }
    return result;
  }

  // ---------------- Student CRUD ----------------

  Future<int> addStudent(Student student) async {
    final db = await database;
    final values = await _includeLegacyStudentColumns(db, student.toMap());
    return await db.insert('students', values);
  }

  Future<List<Student>> getAllStudents() async {
    final db = await database;
    final maps = await db.query('students', orderBy: 'fullName ASC');
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  Future<Student?> getStudentById(int id) async {
    final db = await database;
    final maps = await db.query('students', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Student.fromMap(maps.first);
  }

  /// All fee records for [month] across every class — used for dashboard totals.
  Future<List<FeeRecord>> getAllFeeRecordsForMonth(String month) async {
    final db = await database;
    final maps = await db.query(
      'fee_payments',
      where: 'month = ?',
      whereArgs: [month],
    );
    return maps.map((m) => FeeRecord.fromMap(m)).toList();
  }

  Future<List<Student>> getStudentsByClass(String studentClass) async {
    final db = await database;
    final maps = await db.query(
      'students',
      where: 'studentClass = ?',
      whereArgs: [studentClass],
      orderBy: 'fullName ASC',
    );
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  /// Students who belonged to [studentClass] for [month]. Once a fee month
  /// has been generated, its class is frozen with the fee row so a later
  /// promotion does not move historical fees to a different class dashboard.
  /// If that month has no fee row yet, the student's current class is used.
  /// By default archived students are omitted from visible lists. Pass
  /// [includeArchived] only when calculating historical class accounting totals.
  Future<List<Student>> getStudentsByClassForMonth(
    String studentClass,
    String month, {
    bool includeArchived = false,
  }) async {
    final db = await database;
    final archiveFilter = includeArchived
        ? ''
        : 'AND s.studentClass NOT IN (?, ?)';
    final queryArgs = <Object?>[month, studentClass];
    if (!includeArchived) {
      queryArgs.addAll([kCertificateIssuedLabel, kGraduatedLabel]);
    }
    final rows = await db.rawQuery('''
      SELECT s.*,
             COALESCE(NULLIF(p.classSnapshot, ''), s.studentClass) AS monthClass
      FROM students s
      LEFT JOIN fee_payments p
        ON p.id = (
          SELECT MAX(p2.id)
          FROM fee_payments p2
          WHERE p2.studentId = s.id AND p2.month = ?
        )
      WHERE COALESCE(NULLIF(p.classSnapshot, ''), s.studentClass) = ?
        $archiveFilter
      ORDER BY s.fullName ASC
      ''', queryArgs);
    return rows.map((row) {
      final studentMap = Map<String, dynamic>.from(row);
      studentMap['studentClass'] = row['monthClass'] as String? ?? '';
      return Student.fromMap(studentMap);
    }).toList();
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      // Foreign-key enforcement is not enabled on every existing school DB,
      // so remove linked records explicitly before deleting the student.
      await txn.delete('fee_payments', where: 'studentId = ?', whereArgs: [id]);
      await txn.delete(
        'fee_transactions',
        where: 'studentId = ?',
        whereArgs: [id],
      );
      await txn.delete('marks', where: 'studentId = ?', whereArgs: [id]);
      await txn.delete('certificates', where: 'studentId = ?', whereArgs: [id]);
      return txn.delete('students', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Read-only history for an archived student. These queries reuse the
  /// existing fee and result rows; they do not duplicate archived data.
  Future<List<Map<String, Object?>>> getStudentFeeHistory(int studentId) async {
    final db = await database;
    return db.query(
      'fee_payments',
      where: 'studentId = ?',
      whereArgs: [studentId],
      orderBy: 'month DESC',
    );
  }

  Future<List<Map<String, Object?>>> getStudentReceiptHistory(
    int studentId,
  ) async {
    final db = await database;
    return db.query(
      'fee_transactions',
      where: 'studentId = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getStudentResultHistory(
    int studentId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT m.examName, m.obtainedMarks, s.className, s.subjectName,
             s.totalMarks, s.passingMarks
      FROM marks m
      LEFT JOIN subjects s ON s.id = m.subjectId
      WHERE m.studentId = ?
      ORDER BY m.examName DESC, s.className ASC, s.subjectName ASC
      ''',
      [studentId],
    );
  }

  /// Bulk-updates studentClass for the given student ids — used by the
  /// "Promote Students" tool. Fee and marks history stay linked to the
  /// same student id, so nothing is lost by moving class; any unpaid
  /// balance automatically carries forward via getPreviousBalance.
  Future<void> promoteStudents(List<int> studentIds, String targetClass) async {
    if (studentIds.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final id in studentIds) {
        await txn.update(
          'students',
          {'studentClass': targetClass},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<int> updateStudent(Student student) async {
    final db = await database;
    final values = await _includeLegacyStudentColumns(db, student.toMap());
    return await db.update(
      'students',
      values,
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }

  /// Checks whether [admissionNo] is already used by a DIFFERENT student.
  /// Pass [excludeId] (the student's own id) when editing, so a student
  /// isn't flagged as clashing with their own existing number.
  Future<bool> isAdmissionNoTaken(String admissionNo, {int? excludeId}) async {
    final trimmed = admissionNo.trim();
    if (trimmed.isEmpty) return false;
    final db = await database;
    final maps = await db.query(
      'students',
      where: 'admissionNo = ?',
      whereArgs: [trimmed],
    );
    if (maps.isEmpty) return false;
    if (excludeId != null) {
      return maps.any((m) => (m['id'] as int) != excludeId);
    }
    return true;
  }

  // ---------------- Fee CRUD / logic ----------------

  /// Creates a fee row for [student] in [month] (format 'YYYY-MM') if one
  /// doesn't exist yet, using the student's CURRENT monthlyFee/concession
  /// at that moment. If a row already exists, it is left completely
  /// untouched — a generated month is a locked historical record.
  ///
  /// This is deliberate: editing a student's fee or concession later only
  /// affects months generated AFTER the edit, never months already
  /// generated (even if unpaid). To correct an already-generated month,
  /// use applyExtraConcession for a one-off adjustment to that specific
  /// month instead. amountPaid is, as always, never touched here.
  Future<void> ensureFeeRecordExists(
    Student student,
    String month, {
    bool generated = false,
    double? previousBalanceSnapshot,
  }) async {
    final db = await database;
    // Use the latest saved student details for a new month. Existing fee rows
    // below remain untouched, so a fee edit cannot rewrite generated months.
    final currentStudent = await getStudentById(student.id!) ?? student;
    final existing = await db.query(
      'fee_payments',
      where: 'studentId = ? AND month = ?',
      whereArgs: [student.id, month],
    );
    if (existing.isEmpty) {
      final record = FeeRecord(
        studentId: currentStudent.id!,
        month: month,
        amountDue: currentStudent.effectiveMonthlyFee,
        amountPaid: 0,
        manualAdjustment: 0,
        concessionSnapshot: currentStudent.concession,
        classSnapshot: currentStudent.studentClass,
        concessionReportMonth: _billingMonthForFeeMonth(month),
        isGenerated: generated,
        previousBalanceSnapshot: previousBalanceSnapshot ?? 0,
      );
      await db.insert('fee_payments', record.toMap());
    } else if (generated &&
        (((existing.first['isGenerated'] as num?) ?? 1).toInt() == 0)) {
      // An advance payment may have created this row early. Generating the
      // billing cycle later formalizes it without changing its frozen amounts.
      await db.update(
        'fee_payments',
        {
          'isGenerated': 1,
          'previousBalanceSnapshot': previousBalanceSnapshot ?? 0,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  /// Generates fee rows for every student in [studentClass] for [month].
  /// Also re-syncs any that already existed (see ensureFeeRecordExists).
  Future<void> generateFeesForClassMonth(
    String studentClass,
    String month,
  ) async {
    final students = await getStudentsByClass(studentClass);
    for (final s in students) {
      final previousBalance =
          s.openingBalanceRemaining + await getPreviousBalance(s.id!, month);
      await ensureFeeRecordExists(
        s,
        month,
        generated: true,
        previousBalanceSnapshot: previousBalance,
      );
    }
  }

  /// Generates a single student's fee row and freezes the opening balance.
  /// This is used when a payment or concession is entered before the class
  /// cycle has been generated, without generating fees for every classmate.
  Future<void> generateFeeForStudentMonth(Student student, String month) async {
    final previousBalance =
        student.openingBalanceRemaining +
        await getPreviousBalance(student.id!, month);
    await ensureFeeRecordExists(
      student,
      month,
      generated: true,
      previousBalanceSnapshot: previousBalance,
    );
  }

  /// Records one future month through the same transaction and concession
  /// rules as a multi-month advance payment.
  Future<double> payMonthInAdvance(Student student, String month) async {
    return payMonthsInAdvanceWithTransaction(student, [month]);
  }

  /// Pays several future months in advance in one go (e.g. paying
  /// November and December while looking at October). Each monthly fee row
  /// is still separate, but the transaction and concessions are reported
  /// against the real calendar month when the cash is collected.
  Future<double> payMonthsInAdvanceWithTransaction(
    Student student,
    List<String> months, {
    DateTime? receivedAt,
  }) async {
    final db = await database;
    final receiptDate = receivedAt ?? DateTime.now();
    final today = receiptDate.toIso8601String().split('T').first;
    final transactionMonth = _monthKeyFor(receiptDate);
    double total = 0;
    for (final month in months) {
      await ensureFeeRecordExists(student, month);
      final record = await getFeeRecord(student.id!, month);
      if (record == null) continue;
      final owed = record.amountDue - record.amountPaid;
      if (owed <= 0) continue;
      total += owed;
      await db.update(
        'fee_payments',
        {
          'amountPaid': record.amountDue,
          'concessionReportMonth': transactionMonth,
          'paidDate': today,
        },
        where: 'id = ?',
        whereArgs: [record.id],
      );
    }
    if (total > 0) {
      await db.insert(
        'fee_transactions',
        FeeTransaction(
          studentId: student.id!,
          transactionMonth: transactionMonth,
          amount: total,
          date: today,
        ).toMap(),
      );
    }
    return total;
  }

  /// Applies a one-off extra concession to a specific month's fee record
  /// (e.g. "give this family Rs 200 off just for this month" at the moment
  /// a payment is being recorded). This is tracked separately from the
  /// student's standard fee, so it survives future syncs instead of being
  /// silently overwritten. amountPaid is untouched.
  Future<void> applyExtraConcession(int feeRecordId, double amount) async {
    if (!amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'must be a finite number');
    }
    if (amount <= 0) return;
    final db = await database;
    final maps = await db.query(
      'fee_payments',
      where: 'id = ?',
      whereArgs: [feeRecordId],
    );
    if (maps.isEmpty) return;
    final current = FeeRecord.fromMap(maps.first);
    // Never let a concession reduce the due below money already paid. Only
    // the discount that can still reduce an outstanding balance is reported.
    final outstanding = current.amountDue - current.amountPaid;
    final appliedAmount = amount < outstanding ? amount : outstanding;
    if (appliedAmount <= 0) return;
    final newAdjustment = current.manualAdjustment + appliedAmount;
    final newDue = current.amountDue - appliedAmount;
    await db.update(
      'fee_payments',
      {'manualAdjustment': newAdjustment, 'amountDue': newDue < 0 ? 0 : newDue},
      where: 'id = ?',
      whereArgs: [feeRecordId],
    );
  }

  /// Fee row for one student in one month, or null if not generated yet.
  Future<FeeRecord?> getFeeRecord(int studentId, String month) async {
    final db = await database;
    final maps = await db.query(
      'fee_payments',
      where: 'studentId = ? AND month = ?',
      whereArgs: [studentId, month],
    );
    if (maps.isEmpty) return null;
    return FeeRecord.fromMap(maps.first);
  }

  /// Sum of unpaid balances from all months strictly before [month].
  /// This is how unpaid dues automatically carry forward — no duplication.
  Future<double> getPreviousBalance(int studentId, String month) async {
    final db = await database;
    final maps = await db.query(
      'fee_payments',
      where: 'studentId = ? AND month < ? AND isGenerated = 1',
      whereArgs: [studentId, month],
    );
    double total = 0;
    for (final m in maps) {
      final due = (m['amountDue'] as num).toDouble();
      final paid = (m['amountPaid'] as num).toDouble();
      final unpaid = due - paid;
      if (unpaid > 0) total += unpaid;
    }
    return total;
  }

  /// Sum of concessions reported in [month]. A month paid in advance moves
  /// its concession reporting to the month when cash was received, so it is
  /// counted once in the collection month and not again in the future month.
  Future<double> getFeeConcessionTotalForMonth(
    String month, {
    List<int>? studentIds,
    List<String>? reportMonths,
  }) async {
    final db = await database;
    final months = (reportMonths ?? [month]).toSet().toList()..sort();
    if (months.isEmpty || (studentIds != null && studentIds.isEmpty)) return 0;

    // The June cycle includes July and the August cycle includes September.
    // Extra concessions stay on the exact fee month they changed, while
    // standing concessions can move to the real receipt month for an advance.
    final dueMonthsForAdjustments = <String>{...months};
    for (final reportMonth in months) {
      if (reportMonth.endsWith('-06') || reportMonth.endsWith('-08')) {
        dueMonthsForAdjustments.add(_nextMonthKey(reportMonth));
      }
    }
    final dueMonths = dueMonthsForAdjustments.toList()..sort();
    final reportPlaceholders = List.filled(months.length, '?').join(',');
    final duePlaceholders = List.filled(dueMonths.length, '?').join(',');
    final args = <Object?>[...months, ...dueMonths];
    var studentFilter = '';
    if (studentIds != null) {
      final studentPlaceholders = List.filled(studentIds.length, '?').join(',');
      studentFilter = ' AND studentId IN ($studentPlaceholders)';
      args.addAll(studentIds);
    }

    // Read only relevant fee rows, then classify each concession once. This
    // keeps one-off concessions on their due month and counts advance-paid
    // standing concessions in the cash-receipt month only.
    final rows = await db.query(
      'fee_payments',
      where:
          '(concessionReportMonth IN ($reportPlaceholders) OR month IN ($duePlaceholders))$studentFilter',
      whereArgs: args,
    );
    double standingTotal = 0;
    double extraTotal = 0;
    for (final row in rows) {
      final record = FeeRecord.fromMap(row);
      if (months.contains(record.concessionReportMonth)) {
        final paidInReportMonth =
            record.amountPaid > 0 &&
            record.amountPaid >= record.amountDue &&
            record.paidDate != null &&
            record.paidDate!.length >= 7 &&
            record.paidDate!.substring(0, 7) == record.concessionReportMonth;
        if (record.isGenerated || paidInReportMonth) {
          standingTotal += record.concessionSnapshot;
        }
      }
      if (dueMonths.contains(record.month) && record.isGenerated) {
        extraTotal += record.manualAdjustment;
      }
    }
    return standingTotal + extraTotal;
  }

  /// Records a real payment of [amount], made while looking at [viewedMonth].
  ///
  /// This is the core of correct multi-month behavior:
  /// 1. Logs a transaction against the actual calendar month — this is what
  ///    dashboards sum, so "collected" always reflects when the cash arrived,
  ///    never money that got applied backward to clear an older due.
  /// 2. Applies the money FIFO: oldest unpaid month first, up through
  ///    [viewedMonth] — so paying enough in October to also cover an
  ///    unpaid September correctly marks September Paid too, without
  ///    touching September's own dashboard figures.
  /// 3. Any money left over after everything up to [viewedMonth] is fully
  ///    paid becomes an advance: it automatically generates and marks
  ///    future months Paid (using the CURRENT effectiveMonthlyFee for
  ///    each, so concession is honored) — those future months still show
  ///    Paid, but their own dashboards stay untouched, since no
  ///    transaction is logged against them.
  Future<void> recordPaymentWithWaterfall({
    required Student student,
    required String viewedMonth,
    required double amount,
    DateTime? receivedAt,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'must be a finite number greater than zero',
      );
    }
    final db = await database;
    final receiptDate = receivedAt ?? DateTime.now();
    final today = receiptDate.toIso8601String().split('T').first;
    final transactionMonth = _monthKeyFor(receiptDate);

    // Log the FULL amount against the month it was actually received in —
    // this is exactly what that month's dashboard shows. It doesn't matter
    // whether the money ends up settling an old unpaid month or getting
    // held as advance credit for future months; the cash arrived THIS
    // month, so it counts THIS month, full stop.
    await db.insert(
      'fee_transactions',
      FeeTransaction(
        studentId: student.id!,
        transactionMonth: transactionMonth,
        amount: amount,
        date: today,
      ).toMap(),
    );

    double remaining = amount;

    // Pay off the opening balance FIRST — it's older debt than any
    // generated month, so it should be settled before September, before
    // October, before anything. This is what makes it actually shrink and
    // eventually disappear, instead of being added to every month forever.
    // Always re-read the student fresh, in case it's changed since [student]
    // was loaded.
    final freshStudent = await getStudentById(student.id!) ?? student;
    final openingRemaining = freshStudent.openingBalanceRemaining;
    if (openingRemaining > 0 && remaining > 0) {
      final apply = remaining >= openingRemaining
          ? openingRemaining
          : remaining;
      await db.update(
        'students',
        {'openingBalancePaid': freshStudent.openingBalancePaid + apply},
        where: 'id = ?',
        whereArgs: [student.id],
      );
      remaining -= apply;
    }

    // Waterfall across every existing record up to and including the
    // viewed month, oldest first — this only affects each month's own
    // Paid/Unpaid STATUS, never a dashboard figure.
    final upToRows = await db.query(
      'fee_payments',
      where: 'studentId = ? AND month <= ?',
      whereArgs: [student.id, viewedMonth],
      orderBy: 'month ASC',
    );
    for (final row in upToRows) {
      if (remaining <= 0) break;
      final record = FeeRecord.fromMap(row);
      final owed = record.amountDue - record.amountPaid;
      if (owed <= 0) continue;
      final apply = remaining >= owed ? owed : remaining;
      await db.update(
        'fee_payments',
        {'amountPaid': record.amountPaid + apply, 'paidDate': today},
        where: 'id = ?',
        whereArgs: [record.id],
      );
      remaining -= apply;
    }

    // Any money left over is a pure advance against FUTURE months — it
    // marks them Paid automatically (status only). No transaction is
    // logged for those future months, since the cash was already counted
    // above against the month it was actually received in.
    String cursor = _nextMonthKey(viewedMonth);
    for (int i = 0; i < 24 && remaining > 0; i++) {
      await ensureFeeRecordExists(student, cursor);
      final rec = await getFeeRecord(student.id!, cursor);
      if (rec == null) break;
      final owed = rec.amountDue - rec.amountPaid;
      if (owed > 0) {
        final apply = remaining >= owed ? owed : remaining;
        final updates = <String, Object>{
          'amountPaid': rec.amountPaid + apply,
          'paidDate': today,
        };
        if (apply >= owed) {
          updates['concessionReportMonth'] = transactionMonth;
        }
        await db.update(
          'fee_payments',
          updates,
          where: 'id = ?',
          whereArgs: [rec.id],
        );
        remaining -= apply;
      }
      cursor = _nextMonthKey(cursor);
    }
  }

  String _nextMonthKey(String monthKey) {
    final parts = monthKey.split('-');
    int y = int.parse(parts[0]);
    int m = int.parse(parts[1]) + 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    return '$y-${m.toString().padLeft(2, '0')}';
  }

  String _billingMonthForFeeMonth(String monthKey) {
    final parts = monthKey.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    if (month == 7) return '$year-06';
    if (month == 9) return '$year-08';
    return monthKey;
  }

  String _monthKeyFor(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  /// Returns inclusive-start/exclusive-end ISO date bounds for one calendar
  /// month. Receipt dates are the source of truth for cash reporting; the
  /// transactionMonth column is retained for compatibility with older data.
  List<String> _receiptDateRangeForMonth(String monthKey) {
    if (monthKey.length != 7 || monthKey[4] != '-') {
      throw ArgumentError.value(monthKey, 'monthKey', 'Expected YYYY-MM');
    }
    final year = int.tryParse(monthKey.substring(0, 4));
    final month = int.tryParse(monthKey.substring(5, 7));
    if (year == null || month == null || month < 1 || month > 12) {
      throw ArgumentError.value(monthKey, 'monthKey', 'Expected YYYY-MM');
    }
    final nextMonth = DateTime(year, month + 1);
    String format(DateTime date) =>
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-01';
    return [format(DateTime(year, month)), format(nextMonth)];
  }

  /// Adds [amount] directly to one specific record's amountPaid, with no
  /// waterfall and no transaction logging. Kept for internal use only
  /// (e.g. teacher salaries use the equivalent simple pattern) — for
  /// student fee payments, always use recordPaymentWithWaterfall instead.
  Future<void> recordPayment(int feeRecordId, double amount) async {
    final db = await database;
    final maps = await db.query(
      'fee_payments',
      where: 'id = ?',
      whereArgs: [feeRecordId],
    );
    if (maps.isEmpty) return;
    final current = FeeRecord.fromMap(maps.first);
    final newPaid = current.amountPaid + amount;
    await db.update(
      'fee_payments',
      {
        'amountPaid': newPaid,
        'paidDate': DateTime.now().toIso8601String().split('T').first,
      },
      where: 'id = ?',
      whereArgs: [feeRecordId],
    );
  }

  /// Sum of real cash received for [month] across the given [studentIds]
  /// (or all students if null) — this is what dashboards should show as
  /// "Collected," since it reflects real money-in-hand for that month,
  /// unaffected by which older/newer due-months it was used to settle.
  Future<double> getTransactionsTotalForMonth(
    String month, {
    List<int>? studentIds,
  }) async {
    final db = await database;
    if (studentIds != null && studentIds.isEmpty) return 0;
    final args = <Object?>[..._receiptDateRangeForMonth(month)];
    var studentFilter = '';
    if (studentIds != null) {
      final placeholders = List.filled(studentIds.length, '?').join(',');
      studentFilter = ' AND studentId IN ($placeholders)';
      args.addAll(studentIds);
    }
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS total
      FROM fee_transactions
      WHERE date >= ? AND date < ?$studentFilter
      ''', args);
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  /// Lists receipts whose actual receipt dates fall within [months].
  /// Used by the Fees page's collected card so staff can reconcile its total.
  Future<List<Map<String, Object?>>> getTransactionsForMonths(
    List<String> months, {
    List<int>? studentIds,
  }) async {
    if (months.isEmpty || (studentIds != null && studentIds.isEmpty)) return [];
    final db = await database;
    final uniqueMonths = months.toSet().toList()..sort();
    final dateRanges = uniqueMonths.map(_receiptDateRangeForMonth).toList();
    final dateClauses = List.filled(
      dateRanges.length,
      '(ft.date >= ? AND ft.date < ?)',
    ).join(' OR ');
    final args = <Object?>[];
    for (final range in dateRanges) {
      args.addAll(range);
    }
    var studentFilter = '';
    if (studentIds != null) {
      final placeholders = List.filled(studentIds.length, '?').join(',');
      studentFilter = ' AND ft.studentId IN ($placeholders)';
      args.addAll(studentIds);
    }
    return db.rawQuery('''
      SELECT ft.id, ft.amount, ft.date, s.fullName, s.studentClass,
             (
               SELECT COUNT(*)
               FROM fee_transactions same_day
               WHERE same_day.studentId = ft.studentId
                 AND same_day.date = ft.date
             ) AS sameDayReceiptCount
      FROM fee_transactions ft
      JOIN students s ON s.id = ft.studentId
      WHERE ($dateClauses)$studentFilter
      ORDER BY ft.date DESC, ft.id DESC
      ''', args);
  }

  /// Corrects the date on an existing receipt while keeping its amount and
  /// fee allocations intact. The receipt month is always derived from date.
  Future<void> updateFeeTransactionReceiptDate(
    int transactionId,
    DateTime receiptDate,
  ) async {
    final db = await database;
    final date = receiptDate.toIso8601String().split('T').first;
    await db.transaction((txn) async {
      final matches = await txn.query(
        'fee_transactions',
        columns: ['studentId', 'date'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1,
      );
      if (matches.isEmpty) {
        throw StateError(
          'This receipt no longer exists. Refresh and try again.',
        );
      }
      final studentId = matches.single['studentId'] as int;
      final oldDate = matches.single['date'] as String;
      final oldMonth = oldDate.length >= 7 ? oldDate.substring(0, 7) : '';
      final sameDay = await txn.rawQuery(
        'SELECT COUNT(*) AS count FROM fee_transactions WHERE studentId = ? AND date = ?',
        [studentId, oldDate],
      );
      final sameDayCount = (sameDay.first['count'] as num).toInt();
      if (sameDayCount != 1) {
        throw StateError(
          'This student has multiple receipts on that date. They cannot be safely edited one at a time.',
        );
      }

      final newMonth = _monthKeyFor(receiptDate);
      await txn.update(
        'fee_transactions',
        {'date': date, 'transactionMonth': newMonth},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      // Keep the related fee payment dates and advance-concession reporting
      // aligned with the corrected receipt date. The uniqueness check above
      // makes the student's date-based fee rows unambiguous.
      await txn.update(
        'fee_payments',
        {'paidDate': date},
        where: 'studentId = ? AND paidDate = ? AND amountPaid > 0',
        whereArgs: [studentId, oldDate],
      );
      if (oldMonth.isNotEmpty) {
        await txn.update(
          'fee_payments',
          {'concessionReportMonth': newMonth},
          where: '''
            studentId = ? AND month > ? AND concessionReportMonth = ?
            AND amountPaid > 0
          ''',
          whereArgs: [studentId, oldMonth, oldMonth],
        );
      }
    });
  }

  // ---------------- Teacher CRUD ----------------

  Future<int> addTeacher(Teacher teacher) async {
    if (!teacher.monthlySalary.isFinite || teacher.monthlySalary < 0) {
      throw ArgumentError(
        'Teacher salary must be a finite amount of zero or more.',
      );
    }
    final db = await database;
    return await db.insert('teachers', teacher.toMap());
  }

  Future<List<Teacher>> getAllTeachers() async {
    final db = await database;
    final maps = await db.query('teachers', orderBy: 'fullName ASC');
    return maps.map((m) => Teacher.fromMap(m)).toList();
  }

  Future<int> deleteTeacher(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete(
        'salary_payments',
        where: 'teacherId = ?',
        whereArgs: [id],
      );
      return txn.delete('teachers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> updateTeacher(Teacher teacher) async {
    if (!teacher.monthlySalary.isFinite || teacher.monthlySalary < 0) {
      throw ArgumentError(
        'Teacher salary must be a finite amount of zero or more.',
      );
    }
    final db = await database;
    return await db.update(
      'teachers',
      teacher.toMap(),
      where: 'id = ?',
      whereArgs: [teacher.id],
    );
  }

  // ---------------- Salary CRUD / logic (mirrors fee logic) ----------------

  Future<void> ensureSalaryRecordExists(Teacher teacher, String month) async {
    final db = await database;
    await db.transaction((txn) async {
      final existing = await txn.query(
        'salary_payments',
        where: 'teacherId = ? AND month = ?',
        whereArgs: [teacher.id, month],
        limit: 1,
      );
      if (existing.isNotEmpty) return;

      final record = SalaryRecord(
        teacherId: teacher.id!,
        month: month,
        amountDue: teacher.monthlySalary,
        amountPaid: 0,
      );
      await txn.insert('salary_payments', record.toMap());
    });
  }

  Future<void> generateSalariesForMonth(String month) async {
    final teachers = await getAllTeachers();
    for (final t in teachers) {
      await ensureSalaryRecordExists(t, month);
    }
  }

  Future<SalaryRecord?> getSalaryRecord(int teacherId, String month) async {
    final db = await database;
    final maps = await db.query(
      'salary_payments',
      where: 'teacherId = ? AND month = ?',
      whereArgs: [teacherId, month],
    );
    if (maps.isEmpty) return null;
    return SalaryRecord.fromMap(maps.first);
  }

  /// Sum of unpaid salary from all months strictly before [month].
  Future<double> getPreviousSalaryBalance(int teacherId, String month) async {
    final db = await database;
    final maps = await db.query(
      'salary_payments',
      where: 'teacherId = ? AND month < ?',
      whereArgs: [teacherId, month],
    );
    double total = 0;
    for (final m in maps) {
      final due = (m['amountDue'] as num).toDouble();
      final paid = (m['amountPaid'] as num).toDouble();
      total += (due - paid);
    }
    return total;
  }

  Future<void> recordSalaryPayment(int salaryRecordId, double amount) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError(
        'Payment amount must be a finite number greater than zero.',
      );
    }
    final db = await database;
    final paidDate = DateTime.now().toIso8601String().split('T').first;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'salary_payments',
        where: 'id = ?',
        whereArgs: [salaryRecordId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError(
          'The salary record no longer exists. Reload and try again.',
        );
      }

      final row = rows.first;
      final teacherId = row['teacherId'] as int;
      final month = row['month'] as String;
      final previousRows = await txn.query(
        'salary_payments',
        columns: ['amountDue', 'amountPaid'],
        where: 'teacherId = ? AND month < ?',
        whereArgs: [teacherId, month],
      );
      final previousBalance = previousRows.fold<double>(0, (sum, previous) {
        final due = (previous['amountDue'] as num).toDouble();
        final paid = (previous['amountPaid'] as num).toDouble();
        return sum + due - paid;
      });
      final thisMonthDue = (row['amountDue'] as num).toDouble();
      final alreadyPaid = (row['amountPaid'] as num).toDouble();
      final totalBalance = thisMonthDue + previousBalance - alreadyPaid;
      if (amount > totalBalance + 0.000001) {
        throw ArgumentError(
          'Payment cannot exceed the total remaining salary balance.',
        );
      }

      await txn.update(
        'salary_payments',
        {'amountPaid': alreadyPaid + amount, 'paidDate': paidDate},
        where: 'id = ?',
        whereArgs: [salaryRecordId],
      );
    });
  }

  // ---------------- Dashboard summary ----------------

  /// Real counts + this-month fee totals for the main Dashboard's KPI cards.
  Future<Map<String, dynamic>> getDashboardSummary({DateTime? onDate}) async {
    final db = await database;
    final studentCountRows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM students WHERE studentClass NOT IN (?, ?)',
      [kCertificateIssuedLabel, kGraduatedLabel],
    );
    final teacherCountRows = await db.rawQuery(
      'SELECT COUNT(*) as c FROM teachers',
    );

    final now = onDate ?? DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // "Collected" = cash received THIS calendar month, from the transaction
    // ledger. Older dues and future prepayments are attributed to the month
    // the cash arrived, so this dashboard resets cleanly each month.
    final collected = await getTransactionsTotalForMonth(monthKey);

    // Outstanding is the sum of every active student's remaining opening
    // balance, all generated earlier-month balances, and the current month's
    // due (when generated). Keep the per-student balances inside correlated
    // subqueries, then SUM them across the whole school. Using MAX here would
    // report only the largest student's balance instead of the school total.
    final pendingRows = await db.rawQuery(
      '''
      SELECT COALESCE(
        SUM(
          CASE
            WHEN COALESCE(s.openingBalance, 0) > COALESCE(s.openingBalancePaid, 0)
              THEN COALESCE(s.openingBalance, 0) - COALESCE(s.openingBalancePaid, 0)
            ELSE 0
          END
          + COALESCE((
            SELECT SUM(CASE
              WHEN p.amountDue > p.amountPaid THEN p.amountDue - p.amountPaid
              ELSE 0
            END)
            FROM fee_payments p
            WHERE p.studentId = s.id AND p.month < ? AND p.isGenerated = 1
          ), 0)
          + COALESCE((
            SELECT SUM(CASE
              WHEN p.amountDue > p.amountPaid THEN p.amountDue - p.amountPaid
              ELSE 0
            END)
            FROM fee_payments p
            WHERE p.studentId = s.id AND p.month = ? AND p.isGenerated = 1
          ), 0)
        ),
        0
      ) AS pending
      FROM students s
      WHERE s.studentClass NOT IN (?, ?)
      ''',
      [monthKey, monthKey, kCertificateIssuedLabel, kGraduatedLabel],
    );
    // Aggregate queries normally return one row, even when their source tables
    // are empty. Still guard the result: some existing/partially migrated local
    // databases can return no rows, and List.first would abort the whole
    // dashboard with "Bad state: No element".
    final pendingValue = pendingRows.isEmpty
        ? null
        : pendingRows.first['pending'];
    final pending = (pendingValue as num?)?.toDouble() ?? 0;

    final studentCountValue = studentCountRows.isEmpty
        ? null
        : studentCountRows.first['c'];
    final teacherCountValue = teacherCountRows.isEmpty
        ? null
        : teacherCountRows.first['c'];

    return {
      'totalStudents': (studentCountValue as num?)?.toInt() ?? 0,
      'totalTeachers': (teacherCountValue as num?)?.toInt() ?? 0,
      'feesCollected': collected,
      'feesPending': pending,
    };
  }

  /// Fee payments received in the current calendar month. The list naturally
  /// starts fresh when the month changes.
  Future<List<Map<String, dynamic>>> getRecentPaymentsForCurrentMonth({
    DateTime? onDate,
  }) async {
    final db = await database;
    final date = onDate ?? DateTime.now();
    final monthKey = _monthKeyFor(date);
    final dateRange = _receiptDateRangeForMonth(monthKey);
    return db.rawQuery('''
      SELECT ft.amount as amount, ft.date as date,
             s.fullName as fullName, s.studentClass as studentClass
      FROM fee_transactions ft
      JOIN students s ON s.id = ft.studentId
      WHERE ft.date >= ? AND ft.date < ?
      ORDER BY ft.date DESC, ft.id DESC
    ''', dateRange);
  }

  // ---------------- Subject CRUD ----------------

  /// Adds a subject to a class. Returns false (does nothing) if a subject
  /// with the same name already exists for that class.
  Future<bool> addSubject(Subject subject) async {
    final db = await database;
    final existing = await db.query(
      'subjects',
      where: 'className = ? AND subjectName = ?',
      whereArgs: [subject.className, subject.subjectName],
    );
    if (existing.isNotEmpty) return false;
    await db.insert('subjects', subject.toMap());
    return true;
  }

  Future<List<Subject>> getSubjectsForClass(String className) async {
    final db = await database;
    final maps = await db.query(
      'subjects',
      where: 'className = ?',
      whereArgs: [className],
      orderBy: 'id ASC',
    );
    return maps.map((m) => Subject.fromMap(m)).toList();
  }

  Future<int> deleteSubject(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('marks', where: 'subjectId = ?', whereArgs: [id]);
      return txn.delete('subjects', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------- Marks CRUD ----------------

  /// Inserts or updates a single mark (upsert by studentId+subjectId+examName).
  Future<void> upsertMark({
    required int studentId,
    required int subjectId,
    required String examName,
    required double obtainedMarks,
  }) async {
    await upsertMarksBatch([
      MarkEntry(
        studentId: studentId,
        subjectId: subjectId,
        examName: examName,
        obtainedMarks: obtainedMarks,
      ),
    ]);
  }

  /// Saves a group of marks atomically so a failed class save cannot leave
  /// only some students' results updated for the same exam.
  Future<void> upsertMarksBatch(List<MarkEntry> marks) async {
    if (marks.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final mark in marks) {
        final existing = await txn.query(
          'marks',
          columns: ['id'],
          where: 'studentId = ? AND subjectId = ? AND examName = ?',
          whereArgs: [mark.studentId, mark.subjectId, mark.examName],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('marks', mark.toMap());
        } else {
          await txn.update(
            'marks',
            {'obtainedMarks': mark.obtainedMarks},
            where: 'studentId = ? AND subjectId = ? AND examName = ?',
            whereArgs: [mark.studentId, mark.subjectId, mark.examName],
          );
        }
      }
    });
  }

  /// Returns marks for one class + exam as: {studentId: {subjectId: marks}}
  Future<Map<int, Map<int, double>>> getMarksForClassExam(
    String className,
    String examName,
  ) async {
    final subjects = await getSubjectsForClass(className);
    final subjectIds = subjects.map((s) => s.id!).toList();
    if (subjectIds.isEmpty) return {};

    final db = await database;
    final placeholders = List.filled(subjectIds.length, '?').join(',');
    final maps = await db.rawQuery(
      'SELECT * FROM marks WHERE subjectId IN ($placeholders) AND examName = ?',
      [...subjectIds, examName],
    );

    final result = <int, Map<int, double>>{};
    for (final m in maps) {
      final entry = MarkEntry.fromMap(m);
      result.putIfAbsent(entry.studentId, () => {});
      result[entry.studentId]![entry.subjectId] = entry.obtainedMarks;
    }
    return result;
  }

  /// All exam names that have been used for a given class (for quick re-select).
  Future<List<String>> getExamNamesForClass(String className) async {
    final subjects = await getSubjectsForClass(className);
    final subjectIds = subjects.map((s) => s.id!).toList();
    if (subjectIds.isEmpty) return [];

    final db = await database;
    final placeholders = List.filled(subjectIds.length, '?').join(',');
    final maps = await db.rawQuery(
      'SELECT DISTINCT examName FROM marks WHERE subjectId IN ($placeholders)',
      subjectIds,
    );
    return maps.map((m) => m['examName'] as String).toList();
  }

  /// Deletes one exam's marks for one class, leaving every other class intact.
  Future<int> deleteMarksForClassExam(String className, String examName) async {
    final subjects = await getSubjectsForClass(className);
    final subjectIds = subjects.map((s) => s.id!).toList();
    if (subjectIds.isEmpty) return 0;

    final db = await database;
    final placeholders = List.filled(subjectIds.length, '?').join(',');
    return db.delete(
      'marks',
      where: 'subjectId IN ($placeholders) AND examName = ?',
      whereArgs: [...subjectIds, examName],
    );
  }

  // ---------------- Settings (school name, motto, etc.) ----------------

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Convenience getter used by every printed document (fee slips, DMCs)
  /// so they always reflect whatever is set in Settings, falling back to
  /// sensible defaults if nothing has been saved yet.
  Future<Map<String, String>> getSchoolInfo() async {
    final name = await getSetting('schoolName');
    final tagline = await getSetting('schoolTagline');
    return {
      'name': name ?? 'Amaan Public High School',
      'tagline': tagline ?? 'Enter to Learn, Leave to Serve',
    };
  }

  /// Stores a school's logo inside its own database so it remains local to
  /// that school and is included in normal database backups.
  Future<Uint8List?> getSchoolLogoBytes() async {
    final encoded = await getSetting('schoolLogoData');
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> setSchoolLogoBytes(Uint8List? bytes) async {
    final db = await database;
    if (bytes == null) {
      await db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['schoolLogoData'],
      );
      return;
    }
    await setSetting('schoolLogoData', base64Encode(bytes));
  }

  // ---------------- App Password / Security ----------------

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// True once an admin password has ever been set — used to decide
  /// whether to show "create a password" or "enter your password" on
  /// startup.
  Future<bool> hasPasswordSet() async {
    final hash = await getSetting('appPasswordHash');
    return hash != null && hash.isNotEmpty;
  }

  /// Sets the app password for the very first time, or forcibly resets it
  /// without needing the old one (used only during initial setup).
  Future<void> setPassword(String password) async {
    await setSetting('appPasswordHash', _hashPassword(password));
  }

  String _hashRecoveryCode(String code) {
    final normalized = code.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return sha256.convert(utf8.encode(normalized)).toString();
  }

  String generateRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = math.Random.secure();
    final raw = List.generate(
      20,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
    return List.generate(
      5,
      (index) => raw.substring(index * 4, index * 4 + 4),
    ).join('-');
  }

  Future<bool> hasRecoveryCode() async {
    final storedHash = await getSetting('appRecoveryCodeHash');
    return storedHash != null && storedHash.isNotEmpty;
  }

  Future<void> saveRecoveryCode(String code) async {
    await setSetting('appRecoveryCodeHash', _hashRecoveryCode(code));
  }

  Future<bool> verifyRecoveryCode(String code) async {
    final storedHash = await getSetting('appRecoveryCodeHash');
    if (storedHash == null || storedHash.isEmpty) return false;
    return _hashRecoveryCode(code) == storedHash;
  }

  Future<bool> resetPasswordWithRecoveryCode(
    String code,
    String newPassword,
  ) async {
    if (!await verifyRecoveryCode(code)) return false;
    await setPassword(newPassword);
    return true;
  }

  /// Checks [password] against the stored hash — the real password is
  /// never stored anywhere, only its SHA-256 hash.
  Future<bool> verifyPassword(String password) async {
    final storedHash = await getSetting('appPasswordHash');
    if (storedHash == null) return false;
    return _hashPassword(password) == storedHash;
  }

  /// Changes the password, but only if [currentPassword] is correct.
  /// Returns false (and changes nothing) if the current password is wrong.
  Future<bool> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final isCorrect = await verifyPassword(currentPassword);
    if (!isCorrect) return false;
    await setPassword(newPassword);
    return true;
  }

  // ---------------- Backup / Restore ----------------

  String _backupTimestamp(DateTime now) {
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final subsecond =
        '${now.millisecond.toString().padLeft(3, '0')}${now.microsecond.toString().padLeft(3, '0')}';
    return '${date}_${time}_$subsecond';
  }

  String _backupSortKey(String path) {
    final name = basename(path);
    final match = RegExp(
      r'^backup_(?:pre_upgrade_)?(\d{8})_(\d{6})(?:_(\d{6}))?',
    ).firstMatch(name);
    if (match == null) return '';
    return '${match.group(1)}_${match.group(2)}_${match.group(3) ?? '000000'}';
  }

  int _compareBackupsNewestFirst(FileSystemEntity a, FileSystemEntity b) {
    final byTimestamp = _backupSortKey(
      b.path,
    ).compareTo(_backupSortKey(a.path));
    if (byTimestamp != 0) return byTimestamp;
    return b.path.compareTo(a.path);
  }

  /// Retains a small local recovery window after a verified backup succeeds.
  /// Copies saved elsewhere, such as a USB drive, are outside this folder and
  /// are never affected by this cleanup.
  Future<void> _pruneLocalBackupHistory(Directory backupsDir) async {
    try {
      if (!await backupsDir.exists()) return;
      final files = await backupsDir
          .list(followLinks: false)
          .where(
            (entity) =>
                entity is File &&
                basename(entity.path).startsWith('backup_') &&
                entity.path.toLowerCase().endsWith('.db'),
          )
          .cast<File>()
          .toList();
      files.sort(_compareBackupsNewestFirst);
      for (final oldFile in files.skip(_maxLocalBackupCount)) {
        try {
          await oldFile.delete();
        } catch (_) {
          // A locked file should not make an already-verified backup fail.
        }
      }
    } catch (_) {
      // Local history cleanup is best-effort; it must never invalidate a
      // successfully created backup or interrupt normal app use.
    }
  }

  /// Creates a verified snapshot in a timestamped file inside a 'backups'
  /// folder next to the live database. Returns its full path.
  Future<String> backupDatabase() async {
    final db = await database; // ensure it's initialized/flushed
    final dbFolder = dirname(db.path);
    final backupsDir = Directory(join(dbFolder, 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    final stamp = _backupTimestamp(DateTime.now());
    final backupPath = join(backupsDir.path, 'backup_$stamp.db');
    await _writeValidatedSnapshot(db, backupPath);
    await _pruneLocalBackupHistory(backupsDir);
    return backupPath;
  }

  /// Saves a verified local recovery copy and a second copy at [destination].
  /// The destination is never allowed to be the live database or an existing
  /// file, so a school backup cannot overwrite current data or an older copy.
  Future<String> backupDatabaseTo(String destinationPath) async {
    final db = await database;
    final destination = normalize(absolute(destinationPath));
    final livePath = normalize(absolute(db.path));
    if (destination.toLowerCase() == livePath.toLowerCase()) {
      throw Exception('Choose a backup location, not the live database file.');
    }
    if (await File(destination).exists()) {
      throw Exception(
        'A file already exists at that location. Choose a new backup filename.',
      );
    }

    final localBackupPath = await backupDatabase();
    final output = File(destination);
    try {
      await output.parent.create(recursive: true);
      await File(localBackupPath).copy(destination);
      await _validateBackupDatabase(output);
      return destination;
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  Future<void> _writeValidatedSnapshot(
    Database db,
    String destinationPath,
  ) async {
    final output = File(destinationPath);
    if (await output.exists()) {
      throw Exception('A backup already exists at this location.');
    }
    final escapedPath = destinationPath.replaceAll("'", "''");
    try {
      // VACUUM INTO creates a consistent SQLite snapshot, including committed
      // data even if SQLite is using a write-ahead log.
      await db.execute("VACUUM INTO '$escapedPath'");
      await _validateBackupDatabase(output);
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  /// Lists existing backup files, newest first.
  Future<List<FileSystemEntity>> listBackups() async {
    final dbFolder = await getDatabaseFolderPath();
    final backupsDir = Directory(join(dbFolder, 'backups'));
    if (!await backupsDir.exists()) return [];
    final files = backupsDir
        .listSync()
        .where((f) => f is File && f.path.endsWith('.db'))
        .toList();
    files.sort(_compareBackupsNewestFirst);
    return files;
  }

  Future<void> _validateBackupDatabase(File backupFile) async {
    Database? validationDb;
    try {
      validationDb = await databaseFactory.openDatabase(
        backupFile.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );

      final backupVersion = await validationDb.getVersion();
      if (backupVersion > _currentDatabaseVersion) {
        throw Exception(
          'This backup was created by a newer version of the app. Update the app before restoring it.',
        );
      }

      final integrityRows = await validationDb.rawQuery('PRAGMA quick_check');
      final integrityResults = integrityRows
          .map(
            (row) =>
                row.isEmpty ? null : row.values.first.toString().toLowerCase(),
          )
          .toList();
      if (integrityResults.length != 1 || integrityResults.single != 'ok') {
        throw Exception('The backup failed SQLite’s integrity check.');
      }

      final tableRows = await validationDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tableRows
          .map((row) => row['name'])
          .whereType<String>()
          .toSet();
      final requiredTables = <String>{'students'};
      if (backupVersion >= 18) {
        requiredTables.addAll([
          'fee_payments',
          'fee_transactions',
          'settings',
          'certificates',
          'teachers',
          'salary_payments',
          'subjects',
          'marks',
        ]);
      }
      if (!tableNames.containsAll(requiredTables)) {
        throw Exception(
          'The selected file is not a complete school database (required tables are missing).',
        );
      }
    } finally {
      await validationDb?.close();
    }
  }

  /// Replaces the live database with [backupPath] after validating the file
  /// and saving the current database as a recovery backup. Returns that
  /// recovery backup path, or null if there was no existing database file.
  /// The app should be restarted after a successful restore.
  Future<String?> restoreDatabase(String backupPath) async {
    final db = await database; // initialize the FFI database factory/live DB
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) {
      throw Exception(
        'Backup file not found — it may have been moved or deleted: $backupPath',
      );
    }

    final dbFolder = dirname(db.path);
    final liveDbPath = db.path;
    final selectedPath = normalize(absolute(backupFile.path)).toLowerCase();
    final livePath = normalize(absolute(liveDbPath)).toLowerCase();
    if (selectedPath == livePath) {
      throw Exception('Choose a backup file, not the live database file.');
    }

    // Validate before closing the live connection or touching current data.
    await _validateBackupDatabase(backupFile);

    final backupsDir = Directory(join(dbFolder, 'backups'));
    await backupsDir.create(recursive: true);
    final currentDb = _database;
    if (currentDb != null) {
      await currentDb.close();
      _database = null;
    }

    final liveFile = File(liveDbPath);
    String? recoveryBackupPath;
    try {
      if (await liveFile.exists()) {
        recoveryBackupPath = join(
          backupsDir.path,
          'backup_${_backupTimestamp(DateTime.now())}_before_restore.db',
        );
        await liveFile.copy(recoveryBackupPath);
      }
    } catch (error) {
      try {
        _database = await _initDB();
      } catch (reopenError) {
        throw Exception(
          'Restore stopped because a safety backup could not be created. The original database file was not replaced, but the app could not reopen it: $reopenError. Backup error: $error',
        );
      }
      throw Exception(
        'Restore stopped because a safety backup could not be created. The original database was not replaced. Details: $error',
      );
    }

    try {
      await backupFile.copy(liveDbPath);
    } catch (restoreError) {
      try {
        if (recoveryBackupPath != null) {
          await File(recoveryBackupPath).copy(liveDbPath);
        } else if (await liveFile.exists()) {
          await liveFile.delete();
        }
        _database = await _initDB();
      } catch (rollbackError) {
        throw Exception(
          'Restore failed, and automatic recovery also failed. Keep this recovery backup safe: ${recoveryBackupPath ?? '(no database existed before restore)'}. Recovery error: $rollbackError. Restore error: $restoreError',
        );
      }
      throw Exception(
        'Restore failed. The previous database has been recovered. Details: $restoreError',
      );
    }

    await _pruneLocalBackupHistory(backupsDir);
    return recoveryBackupPath;
  }

  // ---------------- Certificates ----------------

  /// Returns the class before [currentClass], or null for Nursery. This is
  /// used to distinguish the Nursery bonafide certificate from a leaving
  /// certificate; it is not proof of a student's exam result.
  String? getPreviousClass(String currentClass) {
    final index = kClassList.indexOf(currentClass);
    if (index <= 0) return null;
    return kClassList[index - 1];
  }

  /// Saves an immutable certificate snapshot. Nursery students receive a
  /// bonafide certificate and stay active; students in other classes receive
  /// a leaving certificate and are archived from active views. For a leaving
  /// certificate, the class before the current enrollment is recorded as the
  /// last passed class, reflecting the school's promotion decision.
  Future<Certificate> issueCertificate(Student student) async {
    final isBonafide = student.studentClass == kClassList.first;
    final certType = isBonafide ? 'bonafide' : 'leaving';
    final classForCertificate = student.studentClass;
    final lastPassedClass = isBonafide
        ? ''
        : getPreviousClass(student.studentClass) ?? '';

    final db = await database;
    final today = DateTime.now().toIso8601String().split('T').first;

    final id = await db.transaction((txn) async {
      final certificateId = await txn.insert('certificates', {
        'studentId': student.id,
        'studentName': student.fullName,
        'fatherName': student.fatherName,
        'admissionNo': student.admissionNo,
        'dob': student.dob,
        'admissionDate': student.admissionDate,
        'classPassed': classForCertificate,
        'admittedClass': student.admittedClass,
        'lastPassedClass': lastPassedClass,
        'issueDate': today,
        'certificateType': certType,
      });

      // Only a genuine LEAVING certificate removes the student from active
      // views. Keep this change atomic with saving the certificate snapshot.
      if (!isBonafide) {
        await txn.update(
          'students',
          {'studentClass': kCertificateIssuedLabel},
          where: 'id = ?',
          whereArgs: [student.id],
        );
      }
      return certificateId;
    });

    return Certificate(
      id: id,
      studentId: student.id!,
      studentName: student.fullName,
      fatherName: student.fatherName,
      admissionNo: student.admissionNo,
      dob: student.dob,
      admissionDate: student.admissionDate,
      classPassed: classForCertificate,
      admittedClass: student.admittedClass,
      lastPassedClass: lastPassedClass,
      issueDate: today,
      certificateType: certType,
    );
  }

  /// All issued certificates, newest first.
  Future<List<Certificate>> getAllCertificates() async {
    final db = await database;
    final maps = await db.query('certificates', orderBy: 'id DESC');
    return maps.map((m) => Certificate.fromMap(m)).toList();
  }
}
