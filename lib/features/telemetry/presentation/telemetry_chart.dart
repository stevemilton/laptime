import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';

/// A line chart that plots one or two data series using [CustomPainter].
///
/// Used in the lap comparison screen to visualise speed, g-force,
/// braking, and other telemetry channels over time/distance.
class TelemetryChart extends StatelessWidget {
  const TelemetryChart({
    super.key,
    required this.title,
    required this.data1,
    this.data2,
    required this.label1,
    this.label2,
    this.height = 200,
    this.yAxisLabel,
    this.color1 = AppColors.purple,
    this.color2 = AppColors.green,
  });

  /// Chart title displayed above the plot area.
  final String title;

  /// Primary data series.
  final List<double> data1;

  /// Optional comparison data series.
  final List<double>? data2;

  /// Legend label for the first series.
  final String label1;

  /// Legend label for the second series.
  final String? label2;

  /// Chart height in logical pixels.
  final double height;

  /// Optional Y-axis unit label (e.g. "km/h", "g").
  final String? yAxisLabel;

  /// Color for the primary data line.
  final Color color1;

  /// Color for the comparison data line.
  final Color color2;

  @override
  Widget build(BuildContext context) {
    final hasData = data1.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: AppTypography.labelLarge,
          ),
        ),

        // Chart area
        Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: hasData
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TelemetryChartPainter(
                      data1: data1,
                      data2: data2,
                      color1: color1,
                      color2: color2,
                      yAxisLabel: yAxisLabel,
                    ),
                  ),
                )
              : Center(
                  child: Text(
                    'No data available',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
        ),

        // Legend
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendDot(color: color1, label: label1),
              if (data2 != null && label2 != null) ...[
                const SizedBox(width: 16),
                _LegendDot(color: color2, label: label2!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Small colored dot + label for the chart legend.
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

class _TelemetryChartPainter extends CustomPainter {
  _TelemetryChartPainter({
    required this.data1,
    this.data2,
    required this.color1,
    required this.color2,
    this.yAxisLabel,
  });

  final List<double> data1;
  final List<double>? data2;
  final Color color1;
  final Color color2;
  final String? yAxisLabel;

  // Padding inside the chart area for axes
  static const double _leftPad = 40;
  static const double _rightPad = 12;
  static const double _topPad = 12;
  static const double _bottomPad = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _leftPad;
    final plotRight = size.width - _rightPad;
    final plotTop = _topPad;
    final plotBottom = size.height - _bottomPad;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    if (plotWidth <= 0 || plotHeight <= 0) return;

    // Compute global min/max across both series for consistent Y scale
    double yMin = double.infinity;
    double yMax = double.negativeInfinity;

    for (final v in data1) {
      if (v < yMin) yMin = v;
      if (v > yMax) yMax = v;
    }
    if (data2 != null) {
      for (final v in data2!) {
        if (v < yMin) yMin = v;
        if (v > yMax) yMax = v;
      }
    }

    // Add a small margin to min/max
    final range = yMax - yMin;
    if (range < 0.001) {
      yMin -= 1;
      yMax += 1;
    } else {
      yMin -= range * 0.05;
      yMax += range * 0.05;
    }

    // Draw grid lines
    _drawGrid(canvas, plotLeft, plotTop, plotRight, plotBottom, yMin, yMax);

    // Draw data lines
    _drawLine(canvas, data1, color1, plotLeft, plotTop, plotWidth, plotHeight,
        yMin, yMax);
    if (data2 != null && data2!.isNotEmpty) {
      _drawLine(canvas, data2!, color2, plotLeft, plotTop, plotWidth, plotHeight,
          yMin, yMax);
    }
  }

  void _drawGrid(Canvas canvas, double left, double top, double right,
      double bottom, double yMin, double yMax) {
    final gridPaint = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1;

    // Horizontal grid lines (5 lines)
    const gridLines = 5;
    for (var i = 0; i <= gridLines; i++) {
      final y = top + (bottom - top) * i / gridLines;
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);

      // Y-axis labels
      final value = yMax - (yMax - yMin) * i / gridLines;
      final textPainter = TextPainter(
        text: TextSpan(
          text: value.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.textTertiary,
            fontFamily: 'RethinkSans',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(left - textPainter.width - 4, y - textPainter.height / 2),
      );
    }

    // Axes border
    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, top), Offset(left, bottom), axisPaint);
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), axisPaint);
  }

  void _drawLine(
    Canvas canvas,
    List<double> data,
    Color color,
    double left,
    double top,
    double width,
    double height,
    double yMin,
    double yMax,
  ) {
    if (data.length < 2) return;

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    final yRange = yMax - yMin;

    for (var i = 0; i < data.length; i++) {
      final x = left + (i / (data.length - 1)) * width;
      final yNorm = yRange > 0 ? (data[i] - yMin) / yRange : 0.5;
      final y = top + height * (1 - yNorm);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TelemetryChartPainter oldDelegate) {
    return oldDelegate.data1 != data1 ||
        oldDelegate.data2 != data2 ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2;
  }
}
