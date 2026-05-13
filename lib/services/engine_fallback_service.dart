/// engine_fallback_service.dart
/// خدمة المحرك الاحتياطي مع سجلات مفصلة (حل مشكلة #1)
///
/// يحل مشكلة فشل تشغيل Stockfish على بعض أجهزة Android:
/// - MIUI: منع execution
/// - Samsung: SELinux restrictions
/// - Android 14/15: tighter sandbox
/// - Huawei: process policies
///
/// الحل:
/// - تجربة محرك الحزمة أولاً (الأكثر توافقاً)
/// - ثم محرك Process كاحتياطي
/// - سجلات مفصلة لكل خطوة
/// - كشف التوافق التلقائي
/// - إعادة محاولة ذكية

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/stockfish_engine.dart';
import '../engine/stockfish_package_engine.dart';
import '../engine/chess_engine_interface.dart';

// ============================================================================
// مستوى السجل — Log Level
// ============================================================================

enum EngineLogLevel {
  verbose,
  info,
  warning,
  error,
  none,
}

// ============================================================================
// سجل المحرك — Engine Log Entry
// ============================================================================

class EngineLogEntry {
  final DateTime timestamp;
  final EngineLogLevel level;
  final String tag;
  final String message;
  final String? details;
  final String? deviceInfo;

  const EngineLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.details,
    this.deviceInfo,
  });

  String toFormattedString() {
    final levelStr = level.name.toUpperCase().padRight(7);
    return '[${timestamp.toIso8601String()}] $levelStr $tag: $message'
        '${details != null ? '\n  ↳ $details' : ''}'
        '${deviceInfo != null ? '\n  ↳ Device: $deviceInfo' : ''}';
  }
}

// ============================================================================
// وضع المحرك — Engine Mode
// ============================================================================

enum EngineMode {
  /// محرك حقيقي كامل (Stockfish via Package/FFI)
  packageStockfish,

  /// محرك حقيقي كامل (Stockfish via Process)
  fullStockfish,

  /// محرك حقيقي بإعدادات مخفضة (threads=1, hash=16)
  reducedStockfish,

  /// محرك محلي بسيط
  basicLocal,

  /// لا محرك متاح
  none,
}

// ============================================================================
// نتيجة تشخيص المحرك — Engine Diagnostic Result
// ============================================================================

class EngineDiagnosticResult {
  final bool packageAvailable;
  final bool binaryFound;
  final bool binaryExecutable;
  final bool binaryRuns;
  final bool uciokReceived;
  final bool readyokReceived;
  final Duration startupTime;
  final String? binaryPath;
  final String? errorMessage;
  final String? platformDetails;
  final List<EngineLogEntry> logs;
  final EngineMode successfulMode;

  const EngineDiagnosticResult({
    this.packageAvailable = false,
    this.binaryFound = false,
    this.binaryExecutable = false,
    this.binaryRuns = false,
    this.uciokReceived = false,
    this.readyokReceived = false,
    this.startupTime = Duration.zero,
    this.binaryPath,
    this.errorMessage,
    this.platformDetails,
    this.logs = const [],
    this.successfulMode = EngineMode.none,
  });

  /// هل المحرك يعمل بشكل كامل؟
  bool get isFullyOperational =>
      (packageAvailable || (binaryFound && binaryExecutable && binaryRuns)) &&
      uciokReceived &&
      readyokReceived;

  /// هل المحرك يعمل بشكل جزئي؟
  bool get isPartiallyOperational => binaryRuns && uciokReceived;

  /// الوضع الموصى به بناءً على التشخيص
  EngineMode get recommendedMode {
    if (packageAvailable) return EngineMode.packageStockfish;
    if (binaryFound && binaryExecutable && binaryRuns) return EngineMode.fullStockfish;
    if (binaryRuns && uciokReceived) return EngineMode.reducedStockfish;
    if (binaryFound) return EngineMode.basicLocal;
    return EngineMode.none;
  }
}

// ============================================================================
// خدمة المحرك الاحتياطي — Engine Fallback Service
// ============================================================================

