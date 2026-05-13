/// كاشف الافتتاحيات — Opening Detector
/// التعرف على الافتتاحيات الشطرنجية ومطابقتها مع الحركات الملعوبة
library;

// ─── نموذج بيانات الافتتاحية — Opening Data Model ──────────────────────────

/// بيانات الافتتاحية المكتشفة
class OpeningData {
  /// رمز ECO
  final String eco;

  /// اسم الافتتاحية بالعربية
  final String nameAr;

  /// اسم الافتتاحية بالإنجليزية
  final String nameEn;

  /// تسلسل الحركات (UCI)
  final String moves;

  /// تصنيف الافتتاحية
  final String category;

  /// وصف الافتتاحية بالعربية
  final String descriptionAr;

  const OpeningData({
    required this.eco,
    required this.nameAr,
    required this.nameEn,
    required this.moves,
    required this.category,
    required this.descriptionAr,
  });

  @override
  String toString() => '$eco: $nameAr ($nameEn)';
}

// ─── كاشف الافتتاحيات — Opening Detector ───────────────────────────────────

class OpeningDetector {
  /// قاعدة بيانات الافتتاحيات
  static final List<OpeningData> _openingsBook = _buildOpeningsBook();

  /// كشف الافتتاحية بناءً على قائمة الحركات الملعوبة
  ///
  /// [moves] قائمة الحركات بتدوين SAN (مثل: ['e4', 'e5', 'Nf3'])
  /// تُرجع الافتتاحية الأطول مطابقة أو null إذا لم يتم العثور
  static OpeningData? detect(List<String> moves) {
    if (moves.isEmpty) return null;

    // تحويل الحركات إلى نص للمقارنة
    final movesText = moves.join(' ');

    OpeningData? bestMatch;
    int bestMatchLength = 0;

    for (final opening in _openingsBook) {
      final openingMoves = opening.moves;
      if (movesText.startsWith(openingMoves) || openingMoves.startsWith(movesText)) {
        // حساب عدد حركات التطابق
        final openingMoveCount = openingMoves.split(' ').where((m) => m.isNotEmpty).length;
        final playedMoveCount = movesText.split(' ').where((m) => m.isNotEmpty).length;

        // الافتتاحية الأطول هي الأدق
        final matchLength = openingMoveCount <= playedMoveCount ? openingMoveCount : playedMoveCount;

        if (matchLength > bestMatchLength) {
          bestMatchLength = matchLength;
          bestMatch = opening;
        }
      }
    }

    return bestMatch;
  }

  /// كشف الافتتاحية بناءً على سلسلة حركات SAN
  static OpeningData? detectFromString(String movesString) {
    if (movesString.trim().isEmpty) return null;

    // تنظيف النص: إزالة أرقام الحركات والنقاط
    final cleanMoves = _cleanMovesText(movesString);
    final moves = cleanMoves.split(' ').where((m) => m.isNotEmpty).toList();

    return detect(moves);
  }

  /// البحث عن افتتاحية برمز ECO
  static OpeningData? findByEco(String eco) {
    for (final opening in _openingsBook) {
      if (opening.eco == eco) {
        return opening;
      }
    }
    return null;
  }

  /// البحث عن افتتاحية بالاسم (عربي أو إنجليزي)
  static List<OpeningData> searchByName(String query) {
    final results = <OpeningData>[];
    final lowerQuery = query.toLowerCase();

    for (final opening in _openingsBook) {
      if (opening.nameAr.contains(query) ||
          opening.nameEn.toLowerCase().contains(lowerQuery) ||
          opening.eco.toLowerCase().contains(lowerQuery)) {
        results.add(opening);
      }
    }

    return results;
  }

  /// الحصول على جميع الافتتاحيات
  static List<OpeningData> get allOpenings => List.unmodifiable(_openingsBook);

