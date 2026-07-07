// collection_service.dart — ajout de la personnalisation du pack
//   (pack_title, pack_subtitle, pack_image_url) + uploadPackImage
//
// ✅ OPTIMISATIONS (audit juillet 2026) :
//   • getMemberCount : comptage CÔTÉ SERVEUR (plus aucune ligne téléchargée)
//   • saveUserCards  : requêtes GROUPÉES (2 allers-retours au lieu de 2 par carte)
//   • Fin des erreurs silencieuses : chaque catch loggue via debugPrint
//     → les erreurs RLS/réseau apparaissent enfin dans la console !
//   • Signatures et comportements INCHANGÉS pour tous les appelants.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'card_storage.dart';

class CollectionModel {
  final String id;
  final String name;
  final String description;
  final String code;
  final String ownerUserId;
  final DateTime createdAt;
  final String? imageUrl;
  final int packCooldownHours;
  final bool membersCanAddCards;

  // ── Personnalisation du pack ──────────────────────────────────────────────
  final String? packTitle;
  final String? packSubtitle;
  final String? packImageUrl;

  const CollectionModel({
    required this.id,
    required this.name,
    required this.description,
    required this.code,
    required this.ownerUserId,
    required this.createdAt,
    this.imageUrl,
    this.packCooldownHours = 3,
    this.membersCanAddCards = true,
    this.packTitle,
    this.packSubtitle,
    this.packImageUrl,
  });

  factory CollectionModel.fromMap(Map<String, dynamic> m) => CollectionModel(
    id: m['id'] as String,
    name: m['name'] as String,
    description: (m['description'] as String?) ?? '',
    code: m['code'] as String,
    ownerUserId:
        (m['owner_user_id'] as String?) ??
        (m['owner_device_id'] as String?) ??
        '',
    createdAt: DateTime.parse(m['created_at'] as String),
    imageUrl: m['image_url'] as String?,
    packCooldownHours: (m['pack_cooldown_hours'] as int?) ?? 3,
    membersCanAddCards: (m['members_can_add_cards'] as bool?) ?? true,
    packTitle: m['pack_title'] as String?,
    packSubtitle: m['pack_subtitle'] as String?,
    packImageUrl: m['pack_image_url'] as String?,
  );

  bool isOwnedBy(String userId) => ownerUserId == userId;
  String get inviteLink => 'tcgapp://join?code=$code';

  String get cooldownLabel {
    switch (packCooldownHours) {
      case 1:
        return '1h';
      case 2:
        return '2h';
      case 3:
        return '3h';
      case 6:
        return '6h';
      case 12:
        return '12h';
      case 24:
        return '24h';
      default:
        return '${packCooldownHours}h';
    }
  }
}

class UserCardEntry {
  final String id;
  final String cardId;
  final String cardName;
  final String cardRarity;
  final int quantity;
  final DateTime obtainedAt;
  final Map<String, dynamic>? cardData;

  const UserCardEntry({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.cardRarity,
    required this.quantity,
    required this.obtainedAt,
    this.cardData,
  });

  factory UserCardEntry.fromMap(Map<String, dynamic> m) => UserCardEntry(
    id: m['id'] as String,
    cardId: m['card_id'] as String,
    cardName: m['card_name'] as String,
    cardRarity: m['card_rarity'] as String,
    quantity: (m['quantity'] as int?) ?? 1,
    obtainedAt: DateTime.parse(m['obtained_at'] as String),
    cardData:
        m['card_data'] != null
            ? (m['card_data'] as Map<String, dynamic>)
            : null,
  );

  bool get isDuplicate => quantity > 1;

  SavedCard? toSavedCard() {
    if (cardData == null) return null;
    try {
      return CardStorage.fromJson(cardData!);
    } catch (e) {
      debugPrint('⚠️ UserCardEntry.toSavedCard ($cardName) : $e');
      return null;
    }
  }
}

/// ✨ NOUVEAU : entrée du catalogue partagé (collection_cards),
/// avec card_data léger pour reconstruire la carte chez chaque membre.
class CatalogCardEntry {
  final String cardId;
  final String cardName;
  final String cardRarity;
  final Map<String, dynamic>? cardData;

