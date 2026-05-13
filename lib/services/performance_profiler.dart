/// performance_profiler.dart
/// بنية تحسين الأداء (حل مشكلة #5 + #17)
///
/// يحل مشكلتين:
/// #5: Flutter Frame Budget — 16ms frame budget overflow
/// #17: GPU Overdraw — طبقات كثيرة تسبب overdraw/battery drain
///
/// الحل #5:
/// - Frame timing tracking
/// - Slow frame detection
/// - Performance profiling data collection
///
/// الحل #17:
/// - Reduce transparency where possible
/// - Eliminate unnecessary paints
/// - Alpha blending optimization

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// ============================================================================
/// تقرير إطار — Frame Report
class FrameReport {
  final int frameNumber;
  final Duration buildDuration;
  final Duration rasterDuration;
  final Duration totalDuration;
  final bool isSlowFrame;
  final DateTime timestamp;

  const FrameReport({
    required this.frameNumber,
    required this.buildDuration,
    required this.rasterDuration,
    required this.totalDuration,
    required this.isSlowFrame,
    required this.timestamp,
  });
}

// ============================================================================
/// مُحسّن الأداء — Performance Profiler
///
/// يراقب أداء التطبيق:
/// - تتبع إطارات الرسم (frame timing)
/// - كشف الإطارات البطيئة (slow frames > 16ms)
/// - إحصائيات الأداء
/// - توصيات للتحسين
///
/// الاستخدام:
/// ```dart
/// final profiler = PerformanceProfiler();
/// profiler.start();
///
/// // في أي مكان:
/// profiler.recordDroppedFrame();
///
/// // الحصول على الإحصائيات
/// final stats = profiler.stats;
///
/// profiler.dispose();
/// ```
class PerformanceProfiler {
  static const _tag = 'PerformanceProfiler';

  /// عتبة الإطار البطيء (16ms = 60fps)
  static const _slowFrameThreshold = Duration(milliseconds: 16);

  /// عتبة الإطار المتأخر جداً (32ms = 30fps)
  static const _verySlowFrameThreshold = Duration(milliseconds: 32);

  /// Timer المراقبة
  Timer? _monitorTimer;

  /// اشتراك في توقيت الإطارات
  void Function(TimingsCallback)? _timingsCallback;

  /// سجل الإطارات البطيئة
  final List<FrameReport> _slowFrames = [];

  /// الحد الأقصى لسجل الإطارات البطيئة
  static const _maxSlowFrames = 100;

  /// إجمالي الإطارات
  int _totalFrames = 0;

  /// عدد الإطارات البطيئة
  int _slowFrameCount = 0;

  /// عدد الإطارات المتأخرة جداً
  int _verySlowFrameCount = 0;

  /// إجمالي مدة البناء
  Duration _totalBuildTime = Duration.zero;

  /// إجمالي مدة التنقيط
  Duration _totalRasterTime = Duration.zero;

  /// عدد مرات رسم الشاشة (paint count)
  int _paintCount = 0;

  /// هل المراقبة فعالة؟
  bool _isRunning = false;

  // Callbacks

  /// يُستدعى عند كشف إطار بطيء
  void Function(FrameReport report)? onSlowFrame;

  /// يُستدعى عند كشف إطار متأخر جداً
  void Function(FrameReport report)? onVerySlowFrame;

  // Getters

  /// هل المراقبة فعالة؟
  bool get isRunning => _isRunning;

  /// إحصائيات الأداء
  Map<String, dynamic> get stats => {
    'totalFrames': _totalFrames,
    'slowFrameCount': _slowFrameCount,
    'verySlowFrameCount': _verySlowFrameCount,
    'slowFrameRate': _totalFrames > 0
        ? '${(_slowFrameCount / _totalFrames * 100).toStringAsFixed(1)}%'
        : '0%',
    'avgBuildTimeMs': _totalFrames > 0
        ? (_totalBuildTime.inMicroseconds / _totalFrames / 1000).toStringAsFixed(2)
        : '0',
    'avgRasterTimeMs': _totalFrames > 0
        ? (_totalRasterTime.inMicroseconds / _totalFrames / 1000).toStringAsFixed(2)
        : '0',
    'paintCount': _paintCount,
    'recentSlowFrames': _slowFrames.length,
  };

  // ========================================================================
  // بدء وإيقاف المراقبة
  // ========================================================================

