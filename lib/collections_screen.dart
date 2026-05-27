// collections_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collection_service.dart';
import 'pack_system.dart';
import 'collection_detail_screen.dart';

const _palettes = [
  [Color(0xFF7C3AED), Color(0xFF2563EB)],
  [Color(0xFFDB2777), Color(0xFF7C3AED)],
  [Color(0xFF059669), Color(0xFF2563EB)],
  [Color(0xFFD97706), Color(0xFFDB2777)],
  [Color(0xFF0891B2), Color(0xFF7C3AED)],
  [Color(0xFFDC2626), Color(0xFFD97706)],
];
List<Color> _paletteFor(String id) {
  final idx = id.codeUnits.fold(0, (a, b) => a + b) % _palettes.length;
  return _palettes[idx];
}

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
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade800 : Colors.green.shade700,
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
            backgroundColor: const Color(0xFF1A1A2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              isOwner ? 'Supprimer ?' : 'Quitter ?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              isOwner
                  ? 'Tous les membres perdront l\'accès à « ${col.name} ».'
                  : 'Tu quitteras « ${col.name} ».',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  isOwner ? 'Supprimer' : 'Quitter',
                  style: const TextStyle(color: Colors.white),
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
      backgroundColor: const Color(0xFF080814),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            backgroundColor: const Color(0xFF080814),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: const Text(
                'Mes Collections',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: 0.3,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A0533), Color(0xFF080814)],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                onPressed: _load,
              ),
            ],
          ),
          if (_loading)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF7C3AED)),
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
                    palette: _paletteFor(_collections[i].id),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ScaleTransition(
            scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
            child: _fab('Rejoindre', Icons.group_add_rounded, [
              const Color(0xFF0891B2),
              const Color(0xFF2563EB),
            ], _joinByCode),
          ),
          const SizedBox(height: 12),
          ScaleTransition(
            scale: CurvedAnimation(parent: _fabAnim, curve: Curves.elasticOut),
            child: _fab('Créer', Icons.add_rounded, [
              const Color(0xFF7C3AED),
              const Color(0xFFDB2777),
            ], _createCollection),
          ),
        ],
      ),
    );
  }

  Widget _fab(
    String label,
    IconData icon,
    List<Color> colors,
    VoidCallback onTap,
  ) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: colors),
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: colors[0].withValues(alpha: 0.5),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback:
              (b) => const LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
              ).createShader(b),
          child: const Icon(Icons.auto_awesome, size: 80, color: Colors.white),
        ),
        const SizedBox(height: 24),
        const Text(
          'Aucune collection',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Crée ta première collection\nou rejoins celle d\'un ami !',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 15,
            height: 1.6,
          ),
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
//   TUILE COLLECTION
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CollectionCard extends StatefulWidget {
  final CollectionModel collection;
  final String myUserId;
  final List<Color> palette;
  final VoidCallback onTap, onLeaveOrDelete, onShare, onEdit;

  const _CollectionCard({
    required this.collection,
    required this.myUserId,
    required this.palette,
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
  // AJOUT : compteurs membres + cartes
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
      _timer = Timer.periodic(const Duration(seconds: 1), (_) async {
        final r2 = await PackSystem.timeUntilNextPack(widget.collection.id);
        final c2 = await PackSystem.canOpenPack(widget.collection.id);
        if (mounted)
          setState(() {
            _remaining = r2;
            _canOpen = c2;
          });
        if (c2) _timer?.cancel();
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
    final p = widget.palette;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p[0].withValues(alpha: 0.85),
              p[1].withValues(alpha: 0.85),
              Colors.black.withValues(alpha: 0.6),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: p[0].withValues(alpha: _canOpen ? 0.5 : 0.2),
              blurRadius: _canOpen ? 28 : 12,
              spreadRadius: _canOpen ? 2 : 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              if (widget.collection.imageUrl != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.18,
                    child: Image.network(
                      widget.collection.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                      ],
                      stops: const [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Ligne titre + badges ──────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.collection.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.collection.description.isNotEmpty)
                                Text(
                                  widget.collection.description,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.55),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            // Badge ★ Admin (sans le "3h")
                            if (_isOwner) ...[
                              _badge('★ Admin', null, Colors.amber),
                              const SizedBox(width: 6),
                            ],
                            // Badge membres
                            _badge(
                              '$_memberCount membre${_memberCount != 1 ? 's' : ''}',
                              Icons.people_rounded,
                              Colors.white54,
                            ),
                            const SizedBox(width: 6),
                            PopupMenuButton<String>(
                              color: const Color(0xFF1A1A2E),
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.white70,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (v) {
                                if (v == 'share') widget.onShare();
                                if (v == 'edit') widget.onEdit();
                                if (v == 'leave') widget.onLeaveOrDelete();
                              },
                              itemBuilder:
                                  (_) => [
                                    const PopupMenuItem(
                                      value: 'share',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.share,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                          SizedBox(width: 10),
                                          Text(
                                            'Partager',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isOwner)
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.edit_rounded,
                                              color: Colors.white54,
                                              size: 18,
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                              'Modifier',
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'leave',
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isOwner
                                                ? Icons.delete
                                                : Icons.exit_to_app,
                                            color: Colors.red,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            _isOwner ? 'Supprimer' : 'Quitter',
                                            style: const TextStyle(
                                              color: Colors.red,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                            ),
                          ],
                        ),
                      ],
                    ),

                    const Spacer(),

                    // ── Ligne bas : pack + code ───────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _canOpen ? _availBadge() : _timerBadge(),
                              // Barre de progression cartes x/x
                              if (_totalCards > 0) ...[
                                const SizedBox(height: 8),
                                _cardProgressBar(),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: widget.onShare,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'CODE',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 8,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.collection.code,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white.withValues(alpha: 0.3),
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Appuie pour voir la collection',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.3),
                            fontSize: 10,
                          ),
                        ),
                      ],
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

  // Badge générique — icon optionnel (null = juste le texte avec l'étoile dedans)
  Widget _badge(String label, IconData? icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  // Barre progression cartes collectées
  Widget _cardProgressBar() {
    final pct =
        _totalCards > 0 ? (_obtainedCards / _totalCards).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.style_rounded, color: Colors.white38, size: 11),
            const SizedBox(width: 4),
            Text(
              '$_obtainedCards / $_totalCards cartes',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 4,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
          ),
        ),
      ],
    );
  }

  Widget _availBadge() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
    ),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.auto_awesome, color: Colors.white, size: 14),
        SizedBox(width: 6),
        Text(
          'Pack disponible !',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );

  Widget _timerBadge() => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.hourglass_bottom_rounded,
          color: Colors.white54,
          size: 14,
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prochain pack',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
              ),
            ),
            Text(
              PackSystem.formatDuration(_remaining),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
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
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red.shade800,
          ),
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
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Modifier la collection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white38),
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
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(
                  children: [
                    if (_newImageBytes != null)
                      Positioned.fill(
                        child: Image.memory(_newImageBytes!, fit: BoxFit.cover),
                      )
                    else if (widget.collection.imageUrl != null)
                      Positioned.fill(
                        child: Image.network(
                          widget.collection.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.3),
                      ),
                    ),
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _newImageBytes != null
                                ? '✅ Nouvelle image sélectionnée'
                                : (widget.collection.imageUrl != null
                                    ? 'Changer l\'image'
                                    : 'Ajouter une image'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                letterSpacing: 2,
              ),
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient:
                            sel
                                ? const LinearGradient(
                                  colors: [
                                    Color(0xFF7C3AED),
                                    Color(0xFFDB2777),
                                  ],
                                )
                                : null,
                        color:
                            sel ? null : Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              sel
                                  ? Colors.transparent
                                  : Colors.white.withValues(alpha: 0.1),
                        ),
                        boxShadow:
                            sel
                                ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF7C3AED,
                                    ).withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  ),
                                ]
                                : [],
                      ),
                      child: Text(
                        '${h}h',
                        style: TextStyle(
                          color:
                              sel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.5),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Membres peuvent ajouter des cartes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Sinon, seul toi peux ajouter',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _membersCanAdd,
                  onChanged: (v) => setState(() => _membersCanAdd = v),
                  activeColor: const Color(0xFF7C3AED),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _saving ? null : _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child:
                      _saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : const Text(
                            'Enregistrer les modifications',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                ),
              ),
            ),
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
      backgroundColor: const Color(0xFF080814),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080814),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Nouvelle collection',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
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
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Créer',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                            colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                          )
                          : null,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      if (_imageBytes != null)
                        Positioned.fill(
                          child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                        ),
                      if (_imageBytes != null)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.35),
                          ),
                        ),
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _imageBytes != null
                                  ? Icons.edit_rounded
                                  : Icons.add_photo_alternate_rounded,
                              color: Colors.white,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _imageBytes != null
                                  ? 'Changer l\'image'
                                  : 'Ajouter une image de couverture',
                              style: TextStyle(
                                color:
                                    _imageBytes != null
                                        ? Colors.white70
                                        : Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (_nameCtrl.text.isNotEmpty)
                              Text(
                                _nameCtrl.text,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          gradient:
                              sel
                                  ? const LinearGradient(
                                    colors: [
                                      Color(0xFF7C3AED),
                                      Color(0xFFDB2777),
                                    ],
                                  )
                                  : null,
                          color:
                              sel ? null : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                sel
                                    ? Colors.transparent
                                    : Colors.white.withValues(alpha: 0.1),
                          ),
                          boxShadow:
                              sel
                                  ? [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF7C3AED,
                                      ).withValues(alpha: 0.4),
                                      blurRadius: 12,
                                    ),
                                  ]
                                  : [],
                        ),
                        child: Text(
                          '${h}h',
                          style: TextStyle(
                            color:
                                sel
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.people_rounded,
                    color: Colors.white54,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Membres peuvent ajouter des cartes',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Sinon, seul l\'admin peut ajouter',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _membersCanAdd,
                    onChanged: (v) => setState(() => _membersCanAdd = v),
                    activeColor: const Color(0xFF7C3AED),
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

  Widget _sectionTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.3,
    ),
  );

  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    void Function(String)? onChanged,
  }) => TextField(
    controller: c,
    onChanged: onChanged,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF7C3AED), width: 1.5),
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   JOIN + SHARE SHEETS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          const SizedBox(height: 20),
          ShaderMask(
            shaderCallback:
                (b) => const LinearGradient(
                  colors: [Color(0xFF0891B2), Color(0xFF2563EB)],
                ).createShader(b),
            child: const Icon(
              Icons.group_add_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rejoindre une collection',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Entre le code à 6 caractères',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'ABCDEF',
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.15),
                letterSpacing: 10,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF0891B2),
                  width: 2,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AnimatedOpacity(
              opacity: _ctrl.text.length == 6 ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0891B2), Color(0xFF2563EB)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap:
                        _ctrl.text.length == 6
                            ? () => Navigator.pop(context, _ctrl.text)
                            : null,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Rejoindre',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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
        color: Color(0xFF0F0F1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          const SizedBox(height: 20),
          Text(
            'Inviter dans « ${collection.name} »',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Column(
              children: [
                Text(
                  'CODE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 10,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 8),
                ShaderMask(
                  shaderCallback:
                      (b) => const LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                      ).createShader(b),
                  child: Text(
                    collection.code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _btn(Icons.content_copy_rounded, 'Copier le code', () {
            Clipboard.setData(ClipboardData(text: collection.code));
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Code copié !')));
          }),
          const SizedBox(height: 10),
          _btn(Icons.link_rounded, 'Copier le lien', () {
            Clipboard.setData(ClipboardData(text: collection.inviteLink));
            Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Lien copié !')));
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: Colors.white70),
      label: Text(label, style: const TextStyle(color: Colors.white70)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
