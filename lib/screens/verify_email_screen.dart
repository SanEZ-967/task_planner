import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerifyEmailScreen extends StatefulWidget {
  final VoidCallback onRefresh;

  const VerifyEmailScreen({super.key, required this.onRefresh});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? _autoCheckTimer;
  bool _isChecking = false;
  bool _isResending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Checks automatically every few seconds, so switching back to the app
    // after clicking the email link usually just works with no button tap
    // needed. The manual button below exists for an instant check on demand.
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkVerified());
  }

  @override
  void dispose() {
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified() async {
    if (_isChecking) return;
    setState(() {
      _isChecking = true;
    });
    try {
      try {
        await FirebaseAuth.instance.currentUser?.reload();
      } catch (_) {
        // Offline or a temporary error: skip this check, the timer tries again.
        return;
      }
      widget.onRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _resendEmail() async {
    setState(() {
      _isResending = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      setState(() {
        _message = 'Verification email sent again — check your inbox.';
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _message = e.code == 'too-many-requests'
            ? 'Please wait a bit before requesting another email.'
            : 'Could not send the email. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_email_unread_outlined, size: 64),
              const SizedBox(height: 16),
              const Text(
                'We sent a verification link to:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                email,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Click the link in that email, then come back here — this screen checks automatically every few seconds.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isChecking ? null : _checkVerified,
                child: _isChecking
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("I've verified — check again"),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isResending ? null : _resendEmail,
                child: Text(_isResending ? 'Sending...' : 'Resend verification email'),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                child: const Text('Used the wrong email? Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}