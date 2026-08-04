// daily_reward_card.dart
// ════════════════════════════════════════════════════════════════════════════
//  BANDEAU « RÉCOMPENSE DU JOUR » — à placer sur la page de détail d'une
//  collection, à côté du bouton « Ouvrir le pack ». Un tirage par jour ET
//  par collection.
//  • Affiche la série (frise de 7 jours, le 7ᵉ = booster 📦)
//  • Bouton RÉCLAMER quand c'est disponible, sinon un compte à rebours
//  • À la réclamation : tire la/les carte(s) puis ouvre PackOpeningScreen
//    (révélation + persistance Supabase identiques à un vrai pack).
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';

import 'arcade_theme.dart';
import 'collection_service.dart';
import 'daily_reward_service.dart';
import 'pack_opening_screen.dart';

class DailyRewardBanner extends StatefulWidget {
  /// Collection dans laquelle la carte du jour sera tirée.
  final CollectionModel collection;

  /// Appelé après une réclamation réussie (ex. pour rafraîchir l'écran).
  final VoidCallback? onClaimed;

  const DailyRewardBanner({
    super.key,
    required this.collection,
    this.onClaimed,
  });

  @override
  State<DailyRewardBanner> createState() => _DailyRewardBannerState();
}

class _DailyRewardBannerState extends State<DailyRewardBanner> {
  DailyRewardStatus? _status;
  Duration _remaining = Duration.zero;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final st = await DailyRewardService.instance.status(widget.collection.id);
    if (!mounted) return;
    setState(() {
      _status = st;
      _remaining = st.untilReset;
    });
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_status?.canClaim ?? true) return; // rien à décompter
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      final next = _remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _timer?.cancel();
        _load(); // minuit passé → la récompense redevient dispo
      } else {
        setState(() => _remaining = next);
      }
    });
  }

  // ── Réclamation ─────────────────────────────────────────────────────────

  Future<void> _claim() async {
    final st = _status;
    if (_busy || st == null || !st.canClaim) return;
    setState(() => _busy = true);
    try {
      final drawn = await DailyRewardService.instance.drawCards(
        widget.collection.id,
        st.nextCardCount,
      );
      if (!mounted) return;
      if (drawn.isEmpty) {
        _snack(
          'Ajoute des cartes à cette collection pour réclamer ta carte du jour.',
        );
        setState(() => _busy = false);
        return;
      }

      // ✅ CORRECTIF : on enregistre AVANT de consommer la réclamation.
      // Avant, commitClaim brûlait la récompense du jour et la série, puis
      // la sauvegarde arrivait à la fin de l'écran d'ouverture : si elle
      // échouait, le joueur perdait sa carte ET sa journée.
      // Maintenant, un échec laisse la réclamation intacte : il réessaie.
      await CollectionService.instance.saveUserCards(
        widget.collection.id,
        drawn,
      );

      final result = await DailyRewardService.instance.commitClaim(
        widget.collection.id,
      );
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => PackOpeningScreen(
                cards: drawn,
                collectionId: widget.collection.id,
                // Déjà enregistré ci-dessus.
                saveCards: false,
                packName: result.isBooster ? 'BOOSTER BONUS' : 'CARTE DU JOUR',
                packSubtitle:
                    result.isBooster
                        ? '7 jours d\'affilée !'
                        : 'Récompense quotidienne',
                packColor: Arcade.gold,
              ),
        ),
      );

      widget.onClaimed?.call();
      await _load();
    } catch (e) {
      if (mounted) _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: Arcade.body(color: Colors.white)),
        backgroundColor: Arcade.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  String _fmt(Duration d) {
    if (d <= Duration.zero) return 'Disponible !';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    if (st == null) {
      return const SizedBox(height: 96); // placeholder pendant le chargement
    }
    final ready = st.canClaim;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Arcade.rCard),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              ready
                  ? [
                    Arcade.gold.withValues(alpha: 0.22),
                    Arcade.coral.withValues(alpha: 0.10),
                  ]
                  : [
                    Arcade.cream.withValues(alpha: 0.05),
                    Arcade.cream.withValues(alpha: 0.03),
                  ],
        ),
        border: Border.all(
          color: ready ? Arcade.gold.withValues(alpha: 0.55) : Arcade.line,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (ready ? Arcade.gold : Arcade.creamFaint).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  ready ? '🎁' : '🌙',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RÉCOMPENSE DU JOUR',
                      style: Arcade.pixel(
                        size: 9,
                        color: ready ? Arcade.gold : Arcade.creamFaint,
                        spacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ready
                          ? (st.nextIsBooster
                              ? 'Booster bonus débloqué ! 📦'
                              : 'Ta carte gratuite t\'attend')
                          : 'Réclamée · revient dans ${_fmt(_remaining)}',
                      style: Arcade.body(
                        size: 13.5,
                        color: ready ? Arcade.cream : Arcade.creamDim,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (st.streak > 0) ...[
                const SizedBox(width: 8),
                PixelBadge(label: '🔥 ${st.streak}', color: Arcade.coral),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _streakStrip(st.streak),
          const SizedBox(height: 12),
          if (ready)
            ArcadeButton(
              label: _busy ? 'PATIENTE…' : 'RÉCLAMER',
              icon: Icons.redeem_rounded,
              width: double.infinity,
              onTap: _busy ? null : _claim,
            )
          else
            Center(
              child: Text(
                _fmt(_remaining),
                style: Arcade.title(size: 22, color: Arcade.teal),
              ),
            ),
        ],
      ),
    );
  }

  // Frise de 7 jours ; le 7ᵉ jour affiche l'icône booster.
  Widget _streakStrip(int streak) {
    final pos = streak == 0 ? 0 : ((streak - 1) % 7) + 1;
    return Row(
      children: List.generate(7, (i) {
        final filled = i < pos;
        final isBoosterDot = i == 6;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 6 ? 6 : 0),
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  filled ? Arcade.gold.withValues(alpha: 0.9) : Arcade.surface,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: filled ? Arcade.gold : Arcade.line,
                width: 1.5,
              ),
            ),
            child:
                isBoosterDot
                    ? Icon(
                      Icons.inventory_2_rounded,
                      size: 13,
                      color: filled ? const Color(0xFF2A1C00) : Arcade.gold,
                    )
                    : Text(
                      '${i + 1}',
                      style: Arcade.pixel(
                        size: 8.5,
                        color:
                            filled
                                ? const Color(0xFF2A1C00)
                                : Arcade.creamFaint,
                      ),
                    ),
          ),
        );
      }),
    );
  }
}
