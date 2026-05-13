/// engine_isolate.dart
/// تشغيل محرك Stockfish في Isolate منفصل (إصلاح #5)
///
/// يحل مشكلة تجميد واجهة المستخدم أثناء التحليل
/// بفصل محرك الشطرنج عن UI isolate تماماً.
///
/// كيف يحلها ChessIs:
/// - BackgroundAnalysisService منفصل تماماً عن UI
/// - التواصل عبر SendPort/ReceivePort
///
/// في Flutter:
/// - لا نضع stdout.listen في UI isolate مباشرة
/// - بل نستخدم Engine Isolate مع SendPort/ReceivePort

import 'dart:async';
import 'dart:isolate';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'stockfish_engine.dart';
import 'uci_protocol.dart';

// ============================================================================
// رسائل التواصل بين Isolates
// ============================================================================

/// رسالة من Main → Engine Isolate
sealed class EngineCommand {
  const EngineCommand();
}

/// أمر: تهيئة المحرك
class CmdInitialize extends EngineCommand {
  final String? binaryPath;
  const CmdInitialize({this.binaryPath});
}

/// أمر: ضبط الموقف من FEN
class CmdSetPositionFen extends EngineCommand {
  final String fen;
  final List<String> moves;
  const CmdSetPositionFen(this.fen, {this.moves = const []});
}

/// أمر: ضبط الموقف من البداية
class CmdSetPositionStart extends EngineCommand {
  final List<String> moves;
  const CmdSetPositionStart({this.moves = const []});
}

/// أمر: بدء التحليل بعمق
class CmdAnalyzeDepth extends EngineCommand {
  final int depth;
  const CmdAnalyzeDepth(this.depth);
}

/// أمر: بدء التحليل بوقت
class CmdAnalyzeTime extends EngineCommand {
  final int timeMs;
  const CmdAnalyzeTime(this.timeMs);
}

/// أمر: تحليل غير محدود
class CmdAnalyzeInfinite extends EngineCommand {
  const CmdAnalyzeInfinite();
}

/// أمر: إيقاف التحليل
class CmdStopAnalysis extends EngineCommand {
  const CmdStopAnalysis();
}

/// أمر: ضبط خيار
class CmdSetOption extends EngineCommand {
  final String name;
  final String value;
  const CmdSetOption(this.name, this.value);
}

/// أمر: ضبط MultiPV
class CmdSetMultiPv extends EngineCommand {
  final int lines;
  const CmdSetMultiPv(this.lines);
}

/// أمر: ضبط Threads
class CmdSetThreads extends EngineCommand {
  final int threads;
  const CmdSetThreads(this.threads);
}

/// أمر: ضبط Hash
class CmdSetHash extends EngineCommand {
  final int sizeMb;
  const CmdSetHash(this.sizeMb);
}

/// أمر: إغلاق المحرك
class CmdDispose extends EngineCommand {
  const CmdDispose();
}

/// أمر: إيقاف مؤقت (أثناء السحب)
class CmdPause extends EngineCommand {
  const CmdPause();
}

/// أمر: استئناف (بعد السحب)
class CmdResume extends EngineCommand {
  const CmdResume();
}

// ============================================================================
// رسائل من Engine Isolate → Main
// ============================================================================

/// رسالة من Engine Isolate → Main
sealed class EngineEvent {
  const EngineEvent();
}

/// حدث: تحديث تحليل جديد
class EventAnalysisUpdate extends EngineEvent {
  final InfoResponse info;
  const EventAnalysisUpdate(this.info);
}

/// حدث: أفضل حركة
class EventBestMove extends EngineEvent {
  final BestMoveResponse bestMove;
  const EventBestMove(this.bestMove);
}

/// حدث: المحرك جاهز
class EventReady extends EngineEvent {
  const EventReady();
}

/// حدث: خطأ
class EventError extends EngineEvent {
  final String message;
  final String? details;
  const EventError(this.message, {this.details});
}

/// حدث: تغير حالة المحرك
class EventStateChanged extends EngineEvent {
  final EngineState state;
  const EventStateChanged(this.state);
}

/// حدث: المحرك توقف (crash)
class EventEngineCrashed extends EngineEvent {
  final int? exitCode;
  const EventEngineCrashed({this.exitCode});
}

// ============================================================================
// Engine Isolate — محرك في Isolate منفصل
// ============================================================================

