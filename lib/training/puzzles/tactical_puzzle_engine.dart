/// tactical_puzzle_engine.dart
/// محرك الألغاز التكتيكية — Tactical Puzzle Engine
///
/// يحتوي على 20 لغزاً مدمجاً بمواضيع متنوعة مع أوصاف عربية.
library;

import 'dart:math';
import '../models/chess_models.dart';

/// نوع اللغز التكتيكي
enum PuzzleTheme {
  mate('كش مات', 'كش مات', 'تحقيق كش مات'),
  fork('شوكة', 'fork', 'مهاجمة قطعتين أو أكثر في نفس الوقت'),
  pin('تثبيت', 'pin', 'تثبيت قطعة لا يمكن تحريكها دون كشف الأهم'),
  skewer('سيخ', 'skewer', 'إجبار القطعة الأهم على التحرك لكشف الأقل أهمية'),
  sacrifice('تضحية', 'sacrifice', 'التخلي عن مادة للحصول على أفضلية'),
  discoveredAttack('هجوم مكتشف', 'discoveredAttack', 'تحريك قطعة تكشف هجوماً من قطعة أخرى'),
  deflection('إبعاد', 'deflection', 'إبعاد قطعة عن حماية مربع مهم'),
  trappedPiece('قطعة محاصرة', 'trappedPiece', 'محاصرة قطعة وعدم قدرتها على الهروب'),
  backRankMate('كش مات الصف الخلفي', 'backRankMate', 'كش مات على الصف الأول/الثامن'),
  smotheredMate('كش مات مختنق', 'smotheredMate', 'كش مات بالحصان مع قطع تحيط بالملك');

  final String arabicName;
  final String englishName;
  final String descriptionAr;

  const PuzzleTheme(this.arabicName, this.englishName, this.descriptionAr);
}

/// الألغاز المدمجة — 20 لغزاً تكتيكياً
class TacticalPuzzleEngine {
  static final _random = Random();

