import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Cadre de carte TCG : photo utilisateur + overlay SVG + textes.
///
/// Version STATIQUE (aucune animation). Les bords brillants de l'epique et
/// de la legendaire sont deja dessines dans les fichiers SVG.
///
/// Fichiers attendus dans assets/overlays/ :
///   overlay-commune.svg, overlay-peu-commune.svg, overlay-rare.svg,
///   overlay-epique.svg, overlay-legendaire.svg
class CardFrame extends StatelessWidget {
  /// 'commune' | 'peu-commune' | 'rare' | 'epique' | 'legendaire'
  final String rarity;

  /// Photo de l'utilisateur (AssetImage, NetworkImage, FileImage...).
  final ImageProvider? photo;

  /// Nom affiche dans le bandeau.
  final String name;

  /// Texte de l'encadre de description.
  final String description;

  const CardFrame({
    super.key,
    required this.rarity,
    this.photo,
    this.name = '',
    this.description = '',
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 750 / 1050, // ratio identique au repere des SVG
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          // Conversion du repere 750x1050 vers les pixels reels
          double fx(double px) => px / 750 * w;
          double fy(double px) => px / 1050 * h;

          return Stack(
            children: [
              // 1) Photo utilisateur, clippee a la fenetre d'illustration
              //    (zone 60,156,630,566 ; coins arrondis rx14)
              Positioned(
                left: fx(60),
                top: fy(156),
                width: fx(630),
                height: fy(566),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(fx(14)),
                  child:
                      photo != null
                          ? Image(image: photo!, fit: BoxFit.cover)
                          : Container(color: const Color(0xFF1C2433)),
                ),
              ),

              // 2) Overlay SVG (cadre). La fenetre d'illustration y est transparente.
              Positioned.fill(
                child: SvgPicture.asset(
                  'assets/overlays/overlay-$rarity.svg',
                  fit: BoxFit.fill,
                ),
              ),

              // 3) Nom de la carte (zone texte 92,58,566,60)
              Positioned(
                left: fx(92),
                top: fy(58),
                width: fx(566),
                height: fy(60),
                child: Center(
                  child: Text(
                    name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontSize: fy(38),
                      letterSpacing: fx(1.5),
                      fontWeight: FontWeight.w600,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 4) Description (zone texte 84,828,582,164)
              Positioned(
                left: fx(84),
                top: fy(828),
                width: fx(582),
                height: fy(164),
                child: Text(
                  description,
                  style: TextStyle(
                    color: const Color(0xFFDFE5EC),
                    fontFamily: 'serif',
                    fontSize: fy(26),
                    height: 1.3,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
