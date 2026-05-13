/// lru_bitmap_cache.dart
/// تخزين مؤقت LRU لصور القطع مع إخلاء تلقائي (حل مشكلة #2)
///
/// يحل مشكلة Memory Pressure عند:
/// - فتح مباريات كثيرة
/// - مباريات طويلة
/// - تحليل متكرر
///
/// الحل:
/// - LRU bitmap cache بحجم أقصى
/// - cache eviction عند تجاوز الحد
/// - image recycling strategy
/// - مراقبة الذاكرة وتقليلها تلقائياً

import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// عنصر في ذاكرة التخزين المؤقت LRU
class _CacheEntry {
  final String key;
  final ui.Image image;
  int lastAccessTime;
  int accessCount;
  final int sizeBytes;

  _CacheEntry({
    required this.key,
    required this.image,
    required this.lastAccessTime,
    this.accessCount = 1,
    required this.sizeBytes,
  });
}

/// تخزين مؤقت LRU لصور القطع — LRU Bitmap Cache
///
/// يوفر:
/// 1. تخزين مؤقت بصور محدودة الحجم
/// 2. إخلاء تلقائي للعناصر الأقل استخداماً (LRU)
/// 3. إعادة تدوير الصور (image recycling)
/// 4. مراقبة استهلاك الذاكرة
/// 5. تقليل الذاكرة تلقائياً عند الضغط
///
/// الاستخدام:
/// ```dart
/// final cache = LruBitmapCache(maxSizeBytes: 50 * 1024 * 1024); // 50MB
///
/// // تخزين صورة
/// cache.put('wK_90', image);
///
/// // استرجاع صورة
/// final image = cache.get('wK_90');
///
/// // مراقبة الذاكرة
/// print(cache.currentSizeBytes);
/// print(cache.hitRate);
///
/// // تحرير الموارد
/// cache.dispose();
/// ```
class LruBitmapCache {
  static const _tag = 'LruBitmapCache';

  /// الحد الأقصى لحجم الذاكرة المؤقتة (بالبايت)
  final int maxSizeBytes;

  /// الحد الأقصى لعدد العناصر
  final int maxEntries;

  /// عتبة الضغط العالي (نسبة من maxSizeBytes)
  final double highWatermark;

  /// عتبة الضغط المنخفض للإخلاء (نسبة من maxSizeBytes)
  final double lowWatermark;

  /// الذاكرة المؤقتة
  final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();

  /// الحجم الحالي بالبايت
  int _currentSizeBytes = 0;

  /// عدد مرات الوصول الناجح
  int _hits = 0;

  /// عدد مرات الوصول الفاشل
  int _misses = 0;

  /// عدد مرات الإخلاء
  int _evictions = 0;

  /// الوقت الحالي (لـ LRU)
  int _clock = 0;

  LruBitmapCache({
    this.maxSizeBytes = 50 * 1024 * 1024, // 50MB افتراضي
    this.maxEntries = 200,
    this.highWatermark = 0.85,
    this.lowWatermark = 0.60,
  });

  // ========================================================================
  // العمليات الأساسية
  // ========================================================================

  /// تخزين صورة
  void put(String key, ui.Image image, {int? estimatedSizeBytes}) {
    _clock++;

    // حساب حجم الصورة التقريبي
    final sizeBytes = estimatedSizeBytes ??
        (image.width * image.height * 4); // RGBA = 4 bytes per pixel

    // إذا كان العنصر موجوداً مسبقاً، نحذفه
    if (_cache.containsKey(key)) {
      _removeEntry(key);
    }

    // التحقق من الحجم - إذا كان العنصر نفسه أكبر من الحد الأقصى
    if (sizeBytes > maxSizeBytes) {
      debugPrint('$_tag: صورة كبيرة جداً ($sizeBytes bytes)، تخطي التخزين: $key');
      return;
    }

    // الإخلاء إذا لزم الأمر
    while (_currentSizeBytes + sizeBytes > maxSizeBytes && _cache.isNotEmpty) {
      _evictLRU();
    }

    // الإخلاء إذا تجاوز عدد العناصر الحد
    while (_cache.length >= maxEntries && _cache.isNotEmpty) {
      _evictLRU();
    }

    // إضافة العنصر
    final entry = _CacheEntry(
      key: key,
      image: image,
      lastAccessTime: _clock,
      sizeBytes: sizeBytes,
    );

    _cache[key] = entry;
    _currentSizeBytes += sizeBytes;

    // التحقق من عتبة الضغط العالي
    if (_currentSizeBytes > maxSizeBytes * highWatermark) {
      _reduceTo(lowWatermark);
    }
  }

