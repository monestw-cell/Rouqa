/// library_provider.dart
/// مزود حالة المكتبة — Library State Provider
///
/// إدارة تحميل المباريات من قاعدة البيانات، البحث، الحذف، والاستيراد.
/// تم تحسين معالجة الأخطاء مع:
/// - تصنيف أنواع الأخطاء (شبكة، قاعدة بيانات، تحقق)
/// - آلية إعادة المحاولة التلقائية
/// - رسائل خطأ واضحة ومفيدة للمستخدم
/// - التحقق من المدخلات قبل العمليات
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database_helper.dart';
import '../models/chess_models.dart';
import '../services/import_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// تصنيف الأخطاء — Error Classification
// ═══════════════════════════════════════════════════════════════════════════

/// نوع خطأ المكتبة
enum LibraryErrorType {
  /// خطأ في قاعدة البيانات (فشل SQL، تلف البيانات)
  database,

  /// خطأ في الشبكة (انقطاع الاتصال، مهلة الخادم)
  network,

  /// خطأ في التحقق من المدخلات (اسم مستخدم فارغ، PGN غير صالح)
  validation,

  /// خطأ في الاستيراد (فشل تحليل البيانات المستوردة)
  importParsing,

  /// خطأ غير معروف
  unknown,
}

/// نتيجة خطأ مفصّلة — Detailed error result
class LibraryError {
  /// نوع الخطأ
  final LibraryErrorType type;

  /// رسالة الخطأ التقنية (للمطورين)
  final String technicalMessage;

  /// رسالة الخطأ الموجّهة للمستخدم (باللغة العربية)
  final String userMessage;

  /// هل يمكن إعادة المحاولة؟
  final bool isRetryable;

  /// عدد محاولات إعادة المحاولة المتاحة
  final int retryCount;

  /// الاستثناء الأصلي (اختياري)
  final Exception? originalException;

  const LibraryError({
    required this.type,
    required this.technicalMessage,
    required this.userMessage,
    this.isRetryable = false,
    this.retryCount = 0,
    this.originalException,
  });

  /// تحويل الاستثناء إلى LibraryError مع رسالة مناسبة
  factory LibraryError.fromException(Object error, {String? context}) {
    final errorStr = error.toString().toLowerCase();

    // كشف نوع الخطأ من محتوى الرسالة
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('timeout') ||
        errorStr.contains('connection') ||
        errorStr.contains('host')) {
      return LibraryError(
        type: LibraryErrorType.network,
        technicalMessage: '$context: $error',
        userMessage: 'خطأ في الاتصال بالإنترنت. تأكد من اتصالك وحاول مرة أخرى.',
        isRetryable: true,
        originalException: error is Exception ? error : Exception(error.toString()),
      );
    }

    if (errorStr.contains('database') ||
        errorStr.contains('sql') ||
        errorStr.contains('sqflite') ||
        errorStr.contains('constraint')) {
      return LibraryError(
        type: LibraryErrorType.database,
        technicalMessage: '$context: $error',
        userMessage: 'حدث خطأ في قاعدة البيانات. يرجى إعادة تشغيل التطبيق.',
        isRetryable: true,
        originalException: error is Exception ? error : Exception(error.toString()),
      );
    }

    if (errorStr.contains('format') ||
        errorStr.contains('parse') ||
        errorStr.contains('invalid') ||
        errorStr.contains('pgn')) {
      return LibraryError(
        type: LibraryErrorType.importParsing,
        technicalMessage: '$context: $error',
        userMessage: 'صيغة البيانات غير صالحة. تأكد من صحة PGN أو اسم المستخدم.',
        isRetryable: false,
        originalException: error is Exception ? error : Exception(error.toString()),
      );
    }

