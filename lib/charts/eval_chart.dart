import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/chess_models.dart';

/// Evaluation chart widget using fl_chart.
///
/// Displays a line chart showing evaluation over move number with:
/// - White area above zero (white advantage)
/// - Black/dark area below zero (black advantage)
/// - Classification-colored dots on each data point
/// - Touch interaction to see move details
/// - Current move indicator
/// - Smooth curve rendering
class EvalChart extends StatelessWidget {
  /// List of analyzed moves to plot.
  final List<AnalyzedMove> moves;

  /// Index of the currently selected move.
  final int currentMoveIndex;

  /// Whether to use dark theme.
  final bool isDark;

  /// Maximum eval value for the Y axis.
  final double maxEval;

  const EvalChart({
    super.key,
    required this.moves,
    required this.currentMoveIndex,
    this.isDark = true,
    this.maxEval = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) {
      return _buildEmptyChart();
    }

    final spots = _buildSpots();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: LineChart(
        LineChartData(
          gridData: _buildGridData(),
          titlesData: _buildTitlesData(),
          borderData: _buildBorderData(),
          minX: 0,
          maxX: (moves.length - 1).toDouble(),
          minY: -maxEval,
          maxY: maxEval,
          lineBarsData: [
            _buildMainLine(spots),
          ],
          lineTouchData: _buildTouchData(),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              // Zero line (center)
              HorizontalLine(
                y: 0,
                color: isDark ? Colors.white24 : Colors.black26,
                strokeWidth: 1,
                dashArray: [4, 4],
              ),
            ],
            // Current move vertical indicator
            verticalLines: currentMoveIndex >= 0 && currentMoveIndex < moves.length
                ? [
                    VerticalLine(
                      x: currentMoveIndex.toDouble(),
                      color: const Color(0xFFE94560).withOpacity(0.6),
                      strokeWidth: 1.5,
                      dashArray: [3, 3],
                    ),
                  ]
                : [],
          ),

        ),
      ),
    );
  }

  Widget _buildEmptyChart() {
    return Center(
      child: Text(
        'لا توجد بيانات بعد',
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontFamily: 'Tajawal',
        ),
      ),
    );
  }

  /// Build the FlSpot list from moves.
  List<FlSpot> _buildSpots() {
    return List.generate(moves.length, (index) {
      final eval = moves[index].evalScore ?? 0.0;
      final clamped = eval.clamp(-maxEval, maxEval);
      return FlSpot(index.toDouble(), clamped);
    });
  }

  /// Main evaluation line.
  LineChartBarData _buildMainLine(List<FlSpot> spots) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.35,
      preventCurveOverShooting: true,
      color: isDark ? const Color(0xFF5DADE2) : const Color(0xFF2C3E50),
      barWidth: 2,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) {
          if (index < 0 || index >= moves.length) {
            return _defaultDotPainter();
          }

          final classification = moves[index].classification;
          final isCurrentMove = index == currentMoveIndex;

          // Show classification-colored dots
          if (classification != null &&
              classification != MoveClassification.best &&
              classification != MoveClassification.good) {
            return _classificationDotPainter(classification, isCurrentMove);
          }

          // Current move indicator
          if (isCurrentMove) {
            return FlDotCirclePainter(
              radius: 5,
              color: const Color(0xFFE94560),
              strokeWidth: 2,
              strokeColor: Colors.white,
            );
          }

          // Default small dot
          return FlDotCirclePainter(
            radius: 2,
            color: isDark ? const Color(0xFF5DADE2) : const Color(0xFF2C3E50),
            strokeWidth: 0,
            strokeColor: Colors.transparent,
          );
        },
      ),
      // White advantage area (above zero)
      aboveBarData: BarAreaData(
        show: true,
        color: Colors.white.withOpacity(0.08),
        cutOffY: 0,
        applyCutOffY: true,
      ),
      // Black advantage area (below zero)
      belowBarData: BarAreaData(
        show: true,
        color: Colors.black.withOpacity(0.15),
        cutOffY: 0,
        applyCutOffY: true,
      ),
    );
  }

  FlDotPainter _defaultDotPainter() {
    return FlDotCirclePainter(
      radius: 2,
      color: isDark ? const Color(0xFF5DADE2) : const Color(0xFF2C3E50),
      strokeWidth: 0,
      strokeColor: Colors.transparent,
    );
  }

  FlDotPainter _classificationDotPainter(
    MoveClassification classification,
    bool isCurrentMove,
  ) {
    final color = _classificationColor(classification);
    final radius = isCurrentMove ? 6.0 : 4.0;

    return FlDotCirclePainter(
      radius: radius,
      color: color,
      strokeWidth: isCurrentMove ? 2.0 : 1.0,
      strokeColor: isCurrentMove ? Colors.white : color.withOpacity(0.6),
    );
  }

  Color _classificationColor(MoveClassification classification) {
    switch (classification) {
      case MoveClassification.brilliant:
        return const Color(0xFF26A69A);
      case MoveClassification.great:
        return const Color(0xFF66BB6A);
      case MoveClassification.best:
        return const Color(0xFF90CAF9);
      case MoveClassification.good:
        return const Color(0xFF64B5F6);
      case MoveClassification.inaccuracy:
        return const Color(0xFFFFB74D);
      case MoveClassification.mistake:
        return const Color(0xFFFF8A65);
      case MoveClassification.blunder:
        return const Color(0xFFE57373);
      case MoveClassification.book:
        return const Color(0xFFCE93D8);
    }
  }

  /// Grid configuration.
  FlGridData _buildGridData() {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: 5,
      getDrawingHorizontalLine: (value) {
        return FlLine(
          color: isDark ? Colors.white10 : Colors.black12,
          strokeWidth: 0.5,
        );
      },
    );
  }

  /// Axis titles configuration.
  FlTitlesData _buildTitlesData() {
    return FlTitlesData(
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      bottomTitles: AxisTitles(
        axisNameWidget: Text(
          'رقم الحركة',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 9,
            fontFamily: 'Tajawal',
          ),
        ),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 18,
          interval: _calculateBottomInterval(),
          getTitlesWidget: (value, meta) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${value.toInt() + 1}',
                style: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontSize: 8,
                  fontFamily: 'monospace',
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: Text(
          'التقييم',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 9,
            fontFamily: 'Tajawal',
          ),
        ),
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36,
          interval: 5,
          getTitlesWidget: (value, meta) {
            final display = value == 0
                ? '0'
                : value > 0
                    ? '+${value.toInt()}'
                    : '${value.toInt()}';
            return Text(
              display,
              style: TextStyle(
                color: value > 0
                    ? Colors.white70
                    : value < 0
                        ? Colors.white38
                        : (isDark ? Colors.white54 : Colors.black54),
                fontSize: 8,
                fontFamily: 'monospace',
              ),
            );
          },
        ),
      ),
    );
  }

  double _calculateBottomInterval() {
    if (moves.length <= 10) return 1;
    if (moves.length <= 20) return 2;
    if (moves.length <= 50) return 5;
    return 10;
  }

  /// Border configuration.
  FlBorderData _buildBorderData() {
    return FlBorderData(
      show: true,
      border: Border(
        bottom: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
        left: BorderSide(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 1,
        ),
        top: BorderSide.none,
        right: BorderSide.none,
      ),
    );
  }

  /// Touch interaction configuration.
  LineTouchData _buildTouchData() {
    return LineTouchData(
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (spot) => isDark
            ? const Color(0xFF16213E)
            : const Color(0xFF2C3E50),
        tooltipRoundedRadius: 8,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final index = spot.x.toInt();
            if (index < 0 || index >= moves.length) return null;

            final move = moves[index];
            final evalValue = move.evalScore ?? 0.0;
            final evalText = evalValue.abs() > 900
                ? (evalValue > 0
                    ? 'كش مات في ${(1000 - evalValue.toInt())}'
                    : 'كش مات في -${(1000 + evalValue.toInt())}')
                : '${evalValue > 0 ? '+' : ''}${evalValue.toStringAsFixed(1)}';

            final classificationText = move.classification != null
                ? ' ${_classificationArabic(move.classification!)}'
                : '';

            return LineTooltipItem(
              '${move.moveNumber}. ${move.san}\n'
              '$evalText$classificationText',
              TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w500,
              ),
            );
          }).toList();
        },
      ),
    );
  }

  String _classificationArabic(MoveClassification classification) {
    switch (classification) {
      case MoveClassification.brilliant:
        return '★★ ممتاز';
      case MoveClassification.great:
        return '★ رائع';
      case MoveClassification.best:
        return '! أفضل';
      case MoveClassification.good:
        return '✓ جيد';
      case MoveClassification.inaccuracy:
        return '?! عدم دقة';
      case MoveClassification.mistake:
        return '? خطأ';
      case MoveClassification.blunder:
        return '?? خطأ فادح';
      case MoveClassification.book:
        return '📖 كتاب';
    }
  }
}
