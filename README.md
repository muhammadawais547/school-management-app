# School Management App

An offline desktop application for managing day-to-day records for a school. It is built with Flutter and stores each school's records locally on that school's computer.

> **Current app version:** `1.0.0+1` (from `pubspec.yaml`). The GitHub repository does not currently have a published Release or downloadable installer attached to it.

## What the app includes

- **School profile:** school name, motto, and logo can be maintained in Settings.
- **Students:** student records, class placement and promotion, and a separate view for students who have left.
- **Teachers:** teacher records and the teacher area of the dashboard.
- **Fees:** a main dashboard and separate month-by-month class dashboards; fee generation, payments, concessions, advance payments, receipts, and class fee history/ledger.
- **Combined billing periods:** June is billed together with July, and August is billed together with September.
- **PDF documents:** fee slips (four slips per page), payment receipts, class fee ledgers, class result sheets, individual DMCs, and certificates.
- **Exams and results:** subject setup, marks entry, saved exams, result sheets, student positions, and promotion.
- **Backups:** create a local backup, save a copy to another folder or USB drive, and restore a selected backup from Settings.

Fee and result records affect school accounts and student records. The school should check generated totals, receipts, ledgers, and result sheets against its own records before relying on them for official decisions.

## Important fee and result rules

- The app has a main dashboard and separate dashboards for each billing month. Cash is associated with the actual receipt date, including its year.
- June and July are handled as one billing cycle in June. August and September are handled as one billing cycle in August.
- Fee screens and PDFs distinguish the selected cycle's fee from older unpaid balances, payments received, concessions, and the remaining balance.
- A free student should be identified as **Free** in the class fee ledger.
- Subject passing marks are based on 33% of that subject's maximum marks. A failing subject is marked `F`; students who fail a subject do not receive a class position. Teachers use the remarks area for their judgment instead of an overall Pass/Fail label.
- Students tied on a position share it; the next position continues in order.

These describe the application's intended school workflows. Test fee totals, payment dates, concessions, positions, and printed documents with sample records before using them as official accounts or results.

## Data and privacy

The app is designed to work locally and does not provide cloud synchronization. On Windows, its SQLite database is stored in the signed-in Windows user's local application data folder:

```text
%LOCALAPPDATA%\SchoolManager\school_manager.db
```

The app's local backup copies are kept in the `backups` folder beside the database. Use **Save Copy to USB / Folder** in Settings to keep a recovery copy away from the laptop. A backup contains the school's records, so store it securely. Restoring a backup replaces the current records with the records in that backup; the app creates a recovery copy of the current database as part of the restore process.

The database and backups are school data. They should not be uploaded to this public source-code repository.

## Run on Windows

Install the Flutter SDK and the Windows desktop build tools required by Flutter. Then open a terminal in this project folder and run:

```powershell
flutter pub get
flutter run -d windows
```

To build a Windows release:

```powershell
flutter build windows --release
```

The Windows build is created under:

```text
build\windows\x64\runner\Release\
```

For deployment, copy the **entire** `Release` folder to the school computer; the `.exe` needs the accompanying files and folders. Keep a verified database backup before installing an app update or moving the school to another computer.

## Project contents

- `lib/` — Flutter screens, data handling, fee and result workflows, and PDF generation.
- `assets/` — bundled visual assets.
- `windows/` — Windows desktop runner and build configuration.
- `pubspec.yaml` — app version, Flutter dependencies, and bundled assets.

This repository contains the application source code, not a school's live database or a ready-made Windows installer.

## Main technologies

- Flutter and Dart
- SQLite through `sqflite_common_ffi`
- PDF generation through the Dart `pdf` package

## Source code and reuse

This repository is public so people can view the project. It currently has no `LICENSE` file. Public visibility alone does not grant permission to copy, modify, distribute, or sell the code; contact the repository owner about reuse.
