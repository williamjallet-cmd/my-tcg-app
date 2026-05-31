// streak_service.dart
// Gère la "série" (streak) GLOBALE du joueur : nombre de jours consécutifs
// durant lesquels il a ouvert au moins un pack (toutes collections confondues).
//
// Règles :
//   - Ouvrir un pack aujourd'hui alors que le dernier était HIER  → streak +1
//   - Ouvrir un pack alors que le dernier était AUJOURD'HUI        → inchangé
//   - Ouvrir un pack après avoir sauté un ou plusieurs jours        → streak = 1
//
// Stockage local (SharedPreferences), par utilisateur. Pas de dépendance
// Supabase : c'est instantané et suffisant pour un compteur de motivation.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StreakService {
  static String _uid() =>
      Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static String _countKey() => 'streak_count_${_uid()}';
  static String _lastKey() => 'streak_last_day_${_uid()}';
  static String _bestKey() => 'streak_best_${_uid()}';

  // Convertit une date en numéro de jour (sans l'heure) pour comparer
  // facilement "hier / aujourd'hui / avant".
  static int _dayNumber(DateTime d) {
    final local = d.toLocal();
    return DateTime(
          local.year,
          local.month,
          local.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  /// Série actuelle (jours consécutifs). 0 si jamais ouvert.
  static Future<int> currentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_countKey()) ?? 0;
    if (count == 0) return 0;
    final last = prefs.getInt(_lastKey());
    if (last == null) return 0;
    final today = _dayNumber(DateTime.now());
    // Si plus d'un jour s'est écoulé depuis la dernière ouverture, la série
    // est rompue (on renvoie 0 sans encore l'écrire — ce sera remis à jour
    // à la prochaine ouverture).
    if (today - last > 1) return 0;
    return count;
  }

  /// Meilleure série atteinte.
  static Future<int> bestStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_bestKey()) ?? 0;
  }

  /// À appeler à CHAQUE ouverture de pack. Met à jour la série et renvoie
  /// le résultat (nouvelle valeur + si elle a augmenté aujourd'hui).
  static Future<StreakResult> registerPackOpened() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dayNumber(DateTime.now());
    final last = prefs.getInt(_lastKey());
    final current = prefs.getInt(_countKey()) ?? 0;

    int newCount;
    bool increased;

    if (last == null) {
      newCount = 1;
      increased = true;
    } else if (last == today) {
      // Déjà ouvert aujourd'hui : la série ne bouge pas.
      newCount = current == 0 ? 1 : current;
      increased = false;
    } else if (today - last == 1) {
      // Hier → aujourd'hui : on prolonge.
      newCount = current + 1;
      increased = true;
    } else {
      // Trou d'au moins un jour : on repart à 1.
      newCount = 1;
      increased = true;
    }

    await prefs.setInt(_countKey(), newCount);
    await prefs.setInt(_lastKey(), today);

    final best = prefs.getInt(_bestKey()) ?? 0;
    if (newCount > best) {
      await prefs.setInt(_bestKey(), newCount);
    }

    return StreakResult(streak: newCount, increasedToday: increased);
  }
}

class StreakResult {
  final int streak;
  final bool increasedToday;
  const StreakResult({required this.streak, required this.increasedToday});
}
