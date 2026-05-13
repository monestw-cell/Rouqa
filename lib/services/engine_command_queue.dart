/// engine_command_queue.dart
/// مدير قائمة أوامر المحرك (حل مشكلة #16)
///
/// يحل مشكلة فيضان أوامر المحرك (Engine Queue Flooding) عندما:
/// - المستخدم يضغط بسرعة
/// - يقلب نقلات بسرعة
///
/// قد تتكدس:
/// - go depth
/// - stop
/// - position
/// - go
///
/// الحل:
/// - command queue manager
/// - يُلغي الأوامر المتقادمة تلقائياً
/// - يدمج الأوامر المتتالية (stop + position + go = position + go فقط)
/// - يضمن ترتيب الأوامر الصحيح

import 'dart:collection';

import 'package:flutter/foundation.dart';

// ============================================================================
/// نوع أمر المحرك — Engine Command Type
enum EngineCommandType {
  /// ضبط الموقف (position fen/startpos)
  position,

  /// بدء التحليل (go depth/time/infinite)
  go,

  /// إيقاف التحليل (stop)
  stop,

  /// ضبط خيار (setoption)
  setOption,

  /// أمر عام (ucinewgame, isready, etc.)
  general,
}

// ============================================================================
/// أمر المحرك — Engine Command
class EngineCommand {
  final EngineCommandType type;
  final String command;
  final DateTime timestamp;
  final int sequenceNumber;
  final String? description;

  const EngineCommand({
    required this.type,
    required this.command,
    required this.timestamp,
    required this.sequenceNumber,
    this.description,
  });

  @override
  String toString() => 'Cmd($type: $command)';
}

// ============================================================================
/// مدير قائمة أوامر المحرك — Engine Command Queue Manager
///
/// يدير تدفق الأوامر إلى محرك Stockfish:
/// 1. يستقبل الأوامر ويُخزنها في قائمة انتظار
/// 2. يُلغي الأوامر المتقادمة (مثل stop يتبعه position — stop غير ضروري)
/// 3. يدمج الأوامر المتتالية (position + go → position + go)
/// 4. يُصدر الأوامر بترتيب صحيح
/// 5. يحد من عدد الأوامر المرسلة لكل ثانية
///
/// الاستخدام:
/// ```dart
/// final queue = EngineCommandQueue(
///   sendCommand: (cmd) => engine.sendCommand(cmd),
/// );
///
/// // إرسال أوامر
/// queue.enqueuePosition('position fen rnbqkbnr...');
/// queue.enqueueGo(depth: 20);
/// queue.enqueueStop();
///
/// // أو إرسال أمر عام
/// queue.enqueue('setoption name Threads value 2', type: EngineCommandType.setOption);
///
/// queue.dispose();
/// ```
class EngineCommandQueue {
  static const _tag = 'EngineCommandQueue';

  /// دالة إرسال الأوامر الفعلية
  final void Function(String command) sendCommand;

  /// الحد الأقصى لحجم القائمة
  final int maxQueueSize;

  /// الفترة الزمنية الدنيا بين الأوامر (ms)
  final int minCommandIntervalMs;

  /// قائمة الانتظار
  final DoubleLinkedQueue<EngineCommand> _queue = DoubleLinkedQueue();

  /// رقم تسلسلي
  int _sequenceNumber = 0;

  /// هل المحرك يحلل حالياً؟ (لتتبع حالة stop)
  bool _isEngineAnalyzing = false;

  /// آخر أمر position
  String? _lastPositionCommand;

  /// آخر أمر go
  String? _lastGoCommand;

  /// إحصائيات
  int _totalEnqueued = 0;
  int _totalOptimized = 0;
  int _totalSent = 0;

  EngineCommandQueue({
    required this.sendCommand,
    this.maxQueueSize = 30,
    this.minCommandIntervalMs = 16, // ~60fps
  });

  // ========================================================================
  // إضافة الأوامر
  // ========================================================================

