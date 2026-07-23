import 'dart:math' as math;

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;
  late final AnimationController _spinController;
  late final AnimationController _entranceController;
  late final Animation<double> _entrance;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulse = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _entrance = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _spinController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    return ColoredBox(
      color: colors.bg,
      child: Center(
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            return Opacity(
              opacity: _entrance.value,
              child: Transform.translate(
                offset: Offset(0, (1 - _entrance.value) * 12),
                child: child,
              ),
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              colors.accentSoft.withValues(
                                alpha: colors.accentSoft.a * _pulse.value,
                              ),
                              colors.accentSoft.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                      Opacity(opacity: _pulse.value, child: child),
                    ],
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    'assets/branding/cockpit_logo.png',
                    width: 64,
                    height: 64,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('Cockpit', style: typo.display.copyWith(color: colors.text)),
              const SizedBox(height: 20),
              AnimatedBuilder(
                animation: _spinController,
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(20, 20),
                    painter: _LoadingRingPainter(
                      progress: _spinController.value,
                      color: colors.accent,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Anel indeterminado: um arco de ~90° girando continuamente.
class _LoadingRingPainter extends CustomPainter {
  const _LoadingRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final rect = Offset.zero & size;
    final startAngle = progress * 2 * math.pi;
    canvas.drawArc(rect.deflate(1), startAngle, math.pi / 2, false, paint);
  }

  @override
  bool shouldRepaint(covariant _LoadingRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