/// خدمة المحرك الاحتياطي مع سجلات مفصلة
///
/// ترتيب المحاولات:
/// 1. محرك الحزمة (packageStockfish) — الأكثر توافقاً مع جميع الأجهزة
/// 2. محرك Process كامل (fullStockfish) — إذا الحزمة ما اشتغلت
/// 3. محرك Process مخفض (reducedStockfish) — آخر احتياطي
/// 4. لا محرك (none) — إذا فشل كل شي
class EngineFallbackService {
  static const _tag = 'EngineFallbackService';

  final List<EngineLogEntry> _logs = [];
  static const _maxLogEntries = 500;

  EngineLogLevel _logLevel = EngineLogLevel.info;
  EngineMode _currentMode = EngineMode.none;
  int _startupAttempts = 0;
  static const _maxStartupAttempts = 3;

  /// المحرك الحالي (قد يكون من أي نوع)
  ChessEngine? _engine;

  bool _isFallback = false;

  // Callbacks
  void Function(EngineMode mode)? onModeChanged;
  void Function(EngineLogEntry entry)? onLogEntry;

  // Getters
  EngineMode get currentMode => _currentMode;
  bool get isFallback => _isFallback;
  List<EngineLogEntry> get logs => List.unmodifiable(_logs);
  int get startupAttempts => _startupAttempts;
  ChessEngine? get engine => _engine;

  // ========================================================================
  // التسجيل — Logging
  // ========================================================================

  void _log(EngineLogLevel level, String tag, String message, {String? details}) {
    if (level.index < _logLevel.index) return;

    final entry = EngineLogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      details: details,
      deviceInfo: _getDeviceInfo(),
    );

    _logs.add(entry);

    if (_logs.length > _maxLogEntries) {
      _logs.removeRange(0, _logs.length - _maxLogEntries);
    }

    if (kDebugMode) {
      debugPrint(entry.toFormattedString());
    }

