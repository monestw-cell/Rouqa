/// محلل PGN — PGN Parser
/// تحليل ملفات PGN واستخراج الحركات والرؤوس والتعليقات والتبديلات
library;

import 'package:chess/chess.dart' as chess;

// ─── نماذج البيانات — Data Models ──────────────────────────────────────────

/// نموذج رأس PGN
class PgnHeader {
  final String key;
  final String value;

  const PgnHeader({required this.key, required this.value});

  @override
  String toString() => '[$key "$value"]';
}

/// تصنيف NAG (Numeric Annotation Glyph)
class NagAnnotation {
  final int value;
  final String symbol;
  final String descriptionAr;

  const NagAnnotation({
    required this.value,
    required this.symbol,
    required this.descriptionAr,
  });
}

/// خريطة رموز NAG
const Map<int, NagAnnotation> kNagMap = {
  1: NagAnnotation(value: 1, symbol: '!', descriptionAr: 'حركة جيدة'),
  2: NagAnnotation(value: 2, symbol: '?', descriptionAr: 'حركة سيئة'),
  3: NagAnnotation(value: 3, symbol: '!!', descriptionAr: 'حركة رائعة'),
  4: NagAnnotation(value: 4, symbol: '??', descriptionAr: 'خطأ فادح'),
  5: NagAnnotation(value: 5, symbol: '!?', descriptionAr: 'حركة مثيرة للاهتمام'),
  6: NagAnnotation(value: 6, symbol: '?!', descriptionAr: 'حركة مشكوك فيها'),
  7: NagAnnotation(value: 7, symbol: '□', descriptionAr: 'حركة قسرية'),
  10: NagAnnotation(value: 10, symbol: '=', descriptionAr: 'وضع متساوٍ'),
  13: NagAnnotation(value: 13, symbol: '∞', descriptionAr: 'وضع غير واضح'),
  14: NagAnnotation(value: 14, symbol: '+=', descriptionAr: 'أبيض يتفوق قليلاً'),
  15: NagAnnotation(value: 15, symbol: '=+', descriptionAr: 'أسود يتفوق قليلاً'),
  16: NagAnnotation(value: 16, symbol: '±', descriptionAr: 'أبيض يتفوق'),
  17: NagAnnotation(value: 17, symbol: '∓', descriptionAr: 'أسود يتفوق'),
  18: NagAnnotation(value: 18, symbol: '+-', descriptionAr: 'أبيض يتفوق بوضوح'),
  19: NagAnnotation(value: 19, symbol: '-+', descriptionAr: 'أسود يتفوق بوضوح'),
};

/// نموذج حركة واحدة مُحللة
class ParsedMove {
  /// رقم الحركة (يبدأ من 1)
  final int moveNumber;

  /// لون اللاعب
  final chess.Color color;

  /// الحركة بتدوين SAN (مثل: Nf3)
  final String san;

  /// الحركة بتدوين UCI (مثل: g1f3)
  final String? uci;

  /// تعليق على الحركة
  final String? comment;

  /// رمز NAG
  final int? nag;

  /// التبديلات (الحركات البديلة)
  final List<List<ParsedMove>> variations;

  /// زمن التفكير (من تعليق [%clk])
  final Duration? clockTime;

  /// تقييم المحرك (من تعليق [%eval])
  final double? evalScore;

  /// عمق التقييم (من تعليق [%eval])
  final int? evalDepth;

  const ParsedMove({
    required this.moveNumber,
    required this.color,
    required this.san,
    this.uci,
    this.comment,
    this.nag,
    this.variations = const [],
    this.clockTime,
    this.evalScore,
    this.evalDepth,
  });

  /// هل اللاعب أبيض؟
  bool get isWhite => color == chess.Color.WHITE;

  @override
  String toString() {
    final prefix = isWhite ? '$moveNumber. ' : '$moveNumber... ';
    return '$prefix$san';
  }
}

/// نتيجة تحليل PGN كاملة
class PgnParseResult {
  /// رؤوس PGN
  final Map<String, String> headers;

  /// قائمة الحركات المُحللة
  final List<ParsedMove> moves;

  /// نتيجة المباراة
  final String result;

  /// الفتحات المكتشفة (ECO)
  final String? eco;

  /// اسم الافتتاحية
  final String? opening;

  const PgnParseResult({
    required this.headers,
    required this.moves,
    required this.result,
    this.eco,
    this.opening,
  });

  /// اسم اللاعب الأبيض
  String? get whitePlayer => headers['White'];

