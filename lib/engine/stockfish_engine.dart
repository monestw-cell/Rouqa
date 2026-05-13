/// stockfish_engine.dart
/// تكامل محرك Stockfish الحقيقي لتطبيق رُقعة
///
/// هذا الملف يوفر تكاملاً كاملاً مع محرك Stockfish عبر بروتوكول UCI
/// باستخدام dart:io Process للتواصل مع المحرك الثنائي.
///
/// الميزات الرئيسية:
/// - إدارة المحرك الثنائي عبر جميع المنصات (Android, iOS, Desktop)
/// - تنفيذ كامل لبروتوكول UCI
/// - تحليل بعمق محدد أو بوقت محدد أو غير محدود
/// - دعم MultiPV (خطوط لعب متعددة)
/// - تقييد مستوى اللعب بالـ ELO
/// - تدفقات بيانات حية (Streams) للتحديثات الفورية
/// - معالجة أخطاء شاملة مع إعادة تشغيل تلقائية
/// - تنظيف آمن للموارد عند الإغلاق

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'chess_engine_interface.dart';
import 'uci_protocol.dart';

// ============================================================================
// استثناءات المحرك (Engine Exceptions)
// ============================================================================

/// استثناء عام لمحرك الشطرنج
class StockfishException implements Exception {
  final String message;
  final String? details;

  const StockfishException(this.message, {this.details});

  @override
  String toString() =>
      'StockfishException: $message${details != null ? ' ($details)' : ''}';
}

/// استثناء عدم العثور على المحرك الثنائي
class BinaryNotFoundException extends StockfishException {
  final String? searchedPath;

  const BinaryNotFoundException(String message, {this.searchedPath})
      : super(message, details: searchedPath);

  @override
  String toString() =>
      'BinaryNotFoundException: $message${searchedPath != null ? ' (searched: $searchedPath)' : ''}';
}

/// استثناء انهيار المحرك
class EngineCrashException extends StockfishException {
  final int? exitCode;

  const EngineCrashException(String message, {this.exitCode})
      : super(message, details: 'exitCode=$exitCode');

  @override
  String toString() =>
      'EngineCrashException: $message${exitCode != null ? ' (exitCode=$exitCode)' : ''}';
}

/// استثناء انتهاء المهلة
class EngineTimeoutException extends StockfishException {
  final Duration timeout;

  const EngineTimeoutException(String message, this.timeout)
      : super(message, details: '${timeout.inSeconds}s');

  @override
  String toString() =>
      'EngineTimeoutException: $message (timeout: ${timeout.inSeconds}s)';
}

// ============================================================================
// حالة المحرك (Engine State)
// ============================================================================

/// حالات المحرك الممكنة
enum EngineState {
  /// لم يتم التهيئة بعد
  uninitialized,

  /// جاري تهيئة المحرك
  initializing,

  /// المحرك جاهز لاستقبال الأوامر
  ready,

  /// المحرك يحلل الموقف
  analyzing,

  /// حدث خطأ
  error,

  /// تم إغلاق المحرك
  disposed,
}

// ============================================================================
// مدير المحرك الثنائي (StockfishBinaryManager)
// ============================================================================

/// مدير المحرك الثنائي - يتولى العثور على المحرك وتجهيزه عبر المنصات
///
/// على Android:
/// - ينسخ المحرك من assets إلى وحدة التخزين الداخلية للتطبيق
/// - يمنح صلاحية التنفيذ (chmod +x)
///
/// على iOS:
/// - يستخدم المحرك المضمن في الحزمة
///
/// على Desktop (Windows/macOS/Linux):
/// - يبحث عن المحرك المثبت في النظام
/// - أو يستخدم المحرك المضمن في الحزمة
class StockfishBinaryManager {
  static const _tag = 'StockfishBinaryManager';

  /// اسم ملف المحرك الثنائي حسب المنصة
  static String get _binaryName {
    if (Platform.isWindows) return 'stockfish.exe';
    if (Platform.isMacOS) return 'stockfish';
    if (Platform.isLinux) return 'stockfish';
    if (Platform.isAndroid) return 'libstockfish.so';
    if (Platform.isIOS) return 'stockfish';
    return 'stockfish';
  }

  /// المسار المحتمل للمحرك على أنظمة Desktop
  static const _systemPaths = <List<String>>[
    // Linux
    ['/usr/bin/stockfish'],
    ['/usr/games/stockfish'],
    ['/usr/local/bin/stockfish'],
    ['/snap/bin/stockfish'],
    // macOS (Homebrew)
    ['/usr/local/bin/stockfish'],
    ['/opt/homebrew/bin/stockfish'],
    // Windows
    [r'C:\Program Files\Stockfish\stockfish.exe'],
    [r'C:\Stockfish\stockfish.exe'],
    [r'C:\Program Files (x86)\Stockfish\stockfish.exe'],
  ];

  /// مسار المحرك الثنائي بعد التحضير (مخزن مؤقتاً)
  static String? _cachedBinaryPath;

  /// يعثر على مسار المحرك الثنائي ويجهزه
  ///
  /// يعيد المسار الكامل للملف الثنائي القابل للتنفيذ.
  /// يرمي [BinaryNotFoundException] إذا لم يعثر على المحرك.
  static Future<String> prepareBinary() async {
    // إذا كان لدينا مسار مخزن، نستخدمه
    if (_cachedBinaryPath != null) {
      final file = File(_cachedBinaryPath!);
      if (await file.exists()) return _cachedBinaryPath!;
      _cachedBinaryPath = null;
    }

    String? binaryPath;

    if (Platform.isAndroid) {
      binaryPath = await _prepareAndroidBinary();
    } else if (Platform.isIOS) {
      binaryPath = await _prepareIOSBinary();
    } else {
      binaryPath = await _prepareDesktopBinary();
    }

    if (binaryPath == null) {
      throw BinaryNotFoundException(
        'لم يتم العثور على محرك Stockfish. '
        'يرجى التأكد من تثبيت المحرك أو تضمينه في حزمة التطبيق.',
        searchedPath: binaryPath,
      );
    }

    // التحقق من وجود الملف
    final file = File(binaryPath);
    if (!await file.exists()) {
      throw BinaryNotFoundException(
        'ملف المحرك غير موجود في المسار المتوقع',
        searchedPath: binaryPath,
      );
    }

    _cachedBinaryPath = binaryPath;
    debugPrint('$_tag: تم العثور على المحرك في: $binaryPath');
    return binaryPath;
  }

