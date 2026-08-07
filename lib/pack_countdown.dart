// pack_countdown.dart
// ─────────────────────────────────────────────────────────────────────────
//   DÉCOMPTE ISOLÉ DU PROCHAIN PACK
//
//   ⚠️ POURQUOI CE FICHIER EXISTE
//   Avant, le décompte vivait dans l'état de CollectionDetailScreen et de
//   _CollectionCard, avec un `setState` toutes les secondes. Conséquence :
//   TOUT l'écran se reconstruisait chaque seconde — bandeau, jauges, et
//   surtout la grille de cartes et ses Image.memory — pendant l'intégralité
//   du cooldown, c'est-à-dire la quasi-totalité du temps passé sur l'écran.
//
//   Ici, le `setState` par seconde est confiné à CE widget. Seul le texte du
//   décompte se redessine ; le reste de l'écran ne bouge plus.
//
//   Le parent garde la main via une GlobalKey<PackCountdownState> :
//     _key.currentState?.refresh()   après l'ouverture d'un pack.
// ─────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';

import 'pack_system.dart';

class PackCountdown extends StatefulWidget {
  final String collectionId;

  /// Durée du cooldown, déjà connue de l'appelant via CollectionModel.
  /// Évite deux requêtes réseau à chaque rafraîchissement du décompte.
  final int cooldownHours;

  /// Reconstruit à chaque seconde — garde-le le plus petit possible.
  final Widget Function(BuildContext context, Duration remaining, bool canOpen)
  builder;

  /// Appelé une seule fois, au moment où le décompte atteint zéro.
  /// Sert au parent à rafraîchir ce qui dépend de la disponibilité du pack
  /// (halo de la vignette, etc.) sans avoir à ticker lui-même.
  final VoidCallback? onReady;

  const PackCountdown({
    super.key,
    required this.collectionId,
    required this.cooldownHours,
    required this.builder,
    this.onReady,
  });

  @override
  State<PackCountdown> createState() => PackCountdownState();
}

class PackCountdownState extends State<PackCountdown> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _canOpen = false;

  Duration get remaining => _remaining;
  bool get canOpen => _canOpen;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void didUpdateWidget(PackCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collectionId != widget.collectionId) refresh();
  }

  /// Relit l'état réel depuis PackSystem et relance le décompte si besoin.
  /// À appeler après l'ouverture d'un pack ou une synchro serveur.
  Future<void> refresh() async {
    final r = await PackSystem.timeUntilNextPack(
      widget.collectionId,
      cooldownHours: widget.cooldownHours,
    );
    final c = await PackSystem.canOpenPack(
      widget.collectionId,
      cooldownHours: widget.cooldownHours,
    );
    if (!mounted) return;
    setState(() {
      _remaining = r;
      _canOpen = c;
    });
    _timer?.cancel();
    if (!c) _startTicking();
  }

  void _startTicking() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      final next = _remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _timer?.cancel();
        setState(() {
          _remaining = Duration.zero;
          _canOpen = true;
        });
        widget.onReady?.call();
      } else {
        setState(() => _remaining = next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _remaining, _canOpen);
}
