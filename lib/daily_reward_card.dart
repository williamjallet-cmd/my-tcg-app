// daily_reward_card.dart
// ════════════════════════════════════════════════════════════════════════════
//  BANDEAU « RÉCOMPENSE DU JOUR » — à placer en haut de l'écran Collections.
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
  /// Collections de l'utilisateur (pour savoir où tirer la carte).
  final List<CollectionModel> collections;

  /// Appelé après une réclamation réussie (ex. pour rafraîchir la liste).
  final VoidCallback? onClaimed;

  const DailyRewardBanner({
    super.key,
    required this.collections,
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
    final st = await DailyRewardService.instance.status();
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
      final claimable = await DailyRewardService.instance.claimableCollections(
        widget.collections,
      );
      if (!mounted) return;
      if (claimable.isEmpty) {
        _snack(
          'Ajoute des cartes à une collection pour réclamer ta carte du jour.',
        );
        setState(() => _busy = false);
        return;
      }

      final picked =
          claimable.length == 1
              ? claimable.first
              : await _pickCollection(claimable);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return; // annulé
      }
      final chosen = picked;

      final drawn = await DailyRewardService.instance.drawCards(
        chosen.id,
        st.nextCardCount,
      );
      if (!mounted) return;
      if (drawn.isEmpty) {
        _snack('Cette collection n\'a pas encore de cartes.');
        setState(() => _busy = false);
        return;
      }

      final result = await DailyRewardService.instance.commitClaim();
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => PackOpeningScreen(
                cards: drawn,
                collectionId: chosen.id,
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

  Future<CollectionModel?> _pickCollection(List<CollectionModel> cols) {
    return showModalBottomSheet<CollectionModel>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            decoration: BoxDecoration(
              color: Arcade.bg,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(color: Arcade.line, width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Arcade.creamFaint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Carte du jour pour…', style: Arcade.title(size: 18)),
                const SizedBox(height: 6),
                Text(
                  'Choisis la collection à compléter',
                  style: Arcade.body(color: Arcade.creamDim, size: 13),
                ),
                const SizedBox(height: 16),
                ...cols.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context, c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Arcade.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Arcade.line, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              color: Arcade.gold,
                              size: 18,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.name,
                                style: Arcade.body(
                                  size: 15,
                                  weight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Arcade.creamFaint,
                            ),
                          ],
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