  /// جميع الألغاز المدمجة
  static final List<PuzzleData> _builtInPuzzles = [
    // 1. كش مات بالوزير - مبتدئ
    PuzzleData(
      id: 'puzzle_mate_01',
      fen: '6k1/5ppp/8/8/8/8/5PPP/4Q1K1 w - - 0 1',
      solution: ['e1e8'],
      initialEval: 0,
      rating: 800,
      plays: 1542,
      theme: 'mate',
      themeAr: 'كش مات',
    ),
    // 2. شوكة بالحصان - مبتدئ
    PuzzleData(
      id: 'puzzle_fork_01',
      fen: 'r1bqkbnr/pppp1ppp/2n5/4N3/4P3/8/PPPP1PPP/RNBQKB1R w KQkq - 0 1',
      solution: ['e5f7'],
      initialEval: 0,
      rating: 900,
      plays: 2103,
      theme: 'fork',
      themeAr: 'شوكة',
    ),
    // 3. تثبيت بالفيل - متوسط
    PuzzleData(
      id: 'puzzle_pin_01',
      fen: 'rnbqk2r/pppp1ppp/5n2/4p3/1b2P3/2N2N2/PPPP1PPP/R1BQKB1R w KQkq - 0 1',
      solution: ['c3d5'],
      initialEval: 0,
      rating: 1100,
      plays: 1876,
      theme: 'pin',
      themeAr: 'تثبيت',
    ),
    // 4. سيخ بالقلعة - متوسط
    PuzzleData(
      id: 'puzzle_skewer_01',
      fen: '6k1/5ppp/8/8/8/8/r4PPP/3R2K1 w - - 0 1',
      solution: ['d1d8'],
      initialEval: 0,
      rating: 1200,
      plays: 1234,
      theme: 'skewer',
      themeAr: 'سيخ',
    ),
    // 5. تضحية بالوزير - متقدم
    PuzzleData(
      id: 'puzzle_sacrifice_01',
      fen: 'r1b1kb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 0 1',
      solution: ['h5f7'],
      initialEval: 0,
      rating: 1300,
      plays: 3201,
      theme: 'sacrifice',
      themeAr: 'تضحية',
    ),
    // 6. هجوم مكتشف - متوسط
    PuzzleData(
      id: 'puzzle_discovered_01',
      fen: 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1',
      solution: ['c4f7'],
      initialEval: 0,
      rating: 1100,
      plays: 2456,
      theme: 'discoveredAttack',
      themeAr: 'هجوم مكتشف',
    ),
    // 7. إبعاد - متقدم
    PuzzleData(
      id: 'puzzle_deflection_01',
      fen: '2r2rk1/pp3ppp/8/2p1q3/2B5/1Q6/PP3PPP/R4RK1 w - - 0 1',
      solution: ['b3e6'],
      initialEval: 0,
      rating: 1400,
      plays: 987,
      theme: 'deflection',
      themeAr: 'إبعاد',
    ),
    // 8. كش مات الصف الخلفي - مبتدئ
    PuzzleData(
      id: 'puzzle_backrank_01',
      fen: '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1',
      solution: ['d1d8'],
      initialEval: 0,
      rating: 850,
      plays: 3012,
      theme: 'backRankMate',
      themeAr: 'كش مات الصف الخلفي',
    ),
    // 9. كش مات مختنق - خبير
    PuzzleData(
      id: 'puzzle_smothered_01',
      fen: '6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1',
      solution: ['g5f7'],
      initialEval: 0,
      rating: 1600,
      plays: 876,
      theme: 'smotheredMate',
      themeAr: 'كش مات مختنق',
    ),
    // 10. شوكة بالبيدق - مبتدئ
    PuzzleData(
      id: 'puzzle_fork_02',
      fen: 'rnbqkb1r/pppp1ppp/5n2/4p3/2B1P3/8/PPPP1PPP/RNBQK1NR w KQkq - 0 1',
      solution: ['c4f7'],
      initialEval: 0,
      rating: 950,
      plays: 2876,
      theme: 'fork',
      themeAr: 'شوكة',
    ),
    // 11. تثبيت مضاعف - متقدم
    PuzzleData(
      id: 'puzzle_pin_02',
      fen: 'r2qk2r/ppp2ppp/2n1bn2/3pp3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 1',
      solution: ['c4d5'],
      initialEval: 0,
      rating: 1350,
      plays: 1543,
      theme: 'pin',
      themeAr: 'تثبيت',
    ),
    // 12. تضحية بالقلعة - خبير
    PuzzleData(
      id: 'puzzle_sacrifice_02',
      fen: 'r4rk1/pp3ppp/8/2p1q3/2P5/1Q6/PP3PPP/R4RK1 w - - 0 1',
      solution: ['a1a8'],
      initialEval: 0,
      rating: 1500,
      plays: 765,
      theme: 'sacrifice',
      themeAr: 'تضحية',
    ),
    // 13. قطعة محاصرة - متوسط
    PuzzleData(
      id: 'puzzle_trapped_01',
      fen: 'rnbqk2r/ppppppbp/5np1/6/1B2P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 0 1',
      solution: ['b4f8'],
      initialEval: 0,
      rating: 1200,
      plays: 1432,
      theme: 'trappedPiece',
      themeAr: 'قطعة محاصرة',
    ),
    // 14. كش مات بالحصان - متوسط
    PuzzleData(
      id: 'puzzle_mate_02',
      fen: '6k1/pp4pp/8/8/8/8/1N3PPP/6K1 w - - 0 1',
      solution: ['b2d3', 'd3e5', 'e5f7'],
      initialEval: 0,
      rating: 1050,
      plays: 2109,
      theme: 'mate',
      themeAr: 'كش مات',
    ),
    // 15. شوكة بالوزير - متقدم
    PuzzleData(
      id: 'puzzle_fork_03',
      fen: 'r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 0 1',
      solution: ['c5f2'],
      initialEval: 0,
      rating: 1300,
      plays: 1876,
      theme: 'fork',
      themeAr: 'شوكة',
    ),
    // 16. كش مات بالقلعة - مبتدئ
    PuzzleData(
      id: 'puzzle_mate_03',
      fen: '5rk1/pp3ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1',
      solution: ['d1d8'],
      initialEval: 0,
      rating: 800,
      plays: 3456,
      theme: 'mate',
      themeAr: 'كش مات',
    ),
    // 17. سيخ بالوزير - متقدم
    PuzzleData(
      id: 'puzzle_skewer_02',
      fen: '3r2k1/5ppp/8/8/8/8/5PPP/3Q2K1 w - - 0 1',
      solution: ['d1d8'],
      initialEval: 0,
      rating: 1250,
      plays: 1098,
      theme: 'skewer',
      themeAr: 'سيخ',
    ),
    // 18. هجوم مكتشف بالفيل - متوسط
    PuzzleData(
      id: 'puzzle_discovered_02',
      fen: 'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 1',
      solution: ['c4f7'],
      initialEval: 0,
      rating: 1150,
      plays: 2345,
      theme: 'discoveredAttack',
      themeAr: 'هجوم مكتشف',
    ),
    // 19. تضحية بالفيل - خبير
    PuzzleData(
      id: 'puzzle_sacrifice_03',
      fen: 'r2qkb1r/ppp2ppp/2n1b3/3np3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 1',
      solution: ['c4d5'],
      initialEval: 0,
      rating: 1550,
      plays: 654,
      theme: 'sacrifice',
      themeAr: 'تضحية',
    ),
    // 20. كش مات مزدوج - أستاذ
    PuzzleData(
      id: 'puzzle_mate_04',
      fen: 'r1b2rk1/ppppqppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQ1RK1 w - - 0 1',
      solution: ['c4d5'],
      initialEval: 0,
      rating: 1700,
      plays: 543,
      theme: 'mate',
      themeAr: 'كش مات',
    ),
  ];

