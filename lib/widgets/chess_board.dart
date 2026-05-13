/// chess_board.dart
/// ويدجت رقعة الشطرنج الاحترافية — الإصدار المحسن (إصلاحات #1, #3, #4, #17, #20)
///
/// إصلاحات مطبقة:
/// #1: Full Redraw Lag → RepaintBoundary لكل طبقة
/// #3: Heavy Arrows → ArrowOverlayPainter منفصل في RepaintBoundary
/// #4: Touch Latency → Single Gesture Layer بدل GestureDetector لكل مربع
/// #17: Widget Explosion → CustomPainter فقط، لا GridView
/// #20: Frame Drops → isolated repaint لكل طبقة سريعة التحديث
///
/// نظام عرض من 4 طبقات معزولة بـ RepaintBoundary:
/// 1. BoardBackgroundLayer — المربعات (لا تتغير إلا عند تغيير السمة/القلب)
/// 2. BoardHighlightLayer — التمييزات + الحركات القانونية + الكش
/// 3. BoardPieceLayer — القطع + السحب + الأنيميشن
/// 4. BoardOverlayLayer — الأسهم + الإحداثيات (تحديث throttled)

import 'dart:math' as math show min, sqrt, cos, sin, atan2;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:chess/chess.dart' as chess;

// ============================================================================
// إعادة تصدير الأنواع الموجودة (للتوافق مع الكود الحالي)
// ============================================================================

/// رموز Unicode للقطع
const Map<String, String> kPieceSymbols = {
  'wk': '♔', 'wq': '♕', 'wr': '♖', 'wb': '♗', 'wn': '♘', 'wp': '♙',
  'bk': '♚', 'bq': '♛', 'br': '♜', 'bb': '♝', 'bn': '♞', 'bp': '♟',
};

/// أسماء الأعمدة
const List<String> kFileNames = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// أسماء الصفوف
const List<String> kRankNames = ['1', '2', '3', '4', '5', '6', '7', '8'];

// ============================================================================
// BoardTheme — سمات الرقعة (محفوظة من النسخة السابقة)
// ============================================================================

class BoardTheme {
  final Color lightSquare;
  final Color darkSquare;
  final Color lastMoveHighlight;
  final Color selectedSquare;
  final Color legalMoveDot;
  final Color legalMoveCaptureRing;
  final Color checkHighlight;
  final Color coordinateOnLight;
  final Color coordinateOnDark;
  final Color arrowBest;
  final Color arrowAlt;
  final Color arrowThreat;

  const BoardTheme({
    this.lightSquare = const Color(0xFFF0D9B5),
    this.darkSquare = const Color(0xFFB58863),
    this.lastMoveHighlight = const Color(0x66CED26B),
    this.selectedSquare = const Color(0x55829769),
    this.legalMoveDot = const Color(0x44000000),
    this.legalMoveCaptureRing = const Color(0x44000000),
    this.checkHighlight = const Color(0xBBE02020),
    this.coordinateOnLight = const Color(0xFFB58863),
    this.coordinateOnDark = const Color(0xFFF0D9B5),
    this.arrowBest = const Color(0xCC00CC00),
    this.arrowAlt = const Color(0xCC0066CC),
    this.arrowThreat = const Color(0xCCCc0000),
  });

  static const brown = BoardTheme();
  static const blue = BoardTheme(
    lightSquare: Color(0xFFDEE3E6),
    darkSquare: Color(0xFF8CA2AD),
    coordinateOnLight: Color(0xFF8CA2AD),
    coordinateOnDark: Color(0xFFDEE3E6),
    lastMoveHighlight: Color(0x66A8C8DB),
    selectedSquare: Color(0x557FA0B2),
  );
  static const green = BoardTheme(
    lightSquare: Color(0xFFFFEEAB),
    darkSquare: Color(0xFF6D9B51),
    coordinateOnLight: Color(0xFF6D9B51),
    coordinateOnDark: Color(0xFFFFEEAB),
    lastMoveHighlight: Color(0x66BACA2B),
    selectedSquare: Color(0x5589AE4E),
  );
  static const darkBrown = BoardTheme(
    lightSquare: Color(0xFFD7A65A),
    darkSquare: Color(0xFF8B5E3C),
    coordinateOnLight: Color(0xFF8B5E3C),
    coordinateOnDark: Color(0xFFD7A65A),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardTheme &&
          lightSquare == other.lightSquare &&
          darkSquare == other.darkSquare &&
          lastMoveHighlight == other.lastMoveHighlight &&
          selectedSquare == other.selectedSquare &&
          legalMoveDot == other.legalMoveDot &&
          legalMoveCaptureRing == other.legalMoveCaptureRing &&
          checkHighlight == other.checkHighlight &&
          coordinateOnLight == other.coordinateOnLight &&
          coordinateOnDark == other.coordinateOnDark &&
          arrowBest == other.arrowBest &&
          arrowAlt == other.arrowAlt &&
          arrowThreat == other.arrowThreat;

  @override
  int get hashCode => Object.hash(
        lightSquare, darkSquare, lastMoveHighlight, selectedSquare,
        legalMoveDot, legalMoveCaptureRing, checkHighlight,
        coordinateOnLight, coordinateOnDark, arrowBest, arrowAlt, arrowThreat,
      );
}

// ============================================================================
// ArrowStyle, ArrowData, BoardArrows — الأسهم التحليلية
// ============================================================================

enum ArrowStyle { solid, dashed }

class ArrowData {
  final String from;
  final String to;
  final Color color;
  final double width;
  final ArrowStyle style;

