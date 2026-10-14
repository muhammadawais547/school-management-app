import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

// ---------- Student model ----------
class Student {
  final int? id;
  final String name;
  final String grade;
  final String parentPhone;
  final double feeAmount;

  Student({
    this.id,
    required this.name,
    required this.grade,
    required this.parentPhone,
    required this.feeAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'grade': grade,
      'parentPhone': parentPhone,
      'feeAmount': feeAmount,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int?,
      name: map['name'] as String,
      grade: map['grade'] as String,
      parentPhone: map['parentPhone'] as String,
      feeAmount: (map['feeAmount'] as num).toDouble(),
    );
  }
}

// ---------- Database helper (singleton) ----------
class DBHelper {
  static final DBHelper instance = DBHelper._internal();
  DBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // Required once per app for desktop platforms (Windows/Linux/macOS)
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dbPath = await databaseFactory.getDatabasesPath();
    final path = join(dbPath, 'school_manager.db');

    return await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE students (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              grade TEXT NOT NULL,
              parentPhone TEXT NOT NULL,
              feeAmount REAL NOT NULL
            )
          ''');
        },
      ),
    );
  }

  // ---- CRUD operations ----

  Future<int> addStudent(Student student) async {
    final db = await database;
    return await db.insert('students', student.toMap());
  }

  Future<List<Student>> getAllStudents() async {
    final db = await database;
    final maps = await db.query('students', orderBy: 'name ASC');
    return maps.map((m) => Student.fromMap(m)).toList();
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return await db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateStudent(Student student) async {
    final db = await database;
    return await db.update(
      'students',
      student.toMap(),
      where: 'id = ?',
      whereArgs: [student.id],
    );
  }
}
