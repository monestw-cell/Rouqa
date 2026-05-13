/// analysis_provider.dart
/// مزود حالة التحليل لتطبيق رُقعة — Analysis state provider
///
/// هذا الملف يربط بين محرك Stockfish وواجهة المستخدم عبر Riverpod.
/// يدير حالة التحليل الكاملة بما في ذلك:
/// - تحميل PGN و FEN
/// - تحليل المباراة مع تحديثات فورية
/// - التنقل بين الحركات
/// - تحديث خطوط المحرك والتقييم في الوقت الحقيقي
/// - إدارة أسهم اللوحة
/// - تتبع التقدم والدقة
///
/// ملاحظة: إدارة دورة حياة المحرك (تهيئة، إغلاق، مراقبة الحرارة)
/// تم تفويضها إلى engine_provider.dart لتجنب التكرار.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess/chess.dart' as chess;

import '../engine/stockfish_engine.dart';
import '../engine/chess_engine_interface.dart';
import '../engine/uci_protocol.dart';
import '../models/board_arrow.dart';
import '../models/chess_models.dart';
import '../services/game_analyzer.dart';
import '../services/classification_engine.dart';
import '../services/pgn_parser.dart';
import '../services/throttled_analysis_update.dart';
import '../services/analysis_session_manager.dart';
import '../services/engine_command_queue.dart';
import '../services/analysis_backpressure.dart';
import '../services/background_analysis_service.dart';
import 'engine_provider.dart';

// ============================================================================
// حالة التحليل — Analysis State
// ============================================================================

/// حالة التحليل الكاملة — Complete analysis state
///
/// تحتوي على جميع البيانات التي تحتاجها واجهة المستخدم
/// لعرض تحليل المباراة.
class AnalysisState {
  // ── الموقف الحالي ────────────────────────────────────────────────────

  /// FEN الموقف الحالي
  final String currentFEN;

  /// قائمة الحركات المحللة
  final List<AnalyzedMove> moves;

  /// فهرس الحركة الحالية (-1 = موقف البداية)
  final int currentMoveIndex;

  /// هل اللوحة مقلوبة؟
  final bool isBoardFlipped;

  // ── حالة التحليل ─────────────────────────────────────────────────────

  /// هل يتم التحليل حاليًا؟
  final bool isAnalyzing;

  /// تقدم التحليل (0.0 - 1.0)
  final double analysisProgress;

  /// نص الحركة الحالية أثناء التحليل
  final String currentAnalyzingMove;

  // ── بيانات المحرك ────────────────────────────────────────────────────

  /// خطوط MultiPV من المحرك
  final List<EngineLine> engineLines;

  /// التقييم من وجهة نظر الأبيض (centipawns)
  final int? evalScore;

  /// أفضل حركة من المحرك (UCI)
  final String? bestMove;

  /// أسهم اللوحة
  final List<BoardArrow> arrows;

  // ── بيانات المباراة ──────────────────────────────────────────────────

  /// نص PGN الخام
  final String? pgn;

  /// ملخص التحليل
  final AnalysisSummary? summary;

  /// المباراة المحللة
  final ChessMatch? match;

  // ── حالة المحرك ──────────────────────────────────────────────────────

  /// هل المحرك جاهز؟
  final bool engineReady;

  /// هل المحرك في وضع التحليل التفاعلي؟
  final bool isInteractiveAnalysis;

  /// رسالة الخطأ
  final String? errorMessage;

  // ── معلومات اللاعبين ──────────────────────────────────────────────────

  /// اسم اللاعب الأبيض
  final String whiteName;

  /// اسم اللاعب الأسود
  final String blackName;

  /// تصنيف الأبيض
  final int? whiteElo;

  /// تصنيف الأسود
  final int? blackElo;

  // ── المُنشئ ──────────────────────────────────────────────────────────

  const AnalysisState({
    this.currentFEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    this.moves = const [],
    this.currentMoveIndex = -1,
    this.isBoardFlipped = false,
    this.isAnalyzing = false,
    this.analysisProgress = 0.0,
    this.currentAnalyzingMove = '',
    this.engineLines = const [],
    this.evalScore,
    this.bestMove,
    this.arrows = const [],
    this.pgn,
    this.summary,
    this.match,
    this.engineReady = false,
    this.isInteractiveAnalysis = false,
    this.errorMessage,
    this.whiteName = 'الأبيض',
    this.blackName = 'الأسود',
    this.whiteElo,
    this.blackElo,
  });

  // ── نسخ مع تعديل ─────────────────────────────────────────────────────

