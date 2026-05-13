/// app_lifecycle_manager.dart
/// مدير دورة حياة التطبيق (إصلاح #12)
///
/// يحل مشكلة قتل Android للمحرك و Isolate أثناء الخلفية
/// بمراقبة دورة حياة التطبيق وإيقاف/استئناف المحرك تلقائياً.
///
/// التكامل مع خدمة الخلفية:
/// - عند الخلفية أثناء التحليل: تبدأ خدمة الخلفية (Foreground Service)
/// - عند العودة للمقدمة: تتوقف خدمة الخلفية
/// - هذا يضمن استمرارية التحليل في الخلفية على Android 13+

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/stockfish_engine.dart';
import '../engine/engine_isolate.dart';
import 'background_analysis_service.dart';

/// حالة دورة الحياة المُدارة
enum ManagedLifecycleState {
  /// التطبيق في المقدمة ومرئي
  foreground,

  /// التطبيق في الخلفية (غير مرئي)
  background,

  /// التطبيق غير نشط (مثل مكالمة واردة)
  inactive,

  /// التطبيق متوقف مؤقتاً
  paused,
}

/// مدير دورة حياة التطبيق — App Lifecycle Manager
///
/// يدير موارد المحرك بناءً على دورة حياة التطبيق:
/// - عند الخلفية: يوقف التحليل ويقلل استخدام الموارد
/// - عند العودة للمقدمة: يستأنف التحليل
/// - عند الإغلاق: يحرر الموارد
///
/// الاستخدام:
/// ```dart
/// // في main.dart أو في ويدجت الجذر:
/// final lifecycleManager = AppLifecycleManager(
///   engine: stockfishEngine,
/// );
///
/// // في StatefulWidget:
/// class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
///   late AppLifecycleManager _lifecycleManager;
///
///   @override
///   void initState() {
///     super.initState();
///     _lifecycleManager = AppLifecycleManager(engine: _engine);
///     WidgetsBinding.instance.addObserver(this);
///   }
///
///   @override
///   void didChangeAppLifecycleState(AppLifecycleState state) {
///     _lifecycleManager.handleLifecycleChange(state);
///   }
///
///   @override
///   void dispose() {
///     WidgetsBinding.instance.removeObserver(this);
///     _lifecycleManager.dispose();
///     super.dispose();
///   }
/// }
/// ```
class AppLifecycleManager with WidgetsBindingObserver {
  static const _tag = 'AppLifecycleManager';

  /// محرك Stockfish (اختياري — إذا لم يُستخدم EngineIsolate)
  StockfishEngine? _engine;

  /// Engine Isolate (اختياري — بديل عن المحرك المباشر)
  EngineIsolate? _engineIsolate;

  /// خدمة التحليل في الخلفية
  final BackgroundAnalysisService _backgroundService = BackgroundAnalysisService();

  /// حالة دورة الحياة الحالية
  ManagedLifecycleState _currentState = ManagedLifecycleState.foreground;

  /// هل كان المحرك يحلل قبل الدخول للخلفية؟
  bool _wasAnalyzingBeforeBackground = false;

  /// آخر FEN كان يُحلل
  String? _lastAnalyzedFen;

  /// Timer لإيقاف المحرك بعد تأخير (لا نوقفه فوراً عند الخلفية)
  Timer? _backgroundDelayTimer;

  /// التأخير قبل إيقاف المحرك عند الخلفية
  final Duration _backgroundStopDelay;

  /// هل تم تسجيل كمراقب؟
  bool _isObserver = false;

  // Callbacks

  /// يُستدعى عند الدخول للخلفية
  VoidCallback? onEnterBackground;

  /// يُستدعى عند العودة للمقدمة
  VoidCallback? onEnterForeground;

  AppLifecycleManager({
    StockfishEngine? engine,
    EngineIsolate? engineIsolate,
    Duration backgroundStopDelay = const Duration(seconds: 30),
  })  : _engine = engine,
        _engineIsolate = engineIsolate,
        _backgroundStopDelay = backgroundStopDelay {
    _registerObserver();
  }

  /// خدمة الخلفية — واجهة خارجية
  BackgroundAnalysisService get backgroundService => _backgroundService;

  /// حالة دورة الحياة الحالية
  ManagedLifecycleState get currentState => _currentState;

  /// هل التطبيق في المقدمة؟
  bool get isForeground => _currentState == ManagedLifecycleState.foreground;

  // ========================================================================
  // تسجيل المراقب
  // ========================================================================

  /// تسجيل كمراقب لدورة حياة التطبيق
  void _registerObserver() {
    if (!_isObserver) {
      WidgetsBinding.instance.addObserver(this);
      _isObserver = true;
    }
  }

  /// إلغاء تسجيل المراقب
  void _unregisterObserver() {
    if (_isObserver) {
      WidgetsBinding.instance.removeObserver(this);
      _isObserver = false;
    }
  }