  /// الحصول على لغز عشوائي
  static PuzzleData getRandomPuzzle() {
    return _builtInPuzzles[_random.nextInt(_builtInPuzzles.length)];
  }

  /// الحصول على لغز بناءً على التصنيف
  static PuzzleData getPuzzleByRating(int playerRating) {
    // اختيار لغز قريب من تصنيف اللاعب (±200)
    final suitable = _builtInPuzzles.where(
      (p) => (p.rating - playerRating).abs() <= 300,
    ).toList();

    if (suitable.isEmpty) {
      // إذا لم نجد، نختار الأقرب
      _builtInPuzzles.sort(
        (a, b) => (a.rating - playerRating).abs().compareTo(
          (b.rating - playerRating).abs(),
        ),
      );
      return _builtInPuzzles.first;
    }

    return suitable[_random.nextInt(suitable.length)];
  }

  /// الحصول على لغز بناءً على الموضوع
  static PuzzleData getPuzzleByTheme(PuzzleTheme theme) {
    final themed = _builtInPuzzles
        .where((p) => p.theme == theme.englishName)
        .toList();

    if (themed.isEmpty) return getRandomPuzzle();
    return themed[_random.nextInt(themed.length)];
  }

  /// الحصول على جميع الألغاز
  static List<PuzzleData> getAllPuzzles() => List.unmodifiable(_builtInPuzzles);

  /// الحصول على ألغاز حسب الموضوع
  static List<PuzzleData> getPuzzlesByTheme(PuzzleTheme theme) {
    return _builtInPuzzles
        .where((p) => p.theme == theme.englishName)
        .toList();
  }

  /// الحصول على ألغاز حسب نطاق التصنيف
  static List<PuzzleData> getPuzzlesByRatingRange(int min, int max) {
    return _builtInPuzzles.where((p) => p.rating >= min && p.rating <= max).toList();
  }

  /// عدد الألغاز المتاحة
  static int get puzzleCount => _builtInPuzzles.length;

  /// المواضيع المتاحة
  static List<PuzzleTheme> get availableThemes => PuzzleTheme.values;
}
