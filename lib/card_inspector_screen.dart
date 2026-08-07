// card_inspector_screen.dart
// Inspection 3D d'une carte (glisser pour incliner, bouton pour retourner).
//
// ✨ NOUVEAU : en-tête optionnel « rareté + nom » affiché HORS du cadre,
//    dans le même esprit que la révélation de pack. Il ne s'affiche que si
//    l'appelant fournit cardName / rarityLabel — les autres écrans
//    (collection, créateur de cartes) sont donc totalement inchangés.
//
// ✨ La carte est automatiquement réduite si la hauteur disponible est
//    insuffisante : aucun risque d'overflow sur les petits écrans.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ✨ Contrat OPTIONNEL qu'un widget de face de carte peut implémenter pour
/// que l'inspecteur affiche tout seul la rareté et le nom HORS du cadre.
///
/// Intérêt : les écrans appelants (collection, ouverture de pack…) n'ont
/// AUCUNE modification à subir — il suffit que le widget de carte qu'ils
/// passent en `frontCard` implémente cette interface.
///
/// Un widget qui ne l'implémente pas (ex. l'aperçu du créateur de cartes,
/// avec ses calques éditables) est affiché exactement comme avant.
abstract class InspectableCardFace {
  /// Nom affiché sous la pastille de rareté.
  String? get inspectorName;

  /// Libellé de rareté (ex. « Rare »).
  String? get inspectorRarityLabel;

  /// Couleur de la pastille et du halo du nom.
  Color? get inspectorRarityColor;
}

class CardInspectorScreen extends StatefulWidget {
  final Widget frontCard;
  final Widget backCard;

  // ── En-tête « rareté + nom » (hors du cadre) ───────────────────────────
  // Ces trois champs sont des SURCHARGES facultatives : s'ils valent null,
  // l'inspecteur interroge automatiquement `frontCard` lorsque celui-ci
  // implémente InspectableCardFace. Aucun en-tête n'est affiché si ni l'un
  // ni l'autre ne fournit d'information.

  /// Nom affiché au-dessus de la carte.
  final String? cardName;

  /// Libellé de rareté (ex. « Rare »).
  final String? rarityLabel;

  /// Couleur de la rareté (pastille + halo du nom).
  final Color? rarityColor;

  /// Dimensions logiques de la carte fournie — servent au calcul de mise
  /// à l'échelle. Valeurs par défaut = celles utilisées partout dans l'app.
  final double cardWidth;
  final double cardHeight;

  const CardInspectorScreen({
    super.key,
    required this.frontCard,
    required this.backCard,
    this.cardName,
    this.rarityLabel,
    this.rarityColor,
    this.cardWidth = 300,
    this.cardHeight = 420,
  });

  @override
  State<CardInspectorScreen> createState() => _CardInspectorScreenState();
}