  const CatalogCardEntry({
    required this.cardId,
    required this.cardName,
    required this.cardRarity,
    this.cardData,
  });

  factory CatalogCardEntry.fromMap(Map<String, dynamic> m) => CatalogCardEntry(
    cardId: m['card_id'] as String,
    cardName: (m['card_name'] as String?) ?? '',
    cardRarity: (m['card_rarity'] as String?) ?? '',
    cardData:
        m['card_data'] != null
            ? (m['card_data'] as Map<String, dynamic>)
            : null,
  );

  SavedCard? toSavedCard() {
    if (cardData == null) return null;
    try {
      return CardStorage.fromJson(cardData!);
    } catch (e) {
      debugPrint('⚠️ CatalogCardEntry.toSavedCard ($cardName) : $e');
      return null;
    }
  }
}

class CollectionService {
  CollectionService._();
  static final instance = CollectionService._();
  static final _db = Supabase.instance.client;

  String get _uid => _db.auth.currentUser!.id;
  String get userId => _uid;

  Future<String?> uploadCoverImage(Uint8List bytes, String collectionId) async {
    try {
      final path = 'covers/$collectionId.jpg';
      await _db.storage
          .from('collections')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      return _db.storage.from('collections').getPublicUrl(path);
    } catch (e) {
      debugPrint('⚠️ uploadCoverImage : $e');
      return null;
    }
  }

  // Upload de l'image centrale du pack (réservé au proprio via updateCollection)
  Future<String?> uploadPackImage(Uint8List bytes, String collectionId) async {
    try {
      final path = 'packs/$collectionId.jpg';
      await _db.storage
          .from('collections')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      return _db.storage.from('collections').getPublicUrl(path);
    } catch (e) {
      debugPrint('⚠️ uploadPackImage : $e');
      return null;
    }
  }

  Future<CollectionModel> createCollection({
    required String name,
    String description = '',
    String? imageUrl,
    Uint8List? imageBytes,
    int packCooldownHours = 3,
    bool membersCanAddCards = true,
  }) async {
    final code = _generateCode();
    final res =
        await _db
            .from('collections')
            .insert({
              'name': name,
              'description': description,
              'code': code,
              'owner_user_id': _uid,
              'owner_device_id': _uid,
              'image_url': imageUrl,
              'pack_cooldown_hours': packCooldownHours,
              'members_can_add_cards': membersCanAddCards,
            })
            .select()
            .single();

    final collection = CollectionModel.fromMap(res);
    if (imageBytes != null) {
      final url = await uploadCoverImage(imageBytes, collection.id);
      if (url != null) {
        await _db
            .from('collections')
            .update({'image_url': url})
            .eq('id', collection.id);
      }
    }
    await _joinAsMember(collection.id);
    return collection;
  }

  // Modification de la collection par le propriétaire
  // (couverture, cooldown, permissions, ET personnalisation du pack)
  Future<CollectionModel> updateCollection({
    required String collectionId,
    Uint8List? imageBytes,
    int? packCooldownHours,
    bool? membersCanAddCards,
    String? packTitle,
    String? packSubtitle,
    Uint8List? packImageBytes,
  }) async {
    final updates = <String, dynamic>{};
    if (packCooldownHours != null) {
      updates['pack_cooldown_hours'] = packCooldownHours;
    }
    if (membersCanAddCards != null) {
      updates['members_can_add_cards'] = membersCanAddCards;
    }
    if (packTitle != null) {
      updates['pack_title'] = packTitle;
    }
    if (packSubtitle != null) {
      updates['pack_subtitle'] = packSubtitle;
    }

    if (imageBytes != null) {
      final url = await uploadCoverImage(imageBytes, collectionId);
      if (url != null) {
        final cacheBusted = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
        updates['image_url'] = cacheBusted;
      }
    }

    if (packImageBytes != null) {
      final url = await uploadPackImage(packImageBytes, collectionId);
      if (url != null) {
        final cacheBusted = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
        updates['pack_image_url'] = cacheBusted;
      }
    }

    if (updates.isEmpty) {
      final res =
          await _db
              .from('collections')
              .select()
              .eq('id', collectionId)
              .single();
      return CollectionModel.fromMap(res);
    }

    // On filtre seulement par id : certaines anciennes collections n'ont pas
    // owner_user_id renseigné (uniquement owner_device_id), ce qui faisait
    // échouer la mise à jour (PGRST116 = 0 ligne trouvée).
    await _db.from('collections').update(updates).eq('id', collectionId);

    final res =
        await _db.from('collections').select().eq('id', collectionId).single();
    return CollectionModel.fromMap(res);
  }

