// collection_detail_screen.dart
// ✦ 3 onglets : Pack · Cartes · Créer (images multiples, zones de texte, drag) ✦

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

  // FIX CARTES : sync depuis Supabase + reconstruction des cartes manquantes localement
  Future<void> _loadCards() async {
    if (mounted) setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();

    // 1. Charge les cartes locales
    List<SavedCard> all = await CardStorage.loadCards();

    // 2. Sync cartes obtenues depuis Supabase
    Set<String> obtIds =
        (prefs.getStringList(_obtKey(widget.collection.id)) ?? []).toSet();
    try {
      final remoteEntries = await CollectionService.instance.loadUserCards(
        widget.collection.id,
      );
      for (final entry in remoteEntries) {
        obtIds.add(entry.cardId);
        // Si la carte existe dans Supabase mais pas localement → reconstruction
        if (!all.any((c) => c.id == entry.cardId)) {
          final reconstructed = entry.toSavedCard();
          if (reconstructed != null) {
            await CardStorage.addCard(reconstructed);
            all.add(reconstructed);
          }
        }
      }
      // Sauvegarde les IDs obtenus en cache local
      await prefs.setStringList(_obtKey(widget.collection.id), obtIds.toList());
    } catch (_) {}

    // 3. Catalogue : Supabase + fallback local
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
    final updated = {...existing, ...packCards.map((c) => c.id)}.toList();
    await prefs.setStringList(key, updated);

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

class _ImgLayer {
  Uint8List bytes;
  double x = 0, y = 0, scale = 1.0;
  bool selected = false;
  _ImgLayer({required this.bytes});
}

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

  double _nameX = 8, _nameY = 200;
  double _rarityX = 8, _rarityY = 222;

  int _selectedGrad = -1;
  int _backColor = 0xFF16213E;
  Uint8List? _backImageBytes;

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

  Widget _buildFront() {
    final rc = _rc(_rarity);

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
              ..._images.asMap().entries.map((e) {
                final i = e.key;
                final layer = e.value;
                return Positioned(
                  left: layer.x,
                  top: layer.y,
                  child: GestureDetector(
                    onScaleUpdate:
                        (d) => setState(() {
                          layer.x += d.focalPointDelta.dx;
                          layer.y += d.focalPointDelta.dy;
                          layer.scale = (layer.scale * d.scale).clamp(0.1, 6.0);
                        }),
                    onTap:
                        () => setState(() {
                          for (var l in _images) {
                            l.selected = false;
                          }
                          layer.selected = !layer.selected;
                        }),
                    child: Stack(
                      children: [
                        Transform.scale(
                          scale: layer.scale,
                          alignment: Alignment.topLeft,
                          child: Image.memory(
                            layer.bytes,
                            width: _cW,
                            fit: BoxFit.fitWidth,
                          ),
                        ),
                        if (layer.selected)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => setState(() => _images.removeAt(i)),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              ..._textZones.asMap().entries.map((e) {
                final i = e.key;
                final zone = e.value;
                return Positioned(
                  left: zone.x,
                  top: zone.y,
                  child: GestureDetector(
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
              Positioned(
                left: _nameX,
                top: _nameY,
                child: GestureDetector(
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
              Positioned(
                left: _rarityX,
                top: _rarityY,
                child: GestureDetector(
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
                      color: rc,
                      borderRadius: BorderRadius.circular(6),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          const SizedBox(height: 20),
          Center(child: _showBack ? _buildBack() : _buildFront()),
          const SizedBox(height: 6),
          Center(
            child: TextButton.icon(
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
              icon: const Icon(
                Icons.view_in_ar,
                color: Colors.white54,
                size: 16,
              ),
              label: const Text(
                'Inspecter en 3D',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (!_showBack) ...[
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
            const SizedBox(height: 20),

            _secTitle('Rareté'),
            const SizedBox(height: 10),
            ...Rarity.values.map((r) {
              final rc = _rc(r);
              final sel = _rarity == r;
              return GestureDetector(
                onTap: () => setState(() => _rarity = r),
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
                      color: sel ? rc : Colors.white.withValues(alpha: 0.08),
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
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
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
            const SizedBox(height: 20),

            _secTitle('Images (${_images.length})'),
            const SizedBox(height: 10),
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
                          ? 'Ajouter une image'
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
                if (_images.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _images.removeLast()),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Pince pour zoomer • Glisse pour bouger • Tape pour sélectionner/supprimer',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 20),

            _secTitle('Textes (${_textZones.length})'),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _addText,
              icon: const Icon(
                Icons.text_fields_rounded,
                color: Colors.white70,
              ),
              label: const Text(
                'Ajouter une zone de texte',
                style: TextStyle(color: Colors.white70),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_textZones.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Tape sur un texte pour l\'éditer • Glisse pour le déplacer',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 11,
                ),
              ),
            ],
            const SizedBox(height: 20),

            _secTitle('Fond'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _selectedGrad = -1),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            _selectedGrad == -1 ? Colors.white : Colors.white24,
                        width: _selectedGrad == -1 ? 3 : 1,
                      ),
                    ),
                    child:
                        _selectedGrad == -1
                            ? const Icon(
                              Icons.close,
                              color: Colors.white38,
                              size: 16,
                            )
                            : null,
                  ),
                ),
                ...List.generate(
                  _gradients.length,
                  (i) => GestureDetector(
                    onTap: () => setState(() => _selectedGrad = i),
                    child: Container(
                      width: 40,
                      height: 40,
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
          ] else ...[
            _secTitle('Couleur de fond'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children:
                  _backColors
                      .map(
                        (c) => GestureDetector(
                          onTap: () => setState(() => _backColor = c),
                          child: Container(
                            width: 42,
                            height: 42,
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
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
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
          const SizedBox(height: 40),
        ],
      ),
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
  Widget build(BuildContext context) => revealed ? _front() : _back();

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
