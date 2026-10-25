import 'package:flutter/material.dart';

import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_brand.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.authService});

  final AuthService? authService;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (widget.authService == null) {
      setState(
        () => _error = 'Account sync is not configured. Add Supabase keys.',
      );
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      if (_isRegistering) {
        await widget.authService!.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await widget.authService!.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.authService != null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: AppWordmark(fontSize: 18)),
                IconButton(
                  tooltip: 'Close account',
                  onPressed: _isBusy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _isRegistering ? 'Create your account' : 'Sign in to sync',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              configured
                  ? 'Sync across devices.'
                  : 'Add Supabase keys for sync.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _emailController,
              enabled: !_isBusy,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter a valid email'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              enabled: !_isBusy,
              obscureText: true,
              validator: (value) => value == null || value.length < 6
                  ? 'Use at least 6 characters'
                  : null,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontSize: 14),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !_isBusy ? _submit : null,
                child: Text(
                  _isBusy
                      ? 'Working…'
                      : _isRegistering
                      ? 'Create account'
                      : 'Sign in',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: !_isBusy
                    ? () => setState(() {
                        _isRegistering = !_isRegistering;
                        _error = null;
                      })
                    : null,
                child: Text(_isRegistering ? 'Sign in' : 'Create account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
