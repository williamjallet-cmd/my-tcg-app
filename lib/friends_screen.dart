// friends_screen.dart
// Point 3 DA : écran vide plus engageant + 3e onglet Envoyées
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
      if (mounted)
        setState(() {
          _friends = results[0];
          _pending = results[1];
          _sent = results[2];
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(onAdded: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0533), Color(0xFF080814)],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        'Amis',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 26,
                        ),
                      ),
                      const Spacer(),
                      // Bouton + dans le header
                      GestureDetector(
                        onTap: _showSearch,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_add_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Tabs
                  TabBar(
                    controller: _tabCtrl,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white30,
                    indicatorColor: const Color(0xFF7C3AED),
                    indicatorWeight: 2,
                    dividerColor: Colors.white.withValues(alpha: 0.06),
                    tabs: [
                      Tab(text: 'Amis (${_friends.length})'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Reçues'),
                            if (_pending.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDB2777),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_pending.length}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Tab(text: 'Envoyées'),
                    ],
                  ),
                ],
              ),
            ),

            // ── Corps ────────────────────────────────────────────────────────────
            Expanded(
              child:
                  _loading
                      ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF7C3AED),
                        ),
                      )
                      : TabBarView(
                        controller: _tabCtrl,
                        children: [_friendsList(), _pendingList(), _sentList()],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _friendsList() {
    if (_friends.isEmpty) return _emptyFriends();
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

  Widget _pendingList() {
    if (_pending.isEmpty)
      return _emptySimple(
        Icons.mark_email_read_outlined,
        'Aucune demande reçue',
        'Les demandes d\'amis apparaissent ici',
      );
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

  Widget _sentList() {
    if (_sent.isEmpty)
      return _emptySimple(
        Icons.send_rounded,
        'Aucune demande envoyée',
        'Tes demandes en attente apparaissent ici',
      );
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

  // ── État vide amis — illustré et avec CTA ───────────────────────────────────
  Widget _emptyFriends() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Illustration
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF7C3AED).withValues(alpha: 0.2),
                const Color(0xFF080814),
              ],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Cercles décoratifs
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
              ),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
              ),
              // Icône centrale
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                ),
                child: const Icon(
                  Icons.people_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Pas encore d\'amis',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Invite tes amis pour partager\ndes collections et ouvrir des packs ensemble !',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        // CTA
        GestureDetector(
          onTap: _showSearch,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text(
                  'Ajouter un ami',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  // État vide simple (pending / sent)
  Widget _emptySimple(IconData icon, String title, String sub) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 52, color: Colors.white.withValues(alpha: 0.1)),
        const SizedBox(height: 14),
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 13,
          ),
        ),
      ],
    ),
  );
}

// ━━ TUILES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FriendTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onRemove;
  const _FriendTile({required this.friendship, required this.onRemove});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF16213E),
      borderRadius: BorderRadius.circular(16),
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
        ),
      ),
      trailing: PopupMenuButton<String>(
        color: const Color(0xFF16213E),
        icon: Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.4)),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF16213E),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
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
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.red, size: 20),
            onPressed: onDecline,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
            ),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.check, color: Colors.white, size: 20),
            onPressed: onAccept,
          ),
        ),
      ],
    ),
  );
}

class _SentTile extends StatelessWidget {
  final Friendship friendship;
  final VoidCallback onCancel;
  const _SentTile({required this.friendship, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: const Color(0xFF16213E),
      borderRadius: BorderRadius.circular(16),
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
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          'En attente',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ),
    ),
  );
}

class _Avatar extends StatelessWidget {
  final UserProfile profile;
  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      if (profile.avatarUrl!.startsWith('preset:')) {
        final emoji = profile.avatarUrl!.replaceFirst('preset:', '');
        return CircleAvatar(
          radius: 22,
          backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.2),
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        );
      }
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(profile.avatarUrl!),
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.3),
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

// ━━ SEARCH SHEET ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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

  Future<void> _add(UserProfile user) async {
    try {
      await ProfileService.instance.sendFriendRequest(user.id);
      setState(() => _sent.add(user.id));
      widget.onAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Demande envoyée à ${user.displayName} !'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 20,
        right: 20,
        top: 16,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
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
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF7C3AED),
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_searching)
            const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
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
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12,
                  ),
                ),
                trailing:
                    _sent.contains(u.id)
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : ElevatedButton(
                          onPressed: () => _add(u),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7C3AED),
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
