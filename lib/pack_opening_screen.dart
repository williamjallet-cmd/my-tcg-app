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

// ✂️ Fichier decoupe : voir l'en-tete de chaque part.
part 'pack_opening_ceremony.dart';
part 'pack_opening_cards.dart';
part 'pack_opening_saved_card.dart';

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

  /// ✨ Faux quand l'appelant a DÉJÀ enregistré les cartes sur le serveur
  /// avant d'ouvrir cet écran — ce qui est le bon ordre : rien ne doit être
  /// consommé (cooldown, série, réclamation quotidienne) tant que la
  /// sauvegarde n'est pas confirmée.
  ///
  /// Laissé à true par défaut : un futur appelant qui oublierait le
  /// paramètre garde un comportement sûr, avec sauvegarde en fin d'écran.
  final bool saveCards;

  const PackOpeningScreen({
    super.key,
    required this.cards,
    required this.collectionId,
    this.packName = 'Booster',
    this.packColor = const Color(0xFF8A4DFF),
    this.packImageBytes,
    this.packImageUrl,
    this.packSubtitle = 'Pack surprise',
    this.saveCards = true,
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
    // Cartes déjà enregistrées par l'appelant → rien à faire ici.
    if (!widget.saveCards) {
      Navigator.pop(context);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await CollectionService.instance.saveUserCards(
        widget.collectionId,
        widget.cards,
      );
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
      }
    } catch (e) {
      // ⚠️ On NE quitte PAS l'écran : sortir ici ferait disparaître les
      // cartes du pack définitivement. Le joueur peut réessayer.
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Tes cartes n\'ont pas pu être enregistrées.\n'
              '${e.toString().replaceFirst('Exception: ', '')}',
              style: _arcade(size: 14, color: Colors.white),
            ),
            backgroundColor: const Color(0xFFFF5D73),
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'RÉESSAYER',
              textColor: Colors.white,
              onPressed: _saveAndReturn,
            ),
          ),
        );
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
                  onInspect: () => _inspect(_cards[_index]),
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

          // Overlay de suspense avant la dernière carte (voile sombre sobre)
          if (_suspense)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
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
