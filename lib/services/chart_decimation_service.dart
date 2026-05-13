/// chart_decimation_service.dart
/// خدمة تنقيط الرسم البياني + عرض النطاق المرئي (حل مشكلة #6)
///
/// يحل مشكلة أداء الرسم البياني (Chart Performance) عندما:
/// - المباراة 250 move
/// - MultiPV history
///
/// قد يصبح chart ثقيل.
///
/// الحل:
/// - point decimation
/// - lazy rendering
/// - viewport rendering
/// - مثل التطبيقات الاحترافية

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/chess_models.dart';

// ============================================================================
/// نقطة مبسطة للرسم البياني — Decimated Chart Point
class DecimatedPoint {
  /// رقم الحركة (X axis)
  final double x;

  /// التقييم (Y axis)
  final double y;

  /// التصنيف (للون النقطة)
  final MoveClassification? classification;

  /// هل هذه نقطة أصلية أم مدمجة؟
  final bool isOriginal;

  /// عدد النقاط المدمجة (إذا isOriginal = false)
  final int mergedCount;

  const DecimatedPoint({
    required this.x,
    required this.y,
    this.classification,
    this.isOriginal = true,
    this.mergedCount = 1,
  });
}

// ============================================================================
/// خدمة تنقيط الرسم البياني — Chart Decimation Service
///
/// تُبسط البيانات للرسم البياني بـ:
/// 1. تقليل عدد النقاط (decimation)
/// 2. الحفاظ على الشكل العام للمنحنى
/// 3. عرض النقاط المهمة (التصنيفات الخاصة)
/// 4. عرض النطاق المرئي فقط (viewport)
///
/// الاستخدام:
/// ```dart
/// final service = ChartDecimationService();
///
/// // تحويل البيانات الكاملة إلى بيانات مبسطة
/// final decimated = service.decimate(
///   moves: analyzedMoves,
///   maxPoints: 100,
///   viewportStart: 0.0,
///   viewportEnd: 1.0,
/// );
///
/// // عرض النطاق المرئي فقط
/// final visible = service.getVisiblePoints(
///   decimated,
///   viewStart: 20.0,
///   viewEnd: 40.0,
/// );
/// ```
class ChartDecimationService {
  static const _tag = 'ChartDecimationService';

  // ========================================================================
  /// تنقيط البيانات — Decimate chart data
  ///
  /// يحول قائمة الحركات المحللة إلى نقاط مبسطة للرسم البياني.
  ///
  /// [moves] — قائمة الحركات المحللة
  /// [maxPoints] — الحد الأقصى للنقاط (الافتراضي: 150)
  /// [viewportStart] — بداية النطاق المرئي (0.0-1.0)
  /// [viewportEnd] — نهاية النطاق المرئي (0.0-1.0)
  /// [maxEval] — الحد الأقصى للتقييم
  List<DecimatedPoint> decimate({
    required List<AnalyzedMove> moves,
    int maxPoints = 150,
    double viewportStart = 0.0,
    double viewportEnd = 1.0,
    double maxEval = 10.0,
  }) {
    if (moves.isEmpty) return [];

    // الخطوة 1: تحديد النطاق المرئي
    final startIndex = (viewportStart * moves.length).floor();
    final endIndex = (viewportEnd * moves.length).ceil().clamp(0, moves.length);
    final visibleMoves = moves.sublist(startIndex, endIndex);

    if (visibleMoves.isEmpty) return [];

    // الخطوة 2: إذا كان عدد النقاط ضمن الحد، لا تنقيط
    if (visibleMoves.length <= maxPoints) {
      return _convertToPoints(visibleMoves, startIndex, maxEval);
    }

    // الخطوة 3: تنقيط ذكي
    return _smartDecimate(visibleMoves, startIndex, maxPoints, maxEval);
  }

  // ========================================================================
  /// تحويل الحركات إلى نقاط — Convert moves to points
  List<DecimatedPoint> _convertToPoints(
    List<AnalyzedMove> moves,
    int offset,
    double maxEval,
  ) {
    final points = <DecimatedPoint>[];

    // نقطة البداية (تقييم 0)
    points.add(const DecimatedPoint(x: 0, y: 0, isOriginal: true));

    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      final evalCp = move.evalAfter;
      final evalPawns = (evalCp / 100.0).clamp(-maxEval, maxEval);

      // الحفاظ على النقاط ذات التصنيفات الخاصة
      final isSpecial = move.classification == MoveClassification.brilliant ||
          move.classification == MoveClassification.blunder ||
          move.classification == MoveClassification.mistake;

      points.add(DecimatedPoint(
        x: (i + offset + 1).toDouble(),
        y: evalPawns,
        classification: isSpecial ? move.classification : null,
        isOriginal: true,
      ));
    }

