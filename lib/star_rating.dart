// star_rating.dart — étoiles à granularité 0.5 (0.5 → 5) pour la notation
// des collections communautaires. Cohérent avec le design system Arcade.
// Astuce : Icons.star_half_rounded gère nativement le palier 0.5, donc
// aucun CustomPainter n'est nécessaire.

import 'package:flutter/material.dart';
import 'arcade_theme.dart';

IconData _starIconFor(double filled) {
  if (filled >= 1.0) return Icons.star_rounded;
  if (filled >= 0.5) return Icons.star_half_rounded;
  return Icons.star_border_rounded;
}

/// Affichage en lecture seule d'une note moyenne (0.0 à 5.0, pas de 0.5).
class StarRatingDisplay extends StatelessWidget {
  final double rating; // 0.0 - 5.0
  final int? ratingsCount;
  final double size;
  final Color color;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.ratingsCount,
    this.size = 16,
    this.color = Arcade.gold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(5, (i) {
          final filled = (rating - i).clamp(0.0, 1.0);
          return Icon(_starIconFor(filled), size: size, color: color);
        }),
        if (ratingsCount != null) ...[
          const SizedBox(width: 6),
          Text(
            ratingsCount! > 0
                ? '${rating.toStringAsFixed(1)} ($ratingsCount)'
                : 'Pas encore noté',
            style: Arcade.body(size: 12, color: Arcade.creamDim),
          ),
        ],
      ],
    );
  }
}

/// Sélecteur interactif : taper ou glisser sur la ligne d'étoiles.
/// [onChanged] renvoie une valeur entre 0.5 et 5.0 (pas de 0.5).
class StarRatingInput extends StatefulWidget {
  final double initialRating; // 0 = pas encore noté
  final ValueChanged<double> onChanged;
  final double size;

  const StarRatingInput({
    super.key,
    this.initialRating = 0,
    required this.onChanged,
    this.size = 34,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late double _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
  }

  void _updateFromLocalX(double dx, double totalWidth) {
    final raw = (dx / totalWidth) * 5;
    final halfSteps = (raw * 2).round().clamp(1, 10);
    final value = halfSteps / 2.0;
    if (value != _rating) {
      setState(() => _rating = value);
      widget.onChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = widget.size * 5;
    return GestureDetector(
      onTapDown: (d) => _updateFromLocalX(d.localPosition.dx, totalWidth),
      onHorizontalDragUpdate:
          (d) => _updateFromLocalX(d.localPosition.dx, totalWidth),
      child: SizedBox(
        width: totalWidth,
        height: widget.size,
        child: Row(
          children: List.generate(5, (i) {
            final filled = (_rating - i).clamp(0.0, 1.0);
            return Icon(
              _starIconFor(filled),
              size: widget.size,
              color: Arcade.gold,
            );
          }),
        ),
      ),
    );
  }
}
