// daily_reward_service.dart
// ════════════════════════════════════════════════════════════════════════════
//  RÉCOMPENSE QUOTIDIENNE « À RÉCLAMER »
//    • 1 carte gratuite par jour
//    • 7 jours d'affilée  →  un BOOSTER (3 cartes) au lieu d'une seule
//
//  L'état (jour de dernière réclamation + série) est stocké en LOCAL par
//  utilisateur, exactement comme StreakService — instantané, pas de réseau.
//  Les cartes obtenues, elles, passent par PackOpeningScreen →
//  CollectionService.saveUserCards : la synchro Supabase reste INCHANGÉE.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'card_model.dart';
import 'card_storage.dart';
import 'collection_service.dart';

// ── Résultats exposés à l'UI ────────────────────────────────────────────────

class DailyRewardStatus {
  final bool canClaim; // réclamable aujourd'hui ?
  final int streak; // série effective actuelle (0 si rompue / jamais)
  final int bestStreak; // record
  final int nextStreak; // série après réclamation d'aujourd'hui
  final int nextCardCount; // 1, ou 3 si nextStreak tombe sur un multiple de 7
  final Duration untilReset; // temps avant que la réclamation redevienne dispo

  const DailyRewardStatus({
    required this.canClaim,
    required this.streak,
    required this.bestStreak,
    required this.nextStreak,
    required this.nextCardCount,
    required this.untilReset,
  });

  bool get nextIsBooster => nextCardCount > 1;
}

class DailyClaimResult {
  final int streak;
  final int cardCount;
  const DailyClaimResult({required this.streak, required this.cardCount});
  bool get isBooster => cardCount > 1;
}

// ── Service ─────────────────────────────────────────────────────────────────

class DailyRewardService {
  DailyRewardService._();
  static final DailyRewardService instance = DailyRewardService._();

  static const int milestoneEvery = 7; // tous les 7 jours → booster
  static const int boosterCards = 3; // taille du booster bonus

  String _uid() => Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  String _lastKey() => 'daily_last_day_${_uid()}';
  String _streakKey() => 'daily_streak_${_uid()}';
  String _bestKey() => 'daily_best_${_uid()}';

  // Numéro de jour local (sans l'heure) pour comparer hier / aujourd'hui.
  int _dayNumber(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  Duration _untilMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 1));
    return tomorrow.difference(now);
  }

  /// État courant de la récompense (sans rien modifier).
  Future<DailyRewardStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastKey());
    final stored = prefs.getInt(_streakKey()) ?? 0;
    final best = prefs.getInt(_bestKey()) ?? 0;
    final today = _dayNumber(DateTime.now());

    // Série effective : rompue si on a sauté un jour complet.
    int effective;
    if (last == null) {
      effective = 0;
    } else if (today == last) {
      effective = stored; // déjà réclamé aujourd'hui
    } else if (today - last == 1) {
      effective = stored; // hier → on peut prolonger
    } else {
      effective = 0; // trou → série rompue
    }

    final canClaim = last == null || today > last;
    final nextStreak =
        canClaim
            ? ((last != null && today - last == 1) ? stored + 1 : 1)
            : stored;
    final nextCardCount = (nextStreak % milestoneEvery == 0) ? boosterCards : 1;

    return DailyRewardStatus(
      canClaim: canClaim,
      streak: effective,
      bestStreak: best,
      nextStreak: nextStreak,
      nextCardCount: nextCardCount,
      untilReset: canClaim ? Duration.zero : _untilMidnight(),
    );
  }

  /// Valide la réclamation du jour (avance la série + mémorise le jour).
  /// À n'appeler QU'UNE fois les cartes effectivement tirées.
  Future<DailyClaimResult> commitClaim() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_lastKey());
    final stored = prefs.getInt(_streakKey()) ?? 0;
    final today = _dayNumber(DateTime.now());

    // Sécurité : si déjà réclamé aujourd'hui, on ne double pas la série.
    final newStreak =
        (last == today)
            ? (stored == 0 ? 1 : stored)
            : ((last != null && today - last == 1) ? stored + 1 : 1);

    await prefs.setInt(_lastKey(), today);
    await prefs.setInt(_streakKey(), newStreak);
    final best = prefs.getInt(_bestKey()) ?? 0;
    if (newStreak > best) await prefs.setInt(_bestKey(), newStreak);

    final cardCount = (newStreak % milestoneEvery == 0) ? boosterCards : 1;
    return DailyClaimResult(streak: newStreak, cardCount: cardCount);
  }

  // ── Tirage des cartes gratuites ───────────────────────────────────────────
  //  Réplique compacte de la logique de collection_detail_screen (taux + pick),
  //  pour rester 100 % autonome et NE PAS toucher au gros fichier.

  static const Map<Rarity, int> _dropRates = {
    Rarity.common: 50,
    Rarity.uncommon: 28,
    Rarity.rare: 14,
    Rarity.epic: 6,
    Rarity.legendary: 2,
  };

  String _obtKey(String colId) => 'obtained_${_uid()}_$colId';
  String _catKey(String colId) => 'local_cat_${_uid()}_$colId';

  // Catalogue d'une collection — même source que l'écran détail
  // (clé locale `local_cat_` ∪ table Supabase `collection_cards`).
  Future<List<SavedCard>> _catalogue(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await CardStorage.loadCards();
    final ids = <String>{...(prefs.getStringList(_catKey(collectionId)) ?? [])};
    try {
      ids.addAll(
        await CollectionService.instance.getCollectionCardIds(collectionId),
      );
    } catch (_) {}
    return all.where((c) => ids.contains(c.id)).toList();
  }

  /// Parmi les collections fournies, celles qui ont au moins une carte
  /// (donc dans lesquelles on peut tirer une récompense).
  Future<List<CollectionModel>> claimableCollections(
    List<CollectionModel> collections,
  ) async {
    final out = <CollectionModel>[];
    for (final c in collections) {
      final cat = await _catalogue(c.id);
      if (cat.isNotEmpty) out.add(c);
    }
    return out;
  }

  SavedCard _weightedPick(List<SavedCard> pool, math.Random rng) {
    final byR = <Rarity, List<SavedCard>>{};
    for (final c in pool) {
      byR.putIfAbsent(c.rarity, () => []).add(c);
    }
    final total = byR.keys.fold<int>(0, (s, r) => s + (_dropRates[r] ?? 0));
    if (total == 0) return pool[rng.nextInt(pool.length)];
    var roll = rng.nextInt(total);
    for (final r in Rarity.values) {
      if (!byR.containsKey(r)) continue;
      roll -= _dropRates[r]!;
      if (roll < 0) {
        final p = byR[r]!;
        return p[rng.nextInt(p.length)];
      }
    }
    return pool[rng.nextInt(pool.length)];
  }

  /// Tire `count` cartes pondérées dans `collectionId`, les marque obtenues
  /// localement (comme l'ouverture de pack), et renvoie la liste à révéler.
  /// La synchro Supabase est assurée ensuite par PackOpeningScreen.
  Future<List<SavedCard>> drawCards(String collectionId, int count) async {
    final pool = await _catalogue(collectionId);
    if (pool.isEmpty) return [];
    final rng = math.Random();
    final drawn = List.generate(count, (_) => _weightedPick(pool, rng));

    final prefs = await SharedPreferences.getInstance();
    final key = _obtKey(collectionId);
    final existing = prefs.getStringList(key) ?? [];
    await prefs.setStringList(
      key,
      {...existing, ...drawn.map((c) => c.id)}.toList(),
    );
    return drawn;
  }
}
