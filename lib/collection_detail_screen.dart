// collection_detail_screen.dart
// ════════════════════════════════════════════════════════════════════════════
//  RESKIN « RÉTRO-ARCADE PREMIUM » (réf. handoff Brokemon / Balatro)
//  ⚠️ VISUEL UNIQUEMENT — toute la logique est conservée à l'identique :
//     • FIX 1 : isolation des cartes par collection
//     • FIX 2 : mode déplacement avec Listener (bypass de l'arène de gestes)
//     • timers, Supabase, tirage pondéré, streak, customizer : INCHANGÉS
//
//  ▶ POLICES : ce fichier utilise le package `google_fonts`
//    (Lilita One = titres arcade, Silkscreen = labels pixel, Plus Jakarta Sans
//     = corps). Ajoute-le une seule fois :
//        flutter pub add google_fonts
//    Si tu ne veux PAS de dépendance, va voir le bloc « FONTS » plus bas :
//    mets _kUseGoogleFonts = false et tu retombes sur les polices système.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_service.dart';
import 'pack_system.dart';
import 'card_storage.dart';
import 'card_media_service.dart';
import 'card_model.dart';
import 'pack_opening_screen.dart';
import 'card_inspector_screen.dart';
import 'pack_customizer_screen.dart';
import 'manage_members_screen.dart';
import 'streak_service.dart';

// ════════════════════════════════════════════════════════════════════════════
//  TOKENS DE DESIGN
// ════════════════════════════════════════════════════════════════════════════
const _bg = Color(0xFF14101F); // aubergine nuit
const _bgDeep = Color(0xFF0D0A16); // fond profond
const _surface = Color(0xFF211A33);
const _gold = Color(0xFFFFC83D); // accent signature
const _goldDeep = Color(0xFFE0A91E);
const _teal = Color(0xFF21E6C1);
const _coral = Color(0xFFFF5D73);
const _cream = Color(0xFFF6EEDD);

final _creamDim = _cream.withValues(alpha: 0.62);
final _creamFaint = _cream.withValues(alpha: 0.34);
final _surfaceLine = _cream.withValues(alpha: 0.10);

// Couleurs de rareté (cadre + glow) — palette arcade
const _rarColors = {
  Rarity.common: Color(0xFF9AA0B0),
  Rarity.uncommon: Color(0xFF3FD17A),
  Rarity.rare: Color(0xFF2FA8FF),
  Rarity.epic: Color(0xFFB45CFF),
  Rarity.legendary: Color(0xFFFFC83D),
};

// ════════════════════════════════════════════════════════════════════════════
//  FONTS — bascule unique
// ════════════════════════════════════════════════════════════════════════════
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

// ════════════════════════════════════════════════════════════════════════════
//  LOGIQUE DE TIRAGE — INCHANGÉE
// ════════════════════════════════════════════════════════════════════════════
const _dropRates = {
  Rarity.common: 50,
  Rarity.uncommon: 28,
  Rarity.rare: 14,
  Rarity.epic: 6,
  Rarity.legendary: 2,
};
const _dropLabels = {
  Rarity.common: '50%',
  Rarity.uncommon: '28%',
  Rarity.rare: '14%',
  Rarity.epic: '6%',
  Rarity.legendary: '2%',
};

SavedCard _weightedPick(List<SavedCard> pool, math.Random rng) {
  final byR = <Rarity, List<SavedCard>>{};
  for (final c in pool) {
    byR.putIfAbsent(c.rarity, () => []).add(c);
  }
  int total = byR.keys.fold(0, (s, r) => s + (_dropRates[r] ?? 0));
  if (total == 0) return pool[rng.nextInt(pool.length)];
  int roll = rng.nextInt(total);
  for (final r in [
    Rarity.common,
    Rarity.uncommon,
    Rarity.rare,
    Rarity.epic,
    Rarity.legendary,
  ]) {
    if (!byR.containsKey(r)) continue;
    roll -= _dropRates[r]!;
    if (roll < 0) {
      final p = byR[r]!;
      return p[rng.nextInt(p.length)];
    }
  }
  return pool[rng.nextInt(pool.length)];
}

// Palettes par série (utilisées pour la bannière) — INCHANGÉES
const _palettes = [
  [Color(0xFF7C3AED), Color(0xFF2563EB)],
  [Color(0xFFDB2777), Color(0xFF7C3AED)],
  [Color(0xFF059669), Color(0xFF2563EB)],
  [Color(0xFFD97706), Color(0xFFDB2777)],
  [Color(0xFF0891B2), Color(0xFF7C3AED)],
  [Color(0xFFDC2626), Color(0xFFD97706)],
];
List<Color> _pal(String id) =>
    _palettes[id.codeUnits.fold(0, (a, b) => a + b) % _palettes.length];

String _obtKey(String colId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return 'obtained_${uid}_$colId';
}

String _catKey(String colId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return 'local_cat_${uid}_$colId';
}

String _seenKey(String colId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return 'seen_${uid}_$colId';
}

// ════════════════════════════════════════════════════════════════════════════
//  PRIMITIVES ARCADE PARTAGÉES
// ════════════════════════════════════════════════════════════════════════════

