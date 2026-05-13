/// throttled_analysis_update.dart
/// تحديثات التحليل المحدودة بالسرعة (إصلاح #7 + #18)
///
/// يحل مشكلتين:
/// #7: MultiPV الثقيلة - لا تحدث كل frame
/// #18: Best Move Flickering - لا تحدث الأسهم إلا عند استقرار العمق
///
/// كيف يحلها ChessIs:
/// #7: Throttle updates: if (now-lastUpdate < 120ms) return;
/// #18: Debounced updates - لا تحدث arrows/best move إلا إذا depth stable

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../engine/uci_protocol.dart';

/// بيانات التحليل المحدودة — Throttled Analysis Data
class ThrottledAnalysisData {
  /// أحدث معلومات لكل PV
  final Map<int, InfoResponse> infoByPv;

  /// أفضل حركة حالية
  final BestMoveResponse? bestMove;

  /// العمق الحالي
  final int currentDepth;

  /// هل العمق مستقر؟ (لم يتغير منذ فترة)
  final bool isDepthStable;

  /// وقت آخر تحديث
  final DateTime lastUpdateTime;

  const ThrottledAnalysisData({
    this.infoByPv = const {},
    this.bestMove,
    this.currentDepth = 0,
    this.isDepthStable = false,
    this.lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(0),
  });

  ThrottledAnalysisData copyWith({
    Map<int, InfoResponse>? infoByPv,
    BestMoveResponse? bestMove,
    int? currentDepth,
    bool? isDepthStable,
    DateTime? lastUpdateTime,
  }) {
    return ThrottledAnalysisData(
      infoByPv: infoByPv ?? this.infoByPv,
      bestMove: bestMove ?? this.bestMove,
      currentDepth: currentDepth ?? this.currentDepth,
      isDepthStable: isDepthStable ?? this.isDepthStable,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
    );
  }
}

/// تحديثات التحليل المحدودة بالسرعة — Throttled Analysis Update
///
/// يقوم بـ:
/// 1. تقييد تكرار تحديثات التحليل (Throttle) — لا يُحدّث أكثر من مرة كل 120ms
/// 2. تأخير تحديث الأسهم حتى يستقر العمق (Debounce) — لا يُحدّث الأسهم
///    إلا إذا بقي العمق ثابتاً لمدة 300ms
/// 3. تحديث التقييم والعمق فوراً (بدون تأخير)
///
/// الاستخدام:
/// ```dart
/// final throttler = ThrottledAnalysisUpdate(
///   throttleInterval: const Duration(milliseconds: 120),
///   depthStabilityDelay: const Duration(milliseconds: 300),
/// );
///
/// throttler.onUpdate = (data) {
///   // تحديث UI هنا
///   setState(() {
///     _analysisData = data;
///   });
/// };
///
/// // عند تلقي تحديث من المحرك:
/// throttler.pushInfo(info);
/// throttler.pushBestMove(bestMove);
///
/// // عند الانتهاء:
/// throttler.dispose();
/// ```
class ThrottledAnalysisUpdate {
  static const _tag = 'ThrottledAnalysisUpdate';

  /// الفترة الزمنية بين التحديثات (Throttle)
  final Duration throttleInterval;

  /// التأخير قبل اعتبار العمق مستقراً (Debounce)
  final Duration depthStabilityDelay;

  /// آخر بيانات مُرسلة
  ThrottledAnalysisData _lastEmitted = const ThrottledAnalysisData();

  /// آخر بيانات مستلمة (قبل التقييد)
  Map<int, InfoResponse> _latestInfoByPv = {};
  BestMoveResponse? _latestBestMove;
  int _latestDepth = 0;
  int _lastStableDepth = -1;

  /// Timer للتحديث المحدود
  Timer? _throttleTimer;

  /// Timer لاستقرار العمق
  Timer? _depthStabilityTimer;

  /// وقت آخر تحديث مُرسل
  DateTime _lastEmitTime = DateTime.now();

  /// هل يوجد تحديث معلّق؟
  bool _hasPendingUpdate = false;

  // Callbacks

  /// يُستدعى عند وجود تحديث جاهز للعرض
  void Function(ThrottledAnalysisData data)? onUpdate;

  /// يُستدعى عندما يصبح العمق مستقراً (لتحديث الأسهم)
  void Function(ThrottledAnalysisData data)? onDepthStable;

  ThrottledAnalysisUpdate({
    this.throttleInterval = const Duration(milliseconds: 120),
    this.depthStabilityDelay = const Duration(milliseconds: 300),
  });

  // ========================================================================
  // دفع البيانات
  // ========================================================================

  /// دفع تحليل info جديد
  void pushInfo(InfoResponse info) {
    if ((info.multiPv ?? 0) > 0) {
      _latestInfoByPv[(info.multiPv ?? 0)] = info;
    }

    if (info.depth != null && info.depth! > _latestDepth) {
      _latestDepth = info.depth!;

      // إعادة تشغيل Timer استقرار العمق
      _depthStabilityTimer?.cancel();
      _depthStabilityTimer = Timer(depthStabilityDelay, _onDepthStable);
    }

    _scheduleThrottledUpdate();
  }

  /// دفع أفضل حركة جديدة
  void pushBestMove(BestMoveResponse bestMove) {
    _latestBestMove = bestMove;
    _scheduleThrottledUpdate();
  }

  /// مسح البيانات (عند بدء تحليل جديد)
  void clear() {
    _latestInfoByPv.clear();
    _latestBestMove = null;
    _latestDepth = 0;
    _lastStableDepth = -1;
    _hasPendingUpdate = false;
    _throttleTimer?.cancel();
    _depthStabilityTimer?.cancel();
  }

  // ========================================================================
  // التقييد (Throttle)
  // ========================================================================

  /// جدولة تحديث مقيد
  void _scheduleThrottledUpdate() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastEmitTime);

    if (elapsed >= throttleInterval) {
      // يمكن التحديث فوراً
      _emitUpdate();
    } else if (!_hasPendingUpdate) {
      // جدولة تحديث لاحق
      _hasPendingUpdate = true;
      _throttleTimer?.cancel();
      _throttleTimer = Timer(
        throttleInterval - elapsed,
        () {
          _hasPendingUpdate = false;
          _emitUpdate();
        },
      );
    }
  }

  /// إرسال التحديث
  void _emitUpdate() {
    _lastEmitTime = DateTime.now();

    final data = ThrottledAnalysisData(
      infoByPv: Map.unmodifiable(_latestInfoByPv),
      bestMove: _latestBestMove,
      currentDepth: _latestDepth,
      isDepthStable: _latestDepth == _lastStableDepth && _lastStableDepth > 0,
      lastUpdateTime: _lastEmitTime,
    );

    _lastEmitted = data;
    onUpdate?.call(data);
  }

  // ========================================================================
  // استقرار العمق (Debounce)
  // ========================================================================

  /// معالجة استقرار العمق
  void _onDepthStable() {
    if (_latestDepth == _lastStableDepth) return;
    _lastStableDepth = _latestDepth;

    final data = ThrottledAnalysisData(
      infoByPv: Map.unmodifiable(_latestInfoByPv),
      bestMove: _latestBestMove,
      currentDepth: _latestDepth,
      isDepthStable: true,
      lastUpdateTime: DateTime.now(),
    );

    onDepthStable?.call(data);
  }

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  /// تحرير الموارد
  void dispose() {
    _throttleTimer?.cancel();
    _depthStabilityTimer?.cancel();
    _latestInfoByPv.clear();
    onUpdate = null;
    onDepthStable = null;
  }
}