  /// يجهز المحرك على Android - ينسخ من assets إلى التخزين الداخلي
  static Future<String?> _prepareAndroidBinary() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final binaryDir = p.join(appDir.path, 'engine');
      final binaryFile = p.join(binaryDir, _binaryName);

      // التحقق مما إذا كان الملف موجوداً بالفعل
      final file = File(binaryFile);
      if (await file.exists()) {
        // التحقق من صلاحية التنفيذ
        final result = await Process.run('ls', ['-la', binaryFile]);
        if (result.exitCode == 0) {
          // التأكد من صلاحية التنفيذ
          await _ensureExecutable(binaryFile);
          return binaryFile;
        }
      }

      // إنشاء المجلد إذا لم يكن موجوداً
      final dir = Directory(binaryDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // نسخ المحرك من assets
      // في Flutter، نستخدم rootBundle لقراءة assets
      // لكن بما أننا لا نستطيع استيراد flutter/services.dart هنا
      // نعتمد على أن الملف تم نسخه مسبقاً أو عبر طريقة أخرى
      //
      // ملاحظة: يجب أن يتم نسخ المحرك من assets في كود التطبيق الرئيسي
      // باستخدام:
      // ```dart
      // final data = await rootBundle.load('assets/engine/$_binaryName');
      // final bytes = data.buffer.asUint8List();
      // await File(binaryFile).writeAsBytes(bytes);
      // ```
      //
      // نتحقق هنا فقط من وجود الملف بعد النسخ
      if (await file.exists()) {
        await _ensureExecutable(binaryFile);
        return binaryFile;
      }

      // محاولة البحث عن المحرك في مسارات أخرى
      final altPaths = [
        p.join(appDir.path, 'flutter_assets', 'assets', 'engine', _binaryName),
        p.join(appDir.path, 'app_flutter', 'flutter_assets', 'assets', 'engine', _binaryName),
      ];

      for (final altPath in altPaths) {
        final altFile = File(altPath);
        if (await altFile.exists()) {
          // نسخ من المسار البديل إلى المسار الرئيسي
          await altFile.copy(binaryFile);
          await _ensureExecutable(binaryFile);
          return binaryFile;
        }
      }

      debugPrint('$_tag: لم يتم العثور على المحرك في assets على Android');
      return null;
    } catch (e) {
      debugPrint('$_tag: خطأ في تجهيز المحرك على Android: $e');
      return null;
    }
  }

  /// يجهز المحرك على iOS - يستخدم المحرك المضمن
  static Future<String?> _prepareIOSBinary() async {
    // على iOS، المحرك يكون مضمناً في حزمة التطبيق
    // ويمكن الوصول إليه عبر Process مباشرة
    // المسار يعتمد على كيفية تضمين المحرك في المشروع

    try {
      // محاولة العثور على المحرك في مسار الحزمة
      // على iOS، غالباً يكون في Bundle.main.path
      final appDir = await getApplicationSupportDirectory();
      final possiblePaths = [
        p.join(appDir.path, _binaryName),
        // مسار Framework - إذا تم تضمين المحرك كـ framework
        p.join(appDir.path, 'Frameworks', 'Stockfish.framework', 'Stockfish'),
      ];

      for (final path in possiblePaths) {
        if (await File(path).exists()) {
          return path;
        }
      }

      // محاولة استخدام اسم المحرك مباشرة (إذا كان في PATH)
      return _binaryName;
    } catch (e) {
      debugPrint('$_tag: خطأ في تجهيز المحرك على iOS: $e');
      return null;
    }
  }

  /// يجهز المحرك على Desktop - يبحث في مسارات النظام
  static Future<String?> _prepareDesktopBinary() async {
    // 1. البحث في مسارات النظام المعروفة
    for (final pathList in _systemPaths) {
      final path = p.joinAll(pathList);
      final file = File(path);
      if (await file.exists()) {
        await _ensureExecutable(path);
        return path;
      }
    }

    // 2. البحث في متغير PATH باستخدام `which` أو `where`
    try {
      String command;
      if (Platform.isWindows) {
        command = 'where';
      } else {
        command = 'which';
      }

      final result = await Process.run(command, ['stockfish']);
      if (result.exitCode == 0) {
        final foundPath = (result.stdout as String).trim().split('\n').first.trim();
        if (foundPath.isNotEmpty && await File(foundPath).exists()) {
          return foundPath;
        }
      }
    } catch (_) {
      // فشل البحث في PATH - نتابع
    }

    // 3. البحث في مجلد التطبيق
    try {
      final appDir = await getApplicationSupportDirectory();
      final appBinary = p.join(appDir.path, 'engine', _binaryName);
      if (await File(appBinary).exists()) {
        await _ensureExecutable(appBinary);
        return appBinary;
      }
    } catch (_) {
      // لا يوجد مجلد دعم
    }

    // 4. البحث في المجلد الحالي ومجلد المشروع
    final localPaths = [
      _binaryName,
      p.join('engine', _binaryName),
      p.join('assets', 'engine', _binaryName),
      p.join('third_party', 'stockfish', _binaryName),
    ];

    for (final path in localPaths) {
      if (await File(path).exists()) {
        await _ensureExecutable(path);
        return p.absolute(path);
      }
    }

    return null;
  }

  /// يمنح الملف صلاحية التنفيذ على أنظمة Unix
  static Future<void> _ensureExecutable(String path) async {
    if (Platform.isWindows) return; // Windows لا يحتاج chmod

    try {
      final result = await Process.run('chmod', ['+x', path]);
      if (result.exitCode != 0) {
        debugPrint('$_tag: تحذير - فشل chmod +x: ${result.stderr}');
        // نحاول مرة أخرى بطريقة أخرى
        final file = File(path);
        // تغيير صلاحية الملف عبر Dart
        // ملاحظة: dart:io لا يدعم chmod مباشرة، لكننا نستخدم Process
      }
    } catch (e) {
      debugPrint('$_tag: تحذير - خطأ في chmod: $e');
    }
  }

  /// يمسح المحرك الثنائي المخزن (للتنظيف أو التحديث)
  static Future<void> cleanCachedBinary() async {
    if (_cachedBinaryPath != null) {
      try {
        final file = File(_cachedBinaryPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        debugPrint('$_tag: خطأ في مسح المحرك المخزن: $e');
      }
      _cachedBinaryPath = null;
    }
  }

  /// يتحقق من وجود المحرك دون تجهيزه
  static Future<bool> isBinaryAvailable() async {
    try {
      final path = await prepareBinary();
      return path.isNotEmpty;
    } on BinaryNotFoundException {
      return false;
    } catch (_) {
      return false;
    }
  }
}

