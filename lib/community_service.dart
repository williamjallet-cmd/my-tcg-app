// community_service.dart — collections communautaires : publication,
// découverte, rejoindre, notation en étoiles (0.5 → 5, pas de 0.5).
//
// Modèle retenu : « catalogue partagé, comme une invitation mais public ».
// Rejoindre une collection communautaire = devenir membre normal
// (collection_members), exactement comme joinByCode. Le catalogue de
// cartes reste unique et partagé ; la progression (user_collection_cards)
// reste individuelle, comme pour toutes les collections existantes.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collection_service.dart';
import 'profile_service.dart';

class CommunityCollection {
  final CollectionModel collection;
  final UserProfile? owner;
  final int memberCount;
  final double avgRating; // 0.0 - 5.0
  final int ratingsCount;
  final double? myRating; // note déjà posée par l'utilisateur courant
  final bool isMember;

  const CommunityCollection({
    required this.collection,
    required this.owner,
    required this.memberCount,
    required this.avgRating,
    required this.ratingsCount,
    required this.isMember,
    this.myRating,
  });
}

class CommunityService {
  CommunityService._();
  static final instance = CommunityService._();
  static final _db = Supabase.instance.client;

  String get _uid => _db.auth.currentUser!.id;

  /// Publie / dépublie une collection dans la communauté (propriétaire only).
  Future<void> setPublic(String collectionId, bool isPublic) async {
    await _db
        .from('collections')
        .update({'is_public': isPublic})
        .eq('id', collectionId)
        .eq('owner_user_id', _uid);
  }

  /// Liste des collections publiques + stats agrégées (membres, notes).
  /// 3 requêtes groupées au total, quel que soit le nombre de collections
  /// (pas de N+1).
  Future<List<CommunityCollection>> browsePublicCollections({
    String? search,
  }) async {
    try {
      var query = _db.from('collections').select().eq('is_public', true);
      if (search != null && search.trim().isNotEmpty) {
        query = query.ilike('name', '%${search.trim()}%');
      }
      final res = await query.order('created_at', ascending: false).limit(50);
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return [];

      final collections = rows.map(CollectionModel.fromMap).toList();
      final ids = collections.map((c) => c.id).toList();
      final ownerIds =
          collections
              .map((c) => c.ownerUserId)
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();

      // Membres (comptage par collection)
      final membersRes = await _db
          .from('collection_members')
          .select('collection_id, user_id')
          .inFilter('collection_id', ids);
      final memberCounts = <String, int>{};
      final myMemberIds = <String>{};
      for (final r in (membersRes as List)) {
        final cid = r['collection_id'] as String;
        memberCounts[cid] = (memberCounts[cid] ?? 0) + 1;
        if (r['user_id'] == _uid) myMemberIds.add(cid);
      }

      // Notes (somme + compte + ma propre note)
      final ratingsRes = await _db
          .from('collection_ratings')
          .select('collection_id, half_stars, user_id')
          .inFilter('collection_id', ids);
      final ratingSums = <String, int>{};
      final ratingCounts = <String, int>{};
      final myRatings = <String, double>{};
      for (final r in (ratingsRes as List)) {
        final cid = r['collection_id'] as String;
        final hs = r['half_stars'] as int;
        ratingSums[cid] = (ratingSums[cid] ?? 0) + hs;
        ratingCounts[cid] = (ratingCounts[cid] ?? 0) + 1;
        if (r['user_id'] == _uid) myRatings[cid] = hs / 2.0;
      }

      // Profils des créateurs
      final owners = <String, UserProfile>{};
      if (ownerIds.isNotEmpty) {
        final ownersRes = await _db
            .from('profiles')
            .select()
            .inFilter('id', ownerIds);
        for (final r in (ownersRes as List)) {
          owners[r['id'] as String] = UserProfile.fromMap(r);
        }
      }

      return collections.map((c) {
        final count = ratingCounts[c.id] ?? 0;
        final avg = count > 0 ? (ratingSums[c.id]! / count) / 2.0 : 0.0;
        return CommunityCollection(
          collection: c,
          owner: owners[c.ownerUserId],
          memberCount: memberCounts[c.id] ?? 0,
          avgRating: avg,
          ratingsCount: count,
          isMember: myMemberIds.contains(c.id),
          myRating: myRatings[c.id],
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ browsePublicCollections : $e');
      return [];
    }
  }

  /// Rejoint une collection communautaire déjà publique (devient membre
  /// normal, exactement comme joinByCode).
  Future<void> joinPublicCollection(String collectionId) async {
    final existing =
        await _db
            .from('collection_members')
            .select('id')
            .eq('collection_id', collectionId)
            .eq('user_id', _uid)
            .maybeSingle();
    if (existing != null) throw Exception('Vous êtes déjà membre.');
    await _db.from('collection_members').insert({
      'collection_id': collectionId,
      'user_id': _uid,
      'device_id': _uid,
    });
  }

  /// Note (ou met à jour la note) d'une collection, de 0.5 à 5, pas de 0.5.
  Future<void> rateCollection(String collectionId, double rating) async {
    final halfStars = (rating * 2).round().clamp(1, 10);
    await _db.from('collection_ratings').upsert({
      'collection_id': collectionId,
      'user_id': _uid,
      'half_stars': halfStars,
    }, onConflict: 'collection_id,user_id');
  }
}
