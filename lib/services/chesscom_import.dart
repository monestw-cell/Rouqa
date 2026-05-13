/// chesscom_import.dart
/// استيراد المباريات من Chess.com — Chess.com API Integration
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chess_models.dart';

/// استثناءات استيراد Chess.com
class ChessComImportException implements Exception {
  final String message;
  final int? statusCode;

  const ChessComImportException(this.message, {this.statusCode});

  @override
  String toString() =>
      'ChessComImportException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}

/// خدمة استيراد المباريات من Chess.com
class ChessComImportService {
  static const _tag = 'ChessComImport';
  static const _baseUrl = 'https://api.chess.com/pub';

  /// آخر طلب (لإدارة معدل الطلبات)
  static DateTime? _lastRequestTime;

  /// الحد الأدنى بين الطلبات (مللي ثانية)
  static const _minRequestInterval = 1000;

  /// جلب مباريات اللاعب من Chess.com
  ///
  /// [username] — اسم المستخدم على Chess.com
  /// [year] — السنة (اختياري، الافتراضي: السنة الحالية)
  /// [month] — الشهر (اختياري، الافتراضي: الشهر الحالي)
  static Future<List<ChessMatch>> fetchGames({
    required String username,
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final y = year ?? now.year;
    final m = month ?? now.month;
    final monthStr = m.toString().padLeft(2, '0');

    // إدارة معدل الطلبات
    await _rateLimit();

    final url = Uri.parse('$_baseUrl/player/$username/games/$y/$monthStr');

    try {
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'RuqaChessAnalyzer/1.0',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        throw const ChessComImportException(
          'تم تجاوز حد الطلبات. يرجى المحاولة لاحقاً.',
          statusCode: 429,
        );
      }

      if (response.statusCode == 404) {
        throw ChessComImportException(
          'اللاعب "$username" غير موجود على Chess.com.',
          statusCode: 404,
        );
      }

      if (response.statusCode != 200) {
        throw ChessComImportException(
          'خطأ في الاتصال بـ Chess.com.',
          statusCode: response.statusCode,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final games = data['games'] as List<dynamic>? ?? [];

      return games
          .map((game) => _parseGame(game as Map<String, dynamic>, username))
          .where((g) => g.rawPgn != null && g.rawPgn!.isNotEmpty)
          .toList();
    } on ChessComImportException {
      rethrow;
    } catch (e) {
      throw ChessComImportException('فشل الاتصال: $e');
    }
  }

  /// جلب آخر المباريات (عدة أشهر)
  static Future<List<ChessMatch>> fetchRecentGames({
    required String username,
    int months = 3,
  }) async {
    final allGames = <ChessMatch>[];
    final now = DateTime.now();

    for (int i = 0; i < months; i++) {
      final date = DateTime(now.year, now.month - i);
      try {
        final games = await fetchGames(
          username: username,
          year: date.year,
          month: date.month,
        );
        allGames.addAll(games);
      } catch (e) {
        // تابع مع الأشهر التالية
        continue;
      }
    }

    return allGames;
  }

  /// تحليل مباراة واحدة من بيانات Chess.com
  static ChessMatch _parseGame(Map<String, dynamic> data, String username) {
    final white = data['white'] as Map<String, dynamic>? ?? {};
    final black = data['black'] as Map<String, dynamic>? ?? {};
    final pgn = data['pgn'] as String? ?? '';
    final url = data['url'] as String? ?? '';
    final endTime = data['end_time'] as int?;
    final timeClass = data['time_class'] as String? ?? '';
    final timeControl = data['time_control'] as String? ?? '';
    final rules = data['rules'] as String? ?? '';

    // تحديد النتيجة
    GameResult result = GameResult.incomplete;
    final whiteResult = white['result'] as String?;
    final blackResult = black['result'] as String?;

    if (whiteResult == 'win') {
      result = GameResult.whiteWins;
    } else if (blackResult == 'win') {
      result = GameResult.blackWins;
    } else if (whiteResult == 'agreed' || blackResult == 'agreed') {
      result = GameResult.draw;
    } else if (whiteResult == 'repetition' || blackResult == 'repetition') {
      result = GameResult.draw;
    } else if (whiteResult == 'stalemate' || blackResult == 'stalemate') {
      result = GameResult.draw;
    } else if (whiteResult == 'insufficient' || blackResult == 'insufficient') {
      result = GameResult.draw;
    } else if (whiteResult == 'timeout' || blackResult == 'timeout') {
      // انتهاء الوقت — تحديد الفائز
      if (whiteResult == 'timeout') {
        result = GameResult.blackWins;
      } else {
        result = GameResult.whiteWins;
      }
    } else if (whiteResult == 'resigned' || blackResult == 'resigned') {
      if (whiteResult == 'resigned') {
        result = GameResult.blackWins;
      } else {
        result = GameResult.whiteWins;
      }
    }

    // تحديد طريقة الانتهاء
    Termination? termination;
    if (whiteResult == 'checkmated' || blackResult == 'checkmated') {
      termination = Termination.checkmate;
    } else if (whiteResult == 'resigned' || blackResult == 'resigned') {
      termination = Termination.resignation;
    } else if (whiteResult == 'timeout' || blackResult == 'timeout') {
      termination = Termination.timeout;
    } else if (whiteResult == 'repetition' || blackResult == 'repetition') {
      termination = Termination.repetition;
    } else if (whiteResult == 'stalemate' || blackResult == 'stalemate') {
      termination = Termination.stalemate;
    } else if (whiteResult == 'insufficient' || blackResult == 'insufficient') {
      termination = Termination.insufficientMaterial;
    } else if (whiteResult == 'agreed' || blackResult == 'agreed') {
      termination = Termination.agreement;
    }

    final whiteName = white['username'] as String? ?? 'أبيض';
    final blackName = black['username'] as String? ?? 'أسود';
    final whiteRating = white['rating'] as int?;
    final blackRating = black['rating'] as int?;

    return ChessMatch(
      id: 'chesscom_${DateTime.now().millisecondsSinceEpoch}_${whiteName}_$blackName',
      whiteName: whiteName,
      blackName: blackName,
      whiteElo: whiteRating,
      blackElo: blackRating,
      result: result,
      termination: termination,
      date: endTime != null
          ? DateTime.fromMillisecondsSinceEpoch(endTime * 1000)
          : null,
      event: _getEventName(timeClass),
      site: url,
      timeControlInitial: _parseTimeControl(timeControl)?.$1,
      timeControlIncrement: _parseTimeControl(timeControl)?.$2,
      rawPgn: pgn,
      moves: const [],
      evalPoints: const [],
    );
  }

  /// تحليل ضبط الوقت من نص Chess.com
  static (int, int)? _parseTimeControl(String? tc) {
    if (tc == null || tc.isEmpty) return null;
    final parts = tc.split('+');
    if (parts.isEmpty) return null;
    final initial = int.tryParse(parts[0]);
    if (initial == null) return null;
    final increment = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return (initial, increment);
  }

  /// اسم الحدث من نوع اللعبة
  static String _getEventName(String timeClass) {
    switch (timeClass) {
      case 'bullet':
        return 'رصاصي • Bullet';
      case 'blitz':
        return 'خاطف • Blitz';
      case 'rapid':
        return 'سريع • Rapid';
      case 'daily':
        return 'يومي • Daily';
      default:
        return 'مباراة Chess.com';
    }
  }

  /// إدارة معدل الطلبات
  static Future<void> _rateLimit() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      if (elapsed.inMilliseconds < _minRequestInterval) {
        await Future.delayed(
          Duration(milliseconds: _minRequestInterval - elapsed.inMilliseconds),
        );
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// التحقق من وجود اللاعب
  static Future<bool> playerExists(String username) async {
    await _rateLimit();
    try {
      final url = Uri.parse('$_baseUrl/player/$username');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'RuqaChessAnalyzer/1.0',
        },
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
