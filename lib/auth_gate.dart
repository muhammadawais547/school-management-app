import 'package:flutter/material.dart';
import 'db_helper.dart';
import 'main.dart' show AppShell, AppColors;

/// Sits at the very root of the app. Shows a "create password" screen the
/// very first time the app is used, an "enter password" lock screen on
/// every launch after that, and only reveals AppShell once unlocked.
/// Logging out from inside the app returns here without closing anything.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _checking = true;
  bool _hasPassword = false;
  bool _unlocked = false;
  String _schoolName = 'Amaan Public High School';

  @override
  void initState() {
    super.initState();
    _checkPasswordStatus();
  }

  Future<void> _checkPasswordStatus() async {
    final has = await DBHelper.instance.hasPasswordSet();
    final info = await DBHelper.instance.getSchoolInfo();
    if (!mounted) return;
    setState(() {
      _hasPassword = has;
      _schoolName = info['name'] ?? 'School Manager';
      _checking = false;
    });
  }

  void _onUnlocked() => setState(() => _unlocked = true);
  Future<void> _onLogout() async {
    final info = await DBHelper.instance.getSchoolInfo();
    if (!mounted) return;
    setState(() {
      _schoolName = info['name'] ?? 'School Manager';
      _unlocked = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_unlocked) {
      return AppShell(onLogout: _onLogout);
    }
    if (!_hasPassword) {
      return _SetPasswordScreen(
        onDone: () {
          setState(() => _hasPassword = true);
          _onUnlocked();
        },
      );
    }
    return _EnterPasswordScreen(
      onUnlocked: _onUnlocked,
      schoolName: _schoolName,
    );
  }
}

class _AuthCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _AuthCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.teal,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> _showRecoveryCodeDialog(BuildContext context, String code) async {
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
  return saved == true;
}

class _SetPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const _SetPasswordScreen({required this.onDone});

  @override
  State<_SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends State<_SetPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _saving = false;

  Future<void> _submit() async {
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (password.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await DBHelper.instance.setPassword(password);
      if (!await DBHelper.instance.hasRecoveryCode()) {
        final code = DBHelper.instance.generateRecoveryCode();
        final saved = await _showRecoveryCodeDialog(context, code);
        if (!saved) {
          if (mounted) {
            setState(() {
              _saving = false;
              _error = 'Save the recovery code to finish setup.';
            });
          }
          return;
        }
        await DBHelper.instance.saveRecoveryCode(code);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not finish setup: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(
      title: 'Create Admin Password',
      subtitle:
          'Set a password to protect this app. You\'ll need it every time you open it.',
      child: Column(
        children: [
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New Password',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Set Password & Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnterPasswordScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String schoolName;
  const _EnterPasswordScreen({
    required this.onUnlocked,
    required this.schoolName,
  });

  @override
  State<_EnterPasswordScreen> createState() => _EnterPasswordScreenState();
}

class _EnterPasswordScreenState extends State<_EnterPasswordScreen> {
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _checking = false;

  Future<void> _submit() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final correct = await DBHelper.instance.verifyPassword(
        _passwordCtrl.text.trim(),
      );
      if (!mounted) return;
      if (!correct) {
        setState(() {
          _checking = false;
          _error = 'Incorrect password. Please try again.';
        });
        _passwordCtrl.clear();
        return;
      }

      if (!await DBHelper.instance.hasRecoveryCode()) {
        final code = DBHelper.instance.generateRecoveryCode();
        final saved = await _showRecoveryCodeDialog(context, code);
        if (!saved) {
          if (mounted) {
            setState(() {
              _checking = false;
              _error = 'Save the recovery code to finish unlocking the app.';
            });
          }
          return;
        }
        await DBHelper.instance.saveRecoveryCode(code);
      }
      if (!mounted) return;
      setState(() => _checking = false);
      widget.onUnlocked();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Could not check the password: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(
      title: widget.schoolName,
      subtitle: 'Enter your admin password to continue.',
      child: Column(
        children: [
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _checking ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Unlock'),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      _ForgotPasswordScreen(onDone: widget.onUnlocked),
                ),
              );
            },
            child: const Text('Forgot your password?'),
          ),
        ],
      ),
    );
  }
}

class _ForgotPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const _ForgotPasswordScreen({required this.onDone});

  @override
  State<_ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<_ForgotPasswordScreen> {
  final TextEditingController _recoveryCodeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _recoveryCodeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final recoveryCode = _recoveryCodeCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();
    if (recoveryCode.isEmpty) {
      setState(() => _error = 'Enter your recovery code.');
      return;
    }
    if (password.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final reset = await DBHelper.instance.resetPasswordWithRecoveryCode(
        recoveryCode,
        password,
      );
      if (!mounted) return;
      if (!reset) {
        setState(() {
          _saving = false;
          _error = 'Recovery code is incorrect. Please check it and try again.';
        });
        return;
      }
      setState(() => _saving = false);
      Navigator.pop(context);
      widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not reset the password: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthCard(
      title: 'Reset Password',
      subtitle:
          'Enter the recovery code saved during setup, then choose a new password.',
      child: Column(
        children: [
          TextField(
            controller: _recoveryCodeCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Recovery Code',
              hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
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
            controller: _passwordCtrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'New Password',
              filled: true,
              fillColor: const Color(0xFFF5F7FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
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
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.red, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Set New Password'),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
