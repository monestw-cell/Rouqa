/// export_service.dart
/// خدمة التصدير — Export Service
///
/// تصدير المباريات والتحليل بتنسيقات متعددة مع المشاركة.
library;

import 'package:share_plus/share_plus.dart';
import '../models/chess_models.dart';

/// خدمة التصدير
class ExportService {
  /// تصدير المباراة بصيغة PGN مع التعليقات
  static String exportPGN(ChessMatch match) {
    final buffer = StringBuffer();

    // رؤوس PGN
    buffer.writeln('[Event "${match.event ?? 'مباراة محللة برقعة'}"]');
    buffer.writeln('[Site "${match.site ?? 'Ruq\'a Chess Analyzer'}"]');
    buffer.writeln('[Date "${_formatDate(match.date)}"]');
    buffer.writeln('[White "${match.whiteName}"]');
    buffer.writeln('[Black "${match.blackName}"]');
    if (match.whiteElo != null) {
      buffer.writeln('[WhiteElo "${match.whiteElo}"]');
    }
    if (match.blackElo != null) {
      buffer.writeln('[BlackElo "${match.blackElo}"]');
    }
    buffer.writeln('[Result "${match.result.notation}"]');
    if (match.opening != null) {
      buffer.writeln('[ECO "${match.opening!.eco}"]');
      buffer.writeln('[Opening "${match.opening!.nameEn}"]');
    }
    if (match.timeControlInitial != null) {
      final inc = match.timeControlIncrement ?? 0;
      buffer.writeln('[TimeControl "${match.timeControlInitial}+$inc"]');
    }
    if (match.termination != null) {
      buffer.writeln('[Termination "${match.termination!.arabicLabel}"]');
    }

    buffer.writeln();

    // الحركات مع التعليقات
    for (int i = 0; i < match.moves.length; i++) {
      final move = match.moves[i];

      if (move.color == PlayerColor.white) {
        buffer.write('${move.moveNumber}. ');
      } else if (i == 0) {
        buffer.write('${move.moveNumber}... ');
      }

      buffer.write('${move.san}');

      // إضافة رمز التصنيف
      if (move.classification != MoveClassification.good &&
          move.classification != MoveClassification.book) {
        buffer.write(' \$${_classificationToNag(move.classification)}');
      }

      // إضافة تعليق التقييم
      if (move.cpLoss > 0 || move.evalBefore != 0) {
        final evalBefore = move.evalBefore / 100.0;
        final evalAfter = move.evalAfter / 100.0;
        buffer.write(' {${move.classification.arabicLabel}. '
            'تقييم: ${evalAfter >= 0 ? '+' : ''}${evalAfter.toStringAsFixed(2)} '
            'فقد: ${(move.cpLoss / 100.0).toStringAsFixed(2)} بيدق}');
      }

      buffer.write(' ');
    }

    buffer.write(match.result.notation);
    buffer.writeln();

    return buffer.toString();
  }

