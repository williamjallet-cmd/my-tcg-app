// streak_badge.dart
// Petit widget qui affiche la série actuelle du joueur (🔥 X jours).
// Se recharge tout seul à l'affichage. À placer par exemple en haut de
// l'onglet Pack ou sur l'écran profil.

import 'package:flutter/material.dart';
import 'streak_service.dart';

class StreakBadge extends StatefulWidget {
  /// Si true, affiche aussi le record ("record : X").
  final bool showBest;
  const StreakBadge({super.key, this.showBest = false});

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge> {
  int _streak = 0;
  int _best = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StreakService.currentStreak();
    final b = await StreakService.bestStreak();
    if (mounted) {
      setState(() {
        _streak = s;
        _best = b;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    // Éteint quand la série est à 0 (pas encore commencé / rompue).
    final active = _streak > 0;
    final flame = active ? '🔥' : '🌙';
    final label =
        active
            ? '$_streak jour${_streak > 1 ? 's' : ''} d\'affilée'
            : 'Ouvre un pack pour démarrer ta série';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              active
                  ? [
                    const Color(0xFFFF6B00).withValues(alpha: 0.25),
                    const Color(0xFFFFD33D).withValues(alpha: 0.12),
                  ]
                  : [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.white.withValues(alpha: 0.03),
                  ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              active
                  ? const Color(0xFFFF8A3D).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Text(flame, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.showBest && _best > 0)
                  Text(
                    'Record : $_best jour${_best > 1 ? 's' : ''}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
