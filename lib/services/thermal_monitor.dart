/// thermal_monitor.dart
/// مراقب الحرارة والأداء الحقيقي (حل مشكلة #7)
///
/// يحل مشكلة Thermal Throttling الحقيقي:
/// - بعض الأجهزة تخفض CPU فجأة
/// - تقتل الأداء
///
/// الحل:
/// - قراءة thermal APIs عبر Platform Channel
/// - performance class من Android API
/// - battery stats حقيقية من BatteryManager
/// - وليس فقط battery level
///
/// التكامل مع المنصة:
/// - يستخدم [PlatformThermalService] لقراءة بيانات حقيقية
/// - يدعم Android PowerManager.THERMAL_STATUS_API (API 29+)
/// - يدعم Android Performance Class API (API 31+)
/// - يرجع للتقدير على المنصات غير المدعومة

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'platform_thermal_service.dart';

// ============================================================================
/// حالة الحرارة — Thermal State
enum ThermalState {
  /// طبيعي — لا قيود
  normal,

  /// دافئ — تقليل طفيف
  warm,

  /// ساخن — تقليل متوسط
  hot,

  /// حرج — تقليل شديد أو إيقاف
  critical,
}

// ============================================================================
/// فئة أداء الجهاز — Device Performance Class
enum DevicePerformanceClass {
  /// جهاز منخفض الأداء (RAM < 2GB, CPU ضعيف)
  low,

  /// جهاز متوسط الأداء
  medium,

  /// جهاز عالي الأداء (flagship)
  high,

  /// غير معروف
  unknown,
}

// ============================================================================
/// معلومات طاقة البطارية — Battery Info
class BatteryInfo {
  final int level; // 0-100
  final bool isCharging;
  final bool isPowerSave;
  final double? temperature; // درجة الحرارة بالدرجات المئوية

  const BatteryInfo({
    required this.level,
    this.isCharging = false,
    this.isPowerSave = false,
    this.temperature,
  });

  /// هل البطارية منخفضة؟
  bool get isLow => level < 20;

  /// هل البطارية حرجة؟
  bool get isCritical => level < 10;
}

// ============================================================================
/// تقرير الحالة الحرارية — Thermal Report
class ThermalReport {
  final ThermalState thermalState;
  final DevicePerformanceClass performanceClass;
  final BatteryInfo batteryInfo;
  final int droppedFramesLastMinute;
  final Duration averageAnalysisTime;
  final DateTime timestamp;

  /// هل البيانات من المنصة (حقيقية) أم مُقدّرة؟
  final bool isFromPlatform;

