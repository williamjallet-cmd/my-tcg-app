// pack_opening_screen.dart
// FIX DA point 5 : fond aligné avec le thème dark de l'app (#080814)
// FIX : appel saveUserCards avant Navigator.pop + import CollectionService

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'card_model.dart';
import 'card_storage.dart';
import 'card_inspector_screen.dart';
import 'collection_service.dart';

enum _Phase { entering, idle, shaking, tearing, flying, revealing }

class _FlyData {
  final double dx, dy, rot;
  const _FlyData(this.dx, this.dy, this.rot);
}

class PackOpeningScreen extends StatefulWidget {
  final List<SavedCard> cards;
  final String collectionId;
  final String packName;
  final Color packColor;

  const PackOpeningScreen({
    super.key,
    required this.cards,
    required this.collectionId,
    this.packName = 'Booster Pack',
    this.packColor = const Color(0xFF6C3FC5),
  });

  @override
  State<PackOpeningScreen> createState() => _PackOpeningScreenState();
}

class _PackOpeningScreenState extends State<PackOpeningScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.entering;
  final _rng = math.Random();
  late final List<_FlyData> _flyData;
  bool _isSaving = false;

  late AnimationController _entryCtrl,
      _pulseCtrl,
      _shakeCtrl,
      _tearCtrl,
      _flyCtrl;
  late List<AnimationController> _flipCtrls;
  late Animation<double> _entryScale, _entryY;
  late Animation<double> _pulseScale, _glowIntensity;
  late Animation<double> _shakeX;
  late Animation<double> _flapAngle, _flashOpacity, _packFade;
  late List<Animation<double>> _flipAnims;
  late List<bool> _flipped;

  @override
  void initState() {
    super.initState();
    final n = widget.cards.length;
    _flipped = List.filled(n, false);

    _flyData = List.generate(n, (i) {
      final spread = (n <= 1) ? 0.5 : i / (n - 1);
      final angle = math.pi * (-0.38 + spread * 0.76);
      final dist = 85.0 + _rng.nextDouble() * 65.0;
      return _FlyData(
        math.cos(angle) * dist * (1 + _rng.nextDouble() * 0.25),
        -(60 + _rng.nextDouble() * 85),
        (_rng.nextDouble() - 0.5) * 0.65,
      );
    });

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _entryScale = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.elasticOut));
    _entryY = Tween<double>(begin: 280.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(
      begin: 1.0,
      end: 1.065,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _glowIntensity = Tween<double>(
      begin: 0.22,
      end: 0.78,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _shakeX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -18.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -18.0, end: 18.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 18.0, end: -13.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -13.0, end: 13.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 13.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);

    _tearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _flapAngle = Tween<double>(begin: 0.0, end: -math.pi * 0.63).animate(
      CurvedAnimation(
        parent: _tearCtrl,
        curve: const Interval(0.0, 0.55, curve: Curves.easeIn),
      ),
    );
    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 2),
    ]).animate(
      CurvedAnimation(parent: _tearCtrl, curve: const Interval(0.42, 1.0)),
    );
    _packFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _tearCtrl,
        curve: const Interval(0.52, 1.0, curve: Curves.easeIn),
      ),
    );

    _flyCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );

    _flipCtrls = List.generate(
      n,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 560),
      ),
    );
    _flipAnims =
        _flipCtrls
            .map(
              (c) => Tween<double>(
                begin: 0.0,
                end: math.pi,
              ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
            )
            .toList();

    _entryCtrl.forward().then((_) => setState(() => _phase = _Phase.idle));
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _pulseCtrl.dispose();
    _shakeCtrl.dispose();
    _tearCtrl.dispose();
    _flyCtrl.dispose();
    for (final c in _flipCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _openPack() async {
    if (_phase != _Phase.idle) return;
    HapticFeedback.mediumImpact();
    setState(() => _phase = _Phase.shaking);
    _pulseCtrl.stop();
    await _shakeCtrl.forward();
    HapticFeedback.heavyImpact();
    setState(() => _phase = _Phase.tearing);
    await _tearCtrl.forward();
    setState(() => _phase = _Phase.flying);
    await _flyCtrl.forward();
    setState(() => _phase = _Phase.revealing);
  }

  void _flipCard(int i) {
    if (_flipped[i]) return;
    HapticFeedback.selectionClick();
    _flipCtrls[i].forward().then((_) => setState(() => _flipped[i] = true));
  }

  void _inspectCard(int i) {
    final card = widget.cards[i];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => CardInspectorScreen(
              frontCard: SavedCardFrontWidget(
                card: card,
                width: 300,
                height: 420,
              ),
              backCard: SavedCardBackWidget(
                card: card,
                width: 300,
                height: 420,
              ),
            ),
      ),
    );
  }

  Future<void> _saveAndReturn() async {
    setState(() => _isSaving = true);
    try {
      await CollectionService.instance.saveUserCards(
        widget.collectionId,
        widget.cards,
      );
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // FIX DA point 5 : fond aligné avec le reste de l'app (plus de Colors.black pur)
      backgroundColor: const Color(0xFF080814),
      body: Stack(
        children: [
          _background(),
          _phase == _Phase.revealing ? _revealLayout() : _packLayout(),
          _flashOverlay(),
          _closeButton(),
        ],
      ),
    );
  }

  Widget _background() => AnimatedContainer(
    duration: const Duration(milliseconds: 800),
    decoration: BoxDecoration(
      gradient: RadialGradient(
        radius: 1.5,
        colors: [
          widget.packColor.withValues(
            alpha: _phase == _Phase.revealing ? 0.40 : 0.14,
          ),
          // FIX DA : fond dark purple au lieu de Colors.black
          const Color(0xFF080814),
        ],
      ),
    ),
  );

  Widget _flashOverlay() {
    if (_phase != _Phase.tearing) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _flashOpacity,
      builder:
          (_, __) => IgnorePointer(
            child: Opacity(
              opacity: _flashOpacity.value,
              child: Container(color: Colors.white),
            ),
          ),
    );
  }

  Widget _closeButton() => SafeArea(
    child: Align(
      alignment: Alignment.topLeft,
      child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white38),
        onPressed: () => Navigator.pop(context),
      ),
    ),
  );

  Widget _packLayout() {
    return LayoutBuilder(
      builder: (_, bc) {
        final size = Size(bc.maxWidth, bc.maxHeight);
        return Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _animatedPack(),
                  const SizedBox(height: 28),
                  _tapHint(),
                ],
              ),
            ),
            if (_phase == _Phase.flying) ..._flyingCards(size),
          ],
        );
      },
    );
  }

  Widget _animatedPack() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _entryCtrl,
        _pulseCtrl,
        _shakeCtrl,
        _tearCtrl,
      ]),
      builder: (_, __) {
        double scale = _entryScale.value;
        double dx = 0.0, dy = _entryY.value;
        double flapAngle = 0.0, opacity = 1.0;
        switch (_phase) {
          case _Phase.idle:
            scale *= _pulseScale.value;
          case _Phase.shaking:
            dx = _shakeX.value;
            scale *= _pulseScale.value;
          case _Phase.tearing:
            flapAngle = _flapAngle.value;
            opacity = _packFade.value;
          case _Phase.flying:
            opacity = 0.0;
            scale = 0.0;
          default:
            break;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: scale.clamp(0.0, 1.25),
              child: _PackVisual(
                packName: widget.packName,
                packColor: widget.packColor,
                flapAngle: flapAngle,
                glowIntensity: _phase == _Phase.idle ? _glowIntensity.value : 0,
                onTap: _openPack,
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _flyingCards(Size size) {
    const cw = 110.0, sp = 8.0;
    final n = widget.cards.length;
    final cx = size.width / 2;
    final cy = size.height / 2 - 60;
    final totalW = n * cw + (n - 1) * sp;
    final rowLeft = (size.width - totalW) / 2;
    final rowY = size.height * 0.54;

    return List.generate(n, (i) {
      final d = _flyData[i];
      final fx = rowLeft + i * (cw + sp) + cw / 2;
      return AnimatedBuilder(
        animation: _flyCtrl,
        builder: (_, __) {
          final t = _flyCtrl.value;
          double x, y, rot;
          if (t <= 0.5) {
            final e = Curves.easeOut.transform(t * 2);
            x = cx + d.dx * e;
            y = cy + d.dy * e;
            rot = d.rot * e;
          } else {
            final e = Curves.easeInOut.transform((t - 0.5) * 2);
            x = cx + d.dx + (fx - cx - d.dx) * e;
            y = cy + d.dy + (rowY - cy - d.dy) * e;
            rot = d.rot * (1 - e);
          }
          return Positioned(
            left: x - cw / 2,
            top: y - 77,
            child: Transform.rotate(
              angle: rot,
              child: _CardBack(packColor: widget.packColor),
            ),
          );
        },
      );
    });
  }

  Widget _tapHint() => AnimatedOpacity(
    opacity: _phase == _Phase.idle ? 1.0 : 0.0,
    duration: const Duration(milliseconds: 300),
    child: AnimatedBuilder(
      animation: _pulseCtrl,
      builder:
          (_, child) => Transform.translate(
            offset: Offset(0, -7 * _pulseCtrl.value),
            child: child,
          ),
      child: Column(
        children: [
          const Icon(
            Icons.keyboard_arrow_up_rounded,
            color: Colors.white54,
            size: 28,
          ),
          const SizedBox(height: 4),
          Text(
            'Appuie pour ouvrir',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 16,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w300,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _revealLayout() {
    final allFlipped = _flipped.every((f) => f);
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: Text(
                allFlipped
                    ? '✨ ${widget.cards.length} cartes obtenues !'
                    : 'Touche une carte pour la révéler',
                key: ValueKey(allFlipped),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: allFlipped ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 400),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search, color: Colors.white38, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Appuie à nouveau sur une carte pour l\'inspecter',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.cards.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(i),
                      tween: Tween(begin: 1.0, end: 0.0),
                      duration: Duration(milliseconds: 380 + i * 70),
                      curve: Curves.easeOutBack,
                      builder:
                          (_, t, child) => Transform.translate(
                            offset: Offset(0, t * 160),
                            child: Opacity(
                              opacity: (1 - t).clamp(0.0, 1.0),
                              child: child,
                            ),
                          ),
                      child: _FlippableCard(
                        card: widget.cards[i],
                        flipAnim: _flipAnims[i],
                        isFlipped: _flipped[i],
                        packColor: widget.packColor,
                        onTap:
                            _flipped[i]
                                ? () => _inspectCard(i)
                                : () => _flipCard(i),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: allFlipped ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 600),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 40, top: 12),
            child: GestureDetector(
              onTap: allFlipped && !_isSaving ? _saveAndReturn : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  // FIX DA : bouton cohérent avec le thème violet/rose
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isSaving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                        : const Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 20,
                        ),
                    const SizedBox(width: 10),
                    Text(
                      _isSaving ? 'Sauvegarde...' : 'Retour à la collection',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   VISUEL DU PACK
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _PackVisual extends StatelessWidget {
  final String packName;
  final Color packColor;
  final double flapAngle;
  final double glowIntensity;
  final VoidCallback onTap;

  const _PackVisual({
    required this.packName,
    required this.packColor,
    required this.flapAngle,
    required this.glowIntensity,
    required this.onTap,
  });

  static const double kW = 182.0, kH = 286.0, kFlapH = 54.0, kRadius = 16.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: kW + 50,
        height: kH + 50,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (glowIntensity > 0)
              Container(
                width: kW,
                height: kH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadius),
                  boxShadow: [
                    BoxShadow(
                      color: packColor.withValues(alpha: glowIntensity),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            Positioned(top: kFlapH + 4, child: _body()),
            Positioned(
              top: 20,
              child: Transform(
                alignment: Alignment.topCenter,
                transform:
                    Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(flapAngle),
                child: _topFlap(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() => Container(
    width: kW,
    height: kH - kFlapH,
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(kRadius),
        top: Radius.circular(3),
      ),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          packColor,
          Color.lerp(packColor, Colors.black, 0.42)!,
          Colors.black87,
        ],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.13),
        width: 1.5,
      ),
    ),
    child: ClipRRect(
      borderRadius: const BorderRadius.vertical(
        bottom: Radius.circular(kRadius),
        top: Radius.circular(3),
      ),
      child: Stack(children: [_holoShimmer(), _bodyContent(), _tearDotLine()]),
    ),
  );

  Widget _topFlap() => Container(
    width: kW,
    height: kFlapH + 6,
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(kRadius),
        bottom: Radius.circular(3),
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.lerp(packColor, Colors.white, 0.18)!, packColor],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.15),
        width: 1.5,
      ),
    ),
  );

  Widget _holoShimmer() => Positioned.fill(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.04),
            Colors.transparent,
            Colors.white.withValues(alpha: 0.08),
          ],
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
        ),
      ),
    ),
  );

  Widget _bodyContent() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.5,
            ),
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 18),
        Text(
          packName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.2,
            shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'BOOSTER PACK',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 9,
              letterSpacing: 2.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tearDotLine() => Positioned(
    top: 3,
    left: 0,
    right: 0,
    child: Row(
      children: List.generate(
        32,
        (i) => Expanded(
          child: Container(
            height: 1.5,
            color:
                i.isEven
                    ? Colors.white.withValues(alpha: 0.28)
                    : Colors.transparent,
          ),
        ),
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   DOS DE CARTE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _CardBack extends StatelessWidget {
  final Color packColor;
  const _CardBack({required this.packColor});

  @override
  Widget build(BuildContext context) => Container(
    width: 110,
    height: 154,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [packColor.withValues(alpha: 0.9), Colors.black87],
      ),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.2),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: packColor.withValues(alpha: 0.4),
          blurRadius: 14,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Center(
      child: Icon(
        Icons.auto_awesome,
        color: Colors.white.withValues(alpha: 0.35),
        size: 30,
      ),
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   CARTE RETOURNABLE
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _FlippableCard extends StatefulWidget {
  final SavedCard card;
  final Animation<double> flipAnim;
  final bool isFlipped;
  final Color packColor;
  final VoidCallback onTap;

  const _FlippableCard({
    required this.card,
    required this.flipAnim,
    required this.isFlipped,
    required this.packColor,
    required this.onTap,
  });

  @override
  State<_FlippableCard> createState() => _FlippableCardState();
}

class _FlippableCardState extends State<_FlippableCard>
    with SingleTickerProviderStateMixin {
  static const double kW = 120.0, kH = 170.0;
  AnimationController? _glowCtrl;
  Animation<double>? _glowRadius;
  bool _glowTriggered = false;

  Color get _rarityColor {
    switch (widget.card.rarity) {
      case Rarity.legendary:
        return const Color(0xFFFFD700);
      case Rarity.epic:
        return const Color(0xFF9C27B0);
      case Rarity.rare:
        return const Color(0xFF2196F3);
      case Rarity.uncommon:
        return const Color(0xFF4CAF50);
      case Rarity.common:
        return const Color(0xFF9E9E9E);
    }
  }

  String get _rarityName {
    switch (widget.card.rarity) {
      case Rarity.legendary:
        return 'Légendaire';
      case Rarity.epic:
        return 'Épique';
      case Rarity.rare:
        return 'Rare';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.common:
        return 'Commun';
    }
  }

  bool get _isRarePlus =>
      widget.card.rarity == Rarity.rare ||
      widget.card.rarity == Rarity.epic ||
      widget.card.rarity == Rarity.legendary;

  @override
  void initState() {
    super.initState();
    if (_isRarePlus) {
      _glowCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700),
      );
      _glowRadius = Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(CurvedAnimation(parent: _glowCtrl!, curve: Curves.easeOut));
      widget.flipAnim.addListener(_checkMidpoint);
    }
  }

  void _checkMidpoint() {
    if (!_glowTriggered && widget.flipAnim.value >= math.pi / 2) {
      _glowTriggered = true;
      _glowCtrl?.forward();
    }
  }

  @override
  void dispose() {
    widget.flipAnim.removeListener(_checkMidpoint);
    _glowCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: widget.flipAnim,
            builder: (_, __) {
              final a = widget.flipAnim.value;
              final showFront = a > math.pi / 2;
              return Transform(
                alignment: Alignment.center,
                transform:
                    Matrix4.identity()
                      ..setEntry(3, 2, 0.002)
                      ..rotateY(a),
                child:
                    showFront
                        ? Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()..rotateY(math.pi),
                          child: _front(),
                        )
                        : _back(),
              );
            },
          ),
          if (widget.isFlipped)
            Positioned(
              bottom: -8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search,
                        color: Colors.white.withValues(alpha: 0.6),
                        size: 10,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Inspecter',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _back() => Container(
    width: kW,
    height: kH,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [widget.packColor, Colors.black87],
      ),
      border: Border.all(color: Colors.white24, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: widget.packColor.withValues(alpha: 0.35),
          blurRadius: 10,
          spreadRadius: 2,
        ),
      ],
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.auto_awesome,
          color: Colors.white.withValues(alpha: 0.45),
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          '?',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _front() {
    final rc = _rarityColor;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (_isRarePlus && _glowRadius != null)
          AnimatedBuilder(
            animation: _glowRadius!,
            builder: (_, __) {
              final v = _glowRadius!.value;
              return Container(
                width: kW + 60 * v,
                height: kH + 60 * v,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12 + 30 * v),
                  boxShadow: [
                    BoxShadow(
                      color: rc.withValues(alpha: (1 - v) * 0.9),
                      blurRadius: 40 * v,
                      spreadRadius: 14 * v,
                    ),
                  ],
                ),
              );
            },
          ),
        Container(
          width: kW,
          height: kH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF0D0D1C),
            border: Border.all(color: rc, width: 2),
            boxShadow: [
              BoxShadow(
                color: rc.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: 3,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [Expanded(flex: 3, child: _artArea(rc)), _infoBar(rc)],
            ),
          ),
        ),
      ],
    );
  }

  Widget _artArea(Color rc) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [rc.withValues(alpha: 0.14), Colors.black54],
      ),
    ),
    child:
        widget.card.imageBytes != null
            ? Image.memory(
              widget.card.imageBytes!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _defaultArt(rc),
            )
            : _defaultArt(rc),
  );

  Widget _defaultArt(Color rc) => Center(
    child: Icon(
      Icons.auto_fix_high,
      color: rc.withValues(alpha: 0.6),
      size: 38,
    ),
  );

  Widget _infoBar(Color rc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    color: Colors.black87,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.card.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: rc.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _rarityName.toUpperCase(),
            style: TextStyle(
              color: rc,
              fontSize: 7,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    ),
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//   WIDGETS DE RENDU POUR L'INSPECTEUR 3D
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class SavedCardFrontWidget extends StatelessWidget {
  final SavedCard card;
  final double width;
  final double height;

  const SavedCardFrontWidget({
    super.key,
    required this.card,
    this.width = 300,
    this.height = 420,
  });

  Color get _rarityColor {
    switch (card.rarity) {
      case Rarity.legendary:
        return const Color(0xFFFFD700);
      case Rarity.epic:
        return const Color(0xFF9C27B0);
      case Rarity.rare:
        return const Color(0xFF2196F3);
      case Rarity.uncommon:
        return const Color(0xFF4CAF50);
      case Rarity.common:
        return const Color(0xFF9E9E9E);
    }
  }

  String get _rarityName {
    switch (card.rarity) {
      case Rarity.legendary:
        return 'Légendaire';
      case Rarity.epic:
        return 'Épique';
      case Rarity.rare:
        return 'Rare';
      case Rarity.uncommon:
        return 'Peu commun';
      case Rarity.common:
        return 'Commun';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rc = _rarityColor;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFF0D0D1C),
        border: Border.all(color: rc, width: 3),
        boxShadow: [
          BoxShadow(
            color: rc.withValues(alpha: 0.6),
            blurRadius: 28,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      rc.withValues(alpha: 0.18),
                      const Color(0xFF0D0D1C),
                    ],
                  ),
                ),
              ),
            ),
            if (card.imageBytes != null)
              Positioned(
                left: card.imageX * (width / 400),
                top: card.imageY * (height / 560),
                child: Transform.scale(
                  scale: card.imageScale,
                  alignment: Alignment.topLeft,
                  child: Image.memory(
                    card.imageBytes!,
                    width: width * 0.92,
                    fit: BoxFit.fitWidth,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: rc.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: rc.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            _rarityName.toUpperCase(),
                            style: TextStyle(
                              color: rc,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (card.effect != CardEffect.none)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              _effectName(card.effect),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 9,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (card.textZones.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...card.textZones.map(
                        (z) => Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            z.text,
                            style: TextStyle(
                              color: Color(z.color),
                              fontSize: (z.fontSize * 0.72).clamp(8.0, 16.0),
                              fontFamily: z.fontFamily,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.06),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.03),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.07),
                      ],
                      stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _effectName(CardEffect e) {
    switch (e) {
      case CardEffect.holographic:
        return '✨ Holographique';
      case CardEffect.shiny:
        return '⭐ Brillant';
      case CardEffect.negative:
        return '◑ Négatif';
      case CardEffect.none:
        return '';
    }
  }
}

class SavedCardBackWidget extends StatelessWidget {
  final SavedCard card;
  final double width;
  final double height;

  const SavedCardBackWidget({
    super.key,
    required this.card,
    this.width = 300,
    this.height = 420,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Color(card.backColor);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: bg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: bg.withValues(alpha: 0.5),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            if (card.backImageBytes != null)
              Positioned.fill(
                child: Image.memory(
                  card.backImageBytes!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.04),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.09),
                      ],
                      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            if (card.backImageBytes == null)
              Center(
                child: Icon(
                  Icons.auto_awesome,
                  color: Colors.white.withValues(alpha: 0.25),
                  size: 72,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
