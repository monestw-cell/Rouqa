/// training_session_controller.dart
/// متحكم جلسة التدريب المعزول (حل مشكلة #15)
///
/// يحل مشكلة مزامنة وضع التدريب:
/// - position mismatch
/// - stale engine line
/// - wrong expected move
///
/// الحل:
/// - training يحتاج isolated session controller
/// - كل جلسة تدريب لها session خاص
/// - لا تتداخل مع التحليل الرئيسي

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/stockfish_engine.dart';
import '../engine/uci_protocol.dart';
import '../models/chess_models.dart';
import '../services/analysis_session_manager.dart';

// ============================================================================
/// حالة جلسة التدريب — Training Session State
enum TrainingSessionState {
  /// غير نشطة
  idle,

  /// جاري التحميل
  loading,

  /// جاري التدريب
  active,

  /// توقف مؤقت
  paused,

  /// مكتملة
  completed,

  /// خطأ
  error,
}

// ============================================================================
/// خطوة تدريب — Training Step
class TrainingStep {
  /// الفهرس في قائمة الحركات
  final int moveIndex;

  /// الموقف قبل الحركة (FEN)
  final String fenBefore;

  /// الموقف بعد الحركة (FEN)
  final String fenAfter;

  /// الحركة المتوقعة (UCI)
  final String expectedUci;

  /// الحركة المتوقعة (SAN)
  final String expectedSan;

  /// بدائل المحرك
  final List<EngineLine> alternatives;

  /// تقييم الموقف قبل الحركة
  final int evalBefore;

  /// تقييم الموقف بعد الحركة
  final int evalAfter;

  /// تصنيف الحركة المتوقعة
  final MoveClassification expectedClassification;

  /// هل المستخدم أدى الحركة الصحيحة؟
  bool userCorrect = false;

  /// حركة المستخدم الفعلية (إن أخطأ)
  String? userActualUci;

  TrainingStep({
    required this.moveIndex,
    required this.fenBefore,
    required this.fenAfter,
    required this.expectedUci,
    required this.expectedSan,
    this.alternatives = const [],
    this.evalBefore = 0,
    this.evalAfter = 0,
    this.expectedClassification = MoveClassification.best,
  });
}

// ============================================================================
/// نتيجة جلسة التدريب — Training Session Result
class TrainingSessionResult {
  /// إجمالي الخطوات
  final int totalSteps;

  /// الخطوات الصحيحة
  final int correctSteps;

  /// الخطوات الخاطئة
  final int wrongSteps;

  /// نسبة النجاح
  final double successRate;

  /// متوسط زمن الاستجابة
  final Duration averageResponseTime;

  const TrainingSessionResult({
    this.totalSteps = 0,
    this.correctSteps = 0,
    this.wrongSteps = 0,
    this.successRate = 0.0,
    this.averageResponseTime = Duration.zero,
  });
}

// ============================================================================
/// متحكم جلسة التدريب — Training Session Controller
///
/// يدير جلسة تدريب معزولة عن التحليل الرئيسي:
/// - له session token خاص
/// - لا يتداخل مع analysis_provider
/// - يوفر بيانات دقيقة عن الموقف الحالي
/// - يتحقق من صحة حركات المستخدم
///
/// الاستخدام:
/// ```dart
/// final controller = TrainingSessionController(engine: engine);
///
/// // بدء جلسة تدريب
/// await controller.startSession(moves, startIndex: 0);
///
/// // الحصول على الخطوة الحالية
/// final step = controller.currentStep;
///
/// // التحقق من حركة المستخدم
/// final isCorrect = controller.checkMove('e2e4');
///
/// // الانتقال للخطوة التالية
/// controller.nextStep();
///
/// // إنهاء الجلسة
/// final result = controller.endSession();
/// ```
class TrainingSessionController {
  static const _tag = 'TrainingSessionController';

  /// محرك Stockfish
  final StockfishEngine _engine;

  /// مدير الجلسات
  final AnalysisSessionManager _sessionManager = AnalysisSessionManager();

  /// حالة الجلسة
  TrainingSessionState _state = TrainingSessionState.idle;

  /// خطوات التدريب
  List<TrainingStep> _steps = [];

  /// الفهرس الحالي
  int _currentStepIndex = 0;

  /// اشتراك في تحديثات المحرك
  StreamSubscription<UciResponse>? _engineSubscription;

  /// سجل أوقات الاستجابة
  final List<Duration> _responseTimes = [];

