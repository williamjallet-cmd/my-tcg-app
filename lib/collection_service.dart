// collection_service.dart
// FIXES : saveUserCards + loadUserCards + UserCardEntry avec quantity (doublons)

import 'dart:math';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'card_storage.dart'; // SavedCard

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  MODÈLES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

// FIX : modèle pour une carte possédée par un utilisateur (avec doublons)
class UserCardEntry {
  final String id;
  final String cardId;
  final String cardName;
  final String cardRarity;
  final int quantity; // nombre d'exemplaires (doublons inclus)
  final DateTime obtainedAt;
  final Map<String, dynamic>?
  cardData; // données complètes pour reconstruire SavedCard

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

  // Reconstruit un SavedCard depuis les données persistées
  SavedCard? toSavedCard() {
    if (cardData == null) return null;
    try {
      return CardStorage.fromJson(cardData!);
    } catch (_) {
      return null;
    }
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//  SERVICE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class CollectionService {
  CollectionService._();
  static final instance = CollectionService._();

  static final _db = Supabase.instance.client;

  String get _uid => _db.auth.currentUser!.id;
  String get userId => _uid;

  // ── Upload image de couverture ─────────────────────────────────────────────
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
      return null;
    }
  }

  // ── Créer ──────────────────────────────────────────────────────────────────
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

  // ── Rejoindre via code ────────────────────────────────────────────────────
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

  // ── Mes collections ───────────────────────────────────────────────────────
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

  // ── Quitter ───────────────────────────────────────────────────────────────
  Future<void> leaveCollection(String collectionId) async {
    await _db
        .from('collection_members')
        .delete()
        .eq('collection_id', collectionId)
        .eq('user_id', _uid);
  }

  // ── Supprimer (propriétaire) ──────────────────────────────────────────────
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

  Future<int> getMemberCount(String collectionId) async {
    final res = await _db
        .from('collection_members')
        .select('id')
        .eq('collection_id', collectionId);
    return (res as List).length;
  }

  // ── Cartes de la collection (catalogue partagé) ───────────────────────────
  Future<void> addCardToCollection(
    String collectionId,
    String cardId,
    String cardName,
    String cardRarity,
  ) async {
    await _db.from('collection_cards').upsert({
      'collection_id': collectionId,
      'card_id': cardId,
      'card_name': cardName,
      'card_rarity': cardRarity,
      'added_by': _uid,
    });
  }

  Future<List<String>> getCollectionCardIds(String collectionId) async {
    try {
      final res = await _db
          .from('collection_cards')
          .select('card_id')
          .eq('collection_id', collectionId);
      return (res as List).map((r) => r['card_id'] as String).toList();
    } catch (_) {
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

  // ── Cartes possédées par l'utilisateur (FIX persistance + doublons) ────────

  /// Sauvegarde les cartes reçues après ouverture d'un pack.
  /// Incrémente `quantity` si la carte est déjà possédée (doublon).
  Future<void> saveUserCards(String collectionId, List<SavedCard> cards) async {
    for (final card in cards) {
      try {
        final existing =
            await _db
                .from('user_collection_cards')
                .select('id, quantity')
                .eq('collection_id', collectionId)
                .eq('user_id', _uid)
                .eq('card_id', card.id)
                .maybeSingle();

        if (existing != null) {
          // FIX doublon : on incrémente quantity
          final currentQty = (existing['quantity'] as int?) ?? 1;
          await _db
              .from('user_collection_cards')
              .update({'quantity': currentQty + 1})
              .eq('id', existing['id'] as String);
        } else {
          // Première occurrence : on insère avec les données complètes
          await _db.from('user_collection_cards').insert({
            'collection_id': collectionId,
            'user_id': _uid,
            'card_id': card.id,
            'card_name': card.name,
            'card_rarity': card.rarity.name,
            // FIX persistance : sérialise la carte pour pouvoir la reconstruire
            'card_data': CardStorage.toJson(card),
            'quantity': 1,
            // FIX timer : UTC partout
            'obtained_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } catch (e) {
        // Ne pas planter toute la sauvegarde si une carte échoue
        continue;
      }
    }
  }

  /// Charge toutes les cartes possédées par l'utilisateur dans cette collection.
  Future<List<UserCardEntry>> loadUserCards(String collectionId) async {
    try {
      final res = await _db
          .from('user_collection_cards')
          .select()
          .eq('collection_id', collectionId)
          .eq('user_id', _uid)
          .order('obtained_at', ascending: false);

      return (res as List).map((row) => UserCardEntry.fromMap(row)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Charge toutes les cartes et les reconstruit en SavedCard directement.
  Future<List<SavedCard>> loadUserSavedCards(String collectionId) async {
    final entries = await loadUserCards(collectionId);
    return entries.map((e) => e.toSavedCard()).whereType<SavedCard>().toList();
  }

  // ── Helper ────────────────────────────────────────────────────────────────
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