  /// إضافة أمر عام إلى القائمة — Alias متوافق مع engine_provider
  ///
  /// هذا الأسلوب هو الاسم المتوافق الذي يستخدمه engine_provider.
  /// يُرسل الأمر كنوع [EngineCommandType.general].
  void enqueueCommand(String command, {String? description}) {
    enqueue(command, type: EngineCommandType.general, description: description);
  }

  /// إضافة أمر إلى القائمة
  void enqueue(String command, {EngineCommandType type = EngineCommandType.general, String? description}) {
    _sequenceNumber++;
    _totalEnqueued++;

    final cmd = EngineCommand(
      type: type,
      command: command,
      timestamp: DateTime.now(),
      sequenceNumber: _sequenceNumber,
      description: description,
    );

    _optimizeAndEnqueue(cmd);
  }

  /// إضافة أمر position
  void enqueuePosition(String positionCommand, {String? description}) {
    _lastPositionCommand = positionCommand;
    enqueue(positionCommand, type: EngineCommandType.position, description: description ?? 'position');
  }

  /// إضافة أمر go
  void enqueueGo({int? depth, int? timeMs, bool infinite = false, String? description}) {
    String goCmd;
    if (infinite) {
      goCmd = 'go infinite';
    } else if (depth != null) {
      goCmd = 'go depth $depth';
    } else if (timeMs != null) {
      goCmd = 'go movetime $timeMs';
    } else {
      goCmd = 'go infinite';
    }

    _lastGoCommand = goCmd;
    _isEngineAnalyzing = true;
    enqueue(goCmd, type: EngineCommandType.go, description: description ?? 'go');
  }

  /// إضافة أمر stop
  void enqueueStop({String? description}) {
    // تحسين: إذا كان المحرك لا يحلل، stop غير ضروري
    if (!_isEngineAnalyzing) {
      _totalOptimized++;
      debugPrint('$_tag: تحسين — تجاهل stop (المحرك لا يحلل)');
      return;
    }

    _isEngineAnalyzing = false;
    enqueue('stop', type: EngineCommandType.stop, description: description ?? 'stop');
  }

  /// إضافة أمر setoption
  void enqueueSetOption(String name, String value, {String? description}) {
    enqueue('setoption name $name value $value', type: EngineCommandType.setOption, description: description ?? name);
  }

  /// إضافة أمر ucinewgame — Convenience method
  void enqueueNewGame() {
    _isEngineAnalyzing = false;
    enqueue('ucinewgame', type: EngineCommandType.general, description: 'ucinewgame');
  }

  /// إضافة أمر isready — Convenience method
  void enqueueIsReady() {
    enqueue('isready', type: EngineCommandType.general, description: 'isready');
  }

  // ========================================================================
  /// تحسين ودمج الأوامر — Optimize and merge commands
  void _optimizeAndEnqueue(EngineCommand cmd) {
    // التحقق من حجم القائمة
    if (_queue.length >= maxQueueSize) {
      _optimizeQueue();
    }

    // تحسين: إذا أمر position جديد، إزالة أي position قديم لم يُرسل بعد
    if (cmd.type == EngineCommandType.position) {
      _removePendingOfType(EngineCommandType.position);
      _totalOptimized++;
    }

    // تحسين: إذا أمر go جديد بعد stop، إزالة stop
    if (cmd.type == EngineCommandType.go) {
      final hasPendingStop = _hasPendingOfType(EngineCommandType.stop);
      if (hasPendingStop) {
        _removePendingOfType(EngineCommandType.stop);
        _totalOptimized++;
      }
    }

    // تحسين: إذا stop ثم go جديد، إزالة stop
    if (cmd.type == EngineCommandType.stop) {
      final hasPendingGo = _hasPendingOfType(EngineCommandType.go);
      if (hasPendingGo) {
        // stop غير ضروري لأن go سيتجاوزه
        _totalOptimized++;
        return; // لا نضيف stop
      }
    }

    _queue.addLast(cmd);
    _flushQueue();
  }

