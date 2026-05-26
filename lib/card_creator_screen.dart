import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'card_model.dart';
import 'card_inspector_screen.dart';
import 'card_storage.dart';

class CardCreatorScreen extends StatefulWidget {
  const CardCreatorScreen({super.key});

  @override
  State<CardCreatorScreen> createState() => _CardCreatorScreenState();
}

class _CardCreatorScreenState extends State<CardCreatorScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController(text: 'Ma Carte');
  String? _imagePath;
  Uint8List? _imageBytes;
  Rarity _rarity = Rarity.common;
  CardEffect _effect = CardEffect.none;
  double _imageX = 0;
  double _imageY = 0;
  double _imageScale = 1.0;
  final List<TextZone> _textZones = [];
  int? _selectedTextZone;
  double _nameX = 12;
  double _nameY = 340;
  double _rarityX = 12;
  double _rarityY = 365;

  bool _showBack = false;
  int _backColor = 0xFF16213E;
  String? _backImagePath;
  Uint8List? _backImageBytes;

  late AnimationController _effectController;

  final List<Offset> _sparklePositions = [
    const Offset(0.08, 0.18),
    const Offset(0.25, 0.08),
    const Offset(0.45, 0.25),
    const Offset(0.65, 0.12),
    const Offset(0.88, 0.22),
    const Offset(0.15, 0.48),
    const Offset(0.38, 0.58),
    const Offset(0.62, 0.42),
    const Offset(0.82, 0.55),
    const Offset(0.12, 0.72),
    const Offset(0.32, 0.78),
    const Offset(0.52, 0.68),
    const Offset(0.72, 0.82),
    const Offset(0.92, 0.68),
    const Offset(0.48, 0.12),
    const Offset(0.78, 0.35),
    const Offset(0.22, 0.35),
    const Offset(0.58, 0.88),
  ];

  final List<String> _fontFamilies = ['Default', 'Serif', 'Monospace'];

  final List<int> _backColors = [
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
    _effectController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _effectController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({bool isBack = false}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        setState(() {
          if (isBack) {
            _backImageBytes = bytes;
          } else {
            _imageBytes = bytes;
          }
        });
      } else {
        setState(() {
          if (isBack) {
            _backImagePath = picked.path;
          } else {
            _imagePath = picked.path;
          }
        });
      }
    }
  }

  void _addTextZone() {
    setState(() {
      _textZones.add(TextZone(text: 'Texte', x: 50, y: 100));
      _selectedTextZone = _textZones.length - 1;
    });
    _editTextZone(_textZones.length - 1);
  }

  void _editTextZone(int index) {
    final zone = _textZones[index];
    final controller = TextEditingController(text: zone.text);
    String selectedFont = zone.fontFamily ?? 'Default';
    Color selectedColor = Color(zone.color);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
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
                          controller: controller,
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
                          'Police',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              _fontFamilies.map((f) {
                                return GestureDetector(
                                  onTap:
                                      () => setDialogState(
                                        () => selectedFont = f,
                                      ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          selectedFont == f
                                              ? const Color(0xFF6C4AB6)
                                              : Colors.transparent,
                                      border: Border.all(
                                        color: const Color(0xFF6C4AB6),
                                      ),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      f,
                                      style: TextStyle(
                                        color:
                                            selectedFont == f
                                                ? Colors.white
                                                : const Color(0xFF6C4AB6),
                                        fontSize: 11,
                                        fontFamily:
                                            f == 'Default'
                                                ? null
                                                : f.toLowerCase(),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 16),
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
                              ].map((c) {
                                return GestureDetector(
                                  onTap:
                                      () => setDialogState(
                                        () => selectedColor = c,
                                      ),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border:
                                          selectedColor == c
                                              ? Border.all(
                                                color: Colors.white,
                                                width: 3,
                                              )
                                              : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Taille',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Slider(
                          value: zone.fontSize,
                          min: 10,
                          max: 40,
                          activeColor: const Color(0xFF6C4AB6),
                          onChanged: (v) {
                            setDialogState(() => zone.fontSize = v);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        setState(() => _textZones.removeAt(index));
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Supprimer',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          zone.text = controller.text;
                          zone.color = selectedColor.value;
                          zone.fontFamily =
                              selectedFont == 'Default'
                                  ? null
                                  : selectedFont.toLowerCase();
                        });
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(color: Color(0xFF6C4AB6)),
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _buildImageWidget({
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (kIsWeb && _imageBytes != null) {
      return Image.memory(_imageBytes!, width: width, height: height, fit: fit);
    } else if (!kIsWeb && _imagePath != null) {
      return Image.file(
        File(_imagePath!),
        width: width,
        height: height,
        fit: fit,
      );
    }
    return const SizedBox();
  }

  bool get _hasImage => kIsWeb ? _imageBytes != null : _imagePath != null;
  bool get _hasBackImage =>
      kIsWeb ? _backImageBytes != null : _backImagePath != null;

  int get _rarityColorValue {
    switch (_rarity) {
      case Rarity.legendary:
        return 0xFFFFD700;
      case Rarity.epic:
        return 0xFF9C27B0;
      case Rarity.rare:
        return 0xFF2196F3;
      case Rarity.uncommon:
        return 0xFF4CAF50;
      case Rarity.common:
        return 0xFF9E9E9E;
    }
  }

  String get _rarityLabel {
    switch (_rarity) {
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

  Widget _buildSparkles({Color color = Colors.white}) {
    return AnimatedBuilder(
      animation: _effectController,
      builder: (context, _) {
        return Stack(
          children:
              _sparklePositions.map((pos) {
                final phase =
                    ((_effectController.value + pos.dx * 0.7 + pos.dy * 0.3) %
                        1.0);
                final opacity = ((sin(phase * pi * 2) + 1) / 2) * 0.9;
                final size = 2.0 + opacity * 3.5;
                return Positioned(
                  left: pos.dx * 274,
                  top: pos.dy * 394,
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  Widget _buildHolographicEffect() {
    return AnimatedBuilder(
      animation: _effectController,
      builder: (context, _) {
        final t = _effectController.value;
        return Positioned.fill(
          child: Stack(
            children: [
              Opacity(
                opacity: 0.7,
                child: ShaderMask(
                  shaderCallback:
                      (bounds) => LinearGradient(
                        begin: Alignment(-2 + t * 4, -0.5),
                        end: Alignment(-1.5 + t * 4, 0.5),
                        colors: const [
                          Colors.transparent,
                          Color(0xCCFF0080),
                          Color(0xCCFF8C00),
                          Color(0xCCFFFF00),
                          Color(0xCC00FF7F),
                          Color(0xCC0080FF),
                          Color(0xCCBF00FF),
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                  blendMode: BlendMode.srcOver,
                  child: Container(color: Colors.white30),
                ),
              ),
              Opacity(
                opacity: 0.45,
                child: ShaderMask(
                  shaderCallback:
                      (bounds) => LinearGradient(
                        begin: Alignment(-1, -2 + t * 4),
                        end: Alignment(1, -1.5 + t * 4),
                        colors: const [
                          Colors.transparent,
                          Color(0xAAFF00FF),
                          Color(0xAA00FFFF),
                          Color(0xAAFFFF00),
                          Colors.transparent,
                        ],
                      ).createShader(bounds),
                  blendMode: BlendMode.srcOver,
                  child: Container(color: Colors.white.withOpacity(0.2)),
                ),
              ),
              _buildSparkles(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShinyEffect() {
    return AnimatedBuilder(
      animation: _effectController,
      builder: (context, _) {
        final t = _effectController.value;
        return Positioned.fill(
          child: Stack(
            children: [
              ShaderMask(
                shaderCallback:
                    (bounds) => LinearGradient(
                      begin: Alignment(-3 + t * 6, -1),
                      end: Alignment(-2.5 + t * 6, 1),
                      colors: const [
                        Colors.transparent,
                        Color(0x88FFD700),
                        Color(0xEEFFFFFF),
                        Color(0x88FFD700),
                        Colors.transparent,
                      ],
                    ).createShader(bounds),
                blendMode: BlendMode.srcOver,
                child: Container(color: Colors.white),
              ),
              ShaderMask(
                shaderCallback:
                    (bounds) => LinearGradient(
                      begin: Alignment(-1, -3 + t * 6),
                      end: Alignment(1, -2.5 + t * 6),
                      colors: const [
                        Colors.transparent,
                        Color(0x55FFD700),
                        Color(0x99FFE082),
                        Color(0x55FFD700),
                        Colors.transparent,
                      ],
                    ).createShader(bounds),
                blendMode: BlendMode.srcOver,
                child: Container(color: Colors.white),
              ),
              _buildSparkles(color: const Color(0xFFFFD700)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCardFront() {
    final rarityColor = Color(_rarityColorValue);

    Widget inner = Container(
      width: 274,
      height: 394,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: const Color(0xFF1A1A2E),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            if (_hasImage)
              Positioned(
                left: _imageX,
                top: _imageY,
                child: GestureDetector(
                  onScaleUpdate:
                      (d) => setState(() {
                        _imageX += d.focalPointDelta.dx;
                        _imageY += d.focalPointDelta.dy;
                        _imageScale = (_imageScale * d.scale).clamp(0.3, 4.0);
                      }),
                  child: Transform.scale(
                    scale: _imageScale,
                    child: _buildImageWidget(width: 274, height: 280),
                  ),
                ),
              ),
            if (_effect == CardEffect.holographic) _buildHolographicEffect(),
            if (_effect == CardEffect.shiny) _buildShinyEffect(),
            ..._textZones.asMap().entries.map((entry) {
              final i = entry.key;
              final zone = entry.value;
              return Positioned(
                left: zone.x,
                top: zone.y,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedTextZone = i);
                    _editTextZone(i);
                  },
                  onPanUpdate:
                      (d) => setState(() {
                        zone.x += d.delta.dx;
                        zone.y += d.delta.dy;
                      }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                      border:
                          _selectedTextZone == i
                              ? Border.all(color: Colors.white38)
                              : null,
                    ),
                    child: Text(
                      zone.text,
                      style: TextStyle(
                        color: Color(zone.color),
                        fontSize: zone.fontSize,
                        fontFamily: zone.fontFamily,
                      ),
                    ),
                  ),
                ),
              );
            }),
            Positioned(
              left: _nameX,
              top: _nameY,
              child: GestureDetector(
                onPanUpdate:
                    (d) => setState(() {
                      _nameX += d.delta.dx;
                      _nameY += d.delta.dy;
                    }),
                child: Text(
                  _nameController.text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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
                      _rarityX += d.delta.dx;
                      _rarityY += d.delta.dy;
                    }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: rarityColor,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    _rarityLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (_rarity == Rarity.legendary) {
      return AnimatedBuilder(
        animation: _effectController,
        builder: (context, _) {
          return SizedBox(
            width: 280,
            height: 400,
            child: Stack(
              children: [
                Container(
                  width: 280,
                  height: 400,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: SweepGradient(
                      startAngle: _effectController.value * 2 * pi,
                      colors: const [
                        Color(0xFFFFD700),
                        Color(0xFFFFF9C4),
                        Color(0xFFFF8F00),
                        Color(0xFFFFE082),
                        Color(0xFFFFF176),
                        Color(0xFFFFCC02),
                        Color(0xFFFFD700),
                      ],
                    ),
                  ),
                ),
                Center(child: inner),
              ],
            ),
          );
        },
      );
    }

    return SizedBox(
      width: 280,
      height: 400,
      child: Stack(
        children: [
          Container(
            width: 280,
            height: 400,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rarityColor, width: 3),
              color: const Color(0xFF1A1A2E),
            ),
          ),
          Center(child: inner),
        ],
      ),
    );
  }

  Widget _buildCardBack() {
    return Container(
      width: 280,
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Color(_backColor),
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            if (_hasBackImage)
              Positioned.fill(
                child:
                    kIsWeb && _backImageBytes != null
                        ? Image.memory(_backImageBytes!, fit: BoxFit.cover)
                        : _backImagePath != null
                        ? Image.file(File(_backImagePath!), fit: BoxFit.cover)
                        : const SizedBox(),
              ),
            if (!_hasBackImage)
              const Center(
                child: Opacity(
                  opacity: 0.2,
                  child: Icon(Icons.style, size: 100, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) => Align(
    alignment: Alignment.centerLeft,
    child: Text(
      label,
      style: const TextStyle(color: Colors.white70, fontSize: 14),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16213E),
        title: const Text(
          'Créer une carte',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => CardInspectorScreen(
                        frontCard: _buildCardFront(),
                        backCard: _buildCardBack(),
                      ),
                ),
              );
            },
            icon: const Icon(Icons.view_in_ar, color: Colors.white70),
            label: const Text(
              'Inspecter',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: () async {
              final card = SavedCard(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: _nameController.text,
                rarity: _rarity,
                effect: _effect,
                imageBytes: _imageBytes,
                backImageBytes: _backImageBytes,
                backColor: _backColor,
                imageX: _imageX,
                imageY: _imageY,
                imageScale: _imageScale,
                nameX: _nameX,
                nameY: _nameY,
                rarityX: _rarityX,
                rarityY: _rarityY,
                textZones: _textZones,
              );
              await CardStorage.addCard(card);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Carte sauvegardée !'),
                    backgroundColor: Color(0xFF4CAF50),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text(
              'Sauvegarder',
              style: TextStyle(color: Color(0xFF6C4AB6)),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _showBack = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          !_showBack
                              ? const Color(0xFF6C4AB6)
                              : Colors.transparent,
                      border: Border.all(color: const Color(0xFF6C4AB6)),
                      borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(99),
                      ),
                    ),
                    child: Text(
                      'Recto',
                      style: TextStyle(
                        color:
                            !_showBack ? Colors.white : const Color(0xFF6C4AB6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _showBack = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _showBack
                              ? const Color(0xFF6C4AB6)
                              : Colors.transparent,
                      border: Border.all(color: const Color(0xFF6C4AB6)),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(99),
                      ),
                    ),
                    child: Text(
                      'Verso',
                      style: TextStyle(
                        color:
                            _showBack ? Colors.white : const Color(0xFF6C4AB6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _showBack ? _buildCardBack() : _buildCardFront(),
            const SizedBox(height: 24),
            if (!_showBack) ...[
              TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Nom de la carte',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white24),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF6C4AB6)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionLabel('Rareté'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    Rarity.values.map((r) {
                      final colors = {
                        Rarity.common: 0xFF9E9E9E,
                        Rarity.uncommon: 0xFF4CAF50,
                        Rarity.rare: 0xFF2196F3,
                        Rarity.epic: 0xFF9C27B0,
                        Rarity.legendary: 0xFFFFD700,
                      };
                      final names = {
                        Rarity.common: 'Commun',
                        Rarity.uncommon: 'Peu commun',
                        Rarity.rare: 'Rare',
                        Rarity.epic: 'Épique',
                        Rarity.legendary: 'Légendaire',
                      };
                      return GestureDetector(
                        onTap: () => setState(() => _rarity = r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _rarity == r
                                    ? Color(colors[r]!)
                                    : Colors.transparent,
                            border: Border.all(color: Color(colors[r]!)),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            names[r]!,
                            style: TextStyle(
                              color:
                                  _rarity == r
                                      ? Colors.white
                                      : Color(colors[r]!),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 16),
              _buildSectionLabel('Effet'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [CardEffect.none].map((e) {
                      final names = {CardEffect.none: 'Normal'};
                      return GestureDetector(
                        onTap: () => setState(() => _effect = e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                _effect == e
                                    ? const Color(0xFF6C4AB6)
                                    : Colors.transparent,
                            border: Border.all(color: const Color(0xFF6C4AB6)),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            names[e]!,
                            style: TextStyle(
                              color:
                                  _effect == e
                                      ? Colors.white
                                      : const Color(0xFF6C4AB6),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickImage(isBack: false),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Image recto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addTextZone,
                      icon: const Icon(Icons.text_fields),
                      label: const Text('Ajouter texte'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16213E),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasImage) ...[
                const SizedBox(height: 16),
                _buildSectionLabel('Taille de l\'image'),
                Slider(
                  value: _imageScale,
                  min: 0.5,
                  max: 2.0,
                  activeColor: const Color(0xFF6C4AB6),
                  onChanged: (v) => setState(() => _imageScale = v),
                ),
              ],
            ] else ...[
              _buildSectionLabel('Couleur de fond'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    _backColors.map((c) {
                      return GestureDetector(
                        onTap: () => setState(() => _backColor = c),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border:
                                _backColor == c
                                    ? Border.all(color: Colors.white, width: 3)
                                    : Border.all(color: Colors.white24),
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _pickImage(isBack: true),
                icon: const Icon(Icons.photo_library),
                label: const Text('Image verso'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16213E),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
