/// safe_pgn_parser.dart
/// محلل PGN آمن مع استرداد احتياطي (إصلاح #19)
///
/// يحل مشكلة PGN المكسورة من API imports
/// بتحليل متسامح (tolerant parsing) مع fallback recovery.
///
/// كيف يحلها ChessIs:
/// - tolerant parser
/// - safeParse() مع fallback recovery
///
/// في Flutter:
/// - safeParse() مع fallback recovery
/// - compute() لـ parsing في isolate منفصل (إصلاح #10)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:chess/chess.dart' as chess;

import 'pgn_parser.dart';

/// نتيجة التحليل الآمن
class SafePgnResult {
  /// نتيجة التحليل (null إذا فشل كل شيء)
  final PgnParseResult? result;

  /// هل تم التحليل بنجاح كاملاً؟
  final bool isFullyParsed;

  /// هل تم استخدام الاسترداد الاحتياطي؟
  final bool usedFallback;

  /// رسائل التحذير
  final List<String> warnings;

  /// عدد الحركات المستردة (من إجمالي N)
  final int recoveredMoves;

  /// إجمالي الحركات المكتشفة
  final int totalDetectedMoves;

  const SafePgnResult({
    this.result,
    this.isFullyParsed = false,
    this.usedFallback = false,
    this.warnings = const [],
    this.recoveredMoves = 0,
    this.totalDetectedMoves = 0,
  });

  /// هل يوجد نتيجة صالحة؟
  bool get hasResult => result != null && result!.moves.isNotEmpty;
}

/// محلل PGN آمن — Safe PGN Parser
///
/// يوفر تحليلاً متسامحاً لـ PGN مع استرداد احتياطي:
/// 1. يحاول التحليل الكامل أولاً
/// 2. إذا فشل، يحاول التحليل المتسامح (تجاهل الأخطاء)
/// 3. إذا فشل، يحاول استخراج الحركات فقط
/// 4. إذا فشل، يحاول استخراج أي شيء مفيد
///
/// الاستخدام:
/// ```dart
/// final result = SafePgnParser.safeParse(pgnText);
/// if (result.hasResult) {
///   final moves = result.result!.moves;
///   // استخدم الحركات
/// } else {
///   // أظهر رسالة خطأ
///   debugPrint(result.warnings.join('\n'));
/// }
///
/// // تحليل في isolate منفصل (إصلاح #10)
/// final result = await SafePgnParser.parseInIsolate(pgnText);
/// ```
class SafePgnParser {
  static const _tag = 'SafePgnParser';

  /// تحليل آمن مع استرداد احتياطي
  static SafePgnResult safeParse(String pgnText) {
    if (pgnText.trim().isEmpty) {
      return const SafePgnResult(
        warnings: ['نص PGN فارغ'],
      );
    }

    final warnings = <String>[];

    // ── المرحلة 1: تحليل كامل ──────────────────────────────
    try {
      final result = PgnParser.parse(pgnText);
      if (result.moves.isNotEmpty) {
        return SafePgnResult(
          result: result,
          isFullyParsed: true,
          recoveredMoves: result.moves.length,
          totalDetectedMoves: result.moves.length,
        );
      }
    } catch (e) {
      warnings.add('فشل التحليل الكامل: $e');
    }

    // ── المرحلة 2: تنظيف + تحليل متسامح ──────────────────
    try {
      final cleanedPgn = _cleanPgn(pgnText);
      final result = PgnParser.parse(cleanedPgn);
      if (result.moves.isNotEmpty) {
        return SafePgnResult(
          result: result,
          isFullyParsed: false,
          usedFallback: true,
          warnings: warnings,
          recoveredMoves: result.moves.length,
          totalDetectedMoves: result.moves.length,
        );
      }
    } catch (e) {
      warnings.add('فشل التحليل المتسامح: $e');
    }

    // ── المرحلة 3: استخراج الحركات يدوياً ─────────────────
    try {
      final extractedMoves = _extractMovesManually(pgnText);
      if (extractedMoves.isNotEmpty) {
        final headers = _extractHeaders(pgnText);
        final result = PgnParseResult(
          headers: headers,
          moves: extractedMoves,
          result: _extractResult(pgnText),
        );
        return SafePgnResult(
          result: result,
          isFullyParsed: false,
          usedFallback: true,
          warnings: warnings,
          recoveredMoves: extractedMoves.length,
          totalDetectedMoves: extractedMoves.length,
        );
      }
    } catch (e) {
      warnings.add('فشل استخراج الحركات: $e');
    }

    // ── المرحلة 4: استخراج أي شيء مفيد ────────────────────
    try {
      final partialMoves = _extractPartialMoves(pgnText);
      if (partialMoves.isNotEmpty) {
        final headers = _extractHeaders(pgnText);
        final result = PgnParseResult(
          headers: headers,
          moves: partialMoves,
          result: _extractResult(pgnText),
        );
        return SafePgnResult(
          result: result,
          isFullyParsed: false,
          usedFallback: true,
          warnings: warnings,
          recoveredMoves: partialMoves.length,
          totalDetectedMoves: _countMoveTokens(pgnText),
        );
      }
    } catch (e) {
      warnings.add('فشل الاستخراج الجزئي: $e');
    }

    return SafePgnResult(
      warnings: warnings,
      totalDetectedMoves: _countMoveTokens(pgnText),
    );
  }