/// تشغيل محرك Stockfish في Isolate منفصل عن UI
///
/// الاستخدام:
/// ```dart
/// final engineIsolate = EngineIsolate();
/// await engineIsolate.start();
///
/// // الاستماع للأحداث
/// engineIsolate.events.listen((event) {
///   if (event is EventAnalysisUpdate) { ... }
///   if (event is EventBestMove) { ... }
/// });
///
/// // إرسال الأوامر
/// engineIsolate.send(const CmdInitialize());
/// engineIsolate.send(const CmdSetMultiPv(3));
/// engineIsolate.send(CmdSetPositionFen('rnbqkbnr/...'));
/// engineIsolate.send(const CmdAnalyzeDepth(20));
///
/// // إيقاف مؤقت أثناء السحب
/// engineIsolate.send(const CmdPause());
///
/// // استئناف بعد السحب
/// engineIsolate.send(const CmdResume());
///
/// // إغلاق
/// await engineIsolate.stop();
/// ```
class EngineIsolate {
  static const _tag = 'EngineIsolate';

  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription? _subscription;

  final StreamController<EngineEvent> _eventController =
      StreamController<EngineEvent>.broadcast();

  bool _isRunning = false;
  bool _isPaused = false;

  /// تدفق الأحداث من المحرك
  Stream<EngineEvent> get events => _eventController.stream;

  /// هل المحرك يعمل؟
  bool get isRunning => _isRunning;

  /// هل المحرك متوقف مؤقتاً؟
  bool get isPaused => _isPaused;

  /// بدء Engine Isolate
  Future<void> start() async {
    if (_isRunning) return;

    _receivePort = ReceivePort();

    try {
      _isolate = await Isolate.spawn(
        _engineIsolateEntryPoint,
        _receivePort!.sendPort,
        debugName: 'StockfishEngine',
      );

      // انتظار SendPort من الـ Isolate
      final completer = Completer<SendPort>();
      _subscription = _receivePort!.listen((message) {
        if (message is SendPort && !completer.isCompleted) {
          completer.complete(message);
        } else if (message is EngineEvent) {
          if (!_eventController.isClosed) {
            _eventController.add(message);
          }
        }
      });

      _sendPort = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Engine isolate timed out'),
      );

      _isRunning = true;
      debugPrint('$_tag: Engine Isolate بدأ بنجاح');
    } catch (e) {
      debugPrint('$_tag: فشل بدء Engine Isolate: $e');
      // إذا فشل Isolate، نستخدم المحرك مباشرة في الـ main isolate
      // هذا حل بديل للمنصات التي لا تدعم Isolate.spawn
      _isRunning = false;
      rethrow;
    }
  }

  /// إرسال أمر إلى Engine Isolate
  void send(EngineCommand command) {
    if (_sendPort == null) {
      debugPrint('$_tag: Engine Isolate ليس جاهزاً');
      return;
    }
    _sendPort!.send(command);
  }

  /// إيقاف مؤقت للمحرك (أثناء السحب)
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    send(const CmdPause());
  }

  /// استئناف المحرك (بعد السحب)
  void resume() {
    if (!_isPaused) return;
    _isPaused = false;
    send(const CmdResume());
  }

  /// إيقاف Engine Isolate
  Future<void> stop() async {
    if (!_isRunning) return;

    // إرسال أمر الإغلاق
    try {
      send(const CmdDispose());
      await Future<void>.delayed(const Duration(milliseconds: 500));
    } catch (_) {}

    // إغلاق Isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;

    // إلغاء الاشتراك
    await _subscription?.cancel();
    _subscription = null;

    // إغلاق ReceivePort
    _receivePort?.close();
    _receivePort = null;

    // إغلاق StreamController
    if (!_eventController.isClosed) {
      await _eventController.close();
    }

    _sendPort = null;
    _isRunning = false;
    _isPaused = false;

    debugPrint('$_tag: Engine Isolate تم إيقافه');
  }

  /// تحرير الموارد
  void dispose() {
    stop();
  }
}

// ============================================================================
// نقطة دخول Engine Isolate
// ============================================================================

