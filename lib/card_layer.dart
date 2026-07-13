// card_layer.dart — Modèle de couche UNIFIÉ (v5, bloc 1)
//
// Tout élément posé sur la carte est une CardLayer :
//   • image (photo de la galerie)
//   • texte (zones libres, mais aussi le NOM et la RARETÉ de la carte,
//     identifiés par leur `role` → non supprimables)
//   • sticker (bloc 4, champs déjà prévus pour ne plus changer le schéma)
//
// L'ordre dans la liste = ordre d'empilement : index 0 tout derrière,
// dernier index tout devant.
//
// Les champs de style texte (gras/italique/contour/ombre) et sticker sont
// déjà sérialisés même si l'UI arrive aux blocs 3-4 → une seule migration.

import 'dart:convert';
import 'package:flutter/foundation.dart';

enum LayerType { image, text, sticker }

/// Rôle spécial d'une couche texte.
/// cardName / cardRarity : positionnables et transformables comme les autres,
/// mais leur contenu est piloté par la carte (nom, rareté) et elles ne
/// peuvent être ni supprimées ni dupliquées.
enum LayerRole { normal, cardName, cardRarity }

class CardLayer {
  final String id;
  final LayerType type;
  final LayerRole role;

  // ── Transformations communes ──────────────────────────────
  double x, y;
  double scale;
  double rotation; // en degrés (plus lisible pour l'UI que les radians)
  bool flipH, flipV;
  double opacity;
  bool visible;

  // ── Image ─────────────────────────────────────────────────
  Uint8List? bytes;
  String? storagePath; // chemin Supabase Storage (null = pas encore uploadé)

  // ── Texte ─────────────────────────────────────────────────
  String text;
  double fontSize;
  int color;
  String? fontFamily;
  bool bold, italic; // UI au bloc 3
  int? outlineColor; // contour : null = désactivé (bloc 3)
  double outlineWidth;
  bool shadowOn; // ombre (bloc 3)
  double shadowDx, shadowDy, shadowBlur;
  int shadowColor;

  // ── Sticker (bloc 4) ──────────────────────────────────────
  int? stickerIcon; // codePoint de l'icône Material
  int stickerColor;

  CardLayer({
    required this.id,
    required this.type,
    this.role = LayerRole.normal,
    this.x = 0,
    this.y = 0,
    this.scale = 1.0,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.opacity = 1.0,
    this.visible = true,
    this.bytes,
    this.storagePath,
    this.text = '',
    this.fontSize = 16,
    this.color = 0xFFFFFFFF,
    this.fontFamily,
    this.bold = false,
    this.italic = false,
    this.outlineColor,
    this.outlineWidth = 2,
    this.shadowOn = false,
    this.shadowDx = 2,
    this.shadowDy = 2,
    this.shadowBlur = 4,
    this.shadowColor = 0xFF000000,
    this.stickerIcon,
    this.stickerColor = 0xFFFFD700,
  });

  static int _counter = 0;
  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';

  bool get isDeletable => role == LayerRole.normal;

  /// Copie profonde, décalée de 12 px (pour « Dupliquer »).
  CardLayer clone() => CardLayer(
    id: newId(),
    type: type,
    role: LayerRole.normal,
    x: x + 12,
    y: y + 12,
    scale: scale,
    rotation: rotation,
    flipH: flipH,
    flipV: flipV,
    opacity: opacity,
    visible: visible,
    bytes: bytes,
    storagePath: storagePath,
    text: text,
    fontSize: fontSize,
    color: color,
    fontFamily: fontFamily,
    bold: bold,
    italic: italic,
    outlineColor: outlineColor,
    outlineWidth: outlineWidth,
    shadowOn: shadowOn,
    shadowDx: shadowDx,
    shadowDy: shadowDy,
    shadowBlur: shadowBlur,
    shadowColor: shadowColor,
    stickerIcon: stickerIcon,
    stickerColor: stickerColor,
  );

  // ── Sérialisation ─────────────────────────────────────────
  // includeBytes = true  → format RÉSEAU (Supabase) : base64 si pas de
  //                        chemin Storage (même logique qu'ExtraImage)
  // includeBytes = false → format LOCAL (métadonnées) : les octets vivent
  //                        dans des fichiers, on ne garde qu'un drapeau

  Map<String, dynamic> toJson({bool includeBytes = true}) => {
    'id': id,
    'type': type.index,
    'role': role.index,
    'x': x,
    'y': y,
    'scale': scale,
    'rotation': rotation,
    'flipH': flipH,
    'flipV': flipV,
    'opacity': opacity,
    'visible': visible,
    'storagePath': storagePath,
    if (includeBytes)
      'bytes':
          (storagePath == null && bytes != null) ? base64Encode(bytes!) : null,
    if (!includeBytes) 'hasBytes': bytes != null,
    'text': text,
    'fontSize': fontSize,
    'color': color,
    'fontFamily': fontFamily,
    'bold': bold,
    'italic': italic,
    'outlineColor': outlineColor,
    'outlineWidth': outlineWidth,
    'shadowOn': shadowOn,
    'shadowDx': shadowDx,
    'shadowDy': shadowDy,
    'shadowBlur': shadowBlur,
    'shadowColor': shadowColor,
    'stickerIcon': stickerIcon,
    'stickerColor': stickerColor,
  };