// ============================================================================
// محرك Stockfish الرئيسي (StockfishEngine)
// ============================================================================

/// محرك Stockfish - تكامل كامل مع محرك الشطرنج عبر بروتوكول UCI
///
/// الاستخدام الأساسي:
/// ```dart
/// final engine = StockfishEngine();
///
/// // تهيئة المحرك
/// await engine.initialize();
///
/// // إعداد الموقف
/// engine.setPositionFromFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
///
/// // بدء التحليل
/// engine.analyzeDepth(20);
///
/// // الاستماع للنتائج
/// engine.onBestMove = (move) {
///   print('أفضل حركة: $move');
/// };
///
/// // عند الانتهاء
/// engine.dispose();
/// ```
///
/// تصميم المحرك:
/// - يستخدم Process.start() لتشغيل المحرك كعملية منفصلة
/// - يتواصل عبر stdin/stdout streams
/// - يوفر Stream<UciResponse> للتحديثات الحية
/// - يدعم callbacks للعمليات الشائعة
/// - يعالج الأخطاء والانهيارات تلقائياً
class StockfishEngine implements ChessEngine {
  static const _tag = 'StockfishEngine';

  // ========================================================================
  // الإعدادات الافتراضية
  // ========================================================================

  /// المهلة الافتراضية لانتظار استجابة المحرك
  static const defaultTimeout = Duration(seconds: 10);

  /// الحد الأقصى لعمق التحليل
  static const maxDepth = 50;

  /// الحد الأقصى لعدد خطوط MultiPV
  static const maxMultiPv = 5;

  // ========================================================================
  // الحالة الداخلية
  // ========================================================================

  /// عملية المحرك
  Process? _process;

  /// حالة المحرك الحالية
  EngineState _state = EngineState.uninitialized;

  /// Stream controller للاستجابات
  final StreamController<UciResponse> _responseController =
      StreamController<UciResponse>.broadcast();

  /// اشتراك في stdout
  StreamSubscription<String>? _stdoutSubscription;

  /// اشتراك في stderr
  StreamSubscription<String>? _stderrSubscription;

  /// Completer لانتظار uciok
  Completer<void>? _uciokCompleter;

  /// Completer لانتظار readyok
  Completer<void>? _readyokCompleter;

  /// Completer لانتظار bestmove
  Completer<BestMoveResponse>? _bestMoveCompleter;

  /// آخر تحليل info تم استلامه لكل خط MultiPV
  final Map<int, InfoResponse> _latestInfoByPv = {};

  /// عدد خطوط MultiPV المطلوبة حالياً
  int _currentMultiPv = 1;

  /// هل دور الأبيض للعب في الموقف الحالي؟
  bool _isWhiteToMove = true;

  /// المهلة الحالية
  Duration _timeout = defaultTimeout;

  /// ما إذا كان قد تم التخلص من المحرك
  bool _isDisposed = false;

  /// اسم المحرك (من استجابة id)
  String? _engineName;

  /// مؤلف المحرك (من استجابة id)
  String? _engineAuthor;

  /// خيارات المحرك المتاحة (من استجابات option)
  final Map<String, OptionResponse> _options = {};

  /// آخر سطر info كامل تم استلامه
  InfoResponse? _lastInfoResponse;

  /// مفتاح منع إعادة التشغيل المتزامنة
  bool _isRestarting = false;

  /// Timer لمراقبة انهيار المحرك
  Timer? _watchdogTimer;

  // ========================================================================
  // Callbacks
  // ========================================================================

  /// يُستدعى عند تلقي تحليل جديد (كل سطر info)
  @override
  void Function(InfoResponse info)? onAnalysisUpdate;

  /// يُستدعى عند العثور على أفضل حركة
  @override
  void Function(BestMoveResponse bestMove)? onBestMove;

  /// يُستدعى عندما يصبح المحرك جاهزاً
  @override
  void Function()? onReady;

  /// يُستدعى عند حدوث خطأ
  @override
  void Function(StockfishException error)? onError;

  /// يُستدعى عند تغير حالة المحرك
  @override
  void Function(EngineState state)? onStateChanged;

  /// يُستدعى عند تلقي أي استجابة UCI
  @override
  void Function(UciResponse response)? onRawResponse;

  // ========================================================================
  // Getters
  // ========================================================================

  /// حالة المحرك الحالية
  @override
  EngineState get state => _state;

  /// تدفق استجابات UCI الحية
  @override
  Stream<UciResponse> get responses => _responseController.stream;

  /// اسم المحرك
  @override
  String? get engineName => _engineName;

  /// مؤلف المحرك
  String? get engineAuthor => _engineAuthor;

  /// خيارات المحرك المتاحة
  Map<String, OptionResponse> get options => Map.unmodifiable(_options);

  /// آخر تحليل info تم استلامه
  @override
  InfoResponse? get lastInfoResponse => _lastInfoResponse;

  /// آخر تحليل info لكل خط MultiPV
  @override
  Map<int, InfoResponse> get latestInfoByPv => Map.unmodifiable(_latestInfoByPv);

  /// هل المحرك يحلل حالياً؟
  @override
  bool get isAnalyzing => _state == EngineState.analyzing;

  /// هل المحرك جاهز؟
  @override
  bool get isReady => _state == EngineState.ready;

  /// هل المحرك تم التخلص منه؟
  @override
  bool get isDisposed => _isDisposed;

  /// هل دور الأبيض للعب؟
  @override
  bool get isWhiteToMove => _isWhiteToMove;

  /// هل المحرك يعتمد على الحزمة؟ (Process-based = false)
  @override
  bool get isPackageBased => false;

  // ========================================================================
  // التهيئة والإغلاق
  // ========================================================================

