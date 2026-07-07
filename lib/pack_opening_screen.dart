// pack_opening_screen.dart
// Ouverture de pack — style RÉTRO-ARCADE PREMIUM (réf. Balatro).
// D'après le handoff Claude Design "Brokemon". 3 étapes :
//   cérémonie (sachet foil qu'on déchire) → révélation carte par carte → récap.
// La personnalisation du pack (image / titre / sous-titre) est conservée.
// Signature et branchements (CollectionService, inspecteur 3D) inchangés.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'card_model.dart';
import 'card_storage.dart';
import 'card_inspector_screen.dart';
import 'collection_service.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   PALETTE & POLICES (tokens du handoff)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _Pal {
  static const bg = Color(0xFF14101F);
  static const bgDeep = Color(0xFF0D0A16);
  static const surface = Color(0xFF211A33);
  static const gold = Color(0xFFFFC83D);
  static const goldDeep = Color(0xFFE0A91E);
  static const teal = Color(0xFF21E6C1);
  static const cream = Color(0xFFF6EEDD);
  static Color creamDim = const Color(0xFFF6EEDD).withValues(alpha: 0.62);
  static Color creamFaint = const Color(0xFFF6EEDD).withValues(alpha: 0.34);
}

// Police "arcade" (titres) — Lilita One. Police "pixel" — Silkscreen.
TextStyle _arcade({
  double size = 16,
  Color color = _Pal.cream,
  double spacing = 0.5,
  List<Shadow>? shadows,
}) => GoogleFonts.lilitaOne(
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  shadows: shadows,
);

TextStyle _pixel({
  double size = 9,
  Color color = _Pal.cream,
  double spacing = 1,
  FontWeight weight = FontWeight.w400,
}) => GoogleFonts.silkscreen(
  fontSize: size,
  color: color,
  letterSpacing: spacing,
  fontWeight: weight,
);

// Couleur + nom + glow par rareté (tokens du handoff)
Color _rarityColor(Rarity r) {
  switch (r) {
    case Rarity.legendary:
      return _Pal.gold;
    case Rarity.epic:
      return const Color(0xFFB45CFF);
    case Rarity.rare:
      return const Color(0xFF2FA8FF);
    case Rarity.uncommon:
      return const Color(0xFF3FD17A);
    case Rarity.common:
      return const Color(0xFF9AA0B0);
  }
}