  Future<CollectionModel> joinByCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.length != 6) throw Exception('Le code doit faire 6 caractères.');
    final res =
        await _db.from('collections').select().eq('code', code).maybeSingle();
    if (res == null) throw Exception('Aucune collection trouvée.');
    final collection = CollectionModel.fromMap(res);
    final existing =
        await _db
            .from('collection_members')
            .select('id')
            .eq('collection_id', collection.id)
            .eq('user_id', _uid)
            .maybeSingle();
    if (existing != null) throw Exception('Vous êtes déjà membre.');
    await _joinAsMember(collection.id);
    return collection;
  }

  Future<CollectionModel> joinByLink(String link) async {
    final code = Uri.tryParse(link)?.queryParameters['code'];
    if (code == null || code.isEmpty) throw Exception('Lien invalide.');
    return joinByCode(code);
  }

  Future<List<CollectionModel>> getMyCollections() async {
    final res = await _db
        .from('collection_members')
        .select('collections(*)')
        .eq('user_id', _uid);
    return (res as List)
        .where((row) => row['collections'] != null)
        .map(
          (row) => CollectionModel.fromMap(
            row['collections'] as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> leaveCollection(String collectionId) async {
    await _db
        .from('collection_members')
        .delete()
        .eq('collection_id', collectionId)
        .eq('user_id', _uid);
  }

  Future<void> deleteCollection(String collectionId) async {
    await _db
        .from('collection_members')
        .delete()
        .eq('collection_id', collectionId);
    await _db
        .from('collections')
        .delete()
        .eq('id', collectionId)
        .eq('owner_user_id', _uid);
  }

  /// ✅ OPTIMISÉ : comptage effectué par PostgreSQL côté serveur.
  /// Avant : toutes les lignes étaient téléchargées puis comptées côté client.
  Future<int> getMemberCount(String collectionId) async {
    try {
      return await _db
          .from('collection_members')
          .count(CountOption.exact)
          .eq('collection_id', collectionId);
    } catch (e) {
      debugPrint('⚠️ getMemberCount : $e');
      return 0;
    }
  }

  /// ✨ MIGRATION STORAGE : si [card] est fournie, le catalogue transporte
  /// aussi un card_data LÉGER (chemins Storage, pas de base64) → toutes les
  /// cartes deviennent visibles et tirables par TOUS les membres.
  Future<void> addCardToCollection(
    String collectionId,
    String cardId,
    String cardName,
    String cardRarity, [
    SavedCard? card,
  ]) async {
    await _db.from('collection_cards').upsert({
      'collection_id': collectionId,
      'card_id': cardId,
      'card_name': cardName,
      'card_rarity': cardRarity,
      'added_by': _uid,
      if (card != null) 'card_data': CardStorage.toJson(card),
    });
  }

  /// ✨ NOUVEAU : catalogue complet de la collection (avec card_data léger).
  Future<List<CatalogCardEntry>> getCollectionCards(String collectionId) async {
    try {
      final res = await _db
          .from('collection_cards')
          .select('card_id, card_name, card_rarity, card_data')
          .eq('collection_id', collectionId);
      return (res as List)
          .map((r) => CatalogCardEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('⚠️ getCollectionCards : $e');
      return [];
    }
  }

  Future<List<String>> getCollectionCardIds(String collectionId) async {
    try {
      final res = await _db
          .from('collection_cards')
          .select('card_id')
          .eq('collection_id', collectionId);
      return (res as List).map((r) => r['card_id'] as String).toList();
    } catch (e) {
      debugPrint('⚠️ getCollectionCardIds : $e');
      return [];
    }
  }

  Future<void> removeCardFromCollection(
    String collectionId,
    String cardId,
  ) async {
    await _db
        .from('collection_cards')
        .delete()
        .eq('collection_id', collectionId)
        .eq('card_id', cardId);
  }

  /// True si l'utilisateur courant est admin de cette collection
  /// (propriétaire OU membre avec le rôle 'admin').
  Future<bool> amIAdminOf(String collectionId, String ownerUserId) async {
    if (ownerUserId == _uid) return true;
    try {
      final res =
          await _db
              .from('collection_members')
              .select('role')
              .eq('collection_id', collectionId)
              .eq('user_id', _uid)
              .maybeSingle();
      return res != null && res['role'] == 'admin';
    } catch (e) {
      debugPrint('⚠️ amIAdminOf : $e');
      return false;
    }
  }

  /// ✅ OPTIMISÉ : requêtes groupées.
  /// Avant : 2 requêtes PAR carte (select + insert/update), en séquence.
  ///   → un pack de 3 cartes = jusqu'à 6 allers-retours réseau.
  /// Maintenant :
  ///   1 requête pour connaître les cartes déjà possédées,
  ///   1 requête d'insertion GROUPÉE pour toutes les nouvelles cartes,
  ///   + 1 update par doublon uniquement (cas rare).
  /// Le résultat en base est strictement identique à l'ancienne version.
  Future<void> saveUserCards(String collectionId, List<SavedCard> cards) async {
    if (cards.isEmpty) return;
    try {
      // Nombre d'exemplaires de chaque carte dans ce lot (doublons de pack)
      final counts = <String, int>{};
      final byId = <String, SavedCard>{};
      for (final card in cards) {
        counts[card.id] = (counts[card.id] ?? 0) + 1;
        byId[card.id] = card;
      }

      // 1 seule requête : lesquelles possède-t-on déjà ?
      final existingRows = await _db
          .from('user_collection_cards')
          .select('id, card_id, quantity')
          .eq('collection_id', collectionId)
          .eq('user_id', _uid)
          .inFilter('card_id', counts.keys.toList());

      final existingByCard = <String, Map<String, dynamic>>{
        for (final r in (existingRows as List))
          r['card_id'] as String: Map<String, dynamic>.from(r as Map),
      };

      final toInsert = <Map<String, dynamic>>[];
      final nowIso = DateTime.now().toUtc().toIso8601String();

      for (final entry in counts.entries) {
        final cardId = entry.key;
        final n = entry.value;
        final existing = existingByCard[cardId];

        if (existing == null) {
          // Nouvelle carte → ajoutée au lot d'insertion groupée
          final card = byId[cardId]!;
          toInsert.add({
            'collection_id': collectionId,
            'user_id': _uid,
            'card_id': card.id,
            'card_name': card.name,
            'card_rarity': card.rarity.name,
            'card_data': CardStorage.toJson(card),
            'quantity': n,
            'obtained_at': nowIso,
          });
        } else {
          // Carte déjà possédée → on incrémente la quantité
          try {
            final currentQty = (existing['quantity'] as int?) ?? 1;
            await _db
                .from('user_collection_cards')
                .update({'quantity': currentQty + n})
                .eq('id', existing['id'] as String);
          } catch (e) {
            debugPrint('⚠️ saveUserCards (update ${byId[cardId]?.name}) : $e');
          }
        }
      }

      // 1 seule requête d'insertion pour toutes les nouvelles cartes
      if (toInsert.isNotEmpty) {
        await _db.from('user_collection_cards').insert(toInsert);
      }
    } catch (e) {
      debugPrint('⚠️ saveUserCards : $e');
    }
  }

  Future<List<UserCardEntry>> loadUserCards(String collectionId) async {
    try {
      final res = await _db
          .from('user_collection_cards')
          .select()
          .eq('collection_id', collectionId)
          .eq('user_id', _uid)
          .order('obtained_at', ascending: false);
      return (res as List).map((row) => UserCardEntry.fromMap(row)).toList();
    } catch (e) {
      debugPrint('⚠️ loadUserCards : $e');
      return [];
    }
  }

  Future<List<SavedCard>> loadUserSavedCards(String collectionId) async {
    final entries = await loadUserCards(collectionId);
    return entries.map((e) => e.toSavedCard()).whereType<SavedCard>().toList();
  }

  Future<void> _joinAsMember(String collectionId) async {
    await _db.from('collection_members').insert({
      'collection_id': collectionId,
      'user_id': _uid,
      'device_id': _uid,
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}
