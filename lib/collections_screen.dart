// collections_screen.dart — écran d'accueil (liste des collections)
// RESKIN rétro-arcade premium. Logique inchangée (chargement, timer,
// navigation, création, suppression, édition, partage).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collection_service.dart';
import 'pack_system.dart';
import 'collection_detail_screen.dart';
import 'arcade_theme.dart';

// Accent arcade par collection (déterministe sur l'id) — or / teal / corail / épique
const _accents = [
  Arcade.gold,
  Arcade.teal,
  Arcade.coral,
  Color(0xFFB45CFF),
  Color(0xFF2FA8FF),
  Color(0xFF3FD17A),
];
Color _accentFor(String id) =>
    _accents[id.codeUnits.fold(0, (a, b) => a + b) % _accents.length];

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen>
    with SingleTickerProviderStateMixin {
  final _service = CollectionService.instance;
  List<CollectionModel> _collections = [];
  bool _loading = true;
  String? _myUserId;
  late AnimationController _fabAnim;

  @override
  void initState() {
    super.initState();
    _fabAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _load();
  }

  @override
  void dispose() {
    _fabAnim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _myUserId = _service.userId;
      _collections = await _service.getMyCollections();
      for (final col in _collections) {
        await PackSystem.syncFromSupabase(col.id);
      }
    } catch (e) {
      _showMsg('Erreur : $e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showMsg(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: Arcade.body(color: Colors.white)),
        backgroundColor: error ? Arcade.coral : const Color(0xFF2E7D32),
      ),
    );
  }

  Future<void> _createCollection() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const _CreateCollectionScreen(),
        transitionsBuilder:
            (_, anim, __, child) => SlideTransition(
              position: Tween(
                begin: const Offset(0, 1),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
      ),
    );
    if (result == null) return;
    try {
      await _service.createCollection(
        name: result['name'],
        description: result['description'] ?? '',
        imageBytes: result['imageBytes'],
        packCooldownHours: result['cooldown'] ?? 3,
        membersCanAddCards: result['membersCanAdd'] ?? true,
      );
      _showMsg('Collection créée ! 🎉');
      await _load();
    } catch (e) {
      _showMsg('Erreur : $e', error: true);
    }
  }

  Future<void> _joinByCode() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JoinSheet(),
    );
    if (code == null || code.isEmpty) return;
    try {
      final col = await _service.joinByCode(code);
      _showMsg('Bienvenue dans « ${col.name} » ! 🎉');
      await _load();
    } catch (e) {
      _showMsg('$e', error: true);
    }
  }

  Future<void> _leaveOrDelete(CollectionModel col) async {
    final isOwner = col.isOwnedBy(_myUserId ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: Arcade.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              isOwner ? 'Supprimer ?' : 'Quitter ?',
              style: Arcade.title(size: 18),
            ),
            content: Text(
              isOwner
                  ? 'Tous les membres perdront l\'accès à « ${col.name} ».'
                  : 'Tu quitteras « ${col.name} ».',
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
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Arcade.coral),
                child: Text(
                  isOwner ? 'Supprimer' : 'Quitter',
                  style: Arcade.body(
                    color: Colors.white,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    try {
      if (isOwner) {
        await _service.deleteCollection(col.id);
        _showMsg('Collection supprimée.');
      } else {
        await _service.leaveCollection(col.id);
        _showMsg('Collection quittée.');
      }
      await _load();
    } catch (e) {
      _showMsg('Erreur : $e', error: true);
    }
  }

  Future<void> _editCollection(CollectionModel col) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCollectionSheet(collection: col),
    );
    if (updated == true) {
      _showMsg('Collection mise à jour ! ✅');
      await _load();
    }
  }

  void _openDetail(CollectionModel col) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CollectionDetailScreen(
              collection: col,
              myUserId: _myUserId ?? '',
            ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Arcade.bg,
      body: Stack(
        children: [
          // fond radial arcade
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -1),
                radius: 1.3,
                colors: [Color(0xFF241A3A), Arcade.bg, Arcade.bgDeep],
                stops: [0.0, 0.45, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
          const Positioned.fill(child: ScanlineOverlay(opacity: 0.04)),
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
                  title: Text(
                    'BROKEMON',
                    style: Arcade.title(
                      size: 24,
                      spacing: 1,
                      shadows: const [
                        Shadow(blurRadius: 1, color: Arcade.gold),
                        Shadow(offset: Offset(2, 2), color: Color(0x66000000)),
                      ],
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Arcade.cream,
                    ),
                    onPressed: _load,
                  ),
                ],
              ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Arcade.gold),
                  ),
                )
              else if (_collections.isEmpty)
                SliverFillRemaining(child: _emptyState())
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _CollectionCard(
                        collection: _collections[i],
                        myUserId: _myUserId ?? '',
                        accent: _accentFor(_collections[i].id),
                        onTap: () => _openDetail(_collections[i]),
                        onLeaveOrDelete: () => _leaveOrDelete(_collections[i]),
                        onShare: () => _showShareSheet(_collections[i]),
                        onEdit: () => _editCollection(_collections[i]),
                      ),
                      childCount: _collections.length,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ScaleTransition(
            scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
            child: ArcadeButton(
              label: 'REJOINDRE',
              icon: Icons.group_add_rounded,
              color: Arcade.teal,
              colorDeep: const Color(0xFF12A88E),
              textColor: const Color(0xFF06251F),
              onTap: _joinByCode,
            ),
          ),
          const SizedBox(height: 12),
          ScaleTransition(
            scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
            child: ArcadeButton(
              label: 'CRÉER',
              icon: Icons.add_rounded,
              onTap: _createCollection,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('👾', style: TextStyle(fontSize: 72)),
        const SizedBox(height: 20),
        Text('Aucune collection', style: Arcade.title(size: 22)),
        const SizedBox(height: 10),
        Text(
          'Crée ta première collection\nou rejoins celle d\'un ami !',
          textAlign: TextAlign.center,
          style: Arcade.body(color: Arcade.creamFaint, size: 15, height: 1.6),
        ),
      ],
    ),
  );

  void _showShareSheet(CollectionModel col) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(collection: col),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   TUILE COLLECTION (carte actuelle, repeinte arcade)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CollectionCard extends StatefulWidget {
  final CollectionModel collection;
  final String myUserId;
  final Color accent;
  final VoidCallback onTap, onLeaveOrDelete, onShare, onEdit;

  const _CollectionCard({
    required this.collection,
    required this.myUserId,
    required this.accent,
    required this.onTap,
    required this.onLeaveOrDelete,
    required this.onShare,
    required this.onEdit,
  });

  @override
  State<_CollectionCard> createState() => _CollectionCardState();
}

