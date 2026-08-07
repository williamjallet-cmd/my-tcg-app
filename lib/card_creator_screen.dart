// card_creator_screen.dart — BLOCS 1 + 2 + 3 + 4
//
// ✨ Bloc 4 :
//   • Fond du recto : couleur au choix + IMAGE plein cadre (couche
//     verrouillée tout en bas de la pile) avec modes remplir/ajuster
//     et voile assombrissant réglable
//   • Cadres décoratifs dessinés en CustomPainter (or, argent, néon,
//     pointillé) → zéro asset à charger
//   • Stickers : icônes vectorielles colorables, couches à part entière
//     (déplaçables, rotatives, duplicables) — liste d'icônes const pour
//     rester compatible avec le tree-shaking des icônes en release
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'card_layer.dart';
import 'card_media_service.dart';
import 'collection_service.dart';
import 'color_picker_sheet.dart';
import 'error_reporter.dart';
import 'card_model.dart';
import 'card_inspector_screen.dart';
import 'card_storage.dart';

// Dimensions du canvas (identiques à l'ancienne version)
const double _kCardW = 274;
const double _kCardH = 394;

class CardCreatorScreen extends StatefulWidget {
  /// ✨ Si renseigne, la carte est AUSSI rattachee a cette collection
  /// (table `collection_cards`), et devient donc tirable au pack et visible
  /// par tous les membres. Sinon la carte reste dans la galerie locale.
  ///
  /// C'est ce qui a permis de retirer l'ancien editeur embarque : les
  /// collections utilisaient une version sans calques, sans stickers et
  /// sans selecteur de couleur, uniquement parce qu'elle savait faire cet
  /// enregistrement-la.
  final String? collectionId;

  /// Appele apres un enregistrement reussi (rafraichissement de l'appelant).
  final VoidCallback? onSaved;

  /// Insere dans un onglet plutot qu'ouvert en plein ecran : masque la
  /// fleche de retour (il n'y a nulle part ou revenir).
  final bool embedded;

  /// ⚠️ INDISPENSABLE en mode embarque : signale qu'un element est en cours
  /// de deplacement sur la carte. Le parent s'en sert pour geler son
  /// defilement vertical ET le balayage entre onglets — sans quoi faire
  /// glisser un element fait defiler la page au lieu de bouger l'element.
  final ValueChanged<bool>? onMoveModeChanged;

  const CardCreatorScreen({
    super.key,
    this.collectionId,
    this.onSaved,
    this.embedded = false,
    this.onMoveModeChanged,
  });

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
  // Index dans _layers, -1 = rien. Passe par un accesseur pour que TOUTE
  // sélection prévienne l'écran parent — impossible d'en oublier une.
  int _selectedRaw = -1;
  int get _selected => _selectedRaw;

  /// ⚠️ Tant qu'un élément est sélectionné, le parent GÈLE son défilement et
  /// le balayage entre onglets.
  ///
  /// Sans ça, faire glisser un élément horizontalement changeait d'onglet :
  /// dans l'arène des gestes, le TabBarView tranche avant que le
  /// déplacement de l'élément n'ait commencé. Geler pendant le glissement
  /// seul arrivait donc trop tard.
  set _selected(int i) {
    _selectedRaw = i;
    widget.onMoveModeChanged?.call(i >= 0);
  }

  // Mémorisation au début du geste (fix pinch + rotation 2 doigts)
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;

  // ── Aimantation ────────────────────────────────────────────────────────
  // Repères affichés pendant le déplacement (null = aucun).
  double? _guideX;
  double? _guideY;

  /// Distance sous laquelle l'élément se cale, en pixels de la carte.
  static const double _snapDist = 5;

  /// Aimante l'élément déplacé sur la marge gauche, le centre de la carte,
  /// ou l'alignement d'un AUTRE élément.
  ///
  /// Placer proprement des textes au doigt est sinon très pénible : sans
  /// aimantation, deux attaques ne sont jamais alignées au pixel près.
  void _snapLayer(CardLayer moving) {
    _guideX = null;
    _guideY = null;

    // Cibles horizontales : marge gauche, centre, puis les autres couches.
    final xTargets = <double>[12, _kCardW / 2];
    final yTargets = <double>[_kCardH / 2];
    for (final o in _layers) {
      if (identical(o, moving) || !o.visible) continue;
      if (o.role == LayerRole.background) continue;
      xTargets.add(o.x);
      yTargets.add(o.y);
    }

    for (final t in xTargets) {
      if ((moving.x - t).abs() <= _snapDist) {
        moving.x = t;
        _guideX = t;
        break;
      }
    }
    for (final t in yTargets) {
      if ((moving.y - t).abs() <= _snapDist) {
        moving.y = t;
        _guideY = t;
        break;
      }
    }
  }

