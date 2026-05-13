/// analysis_session_manager.dart
/// مدير جلسات التحليل لحل مشكلة Race Conditions (حل مشكلة #4)
///
/// يحل مشكلة Race Conditions بين:
/// - move navigation
/// - engine analysis
/// - autoplay
/// - training mode
/// - chart selection
///
/// قد يظهر:
/// - stale evaluation
/// - wrong arrows
///
/// الحل:
/// - analysis session id
/// - كل تحليل له token
/// - أي response قديم يُرمى

import 'dart:async';

import 'package:flutter/foundation.dart';

// ============================================================================
/// رمز جلسة التحليل — Analysis Session Token
///
/// كل عملية تحليل تحصل على token فريد.
/// أي استجابة من المحرك تحمل token قديم تُرفض.
class AnalysisSessionToken {
  /// المعرف الفريد
  final String id;

  /// وقت الإنشاء
  final DateTime createdAt;

  /// وصف الجلسة (للتصحيح)
  final String description;

  /// هل الجلسة ملغاة؟
  bool _isCancelled = false;

  AnalysisSessionToken({
    required this.id,
    required this.createdAt,
    this.description = '',
  });

  /// هل الجلسة ملغاة؟
  bool get isCancelled => _isCancelled;

  /// إلغاء الجلسة
  void cancel() => _isCancelled = true;

  @override
  String toString() => 'Session($id${description.isNotEmpty ? ': $description' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AnalysisSessionToken && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// ============================================================================
/// نتيجة جلسة التحليل — Analysis Session Result
class AnalysisSessionResult<T> {
  /// رمز الجلسة
  final AnalysisSessionToken token;

  /// النتيجة (null إذا أُلغيت)
  final T? data;

  /// هل الجلسة أُلغيت؟
  final bool wasCancelled;

  /// هل الجلسة انتهت بنجاح؟
  final bool wasSuccessful;

  /// رسالة خطأ (إن وُجدت)
  final String? errorMessage;

  const AnalysisSessionResult({
    required this.token,
    this.data,
    this.wasCancelled = false,
    this.wasSuccessful = false,
    this.errorMessage,
  });

  /// إنشاء نتيجة ناجحة
  factory AnalysisSessionResult.success(AnalysisSessionToken token, T data) {
    return AnalysisSessionResult(
      token: token,
      data: data,
      wasSuccessful: true,
    );
  }

  /// إنشاء نتيجة ملغاة
  factory AnalysisSessionResult.cancelled(AnalysisSessionToken token) {
    return AnalysisSessionResult(
      token: token,
      wasCancelled: true,
    );
  }

  /// إنشاء نتيجة خاطئة
  factory AnalysisSessionResult.error(AnalysisSessionToken token, String error) {
    return AnalysisSessionResult(
      token: token,
      errorMessage: error,
    );
  }
}

// ============================================================================
/// مدير جلسات التحليل — Analysis Session Manager
///
/// يدير جلسات التحليل ويضمن عدم حدوث race conditions:
/// - كل عملية تحليل تحصل على session token فريد
/// - عند بدء تحليل جديد، يُلغى التحليل القديم
/// - أي استجابة من تحليل قديم تُرفض
/// - يوفر إحصائيات عن الجلسات
///
/// الاستخدام:
/// ```dart
/// final sessionManager = AnalysisSessionManager();
///
/// // بدء تحليل جديد
/// final token = sessionManager.startSession('analyze_fen_abc123');
///
/// // في callback المحرك:
/// if (sessionManager.isCurrentSession(token)) {
///   // معالجة التحديث
/// } else {
///   // تجاهل — تحديث قديم
/// }
///
/// // بدء تحليل جديد (يُلغى القديم تلقائياً)
/// final newToken = sessionManager.startSession('navigate_move_5');
///
/// sessionManager.dispose();
/// ```
class AnalysisSessionManager {
  static const _tag = 'AnalysisSessionManager';

  /// الجلسة الحالية
  AnalysisSessionToken? _currentToken;

  /// عداد الجلسات (لإنشاء معرفات فريدة)
  int _sessionCounter = 0;

  /// الجلسات النشطة (للتتبع)
  final Map<String, AnalysisSessionToken> _activeSessions = {};

  /// إحصائيات
  int _totalSessions = 0;
  int _cancelledSessions = 0;
  int _completedSessions = 0;

  // Callbacks

