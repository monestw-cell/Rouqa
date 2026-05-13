/// training_engine.dart
/// محرك التدريب — Training Engine
///
/// وضع اللعب ضد المحرك، التحقق من الحركات، إدارة حالة اللعبة.
library;

import 'dart:async';
import 'package:chess/chess.dart' as chess;
import '../engine/stockfish_engine.dart';
import '../models/chess_models.dart';

/// حالة لعبة التدريب
class TrainingGameState {
  /// كائن الشطرنج
  final chess.Chess game;

  /// مستوى ELO للمحرك
  final int engineElo;

  /// الحركات المنفذة
  final List<String> movesSan;

  /// الحركات بصيغة UCI
  final List<String> movesUci;

  /// القطع المأسورة للأبيض
  final List<String> capturedByWhite;

  /// القطع المأسورة للأسود
  final List<String> capturedByBlack;

  /// حالة اللعبة
  final TrainingGameStatus status;

  /// زمن الأبيض المتبقي (مللي ثانية)
  final int? whiteTimeMs;

  /// زمن الأسود المتبقي (مللي ثانية)
  final int? blackTimeMs;

  /// هل اللعبة جارية؟
  bool get isPlaying => status == TrainingGameStatus.playing;

  /// FEN الحالي
  String get fen => game.fen;

  /// هل دور الأبيض؟
  bool get isWhiteTurn => game.turn == chess.Color.WHITE;

  const TrainingGameState({
    required this.game,
    required this.engineElo,
    this.movesSan = const [],
    this.movesUci = const [],
    this.capturedByWhite = const [],
    this.capturedByBlack = const [],
    this.status = TrainingGameStatus.playing,
    this.whiteTimeMs,
    this.blackTimeMs,
  });

  TrainingGameState copyWith({
    chess.Chess? game,
    int? engineElo,
    List<String>? movesSan,
    List<String>? movesUci,
    List<String>? capturedByWhite,
    List<String>? capturedByBlack,
    TrainingGameStatus? status,
    int? whiteTimeMs,
    int? blackTimeMs,
  }) {
    return TrainingGameState(
      game: game ?? this.game,
      engineElo: engineElo ?? this.engineElo,
      movesSan: movesSan ?? this.movesSan,
      movesUci: movesUci ?? this.movesUci,
      capturedByWhite: capturedByWhite ?? this.capturedByWhite,
      capturedByBlack: capturedByBlack ?? this.capturedByBlack,
      status: status ?? this.status,
      whiteTimeMs: whiteTimeMs ?? this.whiteTimeMs,
      blackTimeMs: blackTimeMs ?? this.blackTimeMs,
    );
  }
}

/// حالة لعبة التدريب
enum TrainingGameStatus {
  playing,
  whiteWins,
  blackWins,
  draw,
  resigned,
  aborted,
}

/// محرك التدريب — يدير اللعب ضد المحرك
class TrainingEngine {
  static const _tag = 'TrainingEngine';

  /// محرك Stockfish
  StockfishEngine? _engine;

  /// حالة اللعبة
  TrainingGameState? _state;

  /// استدعاء عند تغير الحالة
  void Function(TrainingGameState state)? onStateChanged;

  /// استدعاء عند حركة المحرك
  void Function(String san, String uci)? onEngineMoved;

  /// استدعاء عند انتهاء اللعبة
  void Function(TrainingGameStatus status, String message)? onGameEnded;

  /// مؤقت الزمن
  Timer? _timeTimer;

  /// هل يلعب المستخدم بالأبيض؟
  bool _userPlaysWhite = true;

  /// إنشاء لعبة جديدة
  Future<void> newGame({
    required int engineElo,
    bool userPlaysWhite = true,
    int? timeControlSeconds,
    int? incrementSeconds,
  }) async {
    _userPlaysWhite = userPlaysWhite;

    // إيقاف اللعبة السابقة
    await dispose();

    // تهيئة المحرك
    _engine = StockfishEngine();
    try {
      await _engine!.initialize();
      _engine!.setLimitStrength(true);
      _engine!.setElo(engineElo.clamp(100, 2850));
      _engine!.setThreads(1);
      _engine!.setHashSize(64);
    } catch (e) {
      // استخدام محرك وهمي إذا لم يتوفر Stockfish
    }

    final game = chess.Chess();

    _state = TrainingGameState(
      game: game,
      engineElo: engineElo,
      status: TrainingGameStatus.playing,
      whiteTimeMs: timeControlSeconds != null ? timeControlSeconds * 1000 : null,
      blackTimeMs: timeControlSeconds != null ? timeControlSeconds * 1000 : null,
    );

    onStateChanged?.call(_state!);

    // إذا كان المحرك يبدأ (الأسود يبدأ إذا كان المستخدم أبيض)
    if (!_userPlaysWhite) {
      _makeEngineMove();
    }

    // بدء مؤقت الزمن
    if (timeControlSeconds != null) {
      _startTimeTimer();
    }
  }

