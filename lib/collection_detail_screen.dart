// collection_detail_screen.dart
// FEATURES : drag mobile, panneau couches, inspection 3D cartes collectées

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'collection_service.dart';
import 'pack_system.dart';
import 'card_storage.dart';
import 'card_model.dart';
import 'pack_opening_screen.dart';
import 'card_inspector_screen.dart';

const _dropRates = {
  Rarity.common: 50,
  Rarity.uncommon: 28,
  Rarity.rare: 14,
  Rarity.epic: 6,
  Rarity.legendary: 2,
};
const _dropLabels = {
  Rarity.common: '50%',
  Rarity.uncommon: '28%',
  Rarity.rare: '14%',
  Rarity.epic: '6%',
  Rarity.legendary: '2%',
};

SavedCard _weightedPick(List<SavedCard> pool, math.Random rng) {
  final byR = <Rarity, List<SavedCard>>{};
  for (final c in pool) {
    byR.putIfAbsent(c.rarity, () => []).add(c);
  }
  int total = byR.keys.fold(0, (s, r) => s + (_dropRates[r] ?? 0));
  if (total == 0) return pool[rng.nextInt(pool.length)];
  int roll = rng.nextInt(total);
  for (final r in [
    Rarity.common,
    Rarity.uncommon,
    Rarity.rare,
    Rarity.epic,
    Rarity.legendary,
  ]) {
    if (!byR.containsKey(r)) continue;
    roll -= _dropRates[r]!;
    if (roll < 0) {
      final p = byR[r]!;
      return p[rng.nextInt(p.length)];
    }
  }
  return pool[rng.nextInt(pool.length)];
}

const _palettes = [
  [Color(0xFF7C3AED), Color(0xFF2563EB)],
  [Color(0xFFDB2777), Color(0xFF7C3AED)],
  [Color(0xFF059669), Color(0xFF2563EB)],
  [Color(0xFFD97706), Color(0xFFDB2777)],
  [Color(0xFF0891B2), Color(0xFF7C3AED)],
  [Color(0xFFDC2626), Color(0xFFD97706)],
];
List<Color> _pal(String id) =>
    _palettes[id.codeUnits.fold(0, (a, b) => a + b) % _palettes.length];

String _obtKey(String colId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return 'obtained_${uid}_$colId';
}

String _catKey(String colId) {
  final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
  return 'local_cat_${uid}_$colId';
}

class CollectionDetailScreen extends StatefulWidget {
  final CollectionModel collection;
  final String myUserId;
  const CollectionDetailScreen({
    super.key,
    required this.collection,
    required this.myUserId,
  });
  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Duration _remaining = Duration.zero;
  bool _canOpen = false;
  Timer? _timer;
  List<SavedCard> _allCards = [];
  List<SavedCard> _obtainedCards = [];
  Set<String> _catalogueIds = {};
  bool _loading = true;
  String _sortBy = 'rarity';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _syncAndLoad();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _syncAndLoad() async {
    await PackSystem.syncFromSupabase(widget.collection.id);
    _startTimer();
    await _loadCards();
  }

