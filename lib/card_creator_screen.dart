// card_creator_screen.dart — BLOCS 1 + 2 + 3
//
// ✨ Bloc 3 :
//   • Gras / italique sur les textes
//   • Contour (couleur + épaisseur) via double Text superposé
//     (un Paint en mode stroke dessous, le remplissage dessus)
//   • Ombre paramétrable (décalage X/Y, flou, couleur)
//   • Le NOM de la carte est stylable aussi (crayon dans la pilule,
//     dialog sans champ texte ni bouton supprimer)
//   • La puce sombre derrière les zones de texte disparaît dès qu'un
//     contour ou une ombre est appliqué (rendu propre) — les anciennes
//     cartes, sans style, gardent leur apparence exacte
//
// ✨ Bloc 2 :
//   • Bouton « Couches » dans la barre du haut → panneau glissant
//   • Liste affichée du premier plan (haut) vers l'arrière-plan (bas)
//   • Glisser la poignée pour réordonner, œil pour masquer/afficher,
//     taper une ligne pour sélectionner la couche sur la carte
//   • Cadenas sur le nom et la rareté (réordonnables mais indestructibles)
//
// ✨ Nouveautés :
//   • Tout élément (image, texte, nom, rareté) est une CardLayer
//     → sélection unifiée : tape un élément pour le sélectionner
//   • Pilule d'actions rapides sous la carte : flip H/V, rotation 90°,
//     avancer/reculer d'un plan, éditer (texte), dupliquer, supprimer
//   • Sliders rotation précise (-180..180°) + opacité pour l'élément
//     sélectionné
//   • Rotation à DEUX DOIGTS directement sur l'élément (gratuit avec
//     ScaleUpdateDetails.rotation)
//
// 🐛 Corrections au passage :
//   • Pinch : l'échelle de départ est mémorisée dans onScaleStart
//     (avant : facteur cumulatif re-multiplié à chaque frame → zoom fou)
//   • Mobile : les images sont toujours lues en BYTES via readAsBytes()
//     (avant : sur mobile seul _imagePath était rempli, et la sauvegarde
//     n'envoyait que _imageBytes → image perdue hors web)

import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'card_layer.dart';
import 'card_model.dart';
import 'card_inspector_screen.dart';
import 'card_storage.dart';

// Dimensions du canvas (identiques à l'ancienne version)
const double _kCardW = 274;
const double _kCardH = 394;

class CardCreatorScreen extends StatefulWidget {
  const CardCreatorScreen({super.key});

  @override
  State<CardCreatorScreen> createState() => _CardCreatorScreenState();
}