  /// استرجاع صورة
  ui.Image? get(String key) {
    _clock++;

    final entry = _cache[key];
    if (entry == null) {
      _misses++;
      return null;
    }

    // تحديث وقت الوصول (LRU)
    entry.lastAccessTime = _clock;
    entry.accessCount++;
    _hits++;

    // نقل العنصر لنهاية القائمة (أحدث استخدام)
    _cache.remove(key);
    _cache[key] = entry;

    return entry.image;
  }

  /// هل الصورة موجودة؟
  bool contains(String key) => _cache.containsKey(key);

  /// إزالة صورة
  void remove(String key) {
    _removeEntry(key);
  }

  /// مسح كل الصور
  void clear() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _currentSizeBytes = 0;
  }

  // ========================================================================
  // إدارة الذاكرة
  // ========================================================================

  /// إخلاء العنصر الأقل استخداماً
  void _evictLRU() {
    if (_cache.isEmpty) return;

    // العثور على العنصر الأقدم استخداماً
    String? lruKey;
    int oldestTime = _clock + 1;

    for (final entry in _cache.values) {
      if (entry.lastAccessTime < oldestTime) {
        oldestTime = entry.lastAccessTime;
        lruKey = entry.key;
      }
    }

    if (lruKey != null) {
      _removeEntry(lruKey);
      _evictions++;
    }
  }

  /// تقليل الذاكرة إلى نسبة معينة
  void _reduceTo(double targetRatio) {
    final targetBytes = (maxSizeBytes * targetRatio).toInt();

    while (_currentSizeBytes > targetBytes && _cache.isNotEmpty) {
      _evictLRU();
    }

    debugPrint(
      '$_tag: تم تقليل الذاكرة إلى ${(_currentSizeBytes / 1024 / 1024).toStringAsFixed(1)}MB '
      '($_evictions إخلاء)',
    );
  }

  /// إزالة عنصر وإعادة تدوير الصورة
  void _removeEntry(String key) {
    final entry = _cache.remove(key);
    if (entry != null) {
      _currentSizeBytes -= entry.sizeBytes;
      entry.image.dispose();
    }
  }

  /// معالجة ضغط الذاكرة — يُستدعى من النظام عند تحذير الذاكرة
  void handleMemoryPressure() {
    debugPrint('$_tag: تحذير ضغط الذاكرة — تقليل الذاكرة المؤقتة');

    // تقليل إلى 40% من الحجم الأقصى
    _reduceTo(0.40);

    // إعادة تدوير الصور غير المستخدمة مؤخراً
    final now = _clock;
    final keysToRemove = <String>[];

    for (final entry in _cache.values) {
      // إذا لم تُستخدم منذ أكثر من 100 عملية وصول
      if (now - entry.lastAccessTime > 100 && entry.accessCount < 3) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      _removeEntry(key);
    }
  }

  // ========================================================================
  // إحصائيات
  // ========================================================================

  /// الحجم الحالي بالبايت
  int get currentSizeBytes => _currentSizeBytes;

  /// الحجم الحالي بالميجابايت
  double get currentSizeMB => _currentSizeBytes / 1024 / 1024;

  /// عدد العناصر
  int get entryCount => _cache.length;

  /// نسبة استخدام الذاكرة (0.0 - 1.0)
  double get usageRatio => maxSizeBytes > 0 ? _currentSizeBytes / maxSizeBytes : 0.0;

  /// نسبة الوصول الناجح
  double get hitRate {
    final total = _hits + _misses;
    return total > 0 ? _hits / total : 0.0;
  }

  /// عدد مرات الإخلاء
  int get evictionCount => _evictions;

  /// ملخص الإحصائيات
  Map<String, dynamic> get stats => {
    'entryCount': entryCount,
    'currentSizeMB': currentSizeMB.toStringAsFixed(2),
    'usageRatio': usageRatio.toStringAsFixed(2),
    'hitRate': hitRate.toStringAsFixed(2),
    'hits': _hits,
    'misses': _misses,
    'evictions': _evictions,
  };

  // ========================================================================
  // تحرير الموارد
  // ========================================================================

  void dispose() {
    clear();
  }
}
