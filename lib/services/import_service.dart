/// import_service.dart
/// خدمة الاستيراد الموحدة — Unified Import Service
///
/// تكتشف نوع المدخل (PGN، FEN، URL) وتوجهه إلى المحلل المناسب.
library;

import 'chesscom_import.dart';
import 'lichess_import.dart';
import 'pgn_parser.dart';
import '../models/chess_models.dart';

/// نوع المدخل المكتشف
enum InputType {
  pgn,
  fen,
  chesscomUrl,
  lichessUrl,
  chesscomUsername,
  lichessUsername,
  unknown,
}

/// نتيجة الاستيراد
class ImportResult {
  final List<ChessMatch> matches;
  final int totalFound;
  final int successCount;
  final int failCount;
  final List<String> errors;

  const ImportResult({
    required this.matches,
    this.totalFound = 0,
    this.successCount = 0,
    this.failCount = 0,
    this.errors = const [],
  });

  bool get isSuccess => errors.isEmpty;
  bool get hasPartialSuccess => successCount > 0 && failCount > 0;
}

/// خدمة الاستيراد الموحدة
class ImportService {
  /// كشف نوع المدخل تلقائياً
  static InputType detectInputType(String input) {
    final trimmed = input.trim();

    // FEN: يحتوي على 6 أجزاء مفصولة بمسافات
    if (_isFEN(trimmed)) {
      return InputType.fen;
    }

    // URL Chess.com
    if (trimmed.contains('chess.com') || trimmed.contains('chesscom')) {
      return InputType.chesscomUrl;
    }

    // URL Lichess
    if (trimmed.contains('lichess.org')) {
      return InputType.lichessUrl;
    }

    // PGN: يحتوي على أقواس مربعة مع رؤوس
    if (_isPGN(trimmed)) {
      return InputType.pgn;
    }

    // اسم مستخدم (كلمة واحدة بدون مسافات)
    if (_isUsername(trimmed)) {
      // لا نستطيع تحديد المنصة بالتأكيد، نرجع unknown
      return InputType.unknown;
    }

    return InputType.unknown;
  }

  /// استيراد من نص PGN
  static ImportResult importPGN(String pgnText) {
    try {
      final results = PgnParser.parseMultiple(pgnText);
      final matches = <ChessMatch>[];
      final errors = <String>[];

      for (int i = 0; i < results.length; i++) {
        try {
          final result = results[i];
          final match = ChessMatch(
            id: 'pgn_${DateTime.now().millisecondsSinceEpoch}_$i',
            whiteName: result.whitePlayer ?? 'أبيض',
            blackName: result.blackPlayer ?? 'أسود',
            whiteElo: int.tryParse(result.headers['WhiteElo'] ?? ''),
            blackElo: int.tryParse(result.headers['BlackElo'] ?? ''),
            result: GameResult.fromPgn(result.result),
            date: _parseDate(result.headers['Date']),
            event: result.event,
            site: result.site,
            round: int.tryParse(result.headers['Round'] ?? ''),
            rawPgn: pgnText,
            moves: const [],
            evalPoints: const [],
          );
          matches.add(match);
        } catch (e) {
          errors.add('خطأ في تحليل المباراة ${i + 1}: $e');
        }
      }

      return ImportResult(
        matches: matches,
        totalFound: results.length,
        successCount: matches.length,
        failCount: errors.length,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        matches: const [],
        errors: ['خطأ في تحليل PGN: $e'],
      );
    }
  }

  /// استيراد من FEN
  static ImportResult importFEN(String fen) {
    if (!_isFEN(fen.trim())) {
      return const ImportResult(
        matches: [],
        errors: ['نص FEN غير صالح. يجب أن يحتوي على 6 أجزاء مفصولة بمسافات.'],
      );
    }

    final match = ChessMatch(
      id: 'fen_${DateTime.now().millisecondsSinceEpoch}',
      whiteName: 'الأبيض',
      blackName: 'الأسود',
      result: GameResult.incomplete,
      initialFen: fen.trim(),
      rawPgn: '',
      moves: const [],
      evalPoints: const [],
    );

    return ImportResult(
      matches: [match],
      totalFound: 1,
      successCount: 1,
    );
  }

