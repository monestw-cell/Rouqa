// test/services/chart_decimation_service_test.dart
// اختبارات خدمة تنقيط الرسم البياني (حل مشكلة #6)
//
// يتحقق من:
// - تحويل الحركات إلى نقاط
// - تنقيط ذكي يحافظ على الشكل
// - عرض النطاق المرئي

import 'package:flutter_test/flutter_test.dart';
import 'package:ruqa/services/chart_decimation_service.dart';
import 'package:ruqa/models/chess_models.dart';

void main() {
  group('ChartDecimationService', () {
    late ChartDecimationService service;

    setUp(() {
      service = ChartDecimationService();
    });

    test('يُرجع قائمة فارغة لقائمة حركات فارغة', () {
      final result = service.decimate(moves: []);
      expect(result, isEmpty);
    });

    test('يُرجع نقاط لعدد قليل من الحركات (بدون تنقيط)', () {
      final moves = List.generate(
        10,
        (i) => AnalyzedMove(
          moveNumber: (i ~/ 2) + 1,
          plyNumber: i + 1,
          color: i.isEven ? PlayerColor.white : PlayerColor.black,
          san: 'e4',
          uci: 'e2e4',
          fenBefore: '',
          fenAfter: '',
          evalBefore: 0,
          evalAfter: i * 10,
          cpLoss: 0,
          classification: MoveClassification.good,
          depth: 20,
          alternatives: const [],
          pv: '',
        ),
      );

      final result = service.decimate(moves: moves, maxPoints: 100);

      // +1 لنقطة البداية
      expect(result.length, 11);
    });

    test('يُقلل عدد النقاط عند تجاوز الحد', () {
      final moves = List.generate(
        200,
        (i) => AnalyzedMove(
          moveNumber: (i ~/ 2) + 1,
          plyNumber: i + 1,
          color: i.isEven ? PlayerColor.white : PlayerColor.black,
          san: 'e4',
          uci: 'e2e4',
          fenBefore: '',
          fenAfter: '',
          evalBefore: 0,
          evalAfter: (i - 100) * 5,
          cpLoss: 0,
          classification: i == 50
              ? MoveClassification.brilliant
              : i == 100
                  ? MoveClassification.blunder
                  : MoveClassification.good,
          depth: 20,
          alternatives: const [],
          pv: '',
        ),
      );

      final result = service.decimate(moves: moves, maxPoints: 50);

      // يجب أن يكون أقل من عدد الحركات الكامل
      expect(result.length, lessThanOrEqualTo(60)); // سمح بهامش صغير
      expect(result.length, greaterThan(20)); // لكن يحافظ على نقاط كافية
    });

    test('يحتفظ بالنقاط ذات التصنيفات الخاصة', () {
      final moves = List.generate(
        200,
        (i) => AnalyzedMove(
          moveNumber: (i ~/ 2) + 1,
          plyNumber: i + 1,
          color: i.isEven ? PlayerColor.white : PlayerColor.black,
          san: 'Qh5+',
          uci: 'h5e2',
          fenBefore: '',
          fenAfter: '',
          evalBefore: 0,
          evalAfter: 0,
          cpLoss: 0,
          classification: i == 30
              ? MoveClassification.brilliant
              : i == 80
                  ? MoveClassification.blunder
                  : i == 150
                      ? MoveClassification.mistake
                      : MoveClassification.good,
          depth: 20,
          alternatives: const [],
          pv: '',
        ),
      );

      final result = service.decimate(moves: moves, maxPoints: 50);

      // التحقق من أن التصنيفات الخاصة محفوظة
      final specialPoints = result.where(
        (p) => p.classification == MoveClassification.brilliant ||
            p.classification == MoveClassification.blunder ||
            p.classification == MoveClassification.mistake,
      );
      expect(specialPoints.length, greaterThanOrEqualTo(2)); // على الأقل brilliant و blunder
    });

    test('getVisiblePoints يُرجع فقط النقاط في النطاق', () {
      final points = List.generate(
        100,
        (i) => DecimatedPoint(x: i.toDouble(), y: i.toDouble()),
      );

      final visible = service.getVisiblePoints(
        points,
        viewStart: 20.0,
        viewEnd: 30.0,
      );

      for (final point in visible) {
        expect(point.x, greaterThanOrEqualTo(17)); // padding 3
        expect(point.x, lessThanOrEqualTo(33)); // padding 3
      }
    });
  });
}
