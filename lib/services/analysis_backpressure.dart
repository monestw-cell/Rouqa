/// analysis_backpressure.dart
/// نظام ضغط التحليل الخلفي (حل مشكلة #3)
///
/// يحل مشكلة تشبع المحرك (Engine Saturation) عندما:
/// - depth 18
/// - multipv 5
/// - autoplay سريع
///
/// قد يصبح:
/// - stdout flooding
/// - parser overload
///
/// حتى مع throttling.
///
/// الحل:
/// - analysis backpressure system
/// - إذا queue ممتلئة: تسقط updates قديمة، تحتفظ بالأحدث فقط
/// - تحكم في تدفق البيانات من المحرك

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../engine/uci_protocol.dart';

// ============================================================================
// أولوية التحديث — Update Priority
// ============================================================================

enum UpdatePriority {
  /// تحديث حرج (bestMove) — لا يُسقط أبداً
  critical,

  /// تحديث عالي (depth change, eval significant change)
  high,

  /// تحديث عادي (info update at same depth)
  normal,

  /// تحديث منخفض (minor info update)
  low,
}

// ============================================================================
// عنصر قائمة الانتظار — Queue Item
// ============================================================================

class _BackpressureItem {
  final InfoResponse info;
  final UpdatePriority priority;
  final DateTime timestamp;
  final int sequenceNumber;

  const _BackpressureItem({
    required this.info,
    required this.priority,
    required this.timestamp,
    required this.sequenceNumber,
  });
}

// ============================================================================
// نتيجة الضغط الخلفي — Backpressure Result
// ============================================================================

class BackpressureStats {
  final int totalReceived;
  final int totalDropped;
  final int totalEmitted;
  final int queueSize;
  final double dropRate;

  const BackpressureStats({
    this.totalReceived = 0,
    this.totalDropped = 0,
    this.totalEmitted = 0,
    this.queueSize = 0,
    this.dropRate = 0.0,
  });
}

// ============================================================================
/// نظام ضغط التحليل الخلفي — Analysis Backpressure System
///
/// يتحكم في تدفق بيانات التحليل من المحرك:
/// 1. يستقبل تحديثات info من المحرك
/// 2. يحدد أولوية كل تحديث
/// 3. يُخزن في قائمة انتظار محدودة الحجم
/// 4. يُسقط التحديثات القديمة عند امتلاء القائمة
/// 5. يُصدر التحديثات بسرعة مناسبة للـ UI
///
/// الاستخدام:
/// ```dart
/// final backpressure = AnalysisBackpressure(
///   maxQueueSize: 20,
///   emitInterval: Duration(milliseconds: 100),
/// );
///
/// backpressure.onEmit = (info) {
///   // تحديث UI
/// };
///
/// // عند تلقي تحديث من المحرك
/// backpressure.push(info);
///
/// backpressure.dispose();
/// ```
class AnalysisBackpressure {
  static const _tag = 'AnalysisBackpressure';

  /// الحد الأقصى لحجم قائمة الانتظار
  final int maxQueueSize;

  /// الفترة بين إصدار التحديثات
  final Duration emitInterval;

  /// الحد الأدنى لتغير التقييم لاعتباره تحديثاً عالياً
  final int significantEvalChangeCp;

  /// قائمة الانتظار
  final Queue<_BackpressureItem> _queue = DoubleLinkedQueue();

  /// آخر info صادر لكل PV
  final Map<int, InfoResponse> _lastEmittedByPv = {};

  /// Timer للإصدار
  Timer? _emitTimer;

  /// رقم تسلسلي
  int _sequenceNumber = 0;

  /// إحصائيات
  int _totalReceived = 0;
  int _totalDropped = 0;
  int _totalEmitted = 0;

  /// آخر تقييم صادر (PV 1)
  int? _lastEmittedEvalCp;

  /// آخر عمق صادر (PV 1)
  int? _lastEmittedDepth;

  // Callbacks

  /// يُستدعى عند إصدار تحديث
  void Function(InfoResponse info)? onEmit;

  /// يُستدعى عند إسقاط تحديث
  void Function(int droppedCount)? onDropped;

  AnalysisBackpressure({
    this.maxQueueSize = 20,
    this.emitInterval = const Duration(milliseconds: 100),
    this.significantEvalChangeCp = 15,
  });

  // ========================================================================
  // دفع البيانات
  // ========================================================================

  /// دفع تحديث info جديد
  void push(InfoResponse info) {
    _totalReceived++;
    _sequenceNumber++;

    final priority = _calculatePriority(info);
    final item = _BackpressureItem(
      info: info,
      priority: priority,
      timestamp: DateTime.now(),
      sequenceNumber: _sequenceNumber,
    );

    // إذا القائمة ممتلئة، نُسقط العنصر الأقل أولوية
    if (_queue.length >= maxQueueSize) {
      _dropLowestPriority((info.multiPv ?? 0));
    }

    // إذا العنصر حرج (bestMove أو PV 1 بعمق جديد)
    // نُزيل أي عناصر قديمة من نفس PV
    if (priority == UpdatePriority.critical || priority == UpdatePriority.high) {
      _removeOlderFromSamePv((info.multiPv ?? 0));
    }

    _queue.addLast(item);

    // بدء الإصدار إذا لم يكن بدأ
    _startEmitTimer();
  }

