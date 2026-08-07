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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'daily_reward_card.dart';
import 'card_creator_screen.dart';
import 'error_reporter.dart';
import 'pack_countdown.dart';
import 'dev_tools.dart';

// ✂️ Fichier decoupe : voir l'en-tete de chaque part.
part 'collection_detail_card_tile.dart';

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

// ✨ FUSION GOLD — exemplaires requis pour transformer une carte en GOLD
//
// Barème rééquilibré (01/08). L'ancien (30/20/15/6/3) demandait 41 à 45 jours
// de jeu régulier pour la première fusion d'un commun, d'un peu commun ou d'un
// rare — et rendait paradoxalement le légendaire DEUX FOIS plus rapide que le
// commun. Simulation du tirage réel (3 cartes/pack, rareté pondérée puis
// uniforme) sur une collection de référence de 30 cartes (10/8/6/4/2) :
//
//   rareté        seuil   joueur régulier   joueur assidu
//   commun          12         15 j              7 j
//   peu commun       9         15 j              7 j
//   rare             6         14 j              6 j
//   épique           4         14 j              6 j
//   légendaire       3         19 j              8 j
//
// Les quatre premières raretés convergent volontairement vers ~2 semaines ;
// le légendaire reste le plus long, c'est la pièce de prestige. Dorer une
// collection entière demande toujours plusieurs mois, carte par carte.
const _goldCost = {
  Rarity.common: 12,
  Rarity.uncommon: 9,
  Rarity.rare: 6,
  Rarity.epic: 4,
  Rarity.legendary: 3,
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
  // ✨ Le décompte vit désormais dans son propre widget (pack_countdown.dart).
  // Plus aucun setState par seconde sur l'écran entier.
  final _countdownKey = GlobalKey<PackCountdownState>();

  /// Vrai pendant l'enregistrement du pack (avant l'animation).
  bool _openingPack = false;
  List<SavedCard> _allCards = [];
  List<SavedCard> _obtainedCards = [];
  Set<String> _catalogueIds = {};
  bool _loading = true;
  // ✨ Polish : doublons (quantité par carte) + badge NEW (cartes non consultées)
  Map<String, int> _qtyByCard = {};
  Set<String> _seenIds = {};
  Set<String> _goldIds = {};
  String _sortBy = 'rarity';
  bool _sortAsc = true;
  // ✨ Filtre « vitrine GOLD » : n'affiche que les cartes dorées
  bool _goldOnly = false;
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
    super.dispose();
  }

  Future<void> _syncAndLoad() async {
    await PackSystem.syncFromSupabase(widget.collection.id);
    _countdownKey.currentState?.refresh();
    await _loadCards();
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
    final gold = <String>{..._goldIds};
    try {
      // ✅ PERF : d'abord les métadonnées SEULES (quelques centaines
      // d'octets), puis le card_data des seules cartes absentes du
      // téléphone. Avant, le card_data de toutes les cartes possédées
      // était retéléchargé à chaque appel de _loadCards — c'est-à-dire à
      // chaque ouverture de pack, création de carte, fusion, etc.
      final remoteEntries = await CollectionService.instance.loadUserCardMetas(
        widget.collection.id,
      );
      final missingUserIds = [
        for (final e in remoteEntries)
          if (!all.any((c) => c.id == e.cardId)) e.cardId,
      ];
      final withData =
          missingUserIds.isEmpty
              ? const <UserCardEntry>[]
              : await CollectionService.instance.loadUserCardsData(
                widget.collection.id,
                missingUserIds,
              );
      final dataById = {for (final e in withData) e.cardId: e};
      final newCards = <SavedCard>[];
      // ✨ FIX : le serveur fait foi. Les cartes possédées = celles réellement
      // obtenues en pack — fini les cartes « possédées » parce que créées
      // en tant qu'admin ou héritées d'anciennes versions.
      obtIds.clear();
      qty.clear();
      gold.clear();
      for (final entry in remoteEntries) {
        obtIds.add(entry.cardId);
        qty[entry.cardId] = entry.quantity;
        if (entry.isGold) gold.add(entry.cardId);
        final alreadyLocal = all.any((c) => c.id == entry.cardId);
        final alreadyQueued = newCards.any((c) => c.id == entry.cardId);
        if (!alreadyLocal && !alreadyQueued) {
          final reconstructed = dataById[entry.cardId]?.toSavedCard();
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
      // ✅ PERF : on ne demande que les IDENTIFIANTS du catalogue.
      // Le card_data (JSON des calques, parfois une image en base64) n'est
      // réclamé qu'ensuite, pour les seules cartes manquantes.
      // ⚠️ getCollectionCardIds LÈVE si la lecture échoue : le `catch` en bas
      // saute alors toute la purge. Un échec réseau ne doit JAMAIS être
      // interprété comme « le catalogue est vide ».
      final serverIds =
          (await CollectionService.instance.getCollectionCardIds(
            widget.collection.id,
          )).toSet();

      // ⚠️ GARDE-FOU : on ne purge jamais sur un catalogue vide.
      // Une réponse vide alors qu'on a des cartes en local est presque
      // toujours une anomalie (droits RLS, mauvaise collection, réponse
      // tronquée) — jamais une vraie suppression de TOUTES les cartes.
      // Sans ce garde-fou, ce bloc a déjà effacé l'intégralité des cartes
      // du téléphone. Le coût d'un faux négatif (une carte supprimée qui
      // reste visible jusqu'au prochain chargement) est sans commune
      // mesure avec celui d'une perte totale.
      if (serverIds.isEmpty && catIds.isNotEmpty) {
        reportError(
          'Catalogue vide alors que ${catIds.length} cartes sont en local — '
          'purge annulée par sécurité',
          'Réponse serveur vide inattendue',
        );
      } else {
        final removedIds = catIds.difference(serverIds);
        for (final id in removedIds) {
          await CardStorage.deleteCard(id);
          all.removeWhere((c) => c.id == id);
          obtIds.remove(id);
        }
        // Uniquement ici : écraser catIds avec une réponse vide effacerait
        // aussi le catalogue local, et ferait disparaître les cartes de
        // l'affichage même sans suppression de fichiers.
        catIds
          ..clear()
          ..addAll(serverIds);
      }
      await prefs.setStringList(_obtKey(widget.collection.id), obtIds.toList());

      // ✨ NOUVEAU : reconstruit les cartes créées par les AUTRES membres
      // (card_data léger du catalogue + images sur Supabase Storage)
      final missingCatIds = [
        for (final id in serverIds)
          if (!all.any((c) => c.id == id)) id,
      ];
      final catalog = await CollectionService.instance.getCollectionCardsData(
        widget.collection.id,
        missingCatIds,
      );
      final missing = <SavedCard>[];
      for (final e in catalog) {
        if (e.cardData == null) continue;
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
        _goldIds = gold;
        _loading = false;
      });
    }
  }

  // ✨ FUSION GOLD : confirmation puis fusion (consomme les exemplaires)
  Future<void> _confirmFuse(SavedCard card) async {
    final cost = _goldCost[card.rarity]!;
    final have = _qtyByCard[card.id] ?? 1;
    if (_goldIds.contains(card.id) || have < cost) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: _gold, width: 1.5),
            ),
            title: Text(
              '⚡ Fusion GOLD',
              style: _arcade(size: 18, color: _gold),
            ),
            content: Text(
              'Fusionner $cost exemplaires de « ${card.name} » pour obtenir '
              'sa version GOLD permanente ?\n\n'
              'Les exemplaires utilisés seront consommés.',
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
                    gradient: const LinearGradient(colors: [_gold, _goldDeep]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '⚡ Fusionner',
                    style: _body(
                      color: const Color(0xFF2A1C00),
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;

    final ok = await CollectionService.instance.fuseCardToGold(
      widget.collection.id,
      card.id,
      cost,
    );
    if (!mounted) return;
    if (ok) {
      HapticFeedback.heavyImpact();
      _msg('🥇 « ${card.name} » est passée GOLD !');
      await _loadCards();
    } else {
      _msg('Fusion impossible (pas assez d\'exemplaires ?)', err: true);
    }
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
    if (_openingPack) return;
    // ✨ Retour haptique : le pack s'ouvre !
    HapticFeedback.mediumImpact();
    final rng = math.Random();
    final packCards = List.generate(3, (_) => _weightedPick(pool, rng));

    // ✅ CORRECTIF MAJEUR : la sauvegarde passe AVANT tout le reste.
    //
    // Avant, l'ordre était : cooldown → série → prefs locales → animation,
    // et la sauvegarde serveur arrivait tout à la fin. Si elle échouait, le
    // joueur perdait TROIS choses d'un coup : ses cartes, ses 3 h de
    // cooldown et sa série — alors que ses prefs locales lui affichaient
    // quand même les cartes, jusqu'à ce que la synchro suivante les efface
    // sans explication.
    //
    // Désormais, tant que le serveur n'a pas confirmé, RIEN n'est consommé :
    // le joueur peut simplement réappuyer sur le bouton.
    setState(() => _openingPack = true);
    try {
      await CollectionService.instance.saveUserCards(
        widget.collection.id,
        packCards,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _openingPack = false);
        _msg(
          '❌ Enregistrement impossible. Ton pack n\'a pas été consommé, '
          'réessaie.',
          err: true,
        );
      }
      return;
    }
    if (mounted) setState(() => _openingPack = false);

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
    // ✨ Badge NEW : seules les cartes de CE pack portent le badge ;
    // tout le reste passe en « déjà vu » jusqu'au prochain pack.
    final packIds = packCards.map((c) => c.id).toSet();
    await prefs.setStringList(
      _seenKey(widget.collection.id),
      ({...existing, ..._obtainedCards.map((c) => c.id)}
        ..removeAll(packIds)).toList(),
    );
    _countdownKey.currentState?.refresh();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PackOpeningScreen(
              cards: packCards,
              collectionId: _col.id,
              // Déjà enregistré ci-dessus : l'écran ne fait qu'animer.
              saveCards: false,
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
    // ✨ Retour du pack → onglet Cartes directement (badges NEW visibles)
    if (mounted) _tabCtrl.animateTo(1);
    await _loadCards();
    _countdownKey.currentState?.refresh();
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
                      Tab(
                        text:
                            _isAdmin
                                ? '🛠️ Admin'
                                : (_canAddCards ? '✏️ Créer' : '🔒 Créer'),
                      ),
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
                              _isAdmin
                                  ? _adminTab(p)
                                  : (_canAddCards
                                      ? _createTab(p)
                                      : _createLockedTab()),
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
    // 🛠️ Outils de test — n'apparaît JAMAIS en build release.
    actions: [
      if (DevTools.enabled)
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          child: GestureDetector(
            onTap:
                () => DevPanel.show(
                  context,
                  collectionId: widget.collection.id,
                  onChanged: () async {
                    await _loadCards();
                    await _loadAdmin();
                  },
                ),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold, width: 1.5),
              ),
              child: const Center(
                child: Text('🛠️', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ),
    ],
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
      centerTitle: true,
      titlePadding: const EdgeInsets.only(left: 60, right: 60, bottom: 18),
      title: Text(
        _col.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _arcade(
          size: 19,
          color: Colors.white,
          shadows: const [Shadow(color: Colors.black45, offset: Offset(2, 3))],
        ),
      ),
      background: Stack(
        fit: StackFit.expand,
        children: [
          // dégradé série (fond de secours si pas d'image)
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
          // ✨ BANNIÈRE : l'image de la collection en plein cadre.
          // ⚠️ `_col` et non `widget.collection` : sinon la nouvelle image
          // n'apparaît qu'au prochain redémarrage de l'écran.
          if (_col.imageUrl != null) ...[
            Image.network(
              _col.imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: 900,
              errorBuilder: (_, error, __) {
                // Cause la plus fréquente : le bucket Storage `collections`
                // n'est pas PUBLIC → l'URL renvoie 403 et l'image est ignorée.
                debugPrint('⚠️ Bannière « ${_col.name} » illisible : $error');
                debugPrint('   URL : ${_col.imageUrl}');
                return const SizedBox.shrink();
              },
            ),
            // voile dégradé : garde le titre lisible quelle que soit l'image
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x40000000),
                    Color(0x99000000),
                    Color(0xD90D0A16),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ],
          // badges déplacés en HAUT à droite pour ne pas gêner le titre centré
          Positioned(
            top: 14,
            right: 16,
            child: Row(
              children: [
                _pixelBadge(
                  '⏱ ${_col.cooldownLabel}',
                  color: Colors.white,
                  bg: Colors.black.withValues(alpha: 0.35),
                  borderColor: Colors.white.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
                _pixelBadge(
                  '🃏 ${_catalogue.length}',
                  color: Colors.white,
                  bg: Colors.black.withValues(alpha: 0.35),
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
        // ✨ Seul CE widget se reconstruit chaque seconde (voir
        // pack_countdown.dart). La grille de cartes ne bouge plus.
        PackCountdown(
          key: _countdownKey,
          collectionId: widget.collection.id,
          cooldownHours: _col.packCooldownHours,
          builder:
              (_, remaining, canOpen) =>
                  canOpen ? _openBtn(p) : _timerWidget(remaining),
        ),
        const SizedBox(height: 16),
        DailyRewardBanner(collection: _col, onClaimed: _loadCards),
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
    child:
        _openingPack
            // Court instant d'enregistrement : le pack n'est consommé
            // qu'une fois le serveur confirmé.
            ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(width: 12),
                Text('ENREGISTREMENT…'),
              ],
            )
            : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 22),
                SizedBox(width: 10),
                Text('OUVRIR LE PACK'),
              ],
            ),
  );

  Widget _timerWidget(Duration remaining) => Container(
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
          PackSystem.formatDuration(remaining),
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
    // ✅ RÈGLE COMMUNE avec l'écran Collections : on ne compte que les cartes
    // RÉELLES (reconstruites). Une entrée de catalogue orpheline — sans
    // card_data, donc n'affichant aucune carte — ne gonfle plus le total.
    final total = cat.length;
    final owned = cat.where((c) => obtIds.contains(c.id)).length;
    final pct = total == 0 ? 0.0 : owned / total;
    final complete = owned == total;

    // ✨ Progression GOLD — sur le même dénominateur que le dex : une case
    // de dex = une carte à obtenir, puis à dorer.
    final goldOwned = cat.where((c) => _goldIds.contains(c.id)).length;
    final goldPct = total == 0 ? 0.0 : goldOwned / total;
    final goldComplete = total > 0 && goldOwned == total;

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

          // ✨ SECONDE JAUGE — progression GOLD.
          // Même case du dex, second palier : le joueur qui termine son dex
          // découvre qu'il lui reste toutes ses cartes à dorer.
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _surfaceLine, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      goldComplete ? '👑' : '🥇',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'GOLD',
                      style: _pixel(
                        size: 9,
                        color: _creamFaint,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$goldOwned / $total',
                      style: _arcade(
                        size: 15,
                        color: goldOwned > 0 ? _gold : _creamFaint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(goldPct * 100).round()}%',
                      style: _pixel(
                        size: 10,
                        color: goldOwned > 0 ? _gold : _creamFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: goldPct,
                    minHeight: 9,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    valueColor: const AlwaysStoppedAnimation(_gold),
                  ),
                ),
              ],
            ),
          ),

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

              // ✨ FILTRE VITRINE GOLD — n'affiche que les cartes dorées.
              // Séparé visuellement du tri par une barre verticale : ce n'est
              // pas un critère de tri mais un filtre.
              Container(
                width: 1,
                height: 22,
                margin: const EdgeInsets.only(right: 8),
                color: _surfaceLine,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _goldOnly = !_goldOnly),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _goldOnly ? _gold : _cream.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: _goldOnly ? Colors.transparent : _gold,
                        width: 1.5,
                      ),
                      boxShadow:
                          _goldOnly
                              ? [
                                BoxShadow(
                                  color: _gold.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                ),
                              ]
                              : null,
                    ),
                    child: Text(
                      '🥇 Gold',
                      style: _body(
                        size: 12,
                        color: _goldOnly ? const Color(0xFF2A1C00) : _gold,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      Expanded(child: _cardGrid()),
    ],
  );

  Widget _cardGrid() {
    final obtIds = _obtainedCards.map((c) => c.id).toSet();
    // ✨ Filtre vitrine GOLD appliqué avant le tri
    final source =
        _goldOnly
            ? _catalogue.where((c) => _goldIds.contains(c.id)).toList()
            : _catalogue;
    final cards = _sorted(source);

    // État vide spécifique à la vitrine : on n'affiche pas « Crée-en dans
    // l'onglet ✏️ », qui n'aurait aucun sens ici.
    if (cards.isEmpty && _goldOnly) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🥇',
                style: TextStyle(
                  fontSize: 50,
                  color: _cream.withValues(alpha: 0.2),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucune carte GOLD',
                textAlign: TextAlign.center,
                style: _arcade(size: 16, color: _creamFaint),
              ),
              const SizedBox(height: 6),
              Text(
                'Accumule les doublons d\'une même carte, '
                'puis fusionne-les pour la dorer.',
                textAlign: TextAlign.center,
                style: _body(size: 13, color: _creamFaint),
              ),
            ],
          ),
        ),
      );
    }

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
            isGold: _goldIds.contains(c.id),
            onFuse: revealed ? () => _confirmFuse(c) : null,
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

  /// ✅ CORRECTIF : le réglage « les membres peuvent ajouter des cartes »
  /// était enregistré en base et modifiable par le propriétaire… mais
  /// n'était lu NULLE PART. Les membres gardaient l'onglet ✏️ Créer et
  /// pouvaient ajouter des cartes quoi qu'il arrive : l'interrupteur ne
  /// faisait littéralement rien.
  /// Les admins ne sont jamais concernés par la restriction.
  bool get _canAddCards => _isAdmin || _col.membersCanAddCards;

  /// Onglet affiché à un membre quand le propriétaire a verrouillé l'ajout.
  Widget _createLockedTab() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '🔒',
            style: TextStyle(
              fontSize: 52,
              color: _cream.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ajout de cartes verrouillé',
            textAlign: TextAlign.center,
            style: _arcade(size: 17, color: _creamDim),
          ),
          const SizedBox(height: 8),
          Text(
            'Le propriétaire de cette collection a réservé la création '
            'de cartes aux administrateurs.',
            textAlign: TextAlign.center,
            style: _body(size: 13.5, color: _creamFaint, height: 1.45),
          ),
        ],
      ),
    ),
  );

  // ✨ Editeur MODERNE (calques, stickers, contour/ombre, rotation,
  // selecteur de couleur). Il remplace l'ancien _CardCreator, qui n'etait
  // conserve que parce qu'il savait enregistrer dans une collection —
  // CardCreatorScreen le fait desormais via `collectionId`.
  Widget _createTab(List<Color> p) => CardCreatorScreen(
    collectionId: widget.collection.id,
    embedded: true,
    onMoveModeChanged: (v) => setState(() => _cardMoveMode = v),
    onSaved: () {
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
        child: CardCreatorScreen(
          collectionId: widget.collection.id,
          embedded: true,
          onMoveModeChanged: (v) => setState(() => _cardMoveMode = v),
          onSaved: () {
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