  bool _showBack = false;
  int _backColor = 0xFF16213E;
  Uint8List? _backImageBytes;

  // ✨ Bloc 4
  int _frontColor = 0xFF1A1A2E;
  int _frameStyle = 0; // 0=aucun, 1=or, 2=argent, 3=néon, 4=pointillé

  // ✨ Données de jeu (PV, élément, attaques…). Éditées ici, rendues sur la
  // carte par « Appliquer le modèle » qui les transforme en couches.
  final CardStats _stats = CardStats();

  static const List<IconData> _stickerIcons = [
    Icons.star,
    Icons.bolt,
    Icons.favorite,
    Icons.shield,
    Icons.emoji_events,
    Icons.whatshot,
    Icons.auto_awesome,
    Icons.sports_soccer,
    Icons.music_note,
    Icons.diamond,
    Icons.rocket_launch,
    Icons.pets,
  ];

  IconData _iconFor(int? codePoint) => _stickerIcons.firstWhere(
    (i) => i.codePoint == codePoint,
    orElse: () => Icons.star,
  );

  CardLayer? get _bgLayer =>
      (_layers.isNotEmpty && _layers.first.role == LayerRole.background)
          ? _layers.first
          : null;

  /// ✨ Photo dans laquelle la pipette du sélecteur prélève des couleurs.
  /// C'est l'image du calque de fond — celle que le joueur voit derrière
  /// sa carte. Null tant qu'aucune image n'a été choisie : la pipette est
  /// alors simplement masquée.
  Uint8List? get _sampleBytes => _bgLayer?.bytes;

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

