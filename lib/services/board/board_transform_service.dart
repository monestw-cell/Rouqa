/// board_transform_service.dart
/// خدمة تحويل الإحداثيات المركزية للرقعة (إصلاح #13)
///
/// تحل مشكلة الحسابات العشوائية للإحداثيات في عدة أماكن
/// بتجميعها في مكان واحد، مثلما يفعل ChessIs مع Matrix/PointF/Rect.
///
/// الميزات:
/// - تحويل مربع ↔ إحداثيات بكسل
/// - دعم قلب الرقعة (flip)
/// - حساب مستطيلات المربعات
/// - تحويل لمس المستخدم إلى مربع
/// - مركزية كل الحسابات الهندسية

import 'dart:math' as math;

/// أسماء الأعمدة (a-h)
const kFileNames = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

/// أسماء الصفوف (1-8)
const kRankNames = ['1', '2', '3', '4', '5', '6', '7', '8'];

/// خدمة تحويل إحداثيات الرقعة — Board Transform Service
///
/// تُستخدم من قبل:
/// - ChessBoard widget
/// - ArrowOverlayPainter
/// - EvalBar
/// - أي ويدجت تحتاج تحويلات إحداثيات
///
/// الاستخدام:
/// ```dart
/// final transform = BoardTransformService(
///   boardSize: 360,
///   flipped: false,
/// );
///
/// // الحصول على مركز مربع
/// final center = transform.squareCenter('e4');
///
/// // الحصول على مربع من إحداثيات لمس
/// final square = transform.squareFromOffset(offset);
/// ```
class BoardTransformService {
  /// حجم الرقعة الكلي بالبكسل
  final double boardSize;

  /// حجم المربع الواحد بالبكسل
  final double squareSize;

  /// هل الرقعة مقلوبة (منظور الأسود)؟
  final bool flipped;

  /// إنشاء خدمة تحويل جديدة
  BoardTransformService({
    required this.boardSize,
    this.flipped = false,
  }) : squareSize = boardSize / 8;

  // ========================================================================
  // تحويل مربع → إحداثيات
  // ========================================================================

  /// فهرس العمود (0-7) من اسم المربع
  int fileIndex(String square) => square.codeUnitAt(0) - 'a'.codeUnitAt(0);

  /// فهرس الصف (0-7) من اسم المربع (الصف 1 = 0)
  int rankIndex(String square) => square[1].codeUnitAt(0) - '1'.codeUnitAt(0);

  /// اسم المربع من الفهرس
  String squareName(int file, int rank) => '${kFileNames[file]}${rank + 1}';

  /// إحداثيات المركز على الرقعة من اسم مربع
  Offset squareCenter(String square) {
    int file = fileIndex(square);
    int rank = rankIndex(square);
    if (flipped) {
      file = 7 - file;
      rank = 7 - rank;
    }
    return Offset(
      file * squareSize + squareSize / 2,
      (7 - rank) * squareSize + squareSize / 2,
    );
  }

  /// مستطيل المربع على الرقعة من اسم مربع
  Rect squareRect(String square) {
    int file = fileIndex(square);
    int rank = rankIndex(square);
    if (flipped) {
      file = 7 - file;
      rank = 7 - rank;
    }
    return Rect.fromLTWH(
      file * squareSize,
      (7 - rank) * squareSize,
      squareSize,
      squareSize,
    );
  }

  /// مستطيل المربع على الرقعة من الفهرس المباشر (0-7 لكل من file و rank)
  /// [file] فهرس العمود (0=a, 7=h)
  /// [rank] فهرس الصف (0=1, 7=8)
  Rect squareRectFromIndices(int file, int rank) {
    int displayFile = flipped ? 7 - file : file;
    int displayRank = flipped ? rank : 7 - rank;
    return Rect.fromLTWH(
      displayFile * squareSize,
      displayRank * squareSize,
      squareSize,
      squareSize,
    );
  }

  // ========================================================================
  // تحويل إحداثيات → مربع
  // ========================================================================

  /// اسم المربع من إحداثيات محلية (مثل لمس المستخدم)
  String? squareFromOffset(Offset localPosition) {
    if (localPosition.dx < 0 || localPosition.dy < 0) return null;
    if (localPosition.dx > boardSize || localPosition.dy > boardSize) return null;

    int file = (localPosition.dx / squareSize).floor();
    int rank = 7 - (localPosition.dy / squareSize).floor();
    if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
    if (flipped) {
      file = 7 - file;
      rank = 7 - rank;
    }
    return squareName(file, rank);
  }

  // ========================================================================
  // حسابات هندسية مساعدة
  // ========================================================================

  /// هل المربع فاتح اللون؟
  bool isLightSquare(String square) {
    final file = fileIndex(square);
    final rank = rankIndex(square);
    return (file + rank) % 2 == 0;
  }

  /// حساب موقع نقطة بين مربعين (للرسوم المتحركة)
  Offset lerpSquareCenter(String from, String to, double t) {
    final fromCenter = squareCenter(from);
    final toCenter = squareCenter(to);
    return Offset(
      fromCenter.dx + (toCenter.dx - fromCenter.dx) * t,
      fromCenter.dy + (toCenter.dy - fromCenter.dy) * t,
    );
  }

  /// حساب مستطيل القطعة بناءً على نسبة حجمها من المربع
  Rect pieceRect(String square, {double pieceRatio = 0.85}) {
    final center = squareCenter(square);
    final size = squareSize * pieceRatio;
    return Rect.fromCenter(center: center, width: size, height: size);
  }

  /// حساب مستطيل القطعة في موقع معين (للسحب)
  Rect pieceRectAtOffset(Offset center, {double pieceRatio = 0.85}) {
    final size = squareSize * pieceRatio;
    return Rect.fromCenter(center: center, width: size, height: size);
  }

  /// تحويل فهرس الصف/العمود إلى إحداثيات العرض
  int displayFile(int file) => flipped ? 7 - file : file;
  int displayRank(int rank) => flipped ? rank : 7 - rank;

  /// المسافة بين مركزي مربعين
  double distanceBetween(String sq1, String sq2) {
    final c1 = squareCenter(sq1);
    final c2 = squareCenter(sq2);
    return math.sqrt(
      math.pow(c2.dx - c1.dx, 2) + math.pow(c2.dy - c1.dy, 2),
    );
  }
}
