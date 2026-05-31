// arcade_theme.dart — Design system « rétro-arcade premium » (Brokemon)
// ─────────────────────────────────────────────────────────────────────
// Transposition fidèle du handoff Claude Design (HTML/React → Flutter).
// Toutes les valeurs (couleurs, typo, rayons, ombres, scanlines, bouton
// biseauté, badge pixel) proviennent des tokens du bundle de référence.
//
// Dépendance : google_fonts. Ajoute dans pubspec.yaml :
//   dependencies:
//     google_fonts: ^6.2.1
//
// Polices (Google Fonts) :
//   • Titres / marquee arcade  → Lilita One
//   • Corps                    → Plus Jakarta Sans
//   • Micro-labels / badges    → Silkscreen (pixel)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Arcade {
  Arcade._();

  // ── Couleurs de base ───────────────────────────────────────────────
  static const Color bg = Color(0xFF14101F); // aubergine nuit
  static const Color bgDeep = Color(0xFF0D0A16); // fond profond
  static const Color surface = Color(0xFF211A33);
  static const Color surface2 = Color(0xFF2B2240);

  // Accent or (signature)
  static const Color gold = Color(0xFFFFC83D);
  static const Color goldDeep = Color(0xFFE0A91E);
  // Pops
  static const Color teal = Color(0xFF21E6C1);
  static const Color coral = Color(0xFFFF5D73);

  // Texte crème (+ atténuations alpha)
  static const Color cream = Color(0xFFF6EEDD);
  static const Color creamDim = Color(0x9EF6EEDD); // .62
  static const Color creamFaint = Color(0x57F6EEDD); // .34
  static const Color line = Color(0x1AF6EEDD); // .10 — surface-line

  // ── Raretés (cadre + drop) ─────────────────────────────────────────
  static const Color rCommun = Color(0xFF9AA0B0); // 50%
  static const Color rPeuCommun = Color(0xFF3FD17A); // 28%
  static const Color rRare = Color(0xFF2FA8FF); // 14%
  static const Color rEpique = Color(0xFFB45CFF); // 6%
  static const Color rLegendaire = Color(0xFFFFC83D); // 2%

  // ── Rayons ─────────────────────────────────────────────────────────
  static const double rButton = 18;
  static const double rCard = 20;
  static const double rPill = 999;

  // ── Ombres ─────────────────────────────────────────────────────────
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x80000000), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static List<BoxShadow> cardGlow(Color glow) => [
    BoxShadow(color: glow, blurRadius: 26, spreadRadius: 2),
    const BoxShadow(
      color: Color(0x8C000000),
      blurRadius: 26,
      offset: Offset(0, 12),
    ),
  ];

  // ── Typographie ────────────────────────────────────────────────────
  // Titres / marquee → Lilita One (chunky, arrondi). Poids unique 400.
  static TextStyle title({
    double size = 20,
    double spacing = 0.5,
    Color color = cream,
    List<Shadow>? shadows,
  }) => GoogleFonts.lilitaOne(
    fontSize: size,
    height: 1.05,
    letterSpacing: spacing,
    color: color,
    shadows: shadows,
  );

  // Corps → Plus Jakarta Sans (400–800).
  static TextStyle body({
    Color color = cream,
    double size = 14,
    FontWeight weight = FontWeight.w500,
    double height = 1.4,
  }) => GoogleFonts.plusJakartaSans(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
  );

  // Micro-labels / badges → Silkscreen (pixel). Jamais sur du texte courant.
  static TextStyle pixel({
    double size = 8.5,
    Color color = cream,
    double spacing = 0.5,
  }) => GoogleFonts.silkscreen(
    fontSize: size,
    letterSpacing: spacing,
    color: color,
    height: 1.0,
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   SCANLINES CRT — overlay global très discret (≤5% d'opacité)
//   réf : repeating-linear-gradient(to bottom, rgba(0,0,0,op) 0 1px,
//         transparent 1px 3px) ; mix-blend-mode: multiply
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ScanlineOverlay extends StatelessWidget {
  final double opacity;
  const ScanlineOverlay({super.key, this.opacity = 0.05});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ScanlinePainter(opacity),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final double opacity;
  _ScanlinePainter(this.opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withValues(alpha: opacity)
          ..blendMode = BlendMode.multiply
          ..strokeWidth = 1;
    // Une ligne sombre de 1px toutes les 3px (1px ligne + 2px vide).
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y + 0.5), Offset(size.width, y + 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter old) => old.opacity != opacity;
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   ARCADE BUTTON — relief biseauté qui s'enfonce au clic
//   réf : gradient (accent clairci → accent → accent-deep),
//         inset highlights + arête solide 6px + ombre portée ;
//         :active → translateY(5px) + ombre réduite.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class ArcadeButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color colorDeep;
  final Color textColor;
  final VoidCallback? onTap;
  final bool big;
  final double? width;

  const ArcadeButton({
    super.key,
    required this.label,
    this.icon,
    this.color = Arcade.gold,
    this.colorDeep = Arcade.goldDeep,
    this.textColor = const Color(0xFF2A1C00),
    this.onTap,
    this.big = false,
    this.width,
  });

  @override
  State<ArcadeButton> createState() => _ArcadeButtonState();
}

class _ArcadeButtonState extends State<ArcadeButton> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  void _setPressed(bool v) {
    if (!_enabled) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.color;
    final deep = widget.colorDeep;
    final down = _pressed;

    final boxShadow =
        down
            ? [
              BoxShadow(color: deep, offset: const Offset(0, 1)),
              const BoxShadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ]
            : [
              // arête solide « 3D » (0 6px 0 accent-deep)
              BoxShadow(color: deep, offset: const Offset(0, 6)),
              const BoxShadow(
                color: Color(0x73000000),
                blurRadius: 22,
                offset: Offset(0, 12),
              ),
            ];

    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      transform: Matrix4.translationValues(0, down ? 5 : 0, 0),
      width: widget.width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Arcade.rButton),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(Colors.white, accent, 0.88)!, accent, deep],
          stops: const [0.0, 0.42, 1.0],
        ),
        boxShadow: boxShadow,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // liseré interne clair (haut) — inset highlight
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              color: Colors.white.withValues(alpha: down ? 0.40 : 0.55),
            ),
          ),
          // liseré interne sombre (bas) — inset lowlight
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              color: Colors.black.withValues(alpha: down ? 0.25 : 0.22),
            ),
          ),
          // « gleam » : reflet supérieur
          Positioned(
            top: 1,
            left: 0,
            right: 0,
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: Container(
                height: widget.big ? 18 : 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.big ? 26 : 20,
              vertical: widget.big ? 17 : 13,
            ),
            child: Row(
              mainAxisSize:
                  widget.width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    color: widget.textColor,
                    size: widget.big ? 22 : 19,
                  ),
                  const SizedBox(width: 9),
                ],
                Text(
                  widget.label,
                  style: Arcade.title(
                    size: widget.big ? 19 : 15.5,
                    color: widget.textColor,
                    spacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: child,
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   PIXEL BADGE — pastille Silkscreen, bordure currentColor
//   réf : Silkscreen 8.5px, uppercase, padding 4/7/3, radius 5, gap 4,
//         border 1.5px currentColor.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class PixelBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool filled;

  const PixelBadge({
    super.key,
    required this.label,
    this.icon,
    this.color = Arcade.cream,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Arcade.bg : color;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 7, 3),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: Arcade.pixel(size: 8.5, color: fg, spacing: 0.5),
          ),
        ],
      ),
    );
  }
}