/// Bouton arcade biseauté qui s'enfonce au clic (translateY +5, ombre réduite).
class _ArcadeButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool big;
  const _ArcadeButton({required this.child, this.onTap, this.big = false});

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
        padding: EdgeInsets.symmetric(
          vertical: widget.big ? 17 : 13,
          horizontal: widget.big ? 26 : 20,
        ),
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
            // gleam (reflet haut)
            Positioned(
              top: 3,
              left: 14,
              right: 14,
              child: IgnorePointer(
                child: Container(
                  height: widget.big ? 16 : 12,
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
              style: _arcade(
                size: widget.big ? 19 : 15.5,
                color: const Color(0xFF2A1C00),
              ),
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

Widget _pixelBadge(
  String text, {
  Color? color,
  bool filled = false,
  Color? bg,
  Color? borderColor,
  double size = 8.5,
}) {
  final c = color ?? _cream;
  return Container(
    padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
    decoration: BoxDecoration(
      color: filled ? c : (bg ?? Colors.transparent),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(
        color: filled ? Colors.transparent : (borderColor ?? c),
        width: 1.5,
      ),
    ),
    child: Text(
      text.toUpperCase(),
      style: _pixel(size: size, color: filled ? _bg : c, letterSpacing: 0.5),
    ),
  );
}

/// Rayons en éventail derrière la bannière (statique, léger).
class _RayBurstPainter extends CustomPainter {
  final Color color;
  final double opacity;
  _RayBurstPainter(this.color, this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final radius = size.longestSide * 1.2;
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
            stops: [0.08, 0.62],
          ).createShader(r),
      child: CustomPaint(painter: _RayBurstPainter(color, opacity)),
    ),
  ),
);

/// Scanlines CRT globales, très discrètes.
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
//  ÉCRAN DÉTAIL DE SÉRIE
// ════════════════════════════════════════════════════════════════════════════

class CollectionDetailScreen extends StatefulWidget {
  final CollectionModel collection;
  final String myUserId;
  const CollectionDetailScreen({
    super.key,
    required this.collection,
    required this.myUserId,
  });
  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Duration _remaining = Duration.zero;
  bool _canOpen = false;
  Timer? _timer;
  List<SavedCard> _allCards = [];
  List<SavedCard> _obtainedCards = [];
  Set<String> _catalogueIds = {};
  bool _loading = true;
  // ✨ Polish : doublons (quantité par carte) + badge NEW (cartes non consultées)
  Map<String, int> _qtyByCard = {};
  Set<String> _seenIds = {};
  String _sortBy = 'rarity';
  bool _sortAsc = true;
  // FIX scroll : état remonté depuis _CardCreator pour bloquer
  // TabBarView (gauche/droite) ET NestedScrollView (haut/bas)
  bool _cardMoveMode = false;
  // Reflète les modifs du pack faites par le proprio
  CollectionModel? _editedCollection;
  CollectionModel get _col => _editedCollection ?? widget.collection;

  bool _isAdmin = false;

  // Onglet Admin : 'menu' | 'create' | 'delete'
  String _adminMode = 'menu';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _isAdmin = widget.collection.isOwnedBy(widget.myUserId);
    _loadAdmin();
    _syncAndLoad();
  }

  Future<void> _loadAdmin() async {
    final admin = await CollectionService.instance.amIAdminOf(
      widget.collection.id,
      widget.collection.ownerUserId,
    );
    if (mounted && admin != _isAdmin) setState(() => _isAdmin = admin);
  }

  Widget _customizePackBtn() => _GhostButton(
    onTap: _openCustomizer,
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.tune_rounded, size: 18),
        SizedBox(width: 8),
        Text('Personnaliser le pack'),
      ],
    ),
  );

  Widget _manageMembersBtn() => _GhostButton(
    onTap:
        () => Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ManageMembersScreen(
                  collection: _col,
                  myUserId: widget.myUserId,
                ),
          ),
        ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.group_rounded, size: 18),
        SizedBox(width: 8),
        Text('Gérer les membres'),
      ],
    ),
  );

  Future<void> _openCustomizer() async {
    final updated = await Navigator.push<CollectionModel>(
      context,
      MaterialPageRoute(builder: (_) => PackCustomizerScreen(collection: _col)),
    );
    if (updated != null && mounted) {
      setState(() => _editedCollection = updated);
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _syncAndLoad() async {
    await PackSystem.syncFromSupabase(widget.collection.id);
    _startTimer();
    await _loadCards();
  }

  void _startTimer() async {
    final r = await PackSystem.timeUntilNextPack(widget.collection.id);
    final c = await PackSystem.canOpenPack(widget.collection.id);
    if (mounted) {
      setState(() {
        _remaining = r;
        _canOpen = c;
      });
    }
    if (!c) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _timer?.cancel();
          return;
        }
        final next = _remaining - const Duration(seconds: 1);
        if (next <= Duration.zero) {
          _timer?.cancel();
          setState(() {
            _remaining = Duration.zero;
            _canOpen = true;
          });
        } else {
          setState(() => _remaining = next);
        }
      });
    }
  }

  Future<void> _loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final List<SavedCard> all = await CardStorage.loadCards();
    final Set<String> obtIds =
        (prefs.getStringList(_obtKey(widget.collection.id)) ?? []).toSet();
    final Set<String> catIds =
        (prefs.getStringList(_catKey(widget.collection.id)) ?? []).toSet();

    // Badge NEW : cartes déjà consultées. Au premier lancement, tout
    // l'existant est considéré comme déjà vu (pas de déluge de badges).
    final seenStored = prefs.getStringList(_seenKey(widget.collection.id));
    final Set<String> seenIds = (seenStored ?? obtIds.toList()).toSet();
    if (seenStored == null) {
      await prefs.setStringList(
        _seenKey(widget.collection.id),
        seenIds.toList(),
      );
    }

    // 1) Affichage immédiat depuis le cache local (aucune attente réseau)
    if (mounted) {
      setState(() {
        _allCards = all;
        _obtainedCards = all.where((c) => obtIds.contains(c.id)).toList();
        _catalogueIds = catIds;
        _seenIds = seenIds;
        _loading = all.isEmpty && catIds.isEmpty;
      });
    }

    // 2) Synchronisation Supabase en arrière-plan (ne bloque pas l'affichage)
    final qty = <String, int>{..._qtyByCard};
    try {
      final remoteEntries = await CollectionService.instance.loadUserCards(
        widget.collection.id,
      );
      final newCards = <SavedCard>[];
      for (final entry in remoteEntries) {
        obtIds.add(entry.cardId);
        qty[entry.cardId] = entry.quantity;
        final alreadyLocal = all.any((c) => c.id == entry.cardId);
        final alreadyQueued = newCards.any((c) => c.id == entry.cardId);
        if (!alreadyLocal && !alreadyQueued) {
          final reconstructed = entry.toSavedCard();
          if (reconstructed != null) newCards.add(reconstructed);
        }
      }
      if (newCards.isNotEmpty) {
        // ✨ Nouveau format léger : télécharge les images depuis Storage
        final hydrated = await CardMediaService.instance.hydrateAll(newCards);
        await CardStorage.addCards(hydrated);
        all.addAll(hydrated);
      }
      await prefs.setStringList(_obtKey(widget.collection.id), obtIds.toList());
    } catch (e) {
      debugPrint('⚠️ Sync cartes Supabase (loadUserCards) : $e');
    }

    try {
      final catalog = await CollectionService.instance.getCollectionCards(
        widget.collection.id,
      );
      catIds.addAll(catalog.map((e) => e.cardId));

      // ✨ NOUVEAU : reconstruit les cartes créées par les AUTRES membres
      // (card_data léger du catalogue + images sur Supabase Storage)
      final missing = <SavedCard>[];
      for (final e in catalog) {
        if (e.cardData == null) continue;
        if (all.any((c) => c.id == e.cardId)) continue;
        if (missing.any((c) => c.id == e.cardId)) continue;
        final rebuilt = e.toSavedCard();
        if (rebuilt != null) missing.add(rebuilt);
      }
      if (missing.isNotEmpty) {
        final hydrated = await CardMediaService.instance.hydrateAll(missing);
        await CardStorage.addCards(hydrated);
        all.addAll(hydrated);
      }

      await prefs.setStringList(_catKey(widget.collection.id), catIds.toList());
    } catch (e) {
      debugPrint('⚠️ Sync catalogue Supabase (getCollectionCards) : $e');
    }

    // 3) Mise à jour finale après la synchro réseau
    if (mounted) {
      setState(() {
        _allCards = all;
        _obtainedCards = all.where((c) => obtIds.contains(c.id)).toList();
        _catalogueIds = catIds;
        _qtyByCard = qty;
        _loading = false;
      });
    }
  }

  // ✨ Badge NEW : marque une carte comme consultée
  Future<void> _markSeen(String cardId) async {
    if (_seenIds.contains(cardId)) return;
    setState(() => _seenIds.add(cardId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _seenKey(widget.collection.id),
      _seenIds.toList(),
    );
  }

  // FIX 1 : plus de fallback _allCards → isolation stricte par collection
  List<SavedCard> get _catalogue {
    if (_catalogueIds.isEmpty) return [];
    return _allCards.where((c) => _catalogueIds.contains(c.id)).toList();
  }

  Future<void> _openPack() async {
    final pool = _catalogue;
    if (pool.isEmpty) {
      _msg('❌ Crée des cartes dans l\'onglet ✏️ d\'abord !', err: true);
      return;
    }
    // ✨ Retour haptique : le pack s'ouvre !
    HapticFeedback.mediumImpact();
    final rng = math.Random();
    final packCards = List.generate(3, (_) => _weightedPick(pool, rng));
    await PackSystem.setLastOpenedTime(widget.collection.id);
    final streak = await StreakService.registerPackOpened();
    if (mounted && streak.increasedToday) {
      _msg(
        '🔥 Série : ${streak.streak} jour${streak.streak > 1 ? 's' : ''} d\'affilée !',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final key = _obtKey(widget.collection.id);
    final existing = prefs.getStringList(key) ?? [];
    await prefs.setStringList(
      key,
      {...existing, ...packCards.map((c) => c.id)}.toList(),
    );
    _startTimer();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PackOpeningScreen(
              cards: packCards,
              collectionId: _col.id,
              packName:
                  (_col.packTitle?.isNotEmpty ?? false)
                      ? _col.packTitle!
                      : _col.name,
              packSubtitle:
                  (_col.packSubtitle?.isNotEmpty ?? false)
                      ? _col.packSubtitle!
                      : 'Pack surprise',
              packImageUrl: _col.packImageUrl,
              packColor: _pal(_col.id).first,
            ),
      ),
    );
    await _loadCards();
    _startTimer();
  }

  void _msg(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: _body(color: Colors.white)),
        backgroundColor: err ? _coral : _teal.withValues(alpha: 0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<SavedCard> _sorted(List<SavedCard> cards) {
    final l = [...cards];
    int cmp(SavedCard a, SavedCard b) {
      switch (_sortBy) {
        case 'rarity':
          return a.rarity.index.compareTo(b.rarity.index);
        case 'name':
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default:
          return 0;
      }
    }

    l.sort((a, b) => _sortAsc ? cmp(a, b) : cmp(b, a));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final p = _pal(widget.collection.id);
    return Scaffold(
      backgroundColor: _bgDeep,
      body: Stack(
        children: [
          // fond avec halo radial haut
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -1.1),
                  radius: 1.3,
                  colors: [Color(0xFF271C40), _bg, _bgDeep],
                  stops: [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          NestedScrollView(
            // FIX : bloque le scroll vertical quand on déplace un élément
            physics:
                _cardMoveMode
                    ? const NeverScrollableScrollPhysics()
                    : const ScrollPhysics(),
            headerSliverBuilder: (_, __) => [_appBar(p)],
            body: Column(
              children: [
                // ── Onglets restylés ──────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: _surfaceLine, width: 1.5),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabCtrl,
                    labelColor: _cream,
                    unselectedLabelColor: _creamFaint,
                    labelStyle: _body(size: 14.5, weight: FontWeight.w800),
                    unselectedLabelStyle: _body(
                      size: 14.5,
                      weight: FontWeight.w700,
                    ),
                    indicatorColor: _gold,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    tabs: [
                      const Tab(text: '🎁 Pack'),
                      const Tab(text: '🃏 Cartes'),
                      Tab(text: _isAdmin ? '🛠️ Admin' : '✏️ Créer'),
                    ],
                  ),
                ),
                Expanded(
                  child:
                      _loading
                          ? const Center(
                            child: CircularProgressIndicator(color: _gold),
                          )
                          : TabBarView(
                            controller: _tabCtrl,
                            // FIX : bloque le scroll gauche/droite en mode déplacement
                            physics:
                                _cardMoveMode
                                    ? const NeverScrollableScrollPhysics()
                                    : const ScrollPhysics(),
                            children: [
                              _packTab(p),
                              _cardsTab(),
                              _isAdmin ? _adminTab(p) : _createTab(p),
                            ],
                          ),
                ),
              ],
            ),
          ),
          // ── Scanlines CRT par-dessus tout ───────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinePainter()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appBar(List<Color> p) => SliverAppBar(
    expandedHeight: 160,
    pinned: true,
    backgroundColor: _bg,
    elevation: 0,
    leading: Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
      child: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _surfaceLine, width: 1.5),
          ),
          child: const Icon(Icons.chevron_left, color: _cream, size: 24),
        ),
      ),
    ),
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsets.only(left: 60, bottom: 16, right: 16),
      title: Text(
        widget.collection.name,
        style: _arcade(
          size: 19,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, offset: Offset(2, 3))],
        ),
      ),
      background: Stack(
        fit: StackFit.expand,
        children: [
          // dégradé série
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [p[0], Color.lerp(p[0], _bg, 0.6)!, _bg],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),
          _rayBurst(p[1], 0.12),
          if (widget.collection.imageUrl != null)
            Opacity(
              opacity: 0.15,
              child: Image.network(
                widget.collection.imageUrl!,
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Row(
              children: [
                _pixelBadge(
                  '⏱ ${widget.collection.cooldownLabel}',
                  color: Colors.white,
                  bg: Colors.black.withValues(alpha: 0.3),
                  borderColor: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
                _pixelBadge(
                  '🃏 ${_catalogue.length}',
                  color: Colors.white,
                  bg: Colors.black.withValues(alpha: 0.3),
                  borderColor: Colors.white.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // ── ONGLET PACK ───────────────────────────────────────────────────────────
  Widget _packTab(List<Color> p) => SingleChildScrollView(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _canOpen ? _openBtn(p) : _timerWidget(),
        if (_col.isOwnedBy(widget.myUserId)) ...[
          const SizedBox(height: 12),
          _customizePackBtn(),
        ],
        if (_isAdmin) ...[const SizedBox(height: 12), _manageMembersBtn()],
        const SizedBox(height: 28),
        _secTitle('Taux de drop'),
        const SizedBox(height: 12),
        ..._dropRows(),
        const SizedBox(height: 28),
        _secTitle('Code d\'invitation'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _surfaceLine,
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            children: [
              Text(
                'CODE',
                style: _pixel(size: 8, color: _creamFaint, letterSpacing: 2),
              ),
              const SizedBox(height: 10),
              ShaderMask(
                shaderCallback:
                    (b) => const LinearGradient(
                      colors: [_teal, Color(0xFF2FA8FF), _coral],
                    ).createShader(b),
                child: Text(
                  widget.collection.code,
                  style: _arcade(
                    size: 32,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _dropRows() =>
      Rarity.values.reversed.map((r) {
        final rc = _rarColors[r]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: rc,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(color: rc.withValues(alpha: 0.6), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Text(_rn(r), style: _body(size: 13.5, color: _creamDim)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _dropRates[r]! / 100.0,
                    backgroundColor: Colors.black.withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation(rc),
                    minHeight: 7,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 36,
                child: Text(
                  _dropLabels[r]!,
                  textAlign: TextAlign.right,
                  style: _pixel(size: 10, color: rc),
                ),
              ),
            ],
          ),
        );
      }).toList();

  Widget _openBtn(List<Color> p) => _ArcadeButton(
    big: true,
    onTap: _openPack,
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.auto_awesome, size: 22),
        SizedBox(width: 10),
        Text('OUVRIR LE PACK'),
      ],
    ),
  );

  Widget _timerWidget() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _surfaceLine, width: 1.5),
    ),
    child: Column(
      children: [
        Text(
          '⏳ Prochain booster gratuit dans',
          style: _body(size: 12, color: _creamDim, weight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          PackSystem.formatDuration(_remaining),
          style: _arcade(
            size: 30,
            color: _teal,
            shadows: [
              Shadow(color: _teal.withValues(alpha: 0.4), blurRadius: 16),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _secTitle(String t) => Text(t, style: _arcade(size: 16));

  // ── ONGLET CARTES ───────────────────────────────────────────────────────
  // ✨ Jauge de complétion du dex — globale + détail par rareté
  Widget _dexHeader() {
    final cat = _catalogue;
    if (cat.isEmpty) return const SizedBox.shrink();
    final obtIds = _obtainedCards.map((c) => c.id).toSet();
    final total = cat.length;
    final owned = cat.where((c) => obtIds.contains(c.id)).length;
    final pct = total == 0 ? 0.0 : owned / total;
    final complete = owned == total;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 2),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: complete ? _gold : _surfaceLine, width: 1.5),
        boxShadow:
            complete
                ? [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                complete ? '🏆' : '📖',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(width: 8),
              Text(
                'DEX',
                style: _pixel(size: 9, color: _creamFaint, letterSpacing: 2),
              ),
              const Spacer(),
              Text(
                '$owned / $total',
                style: _arcade(size: 15, color: complete ? _gold : _cream),
              ),
              const SizedBox(width: 8),
              Text(
                '${(pct * 100).round()}%',
                style: _pixel(size: 10, color: complete ? _gold : _teal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 9,
              backgroundColor: Colors.black.withValues(alpha: 0.35),
              valueColor: AlwaysStoppedAnimation(complete ? _gold : _teal),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children:
                Rarity.values.reversed
                    .where((r) => cat.any((c) => c.rarity == r))
                    .map((r) {
                      final rc = _rarColors[r]!;
                      final tot = cat.where((c) => c.rarity == r).length;
                      final own =
                          cat
                              .where(
                                (c) => c.rarity == r && obtIds.contains(c.id),
                              )
                              .length;
                      final full = own == tot;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Column(
                            children: [
                              Text(
                                '$own/$tot',
                                style: _pixel(
                                  size: 8,
                                  color: full ? rc : _creamDim,
                                ),
                              ),
                              const SizedBox(height: 3),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: tot == 0 ? 0 : own / tot,
                                  minHeight: 4,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.3,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(rc),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _cardsTab() => Column(
    children: [
      _dexHeader(),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'TRIER',
                  style: _pixel(size: 8, color: _creamFaint),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _sortAsc = !_sortAsc),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _cream.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: _surfaceLine, width: 1.5),
                    ),
                    child: Text(
                      _sortAsc ? '⬆️ Croissant' : '⬇️ Décroissant',
                      style: _pixel(size: 9, color: _cream),
                    ),
                  ),
                ),
              ),
              ...[
                ('rarity', '✨ Rareté'),
                ('name', '🔤 Nom'),
                ('date', '📅 Date'),
              ].map((item) {
                final sel = _sortBy == item.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _sortBy = item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? _gold : _cream.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: sel ? Colors.transparent : _surfaceLine,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        item.$2,
                        style: _body(
                          size: 12,
                          color: sel ? const Color(0xFF2A1C00) : _creamDim,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      Expanded(child: _cardGrid()),
    ],
  );

  Widget _cardGrid() {
    final obtIds = _obtainedCards.map((c) => c.id).toSet();
    final cards = _sorted(_catalogue);
    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '🃏',
              style: TextStyle(
                fontSize: 50,
                color: _cream.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune carte',
              textAlign: TextAlign.center,
              style: _arcade(size: 16, color: _creamFaint),
            ),
            const SizedBox(height: 4),
            Text(
              'Crée-en dans l\'onglet ✏️',
              textAlign: TextAlign.center,
              style: _body(size: 13, color: _creamFaint),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.7,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        final revealed = obtIds.contains(c.id);
        return RepaintBoundary(
          child: _CardTile(
            card: c,
            revealed: revealed,
            copies: _qtyByCard[c.id] ?? 1,
            isNew: revealed && !_seenIds.contains(c.id),
            onSeen: () => _markSeen(c.id),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteCard(SavedCard card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: _surfaceLine, width: 1.5),
            ),
            title: Text('Supprimer la carte ?', style: _arcade(size: 18)),
            content: Text(
              '« ${card.name} » sera retirée de la collection pour tous les membres.',
              style: _body(size: 13.5, color: _creamDim),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler', style: _body(color: _creamDim)),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _coral,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Supprimer',
                    style: _body(color: Colors.white, weight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      await CollectionService.instance.removeCardFromCollection(
        widget.collection.id,
        card.id,
      );
      await CardStorage.deleteCard(card.id);
      // ✨ Nettoyage best-effort des images sur Supabase Storage
      await CardMediaService.instance.deleteCardImages(card);
      _msg('🗑️ Carte supprimée.');
      await _loadCards();
    } catch (e) {
      _msg('Erreur : $e', err: true);
    }
  }

  Widget _createTab(List<Color> p) => _CardCreator(
    palette: p,
    collectionId: widget.collection.id,
    onMoveModeChanged: (v) => setState(() => _cardMoveMode = v),
    onSaved: () {
      _msg('✅ Carte ajoutée !');
      _loadCards();
      _tabCtrl.animateTo(1);
    },
  );

  // ════════════════════════════════════════════════════════════════════════
  //   ONGLET ADMIN — réservé aux admins (Créer / Supprimer une carte)
  // ════════════════════════════════════════════════════════════════════════
  Widget _adminTab(List<Color> p) {
    if (_adminMode == 'create') return _adminCreateView(p);
    if (_adminMode == 'delete') return _adminDeleteView();
    return _adminMenu();
  }

  // Menu de choix : Créer ou Supprimer
  Widget _adminMenu() => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      children: [
        const SizedBox(height: 8),
        Text('Espace admin', style: _arcade(size: 20)),
        const SizedBox(height: 6),
        Text(
          'Gère les cartes de cette collection.',
          textAlign: TextAlign.center,
          style: _body(size: 13.5, color: _creamDim),
        ),
        const SizedBox(height: 28),
        _adminMenuCard(
          emoji: '✏️',
          title: 'Créer une carte',
          subtitle: 'Ajoute une nouvelle carte à la collection',
          color: _teal,
          onTap: () => setState(() => _adminMode = 'create'),
        ),
        const SizedBox(height: 16),
        _adminMenuCard(
          emoji: '🗑️',
          title: 'Supprimer une carte',
          subtitle: 'Retire une carte de la collection',
          color: _coral,
          onTap: () => setState(() => _adminMode = 'delete'),
        ),
      ],
    ),
  );

  Widget _adminMenuCard({
    required String emoji,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _arcade(size: 16)),
                const SizedBox(height: 4),
                Text(subtitle, style: _body(size: 12.5, color: _creamDim)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color),
        ],
      ),
    ),
  );

  // Barre « Retour » affichée en haut des sous-écrans Créer / Supprimer
  Widget _adminBackBar(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _adminMode = 'menu'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _cream.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _surfaceLine, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_back_rounded, size: 16, color: _cream),
                const SizedBox(width: 6),
                Text('Retour', style: _body(size: 12.5, color: _cream)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: _arcade(size: 15)),
      ],
    ),
  );

  // Sous-écran « Créer » : exactement le créateur de carte habituel
  Widget _adminCreateView(List<Color> p) => Column(
    children: [
      _adminBackBar('Créer une carte'),
      Expanded(
        child: _CardCreator(
          palette: p,
          collectionId: widget.collection.id,
          onMoveModeChanged: (v) => setState(() => _cardMoveMode = v),
          onSaved: () {
            _msg('✅ Carte ajoutée !');
            _loadCards();
            setState(() => _adminMode = 'menu');
            _tabCtrl.animateTo(1);
          },
        ),
      ),
    ],
  );

  // Sous-écran « Supprimer » : toutes les cartes de la collection,
  // avec un bouton de suppression sur chacune.
  Widget _adminDeleteView() {
    final cards = _sorted(_catalogue);
    return Column(
      children: [
        _adminBackBar('Supprimer une carte'),
        Expanded(
          child:
              cards.isEmpty
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '🃏',
                          style: TextStyle(
                            fontSize: 50,
                            color: _cream.withValues(alpha: 0.2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Aucune carte à supprimer',
                          style: _arcade(size: 15, color: _creamFaint),
                        ),
                      ],
                    ),
                  )
                  : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.7,
                        ),
                    itemCount: cards.length,
                    itemBuilder:
                        (_, i) => RepaintBoundary(
                          child: _CardTile(
                            card: cards[i],
                            revealed: true,
                            isAdmin: true,
                            onDelete: () => _confirmDeleteCard(cards[i]),
                          ),
                        ),
                  ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//   TUILE CARTE — cadre arcade selon rareté
// ════════════════════════════════════════════════════════════════════════════

class _CardTile extends StatelessWidget {
  final SavedCard card;
  final bool revealed;
  final bool isAdmin;
  final VoidCallback? onDelete;
  // ✨ Polish : compteur de doublons + badge NEW
  final int copies;
  final bool isNew;
  final VoidCallback? onSeen;
  const _CardTile({
    required this.card,
    required this.revealed,
    this.isAdmin = false,
    this.onDelete,
    this.copies = 1,
    this.isNew = false,
    this.onSeen,
  });

  Color get _rc => _rarColors[card.rarity]!;

  String get _rl {
    switch (card.rarity) {
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
    if (!revealed) {
      return Stack(
        children: [
          _back(),
          if (isAdmin && onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return GestureDetector(
      onTap: () {
        onSeen?.call();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CardInspectorScreen(
                  frontCard: SavedCardFrontWidget(
                    card: card,
                    width: 300,
                    height: 420,
                  ),
                  backCard: SavedCardBackWidget(
                    card: card,
                    width: 300,
                    height: 420,
                  ),
                ),
          ),
        );
      },
      child: Stack(
        children: [
          _front(),
          // ✨ Badge NEW — carte pas encore consultée
          if (isNew)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.55),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Text(
                  'NEW',
                  style: _pixel(size: 6.5, color: const Color(0xFF2A1C00)),
                ),
              ),
            ),
          // ✨ Compteur de doublons
          if (copies > 1 && !isAdmin)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _cream.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
                child: Text(
                  '×$copies',
                  style: _pixel(size: 7.5, color: _cream),
                ),
              ),
            ),
          // Badge 3D
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.view_in_ar,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 9,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '3D',
                      style: _pixel(
                        size: 6,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bouton suppression — admin uniquement
          if (isAdmin && onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _coral,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _front() {
    final rc = _rc;
    final isLeg = card.rarity == Rarity.legendary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient:
            isLeg
                ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFE89A),
                    Color(0xFFFFC83D),
                    Color(0xFFC9920E),
                    Color(0xFFFFF1B8),
                  ],
                )
                : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(rc, Colors.white, 0.35)!,
                    rc,
                    Color.lerp(rc, Colors.black, 0.30)!,
                  ],
                ),
        boxShadow: [
          BoxShadow(color: rc.withValues(alpha: 0.4), blurRadius: 8),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_surface, Color(0xFF171125)],
            ),
          ),
          child: Stack(
            children: [
              if (card.imageBytes != null)
                Positioned.fill(
                  child: Image.memory(
                    card.imageBytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.92),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.name,
                        style: _arcade(size: 9, color: _cream),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      _pixelBadge(_rl, color: rc, size: 6),
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

  Widget _back() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(11),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1C1530), Color(0xFF140F22)],
      ),
      border: Border.all(color: _rc.withValues(alpha: 0.45), width: 2),
    ),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '❔',
            style: TextStyle(
              fontSize: 24,
              color: _cream.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 6),
          _pixelBadge(_rl, color: _rc.withValues(alpha: 0.7), size: 6),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//   COUCHE IMAGE — INCHANGÉE
// ════════════════════════════════════════════════════════════════════════════

class _ImgLayer {
  Uint8List bytes;
  double x = 0, y = 0, scale = 1.0;
  double opacity = 1.0;
  _ImgLayer({required this.bytes});
}

// ════════════════════════════════════════════════════════════════════════════
//   CRÉATEUR DE CARTE
//   FIX 2 : Listener sur la carte + mode déplacement (LOGIQUE INCHANGÉE)
//   • Reskin : chrome, boutons, titres, swatches → style arcade
//   • Le canvas (positions/drag) reste mécaniquement identique
// ════════════════════════════════════════════════════════════════════════════

class _CardCreator extends StatefulWidget {
  final List<Color> palette;
  final String collectionId;
  final VoidCallback onSaved;
  final void Function(bool) onMoveModeChanged;
  const _CardCreator({
    required this.palette,
    required this.collectionId,
    required this.onSaved,
    required this.onMoveModeChanged,
  });
  @override
  State<_CardCreator> createState() => _CardCreatorState();
}

class _CardCreatorState extends State<_CardCreator>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController(text: 'Ma Carte');
  Rarity _rarity = Rarity.common;
  bool _showBack = false;
  bool _saving = false;

  // FIX 2 : mode déplacement
  bool _moveMode = false;

  final List<_ImgLayer> _images = [];
  final List<TextZone> _textZones = [];

  // -1 = aucun, >=0 = image, -2 = nom, -3 = rareté
  int _selectedLayer = -1;

  double _nameX = 8, _nameY = 200;
  double _rarityX = 8, _rarityY = 222;

  int _selectedGrad = -1;
  int _backColor = 0xFF211A33;
  Uint8List? _backImageBytes;

  int _borderColorIndex = -1;
  static const _borderColors = [
    Colors.white,
    _gold,
    _coral,
    _teal,
    Color(0xFF2FA8FF),
    Color(0xFFB45CFF),
    Color(0xFF000000),
    Color(0xFF9AA0B0),
  ];

  late AnimationController _legendaryCtrl;
  static const double _cW = 194, _cH = 284;

  final _gradients = [
    [const Color(0xFF7C3AED), const Color(0xFF2563EB)],
    [const Color(0xFFDB2777), const Color(0xFF7C3AED)],
    [const Color(0xFF059669), const Color(0xFF2563EB)],
    [const Color(0xFFD97706), const Color(0xFFDB2777)],
    [const Color(0xFF0891B2), const Color(0xFF2563EB)],
    [const Color(0xFF14101F), const Color(0xFF2B2240)],
  ];

  final _backColors = [
    0xFF211A33,
    0xFF2B2240,
    0xFF0F3460,
    0xFF533483,
    0xFF14101F,
    0xFF1B2631,
    0xFF4A235A,
    0xFF1A5276,
  ];

  static const _fontFamilies = [
    (null, 'Défaut'),
    ('serif', 'Serif'),
    ('monospace', 'Mono'),
    ('cursive', 'Cursif'),
  ];

  @override
  void initState() {
    super.initState();
    _legendaryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _legendaryCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Color _rc(Rarity r) => _rarColors[r]!;

  String _rn(Rarity r) {
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

  Color get _currentBorderColor =>
      _borderColorIndex >= 0 ? _borderColors[_borderColorIndex] : _rc(_rarity);

  // ── FIX 2 : déplace l'élément sélectionné ─────────────────────────────────
  void _moveSelected(Offset delta) {
    if (_selectedLayer == -2) {
      setState(() {
        _nameX = (_nameX + delta.dx).clamp(0.0, _cW - 60);
        _nameY = (_nameY + delta.dy).clamp(0.0, _cH - 20);
      });
    } else if (_selectedLayer == -3) {
      setState(() {
        _rarityX = (_rarityX + delta.dx).clamp(0.0, _cW - 60);
        _rarityY = (_rarityY + delta.dy).clamp(0.0, _cH - 16);
      });
    } else if (_selectedLayer >= 0 && _selectedLayer < _images.length) {
      final l = _images[_selectedLayer];
      setState(() {
        l.x = (l.x + delta.dx).clamp(-_cW, _cW * 2);
        l.y = (l.y + delta.dy).clamp(-_cH, _cH * 2);
      });
    } else if (_selectedLayer >= 100) {
      // textes : index 100+ = textZones[index-100]
      final i = _selectedLayer - 100;
      if (i < _textZones.length) {
        final z = _textZones[i];
        setState(() {
          z.x = (z.x + delta.dx).clamp(0.0, _cW - 20);
          z.y = (z.y + delta.dy).clamp(0.0, _cH - 20);
        });
      }
    }
  }

  // ── Ajout image / texte ────────────────────────────────────────────────────
  Future<void> _addImage({bool isBack = false}) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      if (isBack) {
        _backImageBytes = bytes;
      } else {
        _images.add(_ImgLayer(bytes: bytes));
        _selectedLayer = _images.length - 1;
        _moveMode = true;
        widget.onMoveModeChanged(true);
      }
    });
  }

  void _addText() {
    final zone = TextZone(
      text: 'Texte',
      x: 40,
      y: 80 + _textZones.length * 30.0,
      fontSize: 13,
      color: 0xFFFFFFFF,
    );
    setState(() {
      _textZones.add(zone);
      _selectedLayer = 100 + _textZones.length - 1;
      _moveMode = true;
      widget.onMoveModeChanged(true);
    });
    _editText(_textZones.length - 1);
  }

  void _editText(int idx) {
    final zone = _textZones[idx];
    final ctrl = TextEditingController(text: zone.text);
    Color selColor = Color(zone.color);
    double fontSize = zone.fontSize;
    String? fontFamily = zone.fontFamily;

    showDialog(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setD) => AlertDialog(
                  backgroundColor: _surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: _surfaceLine, width: 1.5),
                  ),
                  title: Text('Modifier le texte', style: _arcade(size: 17)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: ctrl,
                          style: _body(color: _cream),
                          decoration: InputDecoration(
                            labelText: 'Texte',
                            labelStyle: _body(color: _creamFaint),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: _surfaceLine),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Taille',
                          style: _body(size: 13, color: _creamDim),
                        ),
                        Slider(
                          value: fontSize,
                          min: 8,
                          max: 36,
                          activeColor: _gold,
                          onChanged: (v) {
                            setD(() => fontSize = v);
                            setState(() => zone.fontSize = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Police',
                          style: _body(size: 13, color: _creamDim),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children:
                              _fontFamilies.map((f) {
                                final sel = fontFamily == f.$1;
                                return GestureDetector(
                                  onTap: () {
                                    setD(() => fontFamily = f.$1);
                                    setState(() => zone.fontFamily = f.$1);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? _gold.withValues(alpha: 0.25)
                                              : _cream.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: sel ? _gold : _surfaceLine,
                                      ),
                                    ),
                                    child: Text(
                                      f.$2,
                                      style: TextStyle(
                                        color: _cream,
                                        fontSize: 11,
                                        fontFamily: f.$1,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Couleur',
                          style: _body(size: 13, color: _creamDim),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Colors.white,
                                    Colors.black,
                                    _gold,
                                    _coral,
                                    _teal,
                                    const Color(0xFF2FA8FF),
                                    const Color(0xFFB45CFF),
                                    const Color(0xFF3FD17A),
                                    Colors.pink,
                                    Colors.cyan,
                                    Colors.teal,
                                    Colors.amber,
                                  ]
                                  .map(
                                    (c) => GestureDetector(
                                      onTap: () {
                                        setD(() => selColor = c);
                                        setState(
                                          () => zone.color = c.toARGB32(),
                                        );
                                      },
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border:
                                              selColor == c
                                                  ? Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  )
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => _textZones.removeAt(idx));
                        Navigator.pop(ctx);
                      },
                      child: Text('Supprimer', style: _body(color: _coral)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => zone.text = ctrl.text);
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        'OK',
                        style: _body(color: _gold, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ── Label de l'élément sélectionné ────────────────────────────────────────
  String get _selectedLabel {
    if (_selectedLayer == -2) return 'Nom';
    if (_selectedLayer == -3) return 'Rareté';
    if (_selectedLayer >= 0 && _selectedLayer < _images.length) {
      return 'Photo ${_selectedLayer + 1}';
    }
    if (_selectedLayer >= 100) return 'Texte ${_selectedLayer - 99}';
    return '';
  }

  // ── Panneau chips ──────────────────────────────────────────────────────────
  Widget _buildLayerPanel() {
    final hasLayers = _images.isNotEmpty || _textZones.isNotEmpty;
    if (!hasLayers) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          'Ajoute des photos ou du texte pour voir les éléments ici',
          style: _body(size: 11, color: _creamFaint),
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _chip2(
            icon: Icons.badge_rounded,
            label: 'Nom',
            sel: _selectedLayer == -2,
            onTap:
                () => setState(() {
                  _selectedLayer = _selectedLayer == -2 ? -1 : -2;
                  if (_selectedLayer != -1) _moveMode = true;
                }),
          ),
          _chip2(
            icon: Icons.label_rounded,
            label: 'Rareté',
            sel: _selectedLayer == -3,
            onTap:
                () => setState(() {
                  _selectedLayer = _selectedLayer == -3 ? -1 : -3;
                  if (_selectedLayer != -1) _moveMode = true;
                }),
          ),
          for (var i = 0; i < _images.length; i++)
            _chip2(
              imageBytes: _images[i].bytes,
              label: 'Photo ${i + 1}',
              sel: _selectedLayer == i,
              onTap:
                  () => setState(() {
                    _selectedLayer = _selectedLayer == i ? -1 : i;
                    if (_selectedLayer != -1) _moveMode = true;
                  }),
              onDelete:
                  () => setState(() {
                    _images.removeAt(i);
                    _selectedLayer = -1;
                  }),
            ),
          for (var i = 0; i < _textZones.length; i++)
            _chip2(
              icon: Icons.text_fields_rounded,
              label: 'Texte ${i + 1}',
              sel: _selectedLayer == 100 + i,
              onTap: () {
                _editText(i);
                setState(() {
                  _selectedLayer = 100 + i;
                  _moveMode = true;
                });
              },
              onDelete: () => setState(() => _textZones.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _chip2({
    IconData? icon,
    Uint8List? imageBytes,
    required String label,
    required bool sel,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.only(
          left: 8,
          right: onDelete != null ? 6 : 10,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color:
              sel
                  ? _gold.withValues(alpha: 0.22)
                  : _cream.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? _gold : _surfaceLine,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  imageBytes,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  cacheWidth: 48,
                ),
              )
            else
              Icon(icon ?? Icons.layers, color: _cream, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: _body(size: 11, color: _cream, weight: FontWeight.w600),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(
                  Icons.close_rounded,
                  color: _cream.withValues(alpha: 0.45),
                  size: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Canvas carte — avec Listener pour le mode déplacement (INCHANGÉ) ──────
  Widget _buildFront() {
    final rc = _currentBorderColor;

    Widget inner = SizedBox(
      width: _cW,
      height: _cH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration:
              _selectedGrad >= 0
                  ? BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _gradients[_selectedGrad],
                    ),
                  )
                  : const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(13)),
                    color: _surface,
                  ),
          child: Stack(
            children: [
              // Images
              ..._images.asMap().entries.map((e) {
                final i = e.key;
                final layer = e.value;
                return Positioned(
                  left: layer.x,
                  top: layer.y,
                  child: GestureDetector(
                    onTap:
                        () => setState(() {
                          _selectedLayer = _selectedLayer == i ? -1 : i;
                          _moveMode = _selectedLayer != -1;
                          widget.onMoveModeChanged(_moveMode);
                        }),
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: layer.opacity,
                          child: Transform.scale(
                            scale: layer.scale,
                            alignment: Alignment.topLeft,
                            child: Image.memory(
                              layer.bytes,
                              width: _cW,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                        if (_selectedLayer == i)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _gold, width: 2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // Textes
              ..._textZones.asMap().entries.map((e) {
                final i = e.key;
                final zone = e.value;
                final sel = _selectedLayer == 100 + i;
                return Positioned(
                  left: zone.x,
                  top: zone.y,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLayer = sel ? -1 : 100 + i;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      });
                      if (!sel) _editText(i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            sel ? Border.all(color: _gold, width: 1.5) : null,
                      ),
                      child: Text(
                        zone.text,
                        style: TextStyle(
                          color: Color(zone.color),
                          fontSize: zone.fontSize.clamp(8, 36),
                          fontFamily: zone.fontFamily,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Dégradé bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Nom
              Positioned(
                left: _nameX,
                top: _nameY,
                child: GestureDetector(
                  onTap:
                      () => setState(() {
                        _selectedLayer = _selectedLayer == -2 ? -1 : -2;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border:
                          _selectedLayer == -2
                              ? Border.all(color: _gold, width: 1.5)
                              : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _nameCtrl.text,
                      style: _arcade(
                        size: 14,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Rareté
              Positioned(
                left: _rarityX,
                top: _rarityY,
                child: GestureDetector(
                  onTap:
                      () => setState(() {
                        _selectedLayer = _selectedLayer == -3 ? -1 : -3;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _rc(_rarity),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          _selectedLayer == -3
                              ? Border.all(color: Colors.white, width: 1.5)
                              : null,
                    ),
                    child: Text(
                      _rn(_rarity),
                      style: _pixel(size: 7, color: _bg),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_rarity == Rarity.legendary) {
      return AnimatedBuilder(
        animation: _legendaryCtrl,
        builder:
            (_, __) => SizedBox(
              width: _cW + 6,
              height: _cH + 6,
              child: Stack(
                children: [
                  Container(
                    width: _cW + 6,
                    height: _cH + 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: SweepGradient(
                        startAngle: _legendaryCtrl.value * 2 * math.pi,
                        colors: const [
                          Color(0xFFFFD700),
                          Color(0xFFFFF9C4),
                          Color(0xFFFF8F00),
                          Color(0xFFFFE082),
                          Color(0xFFFFF176),
                          Color(0xFFFFD700),
                        ],
                      ),
                    ),
                  ),
                  Center(child: inner),
                ],
              ),
            ),
      );
    }

    return SizedBox(
      width: _cW + 6,
      height: _cH + 6,
      child: Stack(
        children: [
          Container(
            width: _cW + 6,
            height: _cH + 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rc, width: 3),
              boxShadow: [
                BoxShadow(color: rc.withValues(alpha: 0.45), blurRadius: 14),
              ],
            ),
          ),
          Center(child: inner),
        ],
      ),
    );
  }

  Widget _buildBack() => Container(
    width: _cW,
    height: _cH,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Color(_backColor),
      border: Border.all(color: _surfaceLine, width: 2),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          if (_backImageBytes != null)
            Positioned.fill(
              child: Image.memory(
                _backImageBytes!,
                fit: BoxFit.cover,
                cacheWidth: 400,
              ),
            ),
          if (_backImageBytes == null)
            Center(
              child: Text(
                '?',
                style: _arcade(size: 90, color: _gold.withValues(alpha: 0.25)),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Donne un nom à ta carte !',
            style: _body(color: Colors.white),
          ),
          backgroundColor: _gold,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final primaryBytes = _images.isNotEmpty ? _images.first.bytes : null;
      final extra =
          _images.length > 1
              ? _images
                  .sublist(1)
                  .map(
                    (l) => ExtraImage(
                      bytes: l.bytes,
                      x: l.x,
                      y: l.y,
                      scale: l.scale,
                    ),
                  )
                  .toList()
              : <ExtraImage>[];

      final card = SavedCard(
        id:
            '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}',
        name: _nameCtrl.text.trim(),
        rarity: _rarity,
        effect: CardEffect.none,
        imageBytes: primaryBytes,
        imageX: _images.isNotEmpty ? _images.first.x : 0,
        imageY: _images.isNotEmpty ? _images.first.y : 0,
        imageScale: _images.isNotEmpty ? _images.first.scale : 1.0,
        extraImages: extra,
        backImageBytes: _backImageBytes,
        backColor: _backColor,
        nameX: _nameX,
        nameY: _nameY,
        rarityX: _rarityX,
        rarityY: _rarityY,
        textZones: List.from(_textZones),
      );

      // ✨ MIGRATION STORAGE : upload des images vers Supabase Storage.
      // En cas d'échec (hors-ligne…), la carte garde son base64 : rien ne casse.
      final uploaded = await CardMediaService.instance.uploadCardImages(card);

      await CardStorage.addCard(uploaded);

      bool supabaseOk = false;
      try {
        await CollectionService.instance.addCardToCollection(
          widget.collectionId,
          uploaded.id,
          uploaded.name,
          _rn(_rarity),
          uploaded, // card_data léger → carte partagée avec tous les membres
        );
        supabaseOk = true;
      } catch (e) {
        debugPrint('Supabase link: $e');
      }

      if (!supabaseOk) {
        final prefs = await SharedPreferences.getInstance();
        final key = _catKey(widget.collectionId);
        final existing = prefs.getStringList(key) ?? [];
        existing.add(card.id);
        await prefs.setStringList(key, existing);
      }

      setState(() {
        _nameCtrl.text = 'Ma Carte';
        _images.clear();
        _textZones.clear();
        _backImageBytes = null;
        _nameX = 8;
        _nameY = 200;
        _rarityX = 8;
        _rarityY = 222;
        _rarity = Rarity.common;
        _selectedGrad = -1;
        _showBack = false;
        _selectedLayer = -1;
        _borderColorIndex = -1;
        _moveMode = false;
        widget.onMoveModeChanged(false);
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e', style: _body(color: Colors.white)),
            backgroundColor: _coral,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Ligne 1 : toggle recto/verso + bouton mode déplacement ──────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              _toggleBtn(
                'Recto',
                !_showBack,
                () => setState(() => _showBack = false),
              ),
              const SizedBox(width: 8),
              _toggleBtn(
                'Verso',
                _showBack,
                () => setState(() => _showBack = true),
              ),
              const Spacer(),
              // FIX 2 : bouton mode déplacement
              GestureDetector(
                onTap:
                    () => setState(() {
                      _moveMode = !_moveMode;
                      if (!_moveMode) _selectedLayer = -1;
                      widget.onMoveModeChanged(_moveMode);
                    }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient:
                        _moveMode
                            ? const LinearGradient(colors: [_gold, _goldDeep])
                            : null,
                    color: _moveMode ? null : _cream.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _moveMode ? Colors.transparent : _surfaceLine,
                    ),
                    boxShadow:
                        _moveMode
                            ? [
                              BoxShadow(
                                color: _gold.withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ]
                            : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _moveMode
                            ? Icons.open_with_rounded
                            : Icons.touch_app_outlined,
                        color: _moveMode ? const Color(0xFF2A1C00) : _cream,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _moveMode ? 'Déplacer ON' : 'Déplacer',
                        style: _body(
                          size: 12,
                          color: _moveMode ? const Color(0xFF2A1C00) : _cream,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Bandeau info mode déplacement ────────────────────────────────────
        if (_moveMode && !_showBack)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: _teal, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedLayer == -1
                        ? '👆 Tape un élément sur la carte ou un chip ci-dessous pour le sélectionner'
                        : '✋ Glisse sur la carte pour déplacer · $_selectedLabel sélectionné',
                    style: _body(size: 11, color: _teal),
                  ),
                ),
              ],
            ),
          ),

        // ── Canvas carte — FIX 2 : Listener bypass l'arène de gestes ────────
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove:
              _moveMode && _selectedLayer != -1
                  ? (e) => _moveSelected(e.delta)
                  : null,
          child: Center(child: _showBack ? _buildBack() : _buildFront()),
        ),

        // FIX : bouton "Terminer" collé sous la carte, toujours visible
        if (_moveMode && !_showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _ArcadeButton(
              onTap: () {
                setState(() {
                  _moveMode = false;
                  _selectedLayer = -1;
                });
                widget.onMoveModeChanged(false);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('TERMINER LE DÉPLACEMENT'),
                ],
              ),
            ),
          ),

        // Bouton 3D
        TextButton.icon(
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CardInspectorScreen(
                        frontCard: _buildFront(),
                        backCard: _buildBack(),
                      ),
                ),
              ),
          icon: Icon(Icons.view_in_ar, color: _creamFaint, size: 15),
          label: Text(
            'Inspecter en 3D',
            style: _body(size: 11, color: _creamFaint),
          ),
        ),

        // Chips couches
        if (!_showBack) _buildLayerPanel(),

        Divider(height: 1, color: _surfaceLine),

        // ── Paramètres scrollables ───────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            // FIX 2 : désactive le scroll quand le mode déplacement est actif
            physics:
                _moveMode
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_showBack) ...[
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: _body(color: _cream),
                    decoration: _deco('Nom de la carte', Icons.badge_rounded),
                  ),
                  const SizedBox(height: 18),
                  _secTitle('Rareté'),
                  const SizedBox(height: 8),
                  ...Rarity.values.map((r) {
                    final rc = _rc(r);
                    final sel = _rarity == r;
                    return GestureDetector(
                      onTap:
                          () => setState(() {
                            _rarity = r;
                            _borderColorIndex = -1;
                          }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color:
                              sel
                                  ? rc.withValues(alpha: 0.15)
                                  : _cream.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? rc : _surfaceLine,
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: rc,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: rc.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _rn(r),
                              style: _body(
                                size: 13,
                                color: sel ? _cream : _creamDim,
                                weight: sel ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 80,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _dropRates[r]! / 100.0,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.3,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(rc),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 32,
                              child: Text(
                                _dropLabels[r]!,
                                textAlign: TextAlign.right,
                                style: _pixel(size: 9, color: rc),
                              ),
                            ),
                            if (sel) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle, color: rc, size: 16),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),
                  _GhostButton(
                    onTap: () => _addImage(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _images.isEmpty
                              ? 'Ajouter une photo'
                              : 'Ajouter une couche',
                        ),
                      ],
                    ),
                  ),
                  if (_selectedLayer >= 0 &&
                      _selectedLayer < _images.length) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.opacity, color: _creamFaint, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Opacité',
                          style: _body(size: 12, color: _creamFaint),
                        ),
                        Expanded(
                          child: Slider(
                            value: _images[_selectedLayer].opacity,
                            min: 0.1,
                            max: 1.0,
                            activeColor: _gold,
                            onChanged:
                                (v) => setState(
                                  () => _images[_selectedLayer].opacity = v,
                                ),
                          ),
                        ),
                        Text(
                          '${(_images[_selectedLayer].opacity * 100).round()}%',
                          style: _body(size: 11, color: _creamFaint),
                        ),
                      ],
                    ),
                  ],
                  if (_selectedLayer >= 0 &&
                      _selectedLayer < _images.length) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.zoom_in, color: _creamFaint, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Taille',
                          style: _body(size: 12, color: _creamFaint),
                        ),
                        Expanded(
                          child: Slider(
                            value: _images[_selectedLayer].scale.clamp(
                              0.1,
                              6.0,
                            ),
                            min: 0.1,
                            max: 6.0,
                            activeColor: _gold,
                            onChanged:
                                (v) => setState(
                                  () => _images[_selectedLayer].scale = v,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  _GhostButton(
                    onTap: _addText,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.text_fields_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Ajouter du texte'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _secTitle('Fond'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _selectedGrad = -1),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedGrad == -1
                                      ? Colors.white
                                      : _surfaceLine,
                              width: _selectedGrad == -1 ? 3 : 1,
                            ),
                          ),
                          child:
                              _selectedGrad == -1
                                  ? Icon(
                                    Icons.close,
                                    color: _creamFaint,
                                    size: 14,
                                  )
                                  : null,
                        ),
                      ),
                      ...List.generate(
                        _gradients.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _selectedGrad = i),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _gradients[i],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _selectedGrad == i
                                        ? Colors.white
                                        : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _secTitle('Couleur de bordure'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _borderColorIndex = -1),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _rc(_rarity),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _borderColorIndex == -1
                                      ? Colors.white
                                      : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child:
                              _borderColorIndex == -1
                                  ? const Icon(
                                    Icons.auto_awesome,
                                    color: Colors.white,
                                    size: 14,
                                  )
                                  : null,
                        ),
                      ),
                      ...List.generate(
                        _borderColors.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _borderColorIndex = i),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _borderColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _borderColorIndex == i
                                        ? Colors.white
                                        : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  _secTitle('Couleur de fond'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children:
                        _backColors
                            .map(
                              (c) => GestureDetector(
                                onTap: () => setState(() => _backColor = c),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          _backColor == c
                                              ? Colors.white
                                              : _surfaceLine,
                                      width: _backColor == c ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                  _GhostButton(
                    onTap: () => _addImage(isBack: true),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_library_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _backImageBytes != null
                              ? '✅ Image verso — changer'
                              : 'Image verso (optionnel)',
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _ArcadeButton(
                  big: true,
                  onTap: _saving ? null : _save,
                  child:
                      _saving
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Color(0xFF2A1C00),
                              strokeWidth: 2,
                            ),
                          )
                          : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle, size: 20),
                              SizedBox(width: 8),
                              Text('AJOUTER À LA COLLECTION'),
                            ],
                          ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleBtn(
    String label,
    bool active,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        gradient:
            active ? const LinearGradient(colors: [_gold, _goldDeep]) : null,
        color: active ? null : _cream.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Colors.transparent : _surfaceLine),
      ),
      child: Text(
        label,
        style: _body(
          color: active ? const Color(0xFF2A1C00) : _creamDim,
          weight: FontWeight.w800,
        ),
      ),
    ),
  );

  Widget _secTitle(String t) => Text(t, style: _arcade(size: 15));

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: _body(color: _creamFaint),
    prefixIcon: Icon(icon, color: _creamFaint, size: 20),
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
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  Helpers globaux — couleurs/labels de rareté (palette arcade)
// ════════════════════════════════════════════════════════════════════════════
String _rn(Rarity r) {
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
