// profile_service.dart — fix updateProfile + avatar

import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
    id: m['id'] as String,
    username: m['username'] as String,
    displayName: m['display_name'] as String,
    avatarUrl: m['avatar_url'] as String?,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

enum FriendshipStatus { pending, accepted, declined }

class Friendship {
  final String id;
  final UserProfile user;
  final FriendshipStatus status;
  final bool isSentByMe;

  const Friendship({
    required this.id,
    required this.user,
    required this.status,
    required this.isSentByMe,
  });
}

class ProfileService {
  ProfileService._();
  static final instance = ProfileService._();

  final _db = Supabase.instance.client;
  String get _myId => _db.auth.currentUser!.id;

  Future<UserProfile?> getMyProfile() async {
    try {
      final res =
          await _db.from('profiles').select().eq('id', _myId).maybeSingle();
      if (res == null) return null;
      return UserProfile.fromMap(res);
    } catch (_) {
      return null;
    }
  }

  Future<UserProfile?> updateProfile({
    String? displayName,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;
    if (data.isEmpty) return getMyProfile();
    try {
      final res =
          await _db
              .from('profiles')
              .update(data)
              .eq('id', _myId)
              .select()
              .single();
      return UserProfile.fromMap(res);
    } catch (e) {
      // Si update échoue, essaie un upsert
      try {
        final current = await getMyProfile();
        final upsertData = {
          'id': _myId,
          'username': current?.username ?? 'user_$_myId',
          'display_name': displayName ?? current?.displayName ?? '',
          'avatar_url': avatarUrl ?? current?.avatarUrl,
        };
        final res =
            await _db.from('profiles').upsert(upsertData).select().single();
        return UserProfile.fromMap(res);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final res = await _db
        .from('profiles')
        .select()
        .or('username.ilike.%$q%,display_name.ilike.%$q%')
        .neq('id', _myId)
        .limit(20);
    return (res as List).map((r) => UserProfile.fromMap(r)).toList();
  }

  Future<UserProfile?> getUserByUsername(String username) async {
    final res =
        await _db
            .from('profiles')
            .select()
            .eq('username', username.trim().toLowerCase())
            .maybeSingle();
    if (res == null) return null;
    return UserProfile.fromMap(res);
  }

  Future<void> sendFriendRequest(String targetUserId) async {
    final existing =
        await _db
            .from('friendships')
            .select('id')
            .or(
              'and(requester_id.eq.$_myId,addressee_id.eq.$targetUserId),'
              'and(requester_id.eq.$targetUserId,addressee_id.eq.$_myId)',
            )
            .maybeSingle();
    if (existing != null) throw Exception('Demande déjà existante.');
    await _db.from('friendships').insert({
      'requester_id': _myId,
      'addressee_id': targetUserId,
      'status': 'pending',
    });
  }

  Future<void> acceptFriendRequest(String friendshipId) async {
    await _db
        .from('friendships')
        .update({'status': 'accepted'})
        .eq('id', friendshipId)
        .eq('addressee_id', _myId);
  }

  Future<void> declineOrRemoveFriend(String friendshipId) async {
    await _db.from('friendships').delete().eq('id', friendshipId);
  }

  Future<List<Friendship>> getFriends() async {
    final res = await _db
        .from('friendships')
        .select(
          'id, requester_id, addressee_id, status, '
          'requester:profiles!friendships_requester_id_fkey(*), '
          'addressee:profiles!friendships_addressee_id_fkey(*)',
        )
        .eq('status', 'accepted')
        .or('requester_id.eq.$_myId,addressee_id.eq.$_myId');
    return (res as List).map((r) {
      final isSentByMe = r['requester_id'] == _myId;
      final other = UserProfile.fromMap(
        isSentByMe ? r['addressee'] : r['requester'],
      );
      return Friendship(
        id: r['id'],
        user: other,
        status: FriendshipStatus.accepted,
        isSentByMe: isSentByMe,
      );
    }).toList();
  }

  Future<List<Friendship>> getPendingRequests() async {
    final res = await _db
        .from('friendships')
        .select(
          'id, requester_id, status, '
          'requester:profiles!friendships_requester_id_fkey(*)',
        )
        .eq('addressee_id', _myId)
        .eq('status', 'pending');
    return (res as List)
        .map(
          (r) => Friendship(
            id: r['id'],
            user: UserProfile.fromMap(r['requester']),
            status: FriendshipStatus.pending,
            isSentByMe: false,
          ),
        )
        .toList();
  }

  Future<List<Friendship>> getSentRequests() async {
    final res = await _db
        .from('friendships')
        .select(
          'id, addressee_id, status, '
          'addressee:profiles!friendships_addressee_id_fkey(*)',
        )
        .eq('requester_id', _myId)
        .eq('status', 'pending');
    return (res as List)
        .map(
          (r) => Friendship(
            id: r['id'],
            user: UserProfile.fromMap(r['addressee']),
            status: FriendshipStatus.pending,
            isSentByMe: true,
          ),
        )
        .toList();
  }

  Future<UserProfile?> getProfile(String userId) async {
    final res =
        await _db.from('profiles').select().eq('id', userId).maybeSingle();
    if (res == null) return null;
    return UserProfile.fromMap(res);
  }
}
