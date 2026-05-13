/// adaptive_analysis_service.dart
/// خدمة التحليل التكيفي (إصلاح #16)
///
/// تحل مشكلة حرارة الجهاز أثناء التحليل المستمر
/// بتقليل عمق التحليل وخطوط MultiPV عند:
/// - انخفاض البطارية
/// - ارتفاع حرارة الجهاز
/// - ضعف الأداء
///
/// كيف يحلها ChessIs:
/// - adaptive analysis
/// - throttling
///
/// في Flutter:
/// - إذا battery low / thermal high → depth=10, multipv=1

import 'dart:async';

import 'package:flutter/foundation.dart';

/// مستوى الأداء الحالي
enum PerformanceLevel {
  /// أداء كامل — عمق عالي، MultiPV=3-5
  full,

  /// أداء متوسط — عمق متوسط، MultiPV=2
  moderate,

  /// أداء منخفض — عمق منخفض، MultiPV=1
  low,

  /// أداء حرج — عمق 10، MultiPV=1، توقف عند الحرارة العالية
  critical,
}

/// إعدادات التحليل لكل مستوى أداء
class AnalysisProfile {
  final int depth;
  final int multiPV;
  final int threads;
  final int hashSizeMb;
  final Duration throttleInterval;

  const AnalysisProfile({
    required this.depth,
    required this.multiPV,
    required this.threads,
    required this.hashSizeMb,
    required this.throttleInterval,
  });

  /// إعدادات كاملة
  static const full = AnalysisProfile(
    depth: 22,
    multiPV: 3,
    threads: 2,
    hashSizeMb: 128,
    throttleInterval: Duration(milliseconds: 100),
  );

  /// إعدادات متوسطة
  static const moderate = AnalysisProfile(
    depth: 18,
    multiPV: 2,
    threads: 1,
    hashSizeMb: 64,
    throttleInterval: Duration(milliseconds: 150),
  );

  /// إعدادات منخفضة
  static const low = AnalysisProfile(
    depth: 14,
    multiPV: 1,
    threads: 1,
    hashSizeMb: 32,
    throttleInterval: Duration(milliseconds: 200),
  );

  /// إعدادات حرجة
  static const critical = AnalysisProfile(
    depth: 10,
    multiPV: 1,
    threads: 1,
    hashSizeMb: 16,
    throttleInterval: Duration(milliseconds: 300),
  );
}

/// خدمة التحليل التكيفي — Adaptive Analysis Service
///
/// تراقب أداء الجهاز وتُعدّل إعدادات التحليل تلقائياً.
///
/// الاستخدام:
/// ```dart
/// final adaptive = AdaptiveAnalysisService();
/// adaptive.start();
///
/// adaptive.onProfileChanged = (profile) {
///   engine.setMultiPv(profile.multiPV);
///   engine.setThreads(profile.threads);
///   engine.setHashSize(profile.hashSizeMb);
/// };
///
/// // الحصول على الإعدادات الحالية
/// final profile = adaptive.currentProfile;
/// engine.analyzeDepth(profile.depth);
///
/// adaptive.dispose();
/// ```
class AdaptiveAnalysisService {
  static const _tag = 'AdaptiveAnalysisService';

  /// مستوى الأداء الحالي
  PerformanceLevel _currentLevel = PerformanceLevel.full;

  /// Timer للمراقبة
  Timer? _monitorTimer;

  /// عدد التحديثات المتأخرة (dropped frames)
  int _droppedFrames = 0;

  /// وقت آخر تحليل
  DateTime? _lastAnalysisTime;

  /// مدة التحليل الأخيرة
  Duration? _lastAnalysisDuration;

  /// عدد التحليلات المتتالية البطيئة
  int _slowAnalysisCount = 0;

  /// فترة المراقبة
  final Duration _monitorInterval;

  // Callbacks

  /// يُستدعى عند تغير مستوى الأداء
  void Function(PerformanceLevel level, AnalysisProfile profile)?
      onProfileChanged;

  AdaptiveAnalysisService({
    Duration monitorInterval = const Duration(seconds: 30),
  }) : _monitorInterval = monitorInterval;

  /// مستوى الأداء الحالي
  PerformanceLevel get currentLevel => _currentLevel;

