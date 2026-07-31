// pack_system.dart — timer lié à l'utilisateur + sync Supabase
//
// ✅ CORRECTIF (31/07) :
//   • _syncToSupabase : upsert CIBLÉ sur (collection_id, user_id).
//     Avant, l'upsert visait la clé primaire (id) qu'on ne fournissait pas
//     → PostgreSQL tentait un INSERT à chaque ouverture de pack, ce qui
//       déclenchait l'erreur « device_id violates not-null constraint »
//       et, une fois ce NOT NULL retiré, aurait créé des membres en double.
//   • Les erreurs ne sont plus avalées silencieusement : elles s'affichent
//     À L'ÉCRAN via reportError (la console est invisible sur téléphone).
//     Voir error_reporter.dart.
//   • _parseServerDate : Supabase renvoie « ...+00:00 » et non « ...Z ».
//     L'ancien test `endsWith('Z')` ajoutait un second marqueur de fuseau
//     → date invalide et synchro du minuteur en échec à chaque lancement.

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_reporter.dart';

class PackSystem {
  static const _defaultCooldown = 3;

  static String _uid() =>
      Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static String _key(String collectionId) =>
      'pack_timer_${_uid()}_$collectionId';

  // ── API publique ──────────────────────────────────────────────────────────

  static Future<bool> canOpenPack(String collectionId) async {
    final last = await _getTime(collectionId);
    if (last == null) return true;
    final cooldown = await _getCooldown(collectionId);
    return DateTime.now().toUtc().difference(last).inSeconds >= cooldown * 3600;
  }

  static Future<void> setLastOpenedTime(String collectionId) async {
    final now = DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(collectionId), now.millisecondsSinceEpoch);
    // On attend la sync pour s'assurer qu'elle est bien exécutée
    await _syncToSupabase(collectionId, now);
  }

  static Future<Duration> timeUntilNextPack(String collectionId) async {
    final last = await _getTime(collectionId);
    if (last == null) return Duration.zero;
    final cooldown = await _getCooldown(collectionId);
    final next = last.add(Duration(hours: cooldown));
    final diff = next.difference(DateTime.now().toUtc());
    return diff.isNegative ? Duration.zero : diff;
  }

  /// Appelé au lancement de l'app pour récupérer le timer depuis Supabase.
  static Future<void> syncFromSupabase(String collectionId) async {
    try {
      final uid = _uid();
      if (uid == 'anon') return;
      final res =
          await Supabase.instance.client
              .from('collection_members')
              .select('last_pack_opened')
              .eq('collection_id', collectionId)
              .eq('user_id', uid)
              .maybeSingle();
      if (res == null || res['last_pack_opened'] == null) return;

      final raw = res['last_pack_opened'] as String;
      final remote = _parseServerDate(raw);

      final local = await _getLocalTime(collectionId);
      final latest = (local != null && local.isAfter(remote)) ? local : remote;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(collectionId), latest.millisecondsSinceEpoch);
    } catch (e) {
      reportError('Synchronisation du minuteur de pack', e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Fuseau horaire déjà présent : « Z » ou un décalage « +02:00 » / « -0500 ».
  static final _hasTimeZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Convertit une date renvoyée par Supabase en DateTime UTC.
  ///
  /// ⚠️ PostgREST renvoie un décalage EXPLICITE (« 2026-05-24T12:56:14.181
  /// +00:00 »), pas un « Z » final. L'ancien code ne testait que le « Z » et
  /// ajoutait donc un second marqueur de fuseau → « ...+00:00Z », date
  /// invalide, et la synchro du minuteur échouait à CHAQUE lancement.
  static DateTime _parseServerDate(String raw) {
    final normalized = _hasTimeZone.hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  }

  static Future<DateTime?> _getTime(String collectionId) async {
    return _getLocalTime(collectionId);
  }

  static Future<DateTime?> _getLocalTime(String collectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_key(collectionId));
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  static Future<int> _getCooldown(String collectionId) async {
    try {
      final res =
          await Supabase.instance.client
              .from('collections')
              .select('pack_cooldown_hours')
              .eq('id', collectionId)
              .maybeSingle();
      return (res?['pack_cooldown_hours'] as int?) ?? _defaultCooldown;
    } catch (e) {
      // Repli sur 3h : sans signalement, un cooldown personnalisé ignoré
      // passait pour un bug de l'app.
      reportError('Lecture du délai entre packs', e);
      return _defaultCooldown;
    }
  }

  /// ✅ CORRIGÉ : l'upsert cible explicitement le couple (collection_id,
  /// user_id). Il met donc à jour la ligne de membre existante au lieu
  /// d'essayer d'en insérer une nouvelle.
  ///
  /// ⚠️ Nécessite la contrainte d'unicité créée par fix_device_id.sql :
  ///     collection_members_collection_user_unique (collection_id, user_id)
  static Future<void> _syncToSupabase(
    String collectionId,
    DateTime time,
  ) async {
    try {
      final uid = _uid();
      if (uid == 'anon') return;
      await Supabase.instance.client.from('collection_members').upsert({
        'collection_id': collectionId,
        'user_id': uid,
        'last_pack_opened': time.toUtc().toIso8601String(),
      }, onConflict: 'collection_id,user_id');
    } catch (e) {
      // Non enregistré côté serveur → le minuteur repartira à zéro sur un
      // autre appareil. À signaler, sans bloquer l'ouverture du pack.
      reportError('Enregistrement de l\'heure du pack', e);
    }
  }

  /// Formate une durée en "2h 34m" ou "Disponible !"
  static String formatDuration(Duration d) {
    if (d == Duration.zero) return 'Disponible !';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }
}