class _CollectionCardState extends State<_CollectionCard> {
  Duration _remaining = Duration.zero;
  bool _canOpen = false;
  Timer? _timer;
  int _memberCount = 0;
  int _totalCards = 0;
  int _obtainedCards = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      PackSystem.timeUntilNextPack(widget.collection.id),
      PackSystem.canOpenPack(widget.collection.id),
      CollectionService.instance.getMemberCount(widget.collection.id),
      CollectionService.instance.getCollectionCardIds(widget.collection.id),
    ]);

    final r = results[0] as Duration;
    final c = results[1] as bool;
    final members = results[2] as int;
    final cardIds = results[3] as List<String>;

    final prefs = await SharedPreferences.getInstance();
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    final obtained =
        (prefs.getStringList('obtained_${uid}_${widget.collection.id}') ?? [])
            .length;

    if (mounted) {
      setState(() {
        _remaining = r;
        _canOpen = c;
        _memberCount = members;
        _totalCards = cardIds.length;
        _obtainedCards = obtained;
      });
    }
    if (!c) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) {
          _timer?.cancel();
          return;
        }
        final next = _remaining - const Duration(seconds: 1);
        if (next <= Duration.zero) {
          _timer?.cancel();
          setState(() {
            _remaining = Duration.zero;
            _canOpen = true;
          });
        } else {
          setState(() => _remaining = next);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isOwner => widget.collection.isOwnedBy(widget.myUserId);

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(a, Arcade.surface, 0.35)!,
              Arcade.surface,
              Arcade.bgDeep,
            ],
          ),
          border: Border.all(color: a.withValues(alpha: 0.55), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: a.withValues(alpha: _canOpen ? 0.4 : 0.15),
              blurRadius: _canOpen ? 24 : 12,
              spreadRadius: _canOpen ? 1 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              if (widget.collection.imageUrl != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.16,
                    child: Image.network(
                      widget.collection.imageUrl!,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              const Positioned.fill(child: ScanlineOverlay(opacity: 0.05)),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Titre + menu ──────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.collection.name,
                                style: Arcade.title(
                                  size: 21,
                                  shadows: const [
                                    Shadow(
                                      offset: Offset(0, 1.5),
                                      color: Color(0x73000000),
                                    ),
                                  ],
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.collection.description.isNotEmpty)
                                Text(
                                  widget.collection.description,
                                  style: Arcade.body(
                                    color: Arcade.creamDim,
                                    size: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (_isOwner) ...[
                          PixelBadge(label: '★ ADMIN', color: Arcade.gold),
                          const SizedBox(width: 6),
                        ],
                        PixelBadge(
                          label: '$_memberCount',
                          icon: Icons.people_rounded,
                          color: Arcade.creamDim,
                        ),
                        _menu(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── Bas : pack/timer + code ───────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _canOpen ? _availBadge() : _timerBadge(),
                              if (_totalCards > 0) ...[
                                const SizedBox(height: 8),
                                _cardProgressBar(a),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _codeBox(),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        '👆 APPUIE POUR VOIR',
                        style: Arcade.pixel(
                          size: 7.5,
                          color: Arcade.creamFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu() => PopupMenuButton<String>(
    color: Arcade.surface2,
    icon: const Icon(Icons.more_vert, color: Arcade.cream),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: (v) {
      if (v == 'share') widget.onShare();
      if (v == 'edit') widget.onEdit();
      if (v == 'leave') widget.onLeaveOrDelete();
    },
    itemBuilder:
        (_) => [
          PopupMenuItem(
            value: 'share',
            child: Row(
              children: [
                Icon(Icons.share, color: Arcade.creamDim, size: 18),
                const SizedBox(width: 10),
                Text('Partager', style: Arcade.body()),
              ],
            ),
          ),
          if (_isOwner)
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(
                    Icons.edit_rounded,
                    color: Arcade.creamDim,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text('Modifier', style: Arcade.body()),
                ],
              ),
            ),
          PopupMenuItem(
            value: 'leave',
            child: Row(
              children: [
                Icon(
                  _isOwner ? Icons.delete : Icons.exit_to_app,
                  color: Arcade.coral,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _isOwner ? 'Supprimer' : 'Quitter',
                  style: Arcade.body(color: Arcade.coral),
                ),
              ],
            ),
          ),
        ],
  );

  Widget _cardProgressBar(Color a) {
    final pct =
        _totalCards > 0 ? (_obtainedCards / _totalCards).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_obtainedCards / $_totalCards CARTES',
          style: Arcade.pixel(size: 8, color: Arcade.creamDim),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: Colors.black.withValues(alpha: 0.35),
            valueColor: AlwaysStoppedAnimation(a),
          ),
        ),
      ],
    );
  }

  Widget _availBadge() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: Arcade.gold.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Arcade.gold.withValues(alpha: 0.5)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.auto_awesome, color: Arcade.gold, size: 14),
        const SizedBox(width: 6),
        Text('PACK DISPO !', style: Arcade.title(size: 13, color: Arcade.gold)),
      ],
    ),
  );

  Widget _timerBadge() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Arcade.line),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.hourglass_bottom_rounded,
          color: Arcade.teal,
          size: 14,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PROCHAIN PACK',
              style: Arcade.pixel(size: 7, color: Arcade.creamFaint),
            ),
            const SizedBox(height: 2),
            Text(
              PackSystem.formatDuration(_remaining),
              style: Arcade.title(size: 14, color: Arcade.teal),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _codeBox() => GestureDetector(
    onTap: widget.onShare,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Arcade.line),
      ),
      child: Column(
        children: [
          Text('CODE', style: Arcade.pixel(size: 7, color: Arcade.creamFaint)),
          const SizedBox(height: 3),
          Text(
            widget.collection.code,
            style: Arcade.title(size: 16, spacing: 3),
          ),
        ],
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   MODIFIER COLLECTION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _EditCollectionSheet extends StatefulWidget {
  final CollectionModel collection;
  const _EditCollectionSheet({required this.collection});
  @override
  State<_EditCollectionSheet> createState() => _EditCollectionSheetState();
}

class _EditCollectionSheetState extends State<_EditCollectionSheet> {
  late int _cooldown;
  late bool _membersCanAdd;
  Uint8List? _newImageBytes;
  bool _saving = false;
  final _cooldowns = [1, 2, 3, 6, 12, 24];

  @override
  void initState() {
    super.initState();
    _cooldown = widget.collection.packCooldownHours;
    _membersCanAdd = widget.collection.membersCanAddCards;
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _newImageBytes = bytes);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await CollectionService.instance.updateCollection(
        collectionId: widget.collection.id,
        imageBytes: _newImageBytes,
        packCooldownHours: _cooldown,
        membersCanAddCards: _membersCanAdd,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Arcade.coral),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        left: 24,
        right: 24,
        top: 20,
      ),
      decoration: const BoxDecoration(
        color: Arcade.bgDeep,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grip(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Modifier la collection',
                  style: Arcade.title(size: 18),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close, color: Arcade.creamFaint),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: double.infinity,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: Arcade.surface,
                border: Border.all(color: Arcade.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_newImageBytes != null)
                      Image.memory(_newImageBytes!, fit: BoxFit.cover)
                    else if (widget.collection.imageUrl != null)
                      Image.network(
                        widget.collection.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    Container(color: Colors.black.withValues(alpha: 0.3)),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: Arcade.cream,
                            size: 26,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _newImageBytes != null
                                ? '✅ Nouvelle image'
                                : (widget.collection.imageUrl != null
                                    ? 'Changer l\'image'
                                    : 'Ajouter une image'),
                            style: Arcade.body(
                              size: 12,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'COOLDOWN',
              style: Arcade.pixel(size: 9, color: Arcade.creamDim, spacing: 2),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _cooldowns.map((h) {
                  final sel = _cooldown == h;
                  return GestureDetector(
                    onTap: () => setState(() => _cooldown = h),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: sel ? Arcade.gold : Arcade.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel ? Arcade.gold : Arcade.line,
                        ),
                      ),
                      child: Text(
                        '${h}h',
                        style: Arcade.title(
                          size: 14,
                          color:
                              sel ? const Color(0xFF2A1C00) : Arcade.creamDim,
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Arcade.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Arcade.line),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.people_rounded,
                  color: Arcade.creamDim,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Membres peuvent ajouter des cartes',
                        style: Arcade.body(size: 13, weight: FontWeight.w600),
                      ),
                      Text(
                        'Sinon, seul toi peux ajouter',
                        style: Arcade.body(size: 11, color: Arcade.creamFaint),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _membersCanAdd,
                  onChanged: (v) => setState(() => _membersCanAdd = v),
                  activeColor: Arcade.gold,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _saving
              ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(color: Arcade.gold),
              )
              : ArcadeButton(
                label: 'ENREGISTRER',
                big: true,
                width: double.infinity,
                onTap: _save,
              ),
        ],
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CRÉER COLLECTION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CreateCollectionScreen extends StatefulWidget {
  const _CreateCollectionScreen();
  @override
  State<_CreateCollectionScreen> createState() =>
      _CreateCollectionScreenState();
}

class _CreateCollectionScreenState extends State<_CreateCollectionScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  int _cooldown = 3;
  bool _membersCanAdd = true;
  Uint8List? _imageBytes;
  final _cooldowns = [1, 2, 3, 6, 12, 24];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _imageBytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Arcade.bg,
      appBar: AppBar(
        backgroundColor: Arcade.bg,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Arcade.cream),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Nouvelle collection', style: Arcade.title(size: 18)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ArcadeButton(
                label: 'CRÉER',
                onTap: () {
                  if (_nameCtrl.text.trim().isEmpty) return;
                  Navigator.pop(context, {
                    'name': _nameCtrl.text.trim(),
                    'description': _descCtrl.text.trim(),
                    'imageBytes': _imageBytes,
                    'cooldown': _cooldown,
                    'membersCanAdd': _membersCanAdd,
                  });
                },
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 160,
                decoration: BoxDecoration(
                  gradient:
                      _imageBytes == null
                          ? const LinearGradient(
                            colors: [Color(0xFF6A2EA8), Color(0xFF21808F)],
                          )
                          : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_imageBytes != null)
                        Image.memory(_imageBytes!, fit: BoxFit.cover),
                      if (_imageBytes != null)
                        Container(color: Colors.black.withValues(alpha: 0.35)),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _imageBytes != null
                                  ? Icons.edit_rounded
                                  : Icons.add_photo_alternate_rounded,
                              color: Arcade.cream,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _imageBytes != null
                                  ? 'Changer l\'image'
                                  : 'Ajouter une image de couverture',
                              style: Arcade.body(
                                size: 14,
                                weight: FontWeight.w600,
                              ),
                            ),
                            if (_nameCtrl.text.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _nameCtrl.text,
                                style: Arcade.title(size: 20),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Informations'),
            const SizedBox(height: 12),
            _field(
              _nameCtrl,
              'Nom de la collection *',
              Icons.style_rounded,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _field(_descCtrl, 'Description (optionnel)', Icons.notes_rounded),
            const SizedBox(height: 24),
            _sectionTitle('Cooldown entre les packs'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  _cooldowns.map((h) {
                    final sel = _cooldown == h;
                    return GestureDetector(
                      onTap: () => setState(() => _cooldown = h),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: sel ? Arcade.gold : Arcade.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? Arcade.gold : Arcade.line,
                          ),
                        ),
                        child: Text(
                          '${h}h',
                          style: Arcade.title(
                            size: 15,
                            color:
                                sel ? const Color(0xFF2A1C00) : Arcade.creamDim,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Permissions'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Arcade.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Arcade.line),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people_rounded,
                    color: Arcade.creamDim,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Membres peuvent ajouter des cartes',
                          style: Arcade.body(weight: FontWeight.w600),
                        ),
                        Text(
                          'Sinon, seul l\'admin peut ajouter',
                          style: Arcade.body(
                            size: 12,
                            color: Arcade.creamFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _membersCanAdd,
                    onChanged: (v) => setState(() => _membersCanAdd = v),
                    activeColor: Arcade.gold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: Arcade.title(size: 16));

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    void Function(String)? onChanged,
  }) => TextField(
    controller: c,
    onChanged: onChanged,
    style: Arcade.body(),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: Arcade.body(color: Arcade.creamFaint),
      prefixIcon: Icon(icon, color: Arcade.creamFaint, size: 20),
      filled: true,
      fillColor: Arcade.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Arcade.gold, width: 1.5),
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   JOIN + SHARE SHEETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Widget _grip() => Container(
  width: 40,
  height: 4,
  decoration: BoxDecoration(
    color: Arcade.line,
    borderRadius: BorderRadius.circular(2),
  ),
);

class _JoinSheet extends StatefulWidget {
  const _JoinSheet();
  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 16,
      ),
      decoration: const BoxDecoration(
        color: Arcade.bgDeep,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grip(),
          const SizedBox(height: 20),
          const Text('👾', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text('Rejoindre une collection', style: Arcade.title(size: 20)),
          const SizedBox(height: 6),
          Text(
            'Entre le code à 6 caractères',
            style: Arcade.body(size: 13, color: Arcade.creamFaint),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: Arcade.title(size: 32, spacing: 10),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ABCDEF',
              hintStyle: Arcade.title(
                size: 32,
                spacing: 10,
                color: Arcade.creamFaint,
              ),
              filled: true,
              fillColor: Arcade.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Arcade.teal, width: 2),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: _ctrl.text.length == 6 ? 1 : 0.4,
            child: ArcadeButton(
              label: 'REJOINDRE',
              big: true,
              width: double.infinity,
              color: Arcade.teal,
              colorDeep: const Color(0xFF12A88E),
              textColor: const Color(0xFF06251F),
              onTap:
                  _ctrl.text.length == 6
                      ? () => Navigator.pop(context, _ctrl.text)
                      : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareSheet extends StatelessWidget {
  final CollectionModel collection;
  const _ShareSheet({required this.collection});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Arcade.bgDeep,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _grip(),
          const SizedBox(height: 20),
          Text(
            'Inviter dans « ${collection.name} »',
            style: Arcade.title(size: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Arcade.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Arcade.line),
            ),
            child: Column(
              children: [
                Text(
                  'CODE',
                  style: Arcade.pixel(
                    size: 10,
                    color: Arcade.creamDim,
                    spacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  collection.code,
                  style: Arcade.title(
                    size: 44,
                    spacing: 12,
                    color: Arcade.gold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _shareBtn(
            context,
            Icons.content_copy_rounded,
            'Copier le code',
            collection.code,
            'Code copié !',
          ),
          const SizedBox(height: 10),
          _shareBtn(
            context,
            Icons.link_rounded,
            'Copier le lien',
            collection.inviteLink,
            'Lien copié !',
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _shareBtn(
    BuildContext context,
    IconData icon,
    String label,
    String data,
    String done,
  ) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: data));
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(done)));
      },
      icon: Icon(icon, size: 18, color: Arcade.creamDim),
      label: Text(label, style: Arcade.body(color: Arcade.creamDim)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Arcade.line),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