  /// الحصول على الافتتاحيات حسب التصنيف
  static List<OpeningData> getByCategory(String category) {
    return _openingsBook
        .where((o) => o.category == category)
        .toList();
  }

  /// تنظيف نص الحركات من أرقام الحركات والنقاط
  static String _cleanMovesText(String text) {
    // إزالة أرقام الحركات (مثل: 1. أو 1... أو 12.)
    return text.replaceAll(RegExp(r'\d+\.+\s*'), ' ').trim();
  }

  /// بناء قاعدة بيانات الافتتاحيات
  static List<OpeningData> _buildOpeningsBook() {
    return const [
      // ─── افتتاحيات بيادق الملك — King's Pawn Openings ─────────────────

      OpeningData(
        eco: 'B12',
        nameAr: 'دفاع كارو-كان: نسخة المتابعة',
        nameEn: 'Caro-Kann Defense: Advance Variation',
        moves: 'e4 c6 d4 d5 e5',
        category: 'semi-open',
        descriptionAr: 'دفاع متين يتميز بمتانة البنية البيادقية للأسود',
      ),
      OpeningData(
        eco: 'B13',
        nameAr: 'دفاع كارو-كان: تبادل',
        nameEn: 'Caro-Kann Defense: Exchange Variation',
        moves: 'e4 c6 d4 d5 exd5',
        category: 'semi-open',
        descriptionAr: 'نسخة هادئة تؤدي إلى وضعية متساوية',
      ),
      OpeningData(
        eco: 'B20',
        nameAr: 'دفاع صقلية',
        nameEn: 'Sicilian Defense',
        moves: 'e4 c5',
        category: 'semi-open',
        descriptionAr: 'أشهر دفاع ضد بيادق الملك ويوفر للأسود فرصاً هجومية',
      ),
      OpeningData(
        eco: 'B23',
        nameAr: 'دفاع صقلية: مغلق',
        nameEn: 'Sicilian Defense: Closed',
        moves: 'e4 c5 Nc3',
        category: 'semi-open',
        descriptionAr: 'نسخة استراتيجية من الدفاع الصقلي',
      ),
      OpeningData(
        eco: 'B30',
        nameAr: 'دفاع صقلية: نسخة روسو',
        nameEn: 'Sicilian Defense: Rossolimo Variation',
        moves: 'e4 c5 Nf3 Nc6 Bb5',
        category: 'semi-open',
        descriptionAr: 'نسخة فيشي النشطة ضد الدفاع الصقلي',
      ),
      OpeningData(
        eco: 'B33',
        nameAr: 'دفاع صقلية: نسخة شفينيشن',
        nameEn: 'Sicilian Defense: Sveshnikov Variation',
        moves: 'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5',
        category: 'semi-open',
        descriptionAr: 'نسخة حادة مع بيدق متقدم في e5',
      ),
      OpeningData(
        eco: 'B70',
        nameAr: 'دفاع صقلية: تنين',
        nameEn: 'Sicilian Defense: Dragon Variation',
        moves: 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6',
        category: 'semi-open',
        descriptionAr: 'نسخة هجومية شرسة مع قلعة على الجناحين',
      ),
      OpeningData(
        eco: 'B80',
        nameAr: 'دفاع صقلية: شيفينينن',
        nameEn: 'Sicilian Defense: Scheveningen Variation',
        moves: 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6',
        category: 'semi-open',
        descriptionAr: 'نسخة مرنة تتيح للأسود بناءً متيناً',
      ),
      OpeningData(
        eco: 'B90',
        nameAr: 'دفاع صقلية: ناجدورف',
        nameEn: 'Sicilian Defense: Najdorf Variation',
        moves: 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6',
        category: 'semi-open',
        descriptionAr: 'أقوى وأشهر نسخة صقلية — اختيار كاسباروف وفيشر',
      ),
      OpeningData(
        eco: 'C42',
        nameAr: 'دفاع بيتروف',
        nameEn: 'Petrov\'s Defense',
        moves: 'e4 e5 Nf3 Nf6',
        category: 'open',
        descriptionAr: 'دفاع متماثل يعتمد على الهجوم المضاد فوراً',
      ),
      OpeningData(
        eco: 'C50',
        nameAr: 'لعبة إيطالية',
        nameEn: 'Italian Game',
        moves: 'e4 e5 Nf3 Nc6 Bc4',
        category: 'open',
        descriptionAr: 'واحدة من أقدم الافتتاحيات — تطوير الفيل إلى c4',
      ),
      OpeningData(
        eco: 'C55',
        nameAr: 'دفاع الاثنين: نسخة جيوكو بيانو',
        nameEn: 'Two Knights Defense: Giuoco Piano',
        moves: 'e4 e5 Nf3 Nc6 Bc4 Bc5',
        category: 'open',
        descriptionAr: 'النسخة الهادئة من اللعبة الإيطالية',
      ),
      OpeningData(
        eco: 'C59',
        nameAr: 'دفاع الفارسين',
        nameEn: 'Two Knights Defense',
        moves: 'e4 e5 Nf3 Nc6 Bc4 Nf6 Ng5',
        category: 'open',
        descriptionAr: 'نسخة حادة مع هجوم الفارس المبكر على f7',
      ),
      OpeningData(
        eco: 'C65',
        nameAr: 'لعبة روي لوبيز: دفاع بيرلين',
        nameEn: 'Ruy Lopez: Berlin Defense',
        moves: 'e4 e5 Nf3 Nc6 Bb5 Nf6',
        category: 'open',
        descriptionAr: 'الدفاع الذي استخدمه كرامنيك للفوز على كاسباروف',
      ),
      OpeningData(
        eco: 'C84',
        nameAr: 'لعبة روي لوبيز: مغلقة',
        nameEn: 'Ruy Lopez: Closed',
        moves: 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O',
        category: 'open',
        descriptionAr: 'النسخة الرئيسية من أشهر افتتاحية في الشطرنج',
      ),
      OpeningData(
        eco: 'C88',
        nameAr: 'روي لوبيز: مغلقة مع d3',
        nameEn: 'Ruy Lopez: Closed with d3',
        moves: 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O',
        category: 'open',
        descriptionAr: 'نسخة استراتيجية عميقة من روي لوبيز',
      ),
      OpeningData(
        eco: 'C92',
        nameAr: 'روي لوبيز: نسخة زايتسف',
        nameEn: 'Ruy Lopez: Zaitsev Variation',
        moves: 'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O',
        category: 'open',
        descriptionAr: 'نسخة كاسباروف المفضلة — مرنة وغنية بالأفكار',
      ),

      // ─── افتتاحيات بيادق الوزير — Queen\'s Pawn Openings ────────────────

      OpeningData(
        eco: 'D02',
        nameAr: 'افتتاحية بيادق الوزير',
        nameEn: 'Queen\'s Pawn Opening',
        moves: 'd4',
        category: 'closed',
        descriptionAr: 'افتتاحية مرنة تبدأ ببيدق الوزير',
      ),
      OpeningData(
        eco: 'D06',
        nameAr: 'دفاع الهندي الملكي',
        nameEn: 'King\'s Indian Defense',
        moves: 'd4 Nf6 c4 g6',
        category: 'closed',
        descriptionAr: 'دفاع استراتيجي يتيح للأسود هجوماً على الجناح الملك',
      ),
      OpeningData(
        eco: 'D35',
        nameAr: 'مرفوض الوزير: نسخة التبادل',
        nameEn: 'Queen\'s Gambit Declined: Exchange Variation',
        moves: 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7 cxd5',
        category: 'closed',
        descriptionAr: 'نسخة استراتيجية مع بيانق معلقة للأسود',
      ),
      OpeningData(
        eco: 'D44',
        nameAr: 'سلاف نيمزوفيتش',
        nameEn: 'Semi-Slav Defense: Botvinnik Variation',
        moves: 'd4 d5 c4 c6 Nc3 Nf6 Nf3 e6 Bg5 dxc4 e4',
        category: 'closed',
        descriptionAr: 'نسخة حادة جداً مع تضحيات بيادق',
      ),
      OpeningData(
        eco: 'D58',
        nameAr: 'مرفوض الوزير: نسخة تارتاكوير',
        nameEn: 'Queen\'s Gambit Declined: Tartakower Variation',
        moves: 'd4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 h6 Bh4 b6',
        category: 'closed',
        descriptionAr: 'نسخة مرنة مع تحركات على الجناح الوزير',
      ),
      OpeningData(
        eco: 'E60',
        nameAr: 'دفاع نيمزو-هندي',
        nameEn: 'Nimzo-Indian Defense',
        moves: 'd4 Nf6 c4 e6 Nc3 Bb4',
        category: 'closed',
        descriptionAr: 'واحد من أقوى الدفوعات ضد 1.d4 — يكبح الفيل المركزي',
      ),
      OpeningData(
        eco: 'E70',
        nameAr: 'دفاع الهندي الملكي: نسخة عادية',
        nameEn: 'King\'s Indian Defense: Normal Variation',
        moves: 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6',
        category: 'closed',
        descriptionAr: 'النسخة الرئيسية من الهندي الملكي — صراع مركزي',
      ),

      // ─── افتتاحيات الأجنحة — Flank Openings ──────────────────────────────

      OpeningData(
        eco: 'A00',
        nameAr: 'افتتاحية بولوكزابي',
        nameEn: 'Polish Opening (Orangutan)',
        moves: 'b4',
        category: 'flank',
        descriptionAr: 'افتتاحية غير تقليدية تبدأ ببيدق الجناح',
      ),
      OpeningData(
        eco: 'A01',
        nameAr: 'دفاع نيمزوفيتش',
        nameEn: 'Nimzowitsch Defense',
        moves: 'e4 Nc6',
        category: 'semi-open',
        descriptionAr: 'دفاع غير مألوف يطور الفارس إلى c6',
      ),
      OpeningData(
        eco: 'A07',
        nameAr: 'افتتاحية ريتي',
        nameEn: 'Reti Opening',
        moves: 'Nf3 d5 g3',
        category: 'flank',
        descriptionAr: 'افتتاحية فيانكتو مرنة تسيطر على المركز من البعيد',
      ),
      OpeningData(
        eco: 'A11',
        nameAr: 'دفاع الإنجليزي: سلاف معكوس',
        nameEn: 'English Opening: Reversed Slav',
        moves: 'c4 c6',
        category: 'flank',
        descriptionAr: 'نسخة من الافتتاحية الإنجليزية تشبه الدفاع السلافي',
      ),
      OpeningData(
        eco: 'A20',
        nameAr: 'الافتتاحية الإنجليزية',
        nameEn: 'English Opening',
        moves: 'c4',
        category: 'flank',
        descriptionAr: 'افتتاحية مرنة تبدأ ببيدق c وتسيطر على d5',
      ),
      OpeningData(
        eco: 'A30',
        nameAr: 'الإنجليزية: نسخة الرجعية',
        nameEn: 'English Opening: Symmetrical Variation',
        moves: 'c4 c5',
        category: 'flank',
        descriptionAr: 'نسخة متماثلة تؤدي إلى صراع استراتيجي',
      ),
      OpeningData(
        eco: 'A40',
        nameAr: 'دفاع هندي الملكي ضد 1.d4',
        nameEn: 'King\'s Indian Defense vs 1.d4',
        moves: 'd4 Nf6',
        category: 'closed',
        descriptionAr: 'الرد الأكثر شيوعاً على بيدق الوزير',
      ),

      // ─── دفوعات فرنسية وهولندية — French & Dutch ────────────────────────

      OpeningData(
        eco: 'C00',
        nameAr: 'الدفاع الفرنسي',
        nameEn: 'French Defense',
        moves: 'e4 e6',
        category: 'semi-open',
        descriptionAr: 'دفاع متين يضيق المركز ويستعد للهجوم المضاد',
      ),
      OpeningData(
        eco: 'C11',
        nameAr: 'الدفاع الفرنسي: نسخة شتاينيتز',
        nameEn: 'French Defense: Steinitz Variation',
        moves: 'e4 e6 d4 d5 Nc3 Nf6 Bg5',
        category: 'semi-open',
        descriptionAr: 'نسخة ضاغطة تربط الفيل الأسود',
      ),
      OpeningData(
        eco: 'C18',
        nameAr: 'الدفاع الفرنسي: ويناور',
        nameEn: 'French Defense: Winawer Variation',
        moves: 'e4 e6 d4 d5 Nc3 Bb4',
        category: 'semi-open',
        descriptionAr: 'النسخة الأكثر حدة في الدفاع الفرنسي',
      ),
      OpeningData(
        eco: 'A80',
        nameAr: 'الدفاع الهولندي',
        nameEn: 'Dutch Defense',
        moves: 'd4 f5',
        category: 'closed',
        descriptionAr: 'دفاع هجومي يسيطر على المركز من الجناح الملك',
      ),
      OpeningData(
        eco: 'A87',
        nameAr: 'الدفاع الهولندي: فيانكتو',
        nameEn: 'Dutch Defense: Leningrad Variation',
        moves: 'd4 f5 g3 Nf6 Bg2 g6',
        category: 'closed',
        descriptionAr: 'نسخة فيانكتو مرنة من الدفاع الهولندي',
      ),

      // ─── دفوعات بيدق الملك الأخرى — Other King's Pawn Defenses ───────────

      OpeningData(
        eco: 'B01',
        nameAr: 'دفاع اسكندنافيا',
        nameEn: 'Scandinavian Defense',
        moves: 'e4 d5',
        category: 'semi-open',
        descriptionAr: 'دفاع مباشر يهاجم مركز الأبيض فوراً',
      ),
      OpeningData(
        eco: 'B06',
        nameAr: 'دفاع بيرك',
        nameEn: 'Pirc Defense',
        moves: 'e4 d6 d4 Nf6 Nc3 g6',
        category: 'semi-open',
        descriptionAr: 'دفاع فائق المرونة يسمح للأبيض بالمركز ثم يهاجمه',
      ),
      OpeningData(
        eco: 'B07',
        nameAr: 'دفاع بيرك: نسخة كلاسيكية',
        nameEn: 'Pirc Defense: Classical Variation',
        moves: 'e4 d6 d4 Nf6 Nc3 g6 Nf3',
        category: 'semi-open',
        descriptionAr: 'تطوير طبيعي ضد دفاع بيرك',
      ),
      OpeningData(
        eco: 'C21',
        nameAr: 'لعبة المركز',
        nameEn: 'Center Game',
        moves: 'e4 e5 d4 exd4',
        category: 'open',
        descriptionAr: 'افتتاحية مباشرة تفتح المركز فوراً',
      ),
      OpeningData(
        eco: 'C23',
        nameAr: 'افتتاحية فيينا',
        nameEn: 'Vienna Game',
        moves: 'e4 e5 Nc3',
        category: 'open',
        descriptionAr: 'تطوير الفيران لتشكيل هجوم على f7',
      ),
      OpeningData(
        eco: 'C24',
        nameAr: 'افتتاحية فيينا: نسخة الفيل',
        nameEn: 'Vienna Game: Bishop\'s Opening',
        moves: 'e4 e5 Nc3 Nf6 Bc4',
        category: 'open',
        descriptionAr: 'تطوير الفيل مع الاستعداد لهجوم f7',
      ),
      OpeningData(
        eco: 'C27',
        nameAr: 'لعبة الفيل',
        nameEn: 'Bishop\'s Opening',
        moves: 'e4 e5 Bc4',
        category: 'open',
        descriptionAr: 'تطوير مبكر للفيل يستهدف النقطة f7',
      ),
      OpeningData(
        eco: 'C28',
        nameAr: 'لعبة الفيل: نسخة باتشرير',
        nameEn: 'Bishop\'s Opening: Urusov Gambit',
        moves: 'e4 e5 Bc4 Nf6 d4',
        category: 'open',
        descriptionAr: 'تضحية بيدق للحصول على مبادرة قوية',
      ),

      // ─── دفوعات بيادق الوزير الإضافية — Additional Queen\'s Pawn ────────

      OpeningData(
        eco: 'D02',
        nameAr: 'لعبة لندن',
        nameEn: 'London System',
        moves: 'd4 d5 Bf4',
        category: 'closed',
        descriptionAr: 'نظام متين وسهل التنفيذ يعمل ضد معظم الدفوعات',
      ),
      OpeningData(
        eco: 'D06',
        nameAr: 'مرفوض الوزير',
        nameEn: 'Queen\'s Gambit',
        moves: 'd4 d5 c4',
        category: 'closed',
        descriptionAr: 'أشهر افتتاحية بيادق الوزير — تضحية البيدق للمركز',
      ),
      OpeningData(
        eco: 'D10',
        nameAr: 'دفاع سلاف',
        nameEn: 'Slav Defense',
        moves: 'd4 d5 c4 c6',
        category: 'closed',
        descriptionAr: 'دفاع متين يحافظ على الفيل في c8',
      ),
      OpeningData(
        eco: 'D15',
        nameAr: 'سلاف: نسخة شفينيشن',
        nameEn: 'Slav Defense: Schlechter Variation',
        moves: 'd4 d5 c4 c6 Nc3 Nf6 e3',
        category: 'closed',
        descriptionAr: 'نسخة صلبة من الدفاع السلافي',
      ),
      OpeningData(
        eco: 'D17',
        nameAr: 'سلاف: نسخة براغ',
        nameEn: 'Slav Defense: Prague Variation',
        moves: 'd4 d5 c4 c6 Nc3 Nf6 Nf3 dxc4 a4',
        category: 'closed',
        descriptionAr: 'نسخة نشطة مع بيدق مكتسب',
      ),
      OpeningData(
        eco: 'D30',
        nameAr: 'مرفوض الوزير: مقبول',
        nameEn: 'Queen\'s Gambit Accepted',
        moves: 'd4 d5 c4 dxc4',
        category: 'closed',
        descriptionAr: 'الأسود يقبل البيدق ويسعى للدفاع عنه',
      ),
      OpeningData(
        eco: 'D35',
        nameAr: 'مرفوض الوزير: مرفوض',
        nameEn: 'Queen\'s Gambit Declined',
        moves: 'd4 d5 c4 e6',
        category: 'closed',
        descriptionAr: 'رفض تضحية البيدق للحفاظ على بنية متينة',
      ),
      OpeningData(
        eco: 'E12',
        nameAr: 'دفاع هندي الوزير',
        nameEn: "Queen's Indian Defense",
        moves: 'd4 Nf6 c4 e6 Nf3 b6',
        category: 'closed',
        descriptionAr: 'دفاع مرن يسيطر على e4 من الجناح',
      ),
      OpeningData(
        eco: 'E32',
        nameAr: 'نيمزو-هندي: نسخة كلاسيكية',
        nameEn: 'Nimzo-Indian: Classical Variation',
        moves: 'd4 Nf6 c4 e6 Nc3 Bb4 Qc2',
        category: 'closed',
        descriptionAr: 'تطوير الملكة لحماية الفيل المركزي',
      ),
    ];
  }
}