  /// يهيئ المحرك ويشغله
  ///
  /// يجب استدعاء هذه الدالة قبل أي عملية أخرى.
  /// تقوم بـ:
  /// 1. العثور على المحرك الثنائي
  /// 2. تشغيله كعملية منفصلة
  /// 3. إرسال أمر `uci`
  /// 4. انتظار `uciok`
  /// 5. إرسال أمر `isready`
  /// 6. انتظار `readyok`
  ///
  /// يمكن تحديد مسار المحرك يدوياً عبر [binaryPath].
  /// إذا لم يُحدد، يبحث عنه تلقائياً.
  @override
  Future<void> initialize({String? binaryPath}) async {
    if (_isDisposed) {
      throw StockfishException('المحرك تم التخلص منه ولا يمكن تهيئته مجدداً');
    }

    if (_state == EngineState.ready || _state == EngineState.analyzing) {
      return; // المحرك يعمل بالفعل
    }

    _setState(EngineState.initializing);

    try {
      // 1. العثور على المحرك الثنائي
      final path = binaryPath ?? await StockfishBinaryManager.prepareBinary();
      debugPrint('$_tag: بدء تشغيل المحرك من: $path');

      // 2. تشغيل المحرك كعملية منفصلة
      _process = await Process.start(
        path,
        [],
        workingDirectory: p.dirname(path),
      );

      // 3. الاستماع للنتائج
      _setupListeners();

      // 4. إرسال أمر uci وانتظار uciok
      _uciokCompleter = Completer<void>();
      sendCommand('uci');

      await _uciokCompleter!.future.timeout(
        _timeout,
        onTimeout: () => throw EngineTimeoutException(
          'انتهت المهلة أثناء انتظار uciok',
          _timeout,
        ),
      );

      debugPrint('$_tag: تم استلام uciok');

      // 5. إرسال أمر isready وانتظار readyok
      await _sendIsReady();

      debugPrint('$_tag: المحرك جاهز');
      _setState(EngineState.ready);
      onReady?.call();

      // 6. بدء مراقب المحرك
      _startWatchdog();
    } on BinaryNotFoundException catch (e) {
      _setState(EngineState.error);
      final error = StockfishException(
        'لم يتم العثور على محرك Stockfish. '
        'يرجى تثبيت المحرك أو تضمينه في حزمة التطبيق.\n'
        'التفاصيل: ${e.message}',
        details: e.details,
      );
      onError?.call(error);
      throw error;
    } on EngineTimeoutException {
      _setState(EngineState.error);
      final error = StockfishException(
        'انتهت المهلة أثناء تهيئة المحرك. '
        'قد يكون المحرك غير متوافق مع هذا الجهاز.',
      );
      onError?.call(error);
      rethrow;
    } catch (e) {
      _setState(EngineState.error);
      final error = StockfishException(
        'فشل في تهيئة المحرك: $e',
      );
      onError?.call(error);
      throw error;
    }
  }

  /// يغلق المحرك ويحرر جميع الموارد
  ///
  /// آمن للاستدعاء المتعدد.
  /// يرسل أمر `quit` ثم ينتظر انتهاء العملية.
  /// إذا لم تنتهِ خلال 3 ثوانٍ، يقتلها.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    debugPrint('$_tag: جاري إغلاق المحرك...');

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    // إرسال أمر quit
    try {
      sendCommand('quit');
    } catch (_) {
      // المحرك قد يكون متوقفاً بالفعل
    }