  // ========================================================================
  // معالجة تغييرات دورة الحياة
  // ========================================================================

  /// معالجة تغيير حالة دورة الحياة
  void handleLifecycleChange(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleForeground();
        break;
      case AppLifecycleState.inactive:
        _handleInactive();
        break;
      case AppLifecycleState.paused:
        _handleBackground();
        break;
      case AppLifecycleState.detached:
        _handleDetached();
        break;
      case AppLifecycleState.hidden:
        // التطبيق مخفي لكن لا يزال يعمل
        break;
    }
  }

  /// معالجة WidgetsBindingObserver
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleLifecycleChange(state);
  }

  /// عند العودة للمقدمة
  void _handleForeground() {
    if (_currentState == ManagedLifecycleState.foreground) return;

    _currentState = ManagedLifecycleState.foreground;
    _backgroundDelayTimer?.cancel();
    _backgroundDelayTimer = null;

    debugPrint('$_tag: التطبيق في المقدمة');

    // إيقاف خدمة الخلفية
    _stopBackgroundService();

    // استئناف المحرك إذا كان يحلل قبل الخلفية
    if (_wasAnalyzingBeforeBackground) {
      _resumeEngine();
    }

    onEnterForeground?.call();
  }

  /// عند عدم النشاط
  void _handleInactive() {
    _currentState = ManagedLifecycleState.inactive;
    // لا نفعل شيئاً خاصاً — قد يعود للمقدمة قريباً
  }

  /// عند الدخول للخلفية
  void _handleBackground() {
    if (_currentState == ManagedLifecycleState.background) return;

    _currentState = ManagedLifecycleState.background;
    debugPrint('$_tag: التطبيق في الخلفية');

    // حفظ حالة المحرك
    _wasAnalyzingBeforeBackground =
        _engine?.isAnalyzing ?? false;

    // بدء خدمة الخلفية إذا كان المحرك يحلل
    if (_wasAnalyzingBeforeBackground) {
      _startBackgroundService();
    }

    // لا نوقف المحرك فوراً — ننتظر قليلاً
    // لأن المستخدم قد يعود بسرعة
    _backgroundDelayTimer?.cancel();
    _backgroundDelayTimer = Timer(_backgroundStopDelay, () {
      if (_currentState != ManagedLifecycleState.foreground) {
        _pauseEngine();
      }
    });

    onEnterBackground?.call();
  }

  /// عند الانفصال
  void _handleDetached() {
    _currentState = ManagedLifecycleState.paused;
    _pauseEngine();
  }

  // ========================================================================
  // إدارة المحرك
  // ========================================================================

  /// إيقاف المحرك مؤقتاً
  void _pauseEngine() {
    debugPrint('$_tag: إيقاف المحرك مؤقتاً');

    if (_engineIsolate != null) {
      _engineIsolate!.pause();
    } else if (_engine != null) {
      try {
        _engine!.stopAnalysisImmediate();
      } catch (_) {
        // المحرك قد يكون متوقفاً بالفعل
      }
    }
  }

  /// استئناف المحرك
  void _resumeEngine() {
    debugPrint('$_tag: استئناف المحرك');

    if (_engineIsolate != null) {
      _engineIsolate!.resume();
    }
    // للمحرك المباشر: لا نستأنف التحليل تلقائياً
    // نترك الـ provider يقرر متى يبدأ التحليل مجدداً
  }

  // ========================================================================
  // خدمة الخلفية — Background Service Integration
  // ========================================================================

  /// بدء خدمة التحليل في الخلفية
  Future<void> _startBackgroundService() async {
    try {
      final started = await _backgroundService.startAnalysis();
      if (started) {
        debugPrint('$_tag: بدأت خدمة التحليل في الخلفية');
      }
    } catch (e) {
      debugPrint('$_tag: فشل بدء خدمة الخلفية: $e');
    }
  }

  /// إيقاف خدمة التحليل في الخلفية
  Future<void> _stopBackgroundService() async {
    try {
      await _backgroundService.stopAnalysis();
      debugPrint('$_tag: أوقفت خدمة التحليل في الخلفية');
    } catch (e) {
      debugPrint('$_tag: فشل إيقاف خدمة الخلفية: $e');
    }
  }

  /// تحديث تقدم التحليل في الخلفية
  Future<void> updateBackgroundProgress({
    required int current,
    required int total,
    String currentMove = '',
  }) async {
    await _backgroundService.updateProgress(
      current: current,
      total: total,
      currentMove: currentMove,
    );
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  /// تحرير الموارد
  void dispose() {
    _backgroundDelayTimer?.cancel();
    _backgroundDelayTimer = null;
    _unregisterObserver();
    _wasAnalyzingBeforeBackground = false;
    _backgroundService.dispose();
  }
}
