// dev_tools.dart
// ─────────────────────────────────────────────────────────────────────────
//   PANNEAU DE TEST — visible UNIQUEMENT hors build release.
//
//   Objectif : pouvoir tester immédiatement l'ouverture de pack, l'animation
//   de révélation, la fusion GOLD et les jauges du dex, sans attendre le
//   cooldown ni accumuler des doublons pendant des semaines.
//
//   ⚠️ SÉCURITÉ : tout est verrouillé derrière `DevTools.enabled`, qui vaut
//   false en build release (`flutter build apk --release`). Le bouton
//   n'apparaît donc jamais pour tes amis — même s'il reste dans le code.
//   En debug (`flutter run`) et en profile (`flutter run --profile`), il est
//   actif : ce sont tes deux modes de test.
//
//   ⚠️ Ces actions écrivent DIRECTEMENT dans Supabase et affectent ton compte
//   sur la collection ouverte. Elles ne touchent jamais aux autres membres.
// ─────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_service.dart';
import 'pack_system.dart';

class DevTools {
  DevTools._();

  /// Faux en build release → le panneau disparaît complètement.
  static bool get enabled => !kReleaseMode;

  static SupabaseClient get _db => Supabase.instance.client;
  static String? get _uid => _db.auth.currentUser?.id;

  // ── 1. Débloquer l'ouverture de pack ────────────────────────────────────
  /// Efface le timer local ET la date serveur. Les deux sont nécessaires :
  /// PackSystem prend la plus RÉCENTE des deux au démarrage, donc effacer
  /// seulement l'une des deux ne débloque rien.
  static Future<void> resetPackTimer(String collectionId) async {
    await PackSystem.clearTimer(collectionId);
    final uid = _uid;
    if (uid == null) return;
    await _db
        .from('collection_members')
        .update({'last_pack_opened': null})
        .eq('collection_id', collectionId)
        .eq('user_id', uid);
  }

  // ── 2. Remplir le dex ───────────────────────────────────────────────────
  /// Ajoute toutes les cartes du catalogue à ta collection, en [quantity]
  /// exemplaires. Utile pour voir la jauge de dex pleine et tester la fusion
  /// sur toutes les raretés d'un coup.
  /// Retourne le nombre de cartes traitées.
  static Future<int> grantWholeCatalogue(
    String collectionId, {
    int quantity = 12,
  }) async {
    final uid = _uid;
    if (uid == null) return 0;

    final catalogue = await CollectionService.instance.getCollectionCards(
      collectionId,
    );
    if (catalogue.isEmpty) return 0;

    final ownedRows = await _db
        .from('user_collection_cards')
        .select('card_id')
        .eq('collection_id', collectionId)
        .eq('user_id', uid);
    final ownedIds = {
      for (final r in (ownedRows as List)) r['card_id'] as String,
    };

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final toInsert = <Map<String, dynamic>>[];

    for (final c in catalogue) {
      if (ownedIds.contains(c.cardId)) continue;
      // Une entrée sans card_data est orpheline : l'insérer créerait une
      // carte fantôme qui gonflerait le dex sans rien afficher.
      if (c.cardData == null) continue;
      toInsert.add({
        'collection_id': collectionId,
        'user_id': uid,
        'card_id': c.cardId,
        'card_name': c.cardName,
        'card_rarity': c.cardRarity,
        'card_data': c.cardData,
        'quantity': quantity,
        'obtained_at': nowIso,
      });
    }

    if (toInsert.isNotEmpty) {
      await _db.from('user_collection_cards').insert(toInsert);
    }

    // Les cartes déjà possédées : on remonte simplement leur quantité
    await setAllQuantities(collectionId, quantity);
    return catalogue.length;
  }