String _rarityName(Rarity r) {
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

int _rarityRank(Rarity r) {
  switch (r) {
    case Rarity.common:
      return 0;
    case Rarity.uncommon:
      return 1;
    case Rarity.rare:
      return 2;
    case Rarity.epic:
      return 3;
    case Rarity.legendary:
      return 4;
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   ÉCRAN PRINCIPAL
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

enum _Stage { open, reveal, recap }

class PackOpeningScreen extends StatefulWidget {
  final List<SavedCard> cards;
  final String collectionId;
  final String packName;
  final Color packColor;

  // Personnalisation conservée
  final Uint8List? packImageBytes;
  final String? packImageUrl;
  final String packSubtitle;

  const PackOpeningScreen({
    super.key,
    required this.cards,
    required this.collectionId,
    this.packName = 'Booster',
    this.packColor = const Color(0xFF8A4DFF),
    this.packImageBytes,
    this.packImageUrl,
    this.packSubtitle = 'Pack surprise',
  });

  @override
  State<PackOpeningScreen> createState() => _PackOpeningScreenState();
}

class _PackOpeningScreenState extends State<PackOpeningScreen>
    with TickerProviderStateMixin {
  _Stage _stage = _Stage.open;

  // Cartes triées par rareté croissante (climax à la fin), comme le handoff.
  late final List<SavedCard> _cards;
  int _index = 0;
  late List<bool> _revealed;

  bool _flash = false;
  bool _legMoment = false;
  bool _isSaving = false;
  bool _suspense = false; // petite pause de tension avant la dernière carte

  // Animations transverses
  late final AnimationController _flashCtrl;
  late final AnimationController _rayCtrl; // rayons en fond (rayspin)
  late final AnimationController _bannerCtrl; // bannière légendaire

  @override
  void initState() {
    super.initState();
    _cards = [...widget.cards]
      ..sort((a, b) => _rarityRank(a.rarity).compareTo(_rarityRank(b.rarity)));
    _revealed = List.filled(_cards.length, false);

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _rayCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _bannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
  }

  @override
  void dispose() {
    _flashCtrl.dispose();
    _rayCtrl.dispose();
    _bannerCtrl.dispose();
    super.dispose();
  }

  Rarity get _topRarity => _cards
      .map((c) => c.rarity)
      .reduce((a, b) => _rarityRank(a) >= _rarityRank(b) ? a : b);

  void _doFlash([int ms = 550]) {
    _flashCtrl.duration = Duration(milliseconds: ms);
    setState(() => _flash = true);
    _flashCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _flash = false);
    });
  }

  void _onCeremonyDone() {
    _doFlash(520);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _stage = _Stage.reveal);
    });
  }

  void _flip(int i) {
    if (_revealed[i]) return;
    final card = _cards[i];
    final rank = _rarityRank(card.rarity);
    if (rank >= 2) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    setState(() => _revealed[i] = true);
    if (card.rarity == Rarity.legendary) {
      _doFlash(400);
      setState(() => _legMoment = true);
      _bannerCtrl.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 2600), () {
        if (mounted) setState(() => _legMoment = false);
      });
    }
  }

  void _advance() {
    if (_index < _cards.length - 1) {
      final goingToLast = _index + 1 == _cards.length - 1;
      // Avant la dernière carte : petite pause de tension (suspense),
      // d'autant plus longue que la dernière carte est rare.
      if (goingToLast) {
        final topRank = _rarityRank(_cards.last.rarity);
        final ms = 700 + topRank * 200; // 700ms → 1500ms selon la rareté
        HapticFeedback.mediumImpact();
        setState(() => _suspense = true);
        Future.delayed(Duration(milliseconds: ms), () {
          if (!mounted) return;
          setState(() {
            _suspense = false;
            _index++;
          });
        });
      } else {
        setState(() => _index++);
      }
    } else {
      setState(() => _stage = _Stage.recap);
    }
  }

  void _inspect(SavedCard card) {
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
  }

  Future<void> _saveAndReturn() async {
    setState(() => _isSaving = true);
    try {
      await CollectionService.instance.saveUserCards(
        widget.collectionId,
        widget.cards,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final revealColor =
        _stage == _Stage.reveal
            ? _rarityColor(_cards[_index].rarity)
            : _Pal.gold;

    return Scaffold(
      backgroundColor: _Pal.bgDeep,
      body: Stack(
        children: [
          // Fond radial
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.36),
                radius: 1.1,
                colors: [Color(0xFF271C40), _Pal.bg, _Pal.bgDeep],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),

          // Rayons en fond (sauf récap)
          if (_stage != _Stage.recap)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _legMoment ? 0.6 : 0.16,
                  child: _RayBurst(
                    controller: _rayCtrl,
                    color: _legMoment ? _Pal.gold : revealColor,
                  ),
                ),
              ),
            ),

          // Chrome haut (croix + compteur)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _Pal.cream.withValues(alpha: 0.10),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: _Pal.cream,
                        size: 18,
                      ),
                    ),
                  ),
                  if (_stage == _Stage.reveal)
                    Text(
                      'CARTE ${_index + 1}/${_cards.length}',
                      style: _pixel(size: 9, color: _Pal.creamDim),
                    ),
                ],
              ),
            ),
          ),

          // Corps
          Positioned.fill(
            child: SafeArea(
              child: switch (_stage) {
                _Stage.open => _BoosterCeremony(
                  packName: widget.packName,
                  packSubtitle: widget.packSubtitle,
                  packImageBytes: widget.packImageBytes,
                  packImageUrl: widget.packImageUrl,
                  cardCount: _cards.length,
                  onOpened: _onCeremonyDone,
                  onFlash: _doFlash,
                ),
                _Stage.reveal => _RevealCarte(
                  cards: _cards,
                  index: _index,
                  revealed: _revealed,
                  legMoment: _legMoment,
                  onFlip: () => _flip(_index),
                  onAdvance: _advance,
                ),
                _Stage.recap => _Recap(
                  cards: _cards,
                  topRarity: _topRarity,
                  isSaving: _isSaving,
                  onInspect: _inspect,
                  onDone: _saveAndReturn,
                ),
              },
            ),
          ),

          // Bannière légendaire
          if (_legMoment)
            Positioned(
              top: MediaQuery.of(context).size.height * 0.13,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _bannerCtrl,
                      curve: Curves.elasticOut,
                    ),
                    child: Text(
                      'LÉGENDAIRE !',
                      style: _arcade(
                        size: 40,
                        color: _Pal.gold,
                        spacing: 1,
                        shadows: const [
                          Shadow(blurRadius: 24, color: Color(0xE6FFC83D)),
                          Shadow(
                            offset: Offset(3, 4),
                            color: Color(0x66000000),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Overlay de suspense avant la dernière carte
          if (_suspense)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: const Center(child: _SuspensePulse()),
                ),
              ),
            ),

          // Flash blanc
          if (_flash)
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 1, end: 0).animate(
                    CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut),
                  ),
                  child: const ColoredBox(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   SUSPENSE AVANT LA DERNIÈRE CARTE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SuspensePulse extends StatefulWidget {
  const _SuspensePulse();
  @override
  State<_SuspensePulse> createState() => _SuspensePulseState();
}

class _SuspensePulseState extends State<_SuspensePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 1.0 + t * 0.18,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0x33FFC83D), Color(0x00FFC83D)],
                  ),
                  border: Border.all(
                    color: _Pal.gold.withValues(alpha: 0.4 + t * 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _Pal.gold.withValues(alpha: 0.25 + t * 0.35),
                      blurRadius: 24 + t * 20,
                      spreadRadius: t * 6,
                    ),
                  ],
                ),
                child: Center(
                  child: Text('?', style: _arcade(size: 52, color: _Pal.gold)),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'DERNIÈRE CARTE...',
              style: _pixel(size: 11, color: _Pal.teal, spacing: 2),
            ),
          ],
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CÉRÉMONIE — SACHET FOIL QU'ON DÉCHIRE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _BoosterCeremony extends StatefulWidget {
  final String packName;
  final String packSubtitle;
  final Uint8List? packImageBytes;
  final String? packImageUrl;
  final int cardCount;
  final VoidCallback onOpened;
  final void Function([int]) onFlash;

  const _BoosterCeremony({
    required this.packName,
    required this.packSubtitle,
    required this.packImageBytes,
    required this.packImageUrl,
    required this.cardCount,
    required this.onOpened,
    required this.onFlash,
  });

  @override
  State<_BoosterCeremony> createState() => _BoosterCeremonyState();
}

