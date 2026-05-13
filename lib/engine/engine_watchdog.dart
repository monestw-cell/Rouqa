/// engine_watchdog.dart
/// مراقب المحرك مع إعادة تشغيل تلقائية + وضع متدهور آمن (حل مشكلة #8)
///
/// يحل مشكلة انهيار المحرك أو تجمده أو انتهاء المهلة:
/// - restart storm إذا binary غير متوافق
///
/// الحل:
/// - max restart attempts
/// - ثم safe degraded mode
/// - لا restart storm
/// - exponential backoff

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'stockfish_engine.dart';
import 'uci_protocol.dart';

/// حالة المراقب
enum WatchdogState {
  /// المراقب يعمل بشكل طبيعي
  active,

  /// المراقب ينتظر استجابة المحرك
  waiting,

  /// المحرك لا يستجيب - جاري إعادة التشغيل
  restarting,

  /// الوضع المتدهور — المحرك لا يعمل
  degraded,

  /// المراقب متوقف
  stopped,
}

/// مستوى التدهور — Degradation Level
enum DegradationLevel {
  /// لا تدهور — المحرك يعمل بشكل كامل
  none,

  /// تدهور طفيف — إعدادات مخفضة
  minor,

  /// تدهور متوسط — تحليل محدود
  moderate,

  /// تدهور شديد — محرك غير متاح
  severe,
}

/// مراقب المحرك — Engine Watchdog (مُحسّن)
///
/// يراقب استجابات محرك Stockfish ويُعيد تشغيله تلقائياً
/// مع حماية ضد restart storm.
///
/// الميزات المضافة:
/// 1. Exponential backoff — تأخير متزايد بين محاولات إعادة التشغيل
/// 2. Safe degraded mode — وضع آمن عند تجاوز الحد الأقصى
/// 3. Circuit breaker — منع restart storm
/// 4. مراقبة ناجحة مستمرة — إعادة تعيين العداد تدريجياً
class EngineWatchdog {
  static const _tag = 'EngineWatchdog';

  /// المحرك المراقَب
  final StockfishEngine _engine;

  /// المهلة قبل اعتبار المحرك متوقفاً
  final Duration _timeout;

  /// الحد الأقصى لعدد إعادة التشغيل
  final int _maxRestarts;

  /// الفترة الأساسية بين محاولات إعادة التشغيل (قبل exponential backoff)
  final Duration _baseRestartCooldown;

  /// الحد الأقصى لفترة التبريد (لـ exponential backoff)
  final Duration _maxRestartCooldown;

  /// Timer المراقب
  Timer? _watchdogTimer;

  /// وقت آخر استجابة
  DateTime? _lastActivity;

  /// عدد مرات إعادة التشغيل
  int _restartCount = 0;

  /// حالة المراقب
  WatchdogState _state = WatchdogState.stopped;

  /// مستوى التدهور
  DegradationLevel _degradationLevel = DegradationLevel.none;

  /// هل نحن في مرحلة إعادة تشغيل؟
  bool _isRestarting = false;

  /// اشتراك في استجابات المحرك
  StreamSubscription<UciResponse>? _responseSubscription;

  /// وقت آخر نجاح مستمر (لإعادة تعيين العداد)
  DateTime? _lastStablePeriod;

  /// مدة النجاح المستمر المطلوبة لإعادة تعيين العداد
  final Duration _stablePeriodRequired;

  /// سجل أوقات الفشل (لـ circuit breaker)
  final List<DateTime> _failureTimestamps = [];

  /// نافذة الزمن لعد الفشل (لـ circuit breaker)
  final Duration _failureWindow;

  /// الحد الأقصى للفشل في النافذة
  final int _maxFailuresInWindow;

  // Callbacks

  /// يُستدعى عند إعادة تشغيل المحرك
  void Function(int restartCount, Duration cooldown)? onRestart;

  /// يُستدعى عند تجاوز الحد الأقصى لإعادة التشغيل
  void Function(int restartCount)? onMaxRestartsReached;

