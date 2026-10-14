import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/db_helper.dart';
import 'package:path/path.dart' as p;

void main() {
  test('keeps ten newest local backups without deleting USB copies', () async {
    final helper = DBHelper.instance;
    final databaseFolder = await helper.getDatabaseFolderPath();
    final usbFolder = Directory(p.join(databaseFolder, 'usb_copy'));
    await usbFolder.create(recursive: true);
    final externalBackupPath = await helper.backupDatabaseTo(
      p.join(usbFolder.path, 'SchoolBackup_test.db'),
    );

    final createdLocalBackups = <String>[];
    for (var i = 0; i < 12; i++) {
      createdLocalBackups.add(await helper.backupDatabase());
    }

    final retained = await helper.listBackups();
    expect(retained, hasLength(10));
    expect(retained.first.path, createdLocalBackups.last);
    expect(await File(createdLocalBackups.first).exists(), isFalse);
    expect(await File(externalBackupPath).exists(), isTrue);
  });
}