class _BoosterCeremonyState extends State<_BoosterCeremony>
    with SingleTickerProviderStateMixin {
  static const double kW = 220, kH = 304;

  double _progress = 0; // 0 → 1
  bool _done = false;
  bool _dragging = false;
  double _startY = 0;
  double _moved = 0;

  late final AnimationController _idle; // flottement + foil

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    // anime progress → 1
    const step = Duration(milliseconds: 18);
    void tick() {
      if (!mounted) return;
      setState(() => _progress = math.min(1, _progress + 0.12));
      if (_progress >= 1) {
        widget.onFlash(520);
        Future.delayed(const Duration(milliseconds: 300), widget.onOpened);
      } else {
        Future.delayed(step, tick);
      }
    }

    tick();
  }

  void _snapBack() {
    const step = Duration(milliseconds: 16);
    void tick() {
      if (!mounted || _done) return;
      setState(() => _progress = math.max(0, _progress - 0.14));
      if (_progress > 0) Future.delayed(step, tick);
    }

    tick();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _done ? 0 : 1,
          child: Text(
            '★ DÉCHIRE LE SACHET ★',
            style: _pixel(size: 10, color: _Pal.teal, spacing: 2),
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onVerticalDragStart: (d) {
            if (_done) return;
            _dragging = true;
            _startY = d.globalPosition.dy;
            _moved = 0;
          },
          onVerticalDragUpdate: (d) {
            if (!_dragging || _done) return;
            final up = _startY - d.globalPosition.dy;
            _moved = math.max(_moved, up.abs());
            setState(() => _progress = (up / 150).clamp(0.0, 1.0));
          },
          onVerticalDragEnd: (_) {
            if (!_dragging || _done) return;
            _dragging = false;
            if (_moved < 8) {
              _finish();
            } else if (_progress >= 0.42) {
              _finish();
            } else {
              _snapBack();
            }
          },
          onTap: () {
            if (!_done) _finish();
          },
          child: AnimatedBuilder(
            animation: _idle,
            builder: (_, __) {
              final bob =
                  (_progress == 0 && !_done)
                      ? math.sin(_idle.value * 2 * math.pi) * 10
                      : 0.0;
              final rot =
                  (_progress == 0 && !_done)
                      ? math.sin(_idle.value * 2 * math.pi) * 0.026
                      : 0.0;
              return Transform.translate(
                offset: Offset(0, bob),
                child: Transform.rotate(angle: rot, child: _packStack()),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _done ? 0 : 1,
          child: Text('Tire vers le haut ↑', style: _arcade(size: 17)),
        ),
      ],
    );
  }

  Widget _packStack() {
    final lidDx = _progress * 26;
    final lidDy = -_progress * 250;
    final lidRot = _progress * 18 * math.pi / 180;
    final lidOpacity = (1 - _progress * 0.95).clamp(0.0, 1.0);
    final cardsDy = -_progress * 168;
    final foil = _idle.value;

    return SizedBox(
      width: kW + 40,
      height: kH + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // halo doré
          Container(
            width: 200,
            height: 200,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x59FFC83D), Color(0x00FFC83D)],
                stops: [0.0, 0.7],
              ),
            ),
          ),

          // dos du sachet
          SizedBox(
            width: kW,
            height: kH,
            child: _FoilFace(dark: true, foil: foil),
          ),

          // cartes qui sortent
          Transform.translate(
            offset: Offset(0, cardsDy),
            child: SizedBox(
              width: kW,
              height: kH,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  for (final o in [-1, 0, 1])
                    Positioned(
                      top: 64,
                      child: Transform.translate(
                        offset: Offset(o * 16, 0),
                        child: Transform.rotate(
                          angle: o * 5 * math.pi / 180,
                          child: _MiniCardBack(w: 120),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // face avant (bord déchiré en bas de la ligne zigzag)
          ClipPath(
            clipper: _TearClipper(isLid: false),
            child: SizedBox(
              width: kW,
              height: kH,
              child: _FoilFace(
                foil: foil,
                showArt: true,
                packName: widget.packName,
                packSubtitle: widget.packSubtitle,
                packImageBytes: widget.packImageBytes,
                packImageUrl: widget.packImageUrl,
                cardCount: widget.cardCount,
                tornRimShadow: true,
              ),
            ),
          ),

          // couvercle détachable (au-dessus de la ligne)
          Transform.translate(
            offset: Offset(lidDx, lidDy),
            child: Transform.rotate(
              angle: lidRot,
              child: Opacity(
                opacity: lidOpacity,
                child: ClipPath(
                  clipper: _TearClipper(isLid: true),
                  child: SizedBox(
                    width: kW,
                    height: kH,
                    child: _FoilFace(foil: foil, crimp: true),
                  ),
                ),
              ),
            ),
          ),

          // languette 👆
          if (!_done)
            Positioned(
              top: 2,
              right: 4,
              child: AnimatedBuilder(
                animation: _idle,
                builder:
                    (_, __) => Transform.translate(
                      offset: Offset(
                        0,
                        math.sin(_idle.value * 2 * math.pi) * 4,
                      ),
                      child: const Text('👆', style: TextStyle(fontSize: 22)),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

// Face foil du sachet (réutilisée pour dos / face / couvercle)
class _FoilFace extends StatelessWidget {
  final bool dark;
  final bool showArt;
  final bool crimp;
  final bool tornRimShadow;
  final double foil; // 0..1 position du reflet
  final String? packName;
  final String? packSubtitle;
  final Uint8List? packImageBytes;
  final String? packImageUrl;
  final int? cardCount;

  const _FoilFace({
    this.dark = false,
    this.showArt = false,
    this.crimp = false,
    this.tornRimShadow = false,
    this.foil = 0,
    this.packName,
    this.packSubtitle,
    this.packImageBytes,
    this.packImageUrl,
    this.cardCount,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // fond foil holographique
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.7, -1),
                  end: const Alignment(0.7, 1),
                  colors:
                      dark
                          ? const [Color(0xFF2A2140), Color(0xFF15101F)]
                          : const [
                            Color(0xFF3A2A6A),
                            Color(0xFF6A2EA8),
                            Color(0xFF21808F),
                            Color(0xFFB43E78),
                            Color(0xFF3A2A6A),
                          ],
                  stops: dark ? null : const [0.0, 0.26, 0.52, 0.74, 1.0],
                ),
              ),
            ),
          ),
          // scanlines
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinesPainter(opacity: 0.16)),
            ),
          ),
          // reflet foil animé (diagonale qui balaie)
          if (!dark)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _FoilShinePainter(t: foil)),
              ),
            ),
          // contenu (wordmark + image + pastille)
          if (showArt && !dark) Positioned.fill(child: _artContent()),
          // sertissage cranté (couvercle)
          if (crimp)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 14,
              child: CustomPaint(painter: _CrimpPainter()),
            ),
          // ombre du haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 78,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ombre intérieure du bord déchiré
          if (tornRimShadow)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _artContent() {
    Widget emblem;
    const d = 70.0;
    if (packImageBytes != null) {
      emblem = ClipOval(
        child: Image.memory(
          packImageBytes!,
          width: d,
          height: d,
          fit: BoxFit.cover,
          cacheWidth: 140,
          errorBuilder: (_, __, ___) => _defaultEmblem(d),
        ),
      );
    } else if (packImageUrl != null && packImageUrl!.isNotEmpty) {
      emblem = ClipOval(
        child: Image.network(
          packImageUrl!,
          width: d,
          height: d,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultEmblem(d),
        ),
      );
    } else {
      emblem = _defaultEmblem(d);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          emblem,
          const SizedBox(height: 12),
          Text(
            (packName ?? 'BOOSTER').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _arcade(
              size: 22,
              spacing: 0.5,
              shadows: const [
                Shadow(blurRadius: 1, color: _Pal.gold),
                Shadow(offset: Offset(2, 2), color: Color(0x66000000)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(packSubtitle ?? '').toUpperCase()} · ${cardCount ?? 3} CARTES',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _pixel(
              size: 8,
              color: _Pal.cream.withValues(alpha: 0.85),
              spacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultEmblem(double d) => Container(
    width: d,
    height: d,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
    ),
    child: const Center(child: Text('✨', style: TextStyle(fontSize: 32))),
  );
}

// Découpe en dents de scie partagée (couvercle = au-dessus, face = en-dessous)
class _TearClipper extends CustomClipper<Path> {
  final bool isLid;
  _TearClipper({required this.isLid});

  // Points (en % de hauteur) de la ligne zigzag, comme le handoff.
  static const List<List<double>> _zig = [
    [0.0, 0.25],
    [0.02, 0.18],
    [0.09, 0.27],
    [0.16, 0.18],
    [0.23, 0.27],
    [0.30, 0.18],
    [0.37, 0.27],
    [0.44, 0.18],
    [0.51, 0.27],
    [0.58, 0.18],
    [0.65, 0.27],
    [0.72, 0.18],
    [0.79, 0.27],
    [0.86, 0.18],
    [0.93, 0.27],
    [1.0, 0.20],
  ];

  @override
  Path getClip(Size size) {
    final p = Path();
    if (isLid) {
      p.moveTo(0, 0);
      p.lineTo(size.width, 0);
      for (final pt in _zig.reversed) {
        p.lineTo(pt[0] * size.width, pt[1] * size.height);
      }
      p.close();
    } else {
      for (var i = 0; i < _zig.length; i++) {
        final pt = _zig[i];
        if (i == 0) {
          p.moveTo(pt[0] * size.width, pt[1] * size.height);
        } else {
          p.lineTo(pt[0] * size.width, pt[1] * size.height);
        }
      }
      p.lineTo(size.width, size.height);
      p.lineTo(0, size.height);
      p.close();
    }
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ScanlinesPainter extends CustomPainter {
  final double opacity;
  _ScanlinesPainter({required this.opacity});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinesPainter old) => false;
}

class _FoilShinePainter extends CustomPainter {
  final double t;
  _FoilShinePainter({required this.t});
  @override
  void paint(Canvas canvas, Size size) {
    final x = (t * 2 - 0.5) * size.width;
    final rect = Rect.fromLTWH(
      x - size.width * 0.3,
      -size.height * 0.2,
      size.width * 0.6,
      size.height * 1.4,
    );
    final paint =
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(rect)
          ..blendMode = BlendMode.plus;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.42);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRect(rect.translate(x, 0), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoilShinePainter old) => old.t != t;
}

class _CrimpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 3, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 3, 0, 3, size.height),
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrimpPainter old) => false;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   RAYONS, SPARKLES, BOUTON ARCADE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RayBurst extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  const _RayBurst({required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder:
          (_, __) => CustomPaint(
            painter: _RayPainter(
              angle: controller.value * 2 * math.pi,
              color: color,
            ),
          ),
    );
  }
}

class _RayPainter extends CustomPainter {
  final double angle;
  final Color color;
  _RayPainter({required this.angle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);
    final radius = size.longestSide;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final paint = Paint()..color = color.withValues(alpha: 0.5);
    const rays = 30;
    for (int i = 0; i < rays; i++) {
      final a0 = (i / rays) * 2 * math.pi;
      final a1 = a0 + (math.pi / rays) * 0.7;
      final path =
          Path()
            ..moveTo(0, 0)
            ..lineTo(math.cos(a0) * radius, math.sin(a0) * radius)
            ..lineTo(math.cos(a1) * radius, math.sin(a1) * radius)
            ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
    // masque radial : on assombrit les bords pour fondre
    final mask =
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.transparent, _Pal.bgDeep],
            stops: const [0.32, 0.62],
          ).createShader(Rect.fromCircle(center: center, radius: radius * 0.62))
          ..blendMode = BlendMode.dstOut;
    canvas.drawRect(Offset.zero & size, mask);
  }

  @override
  bool shouldRepaint(covariant _RayPainter old) =>
      old.angle != angle || old.color != color;
}