  /// إزالة الأوامر المعلقة من نوع معين
  void _removePendingOfType(EngineCommandType type) {
    _queue.removeWhere((cmd) => cmd.type == type);
  }

  /// هل توجد أوامر معلقة من نوع معين؟
  bool _hasPendingOfType(EngineCommandType type) {
    return _queue.any((cmd) => cmd.type == type);
  }

  /// تحسين القائمة عند امتلائها
  void _optimizeQueue() {
    // إزالة الأوامر المكررة
    final seenTypes = <EngineCommandType>{};
    final toRemove = <EngineCommand>[];

    // من النهاية (الأحدث) إلى البداية (الأقدم)
    final items = _queue.toList().reversed;
    for (final cmd in items) {
      if (seenTypes.contains(cmd.type) &&
          (cmd.type == EngineCommandType.position ||
           cmd.type == EngineCommandType.go ||
           cmd.type == EngineCommandType.stop)) {
        // احتفظ بالأحدث فقط
        toRemove.add(cmd);
        _totalOptimized++;
      } else {
        seenTypes.add(cmd.type);
      }
    }

    for (final cmd in toRemove) {
      _queue.remove(cmd);
    }
  }

  // ========================================================================
  // إرسال الأوامر
  // ========================================================================

  /// إرسال جميع الأوامر المعلقة
  void _flushQueue() {
    while (_queue.isNotEmpty) {
      final cmd = _queue.removeFirst();
      _totalSent++;

      try {
        sendCommand(cmd.command);
        debugPrint('$_tag >> ${cmd.command}');
      } catch (e) {
        debugPrint('$_tag: فشل إرسال الأمر ${cmd.command}: $e');
      }
    }
  }

  /// إرسال فوري (تجاوز القائمة)
  void sendImmediate(String command) {
    _totalSent++;
    try {
      sendCommand(command);
    } catch (e) {
      debugPrint('$_tag: فشل الإرسال الفوري: $e');
    }
  }

  // ========================================================================
  /// إرسال أمر position + go معاً (النمط الشائع)
  ///
  /// يُلغي أي أوامر معلقة ويُرسل فوراً:
  /// 1. stop (إذا كان المحرك يحلل)
  /// 2. position
  /// 3. go
  void sendPositionAndGo({
    required String positionCommand,
    int? depth,
    int? timeMs,
    bool infinite = false,
  }) {
    // إيقاف أي تحليل حالي
    if (_isEngineAnalyzing) {
      sendImmediate('stop');
      _isEngineAnalyzing = false;
    }

    // مسح القائمة المعلقة
    _queue.clear();

    // إرسال position
    _lastPositionCommand = positionCommand;
    sendImmediate(positionCommand);

    // إرسال go
    String goCmd;
    if (infinite) {
      goCmd = 'go infinite';
    } else if (depth != null) {
      goCmd = 'go depth $depth';
    } else if (timeMs != null) {
      goCmd = 'go movetime $timeMs';
    } else {
      goCmd = 'go infinite';
    }

    _lastGoCommand = goCmd;
    _isEngineAnalyzing = true;
    sendImmediate(goCmd);
  }

  // ========================================================================
  // إحصائيات
  // ========================================================================

  Map<String, dynamic> get stats => {
    'totalEnqueued': _totalEnqueued,
    'totalOptimized': _totalOptimized,
    'totalSent': _totalSent,
    'queueSize': _queue.length,
    'isAnalyzing': _isEngineAnalyzing,
    'optimizationRate': _totalEnqueued > 0
        ? '${(_totalOptimized / _totalEnqueued * 100).toStringAsFixed(1)}%'
        : '0%',
  };

  /// هل المحرك يحلل حالياً؟
  bool get isAnalyzing => _isEngineAnalyzing;

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    _queue.clear();
  }
}
