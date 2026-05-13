/// engine_provider.dart
/// مزود المحرك — Engine State Provider
///
/// إدارة تهيئة وإغلاق محرك Stockfish، إرسال الأوامر، ومعالجة ردود المحرك.
/// تم فصل هذا عن analysis_provider لتقليل التعقيد وتحسين قابلية الصيانة.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/stockfish_engine.dart';
import '../engine/stockfish_package_engine.dart';
import '../engine/chess_engine_interface.dart';
import '../engine/uci_protocol.dart';
import '../services/engine_command_queue.dart';
import '../services/engine_fallback_service.dart';
import '../services/thermal_monitor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// حالة المحرك — Engine State
// ═══════════════════════════════════════════════════════════════════════════

/// حالة المحرك
class EngineProviderState {
  /// هل المحرك جاهز؟
  final bool isReady;

  /// هل المحرك يحلل حالياً؟
  final bool isAnalyzing;

  /// خطوط MultiPV من المحرك
  final List<EngineLine> engineLines;

  /// التقييم من وجهة نظر الأبيض (centipawns)
  final int? evalScore;

  /// أفضل حركة من المحرك (UCI)
  final String? bestMove;

  /// رسالة الخطأ
  final String? errorMessage;

  /// وضع المحرك (حزمة / عملية / احتياطي)
  final String engineMode;

  const EngineProviderState({
    this.isReady = false,
    this.isAnalyzing = false,
    this.engineLines = const [],
    this.evalScore,
    this.bestMove,
    this.errorMessage,
    this.engineMode = 'none',
  });

  EngineProviderState copyWith({
    bool? isReady,
    bool? isAnalyzing,
    List<EngineLine>? engineLines,
    int? Function()? evalScore,
    String? Function()? bestMove,
    String? Function()? errorMessage,
    String? engineMode,
  }) {
    return EngineProviderState(
      isReady: isReady ?? this.isReady,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      engineLines: engineLines ?? this.engineLines,
      evalScore: evalScore != null ? evalScore() : this.evalScore,
      bestMove: bestMove != null ? bestMove() : this.bestMove,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      engineMode: engineMode ?? this.engineMode,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مُخطر المحرك — Engine Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// مُخطر حالة المحرك — Manages the chess engine lifecycle
class EngineNotifier extends StateNotifier<EngineProviderState> {
  static const _tag = 'EngineNotifier';

  /// محرك الشطرنج
  ChessEngine? _engine;

  /// مدير قائمة الأوامر
  EngineCommandQueue? _commandQueue;

  /// خدمة المحرك الاحتياطي
  final EngineFallbackService _fallbackService = EngineFallbackService();

  /// مراقب الحرارة
  final ThermalMonitor _thermalMonitor = ThermalMonitor();

  /// مؤقت إعادة المحاولة
  Timer? _retryTimer;

  /// اشتراك في تحديثات المحرك
  StreamSubscription<UciResponse>? _engineSubscription;

  EngineNotifier() : super(const EngineProviderState()) {
    _initializeEngine();
  }

  /// الحصول على المحرك (للاستخدام الداخلي فقط)
  ChessEngine? get engine => _engine;

  /// الحصول على مدير الأوامر
  EngineCommandQueue? get commandQueue => _commandQueue;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _engineSubscription?.cancel();
    _thermalMonitor.dispose();
    _fallbackService.dispose();
    _commandQueue?.dispose();
    _engine?.dispose();
    super.dispose();
  }

  // ─── تهيئة المحرك — Engine Initialization ───────────────────────────

  /// تهيئة المحرك مع ثلاث محاولات
  Future<void> _initializeEngine() async {
    // المحاولة الأولى: محرك الحزمة
    if (await _tryPackageEngine()) return;

    // المحاولة الثانية: محرك العملية
    if (await _tryProcessEngine()) return;

    // المحاولة الثالثة: خدمة الاحتياطي
    if (await _tryFallbackEngine()) return;

    // فشلت جميع المحاولات
    state = state.copyWith(
      isReady: false,
      errorMessage: () => 'فشل تهيئة المحرك بجميع الطرق',
    );

    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), _initializeEngine);
  }