  /// حساب أولوية التحديث
  UpdatePriority _calculatePriority(InfoResponse info) {
    // PV 1 بعمق جديد — عالي
    if ((info.multiPv ?? 0) <= 1) {
      if (info.depth != null && info.depth != _lastEmittedDepth) {
        return UpdatePriority.high;
      }

      // تغير تقييم كبير
      if (info.score != null && _lastEmittedEvalCp != null) {
        final currentEval = info.score!.value;
        final evalDiff = (currentEval - _lastEmittedEvalCp!).abs();
        if (evalDiff > significantEvalChangeCp) {
          return UpdatePriority.high;
        }
      }

      return UpdatePriority.normal;
    }

    // PV أعلى — أولوية أقل
    if ((info.multiPv ?? 0) <= 2) {
      return UpdatePriority.normal;
    }

    return UpdatePriority.low;
  }

  /// إسقاط العنصر الأقل أولوية من PV محدد
  void _dropLowestPriority(int excludePv) {
    _BackpressureItem? lowestItem;
    int? lowestSeq;

    for (final item in _queue) {
      // لا نُسقط عناصر من PV 1 حرجة
      if (item.info.multiPv == 1 && item.priority == UpdatePriority.high) {
        continue;
      }

      if (lowestSeq == null || (item.sequenceNumber ?? 0) < (lowestSeq ?? 0)) {
        // نُسقط الأقدم (أقل تسلسل) من الأولوية الأقل
        if (lowestItem == null ||
            item.priority.index > lowestItem.priority.index ||
            (item.priority == lowestItem.priority && (item.sequenceNumber ?? 0) < (lowestSeq ?? 0)) {
          lowestItem = item;
          lowestSeq = item.sequenceNumber;
        }
      }
    }

    if (lowestItem != null) {
      _queue.remove(lowestItem);
      _totalDropped++;
      onDropped?.call(1);
    }
  }

  /// إزالة العناصر القديمة من نفس PV
  void _removeOlderFromSamePv(int pvNumber) {
    final toRemove = <_BackpressureItem>[];
    bool foundNewer = false;

    for (final item in _queue) {
      if (item.info.multiPv == pvNumber) {
        if (!foundNewer) {
          foundNewer = true;
          // نحتفظ بالأحدث
        } else {
          toRemove.add(item);
        }
      }
    }

    for (final item in toRemove) {
      _queue.remove(item);
      _totalDropped++;
    }

    if (toRemove.isNotEmpty) {
      onDropped?.call(toRemove.length);
    }
  }

  // ========================================================================
  // إصدار التحديثات
  // ========================================================================

  /// بدء Timer الإصدار
  void _startEmitTimer() {
    _emitTimer ??= Timer.periodic(emitInterval, (_) => _emitNext());
  }

  /// إصدار التحديث التالي
  void _emitNext() {
    if (_queue.isEmpty) {
      _emitTimer?.cancel();
      _emitTimer = null;
      return;
    }

    // أخذ العنصر ذو الأولوية الأعلى
    _BackpressureItem? bestItem;
    int? bestSeq;

    for (final item in _queue) {
      if (bestItem == null ||
          item.priority.index < bestItem.priority.index ||
          (item.priority == bestItem.priority && item.sequenceNumber > (bestSeq ?? 0))) {
        bestItem = item;
        bestSeq = item.sequenceNumber;
      }
    }

    if (bestItem != null) {
      _queue.remove(bestItem);
      _totalEmitted++;

      // تحديث آخر info صادر
      _lastEmittedByPv[bestItem.info.multiPv ?? 0] = bestItem.info;

      if ((bestItem.info.multiPv ?? 0) == 1) {
        if (bestItem.info.score != null) {
          _lastEmittedEvalCp = bestItem.info.score!.value;
        }
        if (bestItem.info.depth != null) {
          _lastEmittedDepth = bestItem.info.depth;
        }
      }

      onEmit?.call(bestItem.info);
    }
  }

  // ========================================================================
  // مسح وإعادة تعيين
  // ========================================================================

  /// مسح القائمة
  void clear() {
    _queue.clear();
    _lastEmittedByPv.clear();
    _lastEmittedEvalCp = null;
    _lastEmittedDepth = null;
  }

  /// إعادة تعيين الإحصائيات
  void resetStats() {
    _totalReceived = 0;
    _totalDropped = 0;
    _totalEmitted = 0;
  }

  // ========================================================================
  // إحصائيات
  // ========================================================================

  BackpressureStats get stats => BackpressureStats(
    totalReceived: _totalReceived,
    totalDropped: _totalDropped,
    totalEmitted: _totalEmitted,
    queueSize: _queue.length,
    dropRate: _totalReceived > 0 ? _totalDropped / _totalReceived : 0.0,
  );

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    _emitTimer?.cancel();
    _emitTimer = null;
    _queue.clear();
    _lastEmittedByPv.clear();
    onEmit = null;
    onDropped = null;
  }
}
