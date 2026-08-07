// pack_opening_saved_card.dart
// ─────────────────────────────────────────────────────────────────────────
//   WIDGETS DE RENDU pour l'inspecteur 3D (recto / verso).
//
//   Extrait de pack_opening_screen.dart pour reduire sa taille.
//   `part of` : meme bibliotheque que le parent, donc les helpers prives
//   partages (_Pal, _arcade, _pixel, _rarityColor...) restent accessibles
//   SANS renommage. Les imports vivent dans le fichier parent.
// ─────────────────────────────────────────────────────────────────────────

part of 'pack_opening_screen.dart';


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   WIDGETS DE RENDU POUR L'INSPECTEUR 3D
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SavedCardFrontWidget extends StatelessWidget
    implements InspectableCardFace {
  final SavedCard card;
  final double width;
  final double height;

  /// ✨ Mode « plein cadre » : l'illustration occupe la totalité du cadre,
  /// exactement comme à la révélation du pack. Le nom et la rareté sont
  /// affichés HORS du cadre par CardInspectorScreen, qui les récupère seul
  /// via InspectableCardFace (getters `inspector*` plus bas).
  ///
  /// ⚠️ Par défaut à TRUE : ce widget ne sert QUE dans l'inspecteur 3D
  /// (ouverture de pack + détail de collection), et les deux doivent avoir
  /// le même rendu. Passer false pour retrouver l'ancien affichage.
  final bool fullBleed;

  /// ✨ Carte fusionnée en GOLD. L'info ne vient pas de SavedCard (qui ne la
  /// connaît pas) mais de l'écran appelant, qui lit `_goldIds`.
  final bool isGold;

  const SavedCardFrontWidget({
    super.key,
    required this.card,
    this.width = 300,
    this.height = 420,
    this.fullBleed = true,
    this.isGold = false,
  });

  // ── InspectableCardFace ────────────────────────────────────────────────
  // Permet à l'inspecteur d'afficher rareté + nom hors du cadre sans que
  // l'écran appelant ait quoi que ce soit à transmettre.

  @override
  String? get inspectorName => card.name;

  @override
  String? get inspectorRarityLabel => isGold ? 'Gold' : _rarityName;

  /// Palette arcade (celle de la révélation de pack) pour que la pastille
  /// soit identique d'un écran à l'autre.
  @override
  Color? get inspectorRarityColor =>
      isGold ? _goldAccent : _rarityColor(card.rarity);

  static const _goldAccent = Color(0xFFFFC83D);

  /// Couleur de la BORDURE et du halo du cadre.
  /// ⚠️ Renommé (ex-`_rarityColor`) : le nom masquait la fonction globale
  /// `_rarityColor(Rarity)` de la palette arcade, utilisée ci-dessus.
  Color get _frameColor {
    if (isGold) return _goldAccent;
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
    final rc = _frameColor;

    // ✨ PLEIN CADRE — l'illustration remplit tout le cadre.
    // Les cartes sont composées au ratio 400×560 (= 1.4), soit celui du
    // cadre 300×420 : BoxFit.cover ne rogne donc quasiment rien.
    if (fullBleed) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF0D0D1C),
          border: Border.all(color: rc, width: isGold ? 4 : 3),
          boxShadow: [
            BoxShadow(
              color: rc.withValues(alpha: isGold ? 0.75 : 0.6),
              blurRadius: isGold ? 34 : 28,
              spreadRadius: isGold ? 6 : 4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Fond — visible seulement si l'illustration manque
              DecoratedBox(
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
              if (card.imageBytes != null)
                Image.memory(
                  card.imageBytes!,
                  fit: BoxFit.cover,
                  cacheWidth: 900,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),

              // ✨ Voile ambré GOLD — même traitement que la vignette de la
              // grille, pour que la carte reste reconnaissable une fois
              // agrandie.
              if (isGold)
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _goldAccent.withValues(alpha: 0.34),
                          const Color(0xFFFFF1B8).withValues(alpha: 0.12),
                          _goldAccent.withValues(alpha: 0.30),
                        ],
                      ),
                    ),
                  ),
                ),

              // Reflet diagonal — c'est lui qui donne le relief quand on
              // incline la carte en 3D.
              IgnorePointer(
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
            ],
          ),
        ),
      );
    }

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
