import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../data/telemetry_processor.dart';

/// G-G (friction circle) diagram that plots lateral vs longitudinal g-force.
///
/// Shows the vehicle's grip usage envelope as a scatter plot.
/// Concentric circle guides at 0.5g, 1.0g, 1.5g indicate grip levels.
class GGDiagram extends StatelessWidget {
  const GGDiagram({
    super.key,
    required this.data,
    this.compareData,
    this.size = 280,
    this.label1 = 'Lap 1',
    this.label2 = 'Lap 2',
  });

  /// Primary lap G-G data points.
  final List<GGPoint> data;

  /// Optional comparison lap G-G data points.
  final List<GGPoint>? compareData;

  /// Square side length for the diagram.
  final double size;

  /// Legend label for primary data.
  final String label1;

  /// Legend label for comparison data.
  final String label2;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Diagram container
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: Stack(
              children: [
                // Paint layer
                CustomPaint(
                  size: Size(size, size),
                  painter: _GGDiagramPainter(
                    data: data,
                    compareData: compareData,
                    color1: AppColors.purple,
                    color2: AppColors.green,
                  ),
                ),

                // Axis labels
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'Lateral G',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: Text(
                        'Longitudinal G',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Legend
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: AppColors.purple, label: label1),
              if (compareData != null) ...[
                const SizedBox(width: 16),
                _LegendDot(color: AppColors.green, label: label2),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GGDiagramPainter extends CustomPainter {
  _GGDiagramPainter({
    required this.data,
    this.compareData,
    required this.color1,
    required this.color2,
  });

  final List<GGPoint> data;
  final List<GGPoint>? compareData;
  final Color color1;
  final Color color2;

  // The maximum G value shown on each axis
  static const double _maxG = 2.0;

  // Concentric circle intervals
  static const List<double> _circleGs = [0.5, 1.0, 1.5];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    // Scale: half the diagram width represents _maxG
    final padding = 24.0;
    final halfExtent = (min(size.width, size.height) / 2) - padding;
    final scale = halfExtent / _maxG;

    // Draw concentric circle guides
    final circlePaint = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final g in _circleGs) {
      final r = g * scale;
      canvas.drawCircle(Offset(cx, cy), r, circlePaint);

      // Label the circle
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${g.toStringAsFixed(1)}g',
          style: const TextStyle(
            fontSize: 8,
            color: AppColors.textTertiary,
            fontFamily: 'RethinkSans',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(cx + r + 2, cy - textPainter.height - 1),
      );
    }

    // Draw crosshair axes
    final crosshairPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(cx - halfExtent, cy),
      Offset(cx + halfExtent, cy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(cx, cy - halfExtent),
      Offset(cx, cy + halfExtent),
      crosshairPaint,
    );

    // Plot comparison data first (behind primary)
    if (compareData != null && compareData!.isNotEmpty) {
      _plotPoints(canvas, compareData!, color2, cx, cy, scale);
    }

    // Plot primary data
    if (data.isNotEmpty) {
      _plotPoints(canvas, data, color1, cx, cy, scale);
    }
  }

  void _plotPoints(
    Canvas canvas,
    List<GGPoint> points,
    Color color,
    double cx,
    double cy,
    double scale,
  ) {
    final dotPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    for (final p in points) {
      // X = lateral (right is positive), Y = longitudinal (up is braking)
      final x = cx + p.lateralG * scale;
      final y = cy - p.longitudinalG * scale; // invert Y axis
      canvas.drawCircle(Offset(x, y), 2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GGDiagramPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.compareData != compareData ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2;
  }
}