  const ThermalReport({
    required this.thermalState,
    required this.performanceClass,
    required this.batteryInfo,
    this.droppedFramesLastMinute = 0,
    this.averageAnalysisTime = Duration.zero,
    this.isFromPlatform = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// الوضع الموصى به للتحليل
  ThermalRecommendation get recommendation {
    if (thermalState == ThermalState.critical || batteryInfo.isCritical) {
      return ThermalRecommendation.pauseAnalysis;
    }

    if (thermalState == ThermalState.hot ||
        (batteryInfo.isLow && !batteryInfo.isCharging) ||
        droppedFramesLastMinute > 15) {
      return ThermalRecommendation.reduceAnalysis;
    }

    if (thermalState == ThermalState.warm ||
        droppedFramesLastMinute > 8 ||
        performanceClass == DevicePerformanceClass.low) {
      return ThermalRecommendation.moderateAnalysis;
    }

    return ThermalRecommendation.fullAnalysis;
  }
}

// ============================================================================
/// توصية حرارية — Thermal Recommendation
enum ThermalRecommendation {
  /// تحليل كامل
  fullAnalysis,

  /// تحليل متوسط
  moderateAnalysis,

  /// تحليل مخفض
  reduceAnalysis,

  /// إيقاف التحليل
  pauseAnalysis,
}

// ============================================================================
/// مراقب الحرارة — Thermal Monitor
///
/// يراقب:
/// 1. حالة حرارة الجهاز (عبر Platform Channel)
/// 2. فئة أداء الجهاز (Android Performance Class API)
/// 3. حالة البطارية (BatteryManager)
/// 4. الإطارات المتأخرة
/// 5. مدة التحليل
///
/// ويُصدر توصيات لضبط إعدادات التحليل.
///
/// عند توفر بيانات المنصة (Android)، يستخدم:
/// - PowerManager.getThermalStatus() (API 29+)
/// - BatteryManager للحصول على درجة الحرارة
/// - ActivityManager.getPerformanceClass() (API 31+)
///
/// عند عدم التوفر، يرجع للتقدير بناءً على المؤشرات غير المباشرة.
///
/// الاستخدام:
/// ```dart
/// final monitor = ThermalMonitor();
/// monitor.start();
///
/// monitor.onRecommendationChanged = (recommendation, report) {
///   switch (recommendation) {
///     case ThermalRecommendation.fullAnalysis:
///       engine.setMultiPv(3);
///       break;
///     case ThermalRecommendation.reduceAnalysis:
///       engine.setMultiPv(1);
///       break;
///     case ThermalRecommendation.pauseAnalysis:
///       engine.stopAnalysisImmediate();
///       break;
///   }
/// };
///
/// monitor.dispose();
/// ```
class ThermalMonitor {
  static const _tag = 'ThermalMonitor';

  /// Timer المراقبة
  Timer? _monitorTimer;

  /// فترة المراقبة
  final Duration _monitorInterval;

  /// خدمة قراءة بيانات المنصة
  final PlatformThermalService _platformService;

  /// حالة الحرارة الحالية
  ThermalState _thermalState = ThermalState.normal;

  /// فئة أداء الجهاز
  DevicePerformanceClass _performanceClass = DevicePerformanceClass.unknown;

  /// معلومات البطارية
  BatteryInfo _batteryInfo = const BatteryInfo(level: 100);

  /// الإطارات المتأخرة في الدقيقة الأخيرة
  int _droppedFramesLastMinute = 0;

  /// سجل الإطارات المتأخرة
  final List<DateTime> _droppedFrameTimestamps = [];

  /// سجل مدة التحليل
  final List<Duration> _analysisTimes = [];

  /// التوصية الحالية
  ThermalRecommendation _currentRecommendation = ThermalRecommendation.fullAnalysis;

  /// هل نعمل على Android؟
  bool _isAndroid = false;

  /// هل آخر قراءة كانت من المنصة؟
  bool _lastReadFromPlatform = false;

  // Callbacks

  /// يُستدعى عند تغير التوصية
  void Function(ThermalRecommendation recommendation, ThermalReport report)?
      onRecommendationChanged;

  /// يُستدعى عند تغير حالة الحرارة
  void Function(ThermalState state)? onThermalStateChanged;

  ThermalMonitor({
    Duration monitorInterval = const Duration(seconds: 15),
    PlatformThermalService? platformService,
  })  : _monitorInterval = monitorInterval,
        _platformService = platformService ?? PlatformThermalService() {
    _detectPlatform();
    _detectPerformanceClass();
  }

  // Getters

  ThermalState get thermalState => _thermalState;
  DevicePerformanceClass get performanceClass => _performanceClass;
  BatteryInfo get batteryInfo => _batteryInfo;
  ThermalRecommendation get currentRecommendation => _currentRecommendation;
  ThermalReport get currentReport => ThermalReport(
    thermalState: _thermalState,
    performanceClass: _performanceClass,
    batteryInfo: _batteryInfo,
    droppedFramesLastMinute: _droppedFramesLastMinute,
    averageAnalysisTime: _averageAnalysisTime,
    isFromPlatform: _lastReadFromPlatform,
  );

  /// هل المنصة تدعم قراءة بيانات حقيقية؟
  bool get isPlatformSupported => _platformService.isPlatformSupported;

  /// تقرير نصي للعرض في واجهة المستخدم
  String get statusText {
    final stateNames = {
      ThermalState.normal: 'طبيعي',
      ThermalState.warm: 'دافئ',
      ThermalState.hot: 'ساخن',
      ThermalState.critical: 'حرج',
    };
    final recNames = {
      ThermalRecommendation.fullAnalysis: 'تحليل كامل',
      ThermalRecommendation.moderateAnalysis: 'تحليل متوسط',
      ThermalRecommendation.reduceAnalysis: 'تحليل مخفض',
      ThermalRecommendation.pauseAnalysis: 'إيقاف التحليل',
    };
    final source = _lastReadFromPlatform ? 'المنصة' : 'تقدير';
    return '${stateNames[_thermalState]} • ${recNames[_currentRecommendation]} ($source)';
  }

  Duration get _averageAnalysisTime {
    if (_analysisTimes.isEmpty) return Duration.zero;
    final total = _analysisTimes.reduce((a, b) => a + b);
    return Duration(milliseconds: total.inMilliseconds ~/ _analysisTimes.length);
  }

  // ========================================================================
  // بدء وإيقاف المراقبة
  // ========================================================================

  /// بدء المراقبة
  void start() {
    _monitorTimer?.cancel();
    _monitorTimer = Timer.periodic(_monitorInterval, _monitor);

    // قراءة فورية عند البدء
    _fetchPlatformData();

    debugPrint('$_tag: بدأت المراقبة الحرارية (منصة مدعومة: $isPlatformSupported)');
  }

  /// إيقاف المراقبة
  void stop() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  // ========================================================================
  // كشف المنصة والأداء
  // ========================================================================

  void _detectPlatform() {
    try {
      _isAndroid = defaultTargetPlatform == TargetPlatform.android;
    } catch (_) {
      _isAndroid = false;
    }
  }

  void _detectPerformanceClass() {
    // محاولة قراءة فئة الأداء من المنصة
    if (_platformService.isPlatformSupported) {
      _fetchPerformanceClass();
    } else {
      // تقدير أساسي على المنصات غير المدعومة
      _performanceClass = DevicePerformanceClass.unknown;
      debugPrint('$_tag: فئة الأداء: ${_performanceClass.name} (تقدير)');
    }
  }

  /// قراءة فئة الأداء من المنصة
  Future<void> _fetchPerformanceClass() async {
    try {
      final data = await _platformService.getThermalData();
      if (data.isSupported) {
        _performanceClass = data.toPerformanceClass();
        debugPrint('$_tag: فئة الأداء: ${_performanceClass.name} (من المنصة)');
      }
    } catch (e) {
      debugPrint('$_tag: فشل قراءة فئة الأداء: $e');
    }
  }

  // ========================================================================
  // قراءة بيانات المنصة
  // ========================================================================

  /// قراءة بيانات الحرارة والبطارية من المنصة
  Future<void> _fetchPlatformData() async {
    if (!_platformService.isPlatformSupported) {
      _lastReadFromPlatform = false;
      return;
    }

    try {
      final data = await _platformService.getThermalData();

      if (data.isSupported) {
        // تحديث بيانات البطارية من المنصة
        _batteryInfo = data.toBatteryInfo();
        _lastReadFromPlatform = true;

        // تحديث فئة الأداء إن توفرت
        if (data.performanceClass != null) {
          _performanceClass = data.toPerformanceClass();
        }

        // تحديث الحالة الحرارية من PowerManager إن توفر
        if (data.thermalStatus != null) {
          final platformThermal = data.toThermalState();
          if (platformThermal != _thermalState) {
            final oldState = _thermalState;
            _thermalState = platformThermal;
            debugPrint('$_tag: تغيرت حالة الحرارة: $oldState → $platformThermal (من المنصة)');
            onThermalStateChanged?.call(platformThermal);
          }
        }

        debugPrint(
          '$_tag: بيانات المنصة — بطارية: ${data.batteryLevel}%, '
          'شحن: ${data.isCharging}, حرارة: ${data.batteryTemperature?.toStringAsFixed(1) ?? "N/A"}°C, '
          'حالة حرارة: ${data.thermalStatus}, فئة: ${data.performanceClass}',
        );
      } else {
        _lastReadFromPlatform = false;
      }
    } catch (e) {
      debugPrint('$_tag: فشل قراءة بيانات المنصة: $e');
      _lastReadFromPlatform = false;
    }
  }

  // ========================================================================
  // تحديث الحالة
  // ========================================================================

  /// تحديث معلومات البطارية — يُستدعى من الخارج
  void updateBatteryInfo(BatteryInfo info) {
    _batteryInfo = info;
    _checkAndEmitRecommendation();
  }

  /// تسجيل إطار متأخر
  void recordDroppedFrame() {
    _droppedFrameTimestamps.add(DateTime.now());
  }

  /// تسجيل مدة تحليل
  void recordAnalysisTime(Duration duration) {
    _analysisTimes.add(duration);
    // الاحتفاظ بآخر 20 فقط
    if (_analysisTimes.length > 20) {
      _analysisTimes.removeAt(0);
    }
  }

  // ========================================================================
  // المراقبة الدورية
  // ========================================================================

  void _monitor(Timer timer) {
    // تحديث الإطارات المتأخرة في الدقيقة الأخيرة
    _updateDroppedFrames();

    // قراءة بيانات المنصة أولاً (غير محظور - async)
    _fetchPlatformData().then((_) {
      // إذا لم تتوفر بيانات المنصة، نحسب من المؤشرات غير المباشرة
      if (!_lastReadFromPlatform) {
        _calculateThermalState();
      }

      // التحقق من التوصية
      _checkAndEmitRecommendation();
    });
  }

  void _updateDroppedFrames() {
    final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
    _droppedFrameTimestamps.removeWhere((t) => t.isBefore(oneMinuteAgo));
    _droppedFramesLastMinute = _droppedFrameTimestamps.length;
  }

  void _calculateThermalState() {
    // تقدير الحالة الحرارية بناءً على المؤشرات غير المباشرة:
    // 1. درجة حرارة البطارية (إن توفرت)
    // 2. عدد الإطارات المتأخرة
    // 3. مدة التحليل

    ThermalState newState = ThermalState.normal;

    // مؤشر 1: درجة حرارة البطارية
    if (_batteryInfo.temperature != null) {
      final temp = _batteryInfo.temperature!;
      if (temp > 42) {
        newState = ThermalState.critical;
      } else if (temp > 39) {
        newState = ThermalState.hot;
      } else if (temp > 36) {
        newState = ThermalState.warm;
      }
    }

    // مؤشر 2: الإطارات المتأخرة (مؤشر غير مباشر)
    if (_droppedFramesLastMinute > 30) {
      newState = _worseState(newState, ThermalState.critical);
    } else if (_droppedFramesLastMinute > 15) {
      newState = _worseState(newState, ThermalState.hot);
    } else if (_droppedFramesLastMinute > 8) {
      newState = _worseState(newState, ThermalState.warm);
    }

    // مؤشر 3: بطء التحليل
    if (_analysisTimes.length >= 5) {
      final avgTime = _averageAnalysisTime;
      if (avgTime.inSeconds > 30) {
        newState = _worseState(newState, ThermalState.hot);
      } else if (avgTime.inSeconds > 15) {
        newState = _worseState(newState, ThermalState.warm);
      }
    }

    // تحديث الحالة
    if (newState != _thermalState) {
      final oldState = _thermalState;
      _thermalState = newState;
      debugPrint('$_tag: تغيرت حالة الحرارة: $oldState → $newState (تقدير)');
      onThermalStateChanged?.call(newState);
    }
  }

  ThermalState _worseState(ThermalState a, ThermalState b) {
    return a.index > b.index ? a : b;
  }

  void _checkAndEmitRecommendation() {
    final report = currentReport;
    final newRecommendation = report.recommendation;

    if (newRecommendation != _currentRecommendation) {
      final oldRec = _currentRecommendation;
      _currentRecommendation = newRecommendation;

      debugPrint(
        '$_tag: تغيرت التوصية: $oldRec → $newRecommendation '
        '${_lastReadFromPlatform ? "(من المنصة)" : "(تقدير)"}',
      );

      onRecommendationChanged?.call(newRecommendation, report);
    }
  }

  // ========================================================================
  /// فرض حالة حرارة (للاختبار)
  void forceThermalState(ThermalState state) {
    _thermalState = state;
    _lastReadFromPlatform = false;
    _checkAndEmitRecommendation();
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    stop();
    _droppedFrameTimestamps.clear();
    _analysisTimes.clear();
    onRecommendationChanged = null;
    onThermalStateChanged = null;
  }
}