  /// وقت بدء الخطوة الحالية
  DateTime? _stepStartTime;

  /// أفضل حركة من المحرك للخطوة الحالية
  String? _currentBestMove;

  /// خطوط المحرك للخطوة الحالية
  List<EngineLine> _currentEngineLines = [];

  // Callbacks

  /// يُستدعى عند تغير حالة الجلسة
  void Function(TrainingSessionState state)? onStateChanged;

  /// يُستدعى عند تغير الخطوة الحالية
  void Function(TrainingStep step, int index)? onStepChanged;

  /// يُستدعى عند أداء حركة صحيحة
  void Function(TrainingStep step)? onCorrectMove;

  /// يُستدعى عند أداء حركة خاطئة
  void Function(TrainingStep step, String actualUci)? onWrongMove;

  // Getters

  TrainingSessionState get state => _state;
  List<TrainingStep> get steps => List.unmodifiable(_steps);
  int get currentStepIndex => _currentStepIndex;
  TrainingStep? get currentStep =>
      _currentStepIndex >= 0 && _currentStepIndex < _steps.length
          ? _steps[_currentStepIndex]
          : null;
  bool get isActive => _state == TrainingSessionState.active;

  TrainingSessionController({required StockfishEngine engine}) : _engine = engine;

  // ========================================================================
  // بدء الجلسة
  // ========================================================================

  /// بدء جلسة تدريب جديدة — Start training session
  ///
  /// [moves] — قائمة الحركات المحللة
  /// [startIndex] — فهرس البداية (الافتراضي: 0)
  Future<void> startSession(
    List<AnalyzedMove> moves, {
    int startIndex = 0,
  }) async {
    _setState(TrainingSessionState.loading);

    // إنشاء جلسة جديدة
    final token = _sessionManager.startSession('training');

    // بناء خطوات التدريب
    _steps = _buildTrainingSteps(moves);
    _currentStepIndex = startIndex.clamp(0, _steps.length - 1);

    if (_steps.isEmpty) {
      _setState(TrainingSessionState.error);
      return;
    }

    // الاستماع لتحديثات المحرك
    _setupEngineListener();

    // تحليل الموقف الأول
    await _analyzeCurrentPosition();

    _setState(TrainingSessionState.active);
    _stepStartTime = DateTime.now();

    onStepChanged?.call(currentStep!, _currentStepIndex);
  }

  /// بناء خطوات التدريب من الحركات المحللة
  List<TrainingStep> _buildTrainingSteps(List<AnalyzedMove> moves) {
    return moves.map((move) {
      return TrainingStep(
        moveIndex: move.plyNumber - 1,
        fenBefore: move.fenBefore,
        fenAfter: move.fenAfter,
        expectedUci: move.uci,
        expectedSan: move.san,
        alternatives: move.alternatives,
        evalBefore: move.evalBefore,
        evalAfter: move.evalAfter,
        expectedClassification: move.classification,
      );
    }).toList();
  }

  // ========================================================================
  // التحقق من الحركات
  // ========================================================================

  /// التحقق من حركة المستخدم — Check user's move
  ///
  /// يُرجع true إذا كانت الحركة صحيحة (تطابق المتوقعة أو بديل أفضل).
  bool checkMove(String uciMove) {
    final step = currentStep;
    if (step == null) return false;

    final token = _sessionManager.currentToken;
    if (token == null || !_sessionManager.isCurrentSession(token)) {
      debugPrint('$_tag: تجاهل حركة — جلسة غير صالحة');
      return false;
    }

    // حساب زمن الاستجابة
    if (_stepStartTime != null) {
      final responseTime = DateTime.now().difference(_stepStartTime!);
      _responseTimes.add(responseTime);
    }

    // التحقق من الحركة
    final isExpected = uciMove == step.expectedUci;

    // التحقق مما إذا كانت الحركة بديلاً مقبولاً (أفضل حركة أو حركة جيدة)
    final isGoodAlternative = step.alternatives.isNotEmpty &&
        step.alternatives.first.uciMove == uciMove;

    if (isExpected || isGoodAlternative) {
      step.userCorrect = true;
      onCorrectMove?.call(step);
      return true;
    } else {
      step.userCorrect = false;
      step.userActualUci = uciMove;
      onWrongMove?.call(step, uciMove);
      return false;
    }
  }

  // ========================================================================
  // التنقل
  // ========================================================================