  AnalysisState copyWith({
    String? currentFEN,
    List<AnalyzedMove>? moves,
    int? currentMoveIndex,
    bool? isBoardFlipped,
    bool? isAnalyzing,
    double? analysisProgress,
    String? currentAnalyzingMove,
    List<EngineLine>? engineLines,
    int? Function()? evalScore,
    String? Function()? bestMove,
    List<BoardArrow>? arrows,
    String? Function()? pgn,
    AnalysisSummary? Function()? summary,
    ChessMatch? Function()? match,
    bool? engineReady,
    bool? isInteractiveAnalysis,
    String? Function()? errorMessage,
    String? whiteName,
    String? blackName,
    int? Function()? whiteElo,
    int? Function()? blackElo,
  }) {
    return AnalysisState(
      currentFEN: currentFEN ?? this.currentFEN,
      moves: moves ?? this.moves,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      analysisProgress: analysisProgress ?? this.analysisProgress,
      currentAnalyzingMove: currentAnalyzingMove ?? this.currentAnalyzingMove,
      engineLines: engineLines ?? this.engineLines,
      evalScore: evalScore != null ? evalScore() : this.evalScore,
      bestMove: bestMove != null ? bestMove() : this.bestMove,
      arrows: arrows ?? this.arrows,
      pgn: pgn != null ? pgn() : this.pgn,
      summary: summary != null ? summary() : this.summary,
      match: match != null ? match() : this.match,
      engineReady: engineReady ?? this.engineReady,
      isInteractiveAnalysis: isInteractiveAnalysis ?? this.isInteractiveAnalysis,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      whiteName: whiteName ?? this.whiteName,
      blackName: blackName ?? this.blackName,
      whiteElo: whiteElo != null ? whiteElo() : this.whiteElo,
      blackElo: blackElo != null ? blackElo() : this.blackElo,
    );
  }

  // ── خصائص مشتقة ──────────────────────────────────────────────────────

  /// FEN موقف البداية
  String get startFEN => match?.initialFen ??
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  /// هل نحن في موقف البداية؟
  bool get isAtStart => currentMoveIndex == -1;

  /// هل نحن في آخر موقف؟
  bool get isAtEnd => currentMoveIndex >= moves.length - 1;

  /// الحركة الحالية (إذا وُجدت)
  AnalyzedMove? get currentMove =>
      currentMoveIndex >= 0 && currentMoveIndex < moves.length
          ? moves[currentMoveIndex]
          : null;

  /// رقم الحركة الكاملة الحالية
  int get currentFullMoveNumber {
    if (currentMoveIndex < 0) return 1;
    return moves[currentMoveIndex].moveNumber;
  }

  /// هل دور الأبيض للعب في الموقف الحالي؟
  bool get isWhiteToMove => currentFEN.contains(' w ');

  /// التقييم بتنسيق عرض (مثل: +1.50 أو -0.75 أو M3)
  String get evalDisplay {
    if (evalScore == null) return '0.00';
    final score = evalScore!;

    // كشف كش المات
    if (score.abs() > 90000) {
      final movesToMate = ((100000 - score.abs()) / 100).round();
      return score > 0 ? 'M$movesToMate' : '-M$movesToMate';
    }

    final pawns = score / 100.0;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  /// نسبة التقدم للشريط (0-100)
  double get evalBarPercentage {
    if (evalScore == null) return 50.0;
    final score = evalScore!;

    // كشف كش المات
    if (score.abs() > 90000) {
      return score > 0 ? 100.0 : 0.0;
    }

    // دالة سيغمويدية للتحويل السلس
    const double k = 0.004;
    return 100.0 / (1.0 + _exp(-k * score));
  }

  /// دقة الأبيض
  double get whiteAccuracy => match?.whiteAccuracy ?? summary?.whiteAccuracy ?? 0;

  /// دقة الأسود
  double get blackAccuracy => match?.blackAccuracy ?? summary?.blackAccuracy ?? 0;

  // دالة أسية بسيطة
  static double _exp(double x) {
    if (x > 20) return double.infinity;
    if (x < -20) return 0;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
    }
    return result;
  }
}

// ============================================================================
// مُخطر حالة التحليل — Analysis State Notifier
// ============================================================================

/// مُخطر حالة التحليل — Manages the analysis state
///
/// المسؤول عن:
/// - تحميل PGN و FEN
/// - تشغيل تحليل المباراة
/// - التنقل بين الحركات
/// - التحليل التفاعلي للمواقف
/// - تحديث واجهة المستخدم في الوقت الحقيقي
///
/// ملاحظة: إدارة المحرك (تهيئة، إغلاق، مراقبة الحرارة)
/// تم تفويضها إلى EngineNotifier عبر engine_provider.dart.
class AnalysisNotifier extends StateNotifier<AnalysisState> {
  static const _tag = 'AnalysisNotifier';

  /// مرجع Riverpod للوصول إلى المزودات الأخرى
  final Ref _ref;

  /// محلل المباريات
  GameAnalyzer? _analyzer;

  /// كائن Chess لإدارة اللعبة
  chess.Chess? _game;

  /// رمز إلغاء التحليل الحالي
  CancelToken? _cancelToken;

  /// اشتراك في تحديثات المحرك
  StreamSubscription<UciResponse>? _engineSubscription;

  /// إصلاح #7: محدّد التحديثات (Throttle)
  ThrottledAnalysisUpdate? _throttler;

  /// إصلاح #9: هل المستخدم يسحب قطعة؟ (إيقاف التحليل أثناء السحب)
  bool _isDragging = false;

  /// إصلاح #11: مؤقت التحديثات المجمعة للرسم البياني
  Timer? _chartBatchTimer;
  final List<EvalPoint> _pendingChartPoints = [];
  static const _chartBatchInterval = Duration(milliseconds: 300);