  /// يُستدعى عند تغير حالة المراقب
  void Function(WatchdogState state)? onStateChanged;

  /// يُستدعى عند الدخول في وضع متدهور
  void Function(DegradationLevel level)? onDegraded;

  /// يُستدعى عند نجاح إعادة التشغيل
  void Function()? onRecoverySuccessful;

  // Getters

  /// عدد مرات إعادة التشغيل
  int get restartCount => _restartCount;

  /// حالة المراقب
  WatchdogState get state => _state;

  /// مستوى التدهور
  DegradationLevel get degradationLevel => _degradationLevel;

  /// هل المراقب يعمل؟
  bool get isActive => _state != WatchdogState.stopped;

  /// هل نحن في وضع متدهور؟
  bool get isDegraded => _degradationLevel != DegradationLevel.none;

  /// وقت آخر نشاط
  DateTime? get lastActivity => _lastActivity;

  /// الوقت المنقضي منذ آخر نشاط
  Duration get timeSinceLastActivity =>
      _lastActivity != null
          ? DateTime.now().difference(_lastActivity!)
          : Duration.zero;

  EngineWatchdog({
    required StockfishEngine engine,
    Duration timeout = const Duration(seconds: 15),
    int maxRestarts = 3,
    Duration baseRestartCooldown = const Duration(seconds: 2),
    Duration maxRestartCooldown = const Duration(seconds: 30),
    Duration stablePeriodRequired = const Duration(minutes: 2),
    Duration failureWindow = const Duration(minutes: 5),
    int maxFailuresInWindow = 5,
  })  : _engine = engine,
        _timeout = timeout,
        _maxRestarts = maxRestarts,
        _baseRestartCooldown = baseRestartCooldown,
        _maxRestartCooldown = maxRestartCooldown,
        _stablePeriodRequired = stablePeriodRequired,
        _failureWindow = failureWindow,
        _maxFailuresInWindow = maxFailuresInWindow;

  // ========================================================================
  // بدء وإيقاف المراقب
  // ========================================================================

  /// بدء المراقبة
  void start() {
    if (_state != WatchdogState.stopped) return;

    _state = WatchdogState.active;
    _lastActivity = DateTime.now();
    _lastStablePeriod = DateTime.now();

    // الاستماع لاستجابات المحرك
    _responseSubscription = _engine.responses.listen(_handleEngineResponse);

    // بدء Timer المراقب
    _startWatchdogTimer();

    debugPrint('$_tag: بدأت المراقبة (مهلة: ${_timeout.inSeconds}ث، حد: $_maxRestarts)');
  }

  /// إيقاف المراقبة
  void stop() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _responseSubscription?.cancel();
    _responseSubscription = null;
    _state = WatchdogState.stopped;
    _isRestarting = false;

