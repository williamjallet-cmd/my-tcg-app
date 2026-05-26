// card_storage.dart — SavedCard + ExtraImage (images multiples)

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_model.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   IMAGE SUPPLÉMENTAIRE (couches multiples)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ExtraImage {
  final Uint8List bytes;
  final double x, y, scale;

  ExtraImage({required this.bytes, this.x = 0, this.y = 0, this.scale = 1.0});

  Map<String, dynamic> toJson() => {
    'bytes': base64Encode(bytes),
    'x': x,
    'y': y,
    'scale': scale,
  };

  factory ExtraImage.fromJson(Map<String, dynamic> j) => ExtraImage(
    bytes: base64Decode(j['bytes'] as String),
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    scale: (j['scale'] as num).toDouble(),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   SAVED CARD
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
    this.nameX = 8,
    this.nameY = 200,
    this.rarityX = 8,
    this.rarityY = 222,
    List<TextZone>? textZones,
  }) : extraImages = extraImages ?? [],
       textZones = textZones ?? [];
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   STORAGE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class CardStorage {
  static const _key = 'saved_cards';

  // FIX : verrou d'écriture — empêche deux opérations simultanées
  // d'écraser les changements l'une de l'autre (race condition)
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

  // ── Sérialisation ─────────────────────────────────────────────────────────

  static Map<String, dynamic> toJson(SavedCard c) => {
    'id': c.id,
    'name': c.name,
    'rarity': c.rarity.index,
    'effect': c.effect.index,
    'imageBytes': c.imageBytes != null ? base64Encode(c.imageBytes!) : null,
    'imageX': c.imageX,
    'imageY': c.imageY,
    'imageScale': c.imageScale,
    'extraImages': c.extraImages.map((e) => e.toJson()).toList(),
    'backImageBytes':
        c.backImageBytes != null ? base64Encode(c.backImageBytes!) : null,
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

  // ── Lecture ───────────────────────────────────────────────────────────────

  static Future<List<SavedCard>> loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_key);
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      // FIX : si une carte individuelle est corrompue, on la saute
      // plutôt que de tout perdre
      final cards = <SavedCard>[];
      for (final e in list) {
        try {
          cards.add(fromJson(e as Map<String, dynamic>));
        } catch (_) {
          // carte corrompue ignorée, les autres sont préservées
        }
      }
      return cards;
    } catch (_) {
      return [];
    }
  }

  // ── Écriture ──────────────────────────────────────────────────────────────

  static Future<void> saveCards(List<SavedCard> cards) async {
    await _withLock(() async {
      // FIX : écriture atomique avec gestion d'erreur explicite
      try {
        final prefs = await SharedPreferences.getInstance();
        final encoded = jsonEncode(cards.map(toJson).toList());
        await prefs.setString(_key, encoded);
      } catch (e) {
        throw Exception('Impossible de sauvegarder les cartes : $e');
      }
    });
  }

  static Future<void> addCard(SavedCard card) async {
    // FIX : opération protégée par le verrou → plus de race condition
    await _withLock(() async {
      final cards = await loadCards();
      cards.removeWhere((c) => c.id == card.id); // évite les doublons
      cards.add(card);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(cards.map(toJson).toList()));
    });
  }

  static Future<void> deleteCard(String id) async {
    // FIX : opération protégée par le verrou → plus de race condition
    await _withLock(() async {
      final cards = await loadCards();
      cards.removeWhere((c) => c.id == id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(cards.map(toJson).toList()));
    });
  }
}
