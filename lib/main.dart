import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'collection_service.dart';
import 'secrets.dart';

// ════════════════════════════════════════════════════════════════════════════
//  THÈME RÉTRO-ARCADE PREMIUM (mêmes tokens que collection_detail_screen.dart)
//  ⚠️ VISUEL UNIQUEMENT — toute la logique (auth, Supabase, presets…) intacte.
//  ▶ Polices : nécessite `google_fonts` (flutter pub add google_fonts).
//    Pour t'en passer : mets _kUseGoogleFonts = false.
//  💡 Astuce : ces tokens sont dupliqués entre fichiers ; tu pourras plus tard
//    les extraire dans un seul `arcade_theme.dart` partagé.
// ════════════════════════════════════════════════════════════════════════════
const _bg = Color(0xFF14101F);
const _bgDeep = Color(0xFF0D0A16);
const _surface = Color(0xFF211A33);
const _gold = Color(0xFFFFC83D);
const _goldDeep = Color(0xFFE0A91E);
const _teal = Color(0xFF21E6C1);
const _coral = Color(0xFFFF5D73);
const _cream = Color(0xFFF6EEDD);

final _creamDim = _cream.withValues(alpha: 0.62);
final _creamFaint = _cream.withValues(alpha: 0.34);
final _surfaceLine = _cream.withValues(alpha: 0.10);

const bool _kUseGoogleFonts = true;

TextStyle _arcade({
  double size = 16,
  Color color = _cream,
  double letterSpacing = 0.5,
  double? height,
  List<Shadow>? shadows,
}) {
  if (_kUseGoogleFonts) {
    return GoogleFonts.lilitaOne(
      fontSize: size,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      shadows: shadows,
    );
  }
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w900,
    letterSpacing: letterSpacing,
    height: height,
    shadows: shadows,
  );
}

TextStyle _pixel({double size = 9, Color? color, double letterSpacing = 1}) {
  final c = color ?? _creamFaint;
  if (_kUseGoogleFonts) {
    return GoogleFonts.silkscreen(
      fontSize: size,
      color: c,
      letterSpacing: letterSpacing,
    );
  }
  return TextStyle(
    fontSize: size,
    color: c,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
    letterSpacing: letterSpacing,
  );
}

TextStyle _body({
  double size = 13,
  Color? color,
  FontWeight weight = FontWeight.w600,
  double? height,
}) {
  final c = color ?? _cream;
  if (_kUseGoogleFonts) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      color: c,
      fontWeight: weight,
      height: height,
    );
  }
  return TextStyle(
    fontSize: size,
    color: c,
    fontWeight: weight,
    height: height,
  );
}

// ── Bouton arcade biseauté ──────────────────────────────────────────────────
class _ArcadeButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _ArcadeButton({required this.child, this.onTap});

  @override
  State<_ArcadeButton> createState() => _ArcadeButtonState();
}

class _ArcadeButtonState extends State<_ArcadeButton> {
  bool _down = false;
  void _set(bool v) => setState(() => _down = v);