  /// تحليل في isolate منفصل (إصلاح #10 - PGN ضخم)
  ///
  /// يُستخدم لملفات PGN الكبيرة (أكثر من 300 حركة)
  /// لتجنب تجميد واجهة المستخدم.
  static Future<SafePgnResult> parseInIsolate(String pgnText) async {
    // للملفات الصغيرة، نحلل مباشرة
    if (pgnText.length < 5000) {
      return safeParse(pgnText);
    }

    // للملفات الكبيرة، نستخدم compute
    try {
      return await compute(_safeParseInIsolate, pgnText);
    } catch (e) {
      debugPrint('$_tag: فشل التحليل في Isolate: $e');
      // fallback للتحليل المباشر
      return safeParse(pgnText);
    }
  }

  /// تحليل عدة مباريات في isolate منفصل
  static Future<List<SafePgnResult>> parseMultipleInIsolate(
    String pgnText,
  ) async {
    try {
      return await compute(_parseMultipleInIsolate, pgnText);
    } catch (e) {
      debugPrint('$_tag: فشل تحليل المباريات في Isolate: $e');
      final gameBlocks = _splitIntoGames(pgnText);
      return gameBlocks.map((block) => safeParse(block)).toList();
    }
  }

  // ========================================================================
  // دوال Isolate (يجب أن تكون static أو top-level)
  // ========================================================================

  /// تحليل آمن داخل Isolate
  static SafePgnResult _safeParseInIsolate(String pgnText) {
    return safeParse(pgnText);
  }

  /// تحليل عدة مباريات داخل Isolate
  static List<SafePgnResult> _parseMultipleInIsolate(String pgnText) {
    final gameBlocks = _splitIntoGames(pgnText);
    return gameBlocks.map((block) => safeParse(block)).toList();
  }

  // ========================================================================
  // تنظيف PGN
  // ========================================================================