  /// يُستدعى عند إلغاء جلسة (من قبل جلسة أحدث)
  void Function(AnalysisSessionToken cancelledToken, AnalysisSessionToken newToken)?
      onSessionCancelled;

  /// يُستدعى عند بدء جلسة جديدة
  void Function(AnalysisSessionToken token)? onSessionStarted;

  // Getters

  /// الجلسة الحالية
  AnalysisSessionToken? get currentToken => _currentToken;

  /// هل توجد جلسة نشطة؟
  bool get hasActiveSession => _currentToken != null && !_currentToken!.isCancelled;

  // ========================================================================
  // إدارة الجلسات
  // ========================================================================

  /// بدء جلسة تحليل جديدة — Start a new analysis session
  ///
  /// يُلغى أي جلسة سابقة تلقائياً.
  /// يُرجع رمز الجلسة الجديدة.
  AnalysisSessionToken startSession([String description = '']) {
    _sessionCounter++;
    _totalSessions++;

    // إلغاء الجلسة السابقة
    if (_currentToken != null && !_currentToken!.isCancelled) {
      _currentToken!.cancel();
      _cancelledSessions++;

      debugPrint('$_tag: إلغاء الجلسة $_currentToken');

      onSessionCancelled?.call(_currentToken!, AnalysisSessionToken(
        id: '$_sessionCounter',
        createdAt: DateTime.now(),
        description: description,
      ));
    }

    // إنشاء جلسة جديدة
    final newToken = AnalysisSessionToken(
      id: '$_sessionCounter',
      createdAt: DateTime.now(),
      description: description,
    );

    _currentToken = newToken;
    _activeSessions[newToken.id] = newToken;

    debugPrint('$_tag: بدء جلسة جديدة $newToken');
    onSessionStarted?.call(newToken);

    return newToken;
  }

  /// هل الرمز يمثل الجلسة الحالية؟
  bool isCurrentSession(AnalysisSessionToken token) {
    if (_currentToken == null) return false;
    if (token.isCancelled) return false;
    return token.id == _currentToken!.id && !_currentToken!.isCancelled;
  }

  /// هل الرمز صالح (ليس ملغى)؟
  bool isValidToken(AnalysisSessionToken token) {
    return !token.isCancelled;
  }

  /// إنهاء الجلسة الحالية بنجاح
  void completeCurrentSession() {
    if (_currentToken != null) {
      _completedSessions++;
      _activeSessions.remove(_currentToken!.id);
      debugPrint('$_tag: إكمال الجلسة $_currentToken');
      _currentToken = null;
    }
  }

  /// إلغاء الجلسة الحالية
  void cancelCurrentSession() {
    if (_currentToken != null && !_currentToken!.isCancelled) {
      _currentToken!.cancel();
      _cancelledSessions++;
      debugPrint('$_tag: إلغاء الجلسة $_currentToken');
    }
  }

  // ========================================================================
  // تنفيذ آمن — Safe Execution
  // ========================================================================

  /// تنفيذ عملية مع جلسة آمنة
  ///
  /// يبدأ جلسة جديدة وينفذ العملية.
  /// إذا بدأت جلسة أخرى أثناء التنفيذ، تُلغى النتيجة.
  Future<T?> executeWithSession<T>(
    String description,
    Future<T> Function(AnalysisSessionToken token) operation,
  ) async {
    final token = startSession(description);

    try {
      final result = await operation(token);

      // التحقق من أن الجلسة لا تزال الحالية
      if (isCurrentSession(token)) {
        completeCurrentSession();
        return result;
      } else {
        debugPrint('$_tag: تجاهل نتيجة جلسة ملغاة $token');
        return null;
      }
    } catch (e) {
      if (isCurrentSession(token)) {
        debugPrint('$_tag: خطأ في الجلسة $token: $e');
      }
      return null;
    }
  }

  // ========================================================================
  // إحصائيات
  // ========================================================================

  Map<String, dynamic> get stats => {
    'totalSessions': _totalSessions,
    'cancelledSessions': _cancelledSessions,
    'completedSessions': _completedSessions,
    'activeSessions': _activeSessions.length,
    'currentSessionId': _currentToken?.id,
  };

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    // إلغاء جميع الجلسات النشطة
    for (final token in _activeSessions.values) {
      token.cancel();
    }
    _activeSessions.clear();
    _currentToken = null;
    onSessionCancelled = null;
    onSessionStarted = null;
  }
}
