// color_picker_sheet.dart
// ─────────────────────────────────────────────────────────────────────────
//   SÉLECTEUR DE COULEUR COMPLET — partagé par tout le créateur de cartes.
//
//   Remplace les quatre listes de 9 pastilles codées en dur (couleur de
//   texte, de sticker, de fond recto, de fond verso).
//
//   Contenu :
//     • carré saturation / luminosité + curseur de teinte
//       (plus précis au doigt qu'une roue chromatique)
//     • curseur d'opacité sur damier
//     • champ hexadécimal éditable (#RRGGBB ou #AARRGGBB)
//     • PIPETTE : prélève une couleur directement dans la photo de la carte
//     • couleurs récentes (mémorisées le temps de la session)
//     • présélections aux tokens arcade de l'app
//
//   Usage :
//     final c = await ColorPickerSheet.show(
//       context,
//       initial: Color(layer.color),
//       sampleImage: card.imageBytes,   // active la pipette, facultatif
//     );
//     if (c != null) setState(() => layer.color = c.toARGB32());
// ─────────────────────────────────────────────────────────────────────────

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// services.dart réexporte déjà Uint8List : pas besoin de dart:typed_data.
import 'package:flutter/services.dart';

class ColorPickerSheet extends StatefulWidget {
  final Color initial;

  /// Octets d'une image dans laquelle prélever des couleurs.
  /// Si null, l'onglet pipette est masqué.
  final Uint8List? sampleImage;

  /// Autoriser le réglage de l'opacité. À désactiver pour un fond opaque.
  final bool allowAlpha;

  const ColorPickerSheet({
    super.key,
    required this.initial,
    this.sampleImage,
    this.allowAlpha = true,
  });

  /// Couleurs récemment validées, toutes instances confondues.
  static final List<Color> _recent = [];

