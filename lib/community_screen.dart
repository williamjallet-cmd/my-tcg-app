// community_screen.dart — découverte des collections communautaires
// (recherche, aperçu, rejoindre, noter). Écran autonome, ouvert depuis
// collections_screen.dart. Ne touche pas à collection_detail_screen.dart.

import 'package:flutter/material.dart';
import 'arcade_theme.dart';
import 'community_service.dart';
import 'press_effect.dart';
import 'star_rating.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final _service = CommunityService.instance;
  final _searchCtrl = TextEditingController();
  List<CommunityCollection> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _items = await _service.browsePublicCollections(search: _searchCtrl.text);
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

  Future<void> _join(CommunityCollection item) async {
    try {
      await _service.joinPublicCollection(item.collection.id);
      _showMsg('Collection rejointe ! 🎉');
      await _load();
    } catch (e) {
      _showMsg('Erreur : $e', error: true);
    }
  }

  Future<void> _rate(CommunityCollection item, double rating) async {
    try {
      await _service.rateCollection(item.collection.id, rating);
      await _load();
    } catch (e) {
      _showMsg('Erreur : $e', error: true);
    }
  }

  void _openPreview(CommunityCollection item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (_) => _CommunityPreviewSheet(
            item: item,
            onJoin: () => _join(item),
            onRate: (r) => _rate(item, r),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Arcade.bg,
      body: Stack(
        children: [
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
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Arcade.cream,
                        ),
                      ),
                      Text('COMMUNAUTÉ', style: Arcade.title(size: 20)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchCtrl,
                    style: Arcade.body(),
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une collection…',
                      hintStyle: Arcade.body(color: Arcade.creamFaint),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Arcade.creamFaint,
                      ),
                      filled: true,
                      fillColor: Arcade.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child:
                      _loading
                          ? const Center(
                            child: CircularProgressIndicator(
                              color: Arcade.gold,
                            ),
                          )
                          : _items.isEmpty
                          ? _emptyState()
                          : RefreshIndicator(
                            onRefresh: _load,
                            color: Arcade.gold,
                            backgroundColor: Arcade.surface,
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                              itemCount: _items.length,
                              itemBuilder:
                                  (_, i) => FadeInItem(
                                    index: i,
                                    child: _CommunityCard(
                                      item: _items[i],
                                      onTap: () => _openPreview(_items[i]),
                                      onJoin: () => _join(_items[i]),
                                    ),
                                  ),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.travel_explore_rounded,
            size: 48,
            color: Arcade.creamFaint,
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune collection publique pour le moment.',
            textAlign: TextAlign.center,
            style: Arcade.body(color: Arcade.creamDim),
          ),
        ],
      ),
    ),
  );
}

class _CommunityCard extends StatelessWidget {
  final CommunityCollection item;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  const _CommunityCard({
    required this.item,
    required this.onTap,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final col = item.collection;
    return PressableScale(
      pressedScale: 0.975,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Arcade.surface,
          borderRadius: BorderRadius.circular(Arcade.rCard),
          border: Border.all(color: Arcade.line),
          boxShadow: Arcade.cardShadow,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child:
                    col.imageUrl != null
                        ? Image.network(
                          col.imageUrl!,
                          fit: BoxFit.cover,
                          // ✅ Sans cacheWidth, une bannière de 2000 px se
                          // décodait en pleine résolution pour occuper 56 px.
                          // 168 = 56 × 3 (densité max des écrans visés).
                          cacheWidth: 168,
                          errorBuilder:
                              (_, __, ___) => Container(color: Arcade.surface2),
                        )
                        : Container(
                          color: Arcade.surface2,
                          child: const Icon(
                            Icons.style_rounded,
                            color: Arcade.gold,
                          ),
                        ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    col.name,
                    style: Arcade.title(size: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.owner?.displayName ?? 'Créateur inconnu',
                    style: Arcade.body(size: 12, color: Arcade.creamDim),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      StarRatingDisplay(
                        rating: item.avgRating,
                        ratingsCount: item.ratingsCount,
                        size: 14,
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.people_rounded,
                        size: 13,
                        color: Arcade.creamFaint,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${item.memberCount}',
                        style: Arcade.body(size: 12, color: Arcade.creamFaint),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (item.isMember)
              const Icon(
                Icons.check_circle_rounded,
                color: Arcade.teal,
                size: 26,
              )
            else
              ArcadeButton(
                label: 'REJOINDRE',
                color: Arcade.teal,
                colorDeep: const Color(0xFF12A88E),
                textColor: const Color(0xFF06251F),
                onTap: onJoin,
              ),
          ],
        ),
      ),
    );
  }
}

class _CommunityPreviewSheet extends StatefulWidget {
  final CommunityCollection item;
  final VoidCallback onJoin;
  final ValueChanged<double> onRate;

  const _CommunityPreviewSheet({
    required this.item,
    required this.onJoin,
    required this.onRate,
  });

  @override
  State<_CommunityPreviewSheet> createState() => _CommunityPreviewSheetState();
}

class _CommunityPreviewSheetState extends State<_CommunityPreviewSheet> {
  late double _myRating;

  @override
  void initState() {
    super.initState();
    _myRating = widget.item.myRating ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final col = item.collection;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Arcade.line,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(col.name, style: Arcade.title(size: 20)),
          const SizedBox(height: 6),
          Text(
            'Par ${item.owner?.displayName ?? "créateur inconnu"}',
            style: Arcade.body(size: 13, color: Arcade.creamDim),
          ),
          const SizedBox(height: 12),
          StarRatingDisplay(
            rating: item.avgRating,
            ratingsCount: item.ratingsCount,
            size: 18,
          ),
          const SizedBox(height: 16),
          if (col.description.isNotEmpty) ...[
            Text(col.description, style: Arcade.body(size: 13)),
            const SizedBox(height: 16),
          ],
          if (item.isMember) ...[
            Text(
              'TA NOTE',
              style: Arcade.pixel(size: 9, color: Arcade.creamDim, spacing: 2),
            ),
            const SizedBox(height: 8),
            StarRatingInput(
              initialRating: _myRating,
              onChanged: (r) {
                setState(() => _myRating = r);
                widget.onRate(r);
              },
            ),
            const SizedBox(height: 20),
          ] else
            ArcadeButton(
              label: 'REJOINDRE CETTE COLLECTION',
              big: true,
              width: double.infinity,
              color: Arcade.teal,
              colorDeep: const Color(0xFF12A88E),
              textColor: const Color(0xFF06251F),
              onTap: () {
                Navigator.pop(context);
                widget.onJoin();
              },
            ),
        ],
      ),
    );
  }
}