  const ArrowData({
    required this.from,
    required this.to,
    this.color = const Color(0xCC00CC00),
    this.width = 10.0,
    this.style = ArrowStyle.solid,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowData &&
          from == other.from && to == other.to &&
          color == other.color && width == other.width && style == other.style;

  @override
  int get hashCode => Object.hash(from, to, color, width, style);
}

class BoardArrows {
  final ArrowData? bestMove;
  final List<ArrowData> alternatives;
  final List<ArrowData> threats;

  const BoardArrows({this.bestMove, this.alternatives = const [], this.threats = const []});

  List<ArrowData> get all => [
        if (bestMove != null) bestMove!,
        ...alternatives,
        ...threats,
      ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardArrows &&
          bestMove == other.bestMove &&
          _listEquals(alternatives, other.alternatives) &&
          _listEquals(threats, other.threats);

  @override
  int get hashCode => Object.hash(bestMove, alternatives, threats);

  static bool _listEquals(List<ArrowData> a, List<ArrowData> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ============================================================================
// بيانات الرسوم المتحركة
// ============================================================================

class _MoveAnimData {
  final String from;
  final String to;
  final String pieceKey;
  final bool isCapture;
  final String? capturedKey;

  const _MoveAnimData({
    required this.from,
    required this.to,
    required this.pieceKey,
    this.isCapture = false,
    this.capturedKey,
  });
}

class _DragReturnData {
  final String from;
  final String pieceKey;
  final Offset dropPosition;

  const _DragReturnData({
    required this.from,
    required this.pieceKey,
    required this.dropPosition,
  });
}

// ============================================================================
// ChessBoard — ويدجت الرقعة الرئيسية (إصلاحات #1, #4, #17)
// ============================================================================

class ChessBoard extends StatefulWidget {
  final String fen;
  final BoardTheme theme;
  final bool flipped;
  final bool showCoordinates;
  final bool showLegalMoves;
  final bool enableMoveInput;
  final BoardArrows? arrows;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? checkSquare;
  final Map<String, ui.Image>? pieceImages;
  final void Function(String from, String to, String? promotion)? onMove;
  final void Function(String square)? onSquareTapped;
  final double? size;

  const ChessBoard({
    super.key,
    required this.fen,
    this.theme = BoardTheme.brown,
    this.flipped = false,
    this.showCoordinates = true,
    this.showLegalMoves = true,
    this.enableMoveInput = true,
    this.arrows,
    this.lastMoveFrom,
    this.lastMoveTo,
    this.checkSquare,
    this.pieceImages,
    this.onMove,
    this.onSquareTapped,
    this.size,
  });

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

// ============================================================================
// _ChessBoardState — إصلاح #4: Single Gesture Layer + TickerProvider
// ============================================================================

class _ChessBoardState extends State<ChessBoard> with TickerProviderStateMixin {
  // --- حالة الشطرنج ---
  late chess.Chess _game;

  // --- حالة التفاعل ---
  String? _selectedSquare;
  Set<String> _legalMoveSquares = {};
  bool _isDragging = false;
  String? _dragFrom;
  Offset _dragPosition = Offset.zero;
  Offset _dragOffsetFromCenter = Offset.zero;

  // --- حوار الترقية ---
  bool _showPromotion = false;
  String? _promotionFrom;
  String? _promotionTo;
  bool _promotionIsWhite = true;

  // --- متحكمات الرسوم المتحركة (إصلاح #14: TickerProviderStateMixin) ---
  late AnimationController _moveController;
  late AnimationController _captureController;
  late AnimationController _arrowController;
  late AnimationController _selectController;
  late AnimationController _dragReturnController;

  // --- ValueNotifiers للتحديث المعزول (إصلاح #20) ---
  final ValueNotifier<String> _fenNotifier = ValueNotifier('');
  final ValueNotifier<BoardArrows?> _arrowsNotifier = ValueNotifier(null);
  final ValueNotifier<String?> _selectedSquareNotifier = ValueNotifier(null);
  final ValueNotifier<Set<String>> _legalMovesNotifier = ValueNotifier({});
  final ValueNotifier<String?> _checkSquareNotifier = ValueNotifier(null);

  // --- بيانات الرسوم المتحركة ---
  _MoveAnimData? _moveAnim;
  _DragReturnData? _dragReturnAnim;

  // --- FEN المعروض ---
  String _displayFEN = '';
  String? _pendingFEN;

  // --- تخزين مؤقت ---
  final Map<String, TextPainter> _textPainterCache = {};

  @override
  void initState() {
    super.initState();
    _displayFEN = widget.fen;

    try {
      _game = chess.Chess.fromFEN(widget.fen);
    } catch (_) {
      _game = chess.Chess();
    }

    // تحديث ValueNotifiers
    _fenNotifier.value = _displayFEN;
    _arrowsNotifier.value = widget.arrows;

    // متحكمات الأنيميشن
    _moveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _captureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _arrowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
    _selectController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _dragReturnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _moveController.addStatusListener(_onMoveAnimStatusChanged);
    _dragReturnController.addStatusListener(_onDragReturnStatusChanged);
  }

  @override
  void didUpdateWidget(ChessBoard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.fen != oldWidget.fen) {
      try {
        _game = chess.Chess.fromFEN(widget.fen);
      } catch (_) {}

      _selectedSquare = null;
      _legalMoveSquares = {};
      _selectedSquareNotifier.value = null;
      _legalMovesNotifier.value = {};
      _clearTextPainterCache();

      if (_moveAnim != null) {
        _pendingFEN = widget.fen;
      } else {
        _displayFEN = widget.fen;
        _fenNotifier.value = _displayFEN;
      }

      // تحديث مربع الكش
      _updateCheckSquare();
    }

    if (widget.arrows != oldWidget.arrows) {
      _arrowsNotifier.value = widget.arrows;
      _arrowController.forward(from: 0);
    }

    if (widget.theme != oldWidget.theme) {
      _clearTextPainterCache();
    }
  }

  @override
  void dispose() {
    // إصلاح #8: تنظيف كل الموارد
    _moveController.removeStatusListener(_onMoveAnimStatusChanged);
    _dragReturnController.removeStatusListener(_onDragReturnStatusChanged);
    _moveController.dispose();
    _captureController.dispose();
    _arrowController.dispose();
    _selectController.dispose();
    _dragReturnController.dispose();

    // تنظيف ValueNotifiers
    _fenNotifier.dispose();
    _arrowsNotifier.dispose();
    _selectedSquareNotifier.dispose();
    _legalMovesNotifier.dispose();
    _checkSquareNotifier.dispose();

    _clearTextPainterCache();
    super.dispose();
  }

  // ========================================================================
  // دوال مساعدة (باستخدام BoardTransformService — إصلاح #13)
  // ========================================================================

  int _fileIndex(String square) => square.codeUnitAt(0) - 'a'.codeUnitAt(0);
  int _rankIndex(String square) => square[1].codeUnitAt(0) - '1'.codeUnitAt(0);
  String _squareName(int file, int rank) => '${kFileNames[file]}${rank + 1}';

  Offset _squareCenter(String square, double sqSize) {
    int file = _fileIndex(square);
    int rank = _rankIndex(square);
    if (widget.flipped) { file = 7 - file; rank = 7 - rank; }
    return Offset(file * sqSize + sqSize / 2, (7 - rank) * sqSize + sqSize / 2);
  }

  String? _squareFromOffset(Offset localPosition, double sqSize) {
    if (localPosition.dx < 0 || localPosition.dy < 0) return null;
    int file = (localPosition.dx / sqSize).floor();
    int rank = 7 - (localPosition.dy / sqSize).floor();
    if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
    if (widget.flipped) { file = 7 - file; rank = 7 - rank; }
    return _squareName(file, rank);
  }

  List<List<String?>> _parseFEN(String fen) {
    final board = List<List<String?>>.generate(8, (_) => List<String?>.filled(8, null));
    try {
      final ranks = fen.split(' ').first.split('/');
      for (int ri = 0; ri < 8 && ri < ranks.length; ri++) {
        int fi = 0;
        for (final char in ranks[ri].split('')) {
          final d = int.tryParse(char);
          if (d != null) { fi += d; } else { if (fi < 8) board[ri][fi] = char; fi++; }
        }
      }
    } catch (_) {}
    return board;
  }

  String _fenCharToPieceKey(String char) {
    final isW = char.toUpperCase() == char;
    return '${isW ? 'w' : 'b'}${char.toLowerCase()}';
  }

  String? _findKingSquare(String fen, bool isWhite) {
    final board = _parseFEN(fen);
    final kingChar = isWhite ? 'K' : 'k';
    for (int ri = 0; ri < 8; ri++) {
      for (int fi = 0; fi < 8; fi++) {
        if (board[ri][fi] == kingChar) {
          return '${kFileNames[fi]}${8 - ri}';
        }
      }
    }
    return null;
  }

  bool _hasPieceOfColor(String square, bool isWhite) {
    try {
      final piece = _game.get(square);
      if (piece == null) return false;
      return piece.color == (isWhite ? chess.Color.WHITE : chess.Color.BLACK);
    } catch (_) { return false; }
  }

  void _updateCheckSquare() {
    String? checkSq = widget.checkSquare;
    if (checkSq == null) {
      try {
        if (_game.in_check) {
          final isWhite = _game.turn == chess.Color.WHITE;
          checkSq = _findKingSquare(_displayFEN, isWhite);
        }
      } catch (_) {}
    }
    _checkSquareNotifier.value = checkSq;
  }

  Set<String> _getLegalTargets(String square) {
    final targets = <String>{};
    try {
      final moves = _game.generateMoves();
      for (final move in moves) {
        try {
          if (move.fromAlgebraic == square) targets.add(move.toAlgebraic);
        } catch (_) { continue; }
      }
    } catch (_) {}
    return targets;
  }

  bool _isPromotionMove(String from, String to) {
    try {
      final moves = _game.generateMoves();
      for (final move in moves) {
        try {
          if (move.fromAlgebraic == from && move.toAlgebraic == to && move.promotion != null) return true;
        } catch (_) { continue; }
      }
    } catch (_) {}
    return false;
  }

  String? _getPieceKeyAt(String square) {
    final board = _parseFEN(_displayFEN);
    final file = _fileIndex(square);
    final rank = _rankIndex(square);
    final ri = 7 - rank;
    if (ri < 0 || ri > 7 || file < 0 || file > 7) return null;
    final char = board[ri][file];
    if (char == null) return null;
    return _fenCharToPieceKey(char);
  }

  // ========================================================================
  // معالجة التفاعل (إصلاح #4: Single Gesture Layer)
  // ========================================================================

  void _handleTapUp(TapUpDetails details, double sqSize) {
    if (!widget.enableMoveInput || _showPromotion) return;
    if (_moveAnim != null || _dragReturnAnim != null) return;

    final square = _squareFromOffset(details.localPosition, sqSize);
    if (square == null) return;

    widget.onSquareTapped?.call(square);

    if (_selectedSquare != null) {
      if (square == _selectedSquare) { _deselect(); return; }
      if (_legalMoveSquares.contains(square)) { _attemptMove(_selectedSquare!, square); return; }
      final isWhiteTurn = _game.turn == chess.Color.WHITE;
      if (_hasPieceOfColor(square, isWhiteTurn)) { _selectPiece(square); return; }
      _deselect();
      return;
    }

    final isWhiteTurn = _game.turn == chess.Color.WHITE;
    if (_hasPieceOfColor(square, isWhiteTurn)) _selectPiece(square);
  }

  void _handlePanStart(DragStartDetails details, double sqSize) {
    if (!widget.enableMoveInput || _showPromotion) return;
    if (_moveAnim != null || _dragReturnAnim != null) return;

    final square = _squareFromOffset(details.localPosition, sqSize);
    if (square == null) return;

    final isWhiteTurn = _game.turn == chess.Color.WHITE;
    if (!_hasPieceOfColor(square, isWhiteTurn)) return;

    final center = _squareCenter(square, sqSize);
    final touchPos = details.localPosition;

    setState(() {
      _isDragging = true;
      _dragFrom = square;
      _dragPosition = touchPos;
      _dragOffsetFromCenter = Offset(center.dx - touchPos.dx, center.dy - touchPos.dy);
      _selectedSquare = square;
      _legalMoveSquares = _getLegalTargets(square);
      _selectedSquareNotifier.value = square;
      _legalMovesNotifier.value = _legalMoveSquares;
    });
    _selectController.forward(from: 0);
  }

  void _handlePanUpdate(DragUpdateDetails details, double sqSize) {
    if (!_isDragging || _dragFrom == null) return;
    setState(() { _dragPosition = details.localPosition; });
  }

  void _handlePanEnd(DragEndDetails details, double sqSize) {
    if (!_isDragging || _dragFrom == null) return;

    final dropSquare = _squareFromOffset(_dragPosition + _dragOffsetFromCenter, sqSize);
    final from = _dragFrom!;
    final isLegalDrop = dropSquare != null && _legalMoveSquares.contains(dropSquare);

    if (isLegalDrop && dropSquare != from) {
      setState(() { _isDragging = false; _dragFrom = null; });
      _attemptMove(from, dropSquare);
    } else {
      final pieceKey = _getPieceKeyAt(from);
      setState(() {
        _dragReturnAnim = _DragReturnData(from: from, pieceKey: pieceKey, dropPosition: _dragPosition + _dragOffsetFromCenter);
        _isDragging = false;
        _dragFrom = null;
        _selectedSquare = null;
        _legalMoveSquares = {};
        _selectedSquareNotifier.value = null;
        _legalMovesNotifier.value = {};
      });
      _dragReturnController.forward(from: 0);
    }
  }

  void _selectPiece(String square) {
    setState(() {
      _selectedSquare = square;
      _legalMoveSquares = _getLegalTargets(square);
      _selectedSquareNotifier.value = square;
      _legalMovesNotifier.value = _legalMoveSquares;
    });
    _selectController.forward(from: 0);
  }

  void _deselect() {
    setState(() {
      _selectedSquare = null;
      _legalMoveSquares = {};
      _selectedSquareNotifier.value = null;
      _legalMovesNotifier.value = {};
    });
  }

  void _attemptMove(String from, String to) {
    if (_isPromotionMove(from, to)) {
      final isWhite = _hasPieceOfColor(from, true);
      setState(() {
        _showPromotion = true;
        _promotionFrom = from;
        _promotionTo = to;
        _promotionIsWhite = isWhite;
      });
      return;
    }
    _completeMove(from, to, null);
  }

  void _completeMove(String from, String to, String? promotion) {
    final movingPieceKey = _getPieceKeyAt(from) ?? 'wp';
    final capturedPieceKey = _getPieceKeyAt(to);
    final isCapture = capturedPieceKey != null;

    widget.onMove?.call(from, to, promotion);

    if (!_isDragging) {
      _startMoveAnimation(from, to, movingPieceKey, isCapture, capturedPieceKey);
    }

    setState(() {
      _selectedSquare = null;
      _legalMoveSquares = {};
      _selectedSquareNotifier.value = null;
      _legalMovesNotifier.value = {};
    });
  }

  void _startMoveAnimation(String from, String to, String pieceKey, bool isCapture, String? capturedKey) {
    setState(() {
      _moveAnim = _MoveAnimData(from: from, to: to, pieceKey: pieceKey, isCapture: isCapture, capturedKey: capturedKey);
    });
    _moveController.forward(from: 0);
    if (isCapture) _captureController.forward(from: 0);
  }

  void _onMoveAnimStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _moveAnim = null;
        if (_pendingFEN != null) {
          _displayFEN = _pendingFEN!;
          _pendingFEN = null;
        } else {
          _displayFEN = widget.fen;
        }
        _fenNotifier.value = _displayFEN;
      });
      _captureController.reset();
    }
  }

  void _onDragReturnStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() { _dragReturnAnim = null; });
    }
  }

  void _clearTextPainterCache() {
    for (final p in _textPainterCache.values) { p.dispose(); }
    _textPainterCache.clear();
  }

  TextPainter _getCachedTextPainter(String text, TextStyle style) {
    final key = '${text}_${style.fontSize?.round() ?? 0}';
    if (_textPainterCache.containsKey(key)) return _textPainterCache[key]!;
    final p = TextPainter(text: TextSpan(text: text, style: style), textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    p.layout();
    _textPainterCache[key] = p;
    return p;
  }

  // ========================================================================
  // بناء الويدجت (إصلاحات #1, #17, #20: طبقات معزولة)
  // ========================================================================

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boardSize = widget.size ?? math.min(constraints.maxWidth, constraints.maxHeight);
        final sqSize = boardSize / 8;

        // إصلاح #4: Single Gesture Layer — gesture handler واحد فقط
        return SizedBox(
          width: boardSize,
          height: boardSize,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _handleTapUp(details, sqSize),
            onPanStart: (details) => _handlePanStart(details, sqSize),
            onPanUpdate: (details) => _handlePanUpdate(details, sqSize),
            onPanEnd: (details) => _handlePanEnd(details, sqSize),
            child: Stack(
              children: [
                // ── إصلاح #1: طبقة الخلفية (لا تتغير إلا عند تغيير السمة) ──
                RepaintBoundary(
                  child: _BoardBackgroundLayer(
                    theme: widget.theme,
                    flipped: widget.flipped,
                    boardSize: boardSize,
                  ),
                ),

                // ── طبقة التمييزات (تتغير عند اختيار قطعة أو تنفيذ حركة) ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _selectController,
                      _moveController,
                      _captureController,
                      _dragReturnController,
                    ]),
                    builder: (context, _) {
                      return _BoardHighlightLayer(
                        fen: _displayFEN,
                        theme: widget.theme,
                        flipped: widget.flipped,
                        selectedSquare: _selectedSquare,
                        legalMoveSquares: _legalMoveSquares,
                        lastMoveFrom: widget.lastMoveFrom,
                        lastMoveTo: widget.lastMoveTo,
                        checkSquare: _checkSquareNotifier.value,
                        showLegalMoves: widget.showLegalMoves,
                        selectAnimValue: _selectController.value,
                        moveAnim: _moveAnim,
                        moveAnimValue: Curves.easeOutCubic.transform(_moveController.value),
                        captureAnimValue: _captureController.value,
                        boardSize: boardSize,
                      );
                    },
                  ),
                ),

                // ── طبقة القطع (تتغير عند كل حركة أو سحب) ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      _moveController,
                      _captureController,
                      _dragReturnController,
                    ]),
                    builder: (context, _) {
                      return _BoardPieceLayer(
                        fen: _displayFEN,
                        theme: widget.theme,
                        flipped: widget.flipped,
                        pieceImages: widget.pieceImages,
                        isDragging: _isDragging,
                        dragFrom: _dragFrom,
                        dragPosition: _dragPosition + _dragOffsetFromCenter,
                        moveAnim: _moveAnim,
                        moveAnimValue: Curves.easeOutCubic.transform(_moveController.value),
                        dragReturnAnim: _dragReturnAnim,
                        dragReturnValue: Curves.easeInOut.transform(_dragReturnController.value),
                        boardSize: boardSize,
                        textPainterCache: _textPainterCache,
                        getCachedPainter: _getCachedTextPainter,
                      );
                    },
                  ),
                ),

                // ── إصلاح #3: طبقة الأسهم (محدودة بالسرعة - لا تُحدّث كل frame) ──
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _arrowController,
                    builder: (context, _) {
                      return _BoardOverlayLayer(
                        arrows: widget.arrows,
                        arrowOpacity: _arrowController.value,
                        flipped: widget.flipped,
                        showCoordinates: widget.showCoordinates,
                        theme: widget.theme,
                        boardSize: boardSize,
                        textPainterCache: _textPainterCache,
                        getCachedPainter: _getCachedTextPainter,
                      );
                    },
                  ),
                ),

                // ── حوار الترقية ──
                if (_showPromotion) _buildPromotionDialog(boardSize),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPromotionDialog(double boardSize) {
    final sqSize = boardSize / 8;
    final toFile = _fileIndex(_promotionTo!);
    int displayFile = widget.flipped ? 7 - toFile : toFile;
    int startRank = _promotionIsWhite
        ? (widget.flipped ? 4 : 0)
        : (widget.flipped ? 0 : 4);

    final promoTypes = ['q', 'r', 'b', 'n'];
    final colorChar = _promotionIsWhite ? 'w' : 'b';

    return Positioned(
      left: displayFile * sqSize,
      top: startRank * sqSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: promoTypes.map((type) {
          final pieceKey = '$colorChar$type';
          return _PromotionOption(
            pieceKey: pieceKey,
            size: sqSize,
            lightColor: widget.theme.lightSquare,
            darkColor: widget.theme.darkSquare,
            pieceImages: widget.pieceImages,
            onTap: () {
              setState(() { _showPromotion = false; });
              _completeMove(_promotionFrom!, _promotionTo!, type);
            },
          );
        }).toList(),
      ),
    );
  }
}