/// نقطة دخول Isolate المحرك — تعمل في Isolate منفصل
///
/// هذه الدالة تعمل في isolate منفصل وتتواصل مع الـ main isolate
/// عبر SendPort/ReceivePort.
void _engineIsolateEntryPoint(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  StockfishEngine? engine;
  StreamSubscription? engineSubscription;
  bool isPaused = false;
  String? pendingPosition; // FEN أو startpos
  List<String> pendingMoves = [];
  String? pendingGoCommand; // أمر go الذي كان جارياً

  // الاستماع للأوامر من الـ main isolate
  receivePort.listen((message) {
    if (message is! EngineCommand) return;

    switch (message) {
      case CmdInitialize(:final binaryPath):
        _handleInitialize(
          engine: engine,
          mainSendPort: mainSendPort,
          binaryPath: binaryPath,
          onEngineCreated: (e) {
            engine = e;
            // الاستماع لتحديثات المحرك
            engineSubscription?.cancel();
            engineSubscription = e!.responses.listen((response) {
              switch (response.type) {
                case UciResponseType.info:
                  if (response.info != null) {
                    mainSendPort.send(EventAnalysisUpdate(response.info!));
                  }
                  break;
                case UciResponseType.bestmove:
                  if (response.bestMove != null) {
                    mainSendPort.send(EventBestMove(response.bestMove!));
                  }
                  break;
                default:
                  break;
              }
            });

            e.onStateChanged = (state) {
              mainSendPort.send(EventStateChanged(state));
            };

            e.onError = (error) {
              mainSendPort.send(EventError(error.message, details: error.details));
            };
          },
        );
        break;

      case CmdSetPositionFen(:final fen, :final moves):
        if (engine != null && engine!.isReady) {
          engine!.setPositionFromFen(fen, moves: moves);
        }
        if (isPaused) {
          pendingPosition = 'fen';
          pendingMoves = moves; // لا يمكننا تخزين FEN بدون مرجع
        }
        break;

      case CmdSetPositionStart(:final moves):
        if (engine != null && engine!.isReady) {
          engine!.setPositionFromStart(moves: moves);
        }
        if (isPaused) {
          pendingPosition = 'startpos';
          pendingMoves = moves;
        }
        break;

      case CmdAnalyzeDepth(:final depth):
        if (engine != null && engine!.isReady && !isPaused) {
          engine!.analyzeDepth(depth);
        } else if (isPaused) {
          pendingGoCommand = 'depth $depth';
        }
        break;

      case CmdAnalyzeTime(:final timeMs):
        if (engine != null && engine!.isReady && !isPaused) {
          engine!.analyzeTime(timeMs);
        } else if (isPaused) {
          pendingGoCommand = 'movetime $timeMs';
        }
        break;

      case CmdAnalyzeInfinite():
        if (engine != null && engine!.isReady && !isPaused) {
          engine!.analyzeInfinite();
        } else if (isPaused) {
          pendingGoCommand = 'infinite';
        }
        break;

      case CmdStopAnalysis():
        if (engine != null && engine!.isAnalyzing) {
          engine!.stopAnalysisImmediate();
        }
        break;

      case CmdSetOption(:final name, :final value):
        if (engine != null && engine!.isReady) {
          engine!.setOption(name, value);
        }
        break;

      case CmdSetMultiPv(:final lines):
        if (engine != null && engine!.isReady) {
          engine!.setMultiPv(lines);
        }
        break;

      case CmdSetThreads(:final threads):
        if (engine != null && engine!.isReady) {
          engine!.setThreads(threads);
        }
        break;

      case CmdSetHash(:final sizeMb):
        if (engine != null && engine!.isReady) {
          engine!.setHashSize(sizeMb);
        }
        break;

      case CmdPause():
        isPaused = true;
        if (engine != null && engine!.isAnalyzing) {
          engine!.stopAnalysisImmediate();
        }
        break;

      case CmdResume():
        if (!isPaused) break;
        isPaused = false;
        // لا نستأنف التحليل تلقائياً - نترك الـ main يقرر
        break;

      case CmdDispose():
        engineSubscription?.cancel();
        engine?.dispose();
        engine = null;
        receivePort.close();
        break;
    }
  });
}

/// تهيئة المحرك داخل الـ Isolate
void _handleInitialize({
  required StockfishEngine? engine,
  required SendPort mainSendPort,
  required String? binaryPath,
  required void Function(StockfishEngine?) onEngineCreated,
}) {
  if (engine != null && engine.isReady) {
    mainSendPort.send(const EventReady());
    return;
  }

  engine ??= StockfishEngine();

  engine.initialize(binaryPath: binaryPath).then((_) {
    onEngineCreated(engine);
    mainSendPort.send(const EventReady());
  }).catchError((e) {
    mainSendPort.send(EventError(
      'فشل تهيئة المحرك: $e',
    ));
  });
}
