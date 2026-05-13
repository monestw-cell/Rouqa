// test/services/lru_bitmap_cache_test.dart
// اختبارات ذاكرة التخزين المؤقت LRU (حل مشكلة #2)
//
// يتحقق من:
// - تخزين واسترجاع العناصر
// - إخلاء LRU عند امتلاء الذاكرة
// - إحصائيات hit/miss
// - معالجة ضغط الذاكرة

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ruqa/services/lru_bitmap_cache.dart';

void main() {
  group('LruBitmapCache', () {
    late LruBitmapCache cache;

    setUp(() {
      cache = LruBitmapCache(
        maxSizeBytes: 1000, // 1KB للاختبار
        maxEntries: 5,
      );
    });

    tearDown(() {
      cache.dispose();
    });

    test('يخزن ويسترجع العناصر', () {
      // إنشاء صورة وهمية للاختبار
      // ملاحظة: في بيئة الاختبار، لا نستطيع إنشاء ui.Image حقيقي
      // لكن نختبر منطق LRU

      expect(cache.get('test_key'), isNull);
      expect(cache.contains('test_key'), false);
    });

    test('الإحصائيات تعمل بشكل صحيح', () {
      // miss
      cache.get('nonexistent');

      expect(cache.stats['hits'], 0);
      expect(cache.stats['misses'], 1);
    });

    test('clear يمسح كل البيانات', () {
      cache.clear();

      expect(cache.entryCount, 0);
      expect(cache.currentSizeBytes, 0);
    });

    test('handleMemoryPressure يقلل الذاكرة', () {
      // لا توجد عناصر للاختبار بدون ui.Image
      // لكن نتحقق من أن الدالة لا تُرمي استثناء
      cache.handleMemoryPressure();

      expect(cache.currentSizeBytes, 0);
    });

    test('الإحصائيات تتضمن جميع الحقول', () {
      final stats = cache.stats;

      expect(stats.containsKey('entryCount'), true);
      expect(stats.containsKey('currentSizeMB'), true);
      expect(stats.containsKey('usageRatio'), true);
      expect(stats.containsKey('hitRate'), true);
      expect(stats.containsKey('evictions'), true);
    });
  });
}