  /// اسم اللاعب الأسود
  String? get blackPlayer => headers['Black'];

  /// تاريخ المباراة
  String? get date => headers['Date'];

  /// الحدث
  String? get event => headers['Event'];

  /// الموقع
  String? get site => headers['Site'];

  /// الجولة
  String? get round => headers['Round'];

  /// ضبط الوقت
  String? get timeControl => headers['TimeControl'];

  /// PGN كامل للحركات فقط
  String get movesText {
    final buffer = StringBuffer();
    for (final move in moves) {
      if (move.isWhite) {
        buffer.write('${move.moveNumber}. ');
      }
      buffer.write('${move.san} ');
    }
    buffer.write(result);
    return buffer.toString().trim();
  }
}

// ─── محلل PGN — PGN Parser ─────────────────────────────────────────────────

class PgnParser {
  /// تحليل نص PGN كامل وإرجاع النتيجة
  static PgnParseResult parse(String pgnText) {
    final lines = pgnText.split('\n');
    final headers = <String, String>{};
    int lineIndex = 0;

    // ─── تحليل الرؤوس ────────────────────────────────────────────────────
    while (lineIndex < lines.length) {
      final line = lines[lineIndex].trim();
      if (line.isEmpty) {
        lineIndex++;
        continue;
      }

      // التحقق من أن السطر هو رأس [Key "Value"]
      final headerRegex = RegExp(r'^\[(\w+)\s+"(.*)"\]$');
      final match = headerRegex.firstMatch(line);
      if (match != null) {
        headers[match.group(1)!] = match.group(2)!;
        lineIndex++;
      } else {
        // وصلنا إلى قسم الحركات
        break;
      }
    }

    // ─── تجميع نص الحركات ────────────────────────────────────────────────
    final movesBuffer = StringBuffer();
    while (lineIndex < lines.length) {
      movesBuffer.write(lines[lineIndex]);
      movesBuffer.write(' ');
      lineIndex++;
    }

    final movesText = movesBuffer.toString().trim();

    // ─── استخراج النتيجة ─────────────────────────────────────────────────
    String result = '*';
    if (movesText.endsWith('1-0')) {
      result = '1-0';
    } else if (movesText.endsWith('0-1')) {
      result = '0-1';
    } else if (movesText.endsWith('1/2-1/2')) {
      result = '1/2-1/2';
    }

    // ─── تحليل الحركات ───────────────────────────────────────────────────
    final moves = _parseMoves(movesText);

    return PgnParseResult(
      headers: headers,
      moves: moves,
      result: result,
      eco: headers['ECO'],
      opening: headers['Opening'],
    );
  }

  /// تحليل عدة مباريات من نص PGN
  static List<PgnParseResult> parseMultiple(String pgnText) {
    // تقسيم المباريات بفاصل الرؤوس
    final games = <PgnParseResult>[];
    final gameBlocks = _splitPgnGames(pgnText);

    for (final block in gameBlocks) {
      if (block.trim().isNotEmpty) {
        try {
          games.add(parse(block));
        } catch (_) {
          // تخطي المباريات التالفة
          continue;
        }
      }
    }

    return games;
  }

  /// تقسيم نص PGN إلى كتل مباريات منفصلة
  static List<String> _splitPgnGames(String pgnText) {
    final games = <String>[];
    final lines = pgnText.split('\n');
    final currentGame = StringBuffer();
    bool foundHeaders = false;
    bool inMoves = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // بداية رأس جديد لمباراة جديدة
      final headerRegex = RegExp(r'^\[(\w+)\s+"(.*)"\]$');
      if (headerRegex.hasMatch(trimmed)) {
        if (inMoves && currentGame.isNotEmpty) {
          // حفظ المباراة السابقة
          games.add(currentGame.toString());
          currentGame.clear();
          foundHeaders = false;
          inMoves = false;
        }
        currentGame.writeln(line);
        foundHeaders = true;
        continue;
      }

      if (trimmed.isEmpty) {
        currentGame.writeln(line);
        continue;
      }

      // وصلنا إلى الحركات
      if (foundHeaders && !_isHeaderLine(trimmed)) {
        inMoves = true;
      }

      currentGame.writeln(line);
    }

    // حفظ آخر مباراة
    if (currentGame.isNotEmpty) {
      games.add(currentGame.toString());
    }