  /// حل #4: مدير جلسات التحليل (منع race conditions)
  final AnalysisSessionManager _sessionManager = AnalysisSessionManager();

  /// حل #3: نظام ضغط التحليل الخلفي
  AnalysisBackpressure? _backpressure;

  /// خدمة التحليل في الخلفية (Android Foreground Service)
  final BackgroundAnalysisService _backgroundService = BackgroundAnalysisService();

  // ─── تفويض إدارة المحرك إلى engine_provider ──────────────────────────

  /// الحصول على EngineNotifier من engine_provider
  EngineNotifier get _engineNotifier => _ref.read(engineProvider.notifier);

  /// الحصول على المحرك من engine_provider
  ChessEngine? get _engine => _engineNotifier.engine;

  /// الحصول على مدير الأوامر من engine_provider
  EngineCommandQueue? get _commandQueue => _engineNotifier.commandQueue;

  AnalysisNotifier(this._ref) : super(const AnalysisState()) {
    _setupAnalysis();
  }

  // ════════════════════════════════════════════════════════════════════════
  // إعداد التحليل — Analysis Setup
  // ════════════════════════════════════════════════════════════════════════

  /// إعداد التحليل والاستماع لحالة المحرك — Setup analysis and listen to engine state
  void _setupAnalysis() {
    // الاستماع إلى تغييرات حالة المحرك من engine_provider
    _ref.listen(engineProvider, (previous, next) {
      // تحديث حالة جاهزية المحرك
      if (previous?.isReady != next.isReady) {
        state = state.copyWith(engineReady: next.isReady);

        // ربط callbacks عند جاهزية المحرك
        if (next.isReady) {
          _bindEngineCallbacks();
          _setupAnalyzer();
        }
      }

      // تحديث حالة التحليل من المحرك
      if (previous?.isAnalyzing != next.isAnalyzing) {
        // لا نُحدث isAnalyzing هنا لأن التحليل التفاعلي يُدار محليًا
        // لكن نُحدث حالة المحرك إذا لم نكن في تحليل تفاعلي
        if (!state.isInteractiveAnalysis) {
          state = state.copyWith(isAnalyzing: next.isAnalyzing);
        }
      }

      // تحديث رسالة الخطأ من المحرك
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        state = state.copyWith(errorMessage: () => next.errorMessage);
      }
    });

    // إعداد نظام ضغط التحليل الخلفي
    _backpressure = AnalysisBackpressure(
      maxQueueSize: 20,
      emitInterval: const Duration(milliseconds: 100),
    );
    _backpressure!.onEmit = (info) {
      _handleAnalysisUpdate(info);
    };

    // إعداد محدّد التحديثات
    _throttler = ThrottledAnalysisUpdate();

