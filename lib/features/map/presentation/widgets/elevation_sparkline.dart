import 'package:flutter/material.dart';

class ElevationSparkline extends StatelessWidget {
  final List<double> profile;
  final double height;
  final Color color;

  const ElevationSparkline({
    super.key,
    required this.profile,
    this.height = 40,
    this.color = const Color(0xFF4A90A0),
  });

  @override
  Widget build(BuildContext context) {
    if (profile.isEmpty) return const SizedBox.shrink();

    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: CustomPaint(
        painter: _ElevationPainter(profile, color),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  final List<double> profile;
  final Color color;

  _ElevationPainter(this.profile, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (profile.length < 2) return;

    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0.01)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.fill;

    double minVal = profile[0];
    double maxVal = profile[0];
    for (var v in profile) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    final range = (maxVal - minVal).clamp(1.0, 10000.0);
    final dx = size.width / (profile.length - 1);

    final path = Path();
    path.moveTo(0, size.height - ((profile[0] - minVal) / range * size.height));

    for (int i = 1; i < profile.length; i++) {
      path.lineTo(i * dx, size.height - ((profile[i] - minVal) / range * size.height));
    }

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ElevationPainter oldDelegate) => oldDelegate.profile != profile;
}