class _CardCreatorScreenState extends State<CardCreatorScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController(text: 'Ma Carte');
  Rarity _rarity = Rarity.common;
  CardEffect _effect = CardEffect.none;

  // ✨ Source de vérité unique : la pile de couches (index 0 = derrière)
  final List<CardLayer> _layers = [];
  int _selected = -1; // index dans _layers, -1 = rien

  // Mémorisation au début du geste (fix pinch + rotation 2 doigts)
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;

  bool _showBack = false;
  int _backColor = 0xFF16213E;
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

    // Couches spéciales toujours présentes : nom + rareté
    _layers.add(
      CardLayer(
        id: CardLayer.newId(),
        type: LayerType.text,
        role: LayerRole.cardName,
        x: 12,
        y: 340,
        fontSize: 18,
        bold: true,
        shadowOn: true,
        shadowDx: 0,
        shadowDy: 0,
        shadowBlur: 4,
      ),
    );
    _layers.add(
      CardLayer(
        id: CardLayer.newId(),
        type: LayerType.text,
        role: LayerRole.cardRarity,
        x: 12,
        y: 365,
        fontSize: 11,
      ),
    );
  }

  @override
  void dispose() {
    _effectController.dispose();
    super.dispose();
  }

  CardLayer? get _sel =>
      (_selected >= 0 && _selected < _layers.length)
          ? _layers[_selected]
          : null;

  // ────────────────────────────────────────────────────────
  //   ACTIONS
  // ────────────────────────────────────────────────────────

  // 🐛 Fix mobile : toujours readAsBytes() (fonctionne web + mobile)
  Future<void> _pickImage({bool isBack = false}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      if (isBack) {
        _backImageBytes = bytes;
      } else {
        // Nouvelle image insérée juste sous le nom/la rareté
        // (= au-dessus des autres images/textes libres)
        final insertAt = _layers.indexWhere((l) => l.role != LayerRole.normal);
        final layer = CardLayer(
          id: CardLayer.newId(),
          type: LayerType.image,
          bytes: bytes,
          x: 0,
          y: 0,
        );
        if (insertAt < 0) {
          _layers.add(layer);
          _selected = _layers.length - 1;
        } else {
          _layers.insert(insertAt, layer);
          _selected = insertAt;
        }
      }
    });
  }

  void _addTextZone() {
    final layer = CardLayer(
      id: CardLayer.newId(),
      type: LayerType.text,
      text: 'Texte',
      x: 50,
      y: 100,
    );
    setState(() {
      final insertAt = _layers.indexWhere((l) => l.role != LayerRole.normal);
      if (insertAt < 0) {
        _layers.add(layer);
        _selected = _layers.length - 1;
      } else {
        _layers.insert(insertAt, layer);
        _selected = insertAt;
      }
    });
    _editTextLayer(layer);
  }

  void _moveLayer(int delta) {
    final i = _selected;
    final j = i + delta;
    if (i < 0 || j < 0 || j >= _layers.length) return;
    setState(() {
      final l = _layers.removeAt(i);
      _layers.insert(j, l);
      _selected = j;
    });
  }

  void _duplicateSelected() {
    final l = _sel;
    if (l == null || !l.isDeletable) return;
    setState(() {
      final copy = l.clone();
      _layers.insert(_selected + 1, copy);
      _selected = _selected + 1;
    });
  }

  void _deleteSelected() {
    final l = _sel;
    if (l == null || !l.isDeletable) return;
    setState(() {
      _layers.removeAt(_selected);
      _selected = -1;
    });
  }

  // ────────────────────────────────────────────────────────
  //   DIALOG D'ÉDITION DE TEXTE (couches texte normales)
  // ────────────────────────────────────────────────────────

  void _editTextLayer(CardLayer layer) {
    final isName = layer.role == LayerRole.cardName;
    final controller = TextEditingController(text: layer.text);
    String selectedFont =
        layer.fontFamily == null
            ? 'Default'
            : layer.fontFamily![0].toUpperCase() +
                layer.fontFamily!.substring(1);
    Color selectedColor = Color(layer.color);

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  backgroundColor: const Color(0xFF16213E),
                  title: Text(
                    isName ? 'Style du nom' : 'Modifier le texte',
                    style: const TextStyle(color: Colors.white),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isName)
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
                          value: layer.fontSize.clamp(10.0, 40.0),
                          min: 10,
                          max: 40,
                          activeColor: const Color(0xFF6C4AB6),
                          onChanged: (v) {
                            setDialogState(() => layer.fontSize = v);
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 12),
                        // ✨ Bloc 3 : gras / italique
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                setDialogState(() => layer.bold = !layer.bold);
                                setState(() {});
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      layer.bold
                                          ? const Color(0xFF6C4AB6)
                                          : Colors.transparent,
                                  border: Border.all(
                                    color: const Color(0xFF6C4AB6),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'G',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setDialogState(
                                  () => layer.italic = !layer.italic,
                                );
                                setState(() {});
                              },
                              child: Container(
                                width: 38,
                                height: 38,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      layer.italic
                                          ? const Color(0xFF6C4AB6)
                                          : Colors.transparent,
                                  border: Border.all(
                                    color: const Color(0xFF6C4AB6),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'I',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ✨ Bloc 3 : contour
                        const Text(
                          'Contour',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setDialogState(() => layer.outlineColor = null);
                                setState(() {});
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      layer.outlineColor == null
                                          ? const Color(0xFF6C4AB6)
                                          : Colors.transparent,
                                  border: Border.all(
                                    color: const Color(0xFF6C4AB6),
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  'Aucun',
                                  style: TextStyle(
                                    color:
                                        layer.outlineColor == null
                                            ? Colors.white
                                            : const Color(0xFF6C4AB6),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                            ...[
                              0xFF000000,
                              0xFFFFFFFF,
                              0xFFFFD700,
                              0xFFE53935,
                              0xFF1E88E5,
                              0xFF8E24AA,
                            ].map(
                              (c) => GestureDetector(
                                onTap: () {
                                  setDialogState(() => layer.outlineColor = c);
                                  setState(() {});
                                },
                                child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: Color(c),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color:
                                          layer.outlineColor == c
                                              ? Colors.white
                                              : Colors.white24,
                                      width: layer.outlineColor == c ? 3 : 1,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (layer.outlineColor != null)
                          Row(
                            children: [
                              const Text(
                                'Épaisseur',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: layer.outlineWidth.clamp(1.0, 6.0),
                                  min: 1,
                                  max: 6,
                                  activeColor: const Color(0xFF6C4AB6),
                                  onChanged: (v) {
                                    setDialogState(
                                      () => layer.outlineWidth = v,
                                    );
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 8),
                        // ✨ Bloc 3 : ombre
                        Row(
                          children: [
                            const Text(
                              'Ombre',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Switch(
                              value: layer.shadowOn,
                              activeColor: const Color(0xFF6C4AB6),
                              onChanged: (v) {
                                setDialogState(() => layer.shadowOn = v);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        if (layer.shadowOn) ...[
                          Row(
                            children: [
                              const SizedBox(
                                width: 74,
                                child: Text(
                                  'Décalage X',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: layer.shadowDx.clamp(-8.0, 8.0),
                                  min: -8,
                                  max: 8,
                                  activeColor: const Color(0xFF6C4AB6),
                                  onChanged: (v) {
                                    setDialogState(() => layer.shadowDx = v);
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const SizedBox(
                                width: 74,
                                child: Text(
                                  'Décalage Y',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: layer.shadowDy.clamp(-8.0, 8.0),
                                  min: -8,
                                  max: 8,
                                  activeColor: const Color(0xFF6C4AB6),
                                  onChanged: (v) {
                                    setDialogState(() => layer.shadowDy = v);
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const SizedBox(
                                width: 74,
                                child: Text(
                                  'Flou',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: layer.shadowBlur.clamp(0.0, 12.0),
                                  min: 0,
                                  max: 12,
                                  activeColor: const Color(0xFF6C4AB6),
                                  onChanged: (v) {
                                    setDialogState(() => layer.shadowBlur = v);
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                [
                                      0xFF000000,
                                      0xFFFFFFFF,
                                      0xFFFFD700,
                                      0xFFE53935,
                                      0xFF1E88E5,
                                    ]
                                    .map(
                                      (c) => GestureDetector(
                                        onTap: () {
                                          setDialogState(
                                            () => layer.shadowColor = c,
                                          );
                                          setState(() {});
                                        },
                                        child: Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Color(c),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color:
                                                  layer.shadowColor == c
                                                      ? Colors.white
                                                      : Colors.white24,
                                              width:
                                                  layer.shadowColor == c
                                                      ? 3
                                                      : 1,
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    if (!isName)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _layers.remove(layer);
                            _selected = -1;
                          });
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
                          if (!isName) layer.text = controller.text;
                          layer.color = selectedColor.toARGB32();
                          layer.fontFamily =
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

  // ────────────────────────────────────────────────────────
  //   RARETÉ (inchangé)
  // ────────────────────────────────────────────────────────

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

  // ────────────────────────────────────────────────────────
  //   EFFETS (inchangés)
  // ────────────────────────────────────────────────────────

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
                  left: pos.dx * _kCardW,
                  top: pos.dy * _kCardH,
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
          child: IgnorePointer(
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
                    child: Container(color: Colors.white24),
                  ),
                ),
                _buildSparkles(),
              ],
            ),
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
          child: IgnorePointer(
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
          ),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────────
  //   RENDU D'UNE COUCHE
  // ────────────────────────────────────────────────────────

  // ✨ Bloc 3 : rendu de texte stylé (gras, italique, contour, ombre)
  // Contour = deux Text superposés : le stroke dessous, le remplissage
  // dessus. L'ombre est portée par la couche du dessous pour suivre la
  // silhouette du contour.
  Widget _styledText(String text, CardLayer l) {
    final base = TextStyle(
      fontSize: l.fontSize,
      fontFamily: l.fontFamily,
      fontWeight: l.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: l.italic ? FontStyle.italic : FontStyle.normal,
    );
    final shadows =
        l.shadowOn
            ? [
              Shadow(
                color: Color(l.shadowColor),
                offset: Offset(l.shadowDx, l.shadowDy),
                blurRadius: l.shadowBlur,
              ),
            ]
            : null;

    if (l.outlineColor == null) {
      return Text(
        text,
        style: base.copyWith(color: Color(l.color), shadows: shadows),
      );
    }
    return Stack(
      children: [
        Text(
          text,
          style: base.copyWith(
            shadows: shadows,
            foreground:
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = l.outlineWidth
                  ..color = Color(l.outlineColor!),
          ),
        ),
        Text(text, style: base.copyWith(color: Color(l.color))),
      ],
    );
  }

  Widget _layerContent(CardLayer l, {required bool selected}) {
    Widget content;
    switch (l.type) {
      case LayerType.image:
        content =
            l.bytes != null
                ? Image.memory(l.bytes!, width: _kCardW, cacheWidth: 800)
                : const SizedBox(width: 60, height: 60);
      case LayerType.text:
        if (l.role == LayerRole.cardName) {
          content = _styledText(_nameController.text, l);
        } else if (l.role == LayerRole.cardRarity) {
          content = Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Color(_rarityColorValue),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              _rarityLabel,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          );
        } else {
          // La puce sombre disparaît dès qu'un style est appliqué :
          // les anciennes cartes (sans style) gardent leur rendu exact
          final hasStyle = l.outlineColor != null || l.shadowOn;
          content = Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: hasStyle ? Colors.transparent : Colors.black45,
              borderRadius: BorderRadius.circular(4),
            ),
            child: _styledText(l.text, l),
          );
        }
      case LayerType.sticker:
        content = const SizedBox(); // bloc 4
    }

    // Cadre de sélection — DANS les transformations : il tourne et se
    // retourne avec l'élément, comme sur la maquette
    if (selected) {
      content = Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFFAC775), width: 1.5),
        ),
        child: content,
      );
    }
    return content;
  }

  Widget _buildLayer(int i) {
    final l = _layers[i];
    if (!l.visible) return const SizedBox();
    final selected = i == _selected;

    return Positioned(
      left: l.x,
      top: l.y,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _selected = i);
          // Second tap sur un texte déjà sélectionné → édition rapide
          if (selected &&
              l.type == LayerType.text &&
              l.role != LayerRole.cardRarity) {
            _editTextLayer(l);
          }
        },
        // 🐛 Fix pinch : on mémorise l'état de départ du geste
        onScaleStart: (_) {
          setState(() => _selected = i);
          _gestureStartScale = l.scale;
          _gestureStartRotation = l.rotation;
        },
        onScaleUpdate:
            (d) => setState(() {
              l.x += d.focalPointDelta.dx;
              l.y += d.focalPointDelta.dy;
              if (d.pointerCount > 1) {
                l.scale = (_gestureStartScale * d.scale).clamp(0.2, 4.0);
                // ✨ rotation à deux doigts (radians → degrés)
                l.rotation = _gestureStartRotation + d.rotation * 180 / pi;
              }
            }),
        child: Transform.rotate(
          angle: l.rotation * pi / 180,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              (l.flipH ? -1.0 : 1.0) * l.scale,
              (l.flipV ? -1.0 : 1.0) * l.scale,
              1.0,
            ),
            child: Opacity(
              opacity: l.opacity.clamp(0.05, 1.0),
              child: _layerContent(l, selected: selected),
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────
  //   RECTO
  // ────────────────────────────────────────────────────────

  Widget _buildCardFront() {
    final rarityColor = Color(_rarityColorValue);

    Widget inner = Container(
      width: _kCardW,
      height: _kCardH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: const Color(0xFF1A1A2E),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Stack(
          children: [
            // Tap sur le fond → désélection
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = -1),
              ),
            ),
            // Couches, dans l'ordre d'empilement
            for (int i = 0; i < _layers.length; i++) _buildLayer(i),
            if (_effect == CardEffect.holographic) _buildHolographicEffect(),
            if (_effect == CardEffect.shiny) _buildShinyEffect(),
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
            if (_backImageBytes != null)
              Positioned.fill(
                child: Image.memory(
                  _backImageBytes!,
                  fit: BoxFit.cover,
                  cacheWidth: 600,
                ),
              ),
            if (_backImageBytes == null)
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

  // ────────────────────────────────────────────────────────
  //   PILULE D'ACTIONS + SLIDERS (élément sélectionné)
  // ────────────────────────────────────────────────────────

  Widget _pillButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 20, color: color ?? Colors.white),
      ),
    );
  }

  Widget _buildSelectionTools() {
    final l = _sel;
    if (l == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'Tape un élément de la carte pour le modifier',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        // Pilule d'actions rapides
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _pillButton(Icons.flip, () => setState(() => l.flipH = !l.flipH)),
              RotatedBox(
                quarterTurns: 1,
                child: _pillButton(
                  Icons.flip,
                  () => setState(() => l.flipV = !l.flipV),
                ),
              ),
              _pillButton(
                Icons.rotate_90_degrees_cw,
                () => setState(
                  () => l.rotation = ((l.rotation + 90 + 180) % 360) - 180,
                ),
              ),
              _pillButton(Icons.flip_to_front, () => _moveLayer(1)),
              _pillButton(Icons.flip_to_back, () => _moveLayer(-1)),
              if (l.type == LayerType.text && l.role != LayerRole.cardRarity)
                _pillButton(Icons.edit, () => _editTextLayer(l)),
              if (l.isDeletable) _pillButton(Icons.copy, _duplicateSelected),
              if (l.isDeletable)
                _pillButton(
                  Icons.delete,
                  _deleteSelected,
                  color: Colors.redAccent,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Sliders rotation + opacité
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 60,
                    child: Text(
                      'Rotation',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        value: l.rotation.clamp(-180.0, 180.0),
                        min: -180,
                        max: 180,
                        activeColor: const Color(0xFF6C4AB6),
                        onChanged: (v) => setState(() => l.rotation = v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${l.rotation.round()}°',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 60,
                    child: Text(
                      'Opacité',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                      ),
                      child: Slider(
                        value: l.opacity.clamp(0.1, 1.0),
                        min: 0.1,
                        max: 1.0,
                        activeColor: const Color(0xFF6C4AB6),
                        onChanged: (v) => setState(() => l.opacity = v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(l.opacity * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────
  //   PANNEAU COUCHES (bloc 2)
  //   Affiché du PREMIER PLAN (haut) vers l'ARRIÈRE-PLAN (bas),
  //   comme dans les logiciels de dessin.
  //   Mapping : index panneau p ↔ index couche i = length - 1 - p
  // ────────────────────────────────────────────────────────

  String _layerLabel(CardLayer l) {
    switch (l.type) {
      case LayerType.image:
        final images = _layers.where((e) => e.type == LayerType.image).toList();
        return 'Image ${images.indexOf(l) + 1}';
      case LayerType.text:
        if (l.role == LayerRole.cardName) {
          return 'Nom « ${_nameController.text} »';
        }
        if (l.role == LayerRole.cardRarity) return 'Rareté ($_rarityLabel)';
        return l.text.isEmpty ? 'Texte' : l.text;
      case LayerType.sticker:
        return 'Sticker';
    }
  }

  Widget _layerThumb(CardLayer l) {
    if (l.type == LayerType.image && l.bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          l.bytes!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          cacheWidth: 64,
        ),
      );
    }
    IconData icon;
    switch (l.type) {
      case LayerType.image:
        icon = Icons.image;
      case LayerType.text:
        icon = l.role == LayerRole.cardRarity ? Icons.star : Icons.text_fields;
      case LayerType.sticker:
        icon = Icons.emoji_emotions;
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 18, color: Colors.white70),
    );
  }

  void _openLayersPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (sheetContext) => StatefulBuilder(
            builder: (sheetContext, setSheet) {
              // Rafraîchit le sheet ET l'écran derrière
              void refresh(VoidCallback fn) {
                setSheet(fn);
                setState(() {});
              }

              return SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.layers,
                            size: 18,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Couches',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'haut = devant',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ReorderableListView.builder(
                          shrinkWrap: true,
                          buildDefaultDragHandles: false,
                          itemCount: _layers.length,
                          onReorder: (oldP, newP) {
                            if (newP > oldP) newP--;
                            refresh(() {
                              final sel = _sel; // suit la couche, pas l'index
                              final li = _layers.length - 1 - oldP;
                              final ln = _layers.length - 1 - newP;
                              final l = _layers.removeAt(li);
                              _layers.insert(ln, l);
                              if (sel != null) {
                                _selected = _layers.indexOf(sel);
                              }
                            });
                          },
                          itemBuilder: (context, p) {
                            final i = _layers.length - 1 - p;
                            final l = _layers[i];
                            final selected = i == _selected;
                            return Container(
                              key: ValueKey(l.id),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A2E),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color:
                                      selected
                                          ? const Color(0xFFFAC775)
                                          : Colors.white12,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => refresh(() => _selected = i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: p,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.drag_indicator,
                                            size: 20,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Opacity(
                                        opacity: l.visible ? 1 : 0.4,
                                        child: _layerThumb(l),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          _layerLabel(l),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color:
                                                l.visible
                                                    ? Colors.white
                                                    : Colors.white38,
                                            fontSize: 13,
                                            fontWeight:
                                                selected
                                                    ? FontWeight.w600
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (!l.isDeletable)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 4),
                                          child: Icon(
                                            Icons.lock,
                                            size: 14,
                                            color: Colors.white30,
                                          ),
                                        ),
                                      IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed:
                                            () => refresh(
                                              () => l.visible = !l.visible,
                                            ),
                                        icon: Icon(
                                          l.visible
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                          size: 20,
                                          color:
                                              l.visible
                                                  ? Colors.white70
                                                  : Colors.white30,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
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

  // ────────────────────────────────────────────────────────
  //   SAUVEGARDE
  // ────────────────────────────────────────────────────────

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final card = SavedCard.fromLayers(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text,
      layers:
          _layers.map((l) {
            // Le texte des couches spéciales est figé au moment de la sauvegarde
            if (l.role == LayerRole.cardName) l.text = _nameController.text;
            if (l.role == LayerRole.cardRarity) l.text = _rarityLabel;
            return l;
          }).toList(),
      rarity: _rarity,
      effect: _effect,
      backImageBytes: _backImageBytes,
      backColor: _backColor,
    );
    await CardStorage.addCard(card);
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('✅ Carte sauvegardée !'),
        backgroundColor: Color(0xFF4CAF50),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ────────────────────────────────────────────────────────
  //   BUILD
  // ────────────────────────────────────────────────────────

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
          IconButton(
            onPressed: _showBack ? null : _openLayersPanel,
            icon: const Icon(Icons.layers, color: Colors.white70),
            tooltip: 'Couches',
          ),
          TextButton.icon(
            onPressed: () {
              setState(() => _selected = -1); // pas de cadre dans l'aperçu
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
            onPressed: _save,
            child: const Text(
              'Sauvegarder',
              style: TextStyle(color: Color(0xFF6C4AB6)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toggle recto/verso
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
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
          ),

          // Canvas — hors du scroll (drag OK sur mobile)
          Center(child: _showBack ? _buildCardBack() : _buildCardFront()),

          // ✨ Pilule + sliders de l'élément sélectionné
          if (!_showBack) _buildSelectionTools(),

          const SizedBox(height: 4),

          // Paramètres scrollables
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Column(
                children: [
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
                          borderSide: const BorderSide(
                            color: Color(0xFF6C4AB6),
                          ),
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
                                  border: Border.all(
                                    color: const Color(0xFF6C4AB6),
                                  ),
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
                            label: const Text('Ajouter image'),
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
                                          ? Border.all(
                                            color: Colors.white,
                                            width: 3,
                                          )
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
          ),
        ],
      ),
    );
  }
}
