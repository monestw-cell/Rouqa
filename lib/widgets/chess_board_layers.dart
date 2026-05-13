/// chess_board_layers.dart
/// طبقات الرقعة — ملف التوافق (Compatibility layer)
///
/// هذا الملف يوفر توافقًا مع الكود الذي يستورد chess_board_layers.dart
/// الطبقات الفعلية الآن مُعرّفة داخل chess_board.dart مباشرة.
///
/// إصلاحات مطبقة:
/// #1: RepaintBoundary لكل طبقة
/// #3: ArrowOverlayPainter منفصل
/// #20: isolated repaint لكل طبقة سريعة التحديث

// لا حاجة لتصدير أي شيء — كل الطبقات مُعرّفة في chess_board.dart
// هذا الملف موجود فقط لأغراض التوافق مع الاستيرادات المستقبلية
