// auth_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'secrets.dart'; // FIX : clé Google déplacée dans secrets.dart (gitignored)

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _db = Supabase.instance.client;

  // ── Utilisateur courant ───────────────────────────────────────────────────
  User? get currentUser => _db.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  Stream<AuthState> get authStateChanges => _db.auth.onAuthStateChange;
  Session? get currentSession => _db.auth.currentSession;

  // ── Email / Password ──────────────────────────────────────────────────────
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String username,
    required String displayName,
  }) async {
    final existing =
        await _db
            .from('profiles')
            .select('id')
            .eq('username', username.trim().toLowerCase())
            .maybeSingle();
    if (existing != null) {
      throw Exception('Ce nom d\'utilisateur est déjà pris.');
    }

    final res = await _db.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'username': username.trim().toLowerCase(),
        'display_name': displayName.trim(),
      },
    );

    // FIX : si la création de profil échoue après le signUp,
    // on déconnecte l'utilisateur pour éviter un état partiel
    // (compte auth sans profil)
    if (res.user != null) {
      try {
        await _createProfile(
          userId: res.user!.id,
          username: username.trim().toLowerCase(),
          displayName: displayName.trim(),
        );
      } catch (e) {
        await _db.auth.signOut();
        throw Exception(
          'Erreur lors de la création du profil. Veuillez réessayer.',
        );
      }
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _db.auth.signInWithPassword(email: email.trim(), password: password);
  }

  // ── Google ────────────────────────────────────────────────────────────────
  Future<void> signInWithGoogle() async {
    // FIX : webClientId lu depuis secrets.dart, plus en dur dans le code
    final googleSignIn = GoogleSignIn(
      serverClientId: Secrets.googleWebClientId,
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) throw Exception('Connexion Google annulée.');

    final googleAuth = await googleUser.authentication;
    final accessToken = googleAuth.accessToken;
    final idToken = googleAuth.idToken;

    if (accessToken == null || idToken == null) {
      throw Exception('Tokens Google manquants.');
    }

    final res = await _db.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: accessToken,
    );

    if (res.user != null) {
      await _ensureProfile(
        userId: res.user!.id,
        email: res.user!.email ?? '',
        displayName: googleUser.displayName ?? googleUser.email,
        avatarUrl: googleUser.photoUrl,
      );
    }
  }

  // ── Déconnexion ───────────────────────────────────────────────────────────
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _db.auth.signOut();
  }

  // ── Réinitialisation mot de passe ─────────────────────────────────────────
  Future<void> resetPassword(String email) async {
    await _db.auth.resetPasswordForEmail(email.trim());
  }

  // ── Helpers privés ────────────────────────────────────────────────────────
  Future<void> _createProfile({
    required String userId,
    required String username,
    required String displayName,
    String? avatarUrl,
  }) async {
    await _db.from('profiles').upsert({
      'id': userId,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
    });
  }

  Future<void> _ensureProfile({
    required String userId,
    required String email,
    required String displayName,
    String? avatarUrl,
  }) async {
    final existing =
        await _db.from('profiles').select('id').eq('id', userId).maybeSingle();

    if (existing == null) {
      final base = email.split('@').first.replaceAll(RegExp(r'[^a-z0-9]'), '');
      final username =
          '${base}_${DateTime.now().millisecondsSinceEpoch % 9999}';
      await _createProfile(
        userId: userId,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
      );
    }
  }
}