  /// تنفيذ حركة اللاعب
  bool makePlayerMove(String fromSquare, String toSquare, {String? promotion}) {
    if (_state == null || !_state!.isPlaying) return false;

    final game = _state!.game;

    // البحث عن الحركة القانونية
    String? sanMove;
    try {
      final legalMoves = game.moves();
      for (final m in legalMoves) {
        final mFrom = m.from;
        final mTo = m.to;
        final mPromo = m.promotion;
        if (mFrom == fromSquare && mTo == toSquare) {
          if (promotion == null ||
              (mPromo != null && mPromo.toLowerCase() == promotion.toLowerCase()) ||
              (promotion == null && (mPromo == null || mPromo.isEmpty))) {
            sanMove = m.san;
            break;
          }
        }
      }
    } catch (_) {
      return false;
    }

    if (sanMove == null) return false;

    // تسجيل القطعة المأسورة قبل الحركة
    final capturedPiece = game.get(toSquare);

    // تنفيذ الحركة
    try {
      final result = game.move(sanMove);
      if (result == null) return false;
    } catch (_) {
      return false;
    }

    // تحديث الحالة
    final uci = '$fromSquare$toSquare${promotion ?? ''}';
    final newMovesSan = List<String>.from(_state!.movesSan)..add(sanMove);
    final newMovesUci = List<String>.from(_state!.movesUci)..add(uci);

    List<String> newCapturedByWhite = List.from(_state!.capturedByWhite);
    List<String> newCapturedByBlack = List.from(_state!.capturedByBlack);

    if (capturedPiece != null) {
      final isWhiteCapture = game.turn == chess.Color.BLACK; // الحركة السابقة كانت للأبيض
      final pieceChar = capturedPiece.type.name;
      if (isWhiteCapture) {
        newCapturedByWhite.add(pieceChar);
      } else {
        newCapturedByBlack.add(pieceChar);
      }
    }

    // التحقق من انتهاء اللعبة
    final status = _checkGameEnd(game);

    _state = _state!.copyWith(
      movesSan: newMovesSan,
      movesUci: newMovesUci,
      capturedByWhite: newCapturedByWhite,
      capturedByBlack: newCapturedByBlack,
      status: status,
    );

    onStateChanged?.call(_state!);

    if (status != TrainingGameStatus.playing) {
      _handleGameEnd(status);
      return true;
    }

    // حركة المحرك
    _makeEngineMove();
    return true;
  }

  /// تنفيذ حركة المحرك
  Future<void> _makeEngineMove() async {
    if (_state == null || !_state!.isPlaying) return;
    if (_engine == null || !_engine!.isReady) {
      // محرك وهمي — حركة عشوائية
      _makeRandomMove();
      return;
    }

    try {
      // ضبط الموقف
      if (_state!.movesUci.isEmpty) {
        _engine!.setPositionFromStart();
      } else {
        _engine!.setPositionFromStart(moves: _state!.movesUci);
      }

      // تحليل بوقت قصير
      final bestMove = await _engine!.analyzeTime(500).timeout(
        const Duration(seconds: 5),
      );

      final uci = bestMove.bestMove;
      if (uci.length < 4) {
        _makeRandomMove();
        return;
      }

      final from = uci.substring(0, 2);
      final to = uci.substring(2, 4);
      final promo = uci.length > 4 ? uci.substring(4) : null;

      _applyEngineMove(from, to, promo);
    } catch (e) {
      _makeRandomMove();
    }
  }

  /// حركة عشوائية (بديل عند عدم توفر المحرك)
  void _makeRandomMove() {
    if (_state == null || !_state!.isPlaying) return;

    final game = _state!.game;
    final legalMoves = game.moves();
    if (legalMoves.isEmpty) return;

    final randomIndex = DateTime.now().millisecondsSinceEpoch % legalMoves.length;
    final move = legalMoves[randomIndex];

    final san = move.san;
    final from = move.from;
    final to = move.to;
    final promo = move.promotion;

    if (san.isEmpty || from.isEmpty || to.isEmpty) return;

    _applyEngineMove(from, to, promo);
  }

  /// تطبيق حركة المحرك على اللعبة
  void _applyEngineMove(String from, String to, String? promo) {
    if (_state == null || !_state!.isPlaying) return;

    final game = _state!.game;
    final capturedPiece = game.get(to);

    // البحث عن SAN
    String? sanMove;
    try {
      final legalMoves = game.moves();
      for (final m in legalMoves) {
        final mFrom = m.from;
        final mTo = m.to;
        if (mFrom == from && mTo == to) {
          sanMove = m.san;
          break;
        }
      }
    } catch (_) {}

    if (sanMove == null) return;

    try {
      final result = game.move(sanMove);
      if (result == null) return;
    } catch (_) {
      return;
    }

    final uci = '$from$to${promo ?? ''}';
    final newMovesSan = List<String>.from(_state!.movesSan)..add(sanMove);
    final newMovesUci = List<String>.from(_state!.movesUci)..add(uci);

    List<String> newCapturedByWhite = List.from(_state!.capturedByWhite);
    List<String> newCapturedByBlack = List.from(_state!.capturedByBlack);

    if (capturedPiece != null) {
      final isBlackCapture = game.turn == chess.Color.WHITE; // الحركة السابقة كانت للأسود
      final pieceChar = capturedPiece.type.name;
      if (isBlackCapture) {
        newCapturedByBlack.add(pieceChar);
      } else {
        newCapturedByWhite.add(pieceChar);
      }
    }

    final status = _checkGameEnd(game);

    _state = _state!.copyWith(
      movesSan: newMovesSan,
      movesUci: newMovesUci,
      capturedByWhite: newCapturedByWhite,
      capturedByBlack: newCapturedByBlack,
      status: status,
    );

    onEngineMoved?.call(sanMove, uci);
    onStateChanged?.call(_state!);

    if (status != TrainingGameStatus.playing) {
      _handleGameEnd(status);
    }
  }