    // ربط callbacks إذا كان المحرك جاهزًا بالفعل
    final engineState = _ref.read(engineProvider);
    if (engineState.isReady) {
      _bindEngineCallbacks();
      _setupAnalyzer();
    }
  }

  /// ربط callbacks المحرك — Bind engine callbacks
  ///
  /// يربط دوال معالجة أحداث المحرك للتحليل التفاعلي.
  /// هذا يُعيد تعيين callbacks التي يضعها engine_provider
  /// لأن التحليل يحتاج معالجة مخصصة لبيانات InfoResponse.
  void _bindEngineCallbacks() {
    final engine = _engine;
    if (engine == null) return;

    engine.onAnalysisUpdate = _handleAnalysisUpdate;
    engine.onBestMove = _handleBestMove;
    engine.onReady = () {
      state = state.copyWith(engineReady: true);
      debugPrint('$_tag: المحرك جاهز');
    };
    engine.onError = _handleEngineError;
    engine.onStateChanged = _handleEngineStateChanged;
  }

  /// إعداد محلل المباريات — Setup the game analyzer
  void _setupAnalyzer() {
    final engine = _engine;
    if (engine == null) return;

    // إنشاء محلل المباريات (نستخدم StockfishEngine فقط لأن GameAnalyzer يحتاجه)
    if (engine is StockfishEngine) {
      _analyzer = GameAnalyzer(engine: engine);
    } else {
      _analyzer = GameAnalyzer(); // سيُنشئ محركه الخاص
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // معالجات أحداث المحرك — Engine Event Handlers
  // ════════════════════════════════════════════════════════════════════════

  /// معالجة تحديث التحليل — Handle analysis update
  void _handleAnalysisUpdate(InfoResponse info) {
    if (!state.isInteractiveAnalysis) return;

    // تحديث خطوط المحرك في الوقت الحقيقي
    final engineLines = _buildEngineLinesFromInfo();
    final evalScore = _getEvalFromInfo();
    final bestMove = _getBestMoveFromInfo();
    final arrows = _buildArrowsFromInfo(engineLines);

    state = state.copyWith(
      engineLines: engineLines,
      evalScore: () => evalScore,
      bestMove: () => bestMove,
      arrows: arrows,
    );
  }

  /// معالجة أفضل حركة — Handle best move
  void _handleBestMove(BestMoveResponse bestMove) {
    debugPrint('$_tag: أفضل حركة: ${bestMove.bestMove}');

    if (!state.isInteractiveAnalysis) return;

    // بناء أسهم من أفضل حركة
    final uci = bestMove.bestMove;
    if (uci.length >= 4) {
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);

      state = state.copyWith(
        bestMove: () => uci,
        arrows: [BoardArrow.bestMove(from: from, to: to)],
      );
    }
  }

  /// معالجة خطأ المحرك — Handle engine error
  void _handleEngineError(StockfishException error) {
    debugPrint('$_tag: خطأ المحرك: ${error.message}');
    state = state.copyWith(
      errorMessage: () => error.message,
    );
  }

  /// معالجة تغير حالة المحرك — Handle engine state change
  void _handleEngineStateChanged(EngineState engineState) {
    debugPrint('$_tag: حالة المحرك: $engineState');
    final isReady = engineState == EngineState.ready;
    final isAnalyzing = engineState == EngineState.analyzing;

    if (state.engineReady != isReady || state.isAnalyzing != isAnalyzing) {
      state = state.copyWith(
        engineReady: isReady,
        isAnalyzing: isAnalyzing,
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // تحميل PGN و FEN — Load PGN & FEN
  // ════════════════════════════════════════════════════════════════════════

  /// تحميل مباراة من PGN — Load a game from PGN string
  ///
  /// يحلل PGN ويُعيد تشغيل المباراة ويُحدث الحالة.
  /// لا يبدأ التحليل تلقائيًا - استخدم `analyzeGame()` بعد التحميل.
  Future<void> loadPGN(String pgn) async {
    try {
      // إيقاف أي تحليل حالي
      await stopAnalysis();

      // تحليل PGN
      final result = PgnParser.parse(pgn);

      // إعادة تشغيل المباراة
      final game = chess.Chess();
      final moveDataList = <AnalyzedMove>[];
      final uciMoves = <String>[];

      int plyNumber = 0;
      for (final parsedMove in result.moves) {
        final fenBefore = game.fen;
        final isWhite = game.turn == chess.Color.WHITE;
        final moveNumber = (plyNumber ~/ 2) + 1;

        chess.Move? moveResult;
        try {
          moveResult = game.move(parsedMove.san);
        } catch (e) {
          continue;
        }

        if (moveResult == null) continue;

        plyNumber++;
        final fenAfter = game.fen;

        // استخراج UCI
        String uci = '';
        bool isCapture = false;
        bool isCastling = false;

        try {
      if (moveResult != null) {
            final from = moveResult.from;
            final to = moveResult.to;
            final promotion = moveResult.promotion;
            uci = promotion != null && promotion.isNotEmpty
                ? '$from$to${promotion.toLowerCase()}'
                : '$from$to';
            isCapture = moveResult.captured != null;
            final flags = moveResult.flags ?? '';
            isCastling = flags.contains('k') || flags.contains('q');
          }
        } catch (_) {
          uci = '';
          isCapture = parsedMove.san.contains('x');
          isCastling = parsedMove.san == 'O-O' || parsedMove.san == 'O-O-O';
        }

        uciMoves.add(uci);

        // إنشاء AnalyzedMove مؤقت بدون بيانات تحليل
        // سيتم ملؤها لاحقًا عند تشغيل analyzeGame()
        moveDataList.add(AnalyzedMove(
          moveNumber: moveNumber,
          plyNumber: plyNumber,
          color: isWhite ? PlayerColor.white : PlayerColor.black,
          san: parsedMove.san,
          uci: uci,
          fenBefore: fenBefore,
          fenAfter: fenAfter,
          evalBefore: 0,
          evalAfter: 0,
          cpLoss: 0,
          classification: MoveClassification.good,
          depth: 0,
          alternatives: const [],
          pv: '',
          comment: parsedMove.comment,
          isCheckmate: game.in_checkmate,
          isCheck: game.in_check,
          isCastling: isCastling,
          isCapture: isCapture,
          phase: ClassificationEngine.determineGamePhase(fenBefore),
        ));
      }

      // تحديد نتيجة المباراة
      GameResult gameResult = GameResult.fromPgn(result.result);

      _game = game;

      state = state.copyWith(
        currentFEN: game.fen,
        moves: moveDataList,
        currentMoveIndex: moveDataList.length - 1,
        pgn: () => pgn,
        match: null,
        summary: () => null,
        isAnalyzing: false,
        analysisProgress: 0.0,
        engineLines: const [],
        evalScore: () => null,
        bestMove: () => null,
        arrows: const [],
        errorMessage: () => null,
        whiteName: result.whitePlayer ?? 'الأبيض',
        blackName: result.blackPlayer ?? 'الأسود',
        whiteElo: () => int.tryParse(result.headers['WhiteElo'] ?? ''),
        blackElo: () => int.tryParse(result.headers['BlackElo'] ?? ''),
      );

      debugPrint('$_tag: تم تحليل PGN بنجاح - ${moveDataList.length} حركة');
    } catch (e) {
      debugPrint('$_tag: خطأ في تحميل PGN: $e');
      state = state.copyWith(
        errorMessage: () => 'خطأ في تحميل PGN: $e',
      );
    }
  }

  /// تحميل موقف من FEN — Load a position from FEN string
  Future<void> loadFEN(String fen) async {
    try {
      await stopAnalysis();

      // التحقق من صحة FEN
      final game = chess.Chess.fromFEN(fen);
      _game = game;

      state = state.copyWith(
        currentFEN: fen,
        moves: const [],
        currentMoveIndex: -1,
        pgn: () => null,
        match: null,
        summary: () => null,
        isAnalyzing: false,
        analysisProgress: 0.0,
        engineLines: const [],
        evalScore: () => null,
        bestMove: () => null,
        arrows: const [],
        errorMessage: () => null,
      );

      debugPrint('$_tag: تم تحميل FEN بنجاح');

      // بدء التحليل التفاعلي للموقف
      startEngineAnalysis();
    } catch (e) {
      debugPrint('$_tag: FEN غير صالح: $e');
      state = state.copyWith(
        errorMessage: () => 'FEN غير صالح: $e',
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // تحليل المباراة — Game Analysis
  // ════════════════════════════════════════════════════════════════════════

  /// تحليل المباراة بالكامل — Analyze the complete game
  ///
  /// يستخدم GameAnalyzer لتحليل كل حركة في المباراة.
  /// يُحدث التقدم في الوقت الحقيقي عبر callbacks.
  Future<void> analyzeGame({int depth = 20}) async {
    if (state.moves.isEmpty) {
      state = state.copyWith(
        errorMessage: () => 'لا توجد حركات لتحليلها',
      );
      return;
    }

    // إيقاف التحليل السابق
    _cancelToken?.cancel();
    _cancelToken = CancelToken();

    // إيقاف التحليل التفاعلي
    await stopAnalysis();

    state = state.copyWith(
      isAnalyzing: true,
      analysisProgress: 0.0,
      errorMessage: () => null,
    );

    // بدء خدمة الخلفية (Android Foreground Service)
    if (_backgroundService.isPlatformSupported) {
      final hasPermission = await _backgroundService.checkNotificationPermission();
      if (!hasPermission) {
        await _backgroundService.requestNotificationPermission();
      }
      await _backgroundService.startAnalysis();
    }

    try {
      // التأكد من تهيئة المحرك
      if (_analyzer == null) {
        _analyzer = GameAnalyzer();
        await _analyzer!.initialize();
      }

      // تحويل الحركات الحالية إلى قائمة SAN
      final sanMoves = state.moves.map((m) => m.san).toList();

      // تشغيل التحليل
      final result = await _analyzer!.analyzeGame(
        moves: sanMoves,
        depth: depth,
        multiPV: 3,
        cancelToken: _cancelToken,
        onProgress: (current, total, currentMove) {
          final progress = total > 0 ? current / total : 0.0;
          state = state.copyWith(
            analysisProgress: progress,
            currentAnalyzingMove: currentMove,
          );
          _backgroundService.updateProgress(
            current: current,
            total: total,
            currentMove: currentMove,
          );
        },
      );

      // التحقق من عدم إلغاء التحليل
      if (_cancelToken?.isCancelled ?? false) {
        state = state.copyWith(
          isAnalyzing: false,
          analysisProgress: 0.0,
        );
        return;
      }

      // تحديث الحالة بالنتائج
      final evalScore = result.evalPoints.isNotEmpty
          ? result.evalPoints.last.evalCp
          : 0;

      // إنشاء ملخص
      final summary = ClassificationEngine.generateSummary(result.moves);

      state = state.copyWith(
        isAnalyzing: false,
        analysisProgress: 1.0,
        moves: result.moves,
        match: () => result,
        summary: () => summary,
        evalScore: () => evalScore,
        currentMoveIndex: result.moves.isNotEmpty ? result.moves.length - 1 : -1,
        currentFEN: result.moves.isNotEmpty
            ? result.moves.last.fenAfter
            : state.currentFEN,
      );

      debugPrint('$_tag: تم تحليل المباراة بنجاح - ${result.moves.length} حركة');
    } catch (e) {
      debugPrint('$_tag: خطأ في تحليل المباراة: $e');
      state = state.copyWith(
        isAnalyzing: false,
        analysisProgress: 0.0,
        errorMessage: () => 'خطأ في التحليل: $e',
      );
    } finally {
      await _backgroundService.stopAnalysis();
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // التحليل التفاعلي — Interactive Analysis
  // ════════════════════════════════════════════════════════════════════════

  /// بدء التحليل التفاعلي للموقف الحالي — Start interactive analysis
  ///
  /// يبدأ تحليلًا غير محدود للموقف الحالي.
  /// يُحدث خطوط المحرك والتقييم في الوقت الحقيقي.
  Future<void> startEngineAnalysis() async {
    final engine = _engine;
    if (engine == null || !engine.isReady) return;

    try {
      // حل #4: بدء جلسة تحليل جديدة (منع race conditions)
      final sessionToken = _sessionManager.startSession('interactive_${state.currentMoveIndex}');

      // بناء أمر الموقف
      String positionCommand;
      if (state.currentMoveIndex >= 0 && state.moves.isNotEmpty) {
        final uciMoves = <String>[];
        for (int i = 0; i <= state.currentMoveIndex && i < state.moves.length; i++) {
          uciMoves.add(state.moves[i].uci);
        }
        if (state.startFEN != 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1') {
          positionCommand = 'position fen ${state.startFEN} moves ${uciMoves.join(' ')}';
        } else {
          positionCommand = 'position startpos moves ${uciMoves.join(' ')}';
        }
      } else {
        positionCommand = 'position fen ${state.currentFEN}';
      }

      // حل #16: استخدام مدير الأوامر لضبط الموقف والبدء
      final commandQueue = _commandQueue;
      if (commandQueue != null) {
        commandQueue.enqueueSetOption('MultiPV', '3');
        commandQueue.enqueuePosition(positionCommand);
        commandQueue.enqueueGo(infinite: true);
      } else {
        // Fallback — أوامر مباشرة عبر المحرك
        engine.setMultiPv(3);
        engine.sendCommand(positionCommand);
        engine.analyzeInfinite();
      }

      state = state.copyWith(
        isInteractiveAnalysis: true,
        isAnalyzing: true,
      );

      debugPrint('$_tag: بدأ التحليل التفاعلي (جلسة: ${sessionToken.id})');
    } catch (e) {
      debugPrint('$_tag: خطأ في بدء التحليل التفاعلي: $e');
    }
  }

  /// إيقاف التحليل — Stop analysis
  Future<void> stopAnalysis() async {
    // حل #4: إلغاء الجلسة الحالية
    _sessionManager.cancelCurrentSession();

    try {
      // حل #16: استخدام مدير الأوامر للإيقاف عبر engine_provider
      final commandQueue = _commandQueue;
      final engine = _engine;
      if (commandQueue != null) {
        commandQueue.enqueueStop();
      } else if (engine != null && engine.isAnalyzing) {
        await engine.stopAnalysis().timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      // إيقاف فوري في حالة الفشل
      _engineNotifier.stopAnalysisImmediate();
    }

    state = state.copyWith(
      isAnalyzing: false,
      isInteractiveAnalysis: false,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // التنقل بين الحركات — Move Navigation
  // ════════════════════════════════════════════════════════════════════════

  /// الانتقال إلى حركة محددة — Go to a specific move
  void goToMove(int index) {
    if (index < -1 || index >= state.moves.length) return;

    // إيقاف التحليل التفاعلي مؤقتًا
    if (state.isInteractiveAnalysis) {
      _engineNotifier.stopAnalysisImmediate();
    }

    String fen;
    List<BoardArrow> arrows = [];
    int? evalScore;

    if (index == -1) {
      // موقف البداية
      fen = state.startFEN;
    } else {
      fen = state.moves[index].fenAfter;
      evalScore = state.moves[index].evalAfter;

      // بناء أسهم من بدائل الحركة التالية (إن وُجدت)
      if (index + 1 < state.moves.length) {
        final nextMove = state.moves[index + 1];
        if (nextMove.alternatives.isNotEmpty) {
          final best = nextMove.alternatives.first;
          if (best.uciMove.length >= 4) {
            arrows.add(BoardArrow.bestMove(
              from: best.uciMove.substring(0, 2),
              to: best.uciMove.substring(2, 4),
            ));
          }
        }
      }
    }

    state = state.copyWith(
      currentMoveIndex: index,
      currentFEN: fen,
      arrows: arrows,
      evalScore: () => evalScore,
      engineLines: index >= 0 && index < state.moves.length
          ? state.moves[index].alternatives
          : const [],
    );

    // إعادة تشغيل التحليل التفاعلي
    startEngineAnalysis();
  }

  /// الانتقال إلى موقف البداية — Go to start position
  void goToStart() => goToMove(-1);

  /// الانتقال إلى آخر موقف — Go to end position
  void goToEnd() => goToMove(state.moves.length - 1);

  /// الحركة التالية — Go to next move
  void nextMove() => goToMove(state.currentMoveIndex + 1);

  /// الحركة السابقة — Go to previous move
  void previousMove() => goToMove(state.currentMoveIndex - 1);

  // ─── أساليب بديلة للتوافق — Compatibility Aliases ─────────────────────
  // هذه الأساليب موجودة لتوافق واجهة المستخدم مع أسماء مختلفة

  /// الرجوع (مرادف لـ previousMove) — Go back (alias for previousMove)
  void goBack() => previousMove();

  /// التقدم (مرادف لـ nextMove) — Go forward (alias for nextMove)
  void goForward() => nextMove();

  /// بدء التحليل (مرادف لـ startEngineAnalysis) — Start analysis
  Future<void> startAnalysis() => startEngineAnalysis();

  /// هل اللوحة مقلوبة؟ (خاصية ملائمة) — Is board flipped?
  bool get isFlipped => state.isBoardFlipped;

  // ════════════════════════════════════════════════════════════════════════
  // عمليات اللوحة — Board Operations
  // ════════════════════════════════════════════════════════════════════════

  /// قلب اللوحة — Flip the board
  void flipBoard() {
    state = state.copyWith(isBoardFlipped: !state.isBoardFlipped);
  }

  /// تنفيذ حركة على اللوحة — Make a move on the board
  ///
  /// [fromSquare] - المربع المصدر (مثل: "e2")
  /// [toSquare] - المربع الهدف (مثل: "e4")
  /// [promotion] - قطعة الترقية (اختياري: "q", "r", "b", "n")
  ///
  /// يعيد true إذا كانت الحركة صالحة، وfalse غير ذلك.
  bool makeMove(String fromSquare, String toSquare, {String? promotion}) {
    try {
      // إنشاء أو استعادة كائن Chess
      _game ??= chess.Chess();

      // محاولة مطابقة الحركة مع الحركات القانونية
      final legalMoves = _game!.moves();
      String? sanMove;

      for (final m in legalMoves) {
        final mFrom = m.from;
        final mTo = m.to;
        final mPromo = m.promotion;

        if (mFrom == fromSquare && mTo == toSquare) {
          // مطابقة الترقية
          if (promotion == null ||
              (mPromo != null && mPromo.toLowerCase() == promotion.toLowerCase()) ||
              (promotion == null && (mPromo == null || mPromo.isEmpty))) {
            sanMove = m.san;
            break;
          }
        }
      }

      if (sanMove == null) return false;

      final fenBefore = _game!.fen;
      final isWhite = _game!.turn == chess.Color.WHITE;

      // تنفيذ الحركة
      final moveResult = _game!.move(sanMove);
      if (moveResult == null) return false;

      final fenAfter = _game!.fen;
      final moveNumber = (state.moves.length / 2).floor() + 1;
      final plyNumber = state.moves.length + 1;

      // استخراج UCI
      String uci = '$fromSquare$toSquare${promotion ?? ''}';

      bool isCapture = false;
      bool isCastling = false;
      try {
        if (moveResult != null) {
          isCapture = moveResult.captured != null;
          final flags = moveResult.flags ?? '';
          isCastling = flags.contains('k') || flags.contains('q');
        }
      } catch (_) {}

      // إنشاء AnalyzedMove جديد (بدون بيانات تحليل)
      final analyzedMove = AnalyzedMove(
        moveNumber: moveNumber,
        plyNumber: plyNumber,
        color: isWhite ? PlayerColor.white : PlayerColor.black,
        san: sanMove,
        uci: uci,
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        evalBefore: 0,
        evalAfter: 0,
        cpLoss: 0,
        classification: MoveClassification.good,
        depth: 0,
        alternatives: const [],
        pv: '',
        isCheckmate: _game!.in_checkmate,
        isCheck: _game!.in_check,
        isCastling: isCastling,
        isCapture: isCapture,
        phase: ClassificationEngine.determineGamePhase(fenBefore),
      );

      // إضافة الحركة إلى القائمة
      final newMoves = List<AnalyzedMove>.from(state.moves)..add(analyzedMove);

      state = state.copyWith(
        moves: newMoves,
        currentMoveIndex: newMoves.length - 1,
        currentFEN: fenAfter,
        arrows: const [],
      );

      // بدء التحليل التفاعلي للموقف الجديد
      startEngineAnalysis();

      return true;
    } catch (e) {
      debugPrint('$_tag: خطأ في تنفيذ الحركة: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // دوال مساعدة — Helper Methods
  // ════════════════════════════════════════════════════════════════════════

  /// بناء خطوط المحرك من بيانات Info الحالية — Build engine lines from current info
  List<EngineLine> _buildEngineLinesFromInfo() {
    final engine = _engine;
    if (engine == null) return [];

    final infoByPv = engine.latestInfoByPv;
    final isWhiteToMove = engine.isWhiteToMove;
    final lines = <EngineLine>[];

    for (final entry in infoByPv.entries) {
      final info = entry.value;
      if (info.pv.isEmpty || info.score == null) continue;

      final uciMove = info.pv.first;
      final whiteScore = info.score!.fromWhitePerspective(isWhiteToMove);

      int evalCp = 0;
      bool isMate = false;
      int? mateIn;

      if (whiteScore.type == ScoreType.centipawns) {
        evalCp = whiteScore.value;
      } else if (whiteScore.type == ScoreType.mate) {
        isMate = true;
        mateIn = whiteScore.value;
        if (whiteScore.value > 0) {
          evalCp = 100000 - whiteScore.value * 100;
        } else {
          evalCp = -(100000 + whiteScore.value * 100);
        }
      }

      lines.add(EngineLine(
        uciMove: uciMove,
        sanMove: uciMove, // سيتم تحويله لاحقًا
        evalCp: evalCp,
        depth: info.depth ?? 0,
        pv: info.pv.join(' '),
        nodes: info.nodes,
        isMate: isMate,
        mateIn: mateIn,
      ));
    }

    return lines;
  }

  /// الحصول على التقييم من بيانات Info الحالية — Get eval from current info
  int? _getEvalFromInfo() {
    final engine = _engine;
    if (engine == null) return null;

    final infoByPv = engine.latestInfoByPv;
    final primaryInfo = infoByPv[1];
    if (primaryInfo?.score == null) return null;

    final isWhiteToMove = engine.isWhiteToMove;
    final whiteScore = primaryInfo!.score!.fromWhitePerspective(isWhiteToMove);

    if (whiteScore.type == ScoreType.centipawns) {
      return whiteScore.value;
    } else if (whiteScore.type == ScoreType.mate) {
      if (whiteScore.value > 0) {
        return 100000 - whiteScore.value * 100;
      } else {
        return -(100000 + whiteScore.value * 100);
      }
    }

    return null;
  }

  /// الحصول على أفضل حركة من بيانات Info الحالية — Get best move from current info
  String? _getBestMoveFromInfo() {
    final engine = _engine;
    if (engine == null) return null;

    final infoByPv = engine.latestInfoByPv;
    final primaryInfo = infoByPv[1];
    if (primaryInfo?.pv.isEmpty ?? true) return null;

    return primaryInfo!.pv.first;
  }

  /// بناء أسهم اللوحة من بيانات Info — Build board arrows from info
  List<BoardArrow> _buildArrowsFromInfo(List<EngineLine> lines) {
    final arrows = <BoardArrow>[];

    // أفضل حركة (سهم أخضر)
    if (lines.isNotEmpty) {
      final best = lines.first;
      if (best.uciMove.length >= 4) {
        arrows.add(BoardArrow.bestMove(
          from: best.uciMove.substring(0, 2),
          to: best.uciMove.substring(2, 4),
        ));
      }
    }

    // ثاني أفضل حركة (سهم أزرق) إذا كانت مختلفة
    if (lines.length >= 2) {
      final second = lines[1];
      if (second.uciMove.length >= 4) {
        arrows.add(BoardArrow.goodMove(
          from: second.uciMove.substring(0, 2),
          to: second.uciMove.substring(2, 4),
        ));
      }
    }

    return arrows;
  }

  // ════════════════════════════════════════════════════════════════════════
  // إصلاح #9: إيقاف/استئناف أثناء السحب — Drag Pause/Resume
  // ════════════════════════════════════════════════════════════════════════

  /// إيقاف التحليل أثناء السحب — Pause analysis during drag
  ///
  /// يُستدعى عند بداية سحب قطعة على الرقعة.
  /// يوقف المحرك مؤقتاً لمنع التأتأة.
  void onDragStart() {
    if (_isDragging) return;
    _isDragging = true;

    // إيقاف التحليل فوراً (إصلاح #9)
    final engine = _engine;
    if (engine != null && engine.isAnalyzing) {
      _engineNotifier.stopAnalysisImmediate();
      debugPrint('$_tag: تم إيقاف التحليل أثناء السحب');
    }
  }

  /// استئناف التحليل بعد السحب — Resume analysis after drop
  ///
  /// يُستدعى عند انتهاء السحب (سقوط القطعة).
  /// يعيد تشغيل التحليل التفاعلي.
  void onDragEnd() {
    if (!_isDragging) return;
    _isDragging = false;

    // استئناف التحليل (إصلاح #9)
    if (state.isInteractiveAnalysis) {
      startEngineAnalysis();
      debugPrint('$_tag: تم استئناف التحليل بعد السحب');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // إصلاح #11: تحديثات مجمعة للرسم البياني — Batch Chart Updates
  // ════════════════════════════════════════════════════════════════════════

  /// إضافة نقطة تقييم للتحديث المجمّع — Add eval point for batch update
  void _addChartPoint(EvalPoint point) {
    _pendingChartPoints.add(point);

    // بدء أو إعادة تشغيل مؤقت الدفعة
    _chartBatchTimer?.cancel();
    _chartBatchTimer = Timer(_chartBatchInterval, _flushChartPoints);
  }

  /// إرسال النقاط المجمّعة — Flush batched chart points
  void _flushChartPoints() {
    if (_pendingChartPoints.isEmpty) return;

    // إضافة النقاط إلى المباراة الحالية
    // (هذا سيُحدّث الرسم البياني بدون إعادة بناء كاملة)
    if (state.match != null) {
      final currentPoints = List<EvalPoint>.from(state.match!.evalPoints)
        ..addAll(_pendingChartPoints);

      final updatedMatch = state.match!.copyWith(evalPoints: currentPoints);
      state = state.copyWith(match: () => updatedMatch);
    }

    _pendingChartPoints.clear();
    _chartBatchTimer = null;
  }

  // ════════════════════════════════════════════════════════════════════════
  // التخلص من الموارد — Dispose
  // ════════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _cancelToken?.cancel();
    _engineSubscription?.cancel();
    _chartBatchTimer?.cancel();
    _pendingChartPoints.clear();
    _throttler?.dispose();
    _sessionManager.dispose();
    _backpressure?.dispose();
    _backgroundService.dispose();
    _analyzer?.dispose();
    // لا نُغلق المحرك هنا — engine_provider يملكه ويُديره
    super.dispose();
  }
}

// ============================================================================
// مزود Riverpod — Riverpod Provider
// ============================================================================

/// مزود حالة التحليل — Analysis state provider
///
/// الاستخدام:
/// ```dart
/// // قراءة الحالة
/// final state = ref.watch(analysisProvider);
///
/// // استدعاء دوال
/// ref.read(analysisProvider.notifier).loadPGN(pgn);
/// ref.read(analysisProvider.notifier).analyzeGame();
/// ref.read(analysisProvider.notifier).nextMove();
/// ```
final analysisProvider = StateNotifierProvider<AnalysisNotifier, AnalysisState>(
  (ref) => AnalysisNotifier(ref),
);
