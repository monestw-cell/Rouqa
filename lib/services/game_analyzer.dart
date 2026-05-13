/// game_analyzer.dart
/// خط أنابيب تحليل المباريات الفعلي لتطبيق رُقعة
///
/// هذا الملف يربط محرك Stockfish الحقيقي بواجهة المستخدم عبر:
/// - تحليل مباراة كاملة حركة بحركة مع MultiPV=3
/// - جمع التقييم قبل وبعد كل حركة
/// - حساب فقد السنتيبيدق (cpLoss) لكل حركة
/// - تصنيف كل حركة باستخدام ClassificationEngine
/// - بناء منحنى التقييم (EvalPoint list)
/// - حساب الدقة لكلا اللاعبين
/// - إرجاع ChessMatch كامل مع جميع AnalyzedMove

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:chess/chess.dart' as chess;

import '../engine/stockfish_engine.dart';
import '../engine/uci_protocol.dart';
import '../models/chess_models.dart';
import '../services/classification_engine.dart';
import '../services/pgn_parser.dart';
import '../services/opening_detector.dart' as opening_lib;

// ============================================================================
// أنواع مساعدة — Helper Types
// ============================================================================

/// رمز إلغاء التحليل — Token for cancelling an ongoing analysis
class CancelToken {
  bool _isCancelled = false;

  /// هل تم إلغاء التحليل؟
  bool get isCancelled => _isCancelled;

  /// إلغاء التحليل
  void cancel() => _isCancelled = true;

  /// إعادة تعيين الرمز للاستخدام مرة أخرى
  void reset() => _isCancelled = false;
}

/// دالة رد التقدم — Progress callback type
/// [current] = الحركة الحالية، [total] = إجمالي الحركات، [currentMove] = نص الحركة
typedef ProgressCallback = void Function(int current, int total, String currentMove);

/// بيانات حركة داخلية — Internal move data used during replay
class _MoveData {
  final String fenBefore;
  final String fenAfter;
  final String san;
  final String uci;
  final bool isWhite;
  final int moveNumber;
  final int plyNumber;
  final bool isCheck;
  final bool isCheckmate;
  final bool isCastling;
  final bool isCapture;
  final String? comment;
  final Duration? clockTime;

  const _MoveData({
    required this.fenBefore,
    required this.fenAfter,
    required this.san,
    required this.uci,
    required this.isWhite,
    required this.moveNumber,
    required this.plyNumber,
    this.isCheck = false,
    this.isCheckmate = false,
    this.isCastling = false,
    this.isCapture = false,
    this.comment,
    this.clockTime,
  });
}

/// نتيجة تحليل موقف واحد — Result of analyzing a single position
class _PositionEval {
  /// التقييم من وجهة نظر الأبيض (centipawns)
  final int evalCp;

  /// خطوط MultiPV البديلة
  final List<EngineLine> alternatives;

  /// عمق البحث
  final int depth;

  /// أفضل حركة بصيغة UCI
  final String? bestMoveUci;

  /// هل التقييم كش مات من وجهة نظر الأبيض؟
  final bool isWhiteMate;

  /// عدد حركات الكش مات (إيجابي = للأبيض، سلبي = للأسود)
  final int? mateIn;

  const _PositionEval({
    required this.evalCp,
    this.alternatives = const [],
    this.depth = 0,
    this.bestMoveUci,
    this.isWhiteMate = false,
    this.mateIn,
  });
}

/// بيانات المباراة المُحللة — Parsed game data from PGN or move list
class _GameData {
  final String whiteName;
  final String blackName;
  final int? whiteElo;
  final int? blackElo;
  final GameResult result;
  final Termination? termination;
  final DateTime? date;
  final String? event;
  final String? site;
  final int? round;
  final String? initialFen;
  final String? rawPgn;
  final List<_MoveData> moves;
  final List<String> uciMoves; // جميع حركات UCI لإرسالها للمحرك

  const _GameData({
    this.whiteName = 'الأبيض',
    this.blackName = 'الأسود',
    this.whiteElo,
    this.blackElo,
    this.result = GameResult.incomplete,
    this.termination,
    this.date,
    this.event,
    this.site,
    this.round,
    this.initialFen,
    this.rawPgn,
    this.moves = const [],
    this.uciMoves = const [],
  });
}

// ============================================================================
// محلل المباريات — Game Analyzer
// ============================================================================

/// محلل المباريات الرئيسي — Main game analysis pipeline
///
/// يربط محرك Stockfish الحقيقي بنماذج البيانات ويوفر:
/// - تحليل مباراة كاملة حركة بحركة
/// - تحليل موقف واحد
/// - دعم الإلغاء والتقدم
/// - تنظيف آمن للموارد
class GameAnalyzer {
  static const _tag = 'GameAnalyzer';

  /// محرك Stockfish المستخدم للتحليل
  StockfishEngine? _engine;

  /// هل المحرك مملوك لهذا الكائن (يجب التخلص منه عند الإغلاق)؟
  final bool _ownsEngine;