    // الانتظار لانتهاء العملية
    if (_process != null) {
      try {
        final exitCode = await _process!.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () => -1,
        );

        if (exitCode == -1) {
          debugPrint('$_tag: المحرك لم ينتهِ في الوقت المحدد، جاري الإنهاء...');
          _process!.kill(ProcessSignal.sigkill);
        }
      } catch (e) {
        debugPrint('$_tag: خطأ أثناء إغلاق المحرك: $e');
        try {
          _process!.kill(ProcessSignal.sigkill);
        } catch (_) {}
      }
    }

    // إلغاء الاشتراكات
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();

    // إغلاق StreamController
    if (!_responseController.isClosed) {
      await _responseController.close();
    }

    // إكمال أي Completers معلقة
    _completeAllPending(null);

    _setState(EngineState.disposed);
    debugPrint('$_tag: تم إغلاق المحرك');
  }

  // ========================================================================
  // إرسال الأوامر
  // ========================================================================

  /// يرسل أمر UCI إلى المحرك عبر stdin
  ///
  /// يضيف سطر جديد تلقائياً في نهاية الأمر.
  /// يتحقق من أن المحرك يعمل قبل الإرسال.
  @override
  void sendCommand(String command) {
    if (_isDisposed) {
      throw StockfishException('المحرك تم التخلص منه');
    }

    if (_process == null) {
      throw StockfishException('المحرك لم يتم تهيئته');
    }

    debugPrint('$_tag >> $command');

    try {
      _process!.stdin.writeln(command);
      _process!.stdin.flush();
    } catch (e) {
      final error = StockfishException(
        'فشل في إرسال الأمر إلى المحرك: $e',
      );
      onError?.call(error);
      throw error;
    }
  }

  /// يرسل أمر isready وينتظره readyok
  Future<void> _sendIsReady() async {
    _readyokCompleter = Completer<void>();
    sendCommand('isready');

    await _readyokCompleter!.future.timeout(
      _timeout,
      onTimeout: () => throw EngineTimeoutException(
        'انتهت المهلة أثناء انتظار readyok',
        _timeout,
      ),
    );
  }

  // ========================================================================
  // إعداد خيارات المحرك
  // ========================================================================

  /// يضبط عدد الخيوط (Threads) التي يستخدمها المحرك
  ///
  /// [threads] - عدد الخيوط (1-1024). الافتراضي: 1
  /// القيمة المثلى عادة تساوي عدد أنوية المعالج.
  @override
  void setThreads(int threads) {
    if (threads < 1 || threads > 1024) {
      throw ArgumentError('عدد الخيوط يجب أن يكون بين 1 و 1024');
    }
    sendCommand('setoption name Threads value $threads');
  }

  /// يضبط حجم جدول التجزئة (Hash) بالميجابايت
  ///
  /// [sizeMb] - الحجم بالميجابايت (1-33554432). الافتراضي: 16
  /// القيمة المثلى تعتمد على ذاكرة الجهاز.
  /// 128MB جيد للتحليل السريع، 1024MB أو أكثر للتحليل العميق.
  @override
  void setHashSize(int sizeMb) {
    if (sizeMb < 1 || sizeMb > 33554432) {
      throw ArgumentError('حجم التجزئة يجب أن يكون بين 1 و 33554432 ميجابايت');
    }
    sendCommand('setoption name Hash value $sizeMb');
  }

  /// يضبط عدد خطوط اللعب المتعددة (MultiPV)
  ///
  /// [lines] - عدد الخطوط (1-5). الافتراضي: 1
  /// MultiPV = 1 يعطي أفضل حركة فقط.
  /// MultiPV > 1 يعطي أفضل N حركات مع تقييماتها.
  @override
  void setMultiPv(int lines) {
    if (lines < 1 || lines > maxMultiPv) {
      throw ArgumentError('عدد الخطوط يجب أن يكون بين 1 و $maxMultiPv');
    }
    _currentMultiPv = lines;
    sendCommand('setoption name MultiPV value $lines');
  }

  /// يضبط مستوى المهارة (Skill Level) للمحرك
  ///
  /// [level] - المستوى (0-20). الافتراضي: 20
  /// 0 = أسوأ مستوى، 20 = أفضل مستوى
  /// مفيد لخلق تحدي مناسب لمستوى اللاعب
  @override
  void setSkillLevel(int level) {
    if (level < 0 || level > 20) {
      throw ArgumentError('مستوى المهارة يجب أن يكون بين 0 و 20');
    }
    sendCommand('setoption name Skill Level value $level');
  }

  /// يفعل أو يعطل تقييد القوة بالـ ELO
  ///
  /// [enabled] - تفعيل التقييد
  /// يجب تفعيل هذا قبل ضبط ELO
  void setLimitStrength(bool enabled) {
    sendCommand('setoption name UCI_LimitStrength value ${enabled ? 'true' : 'false'}');
  }

  /// يضبط مستوى ELO للمحرك (لوضع اللعب)
  ///
  /// [elo] - مستوى ELO (100-2850). يُستخدم فقط مع UCI_LimitStrength=true
  /// هذا مفيد لضبط صعوبة المحرك لتناسب مستوى اللاعب.
  /// مثال: ELO 1200 = مستوى مبتدئ، ELO 2000 = متقدم
  @override
  void setElo(int elo) {
    if (elo < 100 || elo > 2850) {
      throw ArgumentError('مستوى ELO يجب أن يكون بين 100 و 2850');
    }
    // يجب تفعيل تقييد القوة أولاً
    setLimitStrength(true);
    sendCommand('setoption name UCI_Elo value $elo');
  }

  /// يضبط مسار قواعد Syzygy للنهايات
  ///
  /// [path] - المسار إلى مجلد ملفات Syzygy
  /// قواعد Syzygy تعطي لعباً مثالياً في النهايات
  void setSyzygyPath(String path) {
    sendCommand('setoption name SyzygyPath value $path');
  }

  /// يضبط خيار عام للمحرك
  ///
  /// [name] - اسم الخيار
  /// [value] - القيمة
  @override
  void setOption(String name, String value) {
    sendCommand('setoption name $name value $value');
  }

  /// يمسح جدول التجزئة (Hash) - مفيد بين المباريات
  @override
  void clearHash() {
    sendCommand('setoption name Clear Hash');
  }

  /// يفعل أو يعطل التفكير المسبق (Ponder)
  ///
  /// [enabled] - تفعيل التفكير المسبق
  void setPonder(bool enabled) {
    sendCommand('setoption name Ponder value ${enabled ? 'true' : 'false'}');
  }

  // ========================================================================
  // إعداد الموقف
  // ========================================================================

  /// يضبط الموقف من وضع البداية مع سلسلة حركات
  ///
  /// [moves] - قائمة الحركات بصيغة UCI (مثل: ['e2e4', 'e7e5', 'g1f3'])
  ///
  /// مثال:
  /// ```dart
  /// engine.setPositionFromStart(moves: ['e2e4', 'e7e5', 'g1f3']);
  /// ```
  @override
  void setPositionFromStart({List<String> moves = const []}) {
    if (moves.isEmpty) {
      sendCommand('position startpos');
    } else {
      sendCommand('position startpos moves ${moves.join(' ')}');
    }
    // الموقف الأولي دائماً دور الأبيض
    _isWhiteToMove = moves.isEmpty || moves.length.isEven;
  }

  /// يضبط الموقف من سلسلة FEN
  ///
  /// [fen] - سلسلة FEN الكاملة
  /// [moves] - حركات إضافية بعد الموقف (اختياري)
  ///
  /// مثال:
  /// ```dart
  /// engine.setPositionFromFen(
  ///   'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
  ///   moves: ['e7e5'],
  /// );
  /// ```
  @override
  void setPositionFromFen(String fen, {List<String> moves = const []}) {
    // تحديد من يلعب من FEN
    _isWhiteToMove = fen.contains(' w ');

    if (moves.isEmpty) {
      sendCommand('position fen $fen');
    } else {
      sendCommand('position fen $fen moves ${moves.join(' ')}');
      // تحديث دور اللعب بناءً على عدد الحركات الإضافية
      if (moves.length.isOdd) {
        _isWhiteToMove = !_isWhiteToMove;
      }
    }
  }

  // ========================================================================
  // التحليل واللعب
  // ========================================================================

  /// يبدأ التحليل بعمق محدد
  ///
  /// [depth] - العمق المطلوب (1-50)
  ///
  /// يرجع Future<BestMoveResponse> عند انتهاء التحليل.
  /// يمكن متابعة التحديثات الفورية عبر [onAnalysisUpdate].
  ///
  /// مثال:
  /// ```dart
  /// final bestMove = await engine.analyzeDepth(20);
  /// print('أفضل حركة: ${bestMove.bestMove}');
  /// ```
  @override
  Future<BestMoveResponse> analyzeDepth(int depth) {
    if (_state != EngineState.ready && _state != EngineState.analyzing) {
      throw StockfishException('المحرك ليس جاهزاً للتحليل');
    }

    if (depth < 1 || depth > maxDepth) {
      throw ArgumentError('العمق يجب أن يكون بين 1 و $maxDepth');
    }

    _latestInfoByPv.clear();
    _lastInfoResponse = null;
    _setState(EngineState.analyzing);

    _bestMoveCompleter = Completer<BestMoveResponse>();
    sendCommand('go depth $depth');

    return _bestMoveCompleter!.future;
  }

  /// يبدأ التحليل بوقت محدد بالمللي ثانية
  ///
  /// [timeMs] - الوقت بالمللي ثانية
  ///
  /// مثال:
  /// ```dart
  /// final bestMove = await engine.analyzeTime(5000); // 5 ثوانٍ
  /// ```
  @override
  Future<BestMoveResponse> analyzeTime(int timeMs) {
    if (_state != EngineState.ready && _state != EngineState.analyzing) {
      throw StockfishException('المحرك ليس جاهزاً للتحليل');
    }

    if (timeMs < 1) {
      throw ArgumentError('الوقت يجب أن يكون موجباً');
    }

    _latestInfoByPv.clear();
    _lastInfoResponse = null;
    _setState(EngineState.analyzing);

    _bestMoveCompleter = Completer<BestMoveResponse>();
    sendCommand('go movetime $timeMs');

    return _bestMoveCompleter!.future;
  }

  /// يبدأ التحليل بقيود زمنية كاملة (مثل وضع اللعب)
  ///
  /// المعلمات الزمنية تحاكي وضع اللعب الفعلي مع الساعة الزمنية.
  /// المحرك يقرر بنفسه كم من الوقت يستخدم.
  ///
  /// [wtime] - الوقت المتبقي للأبيض بالمللي ثانية
  /// [btime] - الوقت المتبقي للأسود بالمللي ثانية
  /// [winc] - زيادة الوقت للأبيض بعد كل حركة (بالمللي ثانية)
  /// [binc] - زيادة الوقت للأسود بعد كل حركة (بالمللي ثانية)
  /// [movestogo] - عدد الحركات المتبقية في هذه الفترة (اختياري)
  /// [depth] - الحد الأقصى للعمق (اختياري)
  /// [nodes] - الحد الأقصى للعقد (اختياري)
  @override
  Future<BestMoveResponse> analyzeWithTimeControls({
    int? wtime,
    int? btime,
    int? winc,
    int? binc,
    int? movestogo,
    int? depth,
    int? nodes,
  }) {
    if (_state != EngineState.ready && _state != EngineState.analyzing) {
      throw StockfishException('المحرك ليس جاهزاً للتحليل');
    }

    _latestInfoByPv.clear();
    _lastInfoResponse = null;
    _setState(EngineState.analyzing);

    final parts = <String>['go'];
    if (wtime != null) parts.add('wtime $wtime');
    if (btime != null) parts.add('btime $btime');
    if (winc != null) parts.add('winc $winc');
    if (binc != null) parts.add('binc $binc');
    if (movestogo != null) parts.add('movestogo $movestogo');
    if (depth != null) parts.add('depth $depth');
    if (nodes != null) parts.add('nodes $nodes');

    _bestMoveCompleter = Completer<BestMoveResponse>();
    sendCommand(parts.join(' '));

    return _bestMoveCompleter!.future;
  }

  /// يبدأ تحليلاً غير محدود - يستمر حتى استدعاء [stopAnalysis]
  ///
  /// مفيد للتحليل التفاعلي حيث يريد المستخدم رؤية
  /// التحليل يتحسن بمرور الوقت.
  ///
  /// يجب استدعاء [stopAnalysis] يدوياً لإيقاف التحليل.
  @override
  void analyzeInfinite() {
    if (_state != EngineState.ready && _state != EngineState.analyzing) {
      throw StockfishException('المحرك ليس جاهزاً للتحليل');
    }

    _latestInfoByPv.clear();
    _lastInfoResponse = null;
    _setState(EngineState.analyzing);

    // لا نستخدم Completer لأن التحليل غير محدود
    _bestMoveCompleter = null;
    sendCommand('go infinite');
  }

  /// يوقف التحليل الجاري
  ///
  /// إذا كان هناك تحليل غير محدود جارٍ، يوقفه
  /// ويرجع أفضل حركة وجدها حتى الآن.
  ///
  /// يرجع BestMoveResponse إذا وجد حركة، أو null إذا لم يجد.
  @override
  Future<BestMoveResponse?> stopAnalysis() async {
    if (_state != EngineState.analyzing) return null;

    // إذا كان هناك Completer قيد الانتظار، نستخدمه
    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      sendCommand('stop');
      try {
        return await _bestMoveCompleter!.future.timeout(
          const Duration(seconds: 5),
        );
      } on TimeoutException {
        return null;
      }
    }

    // تحليل غير محدود - نوقفه وننتظر bestmove
    _bestMoveCompleter = Completer<BestMoveResponse>();
    sendCommand('stop');

    try {
      return await _bestMoveCompleter!.future.timeout(
        const Duration(seconds: 5),
      );
    } on TimeoutException {
      _bestMoveCompleter = null;
      _setState(EngineState.ready);
      return null;
    }
  }

  /// يوقف التحليل فوراً دون انتظار النتيجة
  @override
  void stopAnalysisImmediate() {
    if (_state == EngineState.analyzing) {
      sendCommand('stop');
      _bestMoveCompleter = null;
      _setState(EngineState.ready);
    }
  }

  // ========================================================================
  // الاستماع للنتائج
  // ========================================================================

  /// يضبط مستمعي stdout و stderr
  void _setupListeners() {
    // الاستماع لـ stdout - سطر بسطر
    _stdoutSubscription = _process!.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(
          _handleStdoutLine,
          onError: _handleStdoutError,
          onDone: _handleStdoutDone,
          cancelOnError: false,
        );

    // الاستماع لـ stderr
    _stderrSubscription = _process!.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen(
          _handleStderrLine,
          onError: _handleStderrError,
          onDone: _handleStderrDone,
          cancelOnError: false,
        );
  }

  /// يعالج سطراً من stdout
  void _handleStdoutLine(String line) {
    if (_isDisposed) return;
    if (line.trim().isEmpty) return;

    debugPrint('$_tag << $line');

    // تحليل السطر
    final response = UciParser.parseLine(line);

    // إرسال عبر Stream
    if (!_responseController.isClosed) {
      _responseController.add(response);
    }

    // Callback خام
    onRawResponse?.call(response);

    // معالجة حسب النوع
    switch (response.type) {
      case UciResponseType.id:
        _handleIdResponse(response.id!);
        break;
      case UciResponseType.uciok:
        _handleUciOk();
        break;
      case UciResponseType.readyok:
        _handleReadyOk();
        break;
      case UciResponseType.bestmove:
        _handleBestMove(response.bestMove!);
        break;
      case UciResponseType.info:
        _handleInfo(response.info!);
        break;
      case UciResponseType.option:
        _handleOption(response.option!);
        break;
      case UciResponseType.unknown:
        // أسطر غير معروفة - نتجاهلها بصمت
        break;
    }
  }

  /// يعالج استجابة id
  void _handleIdResponse(UciIdResponse id) {
    if (id.name != null) {
      _engineName = id.name;
      debugPrint('$_tag: اسم المحرك: ${id.name}');
    }
    if (id.author != null) {
      _engineAuthor = id.author;
      debugPrint('$_tag: مؤلف المحرك: ${id.author}');
    }
  }

  /// يعالج استجابة uciok
  void _handleUciOk() {
    if (_uciokCompleter != null && !_uciokCompleter!.isCompleted) {
      _uciokCompleter!.complete();
      _uciokCompleter = null;
    }
  }

  /// يعالج استجابة readyok
  void _handleReadyOk() {
    if (_readyokCompleter != null && !_readyokCompleter!.isCompleted) {
      _readyokCompleter!.complete();
      _readyokCompleter = null;
    }
  }

  /// يعالج استجابة bestmove
  void _handleBestMove(BestMoveResponse bestMove) {
    debugPrint('$_tag: أفضل حركة: ${bestMove.bestMove}${bestMove.ponder != null ? ' (ponder: ${bestMove.ponder})' : ''}');

    // إكمال Completer
    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      _bestMoveCompleter!.complete(bestMove);
      _bestMoveCompleter = null;
    }

    // Callback
    onBestMove?.call(bestMove);

    // العودة لحالة الجاهزية
    if (_state == EngineState.analyzing) {
      _setState(EngineState.ready);
    }
  }

  /// يعالج استجابة info
  void _handleInfo(InfoResponse info) {
    _lastInfoResponse = info;

    // تخزين حسب خط MultiPV
    final pvNumber = info.multiPv ?? 1;
    _latestInfoByPv[pvNumber] = info;

    // Callback
    onAnalysisUpdate?.call(info);
  }

  /// يعالج استجابة option
  void _handleOption(OptionResponse option) {
    _options[option.name] = option;
  }

  // ========================================================================
  // معالجة الأخطاء
  // ========================================================================

  /// يعالج سطراً من stderr
  void _handleStderrLine(String line) {
    if (_isDisposed) return;
    if (line.trim().isEmpty) return;

    debugPrint('$_tag [STDERR] $line');

    // بعض المحركات تكتب معلومات تشخيصية في stderr
    // ليست بالضرورة أخطاء
  }

  /// يعالج خطأ في stdout stream
  void _handleStdoutError(Object error) {
    debugPrint('$_tag: خطأ في stdout: $error');
    _handleProcessError(error);
  }

  /// يعالج انتهاء stdout stream
  void _handleStdoutDone() {
    debugPrint('$_tag: انتهى stdout - المحرك توقف');
    if (!_isDisposed) {
      _handleProcessCrash('انتهى stdout بشكل غير متوقع');
    }
  }

  /// يعالج خطأ في stderr stream
  void _handleStderrError(Object error) {
    debugPrint('$_tag: خطأ في stderr: $error');
  }

  /// يعالج انتهاء stderr stream
  void _handleStderrDone() {
    // stderr ينتتهي عادةً مع stdout
  }

  /// يعالج خطأ عام في المحرك
  void _handleProcessError(Object error) {
    if (_isDisposed) return;

    final exception = StockfishException(
      'خطأ في المحرك: $error',
    );
    onError?.call(exception);
  }

  /// يعالج انهيار المحرك
  void _handleProcessCrash(String reason) async {
    if (_isDisposed || _isRestarting) return;
    _isRestarting = true;

    debugPrint('$_tag: انهيار المحرك - $reason');

    _setState(EngineState.error);

    // إكمال أي Completers معلقة بخطأ
    _completeAllPendingWithErrors(reason);

    final exception = EngineCrashException(
      'انهار المحرك: $reason',
    );
    onError?.call(exception);

    // محاولة إعادة التشغيل تلقائياً
    try {
      debugPrint('$_tag: محاولة إعادة تشغيل المحرك...');
      await _restartProcess();
    } catch (e) {
      debugPrint('$_tag: فشلت إعادة التشغيل: $e');
    } finally {
      _isRestarting = false;
    }
  }

  /// يعيد تشغيل عملية المحرك
  Future<void> _restartProcess() async {
    // تنظيف العملية القديمة
    try {
      _process?.kill(ProcessSignal.sigkill);
    } catch (_) {}

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;

    // إعادة التهيئة
    _uciokCompleter = null;
    _readyokCompleter = null;
    _bestMoveCompleter = null;
    _setState(EngineState.uninitialized);

    // محاولة إعادة التشغيل
    await initialize();
  }

  /// يكمل جميع Completers المعلقة بقيمة فارغة
  void _completeAllPending(BestMoveResponse? value) {
    if (_uciokCompleter != null && !_uciokCompleter!.isCompleted) {
      _uciokCompleter!.complete();
      _uciokCompleter = null;
    }
    if (_readyokCompleter != null && !_readyokCompleter!.isCompleted) {
      _readyokCompleter!.complete();
      _readyokCompleter = null;
    }
    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      if (value != null) {
        _bestMoveCompleter!.complete(value);
      } else {
        // لا نكمل بخطأ لأن ذلك سيسبب استثناء غير معالج
        // نتركه يكتمل بـ timeout
      }
      _bestMoveCompleter = null;
    }
  }

  /// يكمل جميع Completers المعلقة بأخطاء
  void _completeAllPendingWithErrors(String reason) {
    if (_uciokCompleter != null && !_uciokCompleter!.isCompleted) {
      _uciokCompleter!.completeError(EngineCrashException(reason));
      _uciokCompleter = null;
    }
    if (_readyokCompleter != null && !_readyokCompleter!.isCompleted) {
      _readyokCompleter!.completeError(EngineCrashException(reason));
      _readyokCompleter = null;
    }
    if (_bestMoveCompleter != null && !_bestMoveCompleter!.isCompleted) {
      _bestMoveCompleter!.completeError(EngineCrashException(reason));
      _bestMoveCompleter = null;
    }
  }

  // ========================================================================
  // مراقب المحرك (Watchdog)
  // ========================================================================

  /// يبدأ مراقب المحرك - يتحقق من أن العملية لا تزال تعمل
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_isDisposed || _process == null) {
        _watchdogTimer?.cancel();
        return;
      }

      // التحقق من أن العملية لا تزال تعمل
      // نرسل isready ونتظر readyok
      if (_state == EngineState.ready) {
        try {
          await _sendIsReady().timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              debugPrint('$_tag: المراقب - المحرك لا يستجيب');
              _handleProcessCrash('المحرك لا يستجيب لـ isready');
            },
          );
        } catch (e) {
          debugPrint('$_tag: المراقب - خطأ: $e');
          _handleProcessCrash('خطأ في المراقب: $e');
        }
      }
    });
  }

  // ========================================================================
  // دوال مساعدة
  // ========================================================================

  /// يحدّث حالة المحرك
  void _setState(EngineState newState) {
    if (_state == newState) return;
    final oldState = _state;
    _state = newState;
    debugPrint('$_tag: تغيرت الحالة: $oldState → $newState');
    onStateChanged?.call(newState);
  }

  /// يضبط المهلة لانتظار استجابات المحرك
  void setTimeout(Duration timeout) {
    _timeout = timeout;
  }

  /// يحصل على معلومات ملخص عن حالة التحليل الحالي
  ///
  /// يرجع خريطة تحتوي على:
  /// - 'depth': العمق الحالي
  /// - 'score': التقييم الحالي (من منظور الأبيض)
  /// - 'nodes': عدد العقد
  /// - 'nps': السرعة
  /// - 'time': الوقت المستغرق
  /// - 'pv': خط اللعب المتوقع
  Map<String, dynamic> getAnalysisSummary() {
    final summary = <String, dynamic>{};

    if (_lastInfoResponse != null) {
      final info = _lastInfoResponse!;
      summary['depth'] = info.depth;
      summary['selDepth'] = info.selDepth;
      summary['nodes'] = info.nodes;
      summary['nps'] = info.nps;
      summary['timeMs'] = info.timeMs;
      summary['pv'] = info.pv;
      summary['multiPv'] = info.multiPv;

      if (info.score != null) {
        final whiteScore = info.score!.fromWhitePerspective(_isWhiteToMove);
        summary['score'] = whiteScore.toDisplayString();
        summary['scoreType'] = whiteScore.type == ScoreType.mate ? 'mate' : 'cp';
        summary['scoreValue'] = whiteScore.value;
      }
    }

    return summary;
  }

  /// يحصل على أفضل N حركات حالية (من MultiPV)
  ///
  /// يرجع قائمة مرتبة تحتوي على معلومات كل خط.
  List<InfoResponse> getTopLines([int count = 1]) {
    final lines = <InfoResponse>[];

    for (int i = 1; i <= count; i++) {
      final info = _latestInfoByPv[i];
      if (info != null) {
        lines.add(info.withWhitePerspectiveScore(_isWhiteToMove));
      }
    }

    return lines;
  }

  /// يحصل على تقييم الموقف الحالي من منظور الأبيض
  EngineScore? getCurrentScore() {
    final info = _latestInfoByPv[1];
    if (info?.score == null) return null;
    return info!.score!.fromWhitePerspective(_isWhiteToMove);
  }

  /// يحصل على سلسلة عرض للتقييم الحالي
  String getCurrentScoreDisplay() {
    final score = getCurrentScore();
    return score?.toArabicDisplayString() ?? '---';
  }

  /// يجبر المحرك على إعادة التفكير (يوقف التحليل الحالي ويبدأ من جديد)
  Future<BestMoveResponse> rethink({
    int? depth,
    int? timeMs,
  }) async {
    // إيقاف أي تحليل جارٍ
    stopAnalysisImmediate();

    // الانتظار قليلاً للتأكد من توقف المحرك
    await Future.delayed(const Duration(milliseconds: 100));

    // التأكد من جاهزية المحرك
    await _sendIsReady();

    // بدء تحليل جديد
    if (depth != null) {
      return analyzeDepth(depth);
    } else if (timeMs != null) {
      return analyzeTime(timeMs);
    } else {
      return analyzeDepth(20); // عمق افتراضي
    }
  }
}

