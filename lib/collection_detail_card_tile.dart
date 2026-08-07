// collection_detail_card_tile.dart
// ─────────────────────────────────────────────────────────────────────────
//   Extrait de collection_detail_screen.dart pour reduire sa taille.
//   `part of` : meme bibliotheque que le fichier parent, donc les helpers
//   prives partages (_bg, _arcade, _pal, _rn...) restent accessibles SANS
//   aucun renommage. Les imports vivent dans le fichier parent.
// ─────────────────────────────────────────────────────────────────────────

part of 'collection_detail_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//   TUILE CARTE — cadre arcade selon rareté
// ════════════════════════════════════════════════════════════════════════════

class _CardTile extends StatelessWidget {
  final SavedCard card;
  final bool revealed;
  final bool isAdmin;
  final VoidCallback? onDelete;
  // ✨ Polish : compteur de doublons + badge NEW + fusion GOLD
  final int copies;
  final bool isNew;
  final bool isGold;
  final VoidCallback? onFuse;
  const _CardTile({
    required this.card,
    required this.revealed,
    this.isAdmin = false,
    this.onDelete,
    this.copies = 1,
    this.isNew = false,
    this.isGold = false,
    this.onFuse,
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
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => CardInspectorScreen(
                  frontCard: SavedCardFrontWidget(
                    card: card,
                    width: 300,
                    height: 420,
                    // ✨ SavedCard ne connaît pas le statut GOLD : il vient
                    // de _goldIds, porté ici par la vignette.
                    isGold: isGold,
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
          // 🥇 Badge GOLD
          if (isGold)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFE89A), _gold, _goldDeep],
                  ),
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.7),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  'GOLD',
                  style: _pixel(size: 6.5, color: const Color(0xFF2A1C00)),
                ),
              ),
            ),
          // ✨ Badge NEW — cartes du dernier pack ouvert
          if (isNew && !isGold)
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
          // ⚡ Bouton FUSION — assez d'exemplaires pour passer GOLD
          if (!isGold &&
              !isAdmin &&
              onFuse != null &&
              copies >= (_goldCost[card.rarity] ?? 999))
            Positioned(
              bottom: 22,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onFuse,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_gold, _goldDeep],
                      ),
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.65),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Text(
                      '⚡ FUSION',
                      style: _pixel(size: 7, color: const Color(0xFF2A1C00)),
                    ),
                  ),
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
    final isLeg = card.rarity == Rarity.legendary || isGold;
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

              // ✨ Voile ambré réservé aux cartes GOLD.
              // Sans lui, une GOLD et une légendaire sont indiscernables :
              // les deux partagent déjà la bordure dorée (isLeg).
              if (isGold)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _gold.withValues(alpha: 0.34),
                            const Color(0xFFFFF1B8).withValues(alpha: 0.12),
                            _gold.withValues(alpha: 0.30),
                          ],
                        ),
                      ),
                    ),
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