    onLogEntry?.call(entry);
  }

  String _getDeviceInfo() {
    try {
      return 'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'Platform: unknown';
    }
  }

  // ========================================================================
  // التشخيص — Diagnostics
  // ========================================================================

  /// تشخيص كامل للمحرك
  Future<EngineDiagnosticResult> runDiagnostic() async {
    _log(EngineLogLevel.info, _tag, 'بدء التشخيص الكامل للمحرك');

    final stopwatch = Stopwatch()..start();

    // الخطوة 1: تجربة محرك الحزمة
    bool packageAvailable = false;
    String? errorMessage;

    _log(EngineLogLevel.info, _tag, 'فحص محرك الحزمة (stockfish package)...');
    try {
      final testEngine = StockfishPackageEngine();
      final completer = Completer<bool>();

      testEngine.onReady = () {
        if (!completer.isCompleted) completer.complete(true);
      };
      testEngine.onError = (error) {
        errorMessage = error.message;
        if (!completer.isCompleted) completer.complete(false);
      };

      await testEngine.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          errorMessage = 'انتهت مهلة تشغيل الحزمة';
          if (!completer.isCompleted) completer.complete(false);
        },
      );

      final success = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );

      if (success) {
        packageAvailable = true;
        _log(EngineLogLevel.info, _tag, 'محرك الحزمة يعمل بنجاح!');
      } else {
        _log(EngineLogLevel.warning, _tag, 'محرك الحزمة لم يصبح جاهزاً', details: errorMessage);
      }

      await testEngine.dispose();
    } catch (e) {
      errorMessage = e.toString();
      _log(EngineLogLevel.warning, _tag, 'فشل محرك الحزمة', details: e.toString());
    }

    // الخطوة 2: فحص محرك Process
    bool binaryFound = false;
    bool binaryExecutable = false;
    bool binaryRuns = false;
    bool uciokReceived = false;
    bool readyokReceived = false;
    String? binaryPath;

    _log(EngineLogLevel.info, _tag, 'فحص محرك Process...');
    try {
      binaryPath = await StockfishBinaryManager.prepareBinary();
      binaryFound = true;
      _log(EngineLogLevel.info, _tag, 'العثور على binary', details: binaryPath);
    } catch (e) {
      _log(EngineLogLevel.error, _tag, 'فشل العثور على binary', details: e.toString());
    }

    if (binaryFound && binaryPath != null) {
      try {
        final file = File(binaryPath);
        if (await file.exists()) {
          if (!Platform.isWindows) {
            final result = await Process.run('ls', ['-la', binaryPath]);
            binaryExecutable = result.exitCode == 0;
          } else {
            binaryExecutable = true;
          }
        }
      } catch (e) {
        _log(EngineLogLevel.warning, _tag, 'فشل التحقق من الصلاحية', details: e.toString());
      }
    }

    if (binaryFound && binaryExecutable) {
      try {
        final testEngine = StockfishEngine();
        final completer = Completer<bool>();

        testEngine.onReady = () {
          if (!completer.isCompleted) completer.complete(true);
        };
        testEngine.onError = (error) {
          errorMessage = error.message;
          if (!completer.isCompleted) completer.complete(false);
        };

        await testEngine.initialize(binaryPath: binaryPath).timeout(
          const Duration(seconds: 15),
        );

        binaryRuns = true;

        final success = await completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );

        if (success) {
          readyokReceived = true;
          uciokReceived = true;
        }

        await testEngine.dispose();
      } catch (e) {
        errorMessage = e.toString();
        _log(EngineLogLevel.error, _tag, 'فشل تشغيل Process engine', details: e.toString());
      }
    }

    stopwatch.stop();

    // تحديد الوضع الناجح
    EngineMode successfulMode = EngineMode.none;
    if (packageAvailable) {
      successfulMode = EngineMode.packageStockfish;
    } else if (binaryFound && binaryExecutable && binaryRuns && uciokReceived) {
      successfulMode = EngineMode.fullStockfish;
    } else if (binaryRuns && uciokReceived) {
      successfulMode = EngineMode.reducedStockfish;
    }

    final result = EngineDiagnosticResult(
      packageAvailable: packageAvailable,
      binaryFound: binaryFound,
      binaryExecutable: binaryExecutable,
      binaryRuns: binaryRuns,
      uciokReceived: uciokReceived,
      readyokReceived: readyokReceived,
      startupTime: stopwatch.elapsed,
      binaryPath: binaryPath,
      errorMessage: errorMessage,
      platformDetails: _getDeviceInfo(),
      logs: List.from(_logs),
      successfulMode: successfulMode,
    );

    _log(EngineLogLevel.info, _tag, 'انتهى التشخيص',
        details: 'الوضع الموصى به: ${result.recommendedMode.name}');

    return result;
  }

  // ========================================================================
  // التشغيل مع الاحتياطي — Start with Fallback
  // ========================================================================

  /// تشغيل المحرك مع احتياطي تلقائي
  ///
  /// الترتيب:
  /// 1. محرك الحزمة (الأكثر توافقاً — لا يحتاج binary)
  /// 2. محرك Process كامل
  /// 3. محرك Process مخفض
  /// 4. لا محرك
  Future<ChessEngine?> startWithFallback() async {
    _startupAttempts++;
    _log(EngineLogLevel.info, _tag, 'محاولة التشغيل #$_startupAttempts');

    // ── المحاولة 1: محرك الحزمة (الأفضل) ──────────────────────────────
    try {
      final engine = await _tryStartPackage();
      if (engine != null) {
        _setMode(EngineMode.packageStockfish, isFallback: false);
        _startupAttempts = 0;
        return engine;
      }
    } catch (e) {
      _log(EngineLogLevel.warning, _tag, 'فشل محرك الحزمة', details: e.toString());
    }

    // ── المحاولة 2: محرك Process كامل ──────────────────────────────────
    try {
      final engine = await _tryStartFull();
      if (engine != null) {
        _setMode(EngineMode.fullStockfish, isFallback: true);
        _startupAttempts = 0;
        return engine;
      }
    } catch (e) {
      _log(EngineLogLevel.warning, _tag, 'فشل التشغيل الكامل', details: e.toString());
    }

    // ── المحاولة 3: محرك Process مخفض ──────────────────────────────────
    try {
      final engine = await _tryStartReduced();
      if (engine != null) {
        _setMode(EngineMode.reducedStockfish, isFallback: true);
        _startupAttempts = 0;
        return engine;
      }
    } catch (e) {
      _log(EngineLogLevel.warning, _tag, 'فشل التشغيل المخفض', details: e.toString());
    }

    // ── فشلت جميع المحاولات ────────────────────────────────────────────
    _setMode(EngineMode.none, isFallback: true);
    _log(EngineLogLevel.error, _tag, 'فشلت جميع محاولات التشغيل');
    return null;
  }

  /// محاولة تشغيل محرك الحزمة (الأولوية القصوى)
  Future<StockfishPackageEngine?> _tryStartPackage() async {
    _log(EngineLogLevel.info, _tag, 'محاولة تشغيل محرك الحزمة (stockfish package)');

    final engine = StockfishPackageEngine();

    try {
      await engine.initialize().timeout(const Duration(seconds: 15));
      engine.setMultiPv(3);
      engine.setThreads(2);
      engine.setHashSize(128);

      _engine = engine;
      _log(EngineLogLevel.info, _tag, 'نجح تشغيل محرك الحزمة!');
      return engine;
    } catch (e) {
      try {
        await engine.dispose();
      } catch (_) {}
      _log(EngineLogLevel.error, _tag, 'فشل محرك الحزمة', details: e.toString());
      return null;
    }
  }

  /// محاولة تشغيل المحرك الكامل (Process-based)
  Future<StockfishEngine?> _tryStartFull() async {
    _log(EngineLogLevel.info, _tag, 'محاولة التشغيل الكامل (Process)');

    final engine = StockfishEngine();

    try {
      await engine.initialize().timeout(const Duration(seconds: 15));
      engine.setMultiPv(3);
      engine.setThreads(2);
      engine.setHashSize(128);

      _engine = engine;
      _log(EngineLogLevel.info, _tag, 'نجح التشغيل الكامل');
      return engine;
    } catch (e) {
      try {
        await engine.dispose();
      } catch (_) {}
      _log(EngineLogLevel.error, _tag, 'فشل التشغيل الكامل', details: e.toString());
      return null;
    }
  }

  /// محاولة تشغيل المحرك المخفض (Process-based, threads=1, hash=16)
  Future<StockfishEngine?> _tryStartReduced() async {
    _log(EngineLogLevel.info, _tag, 'محاولة التشغيل المخفض (threads=1, hash=16)');

    final engine = StockfishEngine();

    try {
      await engine.initialize().timeout(const Duration(seconds: 20));
      engine.setMultiPv(1);
      engine.setThreads(1);
      engine.setHashSize(16);

      _engine = engine;
      _isFallback = true;
      _log(EngineLogLevel.info, _tag, 'نجح التشغيل المخفض');
      return engine;
    } catch (e) {
      try {
        await engine.dispose();
      } catch (_) {}
      _log(EngineLogLevel.error, _tag, 'فشل التشغيل المخفض', details: e.toString());
      return null;
    }
  }

  /// تغيير وضع المحرك
  void _setMode(EngineMode mode, {required bool isFallback}) {
    if (_currentMode != mode) {
      _currentMode = mode;
      _isFallback = isFallback;
      _log(EngineLogLevel.info, _tag, 'تغير الوضع', details: mode.name);
      onModeChanged?.call(mode);
    }
  }

  // ========================================================================
  // تقارير التشخيص — Diagnostic Reports
  // ========================================================================

  /// الحصول على تقرير تشخيصي كامل
  String getDiagnosticReport() {
    final buffer = StringBuffer();
    buffer.writeln('=== تقرير تشخيص المحرك ===');
    buffer.writeln('التاريخ: ${DateTime.now().toIso8601String()}');
    buffer.writeln('المنصة: ${_getDeviceInfo()}');
    buffer.writeln('الوضع الحالي: ${_currentMode.name}');
    buffer.writeln('وضع احتياطي: ${_isFallback ? 'نعم' : 'لا'}');
    buffer.writeln('محاولات التشغيل: $_startupAttempts');
    buffer.writeln('');
    buffer.writeln('--- السجلات ---');
    for (final entry in _logs) {
      buffer.writeln(entry.toFormattedString());
    }
    return buffer.toString();
  }

  /// مسح السجلات
  void clearLogs() {
    _logs.clear();
  }

  /// ضبط مستوى السجل
  void setLogLevel(EngineLogLevel level) {
    _logLevel = level;
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    _engine?.dispose();
    _engine = null;
    _logs.clear();
    onModeChanged = null;
    onLogEntry = null;
  }
}