  @override
  Widget build(BuildContext context) {
    final depth = _down ? 1.0 : 6.0;
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _down ? 5 : 0, 0),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(_gold, Colors.white, 0.12)!, _gold, _goldDeep],
            stops: const [0.0, 0.42, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: _goldDeep,
              offset: Offset(0, depth),
              blurRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              offset: Offset(0, depth + 6),
              blurRadius: 22,
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 3,
              left: 14,
              right: 14,
              child: IgnorePointer(
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.55),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DefaultTextStyle(
              style: _arcade(size: 15.5, color: const Color(0xFF2A1C00)),
              child: IconTheme(
                data: const IconThemeData(color: Color(0xFF2A1C00), size: 20),
                child: Center(child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _GhostButton({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        decoration: BoxDecoration(
          color: _cream.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _surfaceLine, width: 1.5),
        ),
        child: DefaultTextStyle(
          style: _body(size: 14.5, color: _cream, weight: FontWeight.w700),
          child: IconTheme(
            data: IconThemeData(color: _creamDim, size: 18),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

// ── Rayons en éventail (statique) ───────────────────────────────────────────
class _RayBurstPainter extends CustomPainter {
  final Color color;
  final double opacity;
  _RayBurstPainter(this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide * 1.4;
    final paint = Paint()..color = color.withValues(alpha: opacity);
    const rays = 30;
    for (int i = 0; i < rays; i++) {
      final a0 = i * 2 * math.pi / rays;
      final a1 = a0 + (math.pi / rays) * 0.55;
      final path =
          Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + radius * math.cos(a0), c.dy + radius * math.sin(a0))
            ..lineTo(c.dx + radius * math.cos(a1), c.dy + radius * math.sin(a1))
            ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RayBurstPainter old) => false;
}

Widget _rayBurst(Color color, double opacity) => Positioned.fill(
  child: IgnorePointer(
    child: ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback:
          (r) => const RadialGradient(
            colors: [Colors.black, Colors.transparent],
            stops: [0.0, 0.7],
          ).createShader(r),
      child: CustomPaint(painter: _RayBurstPainter(color, opacity)),
    ),
  ),
);

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.05);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => false;
}

// ════════════════════════════════════════════════════════════════════════════

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
          seedColor: _gold,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: _bgDeep,
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
        backgroundColor: _bgDeep,
        body: Center(child: CircularProgressIndicator(color: _gold)),
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

  static const List<Widget> _screens = [
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
        color: _bgDeep,
        border: Border(top: BorderSide(color: _surfaceLine, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 58,
          child: Row(
            children: List.generate(_items.length, (i) {
              final sel = i == currentIndex;
              final item = _items[i];
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Indicateur biseauté or sous l'icône active
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: sel ? 32 : 0,
                        height: 3,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          gradient:
                              sel
                                  ? const LinearGradient(
                                    colors: [_gold, _goldDeep],
                                  )
                                  : null,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow:
                              sel
                                  ? [
                                    BoxShadow(
                                      color: _gold.withValues(alpha: 0.5),
                                      blurRadius: 8,
                                    ),
                                  ]
                                  : [],
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color:
                              sel
                                  ? _gold.withValues(alpha: 0.14)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          sel ? item.$1 : item.$2,
                          color: sel ? _gold : _creamFaint,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.$3,
                        style: _body(
                          size: 10,
                          color: sel ? _gold : _creamFaint,
                          weight: sel ? FontWeight.w700 : FontWeight.w500,
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

// ════════════════════════════════════════════════════════════════════════════
//  CollectionScreen — écran HÉRITÉ (non utilisé par MainScreen) : laissé tel
//  quel, hors périmètre du reskin. Conserve son ancien style.
// ════════════════════════════════════════════════════════════════════════════
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

// ════════════════════════════════════════════════════════════════════════════
//  PROFIL — reskin arcade (logique intacte)
// ════════════════════════════════════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;
  bool _uploading = false;
  int _collectionsCount = 0;
  int _cardsCount = 0;
  int _friendsCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = await ProfileService.instance.getMyProfile();
    final friends = await ProfileService.instance.getFriends();
    final collections = await CollectionService.instance.getMyCollections();

    // On ne compte que les cartes des collections encore existantes.
    // Une collection supprimée disparaît de getMyCollections(), donc ses
    // cartes ne sont plus comptées.
    final cardIds = <String>{};
    for (final col in collections) {
      final ids = await CollectionService.instance.getCollectionCardIds(col.id);
      cardIds.addAll(ids);
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _friendsCount = friends.length;
        _collectionsCount = collections.length;
        _cardsCount = cardIds.length;
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
            content: Text(
              'Erreur upload : $e',
              style: _body(color: Colors.white),
            ),
            backgroundColor: _coral,
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

  void _showEditDisplayName() {
    final ctrl = TextEditingController(text: _profile?.displayName ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: _surfaceLine, width: 1.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _creamFaint,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Modifier le nom', style: _arcade(size: 18)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: _body(color: _cream),
                    decoration: InputDecoration(
                      hintText: 'Ton prénom ou pseudo',
                      hintStyle: _body(color: _creamFaint),
                      filled: true,
                      fillColor: _cream.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: _gold, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ArcadeButton(
                    onTap: () async {
                      if (ctrl.text.trim().isEmpty) return;
                      Navigator.pop(context);
                      final updated = await ProfileService.instance
                          .updateProfile(displayName: ctrl.text.trim());
                      if (mounted) setState(() => _profile = updated);
                    },
                    child: const Text('ENREGISTRER'),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      body:
          _loading
              ? const Center(child: CircularProgressIndicator(color: _gold))
              : Stack(
                children: [
                  CustomScrollView(
                    slivers: [
                      // ── Hero header ────────────────────────────────────────
                      SliverToBoxAdapter(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomCenter,
                                    colors: [Color(0xFF2A1E47), _bgDeep],
                                  ),
                                ),
                              ),
                            ),
                            _rayBurst(_gold, 0.07),
                            SafeArea(
                              bottom: false,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  24,
                                ),
                                child: Column(
                                  children: [
                                    // Avatar bagué or
                                    GestureDetector(
                                      onTap: _showAvatarPicker,
                                      child: Stack(
                                        alignment: Alignment.bottomRight,
                                        children: [
                                          _uploading
                                              ? _avatarRing(
                                                const Center(
                                                  child:
                                                      CircularProgressIndicator(
                                                        color: _gold,
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                              : _buildAvatarWidget(),
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [_gold, _goldDeep],
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: _bgDeep,
                                                width: 2,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.edit_rounded,
                                              color: Color(0xFF2A1C00),
                                              size: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    // Nom + bouton edit
                                    GestureDetector(
                                      onTap: _showEditDisplayName,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _profile?.displayName.isNotEmpty ==
                                                    true
                                                ? _profile!.displayName
                                                : 'Sans nom',
                                            style: _arcade(
                                              size: 24,
                                              color: Colors.white,
                                              shadows: const [
                                                Shadow(
                                                  color: Colors.black45,
                                                  offset: Offset(2, 3),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.edit_rounded,
                                            color: _creamFaint,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Username pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _teal.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: _teal.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        '@${_profile?.username ?? ''}',
                                        style: _body(
                                          size: 12.5,
                                          color: _teal,
                                          weight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    // Stats
                                    Row(
                                      children: [
                                        _statCard(
                                          'Collections',
                                          _collectionsCount,
                                          Icons.auto_awesome_rounded,
                                          _gold,
                                        ),
                                        const SizedBox(width: 10),
                                        _statCard(
                                          'Cartes',
                                          _cardsCount,
                                          Icons.style_rounded,
                                          _teal,
                                        ),
                                        const SizedBox(width: 10),
                                        _statCard(
                                          'Amis',
                                          _friendsCount,
                                          Icons.people_rounded,
                                          _coral,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── Contenu ────────────────────────────────────────────
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _sectionLabel('Compte'),
                            const SizedBox(height: 10),
                            _accountTile(
                              icon: Icons.badge_rounded,
                              label: 'Nom affiché',
                              value: _profile?.displayName ?? '',
                              onTap: _showEditDisplayName,
                              showChevron: true,
                            ),
                            const SizedBox(height: 8),
                            _accountTile(
                              icon: Icons.alternate_email_rounded,
                              label: 'Identifiant',
                              value: '@${_profile?.username ?? ''}',
                              onTap: null,
                              showChevron: false,
                            ),
                            const SizedBox(height: 8),
                            _accountTile(
                              icon: Icons.email_rounded,
                              label: 'Email',
                              value:
                                  AuthService.instance.currentUser?.email ?? '',
                              onTap: null,
                              showChevron: false,
                            ),
                            const SizedBox(height: 28),

                            // Déconnexion
                            GestureDetector(
                              onTap: () => AuthService.instance.signOut(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: _coral.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _coral.withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.logout_rounded,
                                      color: _coral,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Se déconnecter',
                                      style: _body(
                                        color: _coral,
                                        size: 15,
                                        weight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                  // Scanlines CRT
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _ScanlinePainter()),
                    ),
                  ),
                ],
              ),
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color accent) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _surfaceLine, width: 1.5),
          ),
          child: Column(
            children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(height: 6),
              Text('$value', style: _arcade(size: 22, color: _cream)),
              const SizedBox(height: 3),
              Text(
                label.toUpperCase(),
                style: _pixel(
                  size: 7.5,
                  color: _creamFaint,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _sectionLabel(String label) => Text(
    label.toUpperCase(),
    style: _pixel(size: 9, color: _creamFaint, letterSpacing: 1.5),
  );

  Widget _accountTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback? onTap,
    required bool showChevron,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _surfaceLine, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: _gold, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: _body(size: 11, color: _creamFaint)),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: _body(size: 14, color: _cream),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showChevron)
            Icon(Icons.chevron_right_rounded, color: _creamFaint, size: 20),
        ],
      ),
    ),
  );

  // Anneau or réutilisable autour du contenu d'avatar (90px).
  Widget _avatarRing(Widget child) => Container(
    width: 90,
    height: 90,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE89A), _gold, _goldDeep],
      ),
      boxShadow: [
        BoxShadow(
          color: _gold.withValues(alpha: 0.45),
          blurRadius: 20,
          spreadRadius: 1,
        ),
      ],
    ),
    child: ClipOval(
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _surface),
        child: SizedBox.expand(child: child),
      ),
    ),
  );

  Widget _buildAvatarWidget() {
    final av = _profile?.avatarUrl;
    if (av != null && av.startsWith('preset:')) {
      final emoji = av.replaceFirst('preset:', '');
      return _avatarRing(
        Center(child: Text(emoji, style: const TextStyle(fontSize: 42))),
      );
    }
    if (av != null && av.isNotEmpty) {
      return _avatarRing(
        Image.network(
          av,
          key: ValueKey(av),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultAvatarInner(),
        ),
      );
    }
    return _avatarRing(_defaultAvatarInner());
  }

  Widget _defaultAvatarInner() => Center(
    child: Text(
      _profile?.displayName.isNotEmpty == true
          ? _profile!.displayName[0].toUpperCase()
          : '?',
      style: _arcade(size: 38, color: _gold),
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
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: _surfaceLine, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _creamFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text('Choisir un avatar', style: _arcade(size: 18)),
          const SizedBox(height: 20),
          if (!kIsWeb)
            _GhostButton(
              onTap: onPickGallery,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Choisir depuis la galerie'),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'AVATARS PRÉDÉFINIS',
              style: _pixel(size: 8.5, color: _creamFaint, letterSpacing: 2),
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
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _surfaceLine, width: 1.5),
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
