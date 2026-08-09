// pack_opening_ceremony.dart
// ─────────────────────────────────────────────────────────────────────────
//   CEREMONIE — sachet foil qu'on dechire, et ses painters.
//
//   Extrait de pack_opening_screen.dart pour reduire sa taille.
//   `part of` : meme bibliotheque que le parent, donc les helpers prives
//   partages (_Pal, _arcade, _pixel, _rarityColor...) restent accessibles
//   SANS renommage. Les imports vivent dans le fichier parent.
// ─────────────────────────────────────────────────────────────────────────

part of 'pack_opening_screen.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CÉRÉMONIE — SACHET FOIL QU'ON DÉCHIRE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _BoosterCeremony extends StatefulWidget {
  final String packName;
  final String packSubtitle;
  final Uint8List? packImageBytes;
  final String? packImageUrl;
  final int cardCount;
  final VoidCallback onOpened;
  final void Function([int]) onFlash;

  const _BoosterCeremony({
    required this.packName,
    required this.packSubtitle,
    required this.packImageBytes,
    required this.packImageUrl,
    required this.cardCount,
    required this.onOpened,
    required this.onFlash,
  });

  @override
  State<_BoosterCeremony> createState() => _BoosterCeremonyState();
}

class _BoosterCeremonyState extends State<_BoosterCeremony>
    with SingleTickerProviderStateMixin {
  static const double kW = 220, kH = 304;

  double _progress = 0; // 0 → 1
  bool _done = false;
  bool _dragging = false;
  double _startY = 0;
  double _moved = 0;

  late final AnimationController _idle; // flottement + foil

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  void _finish() {
    if (_done) return;
    setState(() => _done = true);
    // anime progress → 1
    const step = Duration(milliseconds: 18);
    void tick() {
      if (!mounted) return;
      setState(() => _progress = math.min(1, _progress + 0.12));
      if (_progress >= 1) {
        widget.onFlash(520);
        Future.delayed(const Duration(milliseconds: 300), widget.onOpened);
      } else {
        Future.delayed(step, tick);
      }
    }

    tick();
  }

  void _snapBack() {
    const step = Duration(milliseconds: 16);
    void tick() {
      if (!mounted || _done) return;
      setState(() => _progress = math.max(0, _progress - 0.14));
      if (_progress > 0) Future.delayed(step, tick);
    }

    tick();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _done ? 0 : 1,
          child: Text(
            '★ DÉCHIRE LE SACHET ★',
            style: _pixel(size: 10, color: _Pal.teal, spacing: 2),
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onVerticalDragStart: (d) {
            if (_done) return;
            _dragging = true;
            _startY = d.globalPosition.dy;
            _moved = 0;
          },
          onVerticalDragUpdate: (d) {
            if (!_dragging || _done) return;
            final up = _startY - d.globalPosition.dy;
            _moved = math.max(_moved, up.abs());
            setState(() => _progress = (up / 150).clamp(0.0, 1.0));
          },
          onVerticalDragEnd: (_) {
            if (!_dragging || _done) return;
            _dragging = false;
            if (_moved < 8) {
              _finish();
            } else if (_progress >= 0.42) {
              _finish();
            } else {
              _snapBack();
            }
          },
          onTap: () {
            if (!_done) _finish();
          },
          child: AnimatedBuilder(
            animation: _idle,
            builder: (_, __) {
              final bob =
                  (_progress == 0 && !_done)
                      ? math.sin(_idle.value * 2 * math.pi) * 10
                      : 0.0;
              final rot =
                  (_progress == 0 && !_done)
                      ? math.sin(_idle.value * 2 * math.pi) * 0.026
                      : 0.0;
              return Transform.translate(
                offset: Offset(0, bob),
                child: Transform.rotate(angle: rot, child: _packStack()),
              );
            },
          ),
        ),
        const SizedBox(height: 30),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _done ? 0 : 1,
          child: Text('Tire vers le haut ↑', style: _arcade(size: 17)),
        ),
      ],
    );
  }

  Widget _packStack() {
    final lidDx = _progress * 26;
    final lidDy = -_progress * 250;
    final lidRot = _progress * 18 * math.pi / 180;
    final lidOpacity = (1 - _progress * 0.95).clamp(0.0, 1.0);
    final cardsDy = -_progress * 168;
    final foil = _idle.value;

    return SizedBox(
      width: kW + 40,
      height: kH + 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // halo doré
          Container(
            width: 200,
            height: 200,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x59FFC83D), Color(0x00FFC83D)],
                stops: [0.0, 0.7],
              ),
            ),
          ),

          // dos du sachet
          SizedBox(
            width: kW,
            height: kH,
            child: _FoilFace(dark: true, foil: foil),
          ),

          // cartes qui sortent
          Transform.translate(
            offset: Offset(0, cardsDy),
            child: SizedBox(
              width: kW,
              height: kH,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  for (final o in [-1, 0, 1])
                    Positioned(
                      top: 64,
                      child: Transform.translate(
                        offset: Offset(o * 16, 0),
                        child: Transform.rotate(
                          angle: o * 5 * math.pi / 180,
                          child: _MiniCardBack(w: 120),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // face avant (bord déchiré en bas de la ligne zigzag)
          ClipPath(
            clipper: _TearClipper(isLid: false),
            child: SizedBox(
              width: kW,
              height: kH,
              child: _FoilFace(
                foil: foil,
                showArt: true,
                packName: widget.packName,
                packSubtitle: widget.packSubtitle,
                packImageBytes: widget.packImageBytes,
                packImageUrl: widget.packImageUrl,
                cardCount: widget.cardCount,
                tornRimShadow: true,
              ),
            ),
          ),

          // couvercle détachable (au-dessus de la ligne)
          Transform.translate(
            offset: Offset(lidDx, lidDy),
            child: Transform.rotate(
              angle: lidRot,
              child: Opacity(
                opacity: lidOpacity,
                child: ClipPath(
                  clipper: _TearClipper(isLid: true),
                  child: SizedBox(
                    width: kW,
                    height: kH,
                    child: _FoilFace(foil: foil, crimp: true),
                  ),
                ),
              ),
            ),
          ),

          // languette 👆
          if (!_done)
            Positioned(
              top: 2,
              right: 4,
              child: AnimatedBuilder(
                animation: _idle,
                builder:
                    (_, __) => Transform.translate(
                      offset: Offset(
                        0,
                        math.sin(_idle.value * 2 * math.pi) * 4,
                      ),
                      child: const Text('👆', style: TextStyle(fontSize: 22)),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

// Face foil du sachet (réutilisée pour dos / face / couvercle)
class _FoilFace extends StatelessWidget {
  final bool dark;
  final bool showArt;
  final bool crimp;
  final bool tornRimShadow;
  final double foil; // 0..1 position du reflet
  final String? packName;
  final String? packSubtitle;
  final Uint8List? packImageBytes;
  final String? packImageUrl;
  final int? cardCount;

  const _FoilFace({
    this.dark = false,
    this.showArt = false,
    this.crimp = false,
    this.tornRimShadow = false,
    this.foil = 0,
    this.packName,
    this.packSubtitle,
    this.packImageBytes,
    this.packImageUrl,
    this.cardCount,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          // fond foil holographique
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.7, -1),
                  end: const Alignment(0.7, 1),
                  colors:
                      dark
                          ? const [Color(0xFF2A2140), Color(0xFF15101F)]
                          : const [
                            Color(0xFF3A2A6A),
                            Color(0xFF6A2EA8),
                            Color(0xFF21808F),
                            Color(0xFFB43E78),
                            Color(0xFF3A2A6A),
                          ],
                  stops: dark ? null : const [0.0, 0.26, 0.52, 0.74, 1.0],
                ),
              ),
            ),
          ),
          // scanlines
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinesPainter(opacity: 0.16)),
            ),
          ),
          // reflet foil animé (diagonale qui balaie)
          if (!dark)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _FoilShinePainter(t: foil)),
              ),
            ),
          // contenu (wordmark + image + pastille)
          if (showArt && !dark) Positioned.fill(child: _artContent()),
          // sertissage cranté (couvercle)
          if (crimp)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 14,
              child: CustomPaint(painter: _CrimpPainter()),
            ),
          // ombre du haut
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 78,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.18),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          // ombre intérieure du bord déchiré
          if (tornRimShadow)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _artContent() {
    Widget emblem;
    const d = 70.0;
    if (packImageBytes != null) {
      emblem = ClipOval(
        child: Image.memory(
          packImageBytes!,
          width: d,
          height: d,
          fit: BoxFit.cover,
          cacheWidth: 140,
          errorBuilder: (_, __, ___) => _defaultEmblem(d),
        ),
      );
    } else if (packImageUrl != null && packImageUrl!.isNotEmpty) {
      emblem = ClipOval(
        child: Image.network(
          packImageUrl!,
          width: d,
          height: d,
          fit: BoxFit.cover,
          // Meme borne que la variante en memoire juste au-dessus.
          cacheWidth: 140,
          errorBuilder: (_, __, ___) => _defaultEmblem(d),
        ),
      );
    } else {
      emblem = _defaultEmblem(d);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          emblem,
          const SizedBox(height: 12),
          Text(
            (packName ?? 'BOOSTER').toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: _arcade(
              size: 22,
              spacing: 0.5,
              shadows: const [
                Shadow(blurRadius: 1, color: _Pal.gold),
                Shadow(offset: Offset(2, 2), color: Color(0x66000000)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(packSubtitle ?? '').toUpperCase()} · ${cardCount ?? 3} CARTES',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _pixel(
              size: 8,
              color: _Pal.cream.withValues(alpha: 0.85),
              spacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defaultEmblem(double d) => Container(
    width: d,
    height: d,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
    ),
    child: const Center(child: Text('✨', style: TextStyle(fontSize: 32))),
  );
}

// Découpe en dents de scie partagée (couvercle = au-dessus, face = en-dessous)
class _TearClipper extends CustomClipper<Path> {
  final bool isLid;
  _TearClipper({required this.isLid});

  // Points (en % de hauteur) de la ligne zigzag, comme le handoff.
  static const List<List<double>> _zig = [
    [0.0, 0.25],
    [0.02, 0.18],
    [0.09, 0.27],
    [0.16, 0.18],
    [0.23, 0.27],
    [0.30, 0.18],
    [0.37, 0.27],
    [0.44, 0.18],
    [0.51, 0.27],
    [0.58, 0.18],
    [0.65, 0.27],
    [0.72, 0.18],
    [0.79, 0.27],
    [0.86, 0.18],
    [0.93, 0.27],
    [1.0, 0.20],
  ];

  @override
  Path getClip(Size size) {
    final p = Path();
    if (isLid) {
      p.moveTo(0, 0);
      p.lineTo(size.width, 0);
      for (final pt in _zig.reversed) {
        p.lineTo(pt[0] * size.width, pt[1] * size.height);
      }
      p.close();
    } else {
      for (var i = 0; i < _zig.length; i++) {
        final pt = _zig[i];
        if (i == 0) {
          p.moveTo(pt[0] * size.width, pt[1] * size.height);
        } else {
          p.lineTo(pt[0] * size.width, pt[1] * size.height);
        }
      }
      p.lineTo(size.width, size.height);
      p.lineTo(0, size.height);
      p.close();
    }
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ScanlinesPainter extends CustomPainter {
  final double opacity;
  _ScanlinesPainter({required this.opacity});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: opacity);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinesPainter old) => false;
}

class _FoilShinePainter extends CustomPainter {
  final double t;
  _FoilShinePainter({required this.t});
  @override
  void paint(Canvas canvas, Size size) {
    final x = (t * 2 - 0.5) * size.width;
    final rect = Rect.fromLTWH(
      x - size.width * 0.3,
      -size.height * 0.2,
      size.width * 0.6,
      size.height * 1.4,
    );
    final paint =
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.28),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(rect)
          ..blendMode = BlendMode.plus;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.42);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawRect(rect.translate(x, 0), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoilShinePainter old) => old.t != t;
}

class _CrimpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawRect(
        Rect.fromLTWH(x, 0, 3, size.height),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      canvas.drawRect(
        Rect.fromLTWH(x + 3, 0, 3, size.height),
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CrimpPainter old) => false;
}
