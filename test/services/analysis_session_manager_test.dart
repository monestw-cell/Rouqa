// test/services/analysis_session_manager_test.dart
// اختبارات مدير جلسات التحليل (حل مشكلة #4)
//
// يتحقق من:
// - إنشاء جلسة جديدة
// - إلغاء الجلسة القديمة عند بدء جديدة
// - رفض الاستجابات القديمة
// - تنفيذ آمن

import 'package:flutter_test/flutter_test.dart';
import 'package:ruqa/services/analysis_session_manager.dart';

void main() {
  group('AnalysisSessionManager', () {
    late AnalysisSessionManager manager;

    setUp(() {
      manager = AnalysisSessionManager();
    });

    tearDown(() {
      manager.dispose();
    });

    test('يبدأ جلسة جديدة ويعطي token فريد', () {
      final token1 = manager.startSession('test1');
      final token2 = manager.startSession('test2');

      expect(token1.id, isNot(equals(token2.id)));
      expect(manager.currentToken, equals(token2));
    });

    test('يُلغي الجلسة القديمة عند بدء جديدة', () {
      final token1 = manager.startSession('test1');
      expect(token1.isCancelled, false);

      final token2 = manager.startSession('test2');
      expect(token1.isCancelled, true);
      expect(token2.isCancelled, false);
    });

    test('isCurrentSession يعمل بشكل صحيح', () {
      final token1 = manager.startSession('test1');

      expect(manager.isCurrentSession(token1), true);

      final token2 = manager.startSession('test2');

      expect(manager.isCurrentSession(token1), false);
      expect(manager.isCurrentSession(token2), true);
    });

    test('isCurrentSession يرفض token ملغي', () {
      final token1 = manager.startSession('test1');
      manager.startSession('test2'); // يُلغي token1

      expect(manager.isCurrentSession(token1), false);
    });

    test('cancelCurrentSession يُلغي الجلسة الحالية', () {
      final token = manager.startSession('test');

      manager.cancelCurrentSession();

      expect(token.isCancelled, true);
      expect(manager.isCurrentSession(token), false);
    });

    test('completeCurrentSession يُكمل الجلسة', () {
      manager.startSession('test');
      expect(manager.hasActiveSession, true);

      manager.completeCurrentSession();
      expect(manager.currentToken, isNull);
    });

    test('الإحصائيات تعمل بشكل صحيح', () {
      manager.startSession('test1');
      manager.startSession('test2');
      manager.startSession('test3');

      final stats = manager.stats;
      expect(stats['totalSessions'], 3);
      expect(stats['cancelledSessions'], 2); // أول 2 أُلغيا
    });
  });
}
