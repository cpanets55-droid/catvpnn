import 'dart:math' as math;
import 'package:flutter/material.dart';

enum VpnConnectionPhase {
  disconnected,
  connecting,
  connected,
}

class CatPowerOrb extends StatefulWidget {
  final VpnConnectionPhase phase;
  final VoidCallback onTap;

  const CatPowerOrb({
    super.key,
    required this.phase,
    required this.onTap,
  });

  @override
  State<CatPowerOrb> createState() => _CatPowerOrbState();
}

class _CatPowerOrbState extends State<CatPowerOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.phase) {
      case VpnConnectionPhase.connected:
        return const Color(0xFF00F5A0);
      case VpnConnectionPhase.connecting:
        return const Color(0xFF38BDF8);
      case VpnConnectionPhase.disconnected:
        return const Color(0xFF7C5CFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value;
          final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
          final accent = _accentColor;

          return SizedBox(
            width: 226,
            height: 226,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ripple 1
                Container(
                  width: 206 + (pulse * 18),
                  height: 206 + (pulse * 18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(
                        alpha: widget.phase == VpnConnectionPhase.disconnected
                            ? 0.14
                            : 0.28 * (1 - pulse * 0.5),
                      ),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(
                          alpha: widget.phase == VpnConnectionPhase.connected
                              ? 0.25
                              : 0.12,
                        ),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),

                // Rotating arc when connecting or subtle ring when connected
                if (widget.phase != VpnConnectionPhase.disconnected)
                  Transform.rotate(
                    angle: t * 2 * math.pi,
                    child: CustomPaint(
                      size: const Size(192, 192),
                      painter: _OrbitalArcPainter(
                        color: accent,
                        fullRing: widget.phase == VpnConnectionPhase.connected,
                      ),
                    ),
                  ),

                // Inner main button
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: 168,
                  height: 168,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: widget.phase == VpnConnectionPhase.connected
                          ? const [
                              Color(0xFF133B34),
                              Color(0xFF0B1922),
                            ]
                          : const [
                              Color(0xFF1D223B),
                              Color(0xFF101324),
                            ],
                    ),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.75),
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(64, 58),
                        painter: _CatEmblemPainter(
                          color: accent,
                          eyesGlowing:
                              widget.phase != VpnConnectionPhase.disconnected,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.phase == VpnConnectionPhase.connected
                            ? 'NGẮT KẾT NỐI'
                            : widget.phase == VpnConnectionPhase.connecting
                                ? 'ĐANG NỐI...'
                                : 'BẬT KẾT NỐI',
                        style: TextStyle(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OrbitalArcPainter extends CustomPainter {
  final Color color;
  final bool fullRing;

  _OrbitalArcPainter({required this.color, required this.fullRing});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.45),
          color,
        ],
      ).createShader(rect);

    if (fullRing) {
      canvas.drawArc(rect.deflate(3), 0, math.pi * 1.65, false, paint);
    } else {
      canvas.drawArc(rect.deflate(3), 0, math.pi * 1.15, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitalArcPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fullRing != fullRing;
}

class _CatEmblemPainter extends CustomPainter {
  final Color color;
  final bool eyesGlowing;

  _CatEmblemPainter({required this.color, required this.eyesGlowing});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: eyesGlowing ? 0.18 : 0.08)
      ..style = PaintingStyle.fill;

    // Cyber-Cat head with pointed ears
    final path = Path()
      ..moveTo(w * 0.16, h * 0.44)
      ..lineTo(w * 0.13, h * 0.08) // Left ear tip
      ..lineTo(w * 0.36, h * 0.26)
      ..quadraticBezierTo(w * 0.50, h * 0.22, w * 0.64, h * 0.26)
      ..lineTo(w * 0.87, h * 0.08) // Right ear tip
      ..lineTo(w * 0.84, h * 0.44)
      ..quadraticBezierTo(w * 0.90, h * 0.78, w * 0.50, h * 0.94)
      ..quadraticBezierTo(w * 0.10, h * 0.78, w * 0.16, h * 0.44)
      ..close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, outlinePaint);

    // Eyes (sleek angled cyber visors)
    final eyePaint = Paint()
      ..color = eyesGlowing ? Colors.white : color
      ..style = PaintingStyle.fill;

    final leftEye = Path()
      ..moveTo(w * 0.28, h * 0.50)
      ..lineTo(w * 0.43, h * 0.55)
      ..lineTo(w * 0.32, h * 0.61)
      ..close();

    final rightEye = Path()
      ..moveTo(w * 0.72, h * 0.50)
      ..lineTo(w * 0.57, h * 0.55)
      ..lineTo(w * 0.68, h * 0.61)
      ..close();

    canvas.drawPath(leftEye, eyePaint);
    canvas.drawPath(rightEye, eyePaint);

    // Nose triangle
    final nosePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final nose = Path()
      ..moveTo(w * 0.46, h * 0.69)
      ..lineTo(w * 0.54, h * 0.69)
      ..lineTo(w * 0.50, h * 0.75)
      ..close();
    canvas.drawPath(nose, nosePaint);
  }

  @override
  bool shouldRepaint(covariant _CatEmblemPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.eyesGlowing != eyesGlowing;
}