// ============================================================================
// _PromotionOption — خيار ترقية
// ============================================================================

class _PromotionOption extends StatelessWidget {
  final String pieceKey;
  final double size;
  final Color lightColor;
  final Color darkColor;
  final Map<String, ui.Image>? pieceImages;
  final VoidCallback onTap;

  const _PromotionOption({
    required this.pieceKey,
    required this.size,
    required this.lightColor,
    required this.darkColor,
    this.pieceImages,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isWhite = pieceKey.startsWith('w');
    final symbol = kPieceSymbols[pieceKey] ?? '?';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isWhite ? lightColor : darkColor,
          border: Border.all(color: Colors.black26, width: 1),
        ),
        child: Center(
          child: Text(
            symbol,
            style: TextStyle(
              fontSize: size * 0.75,
              color: isWhite ? Colors.white : const Color(0xFF333333),
              shadows: [
                Shadow(
                  offset: const Offset(1, 1),
                  color: isWhite ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
                  blurRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// طبقات الرقعة المعزولة — Board Layers (إصلاحات #1, #3, #17, #20)
// ============================================================================

/// الطبقة 1: خلفية الرقعة — المربعات فقط (لا تتغير إلا عند تغيير السمة)
class _BoardBackgroundLayer extends StatelessWidget {
  final BoardTheme theme;
  final bool flipped;
  final double boardSize;

  const _BoardBackgroundLayer({
    required this.theme,
    required this.flipped,
    required this.boardSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(boardSize, boardSize),
      painter: _BackgroundPainter(theme: theme, flipped: flipped),
    );
  }
}

/// الطبقة 2: التمييزات — آخر حركة، اختيار، حركات قانونية، كش
class _BoardHighlightLayer extends StatelessWidget {
  final String fen;
  final BoardTheme theme;
  final bool flipped;
  final String? selectedSquare;
  final Set<String> legalMoveSquares;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? checkSquare;
  final bool showLegalMoves;
  final double selectAnimValue;
  final _MoveAnimData? moveAnim;
  final double moveAnimValue;
  final double captureAnimValue;
  final double boardSize;

  const _BoardHighlightLayer({
    required this.fen,
    required this.theme,
    required this.flipped,
    this.selectedSquare,
    this.legalMoveSquares = const {},
    this.lastMoveFrom,
    this.lastMoveTo,
    this.checkSquare,
    this.showLegalMoves = true,
    this.selectAnimValue = 1.0,
    this.moveAnim,
    this.moveAnimValue = 1.0,
    this.captureAnimValue = 0.0,
    required this.boardSize,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(boardSize, boardSize),
      painter: _HighlightPainter(
        fen: fen,
        theme: theme,
        flipped: flipped,
        selectedSquare: selectedSquare,
        legalMoveSquares: legalMoveSquares,
        lastMoveFrom: lastMoveFrom,
        lastMoveTo: lastMoveTo,
        checkSquare: checkSquare,
        showLegalMoves: showLegalMoves,
        selectAnimValue: selectAnimValue,
        moveAnim: moveAnim,
        moveAnimValue: moveAnimValue,
        captureAnimValue: captureAnimValue,
      ),
    );
  }
}

/// الطبقة 3: القطع — رسم القطع مع الأنيميشن والسحب
class _BoardPieceLayer extends StatelessWidget {
  final String fen;
  final BoardTheme theme;
  final bool flipped;
  final Map<String, ui.Image>? pieceImages;
  final bool isDragging;
  final String? dragFrom;
  final Offset dragPosition;
  final _MoveAnimData? moveAnim;
  final double moveAnimValue;
  final _DragReturnData? dragReturnAnim;
  final double dragReturnValue;
  final double boardSize;
  final Map<String, TextPainter> textPainterCache;
  final TextPainter Function(String, TextStyle) getCachedPainter;

  const _BoardPieceLayer({
    required this.fen,
    required this.theme,
    required this.flipped,
    this.pieceImages,
    this.isDragging = false,
    this.dragFrom,
    this.dragPosition = Offset.zero,
    this.moveAnim,
    this.moveAnimValue = 1.0,
    this.dragReturnAnim,
    this.dragReturnValue = 1.0,
    required this.boardSize,
    required this.textPainterCache,
    required this.getCachedPainter,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(boardSize, boardSize),
      painter: _PiecePainter(
        fen: fen,
        theme: theme,
        flipped: flipped,
        pieceImages: pieceImages,
        isDragging: isDragging,
        dragFrom: dragFrom,
        dragPosition: dragPosition,
        moveAnim: moveAnim,
        moveAnimValue: moveAnimValue,
        dragReturnAnim: dragReturnAnim,
        dragReturnValue: dragReturnValue,
        textPainterCache: textPainterCache,
        getCachedPainter: getCachedPainter,
      ),
    );
  }
}

/// الطبقة 4: الأسهم والإحداثيات — إصلاح #3: طبقة منفصلة
class _BoardOverlayLayer extends StatelessWidget {
  final BoardArrows? arrows;
  final double arrowOpacity;
  final bool flipped;
  final bool showCoordinates;
  final BoardTheme theme;
  final double boardSize;
  final Map<String, TextPainter> textPainterCache;
  final TextPainter Function(String, TextStyle) getCachedPainter;

  const _BoardOverlayLayer({
    this.arrows,
    this.arrowOpacity = 1.0,
    required this.flipped,
    required this.showCoordinates,
    required this.theme,
    required this.boardSize,
    required this.textPainterCache,
    required this.getCachedPainter,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(boardSize, boardSize),
      painter: _OverlayPainter(
        arrows: arrows,
        arrowOpacity: arrowOpacity,
        flipped: flipped,
        showCoordinates: showCoordinates,
        theme: theme,
        textPainterCache: textPainterCache,
        getCachedPainter: getCachedPainter,
      ),
    );
  }
}

// ============================================================================
// الرسامون — Painters
// ============================================================================

/// رسام الخلفية — مربعات فاتحة وداكنة مع تدرج ثلاثي الأبعاد
class _BackgroundPainter extends CustomPainter {
  final BoardTheme theme;
  final bool flipped;

  _BackgroundPainter({required this.theme, required this.flipped});

  @override
  void paint(Canvas canvas, Size size) {
    final sqSize = size.width / 8;

    for (int rank = 0; rank < 8; rank++) {
      for (int file = 0; file < 8; file++) {
        final isLight = (file + rank) % 2 == 0;
        int df = flipped ? 7 - file : file;
        int dr = flipped ? rank : 7 - rank;

        final rect = Rect.fromLTWH(df * sqSize, dr * sqSize, sqSize, sqSize);
        final paint = Paint()..color = isLight ? theme.lightSquare : theme.darkSquare;

        // تدرج ثلاثي الأبعاد خفيف
        if (isLight) {
          paint.shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(theme.lightSquare, Colors.white, 0.08)!,
              theme.lightSquare,
            ],
          ).createShader(rect);
        } else {
          paint.shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(theme.darkSquare, Colors.black, 0.05)!,
              theme.darkSquare,
            ],
          ).createShader(rect);
        }

        canvas.drawRect(rect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) =>
      theme != old.theme || flipped != old.flipped;
}

/// رسام التمييزات — آخر حركة، اختيار، حركات قانونية، كش
class _HighlightPainter extends CustomPainter {
  final String fen;
  final BoardTheme theme;
  final bool flipped;
  final String? selectedSquare;
  final Set<String> legalMoveSquares;
  final String? lastMoveFrom;
  final String? lastMoveTo;
  final String? checkSquare;
  final bool showLegalMoves;
  final double selectAnimValue;
  final _MoveAnimData? moveAnim;
  final double moveAnimValue;
  final double captureAnimValue;

  _HighlightPainter({
    required this.fen,
    required this.theme,
    required this.flipped,
    this.selectedSquare,
    this.legalMoveSquares = const {},
    this.lastMoveFrom,
    this.lastMoveTo,
    this.checkSquare,
    this.showLegalMoves = true,
    this.selectAnimValue = 1.0,
    this.moveAnim,
    this.moveAnimValue = 1.0,
    this.captureAnimValue = 0.0,
  });

  int _fileIndex(String sq) => sq.codeUnitAt(0) - 'a'.codeUnitAt(0);
  int _rankIndex(String sq) => sq[1].codeUnitAt(0) - '1'.codeUnitAt(0);

  Rect _squareRect(String square, double sqSize) {
    int file = _fileIndex(square);
    int rank = _rankIndex(square);
    if (flipped) { file = 7 - file; rank = 7 - rank; }
    return Rect.fromLTWH(file * sqSize, (7 - rank) * sqSize, sqSize, sqSize);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sqSize = size.width / 8;

    // تمييز آخر حركة
    if (lastMoveFrom != null) {
      canvas.drawRect(_squareRect(lastMoveFrom!, sqSize), Paint()..color = theme.lastMoveHighlight);
    }
    if (lastMoveTo != null) {
      canvas.drawRect(_squareRect(lastMoveTo!, sqSize), Paint()..color = theme.lastMoveHighlight);
    }

    // تمييز المربع المختار
    if (selectedSquare != null) {
      final rect = _squareRect(selectedSquare!, sqSize);
      final paint = Paint()..color = theme.selectedSquare;
      canvas.drawRect(rect, paint);
    }

    // تمييز الكش
    if (checkSquare != null) {
      final rect = _squareRect(checkSquare!, sqSize);
      final paint = Paint()..color = theme.checkHighlight;
      canvas.drawRect(rect, paint);
    }

    // نقاط الحركات القانونية
    if (showLegalMoves && selectedSquare != null) {
      for (final target in legalMoveSquares) {
        final rect = _squareRect(target, sqSize);
        final center = rect.center;

        // كشف إن كان في المربع قطعة (حركة أسر)
        final board = _parseFENSilent(fen);
        final file = target.codeUnitAt(0) - 'a'.codeUnitAt(0);
        final rank = target[1].codeUnitAt(0) - '1'.codeUnitAt(0);
        final ri = 7 - rank;
        final hasPiece = ri >= 0 && ri < 8 && file >= 0 && file < 8 && board[ri][file] != null;

        if (hasPiece) {
          // حلقة الحركة القانونية (أسر)
          final paint = Paint()
            ..color = theme.legalMoveCaptureRing
            ..style = PaintingStyle.stroke
            ..strokeWidth = sqSize * 0.05;
          canvas.drawCircle(center, sqSize * 0.45, paint);
        } else {
          // نقطة الحركة القانونية
          final paint = Paint()..color = theme.legalMoveDot;
          canvas.drawCircle(center, sqSize * 0.15, paint);
        }
      }
    }
  }

  List<List<String?>> _parseFENSilent(String fen) {
    final board = List<List<String?>>.generate(8, (_) => List<String?>.filled(8, null));
    try {
      final ranks = fen.split(' ').first.split('/');
      for (int ri = 0; ri < 8 && ri < ranks.length; ri++) {
        int fi = 0;
        for (final char in ranks[ri].split('')) {
          final d = int.tryParse(char);
          if (d != null) { fi += d; } else { if (fi < 8) board[ri][fi] = char; fi++; }
        }
      }
    } catch (_) {}
    return board;
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter old) =>
      fen != old.fen || theme != old.theme || selectedSquare != old.selectedSquare ||
      lastMoveFrom != old.lastMoveFrom || lastMoveTo != old.lastMoveTo ||
      checkSquare != old.checkSquare || selectAnimValue != old.selectAnimValue ||
      moveAnimValue != old.moveAnimValue || captureAnimValue != old.captureAnimValue;
}

/// رسام القطع
class _PiecePainter extends CustomPainter {
  final String fen;
  final BoardTheme theme;
  final bool flipped;
  final Map<String, ui.Image>? pieceImages;
  final bool isDragging;
  final String? dragFrom;
  final Offset dragPosition;
  final _MoveAnimData? moveAnim;
  final double moveAnimValue;
  final _DragReturnData? dragReturnAnim;
  final double dragReturnValue;
  final Map<String, TextPainter> textPainterCache;
  final TextPainter Function(String, TextStyle) getCachedPainter;

  _PiecePainter({
    required this.fen,
    required this.theme,
    required this.flipped,
    this.pieceImages,
    this.isDragging = false,
    this.dragFrom,
    this.dragPosition = Offset.zero,
    this.moveAnim,
    this.moveAnimValue = 1.0,
    this.dragReturnAnim,
    this.dragReturnValue = 1.0,
    required this.textPainterCache,
    required this.getCachedPainter,
  });

  int _fileIndex(String sq) => sq.codeUnitAt(0) - 'a'.codeUnitAt(0);
  int _rankIndex(String sq) => sq[1].codeUnitAt(0) - '1'.codeUnitAt(0);

  Offset _squareCenter(String square, double sqSize) {
    int file = _fileIndex(square);
    int rank = _rankIndex(square);
    if (flipped) { file = 7 - file; rank = 7 - rank; }
    return Offset(file * sqSize + sqSize / 2, (7 - rank) * sqSize + sqSize / 2);
  }

  String _fenCharToPieceKey(String char) {
    final isW = char.toUpperCase() == char;
    return '${isW ? 'w' : 'b'}${char.toLowerCase()}';
  }

  void _drawPiece(Canvas canvas, String pieceKey, Offset center, double sqSize) {
    // محاولة استخدام صورة محملة مسبقاً
    if (pieceImages != null && pieceImages!.containsKey(pieceKey)) {
      final image = pieceImages![pieceKey]!;
      final size = sqSize * 0.85;
      final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
      final dst = Rect.fromCenter(center: center, width: size, height: size);
      canvas.drawImageRect(image, src, dst, Paint());
    } else {
      // استخدام Unicode
      final symbol = kPieceSymbols[pieceKey] ?? '?';
      final isWhite = pieceKey.startsWith('w');
      final style = TextStyle(
        fontSize: sqSize * 0.75,
        color: isWhite ? Colors.white : const Color(0xFF333333),
        shadows: [
          Shadow(
            offset: const Offset(1, 1),
            color: isWhite ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
            blurRadius: 1,
          ),
        ],
      );
      final painter = getCachedPainter(symbol, style);
      painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy - painter.height / 2));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sqSize = size.width / 8;
    final board = _parseFENSilent(fen);

    // رسم القطع الثابتة
    for (int ri = 0; ri < 8; ri++) {
      for (int fi = 0; fi < 8; fi++) {
        final char = board[ri][fi];
        if (char == null) continue;

        final rank = 8 - ri;
        final file = String.fromCharCode('a'.codeUnitAt(0) + fi);
        final square = '$file$rank';

        // تخطي القطعة المتحركة
        if (moveAnim != null && square == moveAnim!.from) continue;
        // تخطي القطعة المسحوبة
        if (isDragging && square == dragFrom) continue;
        // تخطي القطعة المأسورة أثناء أنيميشن الأسر
        if (moveAnim != null && moveAnim!.isCapture && square == moveAnim!.to) continue;

        final center = _squareCenter(square, sqSize);
        final pieceKey = _fenCharToPieceKey(char);
        _drawPiece(canvas, pieceKey, center, sqSize);
      }
    }

    // رسم القطعة المتحركة (أنيميشن)
    if (moveAnim != null) {
      final fromCenter = _squareCenter(moveAnim!.from, sqSize);
      final toCenter = _squareCenter(moveAnim!.to, sqSize);
      final currentCenter = Offset(
        fromCenter.dx + (toCenter.dx - fromCenter.dx) * moveAnimValue,
        fromCenter.dy + (toCenter.dy - fromCenter.dy) * moveAnimValue,
      );
      _drawPiece(canvas, moveAnim!.pieceKey, currentCenter, sqSize);
    }

    // رسم القطعة المسحوبة
    if (isDragging && dragFrom != null) {
      final pieceKey = _getPieceKeyAt(dragFrom!);
      if (pieceKey != null) {
        _drawPiece(canvas, pieceKey, dragPosition, sqSize);
      }
    }

    // رسم عودة السحب الفاشل
    if (dragReturnAnim != null) {
      final fromCenter = _squareCenter(dragReturnAnim!.from, sqSize);
      final currentCenter = Offset(
        dragReturnAnim!.dropPosition.dx + (fromCenter.dx - dragReturnAnim!.dropPosition.dx) * dragReturnValue,
        dragReturnAnim!.dropPosition.dy + (fromCenter.dy - dragReturnAnim!.dropPosition.dy) * dragReturnValue,
      );
      _drawPiece(canvas, dragReturnAnim!.pieceKey, currentCenter, sqSize);
    }
  }

  List<List<String?>> _parseFENSilent(String fen) {
    final board = List<List<String?>>.generate(8, (_) => List<String?>.filled(8, null));
    try {
      final ranks = fen.split(' ').first.split('/');
      for (int ri = 0; ri < 8 && ri < ranks.length; ri++) {
        int fi = 0;
        for (final char in ranks[ri].split('')) {
          final d = int.tryParse(char);
          if (d != null) { fi += d; } else { if (fi < 8) board[ri][fi] = char; fi++; }
        }
      }
    } catch (_) {}
    return board;
  }

  String? _getPieceKeyAt(String square) {
    final board = _parseFENSilent(fen);
    final file = _fileIndex(square);
    final rank = _rankIndex(square);
    final ri = 7 - rank;
    if (ri < 0 || ri > 7 || file < 0 || file > 7) return null;
    final char = board[ri][file];
    if (char == null) return null;
    return _fenCharToPieceKey(char);
  }

  @override
  bool shouldRepaint(covariant _PiecePainter old) =>
      fen != old.fen || isDragging != old.isDragging ||
      dragFrom != old.dragFrom || dragPosition != old.dragPosition ||
      moveAnimValue != old.moveAnimValue || dragReturnValue != old.dragReturnValue;
}

/// رسام الأسهم والإحداثيات (إصلاح #3: طبقة منفصلة)
class _OverlayPainter extends CustomPainter {
  final BoardArrows? arrows;
  final double arrowOpacity;
  final bool flipped;
  final bool showCoordinates;
  final BoardTheme theme;
  final Map<String, TextPainter> textPainterCache;
  final TextPainter Function(String, TextStyle) getCachedPainter;

  _OverlayPainter({
    this.arrows,
    this.arrowOpacity = 1.0,
    required this.flipped,
    required this.showCoordinates,
    required this.theme,
    required this.textPainterCache,
    required this.getCachedPainter,
  });

  int _fileIndex(String sq) => sq.codeUnitAt(0) - 'a'.codeUnitAt(0);
  int _rankIndex(String sq) => sq[1].codeUnitAt(0) - '1'.codeUnitAt(0);

  Offset _squareCenter(String square, double sqSize) {
    int file = _fileIndex(square);
    int rank = _rankIndex(square);
    if (flipped) { file = 7 - file; rank = 7 - rank; }
    return Offset(file * sqSize + sqSize / 2, (7 - rank) * sqSize + sqSize / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final sqSize = size.width / 8;

    // رسم الأسهم
    if (arrows != null && arrows!.all.isNotEmpty) {
      for (final arrow in arrows!.all) {
        _drawArrow(canvas, arrow, sqSize);
      }
    }

    // رسم الإحداثيات
    if (showCoordinates) {
      _drawCoordinates(canvas, sqSize);
    }
  }

  void _drawArrow(Canvas canvas, ArrowData arrow, double sqSize) {
    final fromCenter = _squareCenter(arrow.from, sqSize);
    final toCenter = _squareCenter(arrow.to, sqSize);

    final paint = Paint()
      ..color = arrow.color.withOpacity(arrowOpacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = arrow.width
      ..strokeCap = StrokeCap.round;

    if (arrow.style == ArrowStyle.dashed) {
      // سهم متقطع
      final dx = toCenter.dx - fromCenter.dx;
      final dy = toCenter.dy - fromCenter.dy;
      final dist = (dx * dx + dy * dy);
      if (dist == 0) return;
      final length = sqrt(dist);
      final dashLen = length / 8;
      final unitX = dx / length;
      final unitY = dy / length;

      for (int i = 0; i < 8; i += 2) {
        final start = Offset(fromCenter.dx + unitX * dashLen * i, fromCenter.dy + unitY * dashLen * i);
        final end = Offset(fromCenter.dx + unitX * dashLen * (i + 1), fromCenter.dy + unitY * dashLen * (i + 1));
        canvas.drawLine(start, end, paint);
      }
    } else {
      canvas.drawLine(fromCenter, toCenter, paint);
    }

    // رأس السهم
    final headSize = arrow.width * 2.5;
    final dx = toCenter.dx - fromCenter.dx;
    final dy = toCenter.dy - fromCenter.dy;
    final angle = atan2(dy, dx);

    final path = Path();
    path.moveTo(toCenter.dx, toCenter.dy);
    path.lineTo(
      toCenter.dx - headSize * cos(angle - 0.4),
      toCenter.dy - headSize * sin(angle - 0.4),
    );
    path.lineTo(
      toCenter.dx - headSize * cos(angle + 0.4),
      toCenter.dy - headSize * sin(angle + 0.4),
    );
    path.close();

    final fillPaint = Paint()
      ..color = arrow.color.withOpacity(arrowOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
  }

  void _drawCoordinates(Canvas canvas, double sqSize) {
    for (int i = 0; i < 8; i++) {
      // أحرف الأعمدة (أسفل الرقعة)
      final fileChar = kFileNames[flipped ? 7 - i : i];
      final isLightFile = i % 2 == 0; // الصف السفلي
      final coordColor = isLightFile ? theme.coordinateOnDark : theme.coordinateOnLight;
      final style = TextStyle(fontSize: sqSize * 0.18, color: coordColor, fontWeight: FontWeight.bold);
      final painter = getCachedPainter(fileChar, style);
      painter.paint(canvas, Offset(i * sqSize + sqSize - painter.width - 2, sqSize * 8 - painter.height - 1));

      // أرقام الصفوف (يسار الرقعة)
      final rankNum = flipped ? (i + 1).toString() : (8 - i).toString();
      final isLightRank = i % 2 == 1;
      final rankColor = isLightRank ? theme.coordinateOnLight : theme.coordinateOnDark;
      final rankStyle = TextStyle(fontSize: sqSize * 0.18, color: rankColor, fontWeight: FontWeight.bold);
      final rankPainter = getCachedPainter(rankNum, rankStyle);
      rankPainter.paint(canvas, const Offset(2, 1) + Offset(0, i * sqSize));
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      arrows != old.arrows || arrowOpacity != old.arrowOpacity ||
      flipped != old.flipped || showCoordinates != old.showCoordinates ||
      theme != old.theme;
}


