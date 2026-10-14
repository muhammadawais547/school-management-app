import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'db_helper.dart';
import 'main.dart' show AppColors;

class SettingsPage extends StatefulWidget {
  final VoidCallback? onBrandingChanged;

  const SettingsPage({super.key, this.onBrandingChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  bool _savingSchoolInfo = false;
  bool _choosingLogo = false;
  bool _hasRecoveryCode = false;
  bool _managingRecoveryCode = false;
  Uint8List? _schoolLogoBytes;
  final TextEditingController _schoolNameController = TextEditingController();
  final TextEditingController _schoolTaglineController =
      TextEditingController();

  List<FileSystemEntity> _backups = [];
  bool _backingUp = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _schoolNameController.dispose();
    _schoolTaglineController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final backups = await DBHelper.instance.listBackups();
      final schoolInfo = await DBHelper.instance.getSchoolInfo();
      final schoolLogo = await DBHelper.instance.getSchoolLogoBytes();
      final hasRecoveryCode = await DBHelper.instance.hasRecoveryCode();
      if (!mounted) return;
      setState(() {
        _backups = backups;
        _schoolNameController.text = schoolInfo['name'] ?? '';
        _schoolTaglineController.text = schoolInfo['tagline'] ?? '';
        _schoolLogoBytes = schoolLogo;
        _hasRecoveryCode = hasRecoveryCode;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load settings: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _chooseSchoolLogo() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Logo image', extensions: ['png', 'jpg', 'jpeg']),
        ],
      );
      if (!mounted || file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      const maxLogoBytes = 3 * 1024 * 1024;
      if (bytes.length > maxLogoBytes) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please choose a logo smaller than 3 MB.'),
            ),
          );
        }
        return;
      }

      final isPng =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0D &&
          bytes[5] == 0x0A &&
          bytes[6] == 0x1A &&
          bytes[7] == 0x0A;
      final isJpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
      if (!isPng && !isJpeg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('That file is not a valid PNG or JPEG image.'),
            ),
          );
        }
        return;
      }

      setState(() => _choosingLogo = true);
      await DBHelper.instance.setSchoolLogoBytes(bytes);
      if (!mounted) return;
      setState(() {
        _schoolLogoBytes = bytes;
        _choosingLogo = false;
      });
      widget.onBrandingChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('School logo saved.')));
    } catch (e) {
      if (mounted) {
        setState(() => _choosingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the logo: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _useDefaultLogo() async {
    setState(() => _choosingLogo = true);
    try {
      await DBHelper.instance.setSchoolLogoBytes(null);
      if (!mounted) return;
      setState(() {
        _schoolLogoBytes = null;
        _choosingLogo = false;
      });
      widget.onBrandingChanged?.call();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Default logo restored.')));
    } catch (e) {
      if (mounted) {
        setState(() => _choosingLogo = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not restore the default logo: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveSchoolInfo() async {
    final name = _schoolNameController.text.trim();
    final tagline = _schoolTaglineController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the school name.')),
      );
      return;
    }

    setState(() => _savingSchoolInfo = true);
    try {
      await DBHelper.instance.setSetting('schoolName', name);
      await DBHelper.instance.setSetting('schoolTagline', tagline);
      widget.onBrandingChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('School details saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save school details: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingSchoolInfo = false);
    }
  }

  Future<void> _manageRecoveryCode() async {
    if (_managingRecoveryCode) return;
    setState(() => _managingRecoveryCode = true);
    try {
      if (_hasRecoveryCode) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace recovery code?'),
            content: const Text(
              'The current recovery code will stop working. You will need to save the new code before it is activated.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create New Code'),
              ),
            ],
          ),
        );
        if (!mounted || replace != true) return;
      }

      final code = DBHelper.instance.generateRecoveryCode();
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Save your recovery code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Write this code down and keep it somewhere private. It can reset the admin password if it is forgotten. The app will not show it again.',
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    code,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('I saved the code'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || saved != true) return;

      await DBHelper.instance.saveRecoveryCode(code);
      if (!mounted) return;
      setState(() => _hasRecoveryCode = true);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Recovery code saved.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the recovery code: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _managingRecoveryCode = false);
    }
  }

  Future<void> _backupNow() async {
    if (_backingUp || _restoring) return;
    setState(() => _backingUp = true);
    try {
      final path = await DBHelper.instance.backupDatabase();
      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved: ${_fileNameOf(path)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  String _suggestedBackupName() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return 'SchoolBackup_${now.year}${twoDigits(now.month)}${twoDigits(now.day)}_'
        '${twoDigits(now.hour)}${twoDigits(now.minute)}${twoDigits(now.second)}.db';
  }

  Future<void> _saveBackupCopy() async {
    if (_backingUp || _restoring) return;
    try {
      final destination = await getSaveLocation(
        suggestedName: _suggestedBackupName(),
        acceptedTypeGroups: const [
          XTypeGroup(label: 'School database backup', extensions: ['db']),
        ],
      );
      if (!mounted || destination == null) return;
      final path = destination.path.toLowerCase().endsWith('.db')
          ? destination.path
          : '${destination.path}.db';
      final destinationExists = await File(path).exists();
      if (!mounted) return;
      if (destinationExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'A file with this name already exists. Choose a new filename so the older backup stays safe.',
            ),
          ),
        );
        return;
      }

      setState(() => _backingUp = true);
      final savedPath = await DBHelper.instance.backupDatabaseTo(path);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved to: $savedPath')));
    } catch (error) {
      if (mounted) {
        await _loadAll();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not save the USB/folder copy: $error. A local safety copy may be available under Previous Backups.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  Future<void> _confirmRestore(FileSystemEntity backup) async {
    await _confirmRestorePath(backup.path);
  }

  Future<void> _restoreFromFile() async {
    if (_backingUp || _restoring) return;
    try {
      final backup = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'School database backup', extensions: ['db']),
        ],
      );
      if (!mounted || backup == null) return;
      await _confirmRestorePath(backup.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open that backup file: $error')),
      );
    }
  }

  Future<void> _confirmRestorePath(String backupPath) async {
    if (_backingUp || _restoring) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Restore this backup?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will REPLACE all current data (students, fees, marks — everything) with the backup from '
          '${_formatBackupName(backupPath)}.\n\nThe app will check the backup first and save the current database '
          'as a recovery backup before replacing it. After a successful restore, close and reopen the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _restoring = true);
    try {
      final recoveryBackupPath = await DBHelper.instance.restoreDatabase(
        backupPath,
      );
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Restore complete',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              recoveryBackupPath == null
                  ? 'There was no existing database to back up. Please close this app completely and reopen it now, so the restored data loads correctly.'
                  : 'The data that was on this computer before restoring was saved as a recovery backup:\n\n$recoveryBackupPath\n\nPlease close this app completely and reopen it now, so the restored data loads correctly.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: $e'),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  String _fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

  Future<void> _showChangePasswordDialog() async {
    if (!mounted) return;
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final pageContext = context;
    String? error;

    try {
      await showDialog<void>(
        context: pageContext,
        builder: (dialogContext) {
          var changing = false;
          return StatefulBuilder(
            builder: (context, setDialogState) => PopScope(
              canPop: !changing,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: currentCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Current Password',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: newCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          filled: true,
                          fillColor: const Color(0xFFF5F7FA),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: changing
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: changing
                        ? null
                        : () async {
                            final current = currentCtrl.text.trim();
                            final newPass = newCtrl.text.trim();
                            final confirm = confirmCtrl.text.trim();
                            if (newPass.length < 4) {
                              setDialogState(
                                () => error =
                                    'New password must be at least 4 characters.',
                              );
                              return;
                            }
                            if (newPass != confirm) {
                              setDialogState(
                                () => error = 'New passwords do not match.',
                              );
                              return;
                            }

                            setDialogState(() {
                              changing = true;
                              error = null;
                            });
                            try {
                              final success = await DBHelper.instance
                                  .changePassword(current, newPass);
                              if (!dialogContext.mounted) return;
                              if (!success) {
                                setDialogState(() {
                                  changing = false;
                                  error = 'Current password is incorrect.';
                                });
                                return;
                              }

                              Navigator.pop(dialogContext);
                              if (mounted) {
                                ScaffoldMessenger.of(pageContext).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Password changed successfully.',
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                changing = false;
                                error = 'Could not change the password: $e';
                              });
                            }
                          },
                    child: changing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Change Password'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } finally {
      currentCtrl.dispose();
      newCtrl.dispose();
      confirmCtrl.dispose();
    }
  }

  // Turns 'backup_20261005_143210.db' into '5 Oct 2026, 2:32 PM'
  String _formatBackupName(String path) {
    final name = _fileNameOf(path);
    final match = RegExp(r'backup_(\d{8})_(\d{6})').firstMatch(name);
    if (match == null) return name;
    final datePart = match.group(1)!;
    final timePart = match.group(2)!;
    final year = int.parse(datePart.substring(0, 4));
    final month = int.parse(datePart.substring(4, 6));
    final day = int.parse(datePart.substring(6, 8));
    final hour = int.parse(timePart.substring(0, 2));
    final minute = int.parse(timePart.substring(2, 4));
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
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$day ${months[month - 1]} $year, $hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 24),

            _sectionCard(
              icon: Icons.school_rounded,
              title: 'School Details',
              subtitle:
                  'These details appear in the app and on printed reports and certificates.',
              child: Column(
                children: [
                  TextField(
                    controller: _schoolNameController,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: 'School name',
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _schoolTaglineController,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: 'School motto or tagline (optional)',
                      filled: true,
                      fillColor: const Color(0xFFF5F7FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 14,
                      runSpacing: 10,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: _schoolLogoBytes == null
                              ? Image.asset(
                                  'assets/logo.jpg',
                                  fit: BoxFit.contain,
                                )
                              : Image.memory(
                                  _schoolLogoBytes!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _choosingLogo
                                  ? null
                                  : _chooseSchoolLogo,
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: const Text('Choose Logo'),
                            ),
                            if (_schoolLogoBytes != null)
                              TextButton.icon(
                                onPressed: _choosingLogo
                                    ? null
                                    : _useDefaultLogo,
                                icon: const Icon(
                                  Icons.restore_rounded,
                                  size: 16,
                                ),
                                label: const Text('Use Default Logo'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose a PNG or JPEG image up to 3 MB. The logo is saved with this school’s local data and backups.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _savingSchoolInfo ? null : _saveSchoolInfo,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: _savingSchoolInfo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save School Details'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ---- Security ----
            _sectionCard(
              icon: Icons.security_rounded,
              title: 'Security',
              subtitle: 'Manage the password and recovery code for this app.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showChangePasswordDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.lock_reset_rounded, size: 18),
                    label: const Text('Change Password'),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _hasRecoveryCode
                        ? 'Your recovery code is active. Create a new one if the saved code is lost.'
                        : 'Create a recovery code and keep it private. It will be required to reset a forgotten password.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _managingRecoveryCode
                        ? null
                        : _manageRecoveryCode,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.navy,
                      side: const BorderSide(color: AppColors.navy),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _managingRecoveryCode
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.key_rounded, size: 18),
                    label: Text(
                      _hasRecoveryCode
                          ? 'Replace Recovery Code'
                          : 'Create Recovery Code',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ---- Backup & Restore ----
            _sectionCard(
              icon: Icons.backup_rounded,
              title: 'Backup & Restore',
              subtitle:
                  'The app keeps the 10 newest local backups and removes older local copies after a verified backup. Copies saved to USB or another folder are not removed.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _backingUp || _restoring ? null : _backupNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: _backingUp
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.backup_rounded, size: 18),
                        label: const Text('Backup Now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _backingUp || _restoring
                            ? null
                            : _saveBackupCopy,
                        icon: const Icon(Icons.usb_rounded, size: 18),
                        label: const Text('Save Copy to USB / Folder'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _backingUp || _restoring
                            ? null
                            : _restoreFromFile,
                        icon: const Icon(Icons.drive_folder_upload_rounded),
                        label: const Text('Restore from USB / Folder'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Previous backups',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_backups.isEmpty)
                    Text(
                      'No backups yet — click "Backup Now" to create your first one.',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    )
                  else
                    ...(_backups
                        .take(10)
                        .map(
                          (b) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.description_outlined,
                                    size: 18,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _formatBackupName(b.path),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _backingUp || _restoring
                                        ? null
                                        : () => _confirmRestore(b),
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ---- About ----
            _sectionCard(
              icon: Icons.info_outline_rounded,
              title: 'About',
              subtitle: null,
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'School Management System',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Built for managing students, teachers, fees, and results.',
                    style: TextStyle(color: AppColors.textGrey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.teal),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
