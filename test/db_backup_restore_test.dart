import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/db_helper.dart';
import 'package:path/path.dart' as p;

void main() {
  test('backups restore safely from local and external copies', () async {
    final helper = DBHelper.instance;
    final liveDatabase = await helper.database;
    const testKey = 'backup_restore_verification_marker';
    final journalMode = await liveDatabase.rawQuery(
      'PRAGMA journal_mode = WAL',
    );
    expect(journalMode.single.values.single.toString().toLowerCase(), 'wal');

    await liveDatabase.insert('settings', {
      'key': testKey,
      'value': 'saved in backup',
    });

    final backupPath = await helper.backupDatabase();
    final backupFile = File(backupPath);
    expect(await backupFile.exists(), isTrue);
    expect(await backupFile.length(), greaterThan(0));

    await liveDatabase.update(
      'settings',
      {'value': 'live value after backup'},
      where: 'key = ?',
      whereArgs: [testKey],
    );

    final recoveryPath = await helper.restoreDatabase(backupPath);
    expect(recoveryPath, isNotNull);
    expect(await File(recoveryPath!).exists(), isTrue);

    final restoredDatabase = await helper.database;
    var rows = await restoredDatabase.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [testKey],
    );
    expect(rows.single['value'], 'saved in backup');

    final usbFolder = Directory(p.join(backupFile.parent.path, 'usb-copy'));
    await usbFolder.create(recursive: true);
    final externalPath = await helper.backupDatabaseTo(
      p.join(usbFolder.path, 'SchoolBackup_test.db'),
    );
    expect(await File(externalPath).exists(), isTrue);
    await expectLater(helper.backupDatabaseTo(externalPath), throwsA(anything));
    await expectLater(
      helper.backupDatabaseTo(await helper.getDatabaseFilePath()),
      throwsA(anything),
    );

    await restoredDatabase.update(
      'settings',
      {'value': 'changed after external backup'},
      where: 'key = ?',
      whereArgs: [testKey],
    );
    await helper.restoreDatabase(externalPath);
    final reopenedAfterExternalRestore = await helper.database;
    rows = await reopenedAfterExternalRestore.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [testKey],
    );
    expect(rows.single['value'], 'saved in backup');

    final invalidBackup = File('${backupFile.parent.path}/invalid_test.db');
    await invalidBackup.writeAsString('not a SQLite database');
    await expectLater(
      helper.restoreDatabase(invalidBackup.path),
      throwsA(anything),
    );

    rows = await reopenedAfterExternalRestore.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [testKey],
    );
    expect(rows.single['value'], 'saved in backup');
    final backupFiles = await helper.listBackups();
    expect(backupFiles.any((file) => file.path == recoveryPath), isTrue);
    expect(backupFiles.any((file) => file.path == externalPath), isFalse);

    await reopenedAfterExternalRestore.close();
  });
}