  Future<bool> _tryPackageEngine() async {
    try {
      _logEngine('محاولة تشغيل محرك الحزمة...');
      final packageEngine = StockfishPackageEngine();
      _bindEngineCallbacks(packageEngine);
      await packageEngine.initialize().timeout(const Duration(seconds: 15));
      packageEngine.setMultiPv(3);
      packageEngine.setThreads(2);
      packageEngine.setHashSize(128);
      _engine = packageEngine;
      _setupEngineDependencies();
      state = state.copyWith(isReady: true, engineMode: 'package');
      _logEngine('تمت تهيئة محرك الحزمة بنجاح!');
      return true;
    } catch (e) {
      _logEngine('فشل محرك الحزمة: $e');
      return false;
    }
  }

  Future<bool> _tryProcessEngine() async {
    try {
      _logEngine('محاولة تشغيل محرك Process...');
      final processEngine = StockfishEngine();
      _bindEngineCallbacks(processEngine);
      await processEngine.initialize();
      processEngine.setMultiPv(3);
      processEngine.setThreads(2);
      processEngine.setHashSize(128);
      _engine = processEngine;
      _setupEngineDependencies();
      state = state.copyWith(isReady: true, engineMode: 'process');
      _logEngine('تمت تهيئة محرك Process بنجاح');
      return true;
    } catch (e) {
      _logEngine('فشل محرك Process: $e');
      return false;
    }
  }

  Future<bool> _tryFallbackEngine() async {
    try {
      _logEngine('محاولة خدمة الاحتياطي...');
      final fallbackEngine = await _fallbackService.startWithFallback();
      if (fallbackEngine != null) {
        _bindEngineCallbacks(fallbackEngine);
        _engine = fallbackEngine;
        _setupEngineDependencies();
        state = state.copyWith(
          isReady: true,
          engineMode: 'fallback-${_fallbackService.currentMode.name}',
        );
        _logEngine('تم تشغيل المحرك في الوضع الاحتياطي');
        return true;
      }
    } catch (e) {
      _logEngine('فشلت خدمة الاحتياطي: $e');
    }
    return false;
  }

  /// ربط callbacks المحرك
  void _bindEngineCallbacks(ChessEngine engine) {
    engine.onAnalysisUpdate = _handleAnalysisUpdate;
    engine.onBestMove = _handleBestMove;
    engine.onReady = () => state = state.copyWith(isReady: true);
    engine.onError = (error) => state = state.copyWith(errorMessage: () => error.message);
    engine.onStateChanged = (engineState) {
      final isReady = engineState == EngineState.ready;
      final isAnalyzing = engineState == EngineState.analyzing;
      state = state.copyWith(isReady: isReady, isAnalyzing: isAnalyzing);
    };
  }

  /// إعداد التبعيات المتعلقة بالمحرك
  void _setupEngineDependencies() {
    _commandQueue = EngineCommandQueue(
      sendCommand: (cmd) {
        try {
          _engine?.sendCommand(cmd);
        } catch (_) {}
      },
    );

    _thermalMonitor.start();
    _thermalMonitor.onRecommendationChanged = (recommendation, report) {
      _handleThermalRecommendation(recommendation);
    };
  }

  void _logEngine(String message) => debugPrint('$_tag: $message');

  // ─── معالجات أحداث المحرك — Engine Event Handlers ───────────────────

  void _handleAnalysisUpdate(InfoResponse info) {
    // سيتم تحديث الحالة عبر analysis_provider
  }

  void _handleBestMove(BestMoveResponse bestMove) {
    final uci = bestMove.bestMove;
    if (uci.length >= 4) {
      state = state.copyWith(bestMove: () => uci);
    }
  }

