/// lichess_import.dart
/// استيراد المباريات من Lichess — Lichess API Integration
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chess_models.dart';

/// استثناءات استيراد Lichess
class LichessImportException implements Exception {
  final String message;
  final int? statusCode;

  const LichessImportException(this.message, {this.statusCode});

  @override
  String toString() =>
      'LichessImportException: $message${statusCode != null ? ' ($statusCode)' : ''}';
}

/// خدمة استيراد المباريات من Lichess
class LichessImportService {
  static const _tag = 'LichessImport';
  static const _baseUrl = 'https://lichess.org/api';

  /// آخر طلب (لإدارة معدل الطلبات)
  static DateTime? _lastRequestTime;

  /// الحد الأدنى بين الطلبات (مللي ثانية)
  static const _minRequestInterval = 1500;

  /// جلب مباريات اللاعب من Lichess
  ///
  /// [username] — اسم المستخدم على Lichess
  /// [maxGames] — الحد الأقصى لعدد المباريات (الافتراضي: 20)
  /// [perfType] — نوع اللعبة (اختياري: bullet, blitz, rapid, classical)
  static Future<List<ChessMatch>> fetchGames({
    required String username,
    int maxGames = 20,
    String? perfType,
  }) async {
    await _rateLimit();

    final queryParams = {
      'max': maxGames.toString(),
      'pgnInJson': 'true',
      'opening': 'true',
      'moves': 'true',
      'tags': 'true',
      'clocks': 'true',
      'evals': 'false',
    };

    if (perfType != null) {
      queryParams['perfType'] = perfType;
    }

    final url = Uri.parse('$_baseUrl/games/user/$username').replace(
      queryParameters: queryParams,
    );

    try {
      final request = http.Request('GET', url);
      request.headers.addAll({
        'Accept': 'application/x-ndjson',
        'User-Agent': 'RuqaChessAnalyzer/1.0',
      });

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      if (streamedResponse.statusCode == 429) {
        throw const LichessImportException(
          'تم تجاوز حد الطلبات. يرجى الانتظار دقيقة ثم المحاولة.',
          statusCode: 429,
        );
      }

      if (streamedResponse.statusCode == 404) {
        throw LichessImportException(
          'اللاعب "$username" غير موجود على Lichess.',
          statusCode: 404,
        );
      }

      if (streamedResponse.statusCode != 200) {
        throw LichessImportException(
          'خطأ في الاتصال بـ Lichess.',
          statusCode: streamedResponse.statusCode,
        );
      }

      // تحليل NDJSON (سطر JSON لكل مباراة)
      final body = await streamedResponse.stream.bytesToString();
      final lines = body.split('\n').where((l) => l.trim().isNotEmpty);

      return lines
          .map((line) {
            try {
              return _parseGame(jsonDecode(line) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<ChessMatch>()
          .toList();
    } on LichessImportException {
      rethrow;
    } catch (e) {
      throw LichessImportException('فشل الاتصال: $e');
    }
  }

  /// تحليل مباراة واحدة من بيانات Lichess NDJSON
  static ChessMatch _parseGame(Map<String, dynamic> data) {
    final id = data['id'] as String? ?? 'unknown';
    final rated = data['rated'] as bool? ?? false;
    final variant = data['variant'] as String? ?? 'standard';
    final speed = data['speed'] as String? ?? '';
    final perf = data['perf'] as String? ?? '';
    final createdAt = data['createdAt'] as int?;
    final lastMoveAt = data['lastMoveAt'] as int?;
    final status = data['status'] as String? ?? '';

    // بيانات اللاعبين
    final players = data['players'] as Map<String, dynamic>? ?? {};
    final whiteData = players['white'] as Map<String, dynamic>? ?? {};
    final blackData = players['black'] as Map<String, dynamic>? ?? {};

    final whiteName = _extractPlayerName(whiteData);
    final blackName = _extractPlayerName(blackData);
    final whiteRating = whiteData['rating'] as int?;
    final blackRating = blackData['rating'] as int?;

    // النتيجة
    GameResult result = GameResult.incomplete;
    Termination? termination;

    final whiteWin = whiteData['isWinner'] as bool? ?? false;
    final blackWin = blackData['isWinner'] as bool? ?? false;

    if (whiteWin) {
      result = GameResult.whiteWins;
    } else if (blackWin) {
      result = GameResult.blackWins;
    } else if (status == 'draw' || status == 'stalemate' ||
               status == 'aborted') {
      result = status == 'aborted' ? GameResult.incomplete : GameResult.draw;
    }

    // طريقة الانتهاء
    switch (status) {
      case 'mate':
        termination = Termination.checkmate;
        break;
      case 'resign':
        termination = Termination.resignation;
        break;
      case 'timeout':
        termination = Termination.timeout;
        break;
      case 'stalemate':
        termination = Termination.stalemate;
        break;
      case 'draw':
        termination = Termination.agreement;
        break;
      case 'outoftime':
        termination = Termination.timeout;
        break;
      case 'abandoned':
        termination = Termination.abandoned;
        break;
    }

    // PGN الخام
    final pgn = data['pgn'] as String? ?? '';

    // الافتتاحية
    final openingData = data['opening'] as Map<String, dynamic>?;
    String? eco;
    String? openingName;
    if (openingData != null) {
      eco = openingData['eco'] as String?;
      openingName = openingData['name'] as String?;
    }

    // ضبط الوقت
    final clock = data['clock'] as Map<String, dynamic>?;
    int? tcInitial;
    int? tcIncrement;
    if (clock != null) {
      tcInitial = clock['initial'] as int?;
      tcIncrement = clock['increment'] as int?;
    }

    return ChessMatch(
      id: 'lichess_$id',
      whiteName: whiteName,
      blackName: blackName,
      whiteElo: whiteRating,
      blackElo: blackRating,
      result: result,
      termination: termination,
      date: createdAt != null
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
      event: _getEventName(speed, rated),
      site: 'https://lichess.org/$id',
      round: null,
      opening: eco != null
          ? OpeningData(
              nameAr: openingName ?? '',
              nameEn: openingName ?? '',
              eco: eco,
              moves: '',
              descriptionAr: '',
              category: '',
            )
          : null,
      timeControlInitial: tcInitial,
      timeControlIncrement: tcIncrement,
      rawPgn: pgn,
      moves: const [],
      evalPoints: const [],
    );
  }

  /// استخراج اسم اللاعب
  static String _extractPlayerName(Map<String, dynamic> playerData) {
    final userId = playerData['userId'] as String?;
    if (userId != null) return userId;

    final aiLevel = playerData['aiLevel'] as int?;
    if (aiLevel != null) return 'محرك مستوى $aiLevel';

    return 'مجهول';
  }

  /// اسم الحدث من السرعة
  static String _getEventName(String speed, bool rated) {
    final ratedStr = rated ? 'رسمي' : 'ودي';
    switch (speed) {
      case 'bullet':
        return 'رصاصي $ratedStr • Bullet';
      case 'blitz':
        return 'خاطف $ratedStr • Blitz';
      case 'rapid':
        return 'سريع $ratedStr • Rapid';
      case 'classical':
        return 'كلاسيكي $ratedStr • Classical';
      case 'correspondence':
        return 'مراسلة $ratedStr • Correspondence';
      default:
        return 'مباراة Lichess $ratedStr';
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
      final url = Uri.parse('$_baseUrl/user/$username');
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