    return games;
  }

  /// هل السطر هو رأس PGN؟
  static bool _isHeaderLine(String line) {
    return RegExp(r'^\[(\w+)\s+"(.*)"\]$').hasMatch(line);
  }

  /// تحليل نص الحركات مع التعليقات والتبديلات
  static List<ParsedMove> _parseMoves(String movesText) {
    final moves = <ParsedMove>[];
    final tokens = _tokenize(movesText);

    // إنشاء كائن شطرنج للتحقق من الحركات
    final game = chess.Chess();

    int moveNumber = 1;
    chess.Color currentColor = chess.Color.WHITE;
    String? pendingComment;
    int? pendingNag;
    Duration? pendingClock;
    double? pendingEval;
    int? pendingEvalDepth;

    int i = 0;
    while (i < tokens.length) {
      final token = tokens[i];

      // تجاهل أرقام الحركات (مثل: 1. أو 1...)
      if (_isMoveNumber(token)) {
        final num = _extractMoveNumber(token);
        if (num != null) {
          moveNumber = num;
        }
        // تحديد اللون من النقاط
        if (token.contains('...')) {
          currentColor = chess.Color.BLACK;
        } else {
          currentColor = chess.Color.WHITE;
        }
        i++;
        continue;
      }

      // تجاهل النتائج
      if (_isResult(token)) {
        i++;
        continue;
      }

      // تعليق بين أقواس معقوفة {comment}
      if (token.startsWith('{') || token == '{') {
        final commentText = _extractComment(tokens, i);
        if (commentText != null) {
          pendingComment = commentText.text;
          // استخراج معلومات من التعليق
          final clockInfo = _extractClockTime(commentText.text);
          if (clockInfo != null) pendingClock = clockInfo;
          final evalInfo = _extractEvalInfo(commentText.text);
          if (evalInfo != null) {
            pendingEval = evalInfo.$1;
            pendingEvalDepth = evalInfo.$2;
          }
          i = commentText.endIndex + 1;
        } else {
          i++;
        }
        continue;
      }

      // تبديل بين أقواس (variations)
      if (token == '(') {
        // تخطي التبديل بالكامل
        final endIdx = _findVariationEnd(tokens, i);
        i = endIdx + 1;
        continue;
      }

      // رمز NAG ($1, $2, etc.)
      if (token.startsWith(r'$')) {
        final nagValue = int.tryParse(token.substring(1));
        if (nagValue != null) {
          pendingNag = nagValue;
        }
        i++;
        continue;
      }

      // محاولة تطبيق الحركة
      if (_isValidMove(game, token)) {
        try {
          final chess.Move? moveObj = game.move(token);
          final uciMove = _moveToUci(moveObj);

          moves.add(ParsedMove(
            moveNumber: moveNumber,
            color: currentColor,
            san: token,
            uci: uciMove,
            comment: pendingComment,
            nag: pendingNag,
            clockTime: pendingClock,
            evalScore: pendingEval,
            evalDepth: pendingEvalDepth,
          ));

          // إعادة تعيين البيانات المعلقة
          pendingComment = null;
          pendingNag = null;
          pendingClock = null;
          pendingEval = null;
          pendingEvalDepth = null;

          // تحديث اللون
          if (currentColor == chess.Color.WHITE) {
            currentColor = chess.Color.BLACK;
          } else {
            moveNumber++;
            currentColor = chess.Color.WHITE;
          }
        } catch (_) {
          // حركة غير صالحة — تخطي
        }
        i++;
        continue;
      }

      // رمز غير معروف — تخطي
      i++;
    }

    return moves;
  }

  /// تقسيم النص إلى رموز (tokens)
  static List<String> _tokenize(String text) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    int i = 0;
    int depth = 0; // عمق التداخل

    while (i < text.length) {
      final char = text[i];

      // بداية تعليق
      if (char == '{') {
        // حفظ الرمز السابق إن وجد
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString().trim());
          buffer.clear();
        }
        depth++;
        buffer.write(char);
        i++;
        continue;
      }

      // داخل تعليق
      if (depth > 0 && char != '}') {
        buffer.write(char);
        i++;
        continue;
      }

      // نهاية تعليق
      if (char == '}') {
        buffer.write(char);
        depth--;
        tokens.add(buffer.toString().trim());
        buffer.clear();
        i++;
        continue;
      }

      // بداية تبديل
      if (char == '(') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString().trim());
          buffer.clear();
        }
        tokens.add('(');
        i++;
        continue;
      }

      // نهاية تبديل
      if (char == ')') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString().trim());
          buffer.clear();
        }
        tokens.add(')');
        i++;
        continue;
      }

      // فاصل (مسافة أو سطر جديد)
      if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString().trim());
          buffer.clear();
        }
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString().trim());
    }

    // إزالة الرموز الفارغة
    return tokens.where((t) => t.isNotEmpty).toList();
  }

  /// هل الرمز هو رقم حركة؟ (مثل: 1. أو 1... أو 12.)
  static bool _isMoveNumber(String token) {
    return RegExp(r'^\d+\.+$').hasMatch(token);
  }

  /// استخراج رقم الحركة من الرمز
  static int? _extractMoveNumber(String token) {
    final match = RegExp(r'^(\d+)').firstMatch(token);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  /// هل الرمز هو نتيجة مباراة؟
  static bool _isResult(String token) {
    return token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*';
  }

  /// التحقق من صحة الحركة في الموضع الحالي
  static bool _isValidMove(chess.Chess game, String move) {
    try {
      // التحقق من أن الحركة قانونية
      final moves = game.moves();
      for (final m in moves) {
        if (m.san == move) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// تحويل كائن الحركة إلى تدوين UCI
  static String _moveToUci(chess.Move? moveObj) {
    try {
      if (moveObj != null) {
        final from = moveObj.from;
        final to = moveObj.to;
        final promotion = moveObj.promotion;
        if (promotion != null && promotion.isNotEmpty) {
          return '$from$to${promotion.toLowerCase()}';
        }
        return '$from$to';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// استخراج التعليق من الرموز
  static _CommentResult? _extractComment(List<String> tokens, int startIndex) {
    if (startIndex >= tokens.length) return null;

    final firstToken = tokens[startIndex];
    // التعليق قد يكون في رمز واحد: {text} أو مفرق
    String text = '';

    if (firstToken.startsWith('{') && firstToken.endsWith('}')) {
      text = firstToken.substring(1, firstToken.length - 1).trim();
      return _CommentResult(text: text, endIndex: startIndex);
    }

    if (firstToken.startsWith('{')) {
      final buffer = StringBuffer();
      buffer.write(firstToken.substring(1));

      for (int i = startIndex + 1; i < tokens.length; i++) {
        final t = tokens[i];
        if (t.endsWith('}')) {
          buffer.write(' ');
          buffer.write(t.substring(0, t.length - 1));
          return _CommentResult(
            text: buffer.toString().trim(),
            endIndex: i,
          );
        }
        buffer.write(' ');
        buffer.write(t);
      }
    }

    return null;
  }

  /// إيجاد نهاية التبديل (القوس المغلق المقابل)
  static int _findVariationEnd(List<String> tokens, int startIndex) {
    int depth = 0;
    for (int i = startIndex; i < tokens.length; i++) {
      if (tokens[i] == '(') depth++;
      if (tokens[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return tokens.length - 1;
  }

  /// استخراج وقت الساعة من التعليق [%clk H:MM:SS]
  static Duration? _extractClockTime(String comment) {
    final match = RegExp(r'%clk\s+(\d+):(\d+):(\d+)').firstMatch(comment);
    if (match != null) {
      final hours = int.parse(match.group(1)!);
      final minutes = int.parse(match.group(2)!);
      final seconds = int.parse(match.group(3)!);
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return null;
  }

  /// استخراج معلومات التقييم من التعليق [%eval depth,score]
  static (double, int)? _extractEvalInfo(String comment) {
    // تنسيق: [%eval 2.35,12] أو [%eval #-1,20] أو [%eval +2.35/12]
    final match = RegExp(r'%eval\s+([+-]?\d+\.?\d*|#\d+)(?:[,/]\s*(\d+))?')
        .firstMatch(comment);
    if (match != null) {
      final evalStr = match.group(1)!;
      final depthStr = match.group(2);

      double evalValue;
      if (evalStr.startsWith('#')) {
        // كش ملك — تحويل إلى قيمة كبيرة
        final movesToMate = int.tryParse(evalStr.substring(1)) ?? 0;
        evalValue = movesToMate > 0 ? 10000.0 : -10000.0;
      } else {
        evalValue = double.tryParse(evalStr) ?? 0.0;
      }

      final depth = depthStr != null ? int.tryParse(depthStr) ?? 0 : 0;
      return (evalValue, depth);
    }
    return null;
  }
}

/// نتيجة استخراج التعليق
class _CommentResult {
  final String text;
  final int endIndex;

  const _CommentResult({required this.text, required this.endIndex});
}