  /// التحقق من انتهاء اللعبة
  TrainingGameStatus _checkGameEnd(chess.Chess game) {
    if (game.in_checkmate) {
      return game.turn == chess.Color.WHITE
          ? TrainingGameStatus.blackWins
          : TrainingGameStatus.whiteWins;
    }
    if (game.in_stalemate) return TrainingGameStatus.draw;
    if (game.in_threefold_repetition) return TrainingGameStatus.draw;
    if (game.insufficient_material) return TrainingGameStatus.draw;
    if (game.halfmoveClock >= 100) return TrainingGameStatus.draw;
    return TrainingGameStatus.playing;
  }

  /// الاستسلام
  void resign() {
    if (_state == null || !_state!.isPlaying) return;

    final status = _userPlaysWhite
        ? TrainingGameStatus.blackWins
        : TrainingGameStatus.whiteWins;

    _state = _state!.copyWith(status: TrainingGameStatus.resigned);
    onStateChanged?.call(_state!);
    _handleGameEnd(TrainingGameStatus.resigned);
  }

  /// عرض التعادل
  void offerDraw() {
    if (_state == null || !_state!.isPlaying) return;
    // المحرك يقبل التعادل إذا كان التقييم متقارب
    // ببساطة: نقبل التعادل باحتمال 30%
    final accept = DateTime.now().millisecondsSinceEpoch % 10 < 3;
    if (accept) {
      _state = _state!.copyWith(status: TrainingGameStatus.draw);
      onStateChanged?.call(_state!);
      _handleGameEnd(TrainingGameStatus.draw);
    }
    // إذا رفض المحرك، تستمر اللعبة
  }

  /// بدء مؤقت الزمن
  void _startTimeTimer() {
    _timeTimer?.cancel();
    _timeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_state == null || !_state!.isPlaying) {
        timer.cancel();
        return;
      }

      final isWhiteTurn = _state!.isWhiteTurn;
      final decrement = 100; // 100 مللي ثانية

      if (isWhiteTurn && _state!.whiteTimeMs != null) {
        final newTime = _state!.whiteTimeMs! - decrement;
        if (newTime <= 0) {
          _state = _state!.copyWith(
            whiteTimeMs: 0,
            status: TrainingGameStatus.blackWins,
          );
          onStateChanged?.call(_state!);
          _handleGameEnd(TrainingGameStatus.blackWins);
          timer.cancel();
          return;
        }
        _state = _state!.copyWith(whiteTimeMs: newTime);
      } else if (!isWhiteTurn && _state!.blackTimeMs != null) {
        final newTime = _state!.blackTimeMs! - decrement;
        if (newTime <= 0) {
          _state = _state!.copyWith(
            blackTimeMs: 0,
            status: TrainingGameStatus.whiteWins,
          );
          onStateChanged?.call(_state!);
          _handleGameEnd(TrainingGameStatus.whiteWins);
          timer.cancel();
          return;
        }
        _state = _state!.copyWith(blackTimeMs: newTime);
      }

      onStateChanged?.call(_state!);
    });
  }

  /// معالجة انتهاء اللعبة
  void _handleGameEnd(TrainingGameStatus status) {
    _timeTimer?.cancel();
    _timeTimer = null;

    final message = switch (status) {
      TrainingGameStatus.whiteWins => _userPlaysWhite
          ? 'مبروك! فزت بالمباراة! 🏆'
          : 'خسرت المباراة. حاول مرة أخرى!',
      TrainingGameStatus.blackWins => _userPlaysWhite
          ? 'خسرت المباراة. حاول مرة أخرى!'
          : 'مبروك! فزت بالمباراة! 🏆',
      TrainingGameStatus.draw => 'تعادل! 🤝',
      TrainingGameStatus.resigned => 'استسلمت. خسارة!',
      TrainingGameStatus.aborted => 'تم إلغاء المباراة.',
      TrainingGameStatus.playing => '',
    };

    onGameEnded?.call(status, message);
  }

  /// الحالة الحالية
  TrainingGameState? get state => _state;

  /// تنظيف الموارد
  Future<void> dispose() async {
    _timeTimer?.cancel();
    _timeTimer = null;

    if (_engine != null) {
      try {
        await _engine!.dispose();
      } catch (_) {}
      _engine = null;
    }

    _state = null;
  }
}
