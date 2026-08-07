// collection_detail_card_creator.dart
// ─────────────────────────────────────────────────────────────────────────
//   Extrait de collection_detail_screen.dart pour reduire sa taille.
//   `part of` : meme bibliotheque que le fichier parent, donc les helpers
//   prives partages (_bg, _arcade, _pal, _rn...) restent accessibles SANS
//   aucun renommage. Les imports vivent dans le fichier parent.
// ─────────────────────────────────────────────────────────────────────────

part of 'collection_detail_screen.dart';

//   COUCHE IMAGE — INCHANGÉE
// ════════════════════════════════════════════════════════════════════════════

class _ImgLayer {
  Uint8List bytes;
  double x = 0, y = 0, scale = 1.0;
  double opacity = 1.0;
  _ImgLayer({required this.bytes});
}

// ════════════════════════════════════════════════════════════════════════════
//   CRÉATEUR DE CARTE
//   FIX 2 : Listener sur la carte + mode déplacement (LOGIQUE INCHANGÉE)
//   • Reskin : chrome, boutons, titres, swatches → style arcade
//   • Le canvas (positions/drag) reste mécaniquement identique
// ════════════════════════════════════════════════════════════════════════════

class _CardCreator extends StatefulWidget {
  final List<Color> palette;
  final String collectionId;
  final VoidCallback onSaved;
  final void Function(bool) onMoveModeChanged;
  const _CardCreator({
    required this.palette,
    required this.collectionId,
    required this.onSaved,
    required this.onMoveModeChanged,
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

  // FIX 2 : mode déplacement
  bool _moveMode = false;

  final List<_ImgLayer> _images = [];
  final List<TextZone> _textZones = [];

  // -1 = aucun, >=0 = image, -2 = nom, -3 = rareté
  int _selectedLayer = -1;

  double _nameX = 8, _nameY = 200;
  double _rarityX = 8, _rarityY = 222;

  int _selectedGrad = -1;
  int _backColor = 0xFF211A33;
  Uint8List? _backImageBytes;

  int _borderColorIndex = -1;
  static const _borderColors = [
    Colors.white,
    _gold,
    _coral,
    _teal,
    Color(0xFF2FA8FF),
    Color(0xFFB45CFF),
    Color(0xFF000000),
    Color(0xFF9AA0B0),
  ];

  late AnimationController _legendaryCtrl;
  static const double _cW = 194, _cH = 284;

  final _gradients = [
    [const Color(0xFF7C3AED), const Color(0xFF2563EB)],
    [const Color(0xFFDB2777), const Color(0xFF7C3AED)],
    [const Color(0xFF059669), const Color(0xFF2563EB)],
    [const Color(0xFFD97706), const Color(0xFFDB2777)],
    [const Color(0xFF0891B2), const Color(0xFF2563EB)],
    [const Color(0xFF14101F), const Color(0xFF2B2240)],
  ];

  final _backColors = [
    0xFF211A33,
    0xFF2B2240,
    0xFF0F3460,
    0xFF533483,
    0xFF14101F,
    0xFF1B2631,
    0xFF4A235A,
    0xFF1A5276,
  ];

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

  Color _rc(Rarity r) => _rarColors[r]!;

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

  // ── FIX 2 : déplace l'élément sélectionné ─────────────────────────────────
  void _moveSelected(Offset delta) {
    if (_selectedLayer == -2) {
      setState(() {
        _nameX = (_nameX + delta.dx).clamp(0.0, _cW - 60);
        _nameY = (_nameY + delta.dy).clamp(0.0, _cH - 20);
      });
    } else if (_selectedLayer == -3) {
      setState(() {
        _rarityX = (_rarityX + delta.dx).clamp(0.0, _cW - 60);
        _rarityY = (_rarityY + delta.dy).clamp(0.0, _cH - 16);
      });
    } else if (_selectedLayer >= 0 && _selectedLayer < _images.length) {
      final l = _images[_selectedLayer];
      setState(() {
        l.x = (l.x + delta.dx).clamp(-_cW, _cW * 2);
        l.y = (l.y + delta.dy).clamp(-_cH, _cH * 2);
      });
    } else if (_selectedLayer >= 100) {
      // textes : index 100+ = textZones[index-100]
      final i = _selectedLayer - 100;
      if (i < _textZones.length) {
        final z = _textZones[i];
        setState(() {
          z.x = (z.x + delta.dx).clamp(0.0, _cW - 20);
          z.y = (z.y + delta.dy).clamp(0.0, _cH - 20);
        });
      }
    }
  }

  // ── Ajout image / texte ────────────────────────────────────────────────────
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
        _selectedLayer = _images.length - 1;
        _moveMode = true;
        widget.onMoveModeChanged(true);
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
    setState(() {
      _textZones.add(zone);
      _selectedLayer = 100 + _textZones.length - 1;
      _moveMode = true;
      widget.onMoveModeChanged(true);
    });
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
                  backgroundColor: _surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: _surfaceLine, width: 1.5),
                  ),
                  title: Text('Modifier le texte', style: _arcade(size: 17)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: ctrl,
                          style: _body(color: _cream),
                          decoration: InputDecoration(
                            labelText: 'Texte',
                            labelStyle: _body(color: _creamFaint),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: _surfaceLine),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Taille',
                          style: _body(size: 13, color: _creamDim),
                        ),
                        Slider(
                          value: fontSize,
                          min: 8,
                          max: 36,
                          activeColor: _gold,
                          onChanged: (v) {
                            setD(() => fontSize = v);
                            setState(() => zone.fontSize = v);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Police',
                          style: _body(size: 13, color: _creamDim),
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
                                              ? _gold.withValues(alpha: 0.25)
                                              : _cream.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: sel ? _gold : _surfaceLine,
                                      ),
                                    ),
                                    child: Text(
                                      f.$2,
                                      style: TextStyle(
                                        color: _cream,
                                        fontSize: 11,
                                        fontFamily: f.$1,
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Couleur',
                          style: _body(size: 13, color: _creamDim),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    Colors.white,
                                    Colors.black,
                                    _gold,
                                    _coral,
                                    _teal,
                                    const Color(0xFF2FA8FF),
                                    const Color(0xFFB45CFF),
                                    const Color(0xFF3FD17A),
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
                      child: Text('Supprimer', style: _body(color: _coral)),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() => zone.text = ctrl.text);
                        Navigator.pop(ctx);
                      },
                      child: Text(
                        'OK',
                        style: _body(color: _gold, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  // ── Label de l'élément sélectionné ────────────────────────────────────────
  String get _selectedLabel {
    if (_selectedLayer == -2) return 'Nom';
    if (_selectedLayer == -3) return 'Rareté';
    if (_selectedLayer >= 0 && _selectedLayer < _images.length) {
      return 'Photo ${_selectedLayer + 1}';
    }
    if (_selectedLayer >= 100) return 'Texte ${_selectedLayer - 99}';
    return '';
  }

  // ── Panneau chips ──────────────────────────────────────────────────────────
  Widget _buildLayerPanel() {
    final hasLayers = _images.isNotEmpty || _textZones.isNotEmpty;
    if (!hasLayers) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          'Ajoute des photos ou du texte pour voir les éléments ici',
          style: _body(size: 11, color: _creamFaint),
        ),
      );
    }
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _chip2(
            icon: Icons.badge_rounded,
            label: 'Nom',
            sel: _selectedLayer == -2,
            onTap:
                () => setState(() {
                  _selectedLayer = _selectedLayer == -2 ? -1 : -2;
                  if (_selectedLayer != -1) _moveMode = true;
                }),
          ),
          _chip2(
            icon: Icons.label_rounded,
            label: 'Rareté',
            sel: _selectedLayer == -3,
            onTap:
                () => setState(() {
                  _selectedLayer = _selectedLayer == -3 ? -1 : -3;
                  if (_selectedLayer != -1) _moveMode = true;
                }),
          ),
          for (var i = 0; i < _images.length; i++)
            _chip2(
              imageBytes: _images[i].bytes,
              label: 'Photo ${i + 1}',
              sel: _selectedLayer == i,
              onTap:
                  () => setState(() {
                    _selectedLayer = _selectedLayer == i ? -1 : i;
                    if (_selectedLayer != -1) _moveMode = true;
                  }),
              onDelete:
                  () => setState(() {
                    _images.removeAt(i);
                    _selectedLayer = -1;
                  }),
            ),
          for (var i = 0; i < _textZones.length; i++)
            _chip2(
              icon: Icons.text_fields_rounded,
              label: 'Texte ${i + 1}',
              sel: _selectedLayer == 100 + i,
              onTap: () {
                _editText(i);
                setState(() {
                  _selectedLayer = 100 + i;
                  _moveMode = true;
                });
              },
              onDelete: () => setState(() => _textZones.removeAt(i)),
            ),
        ],
      ),
    );
  }

  Widget _chip2({
    IconData? icon,
    Uint8List? imageBytes,
    required String label,
    required bool sel,
    required VoidCallback onTap,
    VoidCallback? onDelete,
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
              sel
                  ? _gold.withValues(alpha: 0.22)
                  : _cream.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? _gold : _surfaceLine,
            width: sel ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  imageBytes,
                  width: 24,
                  height: 24,
                  fit: BoxFit.cover,
                  cacheWidth: 48,
                ),
              )
            else
              Icon(icon ?? Icons.layers, color: _cream, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: _body(size: 11, color: _cream, weight: FontWeight.w600),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onDelete,
                child: Icon(
                  Icons.close_rounded,
                  color: _cream.withValues(alpha: 0.45),
                  size: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Canvas carte — avec Listener pour le mode déplacement (INCHANGÉ) ──────
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
                    color: _surface,
                  ),
          child: Stack(
            children: [
              // Images
              ..._images.asMap().entries.map((e) {
                final i = e.key;
                final layer = e.value;
                return Positioned(
                  left: layer.x,
                  top: layer.y,
                  child: GestureDetector(
                    onTap:
                        () => setState(() {
                          _selectedLayer = _selectedLayer == i ? -1 : i;
                          _moveMode = _selectedLayer != -1;
                          widget.onMoveModeChanged(_moveMode);
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
                        if (_selectedLayer == i)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: _gold, width: 2),
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
                final sel = _selectedLayer == 100 + i;
                return Positioned(
                  left: zone.x,
                  top: zone.y,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedLayer = sel ? -1 : 100 + i;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      });
                      if (!sel) _editText(i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            sel ? Border.all(color: _gold, width: 1.5) : null,
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

              // Nom
              Positioned(
                left: _nameX,
                top: _nameY,
                child: GestureDetector(
                  onTap:
                      () => setState(() {
                        _selectedLayer = _selectedLayer == -2 ? -1 : -2;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border:
                          _selectedLayer == -2
                              ? Border.all(color: _gold, width: 1.5)
                              : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _nameCtrl.text,
                      style: _arcade(
                        size: 14,
                        color: Colors.white,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Rareté
              Positioned(
                left: _rarityX,
                top: _rarityY,
                child: GestureDetector(
                  onTap:
                      () => setState(() {
                        _selectedLayer = _selectedLayer == -3 ? -1 : -3;
                        _moveMode = _selectedLayer != -1;
                        widget.onMoveModeChanged(_moveMode);
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
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
                      style: _pixel(size: 7, color: _bg),
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
      border: Border.all(color: _surfaceLine, width: 2),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          if (_backImageBytes != null)
            Positioned.fill(
              child: Image.memory(
                _backImageBytes!,
                fit: BoxFit.cover,
                cacheWidth: 400,
              ),
            ),
          if (_backImageBytes == null)
            Center(
              child: Text(
                '?',
                style: _arcade(size: 90, color: _gold.withValues(alpha: 0.25)),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Donne un nom à ta carte !',
            style: _body(color: Colors.white),
          ),
          backgroundColor: _gold,
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

      // ✨ MIGRATION STORAGE : upload des images vers Supabase Storage.
      // En cas d'échec (hors-ligne…), la carte garde son base64 : rien ne casse.
      final uploaded = await CardMediaService.instance.uploadCardImages(card);

      await CardStorage.addCard(uploaded);

      bool supabaseOk = false;
      try {
        await CollectionService.instance.addCardToCollection(
          widget.collectionId,
          uploaded.id,
          uploaded.name,
          _rn(_rarity),
          uploaded, // card_data léger → carte partagée avec tous les membres
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
        _moveMode = false;
        widget.onMoveModeChanged(false);
      });
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e', style: _body(color: Colors.white)),
            backgroundColor: _coral,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Ligne 1 : toggle recto/verso + bouton mode déplacement ──────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
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
              const Spacer(),
              // FIX 2 : bouton mode déplacement
              GestureDetector(
                onTap:
                    () => setState(() {
                      _moveMode = !_moveMode;
                      if (!_moveMode) _selectedLayer = -1;
                      widget.onMoveModeChanged(_moveMode);
                    }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient:
                        _moveMode
                            ? const LinearGradient(colors: [_gold, _goldDeep])
                            : null,
                    color: _moveMode ? null : _cream.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _moveMode ? Colors.transparent : _surfaceLine,
                    ),
                    boxShadow:
                        _moveMode
                            ? [
                              BoxShadow(
                                color: _gold.withValues(alpha: 0.4),
                                blurRadius: 12,
                              ),
                            ]
                            : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _moveMode
                            ? Icons.open_with_rounded
                            : Icons.touch_app_outlined,
                        color: _moveMode ? const Color(0xFF2A1C00) : _cream,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _moveMode ? 'Déplacer ON' : 'Déplacer',
                        style: _body(
                          size: 12,
                          color: _moveMode ? const Color(0xFF2A1C00) : _cream,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Bandeau info mode déplacement ────────────────────────────────────
        if (_moveMode && !_showBack)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: _teal, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedLayer == -1
                        ? '👆 Tape un élément sur la carte ou un chip ci-dessous pour le sélectionner'
                        : '✋ Glisse sur la carte pour déplacer · $_selectedLabel sélectionné',
                    style: _body(size: 11, color: _teal),
                  ),
                ),
              ],
            ),
          ),

        // ── Canvas carte — FIX 2 : Listener bypass l'arène de gestes ────────
        Listener(
          behavior: HitTestBehavior.opaque,
          onPointerMove:
              _moveMode && _selectedLayer != -1
                  ? (e) => _moveSelected(e.delta)
                  : null,
          child: Center(child: _showBack ? _buildBack() : _buildFront()),
        ),

        // FIX : bouton "Terminer" collé sous la carte, toujours visible
        if (_moveMode && !_showBack)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _ArcadeButton(
              onTap: () {
                setState(() {
                  _moveMode = false;
                  _selectedLayer = -1;
                });
                widget.onMoveModeChanged(false);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('TERMINER LE DÉPLACEMENT'),
                ],
              ),
            ),
          ),

        // Bouton 3D
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
          icon: Icon(Icons.view_in_ar, color: _creamFaint, size: 15),
          label: Text(
            'Inspecter en 3D',
            style: _body(size: 11, color: _creamFaint),
          ),
        ),

        // Chips couches
        if (!_showBack) _buildLayerPanel(),

        Divider(height: 1, color: _surfaceLine),

        // ── Paramètres scrollables ───────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            // FIX 2 : désactive le scroll quand le mode déplacement est actif
            physics:
                _moveMode
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_showBack) ...[
                  TextField(
                    controller: _nameCtrl,
                    onChanged: (_) => setState(() {}),
                    style: _body(color: _cream),
                    decoration: _deco('Nom de la carte', Icons.badge_rounded),
                  ),
                  const SizedBox(height: 18),
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
                                  : _cream.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel ? rc : _surfaceLine,
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
                                boxShadow: [
                                  BoxShadow(
                                    color: rc.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _rn(r),
                              style: _body(
                                size: 13,
                                color: sel ? _cream : _creamDim,
                                weight: sel ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 80,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _dropRates[r]! / 100.0,
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.3,
                                  ),
                                  valueColor: AlwaysStoppedAnimation(rc),
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
                                style: _pixel(size: 9, color: rc),
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
                  _GhostButton(
                    onTap: () => _addImage(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _images.isEmpty
                              ? 'Ajouter une photo'
                              : 'Ajouter une couche',
                        ),
                      ],
                    ),
                  ),
                  if (_selectedLayer >= 0 &&
                      _selectedLayer < _images.length) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.opacity, color: _creamFaint, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Opacité',
                          style: _body(size: 12, color: _creamFaint),
                        ),
                        Expanded(
                          child: Slider(
                            value: _images[_selectedLayer].opacity,
                            min: 0.1,
                            max: 1.0,
                            activeColor: _gold,
                            onChanged:
                                (v) => setState(
                                  () => _images[_selectedLayer].opacity = v,
                                ),
                          ),
                        ),
                        Text(
                          '${(_images[_selectedLayer].opacity * 100).round()}%',
                          style: _body(size: 11, color: _creamFaint),
                        ),
                      ],
                    ),
                  ],
                  if (_selectedLayer >= 0 &&
                      _selectedLayer < _images.length) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.zoom_in, color: _creamFaint, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Taille',
                          style: _body(size: 12, color: _creamFaint),
                        ),
                        Expanded(
                          child: Slider(
                            value: _images[_selectedLayer].scale.clamp(
                              0.1,
                              6.0,
                            ),
                            min: 0.1,
                            max: 6.0,
                            activeColor: _gold,
                            onChanged:
                                (v) => setState(
                                  () => _images[_selectedLayer].scale = v,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  _GhostButton(
                    onTap: _addText,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.text_fields_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Ajouter du texte'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
                            color: _surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color:
                                  _selectedGrad == -1
                                      ? Colors.white
                                      : _surfaceLine,
                              width: _selectedGrad == -1 ? 3 : 1,
                            ),
                          ),
                          child:
                              _selectedGrad == -1
                                  ? Icon(
                                    Icons.close,
                                    color: _creamFaint,
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
                  _secTitle('Couleur de bordure'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
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
                                              : _surfaceLine,
                                      width: _backColor == c ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                  const SizedBox(height: 16),
                  _GhostButton(
                    onTap: () => _addImage(isBack: true),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_library_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _backImageBytes != null
                              ? '✅ Image verso — changer'
                              : 'Image verso (optionnel)',
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _ArcadeButton(
                  big: true,
                  onTap: _saving ? null : _save,
                  child:
                      _saving
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Color(0xFF2A1C00),
                              strokeWidth: 2,
                            ),
                          )
                          : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle, size: 20),
                              SizedBox(width: 8),
                              Text('AJOUTER À LA COLLECTION'),
                            ],
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
        gradient:
            active ? const LinearGradient(colors: [_gold, _goldDeep]) : null,
        color: active ? null : _cream.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? Colors.transparent : _surfaceLine),
      ),
      child: Text(
        label,
        style: _body(
          color: active ? const Color(0xFF2A1C00) : _creamDim,
          weight: FontWeight.w800,
        ),
      ),
    ),
  );

  Widget _secTitle(String t) => Text(t, style: _arcade(size: 15));

  InputDecoration _deco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: _body(color: _creamFaint),
    prefixIcon: Icon(icon, color: _creamFaint, size: 20),
    filled: true,
    fillColor: _cream.withValues(alpha: 0.06),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _gold, width: 1.5),
    ),
  );
}