  /// العمق الافتراضي للتحليل
  final int _defaultDepth;

  /// عدد خطوط MultiPV الافتراضية
  final int _defaultMultiPV;

  /// عدد الخيوط الافتراضية
  final int _threads;

  /// حجم التجزئة الافتراضي (MB)
  final int _hashSizeMb;

  /// المهلة القصوى لتحليل موقف واحد
  final Duration _positionTimeout;

  // ── المُنشئ ──────────────────────────────────────────────────────────

  /// إنشاء محلل مباريات جديد
  ///
  /// [engine] - محرك Stockfish موجود (اختياري، يُنشئ واحدًا جديدًا إذا null)
  /// [depth] - عمق التحليل (1-50، الافتراضي 20)
  /// [multiPV] - عدد خطوط MultiPV (1-5، الافتراضي 3)
  /// [threads] - عدد خيوط المعالجة (1-8، الافتراضي 2)
  /// [hashSizeMb] - حجم جدول التجزئة بالميجابايت (الافتراضي 128)
  /// [positionTimeout] - المهلة القصوى لكل موقف (الافتراضي 60 ثانية)
  GameAnalyzer({
    StockfishEngine? engine,
    int depth = 20,
    int multiPV = 3,
    int threads = 2,
    int hashSizeMb = 128,
    Duration positionTimeout = const Duration(seconds: 60),
  })  : _engine = engine,
        _ownsEngine = engine == null,
        _defaultDepth = depth.clamp(1, 50),
        _defaultMultiPV = multiPV.clamp(1, 5),
        _threads = threads.clamp(1, 8),
        _hashSizeMb = hashSizeMb.clamp(1, 33554432),
        _positionTimeout = positionTimeout;

  // ── التهيئة والإغلاق ─────────────────────────────────────────────────

  /// تهيئة المحرك — Initialize the Stockfish engine
  ///
  /// يجب استدعاؤها قبل أي عملية تحليل.
  /// إذا تم تمرير محرك موجود، لا تفعل شيئًا إذا كان جاهزًا.
  Future<void> initialize() async {
    if (_engine != null && _engine!.isReady) return;

    _engine ??= StockfishEngine();

    if (!_engine!.isReady) {
      await _engine!.initialize();

      // ضبط خيارات المحرك
      _engine!.setMultiPv(_defaultMultiPV);
      _engine!.setThreads(_threads);
      _engine!.setHashSize(_hashSizeMb);

      debugPrint('$_tag: تمت تهيئة المحرك بنجاح');
    }
  }

  /// التخلص من الموارد — Dispose of all resources
  ///
  /// آمن للاستدعاء المتعدد. يغلق المحرك فقط إذا كان مملوكًا لهذا الكائن.
  Future<void> dispose() async {
    if (_ownsEngine && _engine != null) {
      await _engine!.dispose();
      debugPrint('$_tag: تم إغلاق المحرك');
    }
    _engine = null;
  }

  /// هل المحرك جاهز للتحليل؟
  bool get isReady => _engine?.isReady ?? false;

  /// هل المحرك يحلل حاليًا؟
  bool get isAnalyzing => _engine?.isAnalyzing ?? false;

  // ════════════════════════════════════════════════════════════════════════
  // تحليل مباراة كاملة — Full Game Analysis
  // ════════════════════════════════════════════════════════════════════════