    debugPrint('$_tag: توقفت المراقبة');
  }

  // ========================================================================
  // إشعار النشاط
  // ========================================================================

  /// إشعار بأن المحرك نشط
  void notifyActivity() {
    _lastActivity = DateTime.now();

    if (_state == WatchdogState.waiting) {
      _setState(WatchdogState.active);
    }

    // التحقق من نجاح مستمر — إعادة تعيين العداد
    _checkStablePeriod();
  }

  // ========================================================================
  // Timer المراقب
  // ========================================================================

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 2), _checkWatchdog);
  }

  void _checkWatchdog(Timer timer) {
    if (_state == WatchdogState.stopped || _isRestarting) return;
    if (_state == WatchdogState.degraded) return; // لا مراقبة في الوضع المتدهور
    if (!_engine.isAnalyzing) return;

    if (_lastActivity == null) {
      _lastActivity = DateTime.now();
      return;
    }

    final elapsed = DateTime.now().difference(_lastActivity!);

    if (elapsed > _timeout) {
      debugPrint('$_tag: المحرك لا يستجيب منذ ${elapsed.inSeconds}ث');
      _setState(WatchdogState.waiting);
      _handleEngineUnresponsive();
    }
  }

  // ========================================================================
  // معالجة الأحداث
  // ========================================================================

  void _handleEngineResponse(UciResponse response) {
    notifyActivity();
  }

  /// معالجة عدم استجابة المحرك — مع حماية ضد restart storm
  Future<void> _handleEngineUnresponsive() async {
    if (_isRestarting) return;

    // Circuit breaker: التحقق من عدد الفشول في النافذة
    _cleanupOldFailures();
    if (_failureTimestamps.length >= _maxFailuresInWindow) {
      debugPrint('$_tag: Circuit breaker — عدد الفشول في النافذة تجاوز الحد');
      _enterDegradedMode(DegradationLevel.severe);
      return;
    }

    // التحقق من الحد الأقصى لإعادة التشغيل
    if (_restartCount >= _maxRestarts) {
      debugPrint('$_tag: تجاوز الحد الأقصى لإعادة التشغيل ($_maxRestarts)');
      onMaxRestartsReached?.call(_restartCount);
      _enterDegradedMode(DegradationLevel.severe);
      return;
    }

    _isRestarting = true;
    _restartCount++;
    _failureTimestamps.add(DateTime.now());
    _setState(WatchdogState.restarting);

    // حساب فترة التبريد مع exponential backoff
    final cooldown = _calculateBackoff();
    debugPrint('$_tag: جاري إعادة تشغيل المحرك ($_restartCount/$_maxRestarts)، انتظار ${cooldown.inSeconds}ث');
    onRestart?.call(_restartCount, cooldown);

    try {
      // 1. إيقاف التحليل الحالي
      _engine.stopAnalysisImmediate();

      // 2. انتظار فترة التبريد (exponential backoff)
      await Future<void>.delayed(cooldown);

      // 3. إعادة تهيئة المحرك
      if (!_engine.isDisposed) {
        await _engine.dispose();
        await _engine.initialize();

        // ضبط إعدادات مخفضة إذا كانت هناك إعادة تشغيل متكررة
        if (_restartCount > 1) {
          _applyReducedSettings();
        }

        debugPrint('$_tag: تمت إعادة تشغيل المحرك بنجاح');
        onRecoverySuccessful?.call();
      }
    } catch (e) {
      debugPrint('$_tag: فشل إعادة تشغيل المحرك: $e');

      // تحديث مستوى التدهور
      if (_restartCount >= _maxRestarts) {
        _enterDegradedMode(DegradationLevel.severe);
      } else if (_restartCount > _maxRestarts / 2) {
        _updateDegradationLevel(DegradationLevel.moderate);
      } else if (_restartCount > 1) {
        _updateDegradationLevel(DegradationLevel.minor);
      }
    } finally {
      _isRestarting = false;
      _lastActivity = DateTime.now();
      if (_state != WatchdogState.degraded) {
        _setState(WatchdogState.active);
      }
    }
  }

  // ========================================================================
  // Exponential Backoff
  // ========================================================================

  /// حساب فترة التبريد مع exponential backoff
  ///
  /// الصيغة: baseCooldown * 2^(restartCount - 1) + jitter
  /// الحد الأقصى: maxRestartCooldown
  Duration _calculateBackoff() {
    final exponentialMs = _baseRestartCooldown.inMilliseconds *
        math.pow(2, _restartCount - 1).toInt();

    // إضافة jitter عشوائي (0-25% من الفترة)
    final jitterMs = (exponentialMs * 0.25 * math.Random().nextDouble()).toInt();

    final totalMs = (exponentialMs + jitterMs).clamp(
      _baseRestartCooldown.inMilliseconds,
      _maxRestartCooldown.inMilliseconds,
    );

    return Duration(milliseconds: totalMs);
  }

  // ========================================================================
  // الوضع المتدهور — Degraded Mode
  // ========================================================================

  /// الدخول في وضع متدهور
  void _enterDegradedMode(DegradationLevel level) {
    _updateDegradationLevel(level);
    _setState(WatchdogState.degraded);
    onDegraded?.call(level);

    debugPrint('$_tag: دخول الوضع المتدهور — المستوى: ${level.name}');
  }

  /// تحديث مستوى التدهور
  void _updateDegradationLevel(DegradationLevel level) {
    if (level.index > _degradationLevel.index) {
      _degradationLevel = level;
    }
  }

  /// تطبيق إعدادات مخفضة على المحرك
  void _applyReducedSettings() {
    try {
      switch (_degradationLevel) {
        case DegradationLevel.none:
          break;
        case DegradationLevel.minor:
          _engine.setMultiPv(2);
          _engine.setThreads(1);
          debugPrint('$_tag: تطبيق إعدادات طفيفة (MultiPV=2, Threads=1)');
          break;
        case DegradationLevel.moderate:
          _engine.setMultiPv(1);
          _engine.setThreads(1);
          _engine.setHashSize(32);
          debugPrint('$_tag: تطبيق إعدادات متوسطة (MultiPV=1, Threads=1, Hash=32)');
          break;
        case DegradationLevel.severe:
          debugPrint('$_tag: وضع شديد — المحرك غير متاح');
          break;
      }
    } catch (e) {
      debugPrint('$_tag: فشل تطبيق الإعدادات المخفضة: $e');
    }
  }

  // ========================================================================
  // إعادة تعيين العداد — Counter Reset
  // ========================================================================

  /// التحقق من فترة نجاح مستمرة — لإعادة تعيين العداد
  void _checkStablePeriod() {
    if (_restartCount == 0) return;
    if (_lastStablePeriod == null) {
      _lastStablePeriod = DateTime.now();
      return;
    }

    final stableDuration = DateTime.now().difference(_lastStablePeriod!);
    if (stableDuration >= _stablePeriodRequired) {
      // نجاح مستمر لفترة كافية — إعادة تعيين العداد
      final oldCount = _restartCount;
      _restartCount = (_restartCount - 1).clamp(0, _restartCount);
      _lastStablePeriod = DateTime.now();

      if (oldCount != _restartCount) {
        debugPrint('$_tag: إعادة تعيين عداد التشغيل → $_restartCount (نجاح مستمر)');

        // إذا عدّدنا للصفر، نخرج من الوضع المتدهور
        if (_restartCount == 0 && _state == WatchdogState.degraded) {
          _degradationLevel = DegradationLevel.none;
          _setState(WatchdogState.active);
          debugPrint('$_tag: خروج من الوضع المتدهور — استعادة كاملة');
        }
      }
    }
  }

  /// تنظيف سجلات الفشل القديمة
  void _cleanupOldFailures() {
    final cutoff = DateTime.now().subtract(_failureWindow);
    _failureTimestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  // ========================================================================
  // دوال مساعدة
  // ========================================================================

  void _setState(WatchdogState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  /// إعادة تعيين عداد إعادة التشغيل يدوياً
  void resetRestartCount() {
    _restartCount = 0;
    _lastStablePeriod = DateTime.now();
  }

  /// محاولة الاستعادة من الوضع المتدهور — Manual recovery attempt
  Future<bool> attemptRecovery() async {
    if (_state != WatchdogState.degraded) return false;

    debugPrint('$_tag: محاولة يدوية للاستعادة من الوضع المتدهور');

    try {
      if (!_engine.isDisposed) {
        await _engine.dispose();
      }

      // إعادة ضبط الحالة
      _restartCount = 0;
      _degradationLevel = DegradationLevel.none;
      _failureTimestamps.clear();
      _lastActivity = DateTime.now();
      _lastStablePeriod = DateTime.now();

      // إعادة تهيئة المحرك
      await _engine.initialize();

      _setState(WatchdogState.active);
      debugPrint('$_tag: نجحت الاستعادة اليدوية');
      return true;
    } catch (e) {
      debugPrint('$_tag: فشلت الاستعادة اليدوية: $e');
      _enterDegradedMode(DegradationLevel.severe);
      return false;
    }
  }

  /// تحرير الموارد
  void dispose() {
    stop();
    _failureTimestamps.clear();
  }
}
