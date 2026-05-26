import 'dart:math';
import 'package:flutter/material.dart';

class CardInspectorScreen extends StatefulWidget {
  final Widget frontCard;
  final Widget backCard;

  const CardInspectorScreen({
    super.key,
    required this.frontCard,
    required this.backCard,
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
                child: Center(
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
                                  transform: Matrix4.identity()..rotateY(pi),
                                  child: widget.backCard,
                                ),
                      );
                    },
                  ),
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
                    label: const Text(
                      'Centrer',
                      style: TextStyle(color: Colors.white54),
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
                  child: ElevatedButton.icon(
                    onPressed: _flip,
                    icon: const Icon(Icons.flip, color: Colors.white),
                    label: Text(
                      _isFlipped ? '👁 Voir le recto' : '🔄 Retourner la carte',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C4AB6),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
