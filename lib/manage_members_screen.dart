import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collection_service.dart';
import 'arcade_theme.dart';

class ManageMembersScreen extends StatefulWidget {
  final CollectionModel collection;
  final String myUserId;
  const ManageMembersScreen({
    super.key,
    required this.collection,
    required this.myUserId,
  });
  @override
  State<ManageMembersScreen> createState() => _ManageMembersScreenState();
}

class _ManageMembersScreenState extends State<ManageMembersScreen> {
  final _db = Supabase.instance.client;
  List<_Member> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await _db
          .from('collection_members')
          .select('user_id, role, profiles(display_name, username, avatar_url)')
          .eq('collection_id', widget.collection.id);
      if (mounted) {
        setState(() {
          _members =
              (res as List).map((r) {
                final p = r['profiles'] as Map<String, dynamic>?;
                return _Member(
                  userId: r['user_id'] as String,
                  role: r['role'] as String? ?? 'member',
                  displayName:
                      p?['display_name'] as String? ??
                      p?['username'] as String? ??
                      '?',
                  avatarUrl: p?['avatar_url'] as String?,
                );
              }).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setRole(String userId, String newRole) async {
    try {
      await _db
          .from('collection_members')
          .update({'role': newRole})
          .eq('collection_id', widget.collection.id)
          .eq('user_id', userId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Arcade.coral),
      );
    }
  }

  Future<void> _kick(String userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: Arcade.surface,
            title: Text('Exclure ce membre ?', style: Arcade.title(size: 16)),
            content: Text(
              'Cette action est irréversible.',
              style: Arcade.body(color: Arcade.creamDim),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Annuler',
                  style: Arcade.body(color: Arcade.creamDim),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Arcade.coral),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  'Exclure',
                  style: Arcade.body(
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (ok != true) return;
    try {
      await _db
          .from('collection_members')
          .delete()
          .eq('collection_id', widget.collection.id)
          .eq('user_id', userId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Arcade.coral),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.collection.isOwnedBy(widget.myUserId);
    return Scaffold(
      backgroundColor: Arcade.bg,
      appBar: AppBar(
        backgroundColor: Arcade.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Arcade.cream.withValues(alpha: 0.8),
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Membres', style: Arcade.title(size: 20)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Arcade.cream.withValues(alpha: 0.08),
          ),
        ),
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: Arcade.gold),
              )
              : _members.isEmpty
              ? Center(
                child: Text(
                  'Aucun membre',
                  style: Arcade.body(color: Arcade.creamDim),
                ),
              )
              : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: _members.length,
                itemBuilder: (_, i) {
                  final m = _members[i];
                  final isSelf = m.userId == widget.myUserId;
                  final isCollectionOwner = widget.collection.isOwnedBy(
                    m.userId,
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Arcade.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Arcade.cream.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Arcade.surface2,
                          backgroundImage:
                              m.avatarUrl != null
                                  ? NetworkImage(m.avatarUrl!)
                                  : null,
                          child:
                              m.avatarUrl == null
                                  ? Text(
                                    m.displayName.isNotEmpty
                                        ? m.displayName[0].toUpperCase()
                                        : '?',
                                    style: Arcade.title(size: 16),
                                  )
                                  : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.displayName,
                                style: Arcade.body(
                                  size: 14,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isCollectionOwner
                                    ? 'Propriétaire'
                                    : m.role == 'admin'
                                    ? 'Admin'
                                    : 'Membre',
                                style: Arcade.pixel(
                                  size: 9,
                                  color:
                                      isCollectionOwner
                                          ? Arcade.gold
                                          : m.role == 'admin'
                                          ? Arcade.teal
                                          : Arcade.creamDim,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isOwner && !isSelf && !isCollectionOwner) ...[
                          IconButton(
                            tooltip:
                                m.role == 'admin'
                                    ? 'Rétrograder'
                                    : 'Promouvoir admin',
                            icon: Icon(
                              m.role == 'admin'
                                  ? Icons.arrow_downward_rounded
                                  : Icons.arrow_upward_rounded,
                              color:
                                  m.role == 'admin'
                                      ? Arcade.coral
                                      : Arcade.teal,
                              size: 20,
                            ),
                            onPressed:
                                () => _setRole(
                                  m.userId,
                                  m.role == 'admin' ? 'member' : 'admin',
                                ),
                          ),
                          IconButton(
                            tooltip: 'Exclure',
                            icon: Icon(
                              Icons.person_remove_rounded,
                              color: Arcade.coral,
                              size: 20,
                            ),
                            onPressed: () => _kick(m.userId),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
    );
  }
}

class _Member {
  final String userId;
  final String role;
  final String displayName;
  final String? avatarUrl;
  const _Member({
    required this.userId,
    required this.role,
    required this.displayName,
    this.avatarUrl,
  });
}
