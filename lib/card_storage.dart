// card_storage.dart — SavedCard + ExtraImage (images multiples)
// ✅ v3 : les images sont stockées en FICHIERS sur le disque
//    - SharedPreferences ne garde plus que de petites métadonnées → rapide
//    - plus d'encodage/décodage base64 géant à chaque chargement / écriture
//    - migration AUTOMATIQUE et NON destructive depuis l'ancien format
// ✅ v4 (migration Supabase Storage, juillet 2026) :
//    - SavedCard/ExtraImage portent des CHEMINS Supabase Storage optionnels
//      (imagePath, backImagePath, ExtraImage.path)
//    - toJson (format réseau) : si un chemin existe → on envoie LE CHEMIN
//      et plus le base64 → card_data devient minuscule
//    - fromJson : accepte les DEUX formats (base64 des anciennes cartes,
//      chemins des nouvelles) → 100 % rétro-compatible, rien à migrer
//    - le téléchargement des images se fait via CardMediaService

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'; // compute()
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_model.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   IMAGE SUPPLÉMENTAIRE (couches multiples)
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

  // Format réseau (Supabase)
  // → chemin Storage si dispo (léger), sinon base64 (rétro-compat)
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
//   SAVED CARD  (les écrans utilisent toujours imageBytes)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SavedCard {
  final String id;
  final String name;
  final Rarity rarity;
  final CardEffect effect;

  // Image principale
  final Uint8List? imageBytes;
  final double imageX, imageY, imageScale;

  // Images supplémentaires (couches)
  final List<ExtraImage> extraImages;

  // Verso
  final Uint8List? backImageBytes;
  final int backColor;

  // ✨ Chemins Supabase Storage (nouveau format). Null = ancienne carte base64.
  final String? imagePath;
  final String? backImagePath;

  // Position nom + rareté (draggables)
  final double nameX, nameY;
  final double rarityX, rarityY;

  final List<TextZone> textZones;

  SavedCard({
    required this.id,
    required this.name,
    this.rarity = Rarity.common,
    this.effect = CardEffect.none,
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
  }) : extraImages = extraImages ?? [],
       textZones = textZones ?? [];

  /// Copie avec remplacement des champs fournis (les autres sont conservés).
  SavedCard copyWith({
    Uint8List? imageBytes,
    Uint8List? backImageBytes,
    String? imagePath,
    String? backImagePath,
    List<ExtraImage>? extraImages,
  }) => SavedCard(
    id: id,
    name: name,
    rarity: rarity,
    effect: effect,
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
//   Doit rester une fonction de premier niveau (exigence de compute()).
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
  static const _oldKey =
      'saved_cards'; // ancien format (base64) — gardé en secours
  static const _metaKey =
      'saved_cards_v2'; // nouveau format : métadonnées seules

  // Cache mémoire (décodage une seule fois par session)
  static List<SavedCard>? _cache;

  // Chemin du dossier des images (mis en cache)
  static String? _imagesDirPath;

  // Migration « single-flight » : ne s'exécute qu'une fois même si
  // plusieurs écrans appellent loadCards() en même temps.
  static Future<void>? _migrationFuture;

  // Verrou d'écriture — empêche deux écritures simultanées de s'écraser
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

  // ── Chemins des fichiers images ───────────────────────────────────────────

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

  // ── Format RÉSEAU (Supabase) ─────────────────────────────────────────────
  //    Utilisé par CollectionService pour card_data.
  //    ✨ v4 : chemin Storage si dispo (léger), base64 sinon (rétro-compat).

  static Map<String, dynamic> toJson(SavedCard c) => {
    'id': c.id,
    'name': c.name,
    'rarity': c.rarity.index,
    'effect': c.effect.index,
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

  static SavedCard fromJson(Map<String, dynamic> j) => SavedCard(
    id: j['id'] as String,
    name: j['name'] as String,
    rarity: Rarity.values[j['rarity'] as int],
    effect: CardEffect.values[j['effect'] as int],
    imageBytes:
        j['imageBytes'] != null
            ? base64Decode(j['imageBytes'] as String)
            : null,
    imagePath: j['imagePath'] as String?,
    imageX: (j['imageX'] as num?)?.toDouble() ?? 0,
    imageY: (j['imageY'] as num?)?.toDouble() ?? 0,
    imageScale: (j['imageScale'] as num?)?.toDouble() ?? 1.0,
    extraImages:
        ((j['extraImages'] as List?) ?? [])
            .map((e) => ExtraImage.fromJson(e as Map<String, dynamic>))
            .toList(),
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
    textZones:
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
            .toList(),
  );

  // ── Format LOCAL : métadonnées seules (pas d'octets) ────────────────────────

  static Map<String, dynamic> _metaToJson(SavedCard c) => {
    'id': c.id,
    'name': c.name,
    'rarity': c.rarity.index,
    'effect': c.effect.index,
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

  // Reconstruit un SavedCard depuis ses métadonnées + lecture des fichiers images.
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

    return SavedCard(
      id: id,
      name: j['name'] as String,
      rarity: Rarity.values[j['rarity'] as int],
      effect: CardEffect.values[j['effect'] as int],
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
      textZones:
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
              .toList(),
    );
  }

  // Écrit les fichiers images d'une carte (et nettoie les anciens devenus inutiles).
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
    // Supprime d'éventuels extras restants d'une version précédente de la carte
    int i = c.extraImages.length;
    while (await File(_extraPath(dir, c.id, i)).exists()) {
      await File(_extraPath(dir, c.id, i)).delete();
      i++;
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
  }

  // ── Migration automatique, non destructive ──────────────────────────────────

  static Future<void> _ensureMigrated(SharedPreferences prefs) {
    return _migrationFuture ??= _migrate(prefs);
  }

  static Future<void> _migrate(SharedPreferences prefs) async {
    // Déjà migré ?
    if (prefs.getString(_metaKey) != null) return;

    final old = prefs.getString(_oldKey);
    if (old == null || old.isEmpty) {
      await prefs.setString(_metaKey, '[]'); // rien à migrer, on initialise
      return;
    }

    // Décode l'ancien format base64 en arrière-plan (une seule fois)
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

  // ── Lecture ───────────────────────────────────────────────────────────────

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
      // Lecture des fichiers en parallèle (I/O rapide, ne gèle pas l'écran)
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

  // ── Écriture ──────────────────────────────────────────────────────────────

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
      cards.removeWhere((c) => c.id == card.id); // évite les doublons
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

  // Ajout groupé : une seule écriture des métadonnées
  static Future<void> addCards(List<SavedCard> newCards) async {
    if (newCards.isEmpty) return;
    await _withLock(() async {
      final cards = await loadCards();
      final dir = await _imagesDir();
      for (final card in newCards) {
        cards.removeWhere((c) => c.id == card.id); // évite les doublons
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