  /// تصدير ملخص التحليل بالعربية
  static String exportAnalysisSummary(ChessMatch match) {
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('  تحليل رُقعة — Ruq\'a Chess Analyzer');
    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln();

    // معلومات المباراة
    buffer.writeln('♔ ${match.whiteName}'
        '${match.whiteElo != null ? ' (${match.whiteElo})' : ''}');
    buffer.writeln('♚ ${match.blackName}'
        '${match.blackElo != null ? ' (${match.blackElo})' : ''}');
    buffer.writeln('النتيجة: ${match.result.arabicLabel} (${match.result.notation})');
    if (match.termination != null) {
      buffer.writeln('طريقة الانتهاء: ${match.termination!.arabicLabel}');
    }
    if (match.date != null) {
      buffer.writeln('التاريخ: ${_formatDate(match.date)}');
    }
    if (match.opening != null) {
      buffer.writeln('الافتتاحية: ${match.opening!.nameAr}');
    }
    buffer.writeln('عدد الحركات: ${match.totalMoves}');
    buffer.writeln();

    // الدقة
    buffer.writeln('── الدقة ─────────────────────────────');
    buffer.writeln('الأبيض: ${match.whiteAccuracy.toStringAsFixed(1)}%');
    buffer.writeln('الأسود: ${match.blackAccuracy.toStringAsFixed(1)}%');
    buffer.writeln();

    // تصنيفات الحركات
    buffer.writeln('── تصنيفات الحركات ──────────────────');
    buffer.writeln('الأبيض:');
    buffer.writeln('  رائع: ${match.whiteBrilliants} | '
        'ممتاز: ${match.whiteGreatMoves}');
    buffer.writeln('  عدم دقة: ${match.whiteInaccuracies} | '
        'خطأ: ${match.whiteMistakes} | '
        'خطأ فادح: ${match.whiteBlunders}');
    buffer.writeln('الأسود:');
    buffer.writeln('  رائع: ${match.blackBrilliants} | '
        'ممتاز: ${match.blackGreatMoves}');
    buffer.writeln('  عدم دقة: ${match.blackInaccuracies} | '
        'خطأ: ${match.blackMistakes} | '
        'خطأ فادح: ${match.blackBlunders}');
    buffer.writeln();

    // الأخطاء البارزة
    final errors = match.errorMoves;
    if (errors.isNotEmpty) {
      buffer.writeln('── أبرز الأخطاء ─────────────────────');
      for (final move in errors.take(5)) {
        buffer.writeln('  ${move.color.arabicLabel} - '
            'حركة ${move.moveNumber}: ${move.san} '
            '${move.classification.symbol} '
            '(فقد: ${(move.cpLoss / 100.0).toStringAsFixed(1)} بيدق)');
      }
      buffer.writeln();
    }

    buffer.writeln('═══════════════════════════════════════');

    return buffer.toString();
  }

  /// تصدير بصيغة CSV
  static String exportCSV(List<ChessMatch> matches) {
    final buffer = StringBuffer();

    // رؤوس الأعمدة
    buffer.writeln(
      'المعرف,الأبيض,الأسود,تصنيف الأبيض,تصنيف الأسود,'
      'النتيجة,الافتتاحية,دقة الأبيض,دقة الأسود,التاريخ'
    );

    for (final match in matches) {
      buffer.writeln(
        '${match.id},'
        '${match.whiteName},'
        '${match.blackName},'
        '${match.whiteElo ?? ''},'
        '${match.blackElo ?? ''},'
        '${match.result.notation},'
        '${match.opening?.nameAr ?? ''},'
        '${match.whiteAccuracy.toStringAsFixed(1)},'
        '${match.blackAccuracy.toStringAsFixed(1)},'
        '${_formatDate(match.date)}',
      );
    }

    return buffer.toString();
  }

  /// مشاركة PGN عبر share_plus
  static Future<void> sharePGN(ChessMatch match) async {
    final pgn = exportPGN(match);
    await Share.share(
      pgn,
      subject: 'مباراة ${match.whiteName} مقابل ${match.blackName}',
    );
  }

  /// مشاركة ملخص التحليل
  static Future<void> shareSummary(ChessMatch match) async {
    final summary = exportAnalysisSummary(match);
    await Share.share(
      summary,
      subject: 'تحليل مباراة ${match.whiteName} مقابل ${match.blackName}',
    );
  }

  /// مشاركة CSV
  static Future<void> shareCSV(List<ChessMatch> matches) async {
    final csv = exportCSV(matches);
    await Share.share(
      csv,
      subject: 'تصدير مباريات رقعة',
    );
  }

  // ─── دوال مساعدة ──────────────────────────────────────────────────────────

  /// تحويل تصنيف الحركة إلى رمز NAG
  static int _classificationToNag(MoveClassification classification) {
    return switch (classification) {
      MoveClassification.brilliant => 3,
      MoveClassification.great => 1,
      MoveClassification.best => 1,
      MoveClassification.inaccuracy => 6,
      MoveClassification.mistake => 2,
      MoveClassification.blunder => 4,
      MoveClassification.missedWin => 2,
      _ => 0,
    };
  }

  /// تنسيق التاريخ
  static String _formatDate(DateTime? date) {
    if (date == null) return '????.??.??';
    return '${date.year}.${date.month.toString().padLeft(2, '0')}.'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