  /// بدء المراقبة
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    // تتبع توقيت الإطارات
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);

    debugPrint('$_tag: بدأت مراقبة الأداء');
  }

  /// إيقاف المراقبة
  void stop() {
    if (!_isRunning) return;
    _isRunning = false;

    // إزالة callback
    try {
      SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    } catch (_) {}

    debugPrint('$_tag: توقفت مراقبة الأداء');
  }

  // ========================================================================
  // معالجة توقيت الإطارات
  // ========================================================================

  void _handleFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _totalFrames++;

      final buildDuration = timing.buildDuration;
      final rasterDuration = timing.rasterDuration;
      final totalDuration = timing.totalSpan;

      _totalBuildTime += buildDuration;
      _totalRasterTime += rasterDuration;

      // كشف الإطارات البطيئة
      if (totalDuration > _slowFrameThreshold) {
        _slowFrameCount++;

        final isVerySlow = totalDuration > _verySlowFrameThreshold;
        if (isVerySlow) {
          _verySlowFrameCount++;
        }

        final report = FrameReport(
          frameNumber: _totalFrames,
          buildDuration: buildDuration,
          rasterDuration: rasterDuration,
          totalDuration: totalDuration,
          isSlowFrame: true,
          timestamp: DateTime.now(),
        );

        _slowFrames.add(report);
        if (_slowFrames.length > _maxSlowFrames) {
          _slowFrames.removeAt(0);
        }

        if (isVerySlow) {
          onVerySlowFrame?.call(report);
          debugPrint(
            '$_tag: ⚠️ إطار متأخر جداً: ${totalDuration.inMilliseconds}ms '
            '(build: ${buildDuration.inMilliseconds}ms, raster: ${rasterDuration.inMilliseconds}ms)',
          );
        } else {
          onSlowFrame?.call(report);
        }
      }
    }
  }

  // ========================================================================
  // عداد الرسم — Paint Counter (لحل مشكلة #17)
  // ========================================================================

  /// تسجيل عملية رسم — يُستدعى من CustomPainter.shouldRepaint أو paint
  void recordPaint() {
    _paintCount++;
  }

  // ========================================================================
  // توصيات تحسين GPU Overdraw (حل مشكلة #17)
  // ========================================================================

  /// توصيات تقليل GPU Overdraw
  static List<String> getOverdrawRecommendations() {
    return [
      'استخدم Colors.opaque بدل Colors.transparent عندما ممكن',
      'تجنب BoxDecoration مع color شفاف + boxShadow',
      'استخدم RepaintBoundary لفصل الطبقات المتكررة التحديث',
      'قلل عدد الطبقات الشفافة (opacity layers)',
      'استخدم CustomPainter بدل Stack<Container> للوحات الشطرنج',
      'تجنب Opacity widget — استخدم AnimatedOpacity أو Color.withOpacity',
      'اجمع عدة عمليات رسم في paint واحدة بدل عدة CustomPainters',
    ];
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    stop();
    _slowFrames.clear();
    onSlowFrame = null;
    onVerySlowFrame = null;
  }
}

// ============================================================================
/// أدوات تحسين GPU — GPU Optimization Utilities (حل مشكلة #17)
///
/// توفر دوال مساعدة لتقليل GPU overdraw:
/// - ألوان معتمة بدل شفافة
/// - خلفيات بدون alpha blending
/// - حدود بدون transparency
class GpuOptimizations {
  /// لون معتم بديل — يستبدل الألوان الشفافة بألوان معتمة قريبة
  ///
  /// [color] — اللون الأصلي (قد يكون شفافاً)
  /// [background] — لون الخلفية (لدمج اللون الشفاف معها)
  /// يُرجع لوناً معتماً يعادل اللون الشفاف فوق الخلفية.
  static Color opaqueColor(Color color, Color background) {
    if (color.alpha == 255) return color;

    // Alpha compositing: result = src * alpha + dst * (1 - alpha)
    final alpha = color.alpha / 255.0;
    final invAlpha = 1.0 - alpha;

    return Color.fromARGB(
      255,
      (color.red * alpha + background.red * invAlpha).round().clamp(0, 255),
      (color.green * alpha + background.green * invAlpha).round().clamp(0, 255),
      (color.blue * alpha + background.blue * invAlpha).round().clamp(0, 255),
    );
  }

  /// إنشاء Paint بدون anti-aliasing (أسرع) — للعناصر الكبيرة
  static Paint fastPaint({Color color = const Color(0xFF000000)}) {
    return Paint()
      ..color = color
      ..isAntiAlias = false
      ..style = PaintingStyle.fill;
  }

  /// إنشاء Paint مع anti-aliasing للعناصر المهمة (قطع الشطرنج)
  static Paint qualityPaint({Color color = const Color(0xFF000000)}) {
    return Paint()
      ..color = color
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;
  }

  /// إنشاء خط بدون anti-aliasing (أسرع للأسهم الكبيرة)
  static Paint fastStroke({
    Color color = const Color(0xFF000000),
    double width = 2.0,
  }) {
    return Paint()
      ..color = color
      ..isAntiAlias = false
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
  }
}
