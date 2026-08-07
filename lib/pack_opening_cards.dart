// pack_opening_cards.dart
// ─────────────────────────────────────────────────────────────────────────
//   CARTE ARCADE, REVELATION carte par carte et flip 3D.
//
//   Extrait de pack_opening_screen.dart pour reduire sa taille.
//   `part of` : meme bibliotheque que le parent, donc les helpers prives
//   partages (_Pal, _arcade, _pixel, _rarityColor...) restent accessibles
//   SANS renommage. Les imports vivent dans le fichier parent.
// ─────────────────────────────────────────────────────────────────────────

part of 'pack_opening_screen.dart';


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

  /// Badge de rareté en pied de carte. Désactivé lors de la révélation :
  /// le bandeau de rareté au-dessus de la carte le remplace.
  final bool showRarity;

  /// ✨ Nom de la carte en en-tête. Désactivé lors de la révélation :
  /// le nom est affiché HORS du cadre, sous le bandeau de rareté.
  /// Quand showName ET showRarity sont false, l'illustration occupe
  /// la totalité du cadre (mode « plein cadre »).
  final bool showName;

  const _ArcadeCard({
    required this.card,
    required this.w,
    this.faceDown = false,
    this.glow = false,
    this.onTap,
    this.showRarity = true,
    this.showName = true,
  });

  /// Mode « plein cadre » : l'illustration remplit tout l'intérieur du cadre,
  /// sans en-tête ni pied. BoxFit.cover garantit qu'aucune bande vide
  /// n'apparaît (les cartes sont dessinées au ratio 400×560 = 1.4, soit
  /// exactement celui du cadre : le rognage est inférieur à 1 %).
  Widget _fullBleedArt(Color rc) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fond dégradé — visible uniquement si l'illustration manque
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.5),
              radius: 1.0,
              colors: [
                Color.lerp(rc, const Color(0xFF1B1430), 0.62)!,
                const Color(0xFF140F22),
              ],
            ),
          ),
        ),
        // Halo de rareté — DERRIÈRE l'illustration pour ne pas la ternir
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.62,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [rc.withValues(alpha: 0.5), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Illustration plein cadre
        if (card.imageBytes != null)
          Image.memory(
            card.imageBytes!,
            fit: BoxFit.cover,
            cacheWidth: 900,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
      ],
    );
  }

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
            // ✨ Ni nom ni rareté → l'illustration occupe tout le cadre
            child:
                (!showName && !showRarity)
                    ? _fullBleedArt(rc)
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // header : nom (masqué pendant la révélation)
                        if (showName)
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
                            padding: EdgeInsets.symmetric(
                              horizontal: w * 0.045,
                            ),
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
                                          (_, __, ___) =>
                                              const SizedBox.shrink(),
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
                        // footer : badge rareté (masqué pendant la révélation)
                        if (showRarity)
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
  // ✨ Tap sur la carte révélée → inspection 3D
  final VoidCallback onInspect;

  const _RevealCarte({
    required this.cards,
    required this.index,
    required this.revealed,
    required this.legMoment,
    required this.onFlip,
    required this.onAdvance,
    required this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    final card = cards[index];
    final isRev = revealed[index];
    final last = index == cards.length - 1;
    final rc = _rarityColor(card.rarity);

    // ✨ La carte s'adapte à la hauteur réellement disponible : le bloc
    // rareté + nom ajouté au-dessus ne peut donc jamais provoquer d'overflow
    // sur les écrans courts.
    return LayoutBuilder(
      builder: (context, cons) {
        const chromeH = 240.0; // rareté + nom + points + bouton + légende
        final availH = cons.maxHeight - chromeH;
        final cardW = math.max(
          120.0,
          math.min(210.0, math.min(cons.maxWidth * 0.60, availH / 1.4)),
        );

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // ① Bandeau de rareté — remonté, hors du cadre.
            // Hauteur fixe : la carte ne bouge pas quand le badge apparaît.
            SizedBox(
              height: 44,
              child: Center(
                child: AnimatedOpacity(
                  opacity: isRev ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: _RarityBanner(rarity: card.rarity),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // ② ✨ NOM DE LA CARTE — hors du cadre, sous la rareté.
            // FittedBox : les noms longs sont réduits au lieu d'être coupés.
            SizedBox(
              height: 40,
              child: Center(
                child: AnimatedOpacity(
                  opacity: isRev ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        card.name,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: _arcade(
                          size: 28,
                          spacing: 0.8,
                          shadows: [
                            Shadow(
                              blurRadius: 18,
                              color: rc.withValues(alpha: 0.55),
                            ),
                            const Shadow(
                              offset: Offset(0, 2),
                              color: Color(0x8C000000),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ③ La carte — illustration plein cadre
            AnimatedScale(
              scale: isRev && legMoment ? 1.12 : 1.0,
              duration: Duration(milliseconds: legMoment ? 1100 : 300),
              curve: Curves.easeOutCubic,
              child: _FlipCard(
                key: ValueKey('flip_$index'),
                card: card,
                revealed: isRev,
                width: cardW,
                onTap: isRev ? onInspect : onFlip,
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
            const SizedBox(height: 10),
            Opacity(
              opacity: isRev ? 1.0 : 0.0,
              child: Text(
                '👆 TOUCHE LA CARTE POUR L\'INSPECTER EN 3D',
                style: _pixel(size: 8, color: _Pal.creamDim),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Bandeau de rareté affiché au-dessus de la carte révélée
class _RarityBanner extends StatelessWidget {
  final Rarity rarity;
  const _RarityBanner({required this.rarity});

  @override
  Widget build(BuildContext context) {
    final rc = _rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
      decoration: BoxDecoration(
        color: rc.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: rc, width: 2),
        boxShadow: [
          BoxShadow(
            color: rc.withValues(alpha: 0.45),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        _rarityName(rarity).toUpperCase(),
        style: _pixel(size: 11, color: rc, spacing: 2, weight: FontWeight.w700),
      ),
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
                        // Rareté ET nom sont affichés au-dessus, hors du
                        // cadre → l'illustration occupe tout le cadre.
                        showRarity: false,
                        showName: false,
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