  factory CardLayer.fromJson(Map<String, dynamic> j) => CardLayer(
    id: j['id'] as String,
    type: LayerType.values[j['type'] as int],
    role: LayerRole.values[(j['role'] as int?) ?? 0],
    x: (j['x'] as num?)?.toDouble() ?? 0,
    y: (j['y'] as num?)?.toDouble() ?? 0,
    scale: (j['scale'] as num?)?.toDouble() ?? 1.0,
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
    flipH: (j['flipH'] as bool?) ?? false,
    flipV: (j['flipV'] as bool?) ?? false,
    opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
    visible: (j['visible'] as bool?) ?? true,
    bytes: j['bytes'] != null ? base64Decode(j['bytes'] as String) : null,
    storagePath: j['storagePath'] as String?,
    text: (j['text'] as String?) ?? '',
    fontSize: (j['fontSize'] as num?)?.toDouble() ?? 16,
    color: (j['color'] as int?) ?? 0xFFFFFFFF,
    fontFamily: j['fontFamily'] as String?,
    bold: (j['bold'] as bool?) ?? false,
    italic: (j['italic'] as bool?) ?? false,
    outlineColor: j['outlineColor'] as int?,
    outlineWidth: (j['outlineWidth'] as num?)?.toDouble() ?? 2,
    shadowOn: (j['shadowOn'] as bool?) ?? false,
    shadowDx: (j['shadowDx'] as num?)?.toDouble() ?? 2,
    shadowDy: (j['shadowDy'] as num?)?.toDouble() ?? 2,
    shadowBlur: (j['shadowBlur'] as num?)?.toDouble() ?? 4,
    shadowColor: (j['shadowColor'] as int?) ?? 0xFF000000,
    stickerIcon: j['stickerIcon'] as int?,
    stickerColor: (j['stickerColor'] as int?) ?? 0xFFFFD700,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   MIGRATION : anciens champs → liste de couches
//   Ordre d'empilement reproduit à l'identique de l'ancien rendu :
//   image principale → images extra → zones de texte → nom → rareté
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class LegacyLayerBuilder {
  static List<CardLayer> build({
    required String name,
    Uint8List? imageBytes,
    String? imagePath,
    double imageX = 0,
    double imageY = 0,
    double imageScale = 1.0,
    List<dynamic> extraImages = const [], // List<ExtraImage>
    List<dynamic> textZones = const [], // List<TextZone>
    double nameX = 8,
    double nameY = 200,
    double rarityX = 8,
    double rarityY = 222,
  }) {
    final layers = <CardLayer>[];

    if (imageBytes != null || imagePath != null) {
      layers.add(
        CardLayer(
          id: CardLayer.newId(),
          type: LayerType.image,
          bytes: imageBytes,
          storagePath: imagePath,
          x: imageX,
          y: imageY,
          scale: imageScale,
        ),
      );
    }

    for (final e in extraImages) {
      layers.add(
        CardLayer(
          id: CardLayer.newId(),
          type: LayerType.image,
          bytes: (e.bytes as Uint8List).isEmpty ? null : e.bytes as Uint8List,
          storagePath: e.path as String?,
          x: (e.x as num).toDouble(),
          y: (e.y as num).toDouble(),
          scale: (e.scale as num).toDouble(),
        ),
      );
    }

    for (final z in textZones) {
      layers.add(
        CardLayer(
          id: CardLayer.newId(),
          type: LayerType.text,
          text: z.text as String,
          x: (z.x as num).toDouble(),
          y: (z.y as num).toDouble(),
          fontSize: (z.fontSize as num).toDouble(),
          color: z.color as int,
          fontFamily: z.fontFamily as String?,
        ),
      );
    }

    layers.add(
      CardLayer(
        id: CardLayer.newId(),
        type: LayerType.text,
        role: LayerRole.cardName,
        text: name,
        x: nameX,
        y: nameY,
        fontSize: 18,
        bold: true,
        shadowOn: true,
        shadowDx: 0,
        shadowDy: 0,
        shadowBlur: 4,
      ),
    );

    layers.add(
      CardLayer(
        id: CardLayer.newId(),
        type: LayerType.text,
        role: LayerRole.cardRarity,
        x: rarityX,
        y: rarityY,
        fontSize: 11,
      ),
    );

    return layers;
  }
}
