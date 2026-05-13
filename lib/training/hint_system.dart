/// hint_system.dart
/// نظام التلميحات ذو 4 مستويات — 4-Level Hint System
///
/// المستويات:
/// 1. المنطقة: أي منطقة من الرقعة
/// 2. القطعة: أي قطعة يجب تحريكها
/// 3. الاتجاه: الاتجاه أو المنطقة المستهدفة
/// 4. الحركة الكاملة: الحركة المضبوطة
library;

import 'package:chess/chess.dart' as chess;
import '../engine/stockfish_engine.dart';
import '../models/chess_models.dart';

/// مستوى التلميح
enum HintLevel {
  /// المنطقة فقط
  zone,

  /// القطعة المطلوبة
  piece,

  /// اتجاه الحركة
  direction,

  /// الحركة الكاملة
  fullMove;

  /// التسمية العربية
  String get arabicLabel => switch (this) {
        HintLevel.zone => 'المنطقة',
        HintLevel.piece => 'القطعة',
        HintLevel.direction => 'الاتجاه',
        HintLevel.fullMove => 'الحركة الكاملة',
      };

  /// الوصف العربي
  String get arabicDescription => switch (this) {
        HintLevel.zone =>
          'يظهر المنطقة العامة على الرقعة حيث توجد الحركة',
        HintLevel.piece =>
          'يحدد القطعة التي يجب تحريكها',
        HintLevel.direction =>
          'يوضح الاتجاه أو المنطقة المستهدفة',
        HintLevel.fullMove =>
          'يظهر الحركة المضبوطة بالكامل',
      };

  /// الرمز
  String get icon => switch (this) {
        HintLevel.zone => '🔲',
        HintLevel.piece => '♟',
        HintLevel.direction => '➡️',
        HintLevel.fullMove => '✅',
      };
}

/// تلميح واحد
class Hint {
  /// مستوى التلميح
  final HintLevel level;

  /// النص العربي
  final String textAr;

  /// وصف إضافي
  final String? descriptionAr;

  /// المربعات المميزة (للعرض على الرقعة)
  final List<String> highlightedSquares;

  /// مناطق التمييز (أرباع الرقعة)
  final List<BoardZone> zones;

  const Hint({
    required this.level,
    required this.textAr,
    this.descriptionAr,
    this.highlightedSquares = const [],
    this.zones = const [],
  });
}

/// منطقة على الرقعة
enum BoardZone {
  queenside('جانب الوزير', 'a1-a4-h4-h1'),
  kingside('جانب الملك', 'e1-h1-h8-e8'),
  center('المركز', 'c3-f3-f6-c6'),
  queensideTop('جانب الوزير العلوي', 'a5-a8-d8-d5'),
  kingsideTop('جانب الملك العلوي', 'e5-e8-h8-h5'),
  queensideBottom('جانب الوزير السفلي', 'a1-a4-d4-d1'),
  kingsideBottom('جانب الملك السفلي', 'e1-e4-h4-h1');

  final String arabicName;
  final String description;

  const BoardZone(this.arabicName, this.description);
}

/// نظام التلميحات
class HintSystem {
  static const _tag = 'HintSystem';

  /// محرك Stockfish
  StockfishEngine? _engine;

  /// المستوى الحالي للتلميح
  HintLevel _currentLevel = HintLevel.zone;

  /// عدد التلميحات المستخدمة
  int _hintsUsed = 0;

  /// أفضل حركة من المحرك
  String? _bestMoveUci;

  /// الحالة الحالية للمستوى
  HintLevel get currentLevel => _currentLevel;
  int get hintsUsed => _hintsUsed;

  /// تهيئة النظام مع المحرك
  void setEngine(StockfishEngine engine) {
    _engine = engine;
  }

  /// تحليل الموقف الحالي والحصول على أفضل حركة
  Future<String?> _analyzePosition(String fen) async {
    if (_engine == null || !_engine!.isReady) return null;

    try {
      _engine!.setPositionFromFen(fen);
      final bestMove = await _engine!.analyzeDepth(15).timeout(
        const Duration(seconds: 5),
      );
      return bestMove.bestMove;
    } catch (_) {
      return null;
    }
  }

  /// الحصول على تلميح للموقف الحالي
  Future<Hint> getHint(String fen) async {
    // تحليل الموقف
    if (_bestMoveUci == null) {
      _bestMoveUci = await _analyzePosition(fen);
    }

    if (_bestMoveUci == null || _bestMoveUci!.length < 4) {
      return const Hint(
        level: HintLevel.zone,
        textAr: 'لم يتم العثور على تلميح',
        descriptionAr: 'حاول التفكير في حركات تسيطر على المركز',
      );
    }

    final from = _bestMoveUci!.substring(0, 2);
    final to = _bestMoveUci!.substring(2, 4);

    // إنشاء التلميح حسب المستوى الحالي
    final hint = _buildHint(_currentLevel, from, to, fen);

    // ترقية المستوى
    _hintsUsed++;
    if (_currentLevel != HintLevel.fullMove) {
      _currentLevel = HintLevel.values[_currentLevel.index + 1];
    }

    return hint;
  }