  static Future<Color?> show(
    BuildContext context, {
    required Color initial,
    Uint8List? sampleImage,
    bool allowAlpha = true,
  }) {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: const Color(0xFF1B1430),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder:
          (_) => ColorPickerSheet(
            initial: initial,
            sampleImage: sampleImage,
            allowAlpha: allowAlpha,
          ),
    );
  }

  @override
  State<ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<ColorPickerSheet> {
  static const _cream = Color(0xFFF6EEDD);
  static const _gold = Color(0xFFFFC83D);
  static const _line = Color(0xFF3A3050);

  // Présélections : les tokens de l'app + les neutres indispensables.
  static const _presets = <int>[
    0xFFFFFFFF, 0xFF000000, 0xFFF6EEDD, 0xFF9AA0B0,
    0xFFFFC83D, 0xFF21E6C1, 0xFFFF5D73, 0xFFB45CFF,
    0xFF2FA8FF, 0xFF3FD17A, 0xFF14101F, 0xFF1E1830,
  ];

  late double _h; // 0..360
  late double _s; // 0..1
  late double _v; // 0..1
  late double _a; // 0..1

  late final TextEditingController _hexCtrl;
  bool _editingHex = false;

  // ── Pipette ──────────────────────────────────────────────────────────
  bool _eyedropper = false;
  ui.Image? _decoded;
  ByteData? _pixels;
  bool _decoding = false;

  Color get _color => HSVColor.fromAHSV(_a, _h, _s, _v).toColor();

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initial);
    _h = hsv.hue;
    _s = hsv.saturation;
    _v = hsv.value;
    _a = widget.allowAlpha ? widget.initial.a : 1.0;
    _hexCtrl = TextEditingController(text: _hex(_color));
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _decoded?.dispose();
    super.dispose();
  }

  String _hex(Color c) {
    String two(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final rgb = '${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
    return widget.allowAlpha && c.a < 1.0
        ? '#${two(c.a).toUpperCase()}$rgb'
        : '#$rgb';
  }

  void _syncHex() {
    if (_editingHex) return;
    _hexCtrl.text = _hex(_color);
  }

  void _applyHex(String raw) {
    var s = raw.trim().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return;
    final c = Color(v);
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _h = hsv.hue;
      _s = hsv.saturation;
      _v = hsv.value;
      if (widget.allowAlpha) _a = c.a;
    });
  }

  void _setColor(Color c) {
    final hsv = HSVColor.fromColor(c);
    setState(() {
      _h = hsv.hue;
      _s = hsv.saturation;
      _v = hsv.value;
      if (widget.allowAlpha) _a = c.a;
    });
    _syncHex();
  }

  // ── Décodage de l'image pour la pipette ──────────────────────────────
  // Fait UNE seule fois, à la première ouverture de la pipette : décoder
  // à chaque contact rendrait le glissement inutilisable.
  Future<void> _prepareEyedropper() async {
    if (_pixels != null || _decoding) return;
    setState(() => _decoding = true);
    try {
      final codec = await ui.instantiateImageCodec(
        widget.sampleImage!,
        targetWidth: 600, // suffisant pour prélever, léger en mémoire
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (!mounted) return;
      setState(() {
        _decoded = frame.image;
        _pixels = data;
        _decoding = false;
      });
    } catch (e) {
      if (mounted) setState(() => _decoding = false);
    }
  }

  void _sampleAt(Offset local, Size box) {
    final img = _decoded;
    final px = _pixels;
    if (img == null || px == null) return;

    // La photo est affichée en BoxFit.contain : on retrouve le rectangle
    // réellement occupé pour convertir le point touché en pixel image.
    final scale = (box.width / img.width) < (box.height / img.height)
        ? box.width / img.width
        : box.height / img.height;
    final dw = img.width * scale;
    final dh = img.height * scale;
    final dx = (box.width - dw) / 2;
    final dy = (box.height - dh) / 2;

    final ix = ((local.dx - dx) / scale).floor();
    final iy = ((local.dy - dy) / scale).floor();
    if (ix < 0 || iy < 0 || ix >= img.width || iy >= img.height) return;

    final o = (iy * img.width + ix) * 4;
    if (o + 3 >= px.lengthInBytes) return;
    _setColor(
      Color.fromARGB(
        255,
        px.getUint8(o),
        px.getUint8(o + 1),
        px.getUint8(o + 2),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        color: Color(0xFF9A90B5),
        fontSize: 11,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _svSquare() => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      const h = 170.0;
      void handle(Offset p) {
        setState(() {
          _s = (p.dx / w).clamp(0.0, 1.0);
          _v = 1 - (p.dy / h).clamp(0.0, 1.0);
        });
        _syncHex();
      }

      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white,
                          HSVColor.fromAHSV(1, _h, 1, 1).toColor(),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: (_s * w) - 11,
                  top: ((1 - _v) * h) - 11,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _slider({
    required List<Color> colors,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
    bool checker = false,
  }) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      void handle(Offset p) {
        onChanged((p.dx / w).clamp(0.0, 1.0) * max);
        _syncHex();
      }

      return GestureDetector(
        onPanDown: (d) => handle(d.localPosition),
        onPanUpdate: (d) => handle(d.localPosition),
        child: SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              if (checker)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CustomPaint(painter: _CheckerPainter()),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(colors: colors),
                  ),
                ),
              ),
              Positioned(
                left: ((value / max) * w - 11).clamp(0.0, w - 22),
                child: Container(
                  width: 22,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _swatches(List<Color> colors) => Wrap(
    spacing: 9,
    runSpacing: 9,
    children:
        colors.map((c) {
          final sel = c.toARGB32() == _color.toARGB32();
          return GestureDetector(
            onTap: () => _setColor(c),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: sel ? _gold : Colors.white24,
                  width: sel ? 2.5 : 1,
                ),
              ),
            ),
          );
        }).toList(),
  );

  Widget _eyedropperView() {
    if (_decoding || _pixels == null) {
      return const SizedBox(
        height: 170,
        child: Center(child: CircularProgressIndicator(color: _gold)),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final box = Size(c.maxWidth, 170);
        return GestureDetector(
          onPanDown: (d) => _sampleAt(d.localPosition, box),
          onPanUpdate: (d) => _sampleAt(d.localPosition, box),
          child: Container(
            width: box.width,
            height: box.height,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.memory(
                widget.sampleImage!,
                fit: BoxFit.contain,
                cacheWidth: 600,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.sampleImage != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          12,
          18,
          MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Aperçu + hexadécimal
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _CheckerPainter()),
                          ColoredBox(color: _color),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _hexCtrl,
                      style: const TextStyle(
                        color: _cream,
                        fontFamily: 'monospace',
                        fontSize: 15,
                        letterSpacing: 1.5,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9a-fA-F#]'),
                        ),
                        LengthLimitingTextInputFormatter(9),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _line),
                        ),
                      ),
                      onTap: () => _editingHex = true,
                      onChanged: _applyHex,
                      onEditingComplete: () {
                        _editingHex = false;
                        _syncHex();
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                  if (hasImage) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        setState(() => _eyedropper = !_eyedropper);
                        if (_eyedropper) _prepareEyedropper();
                      },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color:
                              _eyedropper
                                  ? _gold
                                  : Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: _eyedropper ? _gold : _line,
                          ),
                        ),
                        child: Icon(
                          Icons.colorize_rounded,
                          size: 21,
                          color:
                              _eyedropper ? const Color(0xFF2A1C00) : _cream,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),

              if (_eyedropper) ...[
                _label('TOUCHE LA PHOTO POUR PRÉLEVER'),
                _eyedropperView(),
              ] else ...[
                _svSquare(),
                const SizedBox(height: 14),
                _slider(
                  colors: const [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                  value: _h,
                  max: 360,
                  onChanged: (v) => setState(() => _h = v),
                ),
                if (widget.allowAlpha) ...[
                  const SizedBox(height: 12),
                  _slider(
                    colors: [
                      _color.withValues(alpha: 0),
                      _color.withValues(alpha: 1),
                    ],
                    value: _a,
                    max: 1,
                    checker: true,
                    onChanged: (v) => setState(() => _a = v),
                  ),
                ],
              ],

              const SizedBox(height: 20),
              _label('PALETTE'),
              _swatches(_presets.map(Color.new).toList()),

              if (ColorPickerSheet._recent.isNotEmpty) ...[
                const SizedBox(height: 18),
                _label('RÉCENTES'),
                _swatches(ColorPickerSheet._recent),
              ],

              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(color: Color(0xFF9A90B5)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () {
                        final c = _color;
                        ColorPickerSheet._recent
                          ..removeWhere(
                            (x) => x.toARGB32() == c.toARGB32(),
                          )
                          ..insert(0, c);
                        if (ColorPickerSheet._recent.length > 12) {
                          ColorPickerSheet._recent.removeLast();
                        }
                        Navigator.pop(context, c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: const Color(0xFF2A1C00),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Valider',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Damier gris clair / gris foncé, pour rendre l'opacité lisible.
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const s = 7.0;
    final a = Paint()..color = const Color(0xFF6E6880);
    final b = Paint()..color = const Color(0xFF4A4460);
    canvas.drawRect(Offset.zero & size, b);
    for (var y = 0.0; y < size.height; y += s) {
      for (var x = 0.0; x < size.width; x += s) {
        if (((x / s).floor() + (y / s).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, s, s), a);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}