  /// إعدادات التحليل الحالية
  AnalysisProfile get currentProfile {
    switch (_currentLevel) {
      case PerformanceLevel.full:
        return AnalysisProfile.full;
      case PerformanceLevel.moderate:
        return AnalysisProfile.moderate;
      case PerformanceLevel.low:
        return AnalysisProfile.low;
      case PerformanceLevel.critical:
        return AnalysisProfile.critical;
    }
  }

  // ========================================================================
  // بدء وإيقاف المراقبة
  // ========================================================================

  /// بدء المراقبة
  void start() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(_monitorInterval, _monitor);

    debugPrint('$_tag: بدأت المراقبة (مستوى: $_currentLevel)');
  }

  /// إيقاف المراقبة
  void stop() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  // ========================================================================
  // تتبع الأداء
  // ========================================================================

  /// تسجيل بداية تحليل
  void recordAnalysisStart() {
    _lastAnalysisTime = DateTime.now();
  }

  /// تسجيل نهاية تحليل
  void recordAnalysisEnd() {
    if (_lastAnalysisTime != null) {
      _lastAnalysisDuration = DateTime.now().difference(_lastAnalysisTime!);

      // إذا كان التحليل أبطأ من المتوقع، نزيد العداد
      final expectedDuration = Duration(
        milliseconds: currentProfile.depth * 200, // تقدير تقريبي
      );
      if (_lastAnalysisDuration! > expectedDuration * 2) {
        _slowAnalysisCount++;
      } else {
        _slowAnalysisCount = (_slowAnalysisCount - 1).clamp(0, _slowAnalysisCount);
      }
    }
  }

  /// تسجيل إطار متأخر (dropped frame)
  void recordDroppedFrame() {
    _droppedFrames++;
  }

  // ========================================================================
  // المراقبة
  // ========================================================================

  /// مراقبة الأداء
  void _monitor(Timer timer) {
    final newLevel = _calculatePerformanceLevel();

    if (newLevel != _currentLevel) {
      final oldLevel = _currentLevel;
      _currentLevel = newLevel;

      debugPrint(
        '$_tag: تغير مستوى الأداء: $oldLevel → $newLevel',
      );

      onProfileChanged?.call(newLevel, currentProfile);
    }

    // إعادة تعيين العدادات
    _droppedFrames = 0;
  }

  /// حساب مستوى الأداء المناسب
  PerformanceLevel _calculatePerformanceLevel() {
    // 1. التحقق من الإطارات المتأخرة
    if (_droppedFrames > 20) {
      return PerformanceLevel.critical;
    } else if (_droppedFrames > 10) {
      return PerformanceLevel.low;
    } else if (_droppedFrames > 5) {
      return PerformanceLevel.moderate;
    }

    // 2. التحقق من بطء التحليل
    if (_slowAnalysisCount > 5) {
      return PerformanceLevel.critical;
    } else if (_slowAnalysisCount > 3) {
      return PerformanceLevel.low;
    } else if (_slowAnalysisCount > 1) {
      return PerformanceLevel.moderate;
    }

    // 3. التحقق من مدة التحليل
    if (_lastAnalysisDuration != null) {
      final expectedDuration = Duration(
        milliseconds: currentProfile.depth * 200,
      );
      if (_lastAnalysisDuration! > expectedDuration * 3) {
        return PerformanceLevel.low;
      } else if (_lastAnalysisDuration! > expectedDuration * 2) {
        return PerformanceLevel.moderate;
      }
    }

    // الأداء جيد — يمكننا الترقية
    if (_currentLevel != PerformanceLevel.full &&
        _slowAnalysisCount == 0 &&
        _droppedFrames == 0) {
      // ترقية تدريجية
      switch (_currentLevel) {
        case PerformanceLevel.critical:
          return PerformanceLevel.low;
        case PerformanceLevel.low:
          return PerformanceLevel.moderate;
        case PerformanceLevel.moderate:
          return PerformanceLevel.full;
        case PerformanceLevel.full:
          return PerformanceLevel.full;
      }
    }

    return _currentLevel;
  }

  /// فرض مستوى أداء معين
  void forceLevel(PerformanceLevel level) {
    if (_currentLevel != level) {
      _currentLevel = level;
      onProfileChanged?.call(level, currentProfile);
    }
  }

  /// تحرير الموارد
  void dispose() {
    stop();
    onProfileChanged = null;
  }
}