  // ── 3. Forcer la quantité (test de la fusion GOLD) ──────────────────────
  /// Met TOUTES tes cartes de cette collection à [quantity] exemplaires.
  /// Avec 12, tous les seuils de fusion sont franchis (12/9/6/4/3).
  static Future<void> setAllQuantities(
    String collectionId,
    int quantity,
  ) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .from('user_collection_cards')
        .update({'quantity': quantity})
        .eq('collection_id', collectionId)
        .eq('user_id', uid);
  }

  // ── 4. Annuler les fusions ──────────────────────────────────────────────
  /// Repasse toutes tes cartes GOLD en cartes normales, pour rejouer
  /// l'animation de fusion autant de fois que voulu.
  static Future<void> clearGold(String collectionId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .from('user_collection_cards')
        .update({'is_gold': false})
        .eq('collection_id', collectionId)
        .eq('user_id', uid);
  }

  // ── 5. Repartir de zéro ─────────────────────────────────────────────────
  /// Supprime TOUTES tes cartes de cette collection : dex vide, badges NEW
  /// réarmés. Ne touche ni au catalogue ni aux cartes des autres membres.
  static Future<void> wipeMyCards(String collectionId) async {
    final uid = _uid;
    if (uid == null) return;
    await _db
        .from('user_collection_cards')
        .delete()
        .eq('collection_id', collectionId)
        .eq('user_id', uid);

    // Caches locaux : sans ça l'écran réafficherait les cartes supprimées
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().toList()) {
      if (k.contains(collectionId)) await prefs.remove(k);
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
//   PANNEAU (feuille du bas)
// ═════════════════════════════════════════════════════════════════════════

class DevPanel extends StatefulWidget {
  final String collectionId;

  /// Appelé après chaque action pour recharger l'écran appelant.
  final Future<void> Function() onChanged;

  const DevPanel({
    super.key,
    required this.collectionId,
    required this.onChanged,
  });

  /// Ouvre le panneau. Ne fait rien en build release.
  static Future<void> show(
    BuildContext context, {
    required String collectionId,
    required Future<void> Function() onChanged,
  }) {
    if (!DevTools.enabled) return Future.value();
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1430),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder:
          (_) =>
              DevPanel(collectionId: collectionId, onChanged: onChanged),
    );
  }

  @override
  State<DevPanel> createState() => _DevPanelState();
}

class _DevPanelState extends State<DevPanel> {
  static const _gold = Color(0xFFFFC83D);
  static const _cream = Color(0xFFF6EEDD);
  static const _coral = Color(0xFFFF5D73);
  static const _teal = Color(0xFF21E6C1);
  static const _line = Color(0xFF3A3050);

  bool _busy = false;
  String? _status;

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
      await widget.onChanged();
      if (mounted) setState(() => _status = '✅ $label');
    } catch (e) {
      if (mounted) setState(() => _status = '❌ $label : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _action({
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _busy ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: _cream.withValues(alpha: 0.6),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.collectionId;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: _line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text('🛠️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'OUTILS DE TEST',
                  style: TextStyle(
                    color: _cream,
                    fontSize: 13,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Invisible en build release. N\'affecte que ton compte '
              'sur cette collection.',
              style: TextStyle(
                color: _cream.withValues(alpha: 0.45),
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            _action(
              title: '⏱️  Débloquer l\'ouverture de pack',
              subtitle:
                  'Efface le timer local ET la date serveur. Le pack '
                  'redevient ouvrable tout de suite.',
              color: _teal,
              onTap:
                  () => _run(
                    'Pack débloqué',
                    () => DevTools.resetPackTimer(id),
                  ),
            ),
            _action(
              title: '📖  Obtenir tout le catalogue (×12)',
              subtitle:
                  'Remplit le dex à 100 % et met chaque carte à 12 '
                  'exemplaires : tous les seuils de fusion sont franchis.',
              color: _gold,
              onTap:
                  () => _run(
                    'Catalogue obtenu',
                    () => DevTools.grantWholeCatalogue(id, quantity: 12),
                  ),
            ),
            _action(
              title: '🔢  Mettre mes cartes à 12 exemplaires',
              subtitle:
                  'Sans rien ajouter au dex : fait apparaître le bouton '
                  'FUSION sur les cartes que tu possèdes déjà.',
              color: _gold,
              onTap:
                  () => _run(
                    'Quantités à 12',
                    () => DevTools.setAllQuantities(id, 12),
                  ),
            ),
            _action(
              title: '↩️  Annuler toutes mes fusions GOLD',
              subtitle:
                  'Repasse tes cartes dorées en cartes normales pour '
                  'rejouer la fusion.',
              color: _cream,
              onTap: () => _run('Fusions annulées', () => DevTools.clearGold(id)),
            ),
            _action(
              title: '🗑️  Vider ma collection',
              subtitle:
                  'Supprime toutes MES cartes : dex vide, badges NEW '
                  'réarmés. Le catalogue et les autres membres ne bougent pas.',
              color: _coral,
              onTap:
                  () => _run('Collection vidée', () => DevTools.wipeMyCards(id)),
            ),

            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: _status!.startsWith('✅') ? _teal : _coral,
                    fontSize: 12.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}