class _ArcadeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool big;
  final double? width;
  const _ArcadeButton({
    required this.label,
    this.onTap,
    this.big = false,
    this.width,
  });

  @override
  State<_ArcadeButton> createState() => _ArcadeButtonState();
}

class _ArcadeButtonState extends State<_ArcadeButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: widget.width,
        transform: Matrix4.translationValues(0, _down ? 5 : 0, 0),
        padding: EdgeInsets.symmetric(
          horizontal: widget.big ? 26 : 20,
          vertical: widget.big ? 17 : 13,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE0A0), _Pal.gold, _Pal.goldDeep],
            stops: [0.0, 0.42, 1.0],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow:
              _down
                  ? [
                    const BoxShadow(color: _Pal.goldDeep, offset: Offset(0, 2)),
                  ]
                  : [
                    const BoxShadow(color: _Pal.goldDeep, offset: Offset(0, 6)),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      offset: const Offset(0, 12),
                      blurRadius: 22,
                    ),
                  ],
        ),
        child: Center(
          child: Text(
            widget.label,
            maxLines: 1,
            style: _arcade(
              size: widget.big ? 19 : 15.5,
              color: const Color(0xFF2A1C00),
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CARTE ARCADE (recto + dos) — utilise les vraies cartes
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _MiniCardBack extends StatelessWidget {
  final double w;
  const _MiniCardBack({required this.w});
  @override
  Widget build(BuildContext context) {
    final h = w * 1.4;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.1),
        gradient: const LinearGradient(
          begin: Alignment(-0.7, -1),
          end: Alignment(0.7, 1),
          colors: [Color(0xFF2B2240), Color(0xFF1A1428)],
        ),
        border: Border.all(color: const Color(0xFF3A2E58), width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Center(
        child: Transform.rotate(
          angle: -8 * math.pi / 180,
          child: Text(
            '?',
            style: _arcade(
              size: w * 0.5,
              color: _Pal.gold.withValues(alpha: 0.92),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArcadeCard extends StatelessWidget {
  final SavedCard card;
  final double w;
  final bool faceDown;
  final bool glow;
  final VoidCallback? onTap;

  const _ArcadeCard({
    required this.card,
    required this.w,
    this.faceDown = false,
    this.glow = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = w * 1.4;
    final rc = _rarityColor(card.rarity);
    final isLeg = card.rarity == Rarity.legendary;

    if (faceDown) {
      return GestureDetector(onTap: onTap, child: _MiniCardBack(w: w));
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: h,
        padding: EdgeInsets.all(math.max(3.5, w * 0.028)),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(w * 0.1),
          gradient:
              isLeg
                  ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFE89A),
                      _Pal.gold,
                      Color(0xFFC9920E),
                      _Pal.gold,
                      Color(0xFFFFF1B8),
                    ],
                    stops: [0.0, 0.3, 0.55, 0.78, 1.0],
                  )
                  : LinearGradient(
                    begin: const Alignment(-0.7, -1),
                    end: const Alignment(0.7, 1),
                    colors: [
                      Color.lerp(rc, Colors.white, 0.5)!,
                      rc,
                      Color.lerp(rc, Colors.black, 0.3)!,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
          boxShadow:
              glow
                  ? [
                    BoxShadow(
                      color: rc.withValues(alpha: 0.55),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 26,
                      offset: const Offset(0, 12),
                    ),
                  ]
                  : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(w * 0.075),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_Pal.surface, Color(0xFF171125)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // header : nom + PW
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    w * 0.045,
                    w * 0.04,
                    w * 0.045,
                    w * 0.022,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _arcade(
                            size: w * 0.088,
                            shadows: const [
                              Shadow(
                                offset: Offset(0, 1.5),
                                color: Color(0x73000000),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // fenêtre d'illustration
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: w * 0.045),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(w * 0.05),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.5),
                                radius: 1.0,
                                colors: [
                                  Color.lerp(
                                    rc,
                                    const Color(0xFF1B1430),
                                    0.62,
                                  )!,
                                  const Color(0xFF140F22),
                                ],
                              ),
                            ),
                          ),
                          if (card.imageBytes != null)
                            Image.memory(
                              card.imageBytes!,
                              fit: BoxFit.contain,
                              cacheWidth: 800,
                              errorBuilder:
                                  (_, __, ___) => const SizedBox.shrink(),
                            ),
                          // glow derrière
                          Center(
                            child: FractionallySizedBox(
                              widthFactor: 0.7,
                              heightFactor: 0.6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      rc.withValues(alpha: 0.5),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // footer : badge rareté
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    w * 0.045,
                    w * 0.04,
                    w * 0.045,
                    w * 0.05,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: rc),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _rarityName(card.rarity).toUpperCase(),
                        style: _pixel(size: w * 0.05, color: rc),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   RÉVÉLATION CARTE PAR CARTE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _RevealCarte extends StatelessWidget {
  final List<SavedCard> cards;
  final int index;
  final List<bool> revealed;
  final bool legMoment;
  final VoidCallback onFlip;
  final VoidCallback onAdvance;

  const _RevealCarte({
    required this.cards,
    required this.index,
    required this.revealed,
    required this.legMoment,
    required this.onFlip,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    final card = cards[index];
    final isRev = revealed[index];
    final last = index == cards.length - 1;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: isRev && legMoment ? 1.12 : 1.0,
          duration: Duration(milliseconds: legMoment ? 1100 : 300),
          curve: Curves.easeOutCubic,
          child: _FlipCard(
            key: ValueKey('flip_$index'),
            card: card,
            revealed: isRev,
            width: 210,
            onTap: isRev ? null : onFlip,
          ),
        ),
        const SizedBox(height: 20),
        // points de progression
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < cards.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3.5),
                width: i == index ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color:
                      revealed[i]
                          ? _rarityColor(cards[i].rarity)
                          : _Pal.cream.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow:
                      revealed[i]
                          ? [
                            BoxShadow(
                              color: _rarityColor(
                                cards[i].rarity,
                              ).withValues(alpha: 0.6),
                              blurRadius: 8,
                            ),
                          ]
                          : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 56,
          child: Center(
            child:
                isRev
                    ? _ArcadeButton(
                      label: last ? '🎉 VOIR LE RÉCAP' : 'SUIVANT ›',
                      width: 220,
                      onTap: onAdvance,
                    )
                    : Text(
                      'Appuie pour révéler ›',
                      style: _arcade(size: 16, color: _Pal.creamDim),
                    ),
          ),
        ),
      ],
    );
  }
}

// Carte avec flip 3D (dos → recto, pop d'échelle)
class _FlipCard extends StatefulWidget {
  final SavedCard card;
  final bool revealed;
  final double width;
  final VoidCallback? onTap;
  const _FlipCard({
    super.key,
    required this.card,
    required this.revealed,
    required this.width,
    this.onTap,
  });

  @override
  State<_FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<_FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
      value: widget.revealed ? 1 : 0,
    );
    if (widget.revealed) _ctrl.value = 1;
  }

  @override
  void didUpdateWidget(_FlipCard old) {
    super.didUpdateWidget(old);
    if (widget.revealed && !old.revealed) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final a = _ctrl.value * math.pi; // 0 → pi
        final showFront = a > math.pi / 2;
        // pop d'échelle 0.72 → 1.04 → 1
        final t = _ctrl.value;
        final scale =
            widget.revealed
                ? (t < 0.55
                    ? 0.72 + (1.04 - 0.72) * (t / 0.55)
                    : 1.04 - (1.04 - 1.0) * ((t - 0.55) / 0.45))
                : 1.0;
        return Transform.scale(
          scale: scale,
          child: Transform(
            alignment: Alignment.center,
            transform:
                Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(a),
            child:
                showFront
                    ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _ArcadeCard(
                        card: widget.card,
                        w: widget.width,
                        glow: true,
                        onTap: widget.onTap,
                      ),
                    )
                    : _ArcadeCard(
                      card: widget.card,
                      w: widget.width,
                      faceDown: true,
                      onTap: widget.onTap,
                    ),
          ),
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   RÉCAP
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _Recap extends StatelessWidget {
  final List<SavedCard> cards;
  final Rarity topRarity;
  final bool isSaving;
  final void Function(SavedCard) onInspect;
  final VoidCallback onDone;

  const _Recap({
    required this.cards,
    required this.topRarity,
    required this.isSaving,
    required this.onInspect,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('✨', style: TextStyle(fontSize: 30)),
          const SizedBox(height: 4),
          Text(
            '${cards.length} cartes obtenues !',
            maxLines: 1,
            style: _arcade(size: 26),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Meilleure carte : ',
                  style: TextStyle(color: _Pal.creamDim, fontSize: 13),
                ),
                TextSpan(
                  text: _rarityName(topRarity),
                  style: TextStyle(
                    color: _rarityColor(topRarity),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < cards.length; i++)
                _RiseIn(
                  delayMs: i * 100,
                  child: _ArcadeCard(
                    card: cards[i],
                    w: 96,
                    glow: true,
                    onTap: () => onInspect(cards[i]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '👆 APPUIE POUR INSPECTER',
            style: _pixel(size: 8.5, color: _Pal.creamFaint),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: 300,
            child:
                isSaving
                    ? const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: _Pal.gold,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                    : _ArcadeButton(
                      label: '↩  MA COLLECTION',
                      big: true,
                      onTap: onDone,
                    ),
          ),
        ],
      ),
    );
  }
}

// Apparition translate (sans fondu, comme demandé dans le handoff)
class _RiseIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _RiseIn({required this.child, required this.delayMs});
  @override
  State<_RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<_RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Transform.translate(
          offset: Offset(0, 14 * (1 - t)),
          child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
        );
      },
      child: widget.child,
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   APERÇU DU PACK (pour l'écran de personnalisation admin)
//   Reprend le sachet foil au repos, au nouveau style arcade.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class PackPreview extends StatefulWidget {
  final String title;
  final String subtitle;
  final Uint8List? imageBytes;
  final String? imageUrl;
  final Color color;
  final int cardCount;

  const PackPreview({
    super.key,
    required this.title,
    required this.subtitle,
    this.imageBytes,
    this.imageUrl,
    this.color = const Color(0xFF8A4DFF),
    this.cardCount = 3,
  });

  @override
  State<PackPreview> createState() => _PackPreviewState();
}

class _PackPreviewState extends State<PackPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const w = 220.0, h = 304.0;
    return AnimatedBuilder(
      animation: _idle,
      builder: (_, __) {
        final bob = math.sin(_idle.value * 2 * math.pi) * 8;
        return Transform.translate(
          offset: Offset(0, bob),
          child: SizedBox(
            width: w,
            height: h,
            child: _FoilFace(
              foil: _idle.value,
              showArt: true,
              crimp: true,
              packName: widget.title.trim().isEmpty ? 'Booster' : widget.title,
              packSubtitle: widget.subtitle,
              packImageBytes: widget.imageBytes,
              packImageUrl: widget.imageUrl,
              cardCount: widget.cardCount,
            ),
          ),
        );
      },
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   WIDGETS DE RENDU POUR L'INSPECTEUR 3D
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SavedCardFrontWidget extends StatelessWidget {
  final SavedCard card;
  final double width;
  final double height;

  const SavedCardFrontWidget({
    super.key,
    required this.card,
    this.width = 300,
    this.height = 420,
  });

  Color get _rarityColor {
    switch (card.rarity) {
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

  String get _rarityName {
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
    final rc = _rarityColor;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0D0D1C),
        border: Border.all(color: rc, width: 3),
        boxShadow: [
          BoxShadow(
            color: rc.withValues(alpha: 0.6),
            blurRadius: 28,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      rc.withValues(alpha: 0.18),
                      const Color(0xFF0D0D1C),
                    ],
                  ),
                ),
              ),
            ),
            if (card.imageBytes != null)
              Positioned(
                left: card.imageX * (width / 400),
                top: card.imageY * (height / 560),
                child: Transform.scale(
                  scale: card.imageScale,
                  alignment: Alignment.topLeft,
                  child: Image.memory(
                    card.imageBytes!,
                    width: width * 0.92,
                    fit: BoxFit.fitWidth,
                    cacheWidth: 800,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.92),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: rc.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: rc.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _rarityName.toUpperCase(),
                            style: TextStyle(
                              color: rc,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (card.effect != CardEffect.none)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              _effectName(card.effect),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 9,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (card.textZones.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...card.textZones.map(
                        (z) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            z.text,
                            style: TextStyle(
                              color: Color(z.color),
                              fontSize: (z.fontSize * 0.72).clamp(8.0, 16.0),
                              fontFamily: z.fontFamily,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.03),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.07),
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _effectName(CardEffect e) {
    switch (e) {
      case CardEffect.holographic:
        return '✨ Holographique';
      case CardEffect.shiny:
        return '⭐ Brillant';
      case CardEffect.negative:
        return '◑ Négatif';
      case CardEffect.none:
        return '';
    }
  }
}

class SavedCardBackWidget extends StatelessWidget {
  final SavedCard card;
  final double width;
  final double height;

  const SavedCardBackWidget({
    super.key,
    required this.card,
    this.width = 300,
    this.height = 420,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Color(card.backColor);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: bg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (card.backImageBytes != null)
              Positioned.fill(
                child: Image.memory(
                  card.backImageBytes!,
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.09),
                      ],
                      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            if (card.backImageBytes == null)
              Center(
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white.withValues(alpha: 0.25),
                  size: 72,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
