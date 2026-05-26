// friends_screen.dart
// ✦ Amis — liste, recherche, demandes, profil public ✦

import 'package:flutter/material.dart';
import 'profile_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<Friendship> _friends = [];
  List<Friendship> _pending = [];
  List<Friendship> _sent = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ProfileService.instance.getFriends(),
        ProfileService.instance.getPendingRequests(),
        ProfileService.instance.getSentRequests(),
      ]);
      if (mounted) {
        setState(() {
          _friends = results[0];
          _pending = results[1];
          _sent = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A0A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SearchSheet(onAdded: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        title: const Text(
          'Amis',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: _showSearch,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white38),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF6C4AB6),
          tabs: [
            Tab(text: 'Amis (${_friends.length})'),
            Tab(
              text: _pending.isEmpty ? 'Reçues' : 'Reçues (${_pending.length})',
            ),
            Tab(text: 'Envoyées'),
          ],
        ),
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C4AB6)),
              )
              : TabBarView(
                controller: _tabCtrl,
                children: [_friendsList(), _pendingList(), _sentList()],
              ),
    );
  }

  // ── Onglet amis ───────────────────────────────────────────────────────────
  Widget _friendsList() {
    if (_friends.isEmpty) {
      return _emptyState(
        Icons.people_outline,
        'Aucun ami pour l\'instant',
        'Ajoute des amis avec le bouton +',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _friends.length,
      itemBuilder:
          (_, i) => _FriendTile(
            friendship: _friends[i],
            onRemove: () async {
              await ProfileService.instance.declineOrRemoveFriend(
                _friends[i].id,
              );
              _load();
            },
          ),
    );
  }

  // ── Onglet demandes reçues ────────────────────────────────────────────────
  Widget _pendingList() {
    if (_pending.isEmpty) {
      return _emptyState(
        Icons.mark_email_read_outlined,
        'Aucune demande reçue',
        '',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pending.length,
      itemBuilder:
          (_, i) => _PendingTile(
            friendship: _pending[i],
            onAccept: () async {
              await ProfileService.instance.acceptFriendRequest(_pending[i].id);
              _load();
            },
            onDecline: () async {
              await ProfileService.instance.declineOrRemoveFriend(
                _pending[i].id,
              );
              _load();
            },
          ),
    );
  }

  // ── Onglet demandes envoyées ──────────────────────────────────────────────
  Widget _sentList() {
    if (_sent.isEmpty) {
      return _emptyState(Icons.send_outlined, 'Aucune demande envoyée', '');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _sent.length,
      itemBuilder:
          (_, i) => _SentTile(
            friendship: _sent[i],
            onCancel: () async {
              await ProfileService.instance.declineOrRemoveFriend(_sent[i].id);
              _load();
            },
          ),
    );
  }

  Widget _emptyState(IconData icon, String title, String sub) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 64, color: Colors.white.withValues(alpha:0.1)),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha:0.4),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            sub,
            style: TextStyle(
              color: Colors.white.withValues(alpha:0.25),
              fontSize: 13,
            ),
          ),
        ],
      ],
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   TUILES
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FriendTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onRemove;
  const _FriendTile({required this.friendship, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: _Avatar(profile: friendship.user),
        title: Text(
          friendship.user.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '@${friendship.user.username}',
          style: TextStyle(color: Colors.white.withValues(alpha:0.4), fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          color: const Color(0xFF16213E),
          icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha:0.4)),
          onSelected: (v) {
            if (v == 'remove') onRemove();
          },
          itemBuilder:
              (_) => [
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove, color: Colors.red, size: 18),
                      SizedBox(width: 10),
                      Text('Retirer', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
        ),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _PendingTile({
    required this.friendship,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C4AB6).withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          _Avatar(profile: friendship.user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friendship.user.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '@${friendship.user.username}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.4),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
            onPressed: onAccept,
          ),
          IconButton(
            icon: Icon(Icons.cancel, color: Colors.red.shade300, size: 28),
            onPressed: onDecline,
          ),
        ],
      ),
    );
  }
}

class _SentTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onCancel;
  const _SentTile({required this.friendship, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: _Avatar(profile: friendship.user),
        title: Text(
          friendship.user.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '@${friendship.user.username}',
          style: TextStyle(color: Colors.white.withValues(alpha:0.4), fontSize: 12),
        ),
        trailing: TextButton(
          onPressed: onCancel,
          child: Text(
            'Annuler',
            style: TextStyle(color: Colors.red.shade300, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final UserProfile profile;
  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(profile.avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFF6C4AB6).withValues(alpha:0.3),
      child: Text(
        profile.displayName.isNotEmpty
            ? profile.displayName[0].toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   BOTTOM SHEET RECHERCHE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SearchSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _SearchSheet({required this.onAdded});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctrl = TextEditingController();
  List<UserProfile> _results = [];
  bool _searching = false;
  final Set<String> _sent = {};

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await ProfileService.instance.searchUsers(q);
      if (mounted) setState(() => _results = res);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addFriend(UserProfile user) async {
    try {
      await ProfileService.instance.sendFriendRequest(user.id);
      if (!mounted) return;
      setState(() => _sent.add(user.id));
      widget.onAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Demande envoyée à ${user.displayName} !'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ajouter un ami',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Rechercher par nom ou @username',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha:0.3)),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF16213E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF6C4AB6),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF6C4AB6)),
            )
          else
            ..._results.map(
              (u) => ListTile(
                leading: _Avatar(profile: u),
                title: Text(
                  u.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '@${u.username}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.4),
                    fontSize: 12,
                  ),
                ),
                trailing:
                    _sent.contains(u.id)
                        ? const Icon(Icons.check, color: Colors.green)
                        : ElevatedButton(
                          onPressed: () => _addFriend(u),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C4AB6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Ajouter',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