  /// استيراد من Chess.com
  static Future<ImportResult> importFromChessCom({
    required String username,
    int months = 1,
  }) async {
    try {
      final games = await ChessComImportService.fetchRecentGames(
        username: username,
        months: months,
      );
      return ImportResult(
        matches: games,
        totalFound: games.length,
        successCount: games.length,
      );
    } on ChessComImportException catch (e) {
      return ImportResult(
        matches: const [],
        errors: [e.message],
      );
    } catch (e) {
      return ImportResult(
        matches: const [],
        errors: ['خطأ غير متوقع: $e'],
      );
    }
  }

  /// استيراد من Lichess
  static Future<ImportResult> importFromLichess({
    required String username,
    int maxGames = 20,
  }) async {
    try {
      final games = await LichessImportService.fetchGames(
        username: username,
        maxGames: maxGames,
      );
      return ImportResult(
        matches: games,
        totalFound: games.length,
        successCount: games.length,
      );
    } on LichessImportException catch (e) {
      return ImportResult(
        matches: const [],
        errors: [e.message],
      );
    } catch (e) {
      return ImportResult(
        matches: const [],
        errors: ['خطأ غير متوقع: $e'],
      );
    }
  }

  /// استيراد تلقائي بناءً على نوع المدخل
  static Future<ImportResult> importAuto(String input) async {
    final type = detectInputType(input);

    switch (type) {
      case InputType.pgn:
        return importPGN(input);
      case InputType.fen:
        return importFEN(input);
      case InputType.chesscomUrl:
        // استخراج اسم المستخدم من الرابط
        final username = _extractChessComUsername(input);
        if (username != null) {
          return importFromChessCom(username: username);
        }
        return const ImportResult(
          matches: [],
          errors: ['لم يتم التعرف على رابط Chess.com.'],
        );
      case InputType.lichessUrl:
        final username = _extractLichessUsername(input);
        if (username != null) {
          return importFromLichess(username: username);
        }
        return const ImportResult(
          matches: [],
          errors: ['لم يتم التعرف على رابط Lichess.'],
        );
      case InputType.chesscomUsername:
        return importFromChessCom(username: input.trim());
      case InputType.lichessUsername:
        return importFromLichess(username: input.trim());
      case InputType.unknown:
        // محاولة كـ PGN أولاً ثم FEN
        if (input.contains('[') || input.contains('1.')) {
          return importPGN(input);
        }
        return const ImportResult(
          matches: [],
          errors: ['لم يتم التعرف على نوع المدخل. يرجى إدخال PGN أو FEN أو اسم مستخدم.'],
        );
    }
  }

  // ─── دوال مساعدة ──────────────────────────────────────────────────────────

  /// هل النص بصيغة FEN؟
  static bool _isFEN(String text) {
    final parts = text.split(' ');
    if (parts.length != 6) return false;

    // التحقق من وضعية الرقعة
    final ranks = parts[0].split('/');
    if (ranks.length != 8) return false;

    // التحقق من دور اللعب
    if (parts[1] != 'w' && parts[1] != 'b') return false;

    return true;
  }

  /// هل النص بصيغة PGN؟
  static bool _isPGN(String text) {
    // يحتوي على رؤوس PGN
    if (text.contains('[Event "') || text.contains('[Site "')) {
      return true;
    }
    // يحتوي على حركات شطرنج
    if (text.contains('1.') && (text.contains('2.') || text.contains('...'))) {
      return true;
    }
    return false;
  }

  /// هل النص اسم مستخدم محتمل؟
  static bool _isUsername(String text) {
    if (text.isEmpty || text.length > 40) return false;
    if (text.contains(' ') || text.contains('\n')) return false;
    // اسم المستخدم يحتوي على حروف وأرقام وشرطات فقط
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(text);
  }

  /// استخراج اسم المستخدم من رابط Chess.com
  static String? _extractChessComUsername(String url) {
    // https://www.chess.com/member/username
    final match = RegExp(r'chess\.com/member/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  /// استخراج اسم المستخدم من رابط Lichess
  static String? _extractLichessUsername(String url) {
    // https://lichess.org/@/username
    final match = RegExp(r'lichess\.org/@/([a-zA-Z0-9_-]+)').firstMatch(url);
    return match?.group(1);
  }

  /// تحليل التاريخ من نص PGN
  static DateTime? _parseDate(String? dateStr) {
    if (dateStr == null) return null;
    final parts = dateStr.split('.');
    if (parts.length == 3) {
      return DateTime.tryParse(parts.join('-'));
    }
    return DateTime.tryParse(dateStr);
  }
}
