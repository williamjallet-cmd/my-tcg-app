// card_media_service.dart — ✨ NOUVEAU (migration Supabase Storage)
// ════════════════════════════════════════════════════════════════════════════
//  Les images de cartes vivent désormais dans Supabase Storage :
//    bucket « collections » → cards/{cardId}/main.jpg, back.jpg, extra_N.jpg
//
//  • uploadCardImages : envoie les images d'une carte, retourne une copie
//    de la carte avec les chemins remplis. En cas d'échec (hors-ligne…),
//    la carte revient inchangée → le base64 prend le relais, rien ne casse.
//  • hydrate / hydrateAll : télécharge les images manquantes des cartes
//    reçues au nouveau format léger (chemins sans octets).
//  • deleteCardImages : nettoyage best-effort à la suppression d'une carte.
//
//  ⚠️ Nécessite les policies Storage du script brokemon_migration_storage.sql
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'card_storage.dart';

class CardMediaService {
  CardMediaService._();
  static final instance = CardMediaService._();

  static final _storage = Supabase.instance.client.storage;
  static const _bucket = 'collections';

  // ── Chemins dans le bucket ──────────────────────────────────────────────
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  static String _mainPath(String cardId) => 'cards/${_safe(cardId)}/main.jpg';
  static String _backPath(String cardId) => 'cards/${_safe(cardId)}/back.jpg';
  static String _extraPath(String cardId, int i) =>
      'cards/${_safe(cardId)}/extra_$i.jpg';

  // ── Primitives ──────────────────────────────────────────────────────────

  Future<String?> _upload(String path, Uint8List bytes) async {
    try {
      await _storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
      return path;
    } catch (e) {
      debugPrint('⚠️ CardMediaService.upload ($path) : $e');
      return null;
    }
  }

  Future<Uint8List?> _download(String path) async {
    try {
      return await _storage.from(_bucket).download(path);
    } catch (e) {
      debugPrint('⚠️ CardMediaService.download ($path) : $e');
      return null;
    }
  }

  // ── API ─────────────────────────────────────────────────────────────────

  /// Envoie les images d'une carte vers Supabase Storage et retourne une
  /// copie de la carte avec les chemins remplis. Les images déjà uploadées
  /// (chemin déjà présent) ne sont pas renvoyées.
  Future<SavedCard> uploadCardImages(SavedCard card) async {
    String? mainPath = card.imagePath;
    String? backPath = card.backImagePath;

    if (card.imageBytes != null && mainPath == null) {
      mainPath = await _upload(_mainPath(card.id), card.imageBytes!);
    }
    if (card.backImageBytes != null && backPath == null) {
      backPath = await _upload(_backPath(card.id), card.backImageBytes!);
    }

    final extras = <ExtraImage>[];
    for (int i = 0; i < card.extraImages.length; i++) {
      final e = card.extraImages[i];
      String? p = e.path;
      if (p == null && e.bytes.isNotEmpty) {
        p = await _upload(_extraPath(card.id, i), e.bytes);
      }
      extras.add(ExtraImage(bytes: e.bytes, x: e.x, y: e.y, scale: e.scale, path: p));
    }

    return card.copyWith(
      imagePath: mainPath,
      backImagePath: backPath,
      extraImages: extras,
    );
  }

  /// Télécharge les images manquantes d'une carte reçue au format léger
  /// (chemins Storage sans octets). Une extra dont le téléchargement échoue
  /// est ignorée plutôt que de risquer un crash d'affichage.
  Future<SavedCard> hydrate(SavedCard card) async {
    Uint8List? main = card.imageBytes;
    if (main == null && card.imagePath != null) {
      main = await _download(card.imagePath!);
    }

    Uint8List? back = card.backImageBytes;
    if (back == null && card.backImagePath != null) {
      back = await _download(card.backImagePath!);
    }

    final extras = <ExtraImage>[];
    for (final e in card.extraImages) {
      if (e.bytes.isNotEmpty) {
        extras.add(e);
        continue;
      }
      if (e.path == null) continue; // ni octets ni chemin : rien à faire
      final b = await _download(e.path!);
      if (b != null) {
        extras.add(ExtraImage(bytes: b, x: e.x, y: e.y, scale: e.scale, path: e.path));
      }
    }

    return card.copyWith(
      imageBytes: main,
      backImageBytes: back,
      extraImages: extras,
    );
  }

  /// Hydrate plusieurs cartes en parallèle.
  Future<List<SavedCard>> hydrateAll(List<SavedCard> cards) {
    if (cards.isEmpty) return Future.value(<SavedCard>[]);
    return Future.wait(cards.map(hydrate));
  }

  /// Suppression best-effort des images d'une carte sur Storage.
  Future<void> deleteCardImages(SavedCard card) async {
    final paths = <String>[
      if (card.imagePath != null) card.imagePath!,
      if (card.backImagePath != null) card.backImagePath!,
      for (final e in card.extraImages)
        if (e.path != null) e.path!,
    ];
    if (paths.isEmpty) return;
    try {
      await _storage.from(_bucket).remove(paths);
    } catch (e) {
      debugPrint('⚠️ CardMediaService.deleteCardImages : $e');
    }
  }
}