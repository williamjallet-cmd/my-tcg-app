// auth_screen.dart — connexion + inscription + "se souvenir de moi"

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = false;
  bool _rememberMe = true; // cochée par défaut

  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl = TextEditingController();
  final _regUsernameCtrl = TextEditingController();
  final _regNameCtrl = TextEditingController();

  bool _obscureLogin = true;
  bool _obscureReg = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadSavedEmail();
  }

  Future<void> _loadSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email') ?? '';
    final rememberMe = prefs.getBool('remember_me') ?? true;
    setState(() {
      _rememberMe = rememberMe;
      if (rememberMe && savedEmail.isNotEmpty) {
        _loginEmailCtrl.text = savedEmail;
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regUsernameCtrl.dispose();
    _regNameCtrl.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
    );
  }

  Future<void> _login() async {
    if (_loginEmailCtrl.text.isEmpty || _loginPassCtrl.text.isEmpty) {
      _showError('Remplis tous les champs.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signInWithEmail(
        email: _loginEmailCtrl.text,
        password: _loginPassCtrl.text,
      );
      // Sauvegarde la préférence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', _rememberMe);
      if (_rememberMe) {
        await prefs.setString('saved_email', _loginEmailCtrl.text.trim());
      } else {
        await prefs.remove('saved_email');
      }
    } catch (e) {
      _showError('Erreur : ${_friendlyError(e.toString())}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_regEmailCtrl.text.isEmpty ||
        _regPassCtrl.text.isEmpty ||
        _regUsernameCtrl.text.isEmpty ||
        _regNameCtrl.text.isEmpty) {
      _showError('Remplis tous les champs.');
      return;
    }
    if (_regPassCtrl.text.length < 6) {
      _showError('Le mot de passe doit faire au moins 6 caractères.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.instance.signUpWithEmail(
        email: _regEmailCtrl.text,
        password: _regPassCtrl.text,
        username: _regUsernameCtrl.text,
        displayName: _regNameCtrl.text,
      );
      _showSuccess('Compte créé ! Tu peux te connecter.');
      _tabCtrl.animateTo(0);
    } catch (e) {
      _showError('Erreur : ${_friendlyError(e.toString())}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }



  Future<void> _resetPassword() async {
    if (_loginEmailCtrl.text.isEmpty) {
      _showError('Entre ton email d\'abord.');
      return;
    }
    await AuthService.instance.resetPassword(_loginEmailCtrl.text);
    _showSuccess('Email de réinitialisation envoyé !');
  }

  String _friendlyError(String e) {
    if (e.contains('Invalid login')) return 'Email ou mot de passe incorrect.';
    if (e.contains('already registered')) return 'Cet email est déjà utilisé.';
    if (e.contains('Password should')) return 'Mot de passe trop court.';
    if (e.contains('username')) return 'Nom d\'utilisateur déjà pris.';
    return e;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 48),

              // Logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha:0.5),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'TCG App',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ta collection de cartes',
                style: TextStyle(
                  color: Colors.white.withValues(alpha:0.4),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 36),

              // Tabs connexion / inscription
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16213E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white38,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(text: 'Connexion'),
                    Tab(text: 'Inscription'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                height: 460,
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [_loginTab(), _registerTab()],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Onglet connexion ──────────────────────────────────────────────────────
  Widget _loginTab() => Column(
    children: [
      _field(
        _loginEmailCtrl,
        'Email',
        Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 14),
      _field(
        _loginPassCtrl,
        'Mot de passe',
        Icons.lock_outline,
        obscure: _obscureLogin,
        toggleObscure: () => setState(() => _obscureLogin = !_obscureLogin),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _resetPassword,
          child: Text(
            'Mot de passe oublié ?',
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.45),
              fontSize: 12,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),

      // ── Se souvenir de moi ────────────────────────────────────────────────
      GestureDetector(
        onTap: () => setState(() => _rememberMe = !_rememberMe),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                _rememberMe
                    ? const Color(0xFF7C3AED).withValues(alpha:0.12)
                    : Colors.white.withValues(alpha:0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  _rememberMe
                      ? const Color(0xFF7C3AED).withValues(alpha:0.5)
                      : Colors.white.withValues(alpha:0.08),
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient:
                      _rememberMe
                          ? const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                          )
                          : null,
                  color: _rememberMe ? null : Colors.white.withValues(alpha:0.08),
                  border:
                      _rememberMe
                          ? null
                          : Border.all(color: Colors.white.withValues(alpha:0.2)),
                ),
                child:
                    _rememberMe
                        ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 14,
                        )
                        : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Se connecter automatiquement',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Rester connecté à ce compte',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha:0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _rememberMe ? Icons.lock_open_rounded : Icons.lock_rounded,
                color:
                    _rememberMe
                        ? const Color(0xFFB06EF3)
                        : Colors.white.withValues(alpha:0.3),
                size: 18,
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: 16),
      _submitButton('Se connecter', _login),
    ],
  );

  // ── Onglet inscription ────────────────────────────────────────────────────
  Widget _registerTab() => Column(
    children: [
      _field(_regNameCtrl, 'Prénom / Pseudo affiché', Icons.badge_outlined),
      const SizedBox(height: 12),
      _field(_regUsernameCtrl, 'Nom d\'utilisateur (@)', Icons.alternate_email),
      const SizedBox(height: 12),
      _field(
        _regEmailCtrl,
        'Email',
        Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      _field(
        _regPassCtrl,
        'Mot de passe (min. 6 car.)',
        Icons.lock_outline,
        obscure: _obscureReg,
        toggleObscure: () => setState(() => _obscureReg = !_obscureReg),
      ),
      const SizedBox(height: 20),
      _submitButton('Créer mon compte', _register),
    ],
  );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) => TextField(
    controller: ctrl,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha:0.3)),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      suffixIcon:
          toggleObscure != null
              ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: toggleObscure,
              )
              : null,
      filled: true,
      fillColor: const Color(0xFF16213E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
      ),
    ),
  );

  Widget _submitButton(String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha:0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _loading ? null : onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child:
                  _loading
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                      : Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
            ),
          ),
        ),
      ),
    ),
  );
}
