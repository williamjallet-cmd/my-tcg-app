// collection_service.dart — ajout de la personnalisation du pack
//   (pack_title, pack_subtitle, pack_image_url) + uploadPackImage
//
// ✅ OPTIMISATIONS (audit juillet 2026) :
//   • getMemberCount : comptage CÔTÉ SERVEUR (plus aucune ligne téléchargée)
//   • saveUserCards  : requêtes GROUPÉES (2 allers-retours au lieu de 2 par carte)
//   • Fin des erreurs silencieuses : chaque échec passe par reportError()
//     → les erreurs RLS/réseau s'affichent À L'ÉCRAN, pas seulement dans
//       la console (invisible sur téléphone). Voir error_reporter.dart.
//   • Signatures et comportements INCHANGÉS pour tous les appelants.

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'card_storage.dart';
import 'error_reporter.dart';

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
  final bool isPublic;

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
    this.isPublic = false,
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
    isPublic: (m['is_public'] as bool?) ?? false,
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
  // ✨ Fusion GOLD
  final bool isGold;

  const UserCardEntry({
    required this.id,
    required this.cardId,
    required this.cardName,
    required this.cardRarity,
    required this.quantity,
    required this.obtainedAt,
    this.cardData,
    this.isGold = false,
  });

  factory UserCardEntry.fromMap(Map<String, dynamic> m) => UserCardEntry(
    id: m['id'] as String,
    cardId: m['card_id'] as String,
    cardName: m['card_name'] as String,
    cardRarity: m['card_rarity'] as String,
    quantity: (m['quantity'] as int?) ?? 1,
    obtainedAt: DateTime.parse(m['obtained_at'] as String),
    isGold: (m['is_gold'] as bool?) ?? false,
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
      // Libellé volontairement générique (sans le nom) : si plusieurs cartes
      // sont illisibles, l'anti-spam du reporter les regroupe en un message.
      debugPrint('⚠️ carte possédée illisible : $cardName');
      reportError('Lecture d\'une de tes cartes', e);
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
      debugPrint('⚠️ carte du catalogue illisible : $cardName');
      reportError('Lecture d\'une carte du catalogue', e);
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

  /// ⚠️ Laisse remonter l'erreur : un échec d'upload (bucket `collections`
  /// absent, policy RLS manquante, hors-ligne) doit être VISIBLE, sinon
  /// l'image semble « ne pas s'enregistrer » sans aucun message.
  Future<String?> uploadCoverImage(Uint8List bytes, String collectionId) async {
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
      reportError('Envoi de l\'image du pack', e, level: ErrorLevel.dataLoss);
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
      // La collection est déjà créée : un échec d'image ne doit pas
      // annuler la création (l'image reste modifiable ensuite).
      try {
        final url = await uploadCoverImage(imageBytes, collection.id);
        if (url != null) {
          await _db
              .from('collections')
              .update({'image_url': url})
              .eq('id', collection.id);
        }
      } catch (e) {
        reportError(
          'Envoi de l\'image de couverture',
          e,
          level: ErrorLevel.dataLoss,
        );
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
    //
    // ⚠️ PIÈGE SUPABASE : un UPDATE bloqué par une règle RLS ne lève AUCUNE
    // erreur — il modifie simplement 0 ligne. Sans le `.select()` ci-dessous,
    // l'app affichait « enregistré » alors que rien n'avait changé
    // (symptôme : l'image de couverture ne s'affiche jamais).
    final updatedRows =
        await _db
            .from('collections')
            .update(updates)
            .eq('id', collectionId)
            .select();

    if ((updatedRows as List).isEmpty) {
      throw Exception(
        'Modification refusée par la base de données : aucune ligne modifiée.\n'
        'Causes possibles : (1) aucune policy RLS `UPDATE` sur la table '
        '`collections` — avec RLS activé, sans policy UPDATE tout est refusé ; '
        '(2) la policy existe mais owner_user_id ne correspond pas à ton '
        'identifiant (ancienne collection migrée).',
      );
    }

    return CollectionModel.fromMap(
      Map<String, dynamic>.from(updatedRows.first as Map),
    );
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

  /// ✅ CORRECTIF : on repêche aussi les collections dont on est
  /// PROPRIÉTAIRE, même sans ligne dans `collection_members`.
  ///
  /// createCollection insère la collection, puis appelle `_joinAsMember`
  /// dans un second temps. Si cette seconde requête échouait (coupure
  /// réseau au mauvais moment), la collection existait bel et bien mais
  /// disparaissait de la liste de son créateur — définitivement, puisque
  /// cette liste ne lisait que `collection_members`.
  Future<List<CollectionModel>> getMyCollections() async {
    final byId = <String, CollectionModel>{};

    final asMember = await _db
        .from('collection_members')
        .select('collections(*)')
        .eq('user_id', _uid);
    for (final row in (asMember as List)) {
      if (row['collections'] == null) continue;
      final c = CollectionModel.fromMap(
        row['collections'] as Map<String, dynamic>,
      );
      byId[c.id] = c;
    }

    final asOwner = await _db
        .from('collections')
        .select()
        .eq('owner_user_id', _uid);
    for (final row in (asOwner as List)) {
      final c = CollectionModel.fromMap(row as Map<String, dynamic>);
      byId[c.id] = c;
    }

    return byId.values.toList();
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
      reportError('Comptage des membres', e);
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
      reportError('Chargement du catalogue', e);
      return [];
    }
  }

  /// ✅ PERF : `card_data` du catalogue UNIQUEMENT pour les cartes demandées.
  /// L'ancienne version tirait le card_data des 44 cartes à chaque
  /// chargement, alors qu'elles sont déjà sur le téléphone.
  Future<List<CatalogCardEntry>> getCollectionCardsData(
    String collectionId,
    List<String> cardIds,
  ) async {
    if (cardIds.isEmpty) return [];
    try {
      final res = await _db
          .from('collection_cards')
          .select('card_id, card_name, card_rarity, card_data')
          .eq('collection_id', collectionId)
          .inFilter('card_id', cardIds);
      return (res as List)
          .map((r) => CatalogCardEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      reportError('Chargement du catalogue', e);
      return [];
    }
  }

  /// ⚠️ LÈVE une exception en cas d'échec — NE RENVOIE JAMAIS une liste vide
  /// pour signaler une erreur.
  ///
  /// Pourquoi c'est vital : l'appelant compare cette liste au catalogue
  /// local et SUPPRIME du téléphone toute carte absente. Avec l'ancien
  /// `return []` en cas d'erreur, une simple coupure réseau faisait croire
  /// que le catalogue était vide → TOUTES les cartes locales étaient
  /// effacées. Un échec doit rester un échec, pas devenir « zéro carte ».
  Future<List<String>> getCollectionCardIds(String collectionId) async {
    final res = await _db
        .from('collection_cards')
        .select('card_id')
        .eq('collection_id', collectionId);
    return (res as List).map((r) => r['card_id'] as String).toList();
  }

  /// Variante tolérante, pour les usages en LECTURE SEULE (affichage d'un
  /// compteur…) où un échec ne doit rien détruire ni bloquer l'écran.
  Future<List<String>> getCollectionCardIdsOrEmpty(String collectionId) async {
    try {
      return await getCollectionCardIds(collectionId);
    } catch (e) {
      reportError('Chargement du catalogue', e);
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
      reportError('Vérification des droits admin', e);
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
            rethrow; // ⚠️ une carte perdue en silence = pire qu'une erreur
          }
        }
      }

      // 1 seule requête d'insertion pour toutes les nouvelles cartes
      if (toInsert.isNotEmpty) {
        await _db.from('user_collection_cards').insert(toInsert);
      }
    } catch (e) {
      // ⚠️ NE PLUS AVALER : un échec ici fait disparaître les cartes du pack
      // (elles n'existent alors NI sur le serveur, NI dans « Mes cartes »).
      // L'appelant doit pouvoir prévenir le joueur.
      debugPrint('⚠️ saveUserCards : $e');
      rethrow;
    }
  }

  /// ✨ FUSION GOLD : consomme [cost] exemplaires d'une carte possédée
  /// et la transforme en version GOLD permanente.
  /// Retourne true si la fusion a réussi.
  Future<bool> fuseCardToGold(
    String collectionId,
    String cardId,
    int cost,
  ) async {
    try {
      final row =
          await _db
              .from('user_collection_cards')
              .select('id, quantity, is_gold')
              .eq('collection_id', collectionId)
              .eq('user_id', _uid)
              .eq('card_id', cardId)
              .maybeSingle();
      if (row == null) return false;
      if ((row['is_gold'] as bool?) ?? false) return false; // déjà GOLD
      final qty = (row['quantity'] as int?) ?? 1;
      if (qty < cost) return false; // pas assez d'exemplaires

      final remaining = qty - cost;
      await _db
          .from('user_collection_cards')
          .update({'quantity': remaining < 1 ? 1 : remaining, 'is_gold': true})
          .eq('id', row['id'] as String);
      return true;
    } catch (e) {
      reportError('Fusion GOLD', e, level: ErrorLevel.dataLoss);
      return false;
    }
  }

  /// ✅ PERF : liste LÉGÈRE des cartes possédées — sans `card_data`.
  ///
  /// `card_data` contient tout le JSON des calques, et même l'image en
  /// base64 pour les cartes dont l'envoi vers Storage avait échoué. Le
  /// télécharger pour TOUTES les cartes à chaque chargement d'écran
  /// représentait des centaines de kilo-octets — parfois des mégaoctets —
  /// alors que les cartes sont déjà sur le téléphone dans 99 % des cas.
  ///
  /// Utiliser [loadUserCardsData] pour ne récupérer que ce qui manque.
  Future<List<UserCardEntry>> loadUserCardMetas(String collectionId) async {
    try {
      final res = await _db
          .from('user_collection_cards')
          .select(
            'id, card_id, card_name, card_rarity, quantity, '
            'obtained_at, is_gold',
          )
          .eq('collection_id', collectionId)
          .eq('user_id', _uid)
          .order('obtained_at', ascending: false);
      return (res as List).map((row) => UserCardEntry.fromMap(row)).toList();
    } catch (e) {
      reportError('Chargement de tes cartes', e);
      return [];
    }
  }

  /// `card_data` UNIQUEMENT pour les cartes demandées (celles absentes du
  /// téléphone). Ne fait aucune requête si la liste est vide.
  Future<List<UserCardEntry>> loadUserCardsData(
    String collectionId,
    List<String> cardIds,
  ) async {
    if (cardIds.isEmpty) return [];
    try {
      final res = await _db
          .from('user_collection_cards')
          .select()
          .eq('collection_id', collectionId)
          .eq('user_id', _uid)
          .inFilter('card_id', cardIds);
      return (res as List).map((row) => UserCardEntry.fromMap(row)).toList();
    } catch (e) {
      reportError('Chargement de tes cartes', e);
      return [];
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
      reportError('Chargement de tes cartes', e);
      return [];
    }
  }

  Future<List<SavedCard>> loadUserSavedCards(String collectionId) async {
    final entries = await loadUserCards(collectionId);
    return entries.map((e) => e.toSavedCard()).whereType<SavedCard>().toList();
  }

  /// ✨ Nombre de cartes réellement POSSÉDÉES par l'utilisateur.
  /// Comptage côté serveur (0 ligne téléchargée).
  ///
  /// ✅ CORRECTIF : passe [collectionIds] pour ne compter que les
  /// collections auxquelles le joueur appartient ENCORE.
  /// `leaveCollection` supprime la ligne de membre mais conserve les cartes
  /// (volontairement : le joueur retrouve sa progression s'il revient).
  /// Sans ce filtre, le compteur du profil incluait les cartes de
  /// collections quittées — un chiffre qui ne pouvait que monter.
  Future<int> getMyOwnedCardCount({List<String>? collectionIds}) async {
    try {
      if (collectionIds != null) {
        if (collectionIds.isEmpty) return 0;
        return await _db
            .from('user_collection_cards')
            .count(CountOption.exact)
            .eq('user_id', _uid)
            .inFilter('collection_id', collectionIds);
      }
      return await _db
          .from('user_collection_cards')
          .count(CountOption.exact)
          .eq('user_id', _uid);
    } catch (e) {
      reportError('Comptage de tes cartes', e);
      return 0;
    }
  }

  /// ✨ Identifiants des cartes possédées dans UNE collection.
  /// Renvoie les ids (et non un simple total) pour pouvoir les croiser avec
  /// les cartes réellement affichables — même règle que le DEX.
  /// Ne télécharge que les `card_id` (pas les `card_data`, très lourds).
  Future<List<String>> getMyOwnedCardIds(String collectionId) async {
    try {
      final res = await _db
          .from('user_collection_cards')
          .select('card_id')
          .eq('collection_id', collectionId)
          .eq('user_id', _uid);
      return (res as List).map((r) => r['card_id'] as String).toList();
    } catch (e) {
      reportError('Comptage de tes cartes', e);
      return [];
    }
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