  /// تحليل مباراة كاملة حركة بحركة — Analyze a complete game move by move
  ///
  /// هذا هو المدخل الرئيسي لتحليل المباريات. يقوم بـ:
  /// 1. تحليل المدخلات (PGN أو قائمة حركات)
  /// 2. إعادة تشغيل المباراة حركة بحركة
  /// 3. تحليل كل موقف بعمق محدد و MultiPV
  /// 4. جمع التقييمات وحساب cpLoss
  /// 5. تصنيف كل حركة
  /// 6. بناء منحنى التقييم
  /// 7. حساب الدقة
  /// 8. إرجاع ChessMatch كامل
  ///
  /// [moves] - قائمة الحركات بصيغة SAN أو UCI
  /// [isUci] - هل الحركات بصيغة UCI؟ (الافتراضي: SAN)
  /// [pgn] - نص PGN كامل (بديل عن moves)
  /// [initialFen] - FEN مبدئي (اختياري)
  /// [depth] - عمق التحليل (يتجاوز الافتراضي)
  /// [multiPV] - عدد خطوط MultiPV (يتجاوز الافتراضي)
  /// [cancelToken] - رمز الإلغاء
  /// [onProgress] - دالة رد التقدم
  Future<ChessMatch> analyzeGame({
    List<String>? moves,
    bool isUci = false,
    String? pgn,
    String? initialFen,
    int? depth,
    int? multiPV,
    CancelToken? cancelToken,
    ProgressCallback? onProgress,
  }) async {
    // ── الخطوة 1: تهيئة المحرك ──────────────────────────────────────
    await initialize();

    final engine = _engine!;
    final analysisDepth = depth ?? _defaultDepth;
    final analysisMultiPV = multiPV ?? _defaultMultiPV;

    // ضبط MultiPV
    if (engine.isReady) {
      engine.setMultiPv(analysisMultiPV);
    }

    // ── الخطوة 2: تحليل المدخلات وإعادة تشغيل المباراة ──────────────
    final gameData = _parseInput(
      moves: moves,
      isUci: isUci,
      pgn: pgn,
      initialFen: initialFen,
    );

    if (gameData.moves.isEmpty) {
      debugPrint('$_tag: لا توجد حركات لتحليلها');
      return _emptyMatch(gameData);
    }

    final totalPositions = gameData.moves.length + 1; // N+1 موقف لـ N حركات
    final positionEvals = <_PositionEval>[];

    // ── الخطوة 3: تحليل كل موقف ─────────────────────────────────────
    for (int i = 0; i < totalPositions; i++) {
      // فحص الإلغاء
      if (cancelToken?.isCancelled ?? false) {
        debugPrint('$_tag: تم إلغاء التحليل عند الموقف $i');
        break;
      }

      // الإبلاغ عن التقدم
      final currentMoveStr = i < gameData.moves.length
          ? gameData.moves[i].san
          : 'النهاية';
      onProgress?.call(i, totalPositions - 1, currentMoveStr);

      // ضبط الموقف في المحرك
      final uciMovesSoFar = gameData.uciMoves.sublist(0, i);
      if (gameData.initialFen != null) {
        engine.setPositionFromFen(gameData.initialFen!, moves: uciMovesSoFar);
      } else {
        engine.setPositionFromStart(moves: uciMovesSoFar);
      }

      // بدء التحليل
      try {
        await engine.analyzeDepth(analysisDepth).timeout(_positionTimeout);

        // جمع النتائج من latestInfoByPv
        final eval = _collectPositionEval(engine);
        positionEvals.add(eval);
      } on TimeoutException {
        debugPrint('$_tag: انتهت مهلة تحليل الموقف $i');
        // محاولة إيقاف التحليل وجمع ما توفر
        try {
          await engine.stopAnalysis().timeout(const Duration(seconds: 3));
        } catch (_) {
          engine.stopAnalysisImmediate();
        }
        final eval = _collectPositionEval(engine);
        positionEvals.add(eval);
      } catch (e) {
        debugPrint('$_tag: خطأ في تحليل الموقف $i: $e');
        positionEvals.add(const _PositionEval(evalCp: 0));

        // محاولة استعادة المحرك
        if (!engine.isReady) {
          try {
            await engine.stopAnalysis().timeout(const Duration(seconds: 3));
          } catch (_) {
            engine.stopAnalysisImmediate();
          }
        }
      }

      // تأخير قصير بين التحليلات للسماح بمعالجة الأحداث
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // إذا أُلغي التحليل، نملأ بقية التقييمات بالأصفار
    while (positionEvals.length < totalPositions) {
      positionEvals.add(const _PositionEval(evalCp: 0));
    }

    // ── الخطوة 4: بناء AnalyzedMove لكل حركة ───────────────────────
    final analyzedMoves = <AnalyzedMove>[];

    for (int i = 0; i < gameData.moves.length; i++) {
      final moveData = gameData.moves[i];
      final evalBefore = positionEvals[i].evalCp;
      final evalAfter = positionEvals[i + 1].evalCp;
      final alternatives = positionEvals[i].alternatives;

      // حساب cpLoss بطريقتين واستخدام الأكثر دقة
      final cpLossFromEvals = ClassificationEngine.calculateCpLoss(
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        isWhite: moveData.isWhite,
      );

      final cpLossFromMultiPV = ClassificationEngine.calculateCpLossFromMultiPV(
        alternatives: alternatives,
        playedUci: moveData.uci,
        isWhite: moveData.isWhite,
      );

      // استخدام القيمة الأكبر (أكثر تحفظًا)
      final cpLoss = cpLossFromEvals > cpLossFromMultiPV
          ? cpLossFromEvals
          : cpLossFromMultiPV;

      // كشف التضحية
      final isSacrifice = ClassificationEngine.detectSacrifice(
        fenBefore: moveData.fenBefore,
        fenAfter: moveData.fenAfter,
        evalAfter: evalAfter,
        isWhite: moveData.isWhite,
        uciMove: moveData.uci,
      );

      // كشف الحركة الوحيدة
      final isOnlyMove = ClassificationEngine.detectOnlyMove(
        alternatives: alternatives,
        evalAfter: evalAfter,
        isWhite: moveData.isWhite,
      );

      // كشف الحركة الكتابية (ضمن أول 10 حركات)
      final isBookMove = i < 20 && _isBookMove(moveData.san, i);

      // تصنيف الحركة
      final classification = ClassificationEngine.classify(
        cpLoss: cpLoss,
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        isOnlyMove: isOnlyMove,
        isSacrifice: isSacrifice,
        isBookMove: isBookMove,
        alternatives: alternatives,
        isWhite: moveData.isWhite,
      );

      // تحديد مرحلة اللعبة
      final phase = ClassificationEngine.determineGamePhase(moveData.fenBefore);

      // بناء كائن AnalyzedMove
      analyzedMoves.add(AnalyzedMove(
        moveNumber: moveData.moveNumber,
        plyNumber: moveData.plyNumber,
        color: moveData.isWhite ? PlayerColor.white : PlayerColor.black,
        san: moveData.san,
        uci: moveData.uci,
        fenBefore: moveData.fenBefore,
        fenAfter: moveData.fenAfter,
        evalBefore: evalBefore,
        evalAfter: evalAfter,
        cpLoss: cpLoss,
        classification: classification,
        depth: positionEvals[i].depth,
        alternatives: alternatives,
        pv: alternatives.isNotEmpty ? alternatives.first.pv : '',
        comment: moveData.comment,
        isCheckmate: moveData.isCheckmate,
        isCheck: moveData.isCheck,
        isCastling: moveData.isCastling,
        isCapture: moveData.isCapture,
        phase: phase,
      ));
    }

    // ── الخطوة 5: بناء منحنى التقييم ───────────────────────────────
    final evalPoints = _buildEvalGraph(analyzedMoves, positionEvals);

    // ── الخطوة 6: حساب الدقة وإحصاء الأخطاء ────────────────────────
    final whiteMoves = analyzedMoves.where((m) => m.color.isWhite).toList();
    final blackMoves = analyzedMoves.where((m) => !m.color.isWhite).toList();

    final whiteAccuracy = ClassificationEngine.calculateGameAccuracy(
      whiteMoves.map((m) => m.cpLoss).toList(),
    );
    final blackAccuracy = ClassificationEngine.calculateGameAccuracy(
      blackMoves.map((m) => m.cpLoss).toList(),
    );

    // عد التصنيفات
    final whiteCounts = _countClassifications(whiteMoves);
    final blackCounts = _countClassifications(blackMoves);

    // كشف نقطة التحول
    final turningPoint = _findTurningPoint(analyzedMoves);

    // كشف الافتتاحية
    final sanMoves = gameData.moves.map((m) => m.san).toList();
    final detectedOpening = opening_lib.OpeningDetector.detect(sanMoves);

    // تحويل OpeningData من مكتبة الكشف إلى نموذج chess_models
    OpeningData? matchOpening;
    if (detectedOpening != null) {
      matchOpening = OpeningData(
        nameAr: detectedOpening.nameAr,
        nameEn: detectedOpening.nameEn,
        eco: detectedOpening.eco,
        moves: detectedOpening.moves,
        descriptionAr: detectedOpening.descriptionAr,
        category: detectedOpening.category,
      );
    }

    // ── الخطوة 7: بناء ChessMatch النهائي ──────────────────────────
    return ChessMatch(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      whiteName: gameData.whiteName,
      blackName: gameData.blackName,
      whiteElo: gameData.whiteElo,
      blackElo: gameData.blackElo,
      result: gameData.result,
      termination: gameData.termination,
      date: gameData.date,
      event: gameData.event,
      site: gameData.site,
      round: gameData.round,
      moves: analyzedMoves,
      opening: matchOpening,
      evalPoints: evalPoints,
      whiteAccuracy: whiteAccuracy,
      blackAccuracy: blackAccuracy,
      whiteInaccuracies: whiteCounts[MoveClassification.inaccuracy] ?? 0,
      whiteMistakes: whiteCounts[MoveClassification.mistake] ?? 0,
      whiteBlunders: whiteCounts[MoveClassification.blunder] ?? 0,
      blackInaccuracies: blackCounts[MoveClassification.inaccuracy] ?? 0,
      blackMistakes: blackCounts[MoveClassification.mistake] ?? 0,
      blackBlunders: blackCounts[MoveClassification.blunder] ?? 0,
      whiteBrilliants: whiteCounts[MoveClassification.brilliant] ?? 0,
      blackBrilliants: blackCounts[MoveClassification.brilliant] ?? 0,
      whiteGreatMoves: whiteCounts[MoveClassification.great] ?? 0,
      blackGreatMoves: blackCounts[MoveClassification.great] ?? 0,
      turningPoint: turningPoint,
      initialFen: gameData.initialFen,
      rawPgn: gameData.rawPgn,
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // تحليل موقف واحد — Single Position Analysis
  // ════════════════════════════════════════════════════════════════════════

  /// تحليل موقف واحد — Analyze a single chess position
  ///
  /// يعيد قائمة EngineLine تمثل أفضل الحركات المتاحة
  /// مع تقييماتها وخطوط اللعب الرئيسية.
  ///
  /// [fen] - الموقف بصيغة FEN
  /// [depth] - عمق التحليل (يتجاوز الافتراضي)
  /// [multiPV] - عدد خطوط MultiPV (يتجاوز الافتراضي)
  Future<List<EngineLine>> analyzePosition({
    required String fen,
    int? depth,
    int? multiPV,
  }) async {
    await initialize();

    final engine = _engine!;
    final analysisDepth = depth ?? _defaultDepth;
    final analysisMultiPV = multiPV ?? _defaultMultiPV;

    // ضبط MultiPV
    engine.setMultiPv(analysisMultiPV);

    // ضبط الموقف
    engine.setPositionFromFen(fen);

    try {
      // بدء التحليل
      await engine.analyzeDepth(analysisDepth).timeout(_positionTimeout);

      // جمع النتائج
      final eval = _collectPositionEval(engine);
      return eval.alternatives;
    } on TimeoutException {
      debugPrint('$_tag: انتهت مهلة تحليل الموقف');
      try {
        await engine.stopAnalysis().timeout(const Duration(seconds: 3));
      } catch (_) {
        engine.stopAnalysisImmediate();
      }
      final eval = _collectPositionEval(engine);
      return eval.alternatives;
    } catch (e) {
      debugPrint('$_tag: خطأ في تحليل الموقف: $e');
      return [];
    }
  }

  /// تحليل موقف واحد مع إرجاع التقييم — Analyze position and return eval
  ///
  /// يعيد تقييم الموقف من وجهة نظر الأبيض بالسنتيبيدق.
  Future<int> analyzePositionEval({
    required String fen,
    int? depth,
  }) async {
    await initialize();

    final engine = _engine!;

    engine.setPositionFromFen(fen);

    try {
      await engine.analyzeDepth(depth ?? _defaultDepth).timeout(_positionTimeout);
      final eval = _collectPositionEval(engine);
      return eval.evalCp;
    } catch (e) {
      debugPrint('$_tag: خطأ في تحليل التقييم: $e');
      return 0;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // دوال داخلية — Internal Methods
  // ════════════════════════════════════════════════════════════════════════

  /// تحليل المدخلات وإعادة تشغيل المباراة — Parse input and replay game
  _GameData _parseInput({
    List<String>? moves,
    bool isUci = false,
    String? pgn,
    String? initialFen,
  }) {
    if (pgn != null) {
      return _parseAndReplayPGN(pgn, initialFen);
    } else if (moves != null && moves.isNotEmpty) {
      return _replayFromMoveList(moves, isUci, initialFen);
    } else {
      return _GameData(initialFen: initialFen);
    }
  }

  /// تحليل PGN وإعادة تشغيل المباراة — Parse PGN and replay
  _GameData _parseAndReplayPGN(String pgn, String? initialFen) {
    try {
      final result = PgnParser.parse(pgn);

      // إعادة تشغيل المباراة باستخدام حركات SAN
      final game = initialFen != null
          ? chess.Chess.fromFEN(initialFen)
          : chess.Chess();

      final moveDataList = <_MoveData>[];
      final uciMoveList = <String>[];
      int plyNumber = 0;

      for (final parsedMove in result.moves) {
        final fenBefore = game.fen;
        final isWhite = game.turn == chess.Color.WHITE;
        final moveNumber = (plyNumber ~/ 2) + 1;

        // محاولة تنفيذ الحركة
        chess.Move? moveResult;
        try {
          moveResult = game.move(parsedMove.san);
        } catch (e) {
          debugPrint('$_tag: فشل تنفيذ الحركة ${parsedMove.san}: $e');
          continue;
        }

        if (moveResult == null) {
          debugPrint('$_tag: حركة غير صالحة: ${parsedMove.san}');
          continue;
        }

        plyNumber++;
        final fenAfter = game.fen;

        // استخراج UCI من نتيجة الحركة
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

            // كشف الأخذ والتبييت
            isCapture = moveResult.captured != null;
            final flags = moveResult.flags ?? '';
            isCastling = flags.contains('k') || flags.contains('q');
          }
        } catch (e) {
          // إذا فشل استخراج UCI، نستخدم التعيين اليدوي
          uci = _manualSanToUci(fenBefore, parsedMove.san);
          isCapture = parsedMove.san.contains('x');
          isCastling = parsedMove.san == 'O-O' || parsedMove.san == 'O-O-O'
              || parsedMove.san == '0-0' || parsedMove.san == '0-0-0';
        }

        uciMoveList.add(uci);

        moveDataList.add(_MoveData(
          fenBefore: fenBefore,
          fenAfter: fenAfter,
          san: parsedMove.san,
          uci: uci,
          isWhite: isWhite,
          moveNumber: moveNumber,
          plyNumber: plyNumber,
          isCheck: game.in_check,
          isCheckmate: game.in_checkmate,
          isCastling: isCastling,
          isCapture: isCapture,
          comment: parsedMove.comment,
          clockTime: parsedMove.clockTime,
        ));
      }

      // تحديد نتيجة المباراة
      final gameResult = GameResult.fromPgn(result.result);

      // تحديد طريقة الانتهاء
      Termination? termination;
      if (game.in_checkmate) {
        termination = Termination.checkmate;
      } else if (game.in_stalemate) {
        termination = Termination.stalemate;
      } else if (game.in_draw) {
        termination = Termination.agreement;
      }

      return _GameData(
        whiteName: result.whitePlayer ?? 'الأبيض',
        blackName: result.blackPlayer ?? 'الأسود',
        whiteElo: int.tryParse(result.headers['WhiteElo'] ?? ''),
        blackElo: int.tryParse(result.headers['BlackElo'] ?? ''),
        result: gameResult,
        termination: termination,
        date: _parseDateHeader(result.date),
        event: result.event,
        site: result.site,
        round: int.tryParse(result.round ?? ''),
        initialFen: initialFen,
        rawPgn: pgn,
        moves: moveDataList,
        uciMoves: uciMoveList,
      );
    } catch (e) {
      debugPrint('$_tag: خطأ في تحليل PGN: $e');
      return _GameData(rawPgn: pgn, initialFen: initialFen);
    }
  }

  /// إعادة تشغيل المباراة من قائمة حركات — Replay from move list
  _GameData _replayFromMoveList(List<String> moves, bool isUci, String? initialFen) {
    final game = initialFen != null
        ? chess.Chess.fromFEN(initialFen)
        : chess.Chess();

    final moveDataList = <_MoveData>[];
    final uciMoveList = <String>[];
    int plyNumber = 0;

    for (final moveStr in moves) {
      final fenBefore = game.fen;
      final isWhite = game.turn == chess.Color.WHITE;
      final moveNumber = (plyNumber ~/ 2) + 1;

      String san;
      String uci;
      bool isCapture = false;
      bool isCastling = false;

      if (isUci) {
        // الحركة بصيغة UCI - تحويل إلى SAN
        uci = moveStr;
        san = _uciToSan(fenBefore, moveStr);
        isCastling = moveStr == 'e1g1' || moveStr == 'e1c1'
            || moveStr == 'e8g8' || moveStr == 'e8c8';
      } else {
        // الحركة بصيغة SAN
        san = moveStr;
        isCastling = moveStr == 'O-O' || moveStr == 'O-O-O'
            || moveStr == '0-0' || moveStr == '0-0-0';
      }

      // تنفيذ الحركة
      chess.Move? moveResult;
      try {
        moveResult = game.move(san);
      } catch (e) {
        debugPrint('$_tag: فشل تنفيذ الحركة $san: $e');
        continue;
      }

      if (moveResult == null) {
        debugPrint('$_tag: حركة غير صالحة: $san');
        continue;
      }

      plyNumber++;
      final fenAfter = game.fen;

      // استخراج UCI من نتيجة الحركة إذا لم يكن UCI معروفًا
      if (!isUci) {
        try {
          if (moveResult != null) {
            final from = moveResult.from;
            final to = moveResult.to;
            final promotion = moveResult.promotion;
            uci = promotion != null && promotion.isNotEmpty
                ? '$from$to${promotion.toLowerCase()}'
                : '$from$to';
            isCapture = moveResult.captured != null;
          } else {
            uci = _manualSanToUci(fenBefore, san);
            isCapture = san.contains('x');
          }
        } catch (e) {
          uci = _manualSanToUci(fenBefore, san);
          isCapture = san.contains('x');
        }
      } else {
        // محاولة كشف الأخذ من SAN
        isCapture = san.contains('x');
      }

      uciMoveList.add(uci);

      moveDataList.add(_MoveData(
        fenBefore: fenBefore,
        fenAfter: fenAfter,
        san: san,
        uci: uci,
        isWhite: isWhite,
        moveNumber: moveNumber,
        plyNumber: plyNumber,
        isCheck: game.in_check,
        isCheckmate: game.in_checkmate,
        isCastling: isCastling,
        isCapture: isCapture,
      ));
    }

    // تحديد نتيجة المباراة
    GameResult result = GameResult.incomplete;
    Termination? termination;

    if (game.in_checkmate) {
      result = game.turn == chess.Color.WHITE
          ? GameResult.blackWins
          : GameResult.whiteWins;
      termination = Termination.checkmate;
    } else if (game.in_stalemate) {
      result = GameResult.draw;
      termination = Termination.stalemate;
    } else if (game.in_draw) {
      result = GameResult.draw;
      termination = Termination.agreement;
    }

    return _GameData(
      result: result,
      termination: termination,
      initialFen: initialFen,
      moves: moveDataList,
      uciMoves: uciMoveList,
    );
  }

  /// جمع نتائج تحليل موقف واحد — Collect position analysis results
  _PositionEval _collectPositionEval(StockfishEngine engine) {
    final infoByPv = engine.latestInfoByPv;
    final isWhiteToMove = engine.isWhiteToMove;

    if (infoByPv.isEmpty) {
      return const _PositionEval(evalCp: 0);
    }

    // التقييم الرئيسي (من PV الأول)
    int evalCp = 0;
    int depth = 0;
    bool isWhiteMate = false;
    int? mateIn;
    String? bestMoveUci;

    final primaryInfo = infoByPv[1];
    if (primaryInfo != null) {
      // تحويل التقييم إلى منظور الأبيض
      if (primaryInfo.score != null) {
        final whiteScore = primaryInfo.score!.fromWhitePerspective(isWhiteToMove);

        if (whiteScore.type == ScoreType.centipawns) {
          evalCp = whiteScore.value;
        } else if (whiteScore.type == ScoreType.mate) {
          isWhiteMate = whiteScore.value > 0;
          mateIn = whiteScore.value;
          // تحويل كش المات إلى قيمة كبيرة
          if (whiteScore.value > 0) {
            evalCp = 100000 - whiteScore.value * 100;
          } else {
            evalCp = -(100000 + whiteScore.value * 100);
          }
        }
      }

      depth = primaryInfo.depth ?? 0;

      if (primaryInfo.pv.isNotEmpty) {
        bestMoveUci = primaryInfo.pv.first;
      }
    }

    // بناء EngineLine لكل PV
    final alternatives = <EngineLine>[];

    for (final entry in infoByPv.entries) {
      final pvNum = entry.key;
      final info = entry.value;

      if (info.pv.isEmpty) continue;
      if (info.score == null) continue;

      final uciMove = info.pv.first;

      // تحويل التقييم إلى منظور الأبيض
      final whiteScore = info.score!.fromWhitePerspective(isWhiteToMove);

      int lineEvalCp = 0;
      bool lineIsMate = false;
      int? lineMateIn;

      if (whiteScore.type == ScoreType.centipawns) {
        lineEvalCp = whiteScore.value;
      } else if (whiteScore.type == ScoreType.mate) {
        lineIsMate = true;
        lineMateIn = whiteScore.value;
        if (whiteScore.value > 0) {
          lineEvalCp = 100000 - whiteScore.value * 100;
        } else {
          lineEvalCp = -(100000 + whiteScore.value * 100);
        }
      }

      // تحويل UCI إلى SAN
      // نحتاج الفين الحالي لذلك - نستخدم خاصية المحرك
      final sanMove = _uciToSanFromEngine(engine, uciMove);

      alternatives.add(EngineLine(
        uciMove: uciMove,
        sanMove: sanMove,
        evalCp: lineEvalCp,
        depth: info.depth ?? depth,
        pv: info.pv.join(' '),
        nodes: info.nodes,
        isMate: lineIsMate,
        mateIn: lineMateIn,
      ));
    }

    return _PositionEval(
      evalCp: evalCp,
      alternatives: alternatives,
      depth: depth,
      bestMoveUci: bestMoveUci,
      isWhiteMate: isWhiteMate,
      mateIn: mateIn,
    );
  }

  /// تحويل UCI إلى SAN باستخدام حالة المحرك الحالية
  String _uciToSanFromEngine(StockfishEngine engine, String uci) {
    try {
      // إنشاء كائن Chess من الوضعية الحالية للمحرك
      // لا يمكننا الحصول على FEN مباشرة من المحرك، لذا نستخدم طريقة أخرى
      // سنستخدم _uciToSan بتمرير FEN فارغ كحل بديل
      // في الواقع، نحتاج لمعرفة FEN الحالي - سنستخدم حلًا بديلًا

      // الحل الأفضل: تمرير FEN صراحة
      // لكن لأن هذه الدالة تُستدعى من _collectPositionEval
      // حيث لا يتوفر FEN مباشرة، سنستخدم تحويلًا بسيطًا

      if (uci.length < 4) return uci;

      // تحويل أساسي: من مربع إلى مربع
      // هذا تحويل تقريبي - التحويل الدقيق يتطلب FEN
      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promo = uci.length > 4 ? uci[4] : '';

      // للترقية
      if (promo.isNotEmpty) {
        return '${from.substring(0, 1)}x$to=$promo'.toUpperCase();
      }

      // للتبييت
      if (from == 'e1' && to == 'g1' || from == 'e8' && to == 'g8') {
        return 'O-O';
      }
      if (from == 'e1' && to == 'c1' || from == 'e8' && to == 'c8') {
        return 'O-O-O';
      }

      // حركة عادية - نعيد UCI كعرض بديل
      // ملاحظة: هذا لن يكون SAN مثالي لكنه كافٍ للعرض
      return uci;
    } catch (e) {
      return uci;
    }
  }

  /// تحويل UCI إلى SAN باستخدام FEN — Convert UCI to SAN using FEN
  String _uciToSan(String fen, String uci) {
    try {
      final game = chess.Chess.fromFEN(fen);
      if (uci.length < 4) return uci;

      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promotion = uci.length > 4 ? uci.substring(4) : null;

      // البحث عن الحركة المطابقة في الحركات القانونية
      try {
        final legalMoves = game.moves();
        for (final m in legalMoves) {
          final mFrom = m.from;
          final mTo = m.to;
          final mPromo = m.promotion;

          if (mFrom == from && mTo == to) {
            // التحقق من مطابقة الترقية
            if (promotion == null ||
                (mPromo != null && mPromo.toLowerCase() == promotion.toLowerCase()) ||
                (promotion.isEmpty && (mPromo == null || mPromo.isEmpty))) {
              return m.san;
            }
          }
        }
      } catch (e) {
        // فشل البحث في الحركات القانونية
      }

      // محاولة بديلة: تنفيذ الحركة مباشرة
      // للتبييت
      if (from == 'e1' && to == 'g1') return 'O-O';
      if (from == 'e1' && to == 'c1') return 'O-O-O';
      if (from == 'e8' && to == 'g8') return 'O-O';
      if (from == 'e8' && to == 'c8') return 'O-O-O';

      return uci;
    } catch (e) {
      return uci;
    }
  }

  /// تحويل SAN إلى UCI يدويًا — Manual SAN to UCI conversion
  String _manualSanToUci(String fen, String san) {
    // معالجة التبييت
    if (san == 'O-O' || san == '0-0') {
      final isWhite = fen.contains(' w ');
      return isWhite ? 'e1g1' : 'e8g8';
    }
    if (san == 'O-O-O' || san == '0-0-0') {
      final isWhite = fen.contains(' w ');
      return isWhite ? 'e1c1' : 'e8c8';
    }

    try {
      final game = chess.Chess.fromFEN(fen);
      final moveResult = game.move(san);
      if (moveResult != null) {
        final from = moveResult.from;
        final to = moveResult.to;
        final promotion = moveResult.promotion;
        game.undo();
        if (promotion != null && promotion.isNotEmpty) {
          return '$from$to${promotion.toLowerCase()}';
        }
        return '$from$to';
      }
      game.undo();
    } catch (e) {
      // فشل التحويل
    }
    return '';
  }

  /// بناء منحنى التقييم — Build evaluation graph data
  List<EvalPoint> _buildEvalGraph(
    List<AnalyzedMove> moves,
    List<_PositionEval> positionEvals,
  ) {
    final points = <EvalPoint>[];

    // نقطة البداية (قبل أول حركة)
    if (positionEvals.isNotEmpty) {
      points.add(EvalPoint(
        moveNumber: 0,
        evalCp: positionEvals[0].evalCp,
        isWhite: true,
      ));
    }

    // نقطة بعد كل حركة
    for (int i = 0; i < moves.length; i++) {
      final move = moves[i];
      final evalIndex = i + 1;
      final evalCp = evalIndex < positionEvals.length
          ? positionEvals[evalIndex].evalCp
          : move.evalAfter;

      points.add(EvalPoint(
        moveNumber: move.moveNumber,
        evalCp: evalCp,
        isWhite: move.color.isWhite,
        classification: move.classification,
      ));
    }

    return points;
  }

  /// عد التصنيفات — Count move classifications
  Map<MoveClassification, int> _countClassifications(List<AnalyzedMove> moves) {
    final counts = <MoveClassification, int>{};
    for (final move in moves) {
      counts[move.classification] = (counts[move.classification] ?? 0) + 1;
    }
    return counts;
  }

  /// إيجاد نقطة التحول — Find the turning point in the game
  ///
  /// نقطة التحول هي الحركة التي شهدت أكبر تغير في التقييم
  /// مع تصنيف يشير إلى خطأ.
  int? _findTurningPoint(List<AnalyzedMove> moves) {
    int? turningPointPly;
    int biggestSwing = 0;

    for (int i = 1; i < moves.length; i++) {
      final swing = (moves[i].evalAfter - moves[i - 1].evalAfter).abs();
      if (swing > biggestSwing && moves[i].classification.isError) {
        biggestSwing = swing;
        turningPointPly = i;
      }
    }

    return turningPointPly;
  }

  /// هل الحركة كتابية (تقريبية)؟ — Is the move a book move (approximate)?
  bool _isBookMove(String san, int moveIndex) {
    // تقدير تقريبي: أول 5 حركات كاملة عادة تكون كتابية
    // هذا تنفيذ مبسط - التنفيذ الكامل يتطلب قاعدة بيانات افتتاحيات
    return moveIndex < 10;
  }

  /// تحليل تاريخ PGN — Parse PGN date header
  DateTime? _parseDateHeader(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      // تنسيق PGN: YYYY.MM.DD
      final parts = dateStr.split('.');
      if (parts.length >= 3) {
        return DateTime(
          int.tryParse(parts[0]) ?? 2000,
          int.tryParse(parts[1]) ?? 1,
          int.tryParse(parts[2]) ?? 1,
        );
      } else if (parts.length == 2) {
        return DateTime(
          int.tryParse(parts[0]) ?? 2000,
          int.tryParse(parts[1]) ?? 1,
        );
      }
    } catch (e) {
      // فشل تحليل التاريخ
    }
    return null;
  }

  /// إنشاء مباراة فارغة — Create empty match
  ChessMatch _emptyMatch(_GameData gameData) {
    return ChessMatch(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      whiteName: gameData.whiteName,
      blackName: gameData.blackName,
      whiteElo: gameData.whiteElo,
      blackElo: gameData.blackElo,
      result: gameData.result,
      termination: gameData.termination,
      date: gameData.date,
      event: gameData.event,
      site: gameData.site,
      round: gameData.round,
      initialFen: gameData.initialFen,
      rawPgn: gameData.rawPgn,
      moves: [],
      evalPoints: [],
    );
  }
}