class _CardInspectorScreenState extends State<CardInspectorScreen>
    with SingleTickerProviderStateMixin {
  double _rotX = 0;
  double _rotY = 0;
  bool _isFlipped = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: pi).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  void _flip() {
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _resetRotation() {
    setState(() {
      _rotX = 0;
      _rotY = 0;
    });
  }

  /// La face avant sait-elle se décrire elle-même ?
  ///
  /// Le transtypage explicite est nécessaire : `InspectableCardFace` n'est
  /// pas un sous-type de `Widget`, donc Dart ne promeut PAS `f` dans la
  /// branche `is` — son type reste `Widget`. Le cast est sûr, il est
  /// protégé par le test qui le précède.
  InspectableCardFace? get _face {
    final f = widget.frontCard;
    return f is InspectableCardFace ? f as InspectableCardFace : null;
  }

  // Les paramètres explicites priment ; sinon on interroge la face avant.
  String? get _name => widget.cardName ?? _face?.inspectorName;
  String? get _rarityLabel => widget.rarityLabel ?? _face?.inspectorRarityLabel;
  Color get _rarityColor =>
      widget.rarityColor ??
      _face?.inspectorRarityColor ??
      const Color(0xFF9AA0B0);

  bool get _hasHeader =>
      (_name != null && _name!.isNotEmpty) ||
      (_rarityLabel != null && _rarityLabel!.isNotEmpty);

  // ── En-tête : pastille de rareté puis nom, hors du cadre ────────────────
  Widget _buildHeader() {
    final rc = _rarityColor;
    final label = _rarityLabel;
    final name = _name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null && label.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              decoration: BoxDecoration(
                color: rc.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: rc, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: rc.withValues(alpha: 0.45),
                    blurRadius: 20,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.silkscreen(
                  fontSize: 11,
                  color: rc,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (label != null && label.isNotEmpty && name != null)
            const SizedBox(height: 10),
          if (name != null && name.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                name,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: GoogleFonts.lilitaOne(
                  fontSize: 28,
                  color: const Color(0xFFF6EEDD),
                  letterSpacing: 0.8,
                  shadows: [
                    Shadow(blurRadius: 18, color: rc.withValues(alpha: 0.55)),
                    const Shadow(
                      offset: Offset(0, 2),
                      color: Color(0x8C000000),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A1A),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Inspection de la carte',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: const Color(0xFF16213E),
            child: const Text(
              '👆 Glissez pour faire pivoter',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),

          // ✨ Rareté + nom, hors du cadre (uniquement si fournis)
          if (_hasHeader) _buildHeader(),

          Expanded(
            child: GestureDetector(
              onPanUpdate: (d) {
                setState(() {
                  _rotY += d.delta.dx * 0.012;
                  _rotX -= d.delta.dy * 0.012;
                  _rotX = _rotX.clamp(-0.7, 0.7);
                  _rotY = _rotY.clamp(-0.9, 0.9);
                });
              },
              onPanEnd: (_) {
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    setState(() {
                      _rotX *= 0.4;
                      _rotY *= 0.4;
                    });
                  }
                });
              },
              child: Container(
                color: const Color(0xFF0A0A1A),
                child: LayoutBuilder(
                  builder: (context, cons) {
                    // Marge de respiration autour de la carte (glow compris).
                    // La carte n'est JAMAIS agrandie, seulement réduite si la
                    // place manque → aucun overflow sur petit écran.
                    final rawScale = min(
                      1.0,
                      min(
                        (cons.maxHeight - 32) / widget.cardHeight,
                        (cons.maxWidth - 32) / widget.cardWidth,
                      ),
                    );
                    final fitScale = rawScale.clamp(0.3, 1.0);

                    return Center(
                      child: Transform.scale(
                        scale: fitScale,
                        child: AnimatedBuilder(
                          animation: _flipAnimation,
                          builder: (context, _) {
                            final flipAngle = _flipAnimation.value;
                            final showFront = flipAngle < pi / 2;
                            return Transform(
                              alignment: Alignment.center,
                              transform:
                                  Matrix4.identity()
                                    ..setEntry(3, 2, 0.0008)
                                    ..rotateY(flipAngle + _rotY)
                                    ..rotateX(_rotX),
                              child:
                                  showFront
                                      ? widget.frontCard
                                      : Transform(
                                        alignment: Alignment.center,
                                        transform:
                                            Matrix4.identity()..rotateY(pi),
                                        child: widget.backCard,
                                      ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF16213E),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetRotation,
                    icon: const Icon(
                      Icons.center_focus_strong,
                      color: Colors.white54,
                    ),
                    // Police de l'app (lilitaOne), comme le reste des boutons.
                    label: Text(
                      'Centrer',
                      style: GoogleFonts.lilitaOne(
                        color: Colors.white54,
                        fontSize: 15.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  // ElevatedButton simple (et non .icon) : l'ancienne icône
                  // Icons.flip s'affichait comme un carré blanc barré, en
                  // doublon avec l'emoji 🔄 déjà présent dans le libellé.
                  child: ElevatedButton(
                    onPressed: _flip,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4AB6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _isFlipped ? '👁 Voir le recto' : '🔄 Retourner la carte',
                      style: GoogleFonts.lilitaOne(
                        color: Colors.white,
                        fontSize: 15.5,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
