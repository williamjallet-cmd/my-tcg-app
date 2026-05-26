// pack_system.dart — timer lié à l'utilisateur + sync Supabase
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    // FIX : on attend la sync pour s'assurer qu'elle est bien exécutée
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
      final remote = DateTime.parse(raw.endsWith('Z') ? raw : '${raw}Z');

      final local = await _getLocalTime(collectionId);
      final latest = (local != null && local.isAfter(remote)) ? local : remote;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(collectionId), latest.millisecondsSinceEpoch);
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
    } catch (_) {
      return _defaultCooldown;
    }
  }

  // FIX : déclaré Future<void> au lieu de void pour pouvoir être attendu
  // FIX : upsert() au lieu de update() → crée la ligne si elle n'existe pas
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
      });
    } catch (_) {}
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