  /// بناء التلميح حسب المستوى
  Hint _buildHint(HintLevel level, String from, String to, String fen) {
    final fromZone = _getSquareZone(from);
    final toZone = _getSquareZone(to);
    final piece = _getPieceAtSquare(fen, from);
    final pieceNameAr = _getPieceNameAr(piece);
    final directionAr = _getDirectionAr(from, to);

    return switch (level) {
      HintLevel.zone => Hint(
          level: HintLevel.zone,
          textAr: 'انظر إلى ${fromZone.arabicName}',
          descriptionAr: 'الحركة المطلوبة في منطقة ${fromZone.arabicName} من الرقعة',
          zones: [fromZone],
          highlightedSquares: _getZoneSquares(fromZone),
        ),
      HintLevel.piece => Hint(
          level: HintLevel.piece,
          textAr: 'حرّك $pieceNameAr على المربع $from',
          descriptionAr: 'القطعة المطلوبة هي $pieceNameAr الموجودة على المربع $from',
          highlightedSquares: [from],
          zones: [fromZone],
        ),
      HintLevel.direction => Hint(
          level: HintLevel.direction,
          textAr: 'حرّك $pieceNameAr باتجاه ${toZone.arabicName}',
          descriptionAr: 'الاتجاه: $directionAr نحو المنطقة ${toZone.arabicName}',
          highlightedSquares: [from, to],
          zones: [fromZone, toZone],
        ),
      HintLevel.fullMove => Hint(
          level: HintLevel.fullMove,
          textAr: 'الحركة: $from → $to',
          descriptionAr: 'حرّك $pieceNameAr من $from إلى $to',
          highlightedSquares: [from, to],
        ),
    };
  }

  /// إعادة تعيين التلميحات (لغز جديد)
  void reset() {
    _currentLevel = HintLevel.zone;
    _hintsUsed = 0;
    _bestMoveUci = null;
  }

  /// تحديد منطقة المربع
  BoardZone _getSquareZone(String square) {
    final file = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(square[1]) - 1;

    final isQueenside = file < 4;
    final isKingside = file >= 4;
    final isTop = rank >= 4;
    final isBottom = rank < 4;
    final isCenterFile = file >= 2 && file <= 5;
    final isCenterRank = rank >= 2 && rank <= 5;

    if (isCenterFile && isCenterRank) return BoardZone.center;
    if (isQueenside && isTop) return BoardZone.queensideTop;
    if (isKingside && isTop) return BoardZone.kingsideTop;
    if (isQueenside && isBottom) return BoardZone.queensideBottom;
    if (isKingside && isBottom) return BoardZone.kingsideBottom;
    return BoardZone.center;
  }

  /// الحصول على مربعات المنطقة
  List<String> _getZoneSquares(BoardZone zone) {
    final squares = <String>[];
    final files = 'abcdefgh'.split('');
    final ranks = '12345678'.split('');

    for (final f in files) {
      for (final r in ranks) {
        final sq = '$f$r';
        if (_getSquareZone(sq) == zone) {
          squares.add(sq);
        }
      }
    }
    return squares;
  }

  /// الحصول على القطعة على المربع
  String? _getPieceAtSquare(String fen, String square) {
    try {
      final game = chess.Chess.fromFEN(fen);
      final piece = game.get(square);
      if (piece == null) return null;
      return '${piece.color.name}${piece.type.name}';
    } catch (_) {
      return null;
    }
  }

  /// اسم القطعة بالعربية
  String _getPieceNameAr(String? piece) {
    if (piece == null) return 'القطعة';
    final lower = piece.toLowerCase();
    if (lower.contains('k')) return 'الملك ♔';
    if (lower.contains('q')) return 'الوزير ♕';
    if (lower.contains('r')) return 'القلعة ♖';
    if (lower.contains('b')) return 'الفيل ♗';
    if (lower.contains('n')) return 'الحصان ♘';
    if (lower.contains('p')) return 'البيدق ♙';
    return 'القطعة';
  }

  /// الاتجاه بالعربية
  String _getDirectionAr(String from, String to) {
    final fromFile = from.codeUnitAt(0);
    final toFile = to.codeUnitAt(0);
    final fromRank = int.parse(from[1]);
    final toRank = int.parse(to[1]);

    final buffer = StringBuffer();

    if (toRank > fromRank) buffer.write('للأمام');
    else if (toRank < fromRank) buffer.write('للخلف');

    if (toFile > fromFile) {
      if (buffer.isNotEmpty) buffer.write(' و');
      buffer.write('ليميناً');
    } else if (toFile < fromFile) {
      if (buffer.isNotEmpty) buffer.write(' و');
      buffer.write('يساراً');
    }

    if (buffer.isEmpty) buffer.write('في نفس المكان');

    return buffer.toString();
  }

  /// تنظيف الموارد
  void dispose() {
    _engine = null;
    _bestMoveUci = null;
  }
}
