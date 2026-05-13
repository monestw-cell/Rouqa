/// background_analysis_service.dart
/// خدمة التحليل في الخلفية — Background Analysis Service
///
/// تتكامل مع AnalysisForegroundService.kt (Android) عبر MethodChannel
/// لضمان استمرارية التحليل في الخلفية.
///
/// الميزات:
/// - بدء/إيقاف الخدمة الأمامية (Foreground Service)
/// - تحديث تقدم التحليل في الإشعار
/// - إدارة WakeLock لمنع النوم
/// - التحقق من أذونات الإشعارات (Android 13+)
/// - طلب إعفاء من تحسين البطارية

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
/// حالة خدمة الخلفية — Background Service State
enum BackgroundServiceState {
  /// الخدمة متوقفة
  stopped,

  /// الخدمة تعمل
  running,

  /// الخدمة متوقفة مؤقتاً
  paused,

  /// خطأ في الخدمة
  error,
}

// ============================================================================
/// خدمة التحليل في الخلفية — Background Analysis Service
///
/// تتواصل مع AnalysisForegroundService.kt عبر MethodChannel.
/// تبدأ خدمة أمامية (Foreground Service) عند بدء التحليل
/// وتُحدث الإشعار بالتقدم، ثم تُوقف الخدمة عند الانتهاء.
///
/// الاستخدام:
/// ```dart
/// final service = BackgroundAnalysisService();
///
/// // بدء الخدمة عند بدء التحليل
/// await service.startAnalysis();
///
/// // تحديث التقدم
/// await service.updateProgress(
///   current: 5,
///   total: 20,
///   currentMove: 'Nf3',
/// );
///
/// // إيقاف الخدمة عند الانتهاء
/// await service.stopAnalysis();
///
/// service.dispose();
/// ```
class BackgroundAnalysisService {
  static const _tag = 'BackgroundAnalysisService';

  /// قناة التواصل مع الخدمة الأمامية — Must match AnalysisForegroundService.kt
  static const _channel = MethodChannel('com.ruqa.chessanalyzer/background_analysis');

  /// حالة الخدمة الحالية
  BackgroundServiceState _state = BackgroundServiceState.stopped;

  /// هل المنصة مدعومة؟
  bool _isPlatformSupported = false;

  /// اشتراك في تغييرات حالة التطبيق
  StreamSubscription? _appStateSubscription;

  // Callbacks

  /// يُستدعى عند تغير حالة الخدمة
  void Function(BackgroundServiceState state)? onStateChanged;

  BackgroundAnalysisService() {
    _checkPlatform();
  }

  // ========================================================================
  // كشف المنصة
  // ========================================================================

  void _checkPlatform() {
    try {
      _isPlatformSupported = !kIsWeb && Platform.isAndroid;
    } catch (_) {
      _isPlatformSupported = false;
    }
  }

  /// هل المنصة مدعومة؟
  bool get isPlatformSupported => _isPlatformSupported;

  /// حالة الخدمة الحالية
  BackgroundServiceState get state => _state;

  /// هل الخدمة تعمل؟
  bool get isRunning => _state == BackgroundServiceState.running;

  // ========================================================================
  // بدء وإيقاف الخدمة
  // ========================================================================

  /// بدء خدمة التحليل في الخلفية — Start background analysis service
  ///
  /// تبدأ خدمة أمامية (Foreground Service) مع إشعار يُظهر تقدم التحليل.
  /// تتطلب إذن POST_NOTIFICATIONS على Android 13+.
  ///
  /// تعيد true إذا نجح البدء، وfalse إذا فشل.
  Future<bool> startAnalysis() async {
    if (!_isPlatformSupported) {
      debugPrint('$_tag: المنصة غير مدعومة');
      return false;
    }

    if (_state == BackgroundServiceState.running) {
      debugPrint('$_tag: الخدمة تعمل بالفعل');
      return true;
    }

    try {
      await _channel.invokeMethod<void>('startAnalysis');
      _state = BackgroundServiceState.running;
      onStateChanged?.call(_state);
      debugPrint('$_tag: بدأت خدمة التحليل في الخلفية');
      return true;
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في بدء الخدمة: ${e.message}');
      _state = BackgroundServiceState.error;
      onStateChanged?.call(_state);

      // محاولة طلب إذن الإشعارات إذا كان الخطأ متعلقًا بالأذونات
      if (e.code == 'PERMISSION_DENIED') {
        debugPrint('$_tag: إذن الإشعارات مرفوض — يجب طلبه');
      }
      return false;
    } catch (e) {
      debugPrint('$_tag: خطأ غير متوقع: $e');
      _state = BackgroundServiceState.error;
      onStateChanged?.call(_state);
      return false;
    }
  }

  /// إيقاف خدمة التحليل في الخلفية — Stop background analysis service
  Future<void> stopAnalysis() async {
    if (!_isPlatformSupported || _state == BackgroundServiceState.stopped) return;

    try {
      await _channel.invokeMethod<void>('stopAnalysis');
      debugPrint('$_tag: أوقفت خدمة التحليل في الخلفية');
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في إيقاف الخدمة: ${e.message}');
    } catch (e) {
      debugPrint('$_tag: خطأ غير متوقع: $e');
    } finally {
      _state = BackgroundServiceState.stopped;
      onStateChanged?.call(_state);
    }
  }

  // ========================================================================
  // تحديث التقدم
  // ========================================================================

  /// تحديث تقدم التحليل في الإشعار — Update notification progress
  ///
  /// [current] — الحركة الحالية (مثل: 5)
  /// [total] — إجمالي الحركات (مثل: 20)
  /// [currentMove] — نص الحركة الحالية (مثل: "Nf3")
  Future<void> updateProgress({
    required int current,
    required int total,
    String currentMove = '',
  }) async {
    if (!_isPlatformSupported || _state != BackgroundServiceState.running) return;

    try {
      await _channel.invokeMethod<void>('updateProgress', {
        'progress': current,
        'currentMove': currentMove,
        'totalMoves': total,
      });
    } on PlatformException catch (e) {
      debugPrint('$_tag: خطأ في تحديث التقدم: ${e.message}');
    } catch (e) {
      // تجاهل الأخطاء في تحديث التقدم — ليست حرجة
    }
  }

  // ========================================================================
  // أذونات الإشعارات (Android 13+)
  // ========================================================================

  /// التحقق من إذن الإشعارات — Check notification permission
  ///
  /// على Android 13+ (API 33)، يجب طلب إذن POST_NOTIFICATIONS
  /// قبل إظهار إشعارات الخدمة الأمامية.
  Future<bool> checkNotificationPermission() async {
    if (!_isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('checkNotificationPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('$_tag: خطأ في التحقق من إذن الإشعارات: $e');
      return false;
    }
  }

  /// طلب إذن الإشعارات — Request notification permission
  Future<bool> requestNotificationPermission() async {
    if (!_isPlatformSupported) return false;

    try {
      final result = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('$_tag: خطأ في طلب إذن الإشعارات: $e');
      return false;
    }
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  /// تحرير الموارد — Dispose resources
  ///
  /// يُوقف الخدمة إذا كانت تعمل ويُلغي الاشتراكات.
  Future<void> dispose() async {
    await stopAnalysis();
    _appStateSubscription?.cancel();
    _appStateSubscription = null;
    onStateChanged = null;
  }
}