  /// تنظيف نص PGN من المشاكل الشائعة
  static String _cleanPgn(String pgnText) {
    var cleaned = pgnText;

    // 1. إزالة الأسطر الفارغة المتعددة
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 2. إصلاح الرؤوس بدون علامات اقتباس
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\[(\w+)\s+([^\]]+)\]'),
      (match) {
        final key = match.group(1)!;
        var value = match.group(2)!;
        if (!value.startsWith('"')) {
          value = '"$value"';
        }
        return '[$key $value]';
      },
    );

    // 3. إزالة التعليقات المتداخلة المكسورة
    cleaned = _fixBrokenComments(cleaned);

    // 4. إصلاح أرقام الحركات المكسورة
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d+)\s*\.\s*\.\s*\.'),
      (match) => '${match.group(1)}...',
    );

    // 5. إزالة الأحرف غير القابلة للطباعة
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    // 6. توحيد نهايات الأسطر
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 7. إزالة النتائج المتكررة
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(1-0|0-1|1/2-1/2|\*)\s+(1-0|0-1|1/2-1/2|\*)'),
      (match) => match.group(1)!,
    );

    return cleaned.trim();
  }

  /// إصلاح التعليقات المكسورة
  static String _fixBrokenComments(String pgnText) {
    // إزالة التعليقات غير المغلقة
    final buffer = StringBuffer();
    bool inComment = false;

    for (int i = 0; i < pgnText.length; i++) {
      final char = pgnText[i];

      if (char == '{' && !inComment) {
        inComment = true;
        buffer.write(char);
        continue;
      }

      if (char == '}' && inComment) {
        inComment = false;
        buffer.write(char);
        continue;
      }

      if (inComment && char == '\n' && i + 1 < pgnText.length) {
        // تعليق غير مغلق عبر سطر — نغلقه
        final nextChar = pgnText[i + 1];
        if (RegExp(r'[a-hKQRBN1-8]').hasMatch(nextChar)) {
          buffer.write('}');
          inComment = false;
          buffer.write(char);
          continue;
        }
      }

      buffer.write(char);
    }

    // إغلاق أي تعليق مفتوح متبقي
    if (inComment) {
      buffer.write('}');
    }

    return buffer.toString();
  }

  // ========================================================================
  // استخراج يدوي
  // ========================================================================

  /// استخراج الحركات يدوياً من PGN
  static List<ParsedMove> _extractMovesManually(String pgnText) {
    final moves = <ParsedMove>[];

    try {
      final game = chess.Chess();
      final moveTokens = _extractMoveTokens(pgnText);

      int moveNumber = 1;
      chess.Color currentColor = chess.Color.WHITE;

      for (final token in moveTokens) {
        try {
          if (_isLikelyMove(token)) {
            final moveObj = game.move(token);
            if (moveObj != null) {
              String? uci;
              if (moveObj != null) {
                final from = moveObj.from;
                final to = moveObj.to;
                final promotion = moveObj.promotion;
                uci = promotion != null && promotion.isNotEmpty
                    ? '$from$to${promotion.toLowerCase()}'
                    : '$from$to';
              }

              moves.add(ParsedMove(
                moveNumber: moveNumber,
                color: currentColor,
                san: token,
                uci: uci,
              ));

              if (currentColor == chess.Color.WHITE) {
                currentColor = chess.Color.BLACK;
              } else {
                moveNumber++;
                currentColor = chess.Color.WHITE;
              }
            }
          }
        } catch (e) {
          // تخطي الحركة غير الصالحة
          continue;
        }
      }
    } catch (e) {
      debugPrint('SafePgnParser: فشل الاستخراج اليدوي: $e');
    }

    return moves;
  }

  /// استخراج جزئي — أي حركات صالحة يمكن العثور عليها
  static List<ParsedMove> _extractPartialMoves(String pgnText) {
    final moves = <ParsedMove>[];

    try {
      final game = chess.Chess();
      final tokens = pgnText.split(RegExp(r'\s+'));

      int moveNumber = 1;
      chess.Color currentColor = chess.Color.WHITE;

      for (final token in tokens) {
        final cleanToken = token.replaceAll(RegExp(r'[!?]+$'), '');

        if (cleanToken.isEmpty) continue;
        if (RegExp(r'^\d+\.+$').hasMatch(cleanToken)) continue;
        if (_isResultToken(cleanToken)) continue;
        if (cleanToken.startsWith('[')) continue;
        if (cleanToken.startsWith('{')) continue;
        if (cleanToken.startsWith('(')) continue;

        try {
          final moveObj = game.move(cleanToken);
          if (moveObj != null) {
            moves.add(ParsedMove(
              moveNumber: moveNumber,
              color: currentColor,
              san: cleanToken,
            ));

            if (currentColor == chess.Color.WHITE) {
              currentColor = chess.Color.BLACK;
            } else {
              moveNumber++;
              currentColor = chess.Color.WHITE;
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}

    return moves;
  }

  /// استخراج رموز الحركات من نص PGN
  static List<String> _extractMoveTokens(String pgnText) {
    final tokens = <String>[];

    // إزالة الرؤوس والتعليقات
    final movesOnly = pgnText
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '');

    final parts = movesOnly.split(RegExp(r'\s+'));

    for (final part in parts) {
      final clean = part.replaceAll(RegExp(r'[!?]+$'), '').trim();
      if (clean.isEmpty) continue;
      if (RegExp(r'^\d+\.+$').hasMatch(clean)) continue;
      if (_isResultToken(clean)) continue;
      tokens.add(clean);
    }

    return tokens;
  }

  // ========================================================================
  // دوال مساعدة
  // ========================================================================

  /// هل الرمز يشبه حركة شطرنج؟
  static bool _isLikelyMove(String token) {
    return RegExp(
      r'^[a-hKQRBN]?[a-h]?[1-8]?[x@]?[a-h][1-8]=[QRBN]?[+#!?]*$|^O-O(-O)?[+#!?]*$|^0-0(-0)?[+#!?]*$',
    ).hasMatch(token);
  }

  /// هل الرمز هو نتيجة؟
  static bool _isResultToken(String token) {
    return token == '1-0' || token == '0-1' || token == '1/2-1/2' || token == '*';
  }

  /// استخراج رؤوس PGN
  static Map<String, String> _extractHeaders(String pgnText) {
    final headers = <String, String>{};
    final regex = RegExp(r'\[(\w+)\s+"([^"]*)"\]');

    for (final match in regex.allMatches(pgnText)) {
      headers[match.group(1)!] = match.group(2)!;
    }

    return headers;
  }

  /// استخراج نتيجة المباراة
  static String _extractResult(String pgnText) {
    if (pgnText.contains('1-0')) return '1-0';
    if (pgnText.contains('0-1')) return '0-1';
    if (pgnText.contains('1/2-1/2')) return '1/2-1/2';
    return '*';
  }

  /// عد رموز الحركات في النص
  static int _countMoveTokens(String pgnText) {
    final cleaned = pgnText
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '');

    return _extractMoveTokens(cleaned).length;
  }

  /// تقسيم نص PGN إلى مباريات منفصلة
  static List<String> _splitIntoGames(String pgnText) {
    final games = <String>[];
    final lines = pgnText.split('\n');
    final currentGame = StringBuffer();
    bool inHeaders = false;
    bool inMoves = false;

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        if (inMoves && currentGame.isNotEmpty) {
          games.add(currentGame.toString());
          currentGame.clear();
        }
        currentGame.writeln(line);
        inHeaders = true;
        inMoves = false;
        continue;
      }

      if (trimmed.isEmpty && inHeaders) {
        currentGame.writeln(line);
        continue;
      }

      if (trimmed.isNotEmpty && inHeaders) {
        inMoves = true;
      }

      currentGame.writeln(line);
    }

    if (currentGame.isNotEmpty) {
      games.add(currentGame.toString());
    }

    return games;
  }
}
