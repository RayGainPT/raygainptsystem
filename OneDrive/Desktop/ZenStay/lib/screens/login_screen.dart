import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _showError(String message) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwCtrl.text,
      );
      if (!mounted) return;
      context.go('/dashboard/euroescape');
    } on FirebaseAuthException catch (e) {
      await _showError(e.message ?? 'Authentication failed');
    } catch (e) {
      await _showError(e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      await _showError('Please enter the account email to reset the password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password reset sent to $email')));
    } catch (e) {
      await _showError(e.toString());
    }
  }

  InputDecoration _insetDecoration(String label, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    // Example brand colors; main app theme may provide better values.
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final useGlass = scaffoldBg.computeLuminance() < 0.95;

    Widget formCard = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo placeholder
              Align(
                alignment: Alignment.center,
                child: Container(
                  height: 72,
                  width: 72,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                      child: Text('Z',
                          style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: primary))),
                ),
              ),

              const SizedBox(height: 16),
              Text('Welcome Back',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 18),

              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: _insetDecoration('Email'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty)
                    return 'Please enter your email';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pwCtrl,
                obscureText: _obscure,
                decoration: _insetDecoration('Password',
                    suffix: IconButton(
                        icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure))),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter your password';
                  if (v.length < 6)
                    return 'Password must be at least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(
                    value: _rememberMe,
                    onChanged: (v) => setState(() => _rememberMe = v ?? false)),
                const SizedBox(width: 6),
                Text('Remember Me', style: GoogleFonts.poppins()),
                const Spacer(),
                TextButton(
                    onPressed: _forgotPassword,
                    child:
                        Text('Forgot Password?', style: GoogleFonts.poppins())),
              ]),
              const SizedBox(height: 18),

              // Gradient button
              SizedBox(
                height: 48,
                child: InkWell(
                  onTap: _loading ? null : _submit,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [primary, secondary]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                            color: primary.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: Center(
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text('Login',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/'),
                child: Text('Back to landing', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(minHeight: MediaQuery.of(context).size.height),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Center(
                child: useGlass
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            margin: const EdgeInsets.all(24),
                            padding: const EdgeInsets.all(0),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.08))),
                            child: formCard,
                          ),
                        ),
                      )
                    : Card(
                        elevation: 18,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        margin: const EdgeInsets.all(24),
                        child: formCard,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 8),
                child: Text('Powered by Zenthora',
                    style: GoogleFonts.poppins(
                        color: Colors.grey.shade500, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
