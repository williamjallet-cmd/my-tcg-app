import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'card_creator_screen.dart';
import 'card_storage.dart';
import 'card_model.dart';
import 'collections_screen.dart';
import 'friends_screen.dart';
import 'auth_service.dart';
import 'auth_screen.dart';
import 'profile_service.dart';
import 'secrets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // supabase_flutter v2 restaure la session PENDANT initialize()
  // Donc currentSession est disponible immédiatement après
  await Supabase.initialize(
    url: Secrets.supabaseUrl,
    anonKey: Secrets.supabaseAnonKey,
  );
  runApp(const TCGApp());
}

class TCGApp extends StatelessWidget {
  const TCGApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TCG App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();
  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool _ready = false;
  bool _loggedIn = false;
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    // supabase_flutter v2 restaure la session dans initialize()
    // On lit currentSession directement — pas besoin d'attendre initialSession
    final session = Supabase.instance.client.auth.currentSession;
    if (mounted) {
      setState(() {
        _ready = true;
        _loggedIn = session != null;
      });
    }

    // Écoute les changements ultérieurs (connexion / déconnexion)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;
        switch (data.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.tokenRefreshed:
            setState(() => _loggedIn = true);
            break;
          case AuthChangeEvent.signedOut:
            setState(() => _loggedIn = false);
            break;
          default:
            break;
        }
      },
      // FIX : capture l'AuthRetryableFetchException (réseau coupé / token expiré)
      // au lieu de laisser une exception non gérée crasher silencieusement l'app
      onError: (Object error, StackTrace stack) {
        if (!mounted) return;
        debugPrint('Auth stream error (réseau/token) : $error');
        // Token expiré + refresh impossible → déconnecter proprement
        if (error is AuthException ||
            error.toString().contains('AuthRetryableFetchException')) {
          setState(() => _loggedIn = false);
          // Déconnexion propre côté Supabase (ignore les erreurs réseau)
          Supabase.instance.client.auth.signOut().catchError((_) {});
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF080814),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
        ),
      );
    }
    return _loggedIn ? const MainScreen() : const AuthScreen();
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    CollectionsScreen(),
    FriendsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  const _BottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    (Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, 'Collections'),
    (Icons.people_rounded, Icons.people_outline_rounded, 'Amis'),
    (Icons.person_rounded, Icons.person_outline_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1E),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: List.generate(_items.length, (i) {
              final sel = i == currentIndex;
              final item = _items[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child:
                            sel
                                ? ShaderMask(
                                  key: ValueKey('on_$i'),
                                  shaderCallback:
                                      (b) => const LinearGradient(
                                        colors: [
                                          Color(0xFF7C3AED),
                                          Color(0xFFDB2777),
                                        ],
                                      ).createShader(b),
                                  child: Icon(
                                    item.$1,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                )
                                : Icon(
                                  item.$2,
                                  key: ValueKey('off_$i'),
                                  color: Colors.white30,
                                  size: 26,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.$3,
                        style: TextStyle(
                          color: sel ? const Color(0xFFB06EF3) : Colors.white30,
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});
  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  List<SavedCard> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    final cards = await CardStorage.loadCards();
    if (mounted) {
      setState(() {
        _cards = cards;
        _loading = false;
      });
    }
  }

  Color _rc(Rarity r) {
    switch (r) {
      case Rarity.legendary:
        return const Color(0xFFFFD700);
      case Rarity.epic:
        return const Color(0xFF9C27B0);
      case Rarity.rare:
        return const Color(0xFF2196F3);
      case Rarity.uncommon:
        return const Color(0xFF4CAF50);
      case Rarity.common:
        return const Color(0xFF9E9E9E);
    }
  }

  String _rl(Rarity r) {
    switch (r) {
      case Rarity.legendary:
        return 'Légendaire';
      case Rarity.epic:
        return 'Épique';
      case Rarity.rare:
        return 'Rare';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.common:
        return 'Commun';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: const Color(0xFF080814),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'Ma Collection (${_cards.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0533), Color(0xFF080814)],
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CardCreatorScreen(),
                      ),
                    );
                    _loadCards();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
              ),
            )
          else if (_cards.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback:
                          (b) => const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                          ).createShader(b),
                      child: const Icon(
                        Icons.style,
                        size: 80,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Aucune carte',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Appuie sur + pour créer ta première carte !',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _buildCard(_cards[i]),
                  childCount: _cards.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.7,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCard(SavedCard card) {
    final rc = _rc(card.rarity);
    return GestureDetector(
      onLongPress: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Supprimer ?',
                  style: TextStyle(color: Colors.white),
                ),
                content: Text(
                  'Supprimer « ${card.name} » ?',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text(
                      'Supprimer',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
        );
        if (ok == true) {
          await CardStorage.deleteCard(card.id);
          _loadCards();
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rc, width: 2),
          color: const Color(0xFF16213E),
          boxShadow: [
            BoxShadow(color: rc.withValues(alpha: 0.3), blurRadius: 8),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              if (card.imageBytes != null)
                Positioned.fill(
                  child: Image.memory(card.imageBytes!, fit: BoxFit.cover),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: rc.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _rl(card.rarity),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _presetAvatars = [
  '🦊',
  '🐺',
  '🦁',
  '🐯',
  '🐻',
  '🐼',
  '🐨',
  '🦝',
  '🐸',
  '🦉',
  '🦋',
  '🐉',
  '🦄',
  '🐬',
  '🦈',
  '🌙',
  '⚡',
  '🔥',
  '💎',
  '👑',
  '🎮',
  '🃏',
  '🌈',
  '🍀',
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await ProfileService.instance.getMyProfile();
    if (mounted) {
      setState(() {
        _profile = p;
        _loading = false;
      });
    }
  }

  void _showAvatarPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _AvatarPickerSheet(
            onPickGallery: _pickFromGallery,
            onPickPreset: _pickPreset,
          ),
    );
  }

  Future<void> _pickFromGallery() async {
    Navigator.pop(context);
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      imageQuality: 80,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final userId = AuthService.instance.currentUser!.id;
      final path = 'avatars/$userId.jpg';
      await Supabase.instance.client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(path);
      final cacheBustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
      final updated = await ProfileService.instance.updateProfile(
        avatarUrl: cacheBustedUrl,
      );
      if (mounted) {
        setState(() {
          _profile = updated;
          _uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur upload : $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _pickPreset(String emoji) async {
    Navigator.pop(context);
    setState(() => _uploading = true);
    try {
      final updated = await ProfileService.instance.updateProfile(
        avatarUrl: 'preset:$emoji',
      );
      if (mounted) {
        setState(() {
          _profile = updated;
          _uploading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: const Color(0xFF080814),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: const Text(
                'Mon Profil',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0533), Color(0xFF080814)],
                  ),
                ),
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Center(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: _showAvatarPicker,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              _uploading
                                  ? Container(
                                    width: 90,
                                    height: 90,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [
                                          Color(0xFF7C3AED),
                                          Color(0xFFDB2777),
                                        ],
                                      ),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                  : _buildAvatarWidget(),
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF7C3AED),
                                      Color(0xFFDB2777),
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF080814),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _profile?.displayName ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF7C3AED,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(
                                0xFF7C3AED,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '@${_profile?.username ?? ''}',
                            style: const TextStyle(
                              color: Color(0xFFB06EF3),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                  _infoTile(
                    Icons.email_rounded,
                    AuthService.instance.currentUser?.email ?? '',
                  ),
                  const SizedBox(height: 32),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.red.withValues(alpha: 0.15),
                          Colors.red.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.logout_rounded,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Se déconnecter',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => AuthService.instance.signOut(),
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAvatarWidget() {
    final av = _profile?.avatarUrl;
    if (av != null && av.startsWith('preset:')) {
      final emoji = av.replaceFirst('preset:', '');
      return Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 44))),
      );
    }
    if (av != null && av.isNotEmpty) {
      return Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            av,
            key: ValueKey(av),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar(),
          ),
        ),
      );
    }
    return _defaultAvatar();
  }

  Widget _defaultAvatar() => Container(
    width: 90,
    height: 90,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.5),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Center(
      child: Text(
        _profile?.displayName.isNotEmpty == true
            ? _profile!.displayName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 38,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  Widget _infoTile(IconData icon, String value) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Row(
      children: [
        Icon(icon, color: const Color(0xFF7C3AED), size: 20),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AvatarPickerSheet extends StatelessWidget {
  final VoidCallback onPickGallery;
  final void Function(String) onPickPreset;
  const _AvatarPickerSheet({
    required this.onPickGallery,
    required this.onPickPreset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Choisir un avatar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          if (!kIsWeb)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.white70,
                ),
                label: const Text(
                  'Choisir depuis la galerie',
                  style: TextStyle(color: Colors.white70),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'AVATARS PRÉDÉFINIS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _presetAvatars.length,
            itemBuilder:
                (_, i) => GestureDetector(
                  onTap: () => onPickPreset(_presetAvatars[i]),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _presetAvatars[i],
                        style: const TextStyle(fontSize: 22),
                      ),
                    ),
                  ),
                ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
