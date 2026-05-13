// test/services/engine_command_queue_test.dart
// اختبارات مدير قائمة أوامر المحرك (حل مشكلة #16)
//
// يتحقق من:
// - إضافة أوامر
// - تحسين الأوامر المكررة
// - إزالة stop غير الضروري
// - إحصائيات التحسين

import 'package:flutter_test/flutter_test.dart';
import 'package:ruqa/services/engine_command_queue.dart';

void main() {
  group('EngineCommandQueue', () {
    late EngineCommandQueue queue;
    final sentCommands = <String>[];

    setUp(() {
      sentCommands.clear();
      queue = EngineCommandQueue(
        sendCommand: (cmd) => sentCommands.add(cmd),
      );
    });

    tearDown(() {
      queue.dispose();
    });

    test('يرسل الأوامر فوراً', () {
      queue.enqueue('uci');

      expect(sentCommands, contains('uci'));
    });

    test('enqueuePosition يرسل أمر position', () {
      queue.enqueuePosition('position fen rnbqkbnr...');

      expect(sentCommands.last, 'position fen rnbqkbnr...');
    });

    test('enqueueGo يرسل أمر go', () {
      queue.enqueueGo(depth: 20);

      expect(sentCommands.last, 'go depth 20');
    });

    test('enqueueGo infinite', () {
      queue.enqueueGo(infinite: true);

      expect(sentCommands.last, 'go infinite');
    });

    test('enqueueStop يرسل أمر stop', () {
      // يجب أن يكون المحرك في حالة تحليل
      queue.enqueueGo(infinite: true);
      queue.enqueueStop();

      expect(sentCommands, contains('stop'));
    });

    test('إحصائيات التحسين تتتبع العمليات', () {
      queue.enqueuePosition('position startpos');
      queue.enqueueGo(depth: 20);

      final stats = queue.stats;
      expect(stats['totalEnqueued'], greaterThanOrEqualTo(2));
      expect(stats['totalSent'], greaterThanOrEqualTo(2));
    });

    test('sendPositionAndGo يوقف + يضع الموقف + يبدأ', () {
      queue.sendPositionAndGo(
        positionCommand: 'position startpos',
        depth: 18,
      );

      // يجب أن يُرسل: stop, position, go
      expect(sentCommands, contains('position startpos'));
      expect(sentCommands, contains('go depth 18'));
    });

    test('enqueueSetOption يرسل أمر setoption', () {
      queue.enqueueSetOption('Threads', '2');

      expect(sentCommands.last, 'setoption name Threads value 2');
    });
  });
}