  void _handleThermalRecommendation(ThermalRecommendation recommendation) {
    if (_engine == null || !_engine!.isReady) return;

    switch (recommendation) {
      case ThermalRecommendation.fullAnalysis:
        _engine!.setMultiPv(3);
        _engine!.setThreads(2);
        _engine!.setHashSize(128);
      case ThermalRecommendation.moderateAnalysis:
        _engine!.setMultiPv(2);
        _engine!.setThreads(1);
        _engine!.setHashSize(64);
      case ThermalRecommendation.reduceAnalysis:
        _engine!.setMultiPv(1);
        _engine!.setThreads(1);
        _engine!.setHashSize(32);
      case ThermalRecommendation.pauseAnalysis:
        if (_engine!.isAnalyzing) {
          _engine!.stopAnalysisImmediate();
        }
        state = state.copyWith(
          errorMessage: () => 'تم إيقاف التحليل بسبب حرارة الجهاز العالية',
        );
    }
  }

  // ─── أوامر المحرك — Engine Commands ─────────────────────────────────

  /// بدء التحليل التفاعلي
  void startInteractiveAnalysis(String positionCommand, {bool infinite = true}) {
    if (_engine == null || !_engine!.isReady) return;

    if (_commandQueue != null) {
      _commandQueue!.enqueueSetOption('MultiPV', '3');
      _commandQueue!.enqueuePosition(positionCommand);
      _commandQueue!.enqueueGo(infinite: infinite);
    } else {
      _engine!.setMultiPv(3);
      _engine!.sendCommand(positionCommand);
      _engine!.analyzeInfinite();
    }

    state = state.copyWith(isAnalyzing: true);
  }

  /// إيقاف التحليل
  Future<void> stopAnalysis() async {
    try {
      if (_commandQueue != null) {
        _commandQueue!.enqueueStop();
      } else if (_engine != null && _engine!.isAnalyzing) {
        await _engine!.stopAnalysis().timeout(const Duration(seconds: 3));
      }
    } catch (_) {
      _engine?.stopAnalysisImmediate();
    }

    state = state.copyWith(isAnalyzing: false);
  }

  /// إيقاف فوري
  void stopAnalysisImmediate() {
    _engine?.stopAnalysisImmediate();
    state = state.copyWith(isAnalyzing: false);
  }

  /// إرسال أمر مباشر للمحرك عبر قائمة الأوامر
  void sendCommand(String command) {
    if (_commandQueue != null) {
      _commandQueue!.enqueueCommand(command);
    } else {
      try {
        _engine?.sendCommand(command);
      } catch (_) {}
    }
  }

  /// ضبط خيار المحرك عبر قائمة الأوامر
  void setOption(String name, String value) {
    if (_commandQueue != null) {
      _commandQueue!.enqueueSetOption(name, value);
    } else {
      try {
        _engine?.sendCommand('setoption name $name value $value');
      } catch (_) {}
    }
  }

  /// بدء لعبة جديدة (ucinewgame) — يُرسل عبر قائمة الأوامر
  void newGame() {
    if (_commandQueue != null) {
      _commandQueue!.enqueueStop();
      _commandQueue!.enqueueNewGame();
      _commandQueue!.enqueueIsReady();
    } else {
      try {
        _engine?.stopAnalysisImmediate();
        _engine?.sendCommand('ucinewgame');
        _engine?.sendCommand('isready');
      } catch (_) {}
    }
  }

  /// ضبط إعدادات المحرك بناءً على التوصية الحرارية
  void applyThermalProfile(ThermalRecommendation recommendation) {
    _handleThermalRecommendation(recommendation);
  }
}

/// مزود حالة المحرك
final engineProvider = StateNotifierProvider<EngineNotifier, EngineProviderState>(
  (ref) => EngineNotifier(),
);