    return points;
  }

  // ========================================================================
  /// تنقيط ذكي — Smart decimation
  ///
  /// يحافظ على:
  /// - النقاط الأولى والأخيرة
  /// - النقاط ذات التصنيفات الخاصة
  /// - القمم والوديان (peaks and valleys)
  /// - توزيع متساوٍ للنقاط المتبقية
  List<DecimatedPoint> _smartDecimate(
    List<AnalyzedMove> moves,
    int offset,
    int maxPoints,
    double maxEval,
  ) {
    final allPoints = _convertToPoints(moves, offset, maxEval);
    if (allPoints.length <= maxPoints) return allPoints;

    final selected = <DecimatedPoint>[];
    final selectedIndices = <int>{};

    // 1. دائماً نحتفظ بالنقطة الأولى والأخيرة
    selectedIndices.add(0);
    selectedIndices.add(allPoints.length - 1);

    // 2. نحتفظ بالنقاط ذات التصنيفات الخاصة
    for (int i = 0; i < allPoints.length; i++) {
      if (allPoints[i].classification != null) {
        selectedIndices.add(i);
      }
    }

    // 3. نحتفظ بالقمم والوديان (peaks and valleys)
    for (int i = 1; i < allPoints.length - 1; i++) {
      final prev = allPoints[i - 1].y;
      final curr = allPoints[i].y;
      final next = allPoints[i + 1].y;

      // قمة محلية
      if (curr > prev && curr > next) {
        selectedIndices.add(i);
      }
      // واد محلي
      if (curr < prev && curr < next) {
        selectedIndices.add(i);
      }
    }

    // 4. نقاط التغيير الكبير
    for (int i = 1; i < allPoints.length; i++) {
      final diff = (allPoints[i].y - allPoints[i - 1].y).abs();
      if (diff > 1.0) { // تغير أكثر من 1 بيدق
        selectedIndices.add(i);
        selectedIndices.add(i - 1);
      }
    }

    // 5. ملء الباقي بالتوزيع المتساوي
    final remainingBudget = maxPoints - selectedIndices.length;
    if (remainingBudget > 0) {
      final step = allPoints.length / remainingBudget;
      for (int j = 0; j < remainingBudget; j++) {
        final idx = (j * step).round().clamp(0, allPoints.length - 1);
        selectedIndices.add(idx);
      }
    }

    // 6. ترتيب وإزالة المكررات
    final sortedIndices = selectedIndices.toList()..sort();
    final uniqueIndices = <int>[];
    for (final idx in sortedIndices) {
      if (uniqueIndices.isEmpty || uniqueIndices.last != idx) {
        uniqueIndices.add(idx);
      }
    }

    // 7. بناء القائمة النهائية
    for (final idx in uniqueIndices) {
      selected.add(allPoints[idx]);
    }

    return selected;
  }

  // ========================================================================
  /// الحصول على النقاط المرئية فقط — Get visible points
  ///
  /// يُرجع فقط النقاط في النطاق المرئي الحالي.
  List<DecimatedPoint> getVisiblePoints(
    List<DecimatedPoint> points, {
    required double viewStart,
    required double viewEnd,
    int padding = 3,
  }) {
    if (points.isEmpty) return [];

    final visible = <DecimatedPoint>[];

    for (int i = 0; i < points.length; i++) {
      final x = points[i].x;
      if (x >= viewStart - padding && x <= viewEnd + padding) {
        visible.add(points[i]);
      }
    }

    return visible;
  }

  // ========================================================================
  /// حساب النطاق المرئي المثالي — Calculate optimal viewport
  ///
  /// يُرجع نطاقاً يُظهر أهم جزء من المباراة.
  ({double start, double end}) calculateOptimalViewport({
    required List<AnalyzedMove> moves,
    int currentMoveIndex = -1,
    double viewportWidth = 40.0,
  }) {
    if (moves.isEmpty) {
      return (start: 0.0, end: viewportWidth);
    }

    final currentX = currentMoveIndex >= 0 ? currentMoveIndex.toDouble() : 0.0;
    final totalMoves = moves.length.toDouble();

    // مركز النطاق على الحركة الحالية
    double start = currentX - viewportWidth / 2;
    double end = currentX + viewportWidth / 2;

    // تعديل الحدود
    if (start < 0) {
      end -= start;
      start = 0;
    }
    if (end > totalMoves) {
      start -= (end - totalMoves);
      end = totalMoves;
    }

    return (start: start.clamp(0.0, totalMoves), end: end.clamp(0.0, totalMoves));
  }
}