  void _startTimer() async {
    final r = await PackSystem.timeUntilNextPack(widget.collection.id);
    final c = await PackSystem.canOpenPack(widget.collection.id);
    if (mounted)
      setState(() {
        _remaining = r;
        _canOpen = c;
      });
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

  Future<void> _loadCards() async {
    if (mounted) setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    List<SavedCard> all = await CardStorage.loadCards();
    Set<String> obtIds =
        (prefs.getStringList(_obtKey(widget.collection.id)) ?? []).toSet();
    try {
      final remoteEntries = await CollectionService.instance.loadUserCards(
        widget.collection.id,
      );
      for (final entry in remoteEntries) {
        obtIds.add(entry.cardId);
        if (!all.any((c) => c.id == entry.cardId)) {
          final reconstructed = entry.toSavedCard();
          if (reconstructed != null) {
            await CardStorage.addCard(reconstructed);
            all.add(reconstructed);
          }
        }
      }
      await prefs.setStringList(_obtKey(widget.collection.id), obtIds.toList());
    } catch (_) {}
    Set<String> catIds = {};
    try {
      catIds.addAll(
        await CollectionService.instance.getCollectionCardIds(
          widget.collection.id,
        ),
      );
    } catch (_) {}
    catIds.addAll(prefs.getStringList(_catKey(widget.collection.id)) ?? []);
    if (mounted) {
      setState(() {
        _allCards = all;
        _obtainedCards = all.where((c) => obtIds.contains(c.id)).toList();
        _catalogueIds = catIds;
        _loading = false;
      });
    }
  }

  List<SavedCard> get _catalogue {
    if (_catalogueIds.isEmpty) return _allCards;
    return _allCards.where((c) => _catalogueIds.contains(c.id)).toList();
  }

  Future<void> _openPack() async {
    final pool = _catalogue;
    if (pool.isEmpty) {
      _msg('❌ Crée des cartes dans l\'onglet ✏️ d\'abord !', err: true);
      return;
    }
    final rng = math.Random();
    final packCards = List.generate(3, (_) => _weightedPick(pool, rng));
    await PackSystem.setLastOpenedTime(widget.collection.id);
    final prefs = await SharedPreferences.getInstance();
    final key = _obtKey(widget.collection.id);
    final existing = prefs.getStringList(key) ?? [];
    await prefs.setStringList(
      key,
      {...existing, ...packCards.map((c) => c.id)}.toList(),
    );
    _startTimer();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PackOpeningScreen(
              cards: packCards,
              collectionId: widget.collection.id,
              packName: widget.collection.name,
              packColor: _pal(widget.collection.id).first,
            ),
      ),
    );
    await _loadCards();
    _startTimer();
  }

  void _msg(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: err ? Colors.red.shade800 : Colors.green.shade700,
      ),
    );
  }

  List<SavedCard> _sorted(List<SavedCard> cards) {
    final l = [...cards];
    if (_sortBy == 'rarity')
      l.sort((a, b) => b.rarity.index.compareTo(a.rarity.index));
    if (_sortBy == 'name') l.sort((a, b) => a.name.compareTo(b.name));
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final p = _pal(widget.collection.id);
    return Scaffold(
      backgroundColor: const Color(0xFF080814),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_appBar(p)],
        body: Column(
          children: [
            Container(
              color: const Color(0xFF0F0F1E),
              child: TabBar(
                controller: _tabCtrl,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: p[0],
                tabs: const [
                  Tab(text: '🎁 Pack'),
                  Tab(text: '🃏 Cartes'),
                  Tab(text: '✏️ Créer'),
                ],
              ),
            ),
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
                        children: [_packTab(p), _cardsTab(), _createTab(p)],
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _appBar(List<Color> p) => SliverAppBar(
    expandedHeight: 150,
    pinned: true,
    backgroundColor: const Color(0xFF080814),
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
      onPressed: () => Navigator.pop(context),
    ),
    flexibleSpace: FlexibleSpaceBar(
      titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
      title: Text(
        widget.collection.name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      background: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    p[0].withValues(alpha: 0.8),
                    p[1].withValues(alpha: 0.5),
                    const Color(0xFF080814),
                  ],
                ),
              ),
            ),
          ),
          if (widget.collection.imageUrl != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: Image.network(
                  widget.collection.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Row(
              children: [
                _chip(widget.collection.cooldownLabel, Icons.timer_rounded),
                const SizedBox(width: 8),
                _chip('${_catalogue.length} cartes', Icons.style_rounded),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _chip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 11),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _packTab(List<Color> p) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _canOpen ? _openBtn(p) : _timerWidget(),
        const SizedBox(height: 28),
        _secTitle('Taux de drop'),
        const SizedBox(height: 12),
        ..._dropRows(),
        const SizedBox(height: 28),
        _secTitle('Code d\'invitation'),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.06),
                Colors.white.withValues(alpha: 0.03),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
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
                    (b) => LinearGradient(colors: p).createShader(b),
                child: Text(
                  widget.collection.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<Widget> _dropRows() =>
      Rarity.values.reversed.map((r) {
        final rc = _rc(r);
        final pct = _dropLabels[r]!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: rc, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(
                  _rn(r),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _dropRates[r]! / 100.0,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(
                      rc.withValues(alpha: 0.7),
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 36,
                child: Text(
                  pct,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: rc,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList();

  Widget _openBtn(List<Color> p) => GestureDetector(
    onTap: _openPack,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: p),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: p[0].withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 22),
          SizedBox(width: 10),
          Text(
            'Ouvrir un booster',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _timerWidget() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.hourglass_bottom_rounded,
          color: Colors.white38,
          size: 20,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prochain booster dans',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
            Text(
              PackSystem.formatDuration(_remaining),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _secTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.w800,
    ),
  );

  // ── Onglet Cartes — FEATURE 2 : inspection 3D ─────────────────────────────
  Widget _cardsTab() => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: const Color(0xFF0A0A18),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'Trier : ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                ),
              ),
              ...[
                ('rarity', '✨ Rareté'),
                ('name', '🔤 Nom'),
                ('date', '📅 Date'),
              ].map((item) {
                final sel = _sortBy == item.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _sortBy = item.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color:
                            sel
                                ? const Color(
                                  0xFF7C3AED,
                                ).withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              sel
                                  ? const Color(
                                    0xFF7C3AED,
                                  ).withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        item.$2,
                        style: TextStyle(
                          color:
                              sel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      Expanded(child: _cardGrid()),
    ],
  );

  Widget _cardGrid() {
    final obtIds = _obtainedCards.map((c) => c.id).toSet();
    final cards = _sorted(_catalogue);
    if (cards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.style_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.1),
            ),
            const SizedBox(height: 12),
            Text(
              'Aucune carte\nCrée-en dans l\'onglet ✏️',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.7,
      ),
      itemCount: cards.length,
      itemBuilder:
          (_, i) =>
              _CardTile(card: cards[i], revealed: obtIds.contains(cards[i].id)),
    );
  }

  Widget _createTab(List<Color> p) => _CardCreator(
    palette: p,
    collectionId: widget.collection.id,
    onSaved: () {
      _msg('✅ Carte ajoutée !');
      _loadCards();
      _tabCtrl.animateTo(1);
    },
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   TUILE CARTE — FEATURE 2 : inspection 3D au tap
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CardTile extends StatelessWidget {
  final SavedCard card;
  final bool revealed;
  const _CardTile({required this.card, required this.revealed});

  Color get _rc {
    switch (card.rarity) {
      case Rarity.legendary:
        return const Color(0xFFFFD700);
      case Rarity.epic:
        return const Color(0xFF9C27B0);
      case Rarity.rare:
        return const Color(0xFF2196F3);
      case Rarity.uncommon:
        return const Color(0xFF4CAF50);
      case Rarity.common:
        return const Color(0xFF9E9E9E);
    }
  }

  String get _rl {
    switch (card.rarity) {
      case Rarity.legendary:
        return 'Légendaire';
      case Rarity.epic:
        return 'Épique';
      case Rarity.rare:
        return 'Rare';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.common:
        return 'Commun';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!revealed) return _back();
    // FEATURE 2 : tap → inspection 3D
    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (_) => CardInspectorScreen(
                    frontCard: SavedCardFrontWidget(
                      card: card,
                      width: 300,
                      height: 420,
                    ),
                    backCard: SavedCardBackWidget(
                      card: card,
                      width: 300,
                      height: 420,
                    ),
                  ),
            ),
          ),
      child: Stack(
        children: [
          _front(),
          // Badge "inspecter"
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.view_in_ar,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 9,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '3D',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _front() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _rc, width: 2),
      color: const Color(0xFF16213E),
      boxShadow: [BoxShadow(color: _rc.withValues(alpha: 0.3), blurRadius: 6)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        children: [
          if (card.imageBytes != null)
            Positioned.fill(
              child: Image.memory(card.imageBytes!, fit: BoxFit.cover),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.95),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _rc.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _rl,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 6,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _back() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A1A3E), Color(0xFF0D0D1C)],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.1),
        width: 1.5,
      ),
    ),
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.help_outline_rounded,
            color: Colors.white.withValues(alpha: 0.15),
            size: 28,
          ),
          Text(
            '?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.1),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   COUCHE IMAGE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _ImgLayer {
  Uint8List bytes;
  double x = 0, y = 0, scale = 1.0;
  double opacity = 1.0;
  _ImgLayer({required this.bytes});
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CRÉATEUR DE CARTE — FEATURE 1 : drag mobile + panneau couches
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CardCreator extends StatefulWidget {
  final List<Color> palette;
  final String collectionId;
  final VoidCallback onSaved;
  const _CardCreator({
    required this.palette,
    required this.collectionId,
    required this.onSaved,
  });
  @override
  State<_CardCreator> createState() => _CardCreatorState();
}

class _CardCreatorState extends State<_CardCreator>
    with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController(text: 'Ma Carte');
  Rarity _rarity = Rarity.common;
  bool _showBack = false;
  bool _saving = false;

  final List<_ImgLayer> _images = [];
  final List<TextZone> _textZones = [];

  // Couche sélectionnée (-1 = aucune, index >= 0 = image, -2 = nom, -3 = rareté)
  int _selectedLayer = -1;

  double _nameX = 8, _nameY = 200;
  double _rarityX = 8, _rarityY = 222;

  int _selectedGrad = -1;
  int _backColor = 0xFF16213E;
  Uint8List? _backImageBytes;

  // Personnalisation de la bordure
  int _borderColorIndex = -1; // -1 = couleur rareté par défaut
  static const _borderColors = [
    Colors.white,
    Color(0xFFFFD700),
    Color(0xFFFF3333),
    Color(0xFF33FF99),
    Color(0xFF3399FF),
    Color(0xFFFF33CC),
    Color(0xFF000000),
    Color(0xFF888888),
  ];

  late AnimationController _legendaryCtrl;
  static const double _cW = 194, _cH = 284;

  final _gradients = [
    [const Color(0xFF7C3AED), const Color(0xFF2563EB)],
    [const Color(0xFFDB2777), const Color(0xFF7C3AED)],
    [const Color(0xFF059669), const Color(0xFF2563EB)],
    [const Color(0xFFD97706), const Color(0xFFDB2777)],
    [const Color(0xFF0891B2), const Color(0xFF2563EB)],
    [const Color(0xFF080814), const Color(0xFF1A1A3E)],
  ];

  final _backColors = [
    0xFF16213E,
    0xFF1A1A2E,
    0xFF0F3460,
    0xFF533483,
    0xFF2C3E50,
    0xFF1B2631,
    0xFF4A235A,
    0xFF1A5276,
  ];

  // Polices disponibles pour les textes
  static const _fontFamilies = [
    (null, 'Défaut'),
    ('serif', 'Serif'),
    ('monospace', 'Mono'),
    ('cursive', 'Cursif'),
  ];

  @override
  void initState() {
    super.initState();
    _legendaryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _legendaryCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Color _rc(Rarity r) {
    switch (r) {
      case Rarity.legendary:
        return const Color(0xFFFFD700);
      case Rarity.epic:
        return const Color(0xFF9C27B0);
      case Rarity.rare:
        return const Color(0xFF2196F3);
      case Rarity.uncommon:
        return const Color(0xFF4CAF50);
      case Rarity.common:
        return const Color(0xFF9E9E9E);
    }
  }

  String _rn(Rarity r) {
    switch (r) {
      case Rarity.legendary:
        return 'Légendaire';
      case Rarity.epic:
        return 'Épique';
      case Rarity.rare:
        return 'Rare';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.common:
        return 'Commun';
    }
  }

  Color get _currentBorderColor =>
      _borderColorIndex >= 0 ? _borderColors[_borderColorIndex] : _rc(_rarity);

  Future<void> _addImage({bool isBack = false}) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      if (isBack) {
        _backImageBytes = bytes;
      } else {
        _images.add(_ImgLayer(bytes: bytes));
        _selectedLayer =
            _images.length - 1; // auto-sélectionne la nouvelle couche
      }
    });
  }

  void _addText() {
    final zone = TextZone(
      text: 'Texte',
      x: 40,
      y: 80 + _textZones.length * 30.0,
      fontSize: 13,
      color: 0xFFFFFFFF,
    );
    setState(() => _textZones.add(zone));
    _editText(_textZones.length - 1);
  }

  void _editText(int idx) {
    final zone = _textZones[idx];
    final ctrl = TextEditingController(text: zone.text);
    Color selColor = Color(zone.color);
    double fontSize = zone.fontSize;
    String? fontFamily = zone.fontFamily;

    showDialog(
      context: context,
      builder:
          (_) => StatefulBuilder(
            builder:
                (ctx, setD) => AlertDialog(
                  backgroundColor: const Color(0xFF16213E),
                  title: const Text(
                    'Modifier le texte',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: ctrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Texte',
                            labelStyle: TextStyle(color: Colors.white54),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.white38),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Taille',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Slider(
                          value: fontSize,
                          min: 8,
                          max: 36,
                          activeColor: const Color(0xFF7C3AED),
                          onChanged: (v) {
                            setD(() => fontSize = v);
                            setState(() => zone.fontSize = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        // Sélecteur de police
                        const Text(
                          'Police',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children:
                              _fontFamilies.map((f) {
                                final sel = fontFamily == f.$1;
                                return GestureDetector(
                                  onTap: () {
                                    setD(() => fontFamily = f.$1);
                                    setState(() => zone.fontFamily = f.$1);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          sel
                                              ? const Color(
                                                0xFF7C3AED,
                                              ).withValues(alpha: 0.3)
                                              : Colors.white.withValues(
                                                alpha: 0.06,
                                              ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            sel
                                                ? const Color(0xFF7C3AED)
                                                : Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                      ),
                                    ),
                                    child: Text(
                                      f.$2,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontFamily: f.$1,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Couleur',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Colors.white,
                                    Colors.black,
                                    Colors.yellow,
                                    Colors.red,
                                    Colors.blue,
                                    Colors.green,
                                    Colors.orange,
                                    Colors.purple,
                                    Colors.pink,
                                    Colors.cyan,
                                    Colors.teal,
                                    Colors.amber,
                                  ]
                                  .map(
                                    (c) => GestureDetector(
                                      onTap: () {
                                        setD(() => selColor = c);
                                        setState(
                                          () => zone.color = c.toARGB32(),
                                        );
                                      },
                                      child: Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border:
                                              selColor == c
                                                  ? Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  )
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => _textZones.removeAt(idx));
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'Supprimer',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          zone.text = ctrl.text;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(color: Color(0xFF7C3AED)),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ── Panneau couches ────────────────────────────────────────────────────────
  Widget _buildLayerPanel() {
    if (_images.isEmpty && _textZones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          'Ajoute des photos ou du texte pour voir les couches ici',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: 11,
          ),
        ),
      );
    }
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // Couches Nom et Rareté
          _layerChip(
            icon: const Icon(
              Icons.badge_rounded,
              color: Colors.white,
              size: 14,
            ),
            label: 'Nom',
            selected: _selectedLayer == -2,
            onTap:
                () => setState(
                  () => _selectedLayer = _selectedLayer == -2 ? -1 : -2,
                ),
            onDelete: null,
          ),
          _layerChip(
            icon: const Icon(
              Icons.label_rounded,
              color: Colors.white,
              size: 14,
            ),
            label: 'Rareté',
            selected: _selectedLayer == -3,
            onTap:
                () => setState(
                  () => _selectedLayer = _selectedLayer == -3 ? -1 : -3,
                ),
            onDelete: null,
          ),
          // Couches images
          for (var i = 0; i < _images.length; i++)
            _layerChip(
              icon: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  _images[i].bytes,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                ),
              ),
              label: 'Photo ${i + 1}',
              selected: _selectedLayer == i,
              onTap:
                  () => setState(
                    () => _selectedLayer = _selectedLayer == i ? -1 : i,
                  ),
              onDelete:
                  () => setState(() {
                    _images.removeAt(i);
                    _selectedLayer = -1;
                  }),
            ),
          // Couches textes
          for (var i = 0; i < _textZones.length; i++)
            _layerChip(
              icon: const Icon(
                Icons.text_fields_rounded,
                color: Colors.white,
                size: 14,
              ),
              label: 'Texte ${i + 1}',
              selected: false,
              onTap: () => _editText(i),
              onDelete: () => setState(() => _textZones.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _layerChip({
    required Widget icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: EdgeInsets.only(
          left: 8,
          right: onDelete != null ? 6 : 10,
          top: 6,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          color:
              selected
                  ? const Color(0xFF7C3AED).withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected
                    ? const Color(0xFF7C3AED)
                    : Colors.white.withValues(alpha: 0.15),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.white.withValues(alpha: 0.45),
                  size: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Canvas carte (drag mobile fix : en dehors du scroll) ──────────────────
  Widget _buildFront() {
    final rc = _currentBorderColor;

    Widget inner = SizedBox(
      width: _cW,
      height: _cH,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Container(
          decoration:
              _selectedGrad >= 0
                  ? BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _gradients[_selectedGrad],
                    ),
                  )
                  : const BoxDecoration(
                    borderRadius: BorderRadius.all(Radius.circular(13)),
                    color: Color(0xFF1A1A2E),
                  ),
          child: Stack(
            children: [
              // Images
              ..._images.asMap().entries.map((e) {
                final i = e.key;
                final layer = e.value;
                final isSelected = _selectedLayer == i;
                return Positioned(
                  left: layer.x,
                  top: layer.y,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap:
                        () => setState(
                          () => _selectedLayer = isSelected ? -1 : i,
                        ),
                    onScaleUpdate:
                        (d) => setState(() {
                          layer.x = (layer.x + d.focalPointDelta.dx).clamp(
                            -_cW,
                            _cW * 2,
                          );
                          layer.y = (layer.y + d.focalPointDelta.dy).clamp(
                            -_cH,
                            _cH * 2,
                          );
                          if (d.scale != 1.0)
                            layer.scale = (layer.scale * d.scale).clamp(
                              0.1,
                              6.0,
                            );
                        }),
                    child: Stack(
                      children: [
                        Opacity(
                          opacity: layer.opacity,
                          child: Transform.scale(
                            scale: layer.scale,
                            alignment: Alignment.topLeft,
                            child: Image.memory(
                              layer.bytes,
                              width: _cW,
                              fit: BoxFit.fitWidth,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFF7C3AED),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              // Textes
              ..._textZones.asMap().entries.map((e) {
                final i = e.key;
                final zone = e.value;
                return Positioned(
                  left: zone.x,
                  top: zone.y,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _editText(i),
                    onPanUpdate:
                        (d) => setState(() {
                          zone.x = (zone.x + d.delta.dx).clamp(0, _cW - 20);
                          zone.y = (zone.y + d.delta.dy).clamp(0, _cH - 20);
                        }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        zone.text,
                        style: TextStyle(
                          color: Color(zone.color),
                          fontSize: zone.fontSize.clamp(8, 36),
                          fontFamily: zone.fontFamily,
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Dégradé bas
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Nom (draggable — FIX MOBILE)
              Positioned(
                left: _nameX,
                top: _nameY,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => setState(
                        () => _selectedLayer = _selectedLayer == -2 ? -1 : -2,
                      ),
                  onPanUpdate:
                      (d) => setState(() {
                        _nameX = (_nameX + d.delta.dx).clamp(0, _cW - 60);
                        _nameY = (_nameY + d.delta.dy).clamp(0, _cH - 20);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border:
                          _selectedLayer == -2
                              ? Border.all(
                                color: const Color(0xFF7C3AED),
                                width: 1.5,
                              )
                              : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _nameCtrl.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ),

              // Rareté (draggable — FIX MOBILE)
              Positioned(
                left: _rarityX,
                top: _rarityY,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap:
                      () => setState(
                        () => _selectedLayer = _selectedLayer == -3 ? -1 : -3,
                      ),
                  onPanUpdate:
                      (d) => setState(() {
                        _rarityX = (_rarityX + d.delta.dx).clamp(0, _cW - 60);
                        _rarityY = (_rarityY + d.delta.dy).clamp(0, _cH - 16);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _rc(_rarity),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          _selectedLayer == -3
                              ? Border.all(color: Colors.white, width: 1.5)
                              : null,
                    ),
                    child: Text(
                      _rn(_rarity),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_rarity == Rarity.legendary) {
      return AnimatedBuilder(
        animation: _legendaryCtrl,
        builder:
            (_, __) => SizedBox(
              width: _cW + 6,
              height: _cH + 6,
              child: Stack(
                children: [
                  Container(
                    width: _cW + 6,
                    height: _cH + 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: SweepGradient(
                        startAngle: _legendaryCtrl.value * 2 * math.pi,
                        colors: const [
                          Color(0xFFFFD700),
                          Color(0xFFFFF9C4),
                          Color(0xFFFF8F00),
                          Color(0xFFFFE082),
                          Color(0xFFFFF176),
                          Color(0xFFFFD700),
                        ],
                      ),
                    ),
                  ),
                  Center(child: inner),
                ],
              ),
            ),
      );
    }

    return SizedBox(
      width: _cW + 6,
      height: _cH + 6,
      child: Stack(
        children: [
          Container(
            width: _cW + 6,
            height: _cH + 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rc, width: 3),
              boxShadow: [
                BoxShadow(color: rc.withValues(alpha: 0.45), blurRadius: 14),
              ],
            ),
          ),
          Center(child: inner),
        ],
      ),
    );
  }

  Widget _buildBack() => Container(
    width: _cW,
    height: _cH,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Color(_backColor),
      border: Border.all(color: Colors.white24, width: 2),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          if (_backImageBytes != null)
            Positioned.fill(
              child: Image.memory(_backImageBytes!, fit: BoxFit.cover),
            ),
          if (_backImageBytes == null)
            const Center(
              child: Opacity(
                opacity: 0.2,
                child: Icon(Icons.style, size: 72, color: Colors.white),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Donne un nom à ta carte !'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final primaryBytes = _images.isNotEmpty ? _images.first.bytes : null;
      final extra =
          _images.length > 1
              ? _images
                  .sublist(1)
                  .map(
                    (l) => ExtraImage(
                      bytes: l.bytes,
                      x: l.x,
                      y: l.y,
                      scale: l.scale,
                    ),
                  )
                  .toList()
              : <ExtraImage>[];

      final card = SavedCard(
        id:
            '${DateTime.now().millisecondsSinceEpoch}_${math.Random().nextInt(99999)}',
        name: _nameCtrl.text.trim(),
        rarity: _rarity,
        effect: CardEffect.none,
        imageBytes: primaryBytes,
        imageX: _images.isNotEmpty ? _images.first.x : 0,
        imageY: _images.isNotEmpty ? _images.first.y : 0,
        imageScale: _images.isNotEmpty ? _images.first.scale : 1.0,
        extraImages: extra,
        backImageBytes: _backImageBytes,
        backColor: _backColor,
        nameX: _nameX,
        nameY: _nameY,
        rarityX: _rarityX,
        rarityY: _rarityY,
        textZones: List.from(_textZones),
      );

      await CardStorage.addCard(card);

      bool supabaseOk = false;
      try {
        await CollectionService.instance.addCardToCollection(
          widget.collectionId,
          card.id,
          card.name,
          _rn(_rarity),
        );
        supabaseOk = true;
      } catch (e) {
        debugPrint('Supabase link: $e');
      }

      if (!supabaseOk) {
        final prefs = await SharedPreferences.getInstance();
        final key = _catKey(widget.collectionId);
        final existing = prefs.getStringList(key) ?? [];
        existing.add(card.id);
        await prefs.setStringList(key, existing);
      }

      setState(() {
        _nameCtrl.text = 'Ma Carte';
        _images.clear();
        _textZones.clear();
        _backImageBytes = null;
        _nameX = 8;
        _nameY = 200;
        _rarityX = 8;
        _rarityY = 222;
        _rarity = Rarity.common;
        _selectedGrad = -1;
        _showBack = false;
        _selectedLayer = -1;
        _borderColorIndex = -1;
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build — FEATURE 1 : canvas EN DEHORS du scroll (fix drag mobile) ───────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toggle recto/verso
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _toggleBtn(
                'Recto',
                !_showBack,
                () => setState(() => _showBack = false),
              ),
              const SizedBox(width: 8),
              _toggleBtn(
                'Verso',
                _showBack,
                () => setState(() => _showBack = true),
              ),
            ],
          ),
        ),

        // Canvas carte — en dehors du scroll → drag fonctionne sur mobile
        Center(child: _showBack ? _buildBack() : _buildFront()),

        // Bouton 3D inspect
        TextButton.icon(
          onPressed:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CardInspectorScreen(
                        frontCard: _buildFront(),
                        backCard: _buildBack(),
                      ),
                ),
              ),
          icon: const Icon(Icons.view_in_ar, color: Colors.white38, size: 15),
          label: const Text(
            'Inspecter en 3D',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),

        // Panneau couches — aussi en dehors du scroll
        if (!_showBack) _buildLayerPanel(),

        // Séparateur
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.07)),

        // Paramètres scrollables
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_showBack) ...[
                  // Nom
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white),
                    decoration: _deco('Nom de la carte', Icons.badge_rounded),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 Glisse le nom et la rareté directement sur la carte',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Rareté
                  _secTitle('Rareté'),
                  const SizedBox(height: 8),
                  ...Rarity.values.map((r) {
                    final rc = _rc(r);
                    final sel = _rarity == r;
                    return GestureDetector(
                      onTap:
                          () => setState(() {
                            _rarity = r;
                            _borderColorIndex = -1;
                          }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color:
                              sel
                                  ? rc.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                sel ? rc : Colors.white.withValues(alpha: 0.08),
                            width: sel ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: rc,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _rn(r),
                              style: TextStyle(
                                color:
                                    sel
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.6),
                                fontSize: 13,
                                fontWeight:
                                    sel ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 80,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _dropRates[r]! / 100.0,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(
                                    rc.withValues(alpha: 0.7),
                                  ),
                                  minHeight: 5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 32,
                              child: Text(
                                _dropLabels[r]!,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: rc,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (sel) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.check_circle, color: rc, size: 16),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 18),

                  // Ajouter photo
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _addImage(),
                          icon: const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: Colors.white70,
                          ),
                          label: Text(
                            _images.isEmpty
                                ? 'Ajouter une photo'
                                : 'Ajouter une couche',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Opacité si une image est sélectionnée
                  if (_selectedLayer >= 0 &&
                      _selectedLayer < _images.length) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          Icons.opacity,
                          color: Colors.white.withValues(alpha: 0.5),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Opacité',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                        Expanded(
                          child: Slider(
                            value: _images[_selectedLayer].opacity,
                            min: 0.1,
                            max: 1.0,
                            activeColor: const Color(0xFF7C3AED),
                            onChanged:
                                (v) => setState(
                                  () => _images[_selectedLayer].opacity = v,
                                ),
                          ),
                        ),
                        Text(
                          '${(_images[_selectedLayer].opacity * 100).round()}%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),

                  // Ajouter texte
                  OutlinedButton.icon(
                    onPressed: _addText,
                    icon: const Icon(
                      Icons.text_fields_rounded,
                      color: Colors.white70,
                    ),
                    label: const Text(
                      'Ajouter du texte',
                      style: TextStyle(color: Colors.white70),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Fond dégradé
                  _secTitle('Fond'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _selectedGrad = -1),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A2E),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedGrad == -1
                                      ? Colors.white
                                      : Colors.white24,
                              width: _selectedGrad == -1 ? 3 : 1,
                            ),
                          ),
                          child:
                              _selectedGrad == -1
                                  ? const Icon(
                                    Icons.close,
                                    color: Colors.white38,
                                    size: 14,
                                  )
                                  : null,
                        ),
                      ),
                      ...List.generate(
                        _gradients.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _selectedGrad = i),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: _gradients[i],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _selectedGrad == i
                                        ? Colors.white
                                        : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Couleur de bordure personnalisée
                  _secTitle('Couleur de bordure'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      // Option "couleur rareté"
                      GestureDetector(
                        onTap: () => setState(() => _borderColorIndex = -1),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _rc(_rarity),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _borderColorIndex == -1
                                      ? Colors.white
                                      : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child:
                              _borderColorIndex == -1
                                  ? const Icon(
                                    Icons.auto_awesome,
                                    color: Colors.white,
                                    size: 14,
                                  )
                                  : null,
                        ),
                      ),
                      ...List.generate(
                        _borderColors.length,
                        (i) => GestureDetector(
                          onTap: () => setState(() => _borderColorIndex = i),
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _borderColors[i],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    _borderColorIndex == i
                                        ? Colors.white
                                        : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Verso
                  _secTitle('Couleur de fond'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children:
                        _backColors
                            .map(
                              (c) => GestureDetector(
                                onTap: () => setState(() => _backColor = c),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          _backColor == c
                                              ? Colors.white
                                              : Colors.white24,
                                      width: _backColor == c ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _addImage(isBack: true),
                      icon: const Icon(
                        Icons.photo_library_rounded,
                        color: Colors.white70,
                      ),
                      label: Text(
                        _backImageBytes != null
                            ? '✅ Image verso — changer'
                            : 'Image verso (optionnel)',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                // Bouton sauvegarder
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: widget.palette),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: widget.palette[0].withValues(alpha: 0.5),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child:
                            _saving
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_circle,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Ajouter à la collection',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggleBtn(
    String label,
    bool active,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        gradient: active ? LinearGradient(colors: widget.palette) : null,
        color: active ? null : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              active ? Colors.transparent : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  );

  Widget _secTitle(String t) => Text(
    t,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
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
  );
}

// Helpers globaux
Color _rc(Rarity r) {
  switch (r) {
    case Rarity.legendary:
      return const Color(0xFFFFD700);
    case Rarity.epic:
      return const Color(0xFF9C27B0);
    case Rarity.rare:
      return const Color(0xFF2196F3);
    case Rarity.uncommon:
      return const Color(0xFF4CAF50);
    case Rarity.common:
      return const Color(0xFF9E9E9E);
  }
}

String _rn(Rarity r) {
  switch (r) {
    case Rarity.legendary:
      return 'Légendaire';
    case Rarity.epic:
      return 'Épique';
    case Rarity.rare:
      return 'Rare';
    case Rarity.uncommon:
      return 'Peu commun';
    case Rarity.common:
      return 'Commun';
  }
}