  // Insère une nouvelle couche juste sous le nom/la rareté
  // (= au-dessus de tout le reste) et la sélectionne.
  void _insertLayer(CardLayer layer) {
    final insertAt = _layers.indexWhere(
      (l) => l.role == LayerRole.cardName || l.role == LayerRole.cardRarity,
    );
    if (insertAt < 0) {
      _layers.add(layer);
      _selected = _layers.length - 1;
    } else {
      _layers.insert(insertAt, layer);
      _selected = insertAt;
    }
  }

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
        _insertLayer(
          CardLayer(
            id: CardLayer.newId(),
            type: LayerType.image,
            bytes: bytes,
            x: 0,
            y: 0,
          ),
        );
      }
    });
  }

  // ✨ Bloc 4 : image de fond (couche verrouillée à l'index 0)
  Future<void> _pickBackgroundImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      final bg = _bgLayer;
      if (bg != null) {
        bg.bytes = bytes;
        bg.storagePath = null; // nouvelle image → ancien chemin caduc
      } else {
        _layers.insert(
          0,
          CardLayer(
            id: CardLayer.newId(),
            type: LayerType.image,
            role: LayerRole.background,
            bytes: bytes,
          ),
        );
        if (_selected >= 0) _selected++;
      }
    });
  }

  void _removeBackgroundImage() {
    if (_bgLayer == null) return;
    setState(() {
      _layers.removeAt(0);
      if (_selected > 0) _selected--;
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
    setState(() => _insertLayer(layer));
    _editTextLayer(layer);
  }

  // ✨ Bloc 4 : stickers
  void _openStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stickers',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 6,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children:
                        _stickerIcons
                            .map(
                              (ic) => InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  setState(
                                    () => _insertLayer(
                                      CardLayer(
                                        id: CardLayer.newId(),
                                        type: LayerType.sticker,
                                        x: 110,
                                        y: 160,
                                        stickerIcon: ic.codePoint,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    ic,
                                    color: const Color(0xFFFFD700),
                                    size: 28,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// ✨ Sélecteur complet (teinte / saturation / luminosité / opacité,
  /// hexadécimal, pipette sur la photo) au lieu des 9 pastilles figées.
  Future<void> _editStickerColor(CardLayer layer) async {
    final c = await ColorPickerSheet.show(
      context,
      initial: Color(layer.stickerColor),
      sampleImage: _sampleBytes,
    );
    if (c == null) return;
    setState(() => layer.stickerColor = c.toARGB32());
  }

  void _moveLayer(int delta) {
    final i = _selected;
    final j = i + delta;
    // Le fond reste verrouillé tout en bas : rien ne passe dessous
    final minIndex = _bgLayer != null ? 1 : 0;
    if (i < minIndex || j < minIndex || j >= _layers.length) return;
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
                        // ✨ Palette complète (+ pipette sur la photo)
                        GestureDetector(
                          onTap: () async {
                            final c = await ColorPickerSheet.show(
                              context,
                              initial: selectedColor,
                              sampleImage: _sampleBytes,
                            );
                            if (c != null) {
                              setDialogState(() => selectedColor = c);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: selectedColor,
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(color: Colors.white24),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Choisir une couleur',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.palette_rounded,
                                  color: Colors.white54,
                                  size: 19,
                                ),
                              ],
                            ),
                          ),
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
        content = Icon(
          _iconFor(l.stickerIcon),
          size: 48,
          color: Color(l.stickerColor),
        );
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

    // ✨ Bloc 4 : le fond est rendu plein cadre, hors gestes
    // (IgnorePointer → taper dessus désélectionne, comme le fond couleur)
    if (l.role == LayerRole.background) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (l.bytes != null)
                Image.memory(
                  l.bytes!,
                  fit: l.bgFit == 1 ? BoxFit.contain : BoxFit.cover,
                  cacheWidth: 800,
                ),
              if (l.bgDarken > 0)
                Container(color: Colors.black.withValues(alpha: l.bgDarken)),
            ],
          ),
        ),
      );
    }

    final selected = i == _selected;

    // Marge tactile ajoutée plus bas autour des textes : on décale la
    // position d'autant pour que le rendu reste EXACTEMENT au même endroit
    // que sur la carte finale (qui, elle, n'a pas cette marge).
    final touchPad = l.type == LayerType.text ? 8.0 : 0.0;

    return Positioned(
      left: l.x - touchPad,
      top: l.y - touchPad,
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
          // Le gel du parent est declenche par l'accesseur _selected.
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
              } else {
                _snapLayer(l); // aimantation + repères d'alignement
              }
            }),
        onScaleEnd: (_) => setState(() {
          _guideX = null;
          _guideY = null;
        }),
        // Pas de degel du parent ici : l'element reste selectionne, donc
        // deplacable autant de fois qu'on veut. Le degel a lieu a la
        // deselection (appui hors de la carte).
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
              // Marge INVISIBLE autour du contenu : elle agrandit la zone
              // sensible au doigt. Un texte fin de 9 pt etait presque
              // impossible a attraper. Le rendu final n'est pas affecte,
              // seule la surface tactile l'est (HitTestBehavior.opaque).
              child: Padding(
                padding: EdgeInsets.all(touchPad),
                child: _layerContent(l, selected: selected),
              ),
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
        color: Color(_frontColor), // ✨ Bloc 4 : couleur de fond du recto
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
            // Repères d'alignement — visibles uniquement pendant un
            // déplacement aimanté. IgnorePointer : purement indicatifs.
            if (_guideX != null)
              Positioned(
                left: _guideX! - 0.5,
                top: 0,
                bottom: 0,
                child: const IgnorePointer(
                  child: SizedBox(
                    width: 1,
                    child: ColoredBox(color: Color(0xCC21E6C1)),
                  ),
                ),
              ),
            if (_guideY != null)
              Positioned(
                top: _guideY! - 0.5,
                left: 0,
                right: 0,
                child: const IgnorePointer(
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(color: Color(0xCC21E6C1)),
                  ),
                ),
              ),
            if (_effect == CardEffect.holographic) _buildHolographicEffect(),
            if (_effect == CardEffect.shiny) _buildShinyEffect(),
            // ✨ Bloc 4 : cadre décoratif par-dessus tout
            if (_frameStyle != 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _FramePainter(_frameStyle)),
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
              if (l.type == LayerType.sticker)
                _pillButton(Icons.palette, () => _editStickerColor(l)),
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
        if (l.role == LayerRole.background) return 'Fond (toujours derrière)';
        final images =
            _layers
                .where(
                  (e) =>
                      e.type == LayerType.image &&
                      e.role != LayerRole.background,
                )
                .toList();
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
                              var ln = _layers.length - 1 - newP;
                              // Rien ne passe sous le fond verrouillé
                              if (_bgLayer != null && ln < 1) ln = 1;
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
                            final isBg = l.role == LayerRole.background;
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
                                onTap:
                                    isBg
                                        ? null
                                        : () => refresh(() => _selected = i),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      if (isBg)
                                        const Padding(
                                          padding: EdgeInsets.all(6),
                                          child: Icon(
                                            Icons.lock,
                                            size: 18,
                                            color: Colors.white30,
                                          ),
                                        )
                                      else
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
                                      if (!l.isDeletable &&
                                          l.role != LayerRole.background)
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

  // ────────────────────────────────────────────────────────
  //   MODÈLE — transforme les données de jeu en couches
  // ────────────────────────────────────────────────────────

  /// Les couches du modèle ont un id STABLE (« tpl_hp », « tpl_atk0_name »…).
  ///
  /// C'est ce qui permet de rafraîchir l'aperçu à chaque frappe SANS effacer
  /// les déplacements de l'utilisateur : si la couche existe déjà, on met à
  /// jour son texte et sa couleur en gardant sa position ; sinon on la crée.
  static const _tplPrefix = 'tpl_';

  /// Ids produits lors de la dernière synchronisation — sert à supprimer les
  /// couches devenues inutiles (attaque effacée, PV vidés…).
  final Set<String> _templateLayerIds = {};

  /// Crée ou met à jour la couche `id`. Renvoie true si elle existait déjà.
  void _upsertTemplateText(
    String id,
    String text, {
    required double x,
    required double y,
    double size = 13,
    int color = 0xFFFFFFFF,
    bool bold = false,
    bool italic = false,
    bool resetPosition = false,
  }) {
    _templateLayerIds.add(id);
    final existing = _layers.indexWhere((l) => l.id == id);
    if (existing >= 0) {
      final l = _layers[existing];
      l.text = text;
      l.fontSize = size;
      l.color = color;
      l.bold = bold;
      l.italic = italic;
      if (resetPosition) {
        l.x = x;
        l.y = y;
      }
      return;
    }
    // ⚠️ Inséré SOUS le nom et la rareté, comme toute autre couche.
    // Avec un simple _layers.add(), les textes du modèle se retrouvaient
    // tout en haut de la pile et recouvraient le nom — qui devenait alors
    // impossible à attraper au doigt.
    final insertAt = _layers.indexWhere(
      (l) => l.role == LayerRole.cardName || l.role == LayerRole.cardRarity,
    );
    final layer = CardLayer(
      id: id,
      type: LayerType.text,
      x: x,
      y: y,
      text: text,
      fontSize: size,
      color: color,
      bold: bold,
      italic: italic,
      shadowOn: true,
      shadowDx: 1,
      shadowDy: 1,
      shadowBlur: 3,
    );
    if (insertAt < 0) {
      _layers.add(layer);
    } else {
      _layers.insert(insertAt, layer);
    }
  }

  /// Génère (ou régénère) les couches de texte correspondant aux données de
  /// jeu, positionnées comme sur une vraie carte à collectionner.
  ///
  /// Les couches précédemment produites par le modèle sont retirées d'abord :
  /// on peut donc modifier les PV puis réappliquer sans accumuler de doublons.
  /// ⚠️ Les couches créées à la main par l'utilisateur ne sont JAMAIS
  /// touchées — seules celles dont l'id est dans _templateLayerIds partent.
  /// Met l'aperçu en accord avec les données de jeu.
  ///
  /// Appelé à CHAQUE modification (frappe, choix d'élément…) : le retour
  /// visuel est immédiat, sans avoir à valider quoi que ce soit.
  /// [resetPositions] remet les éléments à leur place d'origine — réservé au
  /// bouton « Réinitialiser la disposition ».
  void _applyTemplate({bool resetPositions = false}) {
    setState(() {
      final produced = <String>{};
      final el = _stats.element;

      void put(
        String id,
        String text, {
        required double x,
        required double y,
        double size = 13,
        int color = 0xFFFFFFFF,
        bool bold = false,
        bool italic = false,
      }) {
        produced.add(id);
        _upsertTemplateText(
          id,
          text,
          x: x,
          y: y,
          size: size,
          color: color,
          bold: bold,
          italic: italic,
          resetPosition: resetPositions,
        );
      }

      // ── PV + élément, en haut à droite ──
      if (_stats.hp != null) {
        put(
          '${_tplPrefix}hp',
          el == CardElement.neutre
              ? '${_stats.hp} PV'
              : '${el.symbol} ${_stats.hp} PV',
          x: _kCardW - 96,
          y: 10,
          size: 15,
          bold: true,
          color: el == CardElement.neutre ? 0xFFFFFFFF : el.color,
        );
      } else if (el != CardElement.neutre) {
        // Élément choisi sans PV : on affiche quand même le symbole, sinon
        // cliquer « Feu » ne produirait aucun retour visuel.
        put(
          '${_tplPrefix}hp',
          el.symbol,
          x: _kCardW - 46,
          y: 10,
          size: 18,
          bold: true,
          color: el.color,
        );
      }

      // ── Attaques, sous l'illustration ──
      double y = 250;
      for (int i = 0; i < _stats.attacks.length; i++) {
        final a = _stats.attacks[i];
        if (a.name.trim().isEmpty) continue;
        final cost = List.filled(a.cost.clamp(0, 4), el.symbol).join();
        put(
          '${_tplPrefix}atk${i}_name',
          '$cost ${a.name}'.trim(),
          x: 12,
          y: y,
          size: 12.5,
          bold: true,
        );
        if (a.damage > 0) {
          put(
            '${_tplPrefix}atk${i}_dmg',
            '${a.damage}',
            x: _kCardW - 46,
            y: y,
            size: 14,
            bold: true,
            color: el.color,
          );
        }
        y += 18;
        if (a.effect.trim().isNotEmpty) {
          put(
            '${_tplPrefix}atk${i}_fx',
            a.effect.trim(),
            x: 12,
            y: y,
            size: 9.5,
            color: 0xCCFFFFFF,
          );
          y += 14;
        }
      }

      // ── Texte d'ambiance ──
      if (_stats.flavorText.trim().isNotEmpty) {
        put(
          '${_tplPrefix}flavor',
          '« ${_stats.flavorText.trim()} »',
          x: 12,
          y: y + 4,
          size: 9.5,
          italic: true,
          color: 0xB3FFFFFF,
        );
      }

      // ── Faiblesse, tout en bas ──
      if (_stats.weakness != null) {
        put(
          '${_tplPrefix}weak',
          'Faiblesse ${_stats.weakness!.symbol}',
          x: 12,
          y: _kCardH - 26,
          size: 9.5,
          color: 0xCCFFFFFF,
        );
      }

      // Couches du modèle devenues inutiles (attaque supprimée, PV vidés…).
      final stale = _templateLayerIds.difference(produced);
      if (stale.isNotEmpty) {
        _layers.removeWhere((l) => stale.contains(l.id));
        _templateLayerIds.removeAll(stale);
        _selected = -1;
      }
    });
  }

  // ────────────────────────────────────────────────────────
  //   SECTION « JEU » — PV, élément, attaques, ambiance
  // ────────────────────────────────────────────────────────

  InputDecoration _gameField(String label, {String? suffix}) => InputDecoration(
    labelText: label,
    suffixText: suffix,
    labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
    suffixStyle: const TextStyle(color: Colors.white54, fontSize: 12),
    isDense: true,
    filled: true,
    fillColor: const Color(0xFF16213E),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    ),
  );

  Widget _elementChips({
    required CardElement? value,
    required ValueChanged<CardElement?> onPick,
    bool allowNone = false,
  }) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (allowNone)
        _pickChip(
          label: 'Aucune',
          selected: value == null,
          color: 0xFF9E9E9E,
          onTap: () => onPick(null),
        ),
      ...CardElement.values.map(
        (e) => _pickChip(
          label: '${e.symbol} ${e.label}',
          selected: value == e,
          color: e.color,
          onTap: () => onPick(e),
        ),
      ),
    ],
  );

  Widget _pickChip({
    required String label,
    required bool selected,
    required int color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? Color(color).withValues(alpha: 0.25) : const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? Color(color) : Colors.white24,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Color(color) : Colors.white70,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
  );

  List<Widget> _buildGameSection() => [
    _buildSectionLabel('Jeu'),
    // ⚠️ Comme les autres sections, le contenu suit l'accordéon. Sans ce
    // test, appuyer sur « JEU » fermait les autres sections mais laissait
    // celle-ci ouverte en permanence.
    if (_openSection == 'Jeu') ...[
    const SizedBox(height: 4),
    const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Facultatif. Ce que tu saisis apparaît aussitôt sur la carte, et '
        'reste déplaçable comme n\'importe quel élément.',
        style: TextStyle(color: Colors.white38, fontSize: 11.5),
      ),
    ),
    const SizedBox(height: 12),

    // PV
    SizedBox(
      width: 150,
      child: TextFormField(
        initialValue: _stats.hp?.toString() ?? '',
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: _gameField('Points de vie', suffix: 'PV'),
        onChanged: (v) {
          _stats.hp = int.tryParse(v.trim());
          _applyTemplate();
        },
      ),
    ),
    const SizedBox(height: 14),

    const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Élément',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ),
    const SizedBox(height: 6),
    _elementChips(
      value: _stats.element,
      onPick: (e) {
        _stats.element = e ?? CardElement.neutre;
        _applyTemplate();
      },
    ),
    const SizedBox(height: 14),

    const Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'Faiblesse',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
    ),
    const SizedBox(height: 6),
    _elementChips(
      value: _stats.weakness,
      allowNone: true,
      onPick: (e) {
        _stats.weakness = e;
        _applyTemplate();
      },
    ),
    const SizedBox(height: 16),

    // Attaques
    Row(
      children: [
        const Expanded(
          child: Text(
            'Attaques',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        if (_stats.attacks.length < 3)
          TextButton.icon(
            onPressed: () {
              _stats.attacks.add(CardAttack());
              _applyTemplate();
            },
            icon: const Icon(Icons.add, size: 16, color: Color(0xFF6C4AB6)),
            label: const Text(
              'Ajouter',
              style: TextStyle(color: Color(0xFF6C4AB6), fontSize: 12),
            ),
          ),
      ],
    ),
    for (int i = 0; i < _stats.attacks.length; i++) ...[
      _attackEditor(i),
      const SizedBox(height: 10),
    ],
    const SizedBox(height: 4),

    // Texte d'ambiance
    TextFormField(
      initialValue: _stats.flavorText,
      maxLines: 2,
      style: const TextStyle(color: Colors.white),
      decoration: _gameField('Texte d\'ambiance'),
      onChanged: (v) {
        _stats.flavorText = v;
        _applyTemplate();
      },
    ),
    const SizedBox(height: 14),

    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _applyTemplate(resetPositions: true),
        icon: const Icon(Icons.auto_fix_high, size: 18),
        label: const Text('Réinitialiser la disposition'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C4AB6),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    ], // fin de la section « Jeu » repliable
  ];

  Widget _attackEditor(int i) {
    final a = _stats.attacks[i];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: a.name,
                  style: const TextStyle(color: Colors.white),
                  decoration: _gameField('Nom de l\'attaque'),
                  onChanged: (v) {
                    a.name = v;
                    _applyTemplate();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Supprimer',
                onPressed: () {
                  _stats.attacks.removeAt(i);
                  _applyTemplate();
                },
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFFF5D73),
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: a.cost.toString(),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _gameField('Coût', suffix: '⚡'),
                  onChanged: (v) {
                    a.cost = (int.tryParse(v.trim()) ?? 0).clamp(0, 4);
                    _applyTemplate();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: a.damage.toString(),
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _gameField('Dégâts'),
                  onChanged: (v) {
                    a.damage = int.tryParse(v.trim()) ?? 0;
                    _applyTemplate();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: a.effect,
            style: const TextStyle(color: Colors.white),
            decoration: _gameField('Effet (facultatif)'),
            onChanged: (v) {
              a.effect = v;
              _applyTemplate();
            },
          ),
        ],
      ),
    );
  }

  // ── Navigation dans le panneau de réglages ──────────────────────────────
  // Le panneau est long (rareté, effet, jeu, fond, cadre…). Chaque titre
  // porte une clé pour qu'on puisse y sauter directement depuis la barre de
  // raccourcis, au lieu de faire défiler à l'aveugle.
  final Map<String, GlobalKey> _sectionKeys = {};

  /// Section actuellement dépliée — une seule à la fois (accordéon).
  ///
  /// Le panneau enchaînait 6 sections dépliées en permanence : atteindre
  /// « Cadre » demandait de faire défiler des centaines de pixels de
  /// réglages inutiles. En accordéon, tout tient sur un écran.
  /// `null` = tout replié.
  String? _openSection = 'Rareté';

  void _toggleSection(String label) {
    setState(() => _openSection = _openSection == label ? null : label);
    // Replier une section au-dessus fait « remonter » celle qu'on ouvre :
    // on la ramène en vue une fois la nouvelle disposition calculée.
    if (_openSection == label) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToSection(label));
    }
  }

  GlobalKey _keyFor(String label) =>
      _sectionKeys.putIfAbsent(label, () => GlobalKey());

  Future<void> _jumpToSection(String label) async {
    final ctx = _sectionKeys[label]?.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: 0.05, // colle le titre en haut de la zone visible
    );
  }

  /// Barre de raccourcis : n'affiche que les sections réellement présentes
  /// à l'écran (elles diffèrent entre recto et verso).
  Widget _buildSectionNav() {
    final labels =
        _showBack
            ? const ['Couleur de fond']
            : const ['Rareté', 'Effet', 'Jeu', 'Fond', 'Cadre'];
    if (labels.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final active = _openSection == labels[i];
          return GestureDetector(
            // Ouvre la section ET y défile : un raccourci qui se contenterait
            // de défiler vers une section repliée ne montrerait rien.
            onTap: () {
              if (!active) _toggleSection(labels[i]);
            },
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color:
                    active
                        ? const Color(0xFF6C4AB6)
                        : const Color(0xFF16213E),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: active ? const Color(0xFF9B7BE0) : Colors.white24,
                ),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: active ? Colors.white : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    final open = _openSection == label;
    return GestureDetector(
      key: _keyFor(label),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSection(label),
      child: Container(
        // Barre pleine largeur : toute la ligne est cliquable, pas seulement
        // le texte — bien plus facile à viser au doigt.
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: open ? const Color(0xFF241C3A) : const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: open ? const Color(0xFF6C4AB6) : Colors.white12,
            width: open ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: open ? const Color(0xFF9B7BE0) : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: open ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Icon(
              open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              color: open ? const Color(0xFF9B7BE0) : Colors.white38,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

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
      // Copie : la carte enregistrée ne doit pas partager l'objet mutable
      // que l'éditeur continue de modifier après la sauvegarde.
      stats: _stats.copy(),
      backImageBytes: _backImageBytes,
      backColor: _backColor,
      frontColor: _frontColor,
      frameStyle: _frameStyle,
    );
    // Sans collection : la carte reste dans la galerie locale.
    if (widget.collectionId == null) {
      await CardStorage.addCard(card);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Carte sauvegardée !'),
          backgroundColor: Color(0xFF4CAF50),
          duration: Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
      return;
    }

    // ── Enregistrement DANS une collection ────────────────────────────────
    final colId = widget.collectionId!;
    try {
      // Images vers Supabase Storage. En cas d'echec (hors-ligne), la carte
      // conserve son base64 : rien ne casse.
      final uploaded = await CardMediaService.instance.uploadCardImages(card);
      await CardStorage.addCard(uploaded);

      bool supabaseOk = false;
      try {
        await CollectionService.instance.addCardToCollection(
          colId,
          uploaded.id,
          uploaded.name,
          _rarityLabel,
          uploaded, // card_data : indispensable aux AUTRES membres
        );
        supabaseOk = true;
      } catch (e) {
        reportError(
          'Ajout de la carte a la collection',
          e,
          level: ErrorLevel.dataLoss,
        );
      }

      // Repli hors-ligne : on memorise l'id en local pour que la carte
      // apparaisse quand meme dans le catalogue de l'appareil.
      if (!supabaseOk) {
        final prefs = await SharedPreferences.getInstance();
        final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
        final key = 'local_cat_${uid}_$colId';
        final existing = prefs.getStringList(key) ?? [];
        existing.add(uploaded.id);
        await prefs.setStringList(key, existing);
      }

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            supabaseOk
                ? '✅ Carte ajoutée à la collection !'
                : '⚠️ Carte enregistrée sur l\'appareil uniquement.',
          ),
          backgroundColor:
              supabaseOk ? const Color(0xFF4CAF50) : const Color(0xFFB26A00),
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      reportError(
        'Enregistrement de la carte',
        e,
        level: ErrorLevel.dataLoss,
      );
    }
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
        // En mode embarqué, la barre sert de barre d'outils : pas de flèche
        // de retour, sinon elle quitterait tout l'écran de collection.
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          widget.embedded ? 'Nouvelle carte' : 'Créer une carte',
          style: const TextStyle(color: Colors.white),
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
                  // Raccourcis vers les sections : évite de faire défiler
                  // tout le panneau pour atteindre « Cadre » ou « Jeu ».
                  _buildSectionNav(),
                  const SizedBox(height: 12),
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
                    if (_openSection == 'Rareté') ...[
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
                    ],
                    const SizedBox(height: 16),
                    _buildSectionLabel('Effet'),
                    if (_openSection == 'Effet') ...[
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
                    ],
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickImage(isBack: false),
                            icon: const Icon(Icons.photo_library, size: 18),
                            label: const Text(
                              'Image',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16213E),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _addTextZone,
                            icon: const Icon(Icons.text_fields, size: 18),
                            label: const Text(
                              'Texte',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16213E),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _openStickerPicker,
                            icon: const Icon(Icons.emoji_emotions, size: 18),
                            label: const Text(
                              'Sticker',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16213E),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ..._buildGameSection(),
                    const SizedBox(height: 24),
                    // ✨ Bloc 4 : fond du recto
                    _buildSectionLabel('Fond'),
                    if (_openSection == 'Fond') ...[
                    const SizedBox(height: 8),
                    // ✨ Raccourcis + accès à la palette complète
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ..._backColors.map((c) {
                          return GestureDetector(
                            onTap: () => setState(() => _frontColor = c),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border:
                                    _frontColor == c
                                        ? Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        )
                                        : Border.all(color: Colors.white24),
                              ),
                            ),
                          );
                        }),
                        GestureDetector(
                          onTap: () async {
                            final c = await ColorPickerSheet.show(
                              context,
                              initial: Color(_frontColor),
                              sampleImage: _sampleBytes,
                              allowAlpha: false,
                            );
                            if (c != null) {
                              setState(() => _frontColor = c.toARGB32());
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFC83D),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Color(0xFFFFC83D),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickBackgroundImage,
                            icon: const Icon(Icons.wallpaper, size: 18),
                            label: Text(
                              _bgLayer == null
                                  ? 'Image de fond'
                                  : 'Changer l\'image de fond',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16213E),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (_bgLayer != null)
                          IconButton(
                            onPressed: _removeBackgroundImage,
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Retirer l\'image de fond',
                          ),
                      ],
                    ),
                    if (_bgLayer != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _bgLayer!.bgFit = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _bgLayer!.bgFit == 0
                                        ? const Color(0xFF6C4AB6)
                                        : Colors.transparent,
                                border: Border.all(
                                  color: const Color(0xFF6C4AB6),
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'Remplir',
                                style: TextStyle(
                                  color:
                                      _bgLayer!.bgFit == 0
                                          ? Colors.white
                                          : const Color(0xFF6C4AB6),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => setState(() => _bgLayer!.bgFit = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _bgLayer!.bgFit == 1
                                        ? const Color(0xFF6C4AB6)
                                        : Colors.transparent,
                                border: Border.all(
                                  color: const Color(0xFF6C4AB6),
                                ),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                'Ajuster',
                                style: TextStyle(
                                  color:
                                      _bgLayer!.bgFit == 1
                                          ? Colors.white
                                          : const Color(0xFF6C4AB6),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const SizedBox(
                            width: 70,
                            child: Text(
                              'Assombrir',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _bgLayer!.bgDarken.clamp(0.0, 0.7),
                              min: 0,
                              max: 0.7,
                              activeColor: const Color(0xFF6C4AB6),
                              onChanged:
                                  (v) => setState(() => _bgLayer!.bgDarken = v),
                            ),
                          ),
                          SizedBox(
                            width: 38,
                            child: Text(
                              '${(_bgLayer!.bgDarken * 100).round()}%',
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
                    ],
                    const SizedBox(height: 16),
                    // ✨ Bloc 4 : cadre décoratif
                    _buildSectionLabel('Cadre'),
                    if (_openSection == 'Cadre') ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          const {
                            0: 'Aucun',
                            1: 'Or',
                            2: 'Argent',
                            3: 'Néon',
                            4: 'Pointillé',
                          }.entries.map((e) {
                            final sel = _frameStyle == e.key;
                            return GestureDetector(
                              onTap: () => setState(() => _frameStyle = e.key),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      sel
                                          ? const Color(0xFF6C4AB6)
                                          : Colors.transparent,
                                  border: Border.all(
                                    color: const Color(0xFF6C4AB6),
                                  ),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  e.value,
                                  style: TextStyle(
                                    color:
                                        sel
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
                    ],
                  ] else ...[
                    _buildSectionLabel('Couleur de fond'),
                    if (_openSection == 'Couleur de fond') ...[
                    const SizedBox(height: 12),
                    // ✨ Raccourcis + accès à la palette complète
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ..._backColors.map((c) {
                          return GestureDetector(
                            onTap: () => setState(() => _backColor = c),
                            child: Container(
                              width: 36,
                              height: 36,
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
                        }),
                        GestureDetector(
                          onTap: () async {
                            final c = await ColorPickerSheet.show(
                              context,
                              initial: Color(_backColor),
                              sampleImage: _sampleBytes,
                              allowAlpha: false,
                            );
                            if (c != null) {
                              setState(() => _backColor = c.toARGB32());
                            }
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFC83D),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Color(0xFFFFC83D),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    ],
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   ✨ Bloc 4 : CADRES DÉCORATIFS (CustomPainter, zéro asset)
//   1 = Or  ·  2 = Argent  ·  3 = Néon  ·  4 = Pointillé
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FramePainter extends CustomPainter {
  final int style;
  _FramePainter(this.style);

  RRect _rrect(Size size, double inset, double radius) =>
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          inset,
          inset,
          size.width - inset * 2,
          size.height - inset * 2,
        ),
        Radius.circular(radius),
      );

  void _corners(Canvas canvas, Size size, Color color) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round;
    const len = 16.0;
    const m = 14.0; // marge depuis le coin
    final w = size.width, h = size.height;
    // Petites équerres diagonales dans les 4 coins
    canvas.drawLine(Offset(m, m + len), Offset(m + len, m), paint);
    canvas.drawLine(Offset(w - m, m + len), Offset(w - m - len, m), paint);
    canvas.drawLine(Offset(m, h - m - len), Offset(m + len, h - m), paint);
    canvas.drawLine(
      Offset(w - m, h - m - len),
      Offset(w - m - len, h - m),
      paint,
    );
  }

  void _doubleStroke(Canvas canvas, Size size, Color outer, Color inner) {
    canvas.drawRRect(
      _rrect(size, 5, 10),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = outer,
    );
    canvas.drawRRect(
      _rrect(size, 10, 7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = inner,
    );
    _corners(canvas, size, outer);
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case 1: // Or
        _doubleStroke(
          canvas,
          size,
          const Color(0xFFFFD700),
          const Color(0xFFFFF3B0),
        );
      case 2: // Argent
        _doubleStroke(
          canvas,
          size,
          const Color(0xFFC0C0C0),
          const Color(0xFFF2F2F2),
        );
      case 3: // Néon : halo flou + trait net
        canvas.drawRRect(
          _rrect(size, 6, 10),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = const Color(0xAA00E5FF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
        canvas.drawRRect(
          _rrect(size, 6, 10),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFFB2FFFF),
        );
      case 4: // Pointillé
        final paint =
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round
              ..color = Colors.white70;
        final path = Path()..addRRect(_rrect(size, 6, 10));
        for (final metric in path.computeMetrics()) {
          double d = 0;
          while (d < metric.length) {
            canvas.drawPath(
              metric.extractPath(d, min(d + 8, metric.length)),
              paint,
            );
            d += 14;
          }
        }
    }
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.style != style;
}
