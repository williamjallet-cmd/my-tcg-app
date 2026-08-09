// skeleton.dart
// ─────────────────────────────────────────────────────────────────────────
//   SILHOUETTES DE CHARGEMENT
//
//   Pourquoi remplacer la roue qui tourne :
//   une roue au centre d'un écran vide ne dit rien de ce qui arrive, et la
//   page « saute » brutalement quand le contenu apparaît. Une silhouette
//   qui reprend la FORME du contenu à venir occupe déjà la bonne place :
//   l'arrivée des vraies données ne déplace plus rien, et l'attente paraît
//   plus courte parce qu'on voit la page se construire.
//
//   Un seul Shimmer anime tout un écran : une animation par silhouette
//   multiplierait les contrôleurs pour un résultat identique.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Balaie ses enfants d'un reflet clair, en boucle.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, child) {
      // Le reflet traverse l'écran de gauche à droite ; les bornes sortent
      // du cadre pour qu'il entre et sorte proprement.
      final t = _c.value * 2 - 1;
      return ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback:
            (bounds) => LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: const [
                Color(0x00FFFFFF),
                Color(0x1AFFFFFF),
                Color(0x00FFFFFF),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// Bloc gris arrondi : la brique de base des silhouettes.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Silhouette d'une vignette de collection (écran d'accueil).
class CollectionTileSkeleton extends StatelessWidget {
  const CollectionTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    height: 168,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SkeletonBox(width: 150, height: 20),
            const Spacer(),
            const SkeletonBox(width: 54, height: 20, radius: 10),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: const [
            Expanded(child: SkeletonBox(height: 48, radius: 12)),
            SizedBox(width: 12),
            SkeletonBox(width: 104, height: 48, radius: 12),
          ],
        ),
        const Spacer(),
        const SkeletonBox(height: 10, radius: 5),
      ],
    ),
  );
}

/// Silhouette d'une carte dans la grille du dex.
class CardTileSkeleton extends StatelessWidget {
  const CardTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
  );
}

/// Grille de silhouettes de cartes, aux mêmes proportions que la vraie.
class CardGridSkeleton extends StatelessWidget {
  final int count;
  const CardGridSkeleton({super.key, this.count = 9});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: GridView.builder(
      padding: const EdgeInsets.all(14),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.7,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const CardTileSkeleton(),
    ),
  );
}

/// Liste de silhouettes de vignettes de collection.
class CollectionListSkeleton extends StatelessWidget {
  final int count;
  const CollectionListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) => Shimmer(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: List.generate(count, (_) => const CollectionTileSkeleton()),
      ),
    ),
  );
}