// ============================================================================
// مصنع المحرك (Engine Factory) - مساعد لإنشاء محرك جاهز
// ============================================================================

/// مصنع محرك Stockfish - يسهل إنشاء محرك بإعدادات مسبقة
class StockfishEngineFactory {
  /// ينشئ محركاً للتحليل بأفضل إعدادات
  ///
  /// [threads] - عدد الخيوط (افتراضي: 2)
  /// [hashSizeMb] - حجم التجزئة بالميجابايت (افتراضي: 128)
  /// [multiPv] - عدد خطوط اللعب (افتراضي: 1)
  static Future<StockfishEngine> createAnalyzer({
    int threads = 2,
    int hashSizeMb = 128,
    int multiPv = 1,
    String? binaryPath,
  }) async {
    final engine = StockfishEngine();
    await engine.initialize(binaryPath: binaryPath);

    engine.setThreads(threads);
    engine.setHashSize(hashSizeMb);
    if (multiPv > 1) {
      engine.setMultiPv(multiPv);
    }

    // التأكد من جاهزية المحرك بعد تغيير الإعدادات
    await engine._sendIsReady();

    return engine;
  }

  /// ينشئ محركاً للعب بإعدادات تناسب مستوى اللاعب
  ///
  /// [elo] - مستوى ELO المطلوب (100-2850)
  /// [threads] - عدد الخيوط
  /// [hashSizeMb] - حجم التجزئة
  static Future<StockfishEngine> createPlayer({
    required int elo,
    int threads = 1,
    int hashSizeMb = 64,
    String? binaryPath,
  }) async {
    final engine = StockfishEngine();
    await engine.initialize(binaryPath: binaryPath);

    engine.setThreads(threads);
    engine.setHashSize(hashSizeMb);
    engine.setElo(elo);

    // التأكد من جاهزية المحرك بعد تغيير الإعدادات
    await engine._sendIsReady();

    return engine;
  }

  /// ينشئ محركاً للتحليل المتعمق (للمحترفين)
  ///
  /// يستخدم موارد أكبر للحصول على أفضل تحليل ممكن.
  static Future<StockfishEngine> createDeepAnalyzer({
    int threads = 4,
    int hashSizeMb = 1024,
    int multiPv = 3,
    String? binaryPath,
  }) async {
    final engine = StockfishEngine();
    await engine.initialize(binaryPath: binaryPath);

    engine.setThreads(threads);
    engine.setHashSize(hashSizeMb);
    engine.setMultiPv(multiPv);

    // التأكد من جاهزية المحرك بعد تغيير الإعدادات
    await engine._sendIsReady();

    return engine;
  }
}
