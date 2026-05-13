/// board_arrow.dart
/// سهم اللوحة — Board Arrow
///
/// يُستخدم لعرض الحركات المقترحة من المحرك
/// أو أفضل الحركات على اللوحة.

/// سهم على لوحة الشطرنج — Arrow on the chess board
///
/// يُستخدم لعرض الحركات المقترحة من المحرك
/// أو أفضل الحركات على اللوحة.
class BoardArrow {
  /// المربع المصدر (مثل: "e2")
  final String from;

  /// المربع الهدف (مثل: "e4")
  final String to;

  /// اللون بصيغة ARGB (الافتراضي: أحمر شفاف)
  final int color;

  /// سُمك السهم (الافتراضي: 4)
  final double width;

  const BoardArrow({
    required this.from,
    required this.to,
    this.color = 0x80FF0000,
    this.width = 4.0,
  });

  /// سهم أفضل حركة (أخضر)
  factory BoardArrow.bestMove({required String from, required String to}) {
    return BoardArrow(from: from, to: to, color: 0x8000CC00);
  }

  /// سهم حركة جيدة (أزرق)
  factory BoardArrow.goodMove({required String from, required String to}) {
    return BoardArrow(from: from, to: to, color: 0x800000CC);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoardArrow && from == other.from && to == other.to && color == other.color;

  @override
  int get hashCode => Object.hash(from, to, color);
}