    return LibraryError(
      type: LibraryErrorType.unknown,
      technicalMessage: '$context: $error',
      userMessage: 'حدث خطأ غير متوقع. حاول مرة أخرى لاحقاً.',
      isRetryable: false,
      originalException: error is Exception ? error : Exception(error.toString()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// حالة المكتبة — Library State
// ═══════════════════════════════════════════════════════════════════════════

/// حالة المكتبة
class LibraryState {
  /// قائمة المباريات
  final List<Map<String, dynamic>> matches;

  /// عدد المباريات
  final int totalCount;

  /// إحصائيات المباريات
  final Map<String, dynamic> stats;

  /// هل يتم التحميل؟
  final bool isLoading;

  /// نص البحث
  final String searchQuery;

  /// ترتيب العرض
  final String sortBy;

  /// رسالة الخطأ الموجّهة للمستخدم
  final String? errorMessage;

  /// تفاصيل الخطأ المفصّلة (للمطورين)
  final LibraryError? errorDetails;

  /// هل يتم الاستيراد؟
  final bool isImporting;

  /// تقدم الاستيراد
  final String importStatus;

  /// عدد مباريات تم استيرادها بنجاح
  final int importedCount;

  /// عدد مباريات فشل استيرادها
  final int failedCount;

  /// هل يمكن إعادة المحاولة للعملية الأخيرة؟
  final bool canRetry;

  const LibraryState({
    this.matches = const [],
    this.totalCount = 0,
    this.stats = const {},
    this.isLoading = false,
    this.searchQuery = '',
    this.sortBy = 'date_desc',
    this.errorMessage,
    this.errorDetails,
    this.isImporting = false,
    this.importStatus = '',
    this.importedCount = 0,
    this.failedCount = 0,
    this.canRetry = false,
  });

  LibraryState copyWith({
    List<Map<String, dynamic>>? matches,
    int? totalCount,
    Map<String, dynamic>? stats,
    bool? isLoading,
    String? searchQuery,
    String? sortBy,
    String? Function()? errorMessage,
    LibraryError? Function()? errorDetails,
    bool? isImporting,
    String? importStatus,
    int? importedCount,
    int? failedCount,
    bool? canRetry,
  }) {
    return LibraryState(
      matches: matches ?? this.matches,
      totalCount: totalCount ?? this.totalCount,
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      searchQuery: searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      errorDetails: errorDetails != null ? errorDetails() : this.errorDetails,
      isImporting: isImporting ?? this.isImporting,
      importStatus: importStatus ?? this.importStatus,
      importedCount: importedCount ?? this.importedCount,
      failedCount: failedCount ?? this.failedCount,
      canRetry: canRetry ?? this.canRetry,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مزود حالة المكتبة — Library Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// مزود حالة المكتبة
class LibraryNotifier extends StateNotifier<LibraryState> {
  static const _tag = 'LibraryNotifier';

  final DatabaseHelper _db = DatabaseHelper();

  /// الحد الأقصى لعدد محاولات إعادة المحاولة
  static const _maxRetries = 3;

  /// مدة الانتظار قبل إعادة المحاولة (مللي ثانية)
  static const _retryDelayMs = 2000;

  /// مؤقت إعادة المحاولة
  Timer? _retryTimer;

  /// العملية الأخيرة لإعادة المحاولة
  VoidCallback? _lastOperation;

  LibraryNotifier() : super(const LibraryState()) {
    loadGames();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  // ─── التحقق من المدخلات — Input Validation ──────────────────────────

  /// التحقق من اسم المستخدم
  ///
  /// يتحقق من أن اسم المستخدم ليس فارغاً ولا يحتوي على أحرف غير مسموحة.
  /// يعيد رسالة خطأ إذا كان غير صالح، أو null إذا كان صالحاً.
  String? _validateUsername(String username) {
    if (username.trim().isEmpty) {
      return 'يرجى إدخال اسم المستخدم';
    }
    if (username.trim().length < 2) {
      return 'اسم المستخدم قصير جداً';
    }
    if (username.trim().length > 50) {
      return 'اسم المستخدم طويل جداً';
    }
    // أسماء المستخدمين لا يجب أن تحتوي على مسافات
    if (username.trim().contains(' ')) {
      return 'اسم المستخدم لا يجب أن يحتوي على مسافات';
    }
    return null;
  }

  /// التحقق من نص PGN
  String? _validatePgn(String pgnText) {
    if (pgnText.trim().isEmpty) {
      return 'يرجى لصق PGN أو FEN';
    }
    if (pgnText.trim().length < 10) {
      return 'نص PGN قصير جداً. تأكد من لصق النص كاملاً.';
    }
    return null;
  }

  // ─── معالجة الأخطاء المركزية — Centralized Error Handling ────────────

  /// معالجة الخطأ مع تصنيفه وتحديث الحالة
  void _handleError(
    Object error, {
    required String context,
    VoidCallback? retryOperation,
  }) {
    final libraryError = LibraryError.fromException(error, context: context);

    debugPrint('$_tag: [${libraryError.type.name}] ${libraryError.technicalMessage}');

    state = state.copyWith(
      isLoading: () => false,
      isImporting: () => false,
      errorMessage: () => libraryError.userMessage,
      errorDetails: () => libraryError,
      canRetry: () => libraryError.isRetryable && retryOperation != null,
    );

    // تخزين العملية لإعادة المحاولة لاحقاً
    if (libraryError.isRetryable && retryOperation != null) {
      _lastOperation = retryOperation;
    }
  }

  /// إعادة المحاولة للعملية الأخيرة
  Future<void> retryLastOperation() async {
    if (_lastOperation == null) return;

    state = state.copyWith(
      errorMessage: () => null,
      errorDetails: () => null,
      canRetry: () => false,
    );

    _lastOperation!();
  }

  /// إعادة المحاولة التلقائية مع تراجع تصاعدي
  Future<void> _autoRetryWithBackoff(
    VoidCallback operation, {
    int attempt = 1,
  }) async {
    if (attempt > _maxRetries) return;

    final delayMs = _retryDelayMs * attempt;
    debugPrint('$_tag: إعادة محاولة تلقائية ($attempt/$_maxRetries) بعد ${delayMs}ms');

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: delayMs), operation);
  }

  // ─── عمليات قاعدة البيانات — Database Operations ────────────────────

  /// تحميل المباريات من قاعدة البيانات
  Future<void> loadGames() async {
    state = state.copyWith(
      isLoading: true,
      errorMessage: () => null,
      errorDetails: () => null,
    );

    try {
      final matches = await _db.getAllMatches(orderBy: _getOrderBy());
      final count = await _db.getMatchCount();
      final stats = await _db.getMatchStats();

      state = state.copyWith(
        matches: matches,
        totalCount: count,
        stats: stats,
        isLoading: false,
        canRetry: false,
      );
    } catch (e) {
      _handleError(
        e,
        context: 'loadGames',
        retryOperation: loadGames,
      );

      // محاولة إعادة تلقائية لعمليات قاعدة البيانات
      if (e.toString().toLowerCase().contains('database') ||
          e.toString().toLowerCase().contains('sqflite')) {
        _autoRetryWithBackoff(loadGames, attempt: 1);
      }
    }
  }

  /// البحث في المباريات
  Future<void> searchGames(String query) async {
    state = state.copyWith(searchQuery: query, isLoading: true);

    try {
      if (query.isEmpty) {
        await loadGames();
        return;
      }

      final matches = await _db.searchMatches(query);
      state = state.copyWith(
        matches: matches,
        isLoading: false,
      );
    } catch (e) {
      _handleError(
        e,
        context: 'searchGames',
        retryOperation: () => searchGames(query),
      );
    }
  }

  /// تغيير الترتيب
  Future<void> changeSortBy(String sortBy) async {
    state = state.copyWith(sortBy: sortBy);
    await loadGames();
  }

  /// حذف مباراة
  Future<void> deleteGame(int id) async {
    try {
      await _db.deleteMatch(id);
      await loadGames();
    } catch (e) {
      _handleError(
        e,
        context: 'deleteGame($id)',
        retryOperation: () => deleteGame(id),
      );
    }
  }

  /// حذف جميع المباريات
  Future<void> deleteAllGames() async {
    try {
      await _db.deleteAllMatches();
      await loadGames();
    } catch (e) {
      _handleError(
        e,
        context: 'deleteAllGames',
        retryOperation: deleteAllGames,
      );
    }
  }

  // ─── عمليات الاستيراد — Import Operations ───────────────────────────

  /// استيراد مباريات من Chess.com
  Future<void> importFromChessCom(String username) async {
    // التحقق من المدخلات
    final validationError = _validateUsername(username);
    if (validationError != null) {
      state = state.copyWith(
        errorMessage: () => validationError,
        errorDetails: () => const LibraryError(
          type: LibraryErrorType.validation,
          technicalMessage: 'Username validation failed',
          userMessage: '', // سيُستخدم validationError بدلاً منها
          isRetryable: false,
        ),
      );
      return;
    }

    state = state.copyWith(
      isImporting: true,
      importStatus: 'جاري الاستيراد من Chess.com...',
      errorMessage: () => null,
      errorDetails: () => null,
      importedCount: 0,
      failedCount: 0,
    );

    try {
      final result = await ImportService.importFromChessCom(username: username);

      // حفظ المباريات المستوردة في قاعدة البيانات مع تتبع النجاح والفشل
      int saved = 0;
      int failed = 0;
      final errors = <String>[];

      for (final match in result.matches) {
        try {
          await _db.insertMatch({
            'white_player': match.whiteName,
            'black_player': match.blackName,
            'result': match.result.notation,
            'date': match.date?.toIso8601String(),
            'pgn': match.rawPgn ?? '',
            'eco': match.opening?.eco,
            'opening': match.opening?.nameAr,
            'white_accuracy': match.whiteAccuracy,
            'black_accuracy': match.blackAccuracy,
            'time_control': match.timeControlInitial != null
                ? '${match.timeControlInitial}+${match.timeControlIncrement ?? 0}'
                : null,
            'source': 'chesscom',
          });
          saved++;
        } catch (e) {
          failed++;
          errors.add('فشل حفظ مباراة ${match.whiteName} vs ${match.blackName}: $e');
          if (errors.length <= 3) {
            debugPrint('$_tag: ${errors.last}');
          }
        }
      }

      final statusMsg = failed > 0
          ? 'تم استيراد $saved من ${result.matches.length} مباراة من Chess.com ($failed فشلت)'
          : 'تم استيراد $saved مباراة من Chess.com';

      state = state.copyWith(
        isImporting: false,
        importStatus: statusMsg,
        importedCount: saved,
        failedCount: failed,
      );

      await loadGames();
    } catch (e) {
      _handleError(
        e,
        context: 'importFromChessCom($username)',
        retryOperation: () => importFromChessCom(username),
      );
    }
  }

  /// استيراد مباريات من Lichess
  Future<void> importFromLichess(String username) async {
    // التحقق من المدخلات
    final validationError = _validateUsername(username);
    if (validationError != null) {
      state = state.copyWith(
        errorMessage: () => validationError,
        errorDetails: () => const LibraryError(
          type: LibraryErrorType.validation,
          technicalMessage: 'Username validation failed',
          userMessage: '',
          isRetryable: false,
        ),
      );
      return;
    }

    state = state.copyWith(
      isImporting: true,
      importStatus: 'جاري الاستيراد من Lichess...',
      errorMessage: () => null,
      errorDetails: () => null,
      importedCount: 0,
      failedCount: 0,
    );

    try {
      final result = await ImportService.importFromLichess(username: username);

      int saved = 0;
      int failed = 0;
      final errors = <String>[];

      for (final match in result.matches) {
        try {
          await _db.insertMatch({
            'white_player': match.whiteName,
            'black_player': match.blackName,
            'result': match.result.notation,
            'date': match.date?.toIso8601String(),
            'pgn': match.rawPgn ?? '',
            'eco': match.opening?.eco,
            'opening': match.opening?.nameAr,
            'white_accuracy': match.whiteAccuracy,
            'black_accuracy': match.blackAccuracy,
            'time_control': match.timeControlInitial != null
                ? '${match.timeControlInitial}+${match.timeControlIncrement ?? 0}'
                : null,
            'source': 'lichess',
          });
          saved++;
        } catch (e) {
          failed++;
          errors.add('فشل حفظ مباراة ${match.whiteName} vs ${match.blackName}: $e');
          if (errors.length <= 3) {
            debugPrint('$_tag: ${errors.last}');
          }
        }
      }

      final statusMsg = failed > 0
          ? 'تم استيراد $saved من ${result.matches.length} مباراة من Lichess ($failed فشلت)'
          : 'تم استيراد $saved مباراة من Lichess';

      state = state.copyWith(
        isImporting: false,
        importStatus: statusMsg,
        importedCount: saved,
        failedCount: failed,
      );

      await loadGames();
    } catch (e) {
      _handleError(
        e,
        context: 'importFromLichess($username)',
        retryOperation: () => importFromLichess(username),
      );
    }
  }

  /// استيراد من PGN
  Future<void> importFromPGN(String pgnText) async {
    // التحقق من المدخلات
    final validationError = _validatePgn(pgnText);
    if (validationError != null) {
      state = state.copyWith(
        errorMessage: () => validationError,
        errorDetails: () => const LibraryError(
          type: LibraryErrorType.validation,
          technicalMessage: 'PGN validation failed',
          userMessage: '',
          isRetryable: false,
        ),
      );
      return;
    }

    state = state.copyWith(
      isImporting: true,
      importStatus: 'جاري تحليل PGN...',
      errorMessage: () => null,
      errorDetails: () => null,
      importedCount: 0,
      failedCount: 0,
    );

    try {
      final result = ImportService.importPGN(pgnText);

      int saved = 0;
      int failed = 0;

      for (final match in result.matches) {
        try {
          await _db.insertMatch({
            'white_player': match.whiteName,
            'black_player': match.blackName,
            'result': match.result.notation,
            'date': match.date?.toIso8601String(),
            'pgn': match.rawPgn ?? '',
            'eco': match.opening?.eco,
            'opening': match.opening?.nameAr,
            'white_accuracy': match.whiteAccuracy,
            'black_accuracy': match.blackAccuracy,
            'source': 'pgn',
          });
          saved++;
        } catch (e) {
          failed++;
          debugPrint('$_tag: فشل حفظ مباراة PGN: $e');
        }
      }

      final statusMsg = failed > 0
          ? 'تم استيراد $saved من ${result.matches.length} مباراة من PGN ($failed فشلت)'
          : 'تم استيراد $saved مباراة من PGN';

      state = state.copyWith(
        isImporting: false,
        importStatus: statusMsg,
        importedCount: saved,
        failedCount: failed,
      );

      await loadGames();
    } catch (e) {
      _handleError(
        e,
        context: 'importFromPGN',
        retryOperation: () => importFromPGN(pgnText),
      );
    }
  }

  /// تحويل اسم الترتيب إلى عبارة SQL
  String _getOrderBy() {
    return switch (state.sortBy) {
      'date_asc' => 'created_at ASC',
      'accuracy_desc' => 'white_accuracy DESC, black_accuracy DESC',
      'accuracy_asc' => 'white_accuracy ASC, black_accuracy ASC',
      'result' => 'result ASC',
      'date_desc' => 'created_at DESC',
      _ => 'created_at DESC',
    };
  }
}

/// مزود Riverpod لحالة المكتبة
final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>(
  (ref) => LibraryNotifier(),
);
