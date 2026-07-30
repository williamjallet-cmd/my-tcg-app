// error_reporter.dart
// ════════════════════════════════════════════════════════════════════════════
//  ERREURS VISIBLES — canal unique pour signaler un échec à l'utilisateur.
//
//  POURQUOI CE FICHIER :
//  les services (CollectionService, ProfileService, PackSystem…) n'ont pas de
//  BuildContext. Leur seule option était `debugPrint()`, invisible sur
//  téléphone. Conséquence vécue : des cartes non enregistrées, une règle RLS
//  bloquante et un profil non sauvegardé sont passés totalement inaperçus
//  pendant des jours.
//
//  RÈGLE : une opération qui ÉCHOUE ne doit jamais se taire.
//    • ErrorLevel.degraded  → l'app continue avec une valeur de repli
//    • ErrorLevel.dataLoss  → une donnée n'a PAS été enregistrée (grave)
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'arcade_theme.dart';

/// Branché sur `MaterialApp(scaffoldMessengerKey:)` dans main.dart.
/// C'est ce qui permet d'afficher un message depuis n'importe où.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

enum ErrorLevel {
  /// Échec non bloquant : l'app poursuit avec une valeur par défaut
  /// (liste vide, compteur à 0…). L'utilisateur doit savoir que
  /// l'affichage est incomplet, sans être alarmé.
  degraded,

  /// Une donnée n'a PAS été écrite. L'utilisateur croirait avoir réussi.
  dataLoss,
}

String? _lastMessage;
DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);

/// Signale un échec : trace console + bandeau à l'écran.
///
/// [operation] décrit l'action en langage clair, pas le nom de la fonction
/// (« Enregistrement des cartes » plutôt que « saveUserCards »).
void reportError(
  String operation,
  Object error, {
  ErrorLevel level = ErrorLevel.degraded,
}) {
  // Toujours dans la console, même si l'UI n'est pas prête.
  debugPrint('⚠️ $operation : $error');

  final messenger = appMessengerKey.currentState;
  if (messenger == null) return; // app pas encore construite

  final detail = error.toString().replaceFirst('Exception: ', '');
  final isCritical = level == ErrorLevel.dataLoss;
  final message =
      isCritical
          ? '$operation a échoué.\n$detail'
          : '$operation : affichage incomplet.\n$detail';

  // Anti-spam : plusieurs collections qui échouent d'affilée, ou une boucle
  // de rafraîchissement, ne doivent pas noyer l'écran sous les bandeaux.
  final now = DateTime.now();
  if (message == _lastMessage &&
      now.difference(_lastShownAt) < const Duration(seconds: 5)) {
    return;
  }
  _lastMessage = message;
  _lastShownAt = now;

  messenger.showSnackBar(
    SnackBar(
      content: Text(message, style: Arcade.body(color: Colors.white)),
      backgroundColor: isCritical ? Arcade.coral : Arcade.surface2,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isCritical ? 8 : 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
