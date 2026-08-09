// press_effect.dart
// ─────────────────────────────────────────────────────────────────────────
//   RETOUR TACTILE — l'élément « s'enfonce » sous le doigt.
//
//   Pourquoi : sans réaction au toucher, une interface paraît morte et on
//   doute d'avoir vraiment appuyé — surtout quand l'action qui suit prend
//   un aller-retour réseau. Un léger enfoncement + une vibration courte
//   confirment le geste INSTANTANÉMENT, avant même que l'action ne parte.
//
//   Volontairement sobre : 4 % de réduction, 110 ms. Au-delà, l'effet
//   devient un gadget qui ralentit l'usage.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ouverture d'écran « qui grandit » : la nouvelle page apparaît en montant
/// légèrement en échelle, plutôt que de glisser depuis la droite.
///
/// Utilisé pour l'inspecteur 3D : on a l'impression que la carte touchée
/// s'agrandit, sans les contraintes d'un Hero — deux onglets affichent les
/// mêmes cartes en même temps (Cartes et Admin), et deux Hero partageant
/// une étiquette font planter Flutter.
Route<T> growRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 260),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, __, ___) => page,
  transitionsBuilder: (_, anim, __, child) {
    final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
        child: child,
      ),
    );
  },
);

/// Apparition en fondu montant, décalée selon la position dans une grille.
///
/// Sans elle, la grille de cartes surgit d'un bloc à chaque chargement, ce
/// qui donne une impression de saccade. Le décalage est plafonné : au-delà
/// d'une dizaine d'éléments, attendre son tour deviendrait pénible.
class FadeInItem extends StatelessWidget {
  final Widget child;
  final int index;

  const FadeInItem({super.key, required this.child, required this.index});

  @override
  Widget build(BuildContext context) {
    final delayMs = (index.clamp(0, 11)) * 35;
    return TweenAnimationBuilder<double>(
      // La clé fait rejouer l'animation quand l'élément change réellement,
      // pas à chaque reconstruction.
      key: ValueKey(index),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 260 + delayMs),
      curve: Interval(
        delayMs / (260 + delayMs),
        1.0,
        curve: Curves.easeOutCubic,
      ),
      builder:
          (_, t, c) => Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - t)),
              child: c,
            ),
          ),
      child: child,
    );
  }
}

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Échelle atteinte pendant l'appui.
  final double pressedScale;

  /// Vibration légère au toucher. À désactiver pour les éléments appuyés
  /// en rafale, où la répétition devient désagréable.
  final bool haptic;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    // Élément inactif : aucun effet, sinon on promet une action qui
    // n'arrivera pas.
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _set(true);
        if (widget.haptic) HapticFeedback.selectionClick();
      },
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        // Descente rapide, remontée un peu plus souple : c'est ce décalage
        // qui donne la sensation de matière plutôt que de simple zoom.
        duration: Duration(milliseconds: _down ? 90 : 160),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