  /// الانتقال للخطوة التالية
  Future<void> nextStep() async {
    if (_currentStepIndex >= _steps.length - 1) {
      // اكتمل التدريب
      _setState(TrainingSessionState.completed);
      return;
    }

    _currentStepIndex++;
    _stepStartTime = DateTime.now();

    await _analyzeCurrentPosition();
    onStepChanged?.call(currentStep!, _currentStepIndex);
  }

  /// الانتقال للخطوة السابقة
  Future<void> previousStep() async {
    if (_currentStepIndex <= 0) return;

    _currentStepIndex--;
    _stepStartTime = DateTime.now();

    await _analyzeCurrentPosition();
    onStepChanged?.call(currentStep!, _currentStepIndex);
  }

  /// الانتقال لخطوة محددة
  Future<void> goToStep(int index) async {
    if (index < 0 || index >= _steps.length) return;

    _currentStepIndex = index;
    _stepStartTime = DateTime.now();

    await _analyzeCurrentPosition();
    onStepChanged?.call(currentStep!, _currentStepIndex);
  }

  // ========================================================================
  // تحليل الموقف
  // ========================================================================

  /// تحليل الموقف الحالي
  Future<void> _analyzeCurrentPosition() async {
    final step = currentStep;
    if (step == null) return;

    // إيقاف أي تحليل حالي
    if (_engine.isAnalyzing) {
      _engine.stopAnalysisImmediate();
    }

    // ضبط الموقف
    _engine.setPositionFromFen(step.fenBefore);

    // بدء التحليل
    _currentBestMove = null;
    _currentEngineLines = [];

    try {
      _engine.analyzeInfinite();
    } catch (e) {
      debugPrint('$_tag: خطأ في تحليل الموقف: $e');
    }
  }

  /// إعداد مستمع المحرك
  void _setupEngineListener() {
    _engineSubscription?.cancel();
    _engineSubscription = _engine.responses.listen((response) {
      final token = _sessionManager.currentToken;
      if (token == null || !_sessionManager.isCurrentSession(token)) {
        return; // تجاهل — استجابة قديمة
      }

      switch (response.type) {
        case UciResponseType.info:
          if (response.info != null && (response.info!.multiPv ?? 0) == 1) {
            if (response.info!.pv.isNotEmpty) {
              _currentBestMove = response.info!.pv.first;
            }
          }
          break;
        case UciResponseType.bestmove:
          if (response.bestMove != null) {
            _currentBestMove = response.bestMove!.bestMove;
          }
          break;
        default:
          break;
      }
    });
  }

  // ========================================================================
  // إنهاء الجلسة
  // ========================================================================

  /// إنهاء الجلسة — End session and get result
  TrainingSessionResult endSession() {
    _sessionManager.cancelCurrentSession();
    _engineSubscription?.cancel();
    _engineSubscription = null;

    // إيقاف المحرك
    if (_engine.isAnalyzing) {
      _engine.stopAnalysisImmediate();
    }

    final correct = _steps.where((s) => s.userCorrect).length;
    final wrong = _steps.where((s) => !s.userCorrect && s.userActualUci != null).length;
    final total = correct + wrong;

    Duration avgResponseTime = Duration.zero;
    if (_responseTimes.isNotEmpty) {
      final totalMs = _responseTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
      avgResponseTime = Duration(milliseconds: totalMs ~/ _responseTimes.length);
    }

    _setState(TrainingSessionState.idle);

    return TrainingSessionResult(
      totalSteps: total,
      correctSteps: correct,
      wrongSteps: wrong,
      successRate: total > 0 ? correct / total : 0.0,
      averageResponseTime: avgResponseTime,
    );
  }

  // ========================================================================
  /// إيقاف مؤقت
  void pause() {
    if (_state != TrainingSessionState.active) return;
    _setState(TrainingSessionState.paused);
    if (_engine.isAnalyzing) {
      _engine.stopAnalysisImmediate();
    }
  }

  /// استئناف
  void resume() {
    if (_state != TrainingSessionState.paused) return;
    _setState(TrainingSessionState.active);
    _analyzeCurrentPosition();
  }

  // ========================================================================
  void _setState(TrainingSessionState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChanged?.call(newState);
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    _sessionManager.dispose();
    _engineSubscription?.cancel();
    _engineSubscription = null;
    _steps.clear();
    _responseTimes.clear();
    onStateChanged = null;
    onStepChanged = null;
    onCorrectMove = null;
    onWrongMove = null;
  }
}
