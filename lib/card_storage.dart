// card_storage.dart — SavedCard + ExtraImage (images multiples)
// ✅ v3 : images en FICHIERS sur le disque (métadonnées seules en prefs)
// ✅ v4 : chemins Supabase Storage optionnels (rétro-compat base64)
// ✅ v5 (bloc 1 — couches unifiées, juillet 2026) :
//    - SavedCard porte une liste `layers` (CardLayer) : image / texte /
//      sticker, avec rotation, flip, opacité, ordre d'empilement libre
//    - les ANCIENS champs (imageBytes, imageX/Y/Scale, extraImages,
//      textZones, nameX/Y, rarityX/Y) sont CONSERVÉS et mirrorés depuis
//      les couches → les autres écrans continuent de fonctionner tels quels
//    - fromJson / _cardFromMeta : si `layers` absent (ancienne carte),
//      les couches sont reconstruites via LegacyLayerBuilder
//      → 100 % rétro-compatible, rien à migrer manuellement
//    - les octets des couches image sont stockés en fichiers nommés par
//      l'ID DE LA COUCHE (stable même si on réordonne les couches)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // compute()
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_layer.dart';
import 'card_model.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   IMAGE SUPPLÉMENTAIRE (ancien format — conservé pour rétro-compat)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ExtraImage {
  final Uint8List bytes;
  final double x, y, scale;

  /// Chemin Supabase Storage (nouveau format). Null pour les anciennes cartes.
  final String? path;

  ExtraImage({
    required this.bytes,
    this.x = 0,
    this.y = 0,
    this.scale = 1.0,
    this.path,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'bytes': (path == null && bytes.isNotEmpty) ? base64Encode(bytes) : null,
    'x': x,
    'y': y,
    'scale': scale,
  };

  factory ExtraImage.fromJson(Map<String, dynamic> j) => ExtraImage(
    bytes:
        j['bytes'] != null ? base64Decode(j['bytes'] as String) : Uint8List(0),
    path: j['path'] as String?,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    scale: (j['scale'] as num).toDouble(),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   SAVED CARD
//   `layers` est la SOURCE DE VÉRITÉ pour le rendu du recto.
//   Les champs legacy sont mirrorés pour les écrans pas encore migrés.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SavedCard {
  final String id;
  final String name;
  final Rarity rarity;
  final CardEffect effect;

  // ✨ v5 : couches unifiées (recto)
  final List<CardLayer> layers;

  // Legacy — mirrorés depuis layers (voir mirrorLegacyFields)
  final Uint8List? imageBytes;
  final double imageX, imageY, imageScale;
  final List<ExtraImage> extraImages;
  final double nameX, nameY;
  final double rarityX, rarityY;
  final List<TextZone> textZones;

  // Verso
  final Uint8List? backImageBytes;
  final int backColor;

  // Chemins Supabase Storage
  final String? imagePath;
  final String? backImagePath;

  SavedCard({
    required this.id,
    required this.name,
    this.rarity = Rarity.common,
    this.effect = CardEffect.none,
    List<CardLayer>? layers,
    this.imageBytes,
    this.imageX = 0,
    this.imageY = 0,
    this.imageScale = 1.0,
    List<ExtraImage>? extraImages,
    this.backImageBytes,
    this.backColor = 0xFF16213E,
    this.imagePath,
    this.backImagePath,
    this.nameX = 8,
    this.nameY = 200,
    this.rarityX = 8,
    this.rarityY = 222,
    List<TextZone>? textZones,
  }) : layers = layers ?? [],
       extraImages = extraImages ?? [],
       textZones = textZones ?? [];

  /// Couches effectives : celles enregistrées, sinon reconstruites
  /// depuis les champs legacy (anciennes cartes jamais rouvertes).
  List<CardLayer> get effectiveLayers =>
      layers.isNotEmpty
          ? layers
          : LegacyLayerBuilder.build(
            name: name,
            imageBytes: imageBytes,
            imagePath: imagePath,
            imageX: imageX,
            imageY: imageY,
            imageScale: imageScale,
            extraImages: extraImages,
            textZones: textZones,
            nameX: nameX,
            nameY: nameY,
            rarityX: rarityX,
            rarityY: rarityY,
          );

  /// Fabrique une SavedCard depuis des couches, en remplissant
  /// automatiquement les champs legacy pour les écrans non migrés.
  factory SavedCard.fromLayers({
    required String id,
    required String name,
    required List<CardLayer> layers,
    Rarity rarity = Rarity.common,
    CardEffect effect = CardEffect.none,
    Uint8List? backImageBytes,
    int backColor = 0xFF16213E,
    String? backImagePath,
  }) {
    Uint8List? mainBytes;
    String? mainPath;
    double mX = 0, mY = 0, mScale = 1.0;
    final extras = <ExtraImage>[];
    final zones = <TextZone>[];
    double nX = 8, nY = 200, rX = 8, rY = 222;
    bool mainFound = false;

    for (final l in layers) {
      switch (l.type) {
        case LayerType.image:
          if (!mainFound) {
            mainFound = true;
            mainBytes = l.bytes;
            mainPath = l.storagePath;
            mX = l.x;
            mY = l.y;
            mScale = l.scale;
          } else {
            extras.add(
              ExtraImage(
                bytes: l.bytes ?? Uint8List(0),
                path: l.storagePath,
                x: l.x,
                y: l.y,
                scale: l.scale,
              ),
            );
          }
        case LayerType.text:
          if (l.role == LayerRole.cardName) {
            nX = l.x;
            nY = l.y;
          } else if (l.role == LayerRole.cardRarity) {
            rX = l.x;
            rY = l.y;
          } else {
            zones.add(
              TextZone(
                text: l.text,
                x: l.x,
                y: l.y,
                fontSize: l.fontSize,
                color: l.color,
                fontFamily: l.fontFamily,
              ),
            );
          }
        case LayerType.sticker:
          break; // pas d'équivalent legacy
      }
    }

    return SavedCard(
      id: id,
      name: name,
      rarity: rarity,
      effect: effect,
      layers: layers,
      imageBytes: mainBytes,
      imagePath: mainPath,
      imageX: mX,
      imageY: mY,
      imageScale: mScale,
      extraImages: extras,
      backImageBytes: backImageBytes,
      backColor: backColor,
      backImagePath: backImagePath,
      nameX: nX,
      nameY: nY,
      rarityX: rX,
      rarityY: rY,
      textZones: zones,
    );
  }

  /// Copie avec remplacement des champs fournis (les autres sont conservés).
  SavedCard copyWith({
    Uint8List? imageBytes,
    Uint8List? backImageBytes,
    String? imagePath,
    String? backImagePath,
    List<ExtraImage>? extraImages,
    List<CardLayer>? layers,
  }) => SavedCard(
    id: id,
    name: name,
    rarity: rarity,
    effect: effect,
    layers: layers ?? this.layers,
    imageBytes: imageBytes ?? this.imageBytes,
    imageX: imageX,
    imageY: imageY,
    imageScale: imageScale,
    extraImages: extraImages ?? this.extraImages,
    backImageBytes: backImageBytes ?? this.backImageBytes,
    backColor: backColor,
    imagePath: imagePath ?? this.imagePath,
    backImagePath: backImagePath ?? this.backImagePath,
    nameX: nameX,
    nameY: nameY,
    rarityX: rarityX,
    rarityY: rarityY,
    textZones: textZones,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   DÉCODAGE EN ARRIÈRE-PLAN (uniquement pour la migration unique)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

List<SavedCard> _decodeOldCardsInBackground(String data) {
  final list = jsonDecode(data) as List;
  final cards = <SavedCard>[];
  for (final e in list) {
    try {
      cards.add(CardStorage.fromJson(e as Map<String, dynamic>));
    } catch (_) {
      // carte corrompue ignorée
    }
  }
  return cards;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   STORAGE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class CardStorage {
  static const _oldKey = 'saved_cards'; // ancien format base64 — secours
  static const _metaKey = 'saved_cards_v2'; // métadonnées seules

  static List<SavedCard>? _cache;
  static String? _imagesDirPath;
  static Future<void>? _migrationFuture;
  static Future<void>? _pendingWrite;

  static Future<void> _withLock(Future<void> Function() fn) async {
    final prev = _pendingWrite;
    final completer = Completer<void>();
    _pendingWrite = completer.future;
    if (prev != null) await prev;
    try {
      await fn();
    } finally {
      completer.complete();
    }
  }

  static void clearCache() => _cache = null;

  // ── Chemins des fichiers images ──────────────────────────

  static Future<String> _imagesDir() async {
    if (_imagesDirPath != null) return _imagesDirPath!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/card_images');
    if (!await dir.exists()) await dir.create(recursive: true);
    _imagesDirPath = dir.path;
    return dir.path;
  }

  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static String _mainPath(String dir, String id) => '$dir/${_safe(id)}__main';
  static String _backPath(String dir, String id) => '$dir/${_safe(id)}__back';
  static String _extraPath(String dir, String id, int i) =>
      '$dir/${_safe(id)}__extra_$i';

  // ✨ v5 : fichier nommé par l'ID DE COUCHE → stable au réordonnancement
  static String _layerPath(String dir, String cardId, String layerId) =>
      '$dir/${_safe(cardId)}__layer_${_safe(layerId)}';

  // ── Format RÉSEAU (Supabase) ─────────────────────────────
  //    v5 : `layers` ajouté ; champs legacy toujours émis (mirroir)
  //    → les anciennes versions de l'app lisent encore les cartes.

  static Map<String, dynamic> toJson(SavedCard c) => {
    'id': c.id,
    'name': c.name,
    'rarity': c.rarity.index,
    'effect': c.effect.index,
    'layers': c.layers.map((l) => l.toJson(includeBytes: true)).toList(),
    'imagePath': c.imagePath,
    'imageBytes':
        (c.imagePath == null && c.imageBytes != null)
            ? base64Encode(c.imageBytes!)
            : null,
    'imageX': c.imageX,
    'imageY': c.imageY,
    'imageScale': c.imageScale,
    'extraImages': c.extraImages.map((e) => e.toJson()).toList(),
    'backImagePath': c.backImagePath,
    'backImageBytes':
        (c.backImagePath == null && c.backImageBytes != null)
            ? base64Encode(c.backImageBytes!)
            : null,
    'backColor': c.backColor,
    'nameX': c.nameX,
    'nameY': c.nameY,
    'rarityX': c.rarityX,
    'rarityY': c.rarityY,
    'textZones':
        c.textZones
            .map(
              (z) => {
                'text': z.text,
                'x': z.x,
                'y': z.y,
                'fontSize': z.fontSize,
                'color': z.color,
                'fontFamily': z.fontFamily,
              },
            )
            .toList(),
  };

  static SavedCard fromJson(Map<String, dynamic> j) {
    final imageBytes =
        j['imageBytes'] != null
            ? base64Decode(j['imageBytes'] as String)
            : null;
    final extras =
        ((j['extraImages'] as List?) ?? [])
            .map((e) => ExtraImage.fromJson(e as Map<String, dynamic>))
            .toList();
    final zones =
        ((j['textZones'] as List?) ?? [])
            .map(
              (z) => TextZone(
                text: z['text'] as String,
                x: (z['x'] as num).toDouble(),
                y: (z['y'] as num).toDouble(),
                fontSize: (z['fontSize'] as num).toDouble(),
                color: z['color'] as int,
                fontFamily: z['fontFamily'] as String?,
              ),
            )
            .toList();

    // v5 si présent, sinon reconstruction depuis le legacy
    final layersJson = j['layers'] as List?;
    final layers =
        layersJson != null && layersJson.isNotEmpty
            ? layersJson
                .map((l) => CardLayer.fromJson(l as Map<String, dynamic>))
                .toList()
            : LegacyLayerBuilder.build(
              name: j['name'] as String,
              imageBytes: imageBytes,
              imagePath: j['imagePath'] as String?,
              imageX: (j['imageX'] as num?)?.toDouble() ?? 0,
              imageY: (j['imageY'] as num?)?.toDouble() ?? 0,
              imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
              extraImages: extras,
              textZones: zones,
              nameX: (j['nameX'] as num?)?.toDouble() ?? 8,
              nameY: (j['nameY'] as num?)?.toDouble() ?? 200,
              rarityX: (j['rarityX'] as num?)?.toDouble() ?? 8,
              rarityY: (j['rarityY'] as num?)?.toDouble() ?? 222,
            );

    return SavedCard(
      id: j['id'] as String,
      name: j['name'] as String,
      rarity: Rarity.values[j['rarity'] as int],
      effect: CardEffect.values[j['effect'] as int],
      layers: layers,
      imageBytes: imageBytes,
      imagePath: j['imagePath'] as String?,
      imageX: (j['imageX'] as num?)?.toDouble() ?? 0,
      imageY: (j['imageY'] as num?)?.toDouble() ?? 0,
      imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
      extraImages: extras,
      backImageBytes:
          j['backImageBytes'] != null
              ? base64Decode(j['backImageBytes'] as String)
              : null,
      backImagePath: j['backImagePath'] as String?,
      backColor: (j['backColor'] as int?) ?? 0xFF16213E,
      nameX: (j['nameX'] as num?)?.toDouble() ?? 8,
      nameY: (j['nameY'] as num?)?.toDouble() ?? 200,
      rarityX: (j['rarityX'] as num?)?.toDouble() ?? 8,
      rarityY: (j['rarityY'] as num?)?.toDouble() ?? 222,
      textZones: zones,
    );
  }

  // ── Format LOCAL : métadonnées seules (pas d'octets) ─────

  static Map<String, dynamic> _metaToJson(SavedCard c) => {
    'id': c.id,
    'name': c.name,
    'rarity': c.rarity.index,
    'effect': c.effect.index,
    'layers': c.layers.map((l) => l.toJson(includeBytes: false)).toList(),
    'imageX': c.imageX,
    'imageY': c.imageY,
    'imageScale': c.imageScale,
    'backColor': c.backColor,
    'nameX': c.nameX,
    'nameY': c.nameY,
    'rarityX': c.rarityX,
    'rarityY': c.rarityY,
    'hasImage': c.imageBytes != null,
    'hasBack': c.backImageBytes != null,
    'imagePath': c.imagePath,
    'backImagePath': c.backImagePath,
    'extraImages':
        c.extraImages
            .map((e) => {'x': e.x, 'y': e.y, 'scale': e.scale, 'path': e.path})
            .toList(),
    'textZones':
        c.textZones
            .map(
              (z) => {
                'text': z.text,
                'x': z.x,
                'y': z.y,
                'fontSize': z.fontSize,
                'color': z.color,
                'fontFamily': z.fontFamily,
              },
            )
            .toList(),
  };

  // Reconstruit un SavedCard depuis ses métadonnées + fichiers images.
  static Future<SavedCard> _cardFromMeta(
    Map<String, dynamic> j,
    String dir,
  ) async {
    final id = j['id'] as String;

    Uint8List? main;
    if ((j['hasImage'] as bool?) ?? false) {
      final f = File(_mainPath(dir, id));
      if (await f.exists()) main = await f.readAsBytes();
    }

    Uint8List? back;
    if ((j['hasBack'] as bool?) ?? false) {
      final f = File(_backPath(dir, id));
      if (await f.exists()) back = await f.readAsBytes();
    }

    final extraMeta = (j['extraImages'] as List?) ?? [];
    final extras = <ExtraImage>[];
    for (int i = 0; i < extraMeta.length; i++) {
      final f = File(_extraPath(dir, id, i));
      if (await f.exists()) {
        final m = extraMeta[i] as Map<String, dynamic>;
        extras.add(
          ExtraImage(
            bytes: await f.readAsBytes(),
            x: (m['x'] as num).toDouble(),
            y: (m['y'] as num).toDouble(),
            scale: (m['scale'] as num).toDouble(),
            path: m['path'] as String?,
          ),
        );
      }
    }

    final zones =
        ((j['textZones'] as List?) ?? [])
            .map(
              (z) => TextZone(
                text: z['text'] as String,
                x: (z['x'] as num).toDouble(),
                y: (z['y'] as num).toDouble(),
                fontSize: (z['fontSize'] as num).toDouble(),
                color: z['color'] as int,
                fontFamily: z['fontFamily'] as String?,
              ),
            )
            .toList();

    // ✨ v5 : couches — octets lus depuis les fichiers par ID de couche
    List<CardLayer> layers = [];
    final layersMeta = (j['layers'] as List?) ?? [];
    for (final lm in layersMeta) {
      final layer = CardLayer.fromJson(lm as Map<String, dynamic>);
      if (layer.type == LayerType.image &&
          ((lm['hasBytes'] as bool?) ?? false)) {
        final f = File(_layerPath(dir, id, layer.id));
        if (await f.exists()) layer.bytes = await f.readAsBytes();
      }
      layers.add(layer);
    }

    // Ancienne carte (pas de couches en meta) → reconstruction
    if (layers.isEmpty) {
      layers = LegacyLayerBuilder.build(
        name: j['name'] as String,
        imageBytes: main,
        imagePath: j['imagePath'] as String?,
        imageX: (j['imageX'] as num?)?.toDouble() ?? 0,
        imageY: (j['imageY'] as num?)?.toDouble() ?? 0,
        imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
        extraImages: extras,
        textZones: zones,
        nameX: (j['nameX'] as num?)?.toDouble() ?? 8,
        nameY: (j['nameY'] as num?)?.toDouble() ?? 200,
        rarityX: (j['rarityX'] as num?)?.toDouble() ?? 8,
        rarityY: (j['rarityY'] as num?)?.toDouble() ?? 222,
      );
    }

    return SavedCard(
      id: id,
      name: j['name'] as String,
      rarity: Rarity.values[j['rarity'] as int],
      effect: CardEffect.values[j['effect'] as int],
      layers: layers,
      imageBytes: main,
      imageX: (j['imageX'] as num?)?.toDouble() ?? 0,
      imageY: (j['imageY'] as num?)?.toDouble() ?? 0,
      imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
      extraImages: extras,
      backImageBytes: back,
      backColor: (j['backColor'] as int?) ?? 0xFF16213E,
      imagePath: j['imagePath'] as String?,
      backImagePath: j['backImagePath'] as String?,
      nameX: (j['nameX'] as num?)?.toDouble() ?? 8,
      nameY: (j['nameY'] as num?)?.toDouble() ?? 200,
      rarityX: (j['rarityX'] as num?)?.toDouble() ?? 8,
      rarityY: (j['rarityY'] as num?)?.toDouble() ?? 222,
      textZones: zones,
    );
  }

  // Écrit les fichiers images d'une carte (et nettoie les anciens).
  static Future<void> _writeImages(SavedCard c, String dir) async {
    final mainF = File(_mainPath(dir, c.id));
    if (c.imageBytes != null) {
      await mainF.writeAsBytes(c.imageBytes!, flush: true);
    } else if (await mainF.exists()) {
      await mainF.delete();
    }

    final backF = File(_backPath(dir, c.id));
    if (c.backImageBytes != null) {
      await backF.writeAsBytes(c.backImageBytes!, flush: true);
    } else if (await backF.exists()) {
      await backF.delete();
    }

    for (int i = 0; i < c.extraImages.length; i++) {
      await File(
        _extraPath(dir, c.id, i),
      ).writeAsBytes(c.extraImages[i].bytes, flush: true);
    }
    int i = c.extraImages.length;
    while (await File(_extraPath(dir, c.id, i)).exists()) {
      await File(_extraPath(dir, c.id, i)).delete();
      i++;
    }

    // ✨ v5 : fichiers des couches image — on réécrit celles présentes,
    // puis on supprime tout fichier __layer_* orphelin de cette carte.
    final keep = <String>{};
    for (final l in c.layers) {
      if (l.type == LayerType.image && l.bytes != null) {
        final path = _layerPath(dir, c.id, l.id);
        keep.add(path);
        await File(path).writeAsBytes(l.bytes!, flush: true);
      }
    }
    final prefix = '${_safe(c.id)}__layer_';
    await for (final entity in Directory(dir).list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith(prefix) &&
          !keep.contains(entity.path)) {
        await entity.delete();
      }
    }
  }

  static Future<void> _deleteImages(String id, String dir) async {
    final mainF = File(_mainPath(dir, id));
    if (await mainF.exists()) await mainF.delete();
    final backF = File(_backPath(dir, id));
    if (await backF.exists()) await backF.delete();
    int i = 0;
    while (await File(_extraPath(dir, id, i)).exists()) {
      await File(_extraPath(dir, id, i)).delete();
      i++;
    }
    // ✨ v5 : fichiers de couches
    final prefix = '${_safe(id)}__layer_';
    await for (final entity in Directory(dir).list()) {
      if (entity is File && entity.uri.pathSegments.last.startsWith(prefix)) {
        await entity.delete();
      }
    }
  }

  // ── Migration automatique, non destructive ───────────────

  static Future<void> _ensureMigrated(SharedPreferences prefs) {
    return _migrationFuture ??= _migrate(prefs);
  }

  static Future<void> _migrate(SharedPreferences prefs) async {
    if (prefs.getString(_metaKey) != null) return;

    final old = prefs.getString(_oldKey);
    if (old == null || old.isEmpty) {
      await prefs.setString(_metaKey, '[]');
      return;
    }

    List<SavedCard> cards;
    try {
      cards = await compute(_decodeOldCardsInBackground, old);
    } catch (_) {
      cards = [];
    }

    final dir = await _imagesDir();
    for (final c in cards) {
      await _writeImages(c, dir);
    }
    await prefs.setString(
      _metaKey,
      jsonEncode(cards.map(_metaToJson).toList()),
    );
    // NB : on NE supprime PAS l'ancienne clé 'saved_cards' → filet de sécurité.
  }

  // ── Lecture ──────────────────────────────────────────────

  static Future<List<SavedCard>> loadCards() async {
    if (_cache != null) return List<SavedCard>.from(_cache!);

    final prefs = await SharedPreferences.getInstance();
    await _ensureMigrated(prefs);
    final dir = await _imagesDir();

    final data = prefs.getString(_metaKey);
    if (data == null || data.isEmpty) {
      _cache = [];
      return [];
    }

    try {
      final list = jsonDecode(data) as List;
      final cards = await Future.wait(
        list.map((e) => _cardFromMeta(e as Map<String, dynamic>, dir)),
      );
      _cache = cards;
    } catch (e) {
      debugPrint('⚠️ CardStorage.loadCards : $e');
      _cache = [];
    }
    return List<SavedCard>.from(_cache!);
  }

  // ── Écriture ─────────────────────────────────────────────

  static Future<void> saveCards(List<SavedCard> cards) async {
    await _withLock(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await _ensureMigrated(prefs);
        final dir = await _imagesDir();
        for (final c in cards) {
          await _writeImages(c, dir);
        }
        await prefs.setString(
          _metaKey,
          jsonEncode(cards.map(_metaToJson).toList()),
        );
        _cache = List<SavedCard>.from(cards);
      } catch (e) {
        throw Exception('Impossible de sauvegarder les cartes : $e');
      }
    });
  }

  static Future<void> addCard(SavedCard card) async {
    await _withLock(() async {
      final cards = await loadCards();
      cards.removeWhere((c) => c.id == card.id);
      cards.add(card);
      final prefs = await SharedPreferences.getInstance();
      final dir = await _imagesDir();
      await _writeImages(card, dir);
      await prefs.setString(
        _metaKey,
        jsonEncode(cards.map(_metaToJson).toList()),
      );
      _cache = List<SavedCard>.from(cards);
    });
  }

  static Future<void> addCards(List<SavedCard> newCards) async {
    if (newCards.isEmpty) return;
    await _withLock(() async {
      final cards = await loadCards();
      final dir = await _imagesDir();
      for (final card in newCards) {
        cards.removeWhere((c) => c.id == card.id);
        cards.add(card);
        await _writeImages(card, dir);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _metaKey,
        jsonEncode(cards.map(_metaToJson).toList()),
      );
      _cache = List<SavedCard>.from(cards);
    });
  }

  static Future<void> deleteCard(String id) async {
    await _withLock(() async {
      final cards = await loadCards();
      cards.removeWhere((c) => c.id == id);
      final prefs = await SharedPreferences.getInstance();
      final dir = await _imagesDir();
      await _deleteImages(id, dir);
      await prefs.setString(
        _metaKey,
        jsonEncode(cards.map(_metaToJson).toList()),
      );
      _cache = List<SavedCard>.from(cards);
    });
  }
}
