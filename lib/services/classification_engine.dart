/// Ruq'a Chess Analyzer - Move Classification Engine
/// محرك تصنيف الحركات لمحلل الشطرنج رقعة
///
/// Implements the same 9-level move classification system used by
/// Chess.com and Lichess. Each move in a game is classified based on
/// centipawn loss relative to the engine's best line, positional
/// context (sacrifices, only-move situations), and opening book data.
///
/// Classification hierarchy (best → worst):
///   Brilliant (♪) → Great (!) → Best (!!) → Good (✓) → Book (📚)
///   → Inaccuracy (?!) → Mistake (?) → Blunder (??) → Missed Win (∓)
///
/// The accuracy formula matches Chess.com's published algorithm:
///   accuracy = 103.1667 * exp(-0.0437 * cpLoss) - 3.1667
///   clamped to [0, 100]

import 'dart:math';
import '../models/chess_models.dart';

class ClassificationEngine {
  // ===========================================================================
  // CONSTANTS - Classification thresholds in centipawns (1 pawn = 100 cp)
  // ===========================================================================

  /// عامل التحويل: 100 سنتيبيدق = 1 بيدق
  static const int cpPerPawn = 100;

  /// الحد الأدنى لفقد البيدق لاعتبار الحركة "عدم دقة"
  /// Inaccuracy threshold: 0.5 pawns = 50 cp
  static const int inaccuracyThreshold = 50;

  /// الحد الأدنى لفقد البيدق لاعتبار الحركة "خطأ"
  /// Mistake threshold: 1.5 pawns = 150 cp
  static const int mistakeThreshold = 150;

  /// الحد الأدنى لفقد البيدق لاعتبار الحركة "خطأ فادح"
  /// Blunder threshold: 3.0 pawns = 300 cp
  static const int blunderThreshold = 300;

  /// نطاق "حركة ممتازة": ضمن 0.5 بيدق من أفضل حركة
  /// Great move threshold: within 0.5 pawns = 50 cp
  static const int greatMoveThreshold = 50;

  /// نطاق "أفضل حركة": ضمن 0.1 بيدق من خط المحرك الأول
  /// Best move threshold: within 0.1 pawns = 10 cp
  static const int bestMoveThreshold = 10;

  /// نطاق "حركة جيدة": ضمن 1.5 بيدق من أفضل حركة
  /// Good move threshold: within 1.5 pawns = 150 cp
  static const int goodMoveThreshold = 150;

  /// حد التضحية: الفقد المادي المؤقت الذي يعتبر تضحية
  /// Sacrifice threshold: temporary material loss of at least 1 pawn
  static const int sacrificeThreshold = 100;

  /// حد "حركة فوز ضائع": فرق 2+ بيدق بين الفوز والتعادل
  /// Missed win threshold: eval swing of 2+ pawns (200 cp)
  static const int missedWinThreshold = 200;

  /// حد "الحركة الوحيدة": الفرق بين الحركة الأولى والثانية
  /// Only-move threshold: second-best is at least 2 pawns worse
  static const int onlyMoveThreshold = 200;

  /// حد التقييم الإيجابي لاعتبار الوضعية "رابحة"
  /// Winning eval threshold: 2 pawns = 200 cp
  static const int winningEvalThreshold = 200;

  /// حد التقييم السلبي لاعتبار الوضعية "خاسرة"
  /// Losing eval threshold: -2 pawns = -200 cp
  static const int losingEvalThreshold = -200;

  /// حد التقييم للوضعية المتساوية
  /// Equal position threshold: within 0.3 pawns = 30 cp
  static const int equalEvalThreshold = 30;

  // ===========================================================================
  // MAIN CLASSIFICATION METHOD
  // ===========================================================================

  /// تصنيف الحركة - Classify a single chess move
  ///
  /// This is the primary entry point for move classification. It evaluates
  /// a move based on multiple factors and returns one of 9 classifications.
  ///
  /// The classification follows a strict priority order:
  /// 1. Book moves are identified first (if from opening theory)
  /// 2. Brilliant moves (sacrifice + only non-losing move)
  /// 3. Blunders (massive eval loss)
  /// 4. Missed wins (missed winning move without losing material)
  /// 5. Mistakes (significant eval loss)
  /// 6. Inaccuracies (minor eval loss)
  /// 7. Best moves (matches engine top choice)
  /// 8. Great moves (near-best)
  /// 9. Good moves (reasonable but suboptimal)
  ///
  /// Parameters:
  /// - [cpLoss]: Centipawns lost compared to the best move (always >= 0)
  /// - [evalBefore]: Position evaluation before the move (centipawns,
  ///   positive = White advantage)
  /// - [evalAfter]: Position evaluation after the move (centipawns,
  ///   positive = White advantage)
  /// - [isOnlyMove]: Whether this is the only move that doesn't
  ///   significantly worsen the position
  /// - [isSacrifice]: Whether the move involves giving up material
  ///   (temporarily or permanently)
  /// - [isBookMove]: Whether this is a known opening book move
  /// - [alternatives]: List of engine's MultiPV lines (alternative
  ///   candidate moves with their evaluations)
  /// - [isWhite]: Whether the moving player is White
  ///
  /// Returns the appropriate [MoveClassification].
  static MoveClassification classify({
    required int cpLoss,
    required int evalBefore,
    required int evalAfter,
    required bool isOnlyMove,
    required bool isSacrifice,
    required bool isBookMove,
    required List<EngineLine> alternatives,
    bool isWhite = true,
  }) {
    // -----------------------------------------------------------------------
    // Step 1: Book move check
    // حركة كتابية - من نظرية الافتتاحيات
    // Book moves are classified separately and take priority.
    // -----------------------------------------------------------------------
    if (isBookMove) {
      return MoveClassification.book;
    }

    // -----------------------------------------------------------------------
    // Step 2: Compute evaluation from the moving player's perspective
    // حساب التقييم من وجهة نظر اللاعب المتحرك
    // -----------------------------------------------------------------------
    final int playerEvalBefore = isWhite ? evalBefore : -evalBefore;
    final int playerEvalAfter = isWhite ? evalAfter : -evalAfter;

    // -----------------------------------------------------------------------
    // Step 3: Brilliant move check
    // حركة رائعة - التضحية الوحيدة التي تنقذ الموقف
    //
    // A Brilliant move (♪) must satisfy ALL of the following:
    //   1. It involves a sacrifice (giving up material)
    //   2. It is the ONLY move that doesn't lose (isOnlyMove = true)
    //      OR it's the only move within greatMoveThreshold of the best
    //   3. The resulting position has a positive eval (from player's view)
    //   4. cpLoss is minimal (within bestMoveThreshold of engine's choice)
    //
    // Rationale: A brilliant move is one where the player finds the
    // unique solution to a difficult position, and that solution
    // involves a non-obvious sacrifice.
    // -----------------------------------------------------------------------
    if (_isBrilliant(
      cpLoss: cpLoss,
      playerEvalAfter: playerEvalAfter,
      playerEvalBefore: playerEvalBefore,
      isOnlyMove: isOnlyMove,
      isSacrifice: isSacrifice,
      alternatives: alternatives,
    )) {
      return MoveClassification.brilliant;
    }

    // -----------------------------------------------------------------------
    // Step 4: Blunder check
    // خطأ فادح - خسارة كبيرة جداً تغير مسار اللعبة
    //
    // A Blunder (??) occurs when:
    //   1. cpLoss >= blunderThreshold (3+ pawns lost), OR
    //   2. The move changes the evaluation from winning to losing:
    //      - evalBefore was winning (>= winningEvalThreshold for player)
    //        AND evalAfter is losing (<= losingEvalThreshold for player)
    //      This captures "game-changing" errors even if cpLoss is
    //      technically less than the threshold.
    //   3. Special case: going from a large advantage to a much smaller
    //      one (winning advantage halved or more) can also be a blunder
    //      if the cpLoss is significant enough.
    // -----------------------------------------------------------------------
    if (_isBlunder(
      cpLoss: cpLoss,
      playerEvalBefore: playerEvalBefore,
      playerEvalAfter: playerEvalAfter,
      alternatives: alternatives,
    )) {
      return MoveClassification.blunder;
    }

    // -----------------------------------------------------------------------
    // Step 5: Missed Win check
    // فوز ضائع - تفويت حركة كانت ستحسم المباراة
    //
    // A Missed Win (∓) occurs when:
    //   1. The move doesn't lose material (cpLoss < mistakeThreshold)
    //   2. BUT there was a winning move available that would give a
    //      decisive advantage
    //   3. The eval swing between the best move and the played move
    //      is at least missedWinThreshold (2+ pawns)
    //   4. The best move would lead to a winning position, but the
    //      played move leads to a non-winning (drawing or equal) position
    //
    // Key distinction from blunder: a missed win doesn't actively lose
    // material; it just fails to capitalize on a winning opportunity.
    // -----------------------------------------------------------------------
    if (_isMissedWin(
      cpLoss: cpLoss,
      playerEvalBefore: playerEvalBefore,
      playerEvalAfter: playerEvalAfter,
      alternatives: alternatives,
    )) {
      return MoveClassification.missedWin;
    }

    // -----------------------------------------------------------------------
    // Step 6: Mistake check
    // خطأ - خسارة كبيرة في التقييم
    //
    // A Mistake (?) occurs when:
    //   cpLoss is between mistakeThreshold (1.5 pawns) and
    //   blunderThreshold (3.0 pawns).
    //   OR the move changes from winning/slightly better to equal/worse
    //   (significant but not game-changing loss).
    // -----------------------------------------------------------------------
    if (_isMistake(
      cpLoss: cpLoss,
      playerEvalBefore: playerEvalBefore,
      playerEvalAfter: playerEvalAfter,
    )) {
      return MoveClassification.mistake;
    }

    // -----------------------------------------------------------------------
    // Step 7: Inaccuracy check
    // عدم دقة - خسارة طفيفة في التقييم
    //
    // An Inaccuracy (?!) occurs when:
    //   cpLoss is between inaccuracyThreshold (0.5 pawns) and
    //   mistakeThreshold (1.5 pawns).
    //   The move is suboptimal but not catastrophically wrong.
    // -----------------------------------------------------------------------
    if (_isInaccuracy(
      cpLoss: cpLoss,
      playerEvalBefore: playerEvalBefore,
      playerEvalAfter: playerEvalAfter,
    )) {
      return MoveClassification.inaccuracy;
    }

    // -----------------------------------------------------------------------
    // Step 8: Best move check
    // أفضل حركة - اختيار المحرك الأول
    //
    // A Best move (!!) is the engine's top choice. It matches when:
    //   1. cpLoss is within bestMoveThreshold (0.1 pawns = 10 cp) of
    //      the engine's first choice, OR
    //   2. The played move matches the first MultiPV line exactly
    // -----------------------------------------------------------------------
    if (_isBestMove(cpLoss: cpLoss, alternatives: alternatives)) {
      return MoveClassification.best;
    }

    // -----------------------------------------------------------------------
    // Step 9: Great move check
    // حركة ممتازة - من أفضل الحركات المتاحة
    //
    // A Great move (!) is one of the top moves available:
    //   1. cpLoss is within greatMoveThreshold (0.5 pawns = 50 cp), AND
    //   2. The move is among the top 3 engine lines, AND
    //   3. The eval is maintained or improved (from player's perspective)
    //
    // Special case: a move that saves a losing position when most other
    // moves would lose is also classified as Great.
    // -----------------------------------------------------------------------
    if (_isGreatMove(
      cpLoss: cpLoss,
      playerEvalBefore: playerEvalBefore,
      playerEvalAfter: playerEvalAfter,
      isOnlyMove: isOnlyMove,
      alternatives: alternatives,
    )) {
      return MoveClassification.great;
    }

    // -----------------------------------------------------------------------
    // Step 10: Default - Good move
    // حركة جيدة - معقولة لكن ليست المثالية
    //
    // If none of the above classifications apply, the move is "Good".
    // This means it's a reasonable move within goodMoveThreshold
    // (1.5 pawns) of the best move but doesn't meet the stricter
    // criteria for Best or Great.
    // -----------------------------------------------------------------------
    return MoveClassification.good;
  }

  // ===========================================================================
  // PRIVATE HELPER METHODS - Individual classification checks
  // ===========================================================================

  /// فحص الحركة الرائعة - Check if the move is Brilliant
  ///
  /// A Brilliant move must satisfy:
  /// 1. Involves a sacrifice (isSacrifice = true)
  /// 2. Is the only move that maintains a good position, verified by:
  ///    a. isOnlyMove flag is true, OR
  ///    b. All alternative moves are at least onlyMoveThreshold worse
  /// 3. The resulting position is positive (from the player's view)
  /// 4. cpLoss is within bestMoveThreshold (nearly the best move)
  static bool _isBrilliant({
    required int cpLoss,
    required int playerEvalAfter,
    required int playerEvalBefore,
    required bool isOnlyMove,
    required bool isSacrifice,
    required List<EngineLine> alternatives,
  }) {
    // الشرط الأول: يجب أن تكون الحركة تضحية
    if (!isSacrifice) return false;

    // الشرط الثاني: يجب أن تكون الحركة جيدة تقريباً (فقد ضئيل)
    if (cpLoss > bestMoveThreshold) return false;

    // الشرط الثالث: النتيجة يجب أن تكون إيجابية من وجهة نظر اللاعب
    if (playerEvalAfter < equalEvalThreshold) return false;

    // الشرط الرابع: يجب أن تكون "الحركة الوحيدة"
    // التحقق من أن جميع البدائل أسوأ بكثير
    bool onlyNonLosingMove = isOnlyMove;

    if (!onlyNonLosingMove && alternatives.length >= 2) {
      // حساب الفرق بين الحركة الأولى والثانية
      final sortedAlternatives = _sortedByEval(alternatives);
      if (sortedAlternatives.length >= 2) {
        final bestEval = sortedAlternatives[0].effectiveEvalCp;
        final secondBestEval = sortedAlternatives[1].effectiveEvalCp;
        final gap = (bestEval - secondBestEval).abs();

        // إذا كان الفرق بين الأفضل والثاني كبير جداً
        // فالحركة الأولى هي "الوحيدة" عملياً
        onlyNonLosingMove = gap >= onlyMoveThreshold;
      }
    }

    if (!onlyNonLosingMove) return false;

    // شرط إضافي: الوضعية قبل الحركة يجب أن تكون صعبة
    // (إما متساوية أو اللاعب متأخر قليلاً)
    // هذا يمنع تصنيف التضحيات في وضعيات رابحة بسهولة كـ "رائعة"
    // لا نشترط هذا بشدة لأن التضحية قد تكون رائعة حتى في وضعية جيدة
    // لكنها أكثر إثارة للإعجاب في وضعيات صعبة

    return true;
  }

  /// فحص الخطأ الفادح - Check if the move is a Blunder
  ///
  /// A Blunder occurs when:
  /// 1. cpLoss >= blunderThreshold (3+ pawns), OR
  /// 2. The position goes from winning to losing, OR
  /// 3. The position goes from equal/drawn to clearly losing, AND
  ///    the cpLoss is at least mistakeThreshold
  static bool _isBlunder({
    required int cpLoss,
    required int playerEvalBefore,
    required int playerEvalAfter,
    required List<EngineLine> alternatives,
  }) {
    // الشرط الأول: فقد أكثر من 3 بيدق
    if (cpLoss >= blunderThreshold) {
      return true;
    }

    // الشرط الثاني: التحول من وضعية رابحة إلى وضعية خاسرة
    // كان اللاعب يربح (تقييم >= 2 بيدق) وأصبح يخسر (تقييم <= -2 بيدق)
    if (playerEvalBefore >= winningEvalThreshold &&
        playerEvalAfter <= losingEvalThreshold) {
      return true;
    }

    // الشرط الثالث: التحول من أفضلية كبيرة إلى وضعية متساوية أو خاسرة
    // إذا كان التقييم >= 3 بيدق وأصبح <= 0 بيدق
    if (playerEvalBefore >= blunderThreshold &&
        playerEvalAfter <= 0) {
      return true;
    }

    // الشرط الرابع: فقدان كش مات محقق
    // إذا كانت البدائل تتضمن كش مات والحركة المختارة لا تحققه
    if (alternatives.isNotEmpty) {
      final bestAlternative = _sortedByEval(alternatives).first;
      if (bestAlternative.isMate &&
          bestAlternative.mateIn != null &&
          bestAlternative.mateIn! > 0) {
        // أفضل حركة تعطي كش مات
        // لكن اللاعب لم يخترها
        // هذا خطأ فادح إذا كان الفقد كبيراً
        if (cpLoss >= mistakeThreshold) {
          return true;
        }
      }
    }

    return false;
  }

  /// فحص الفوز الضائع - Check if the move is a Missed Win
  ///
  /// A Missed Win occurs when:
  /// 1. The player doesn't lose material (cpLoss < mistakeThreshold)
  /// 2. The best move would have given a winning advantage
  /// 3. The played move results in a non-winning (drawing/equal) position
  /// 4. The eval swing between best and played move is >= missedWinThreshold
  static bool _isMissedWin({
    required int cpLoss,
    required int playerEvalBefore,
    required int playerEvalAfter,
    required List<EngineLine> alternatives,
  }) {
    // الشرط الأول: لا يجب أن يكون الخطأ كبيراً جداً
    // (الأخطاء الكبيرة تصنف كـ blunder أو mistake)
    if (cpLoss >= mistakeThreshold) return false;

    // الشرط الثاني: يجب أن يكون الفقد كافياً (على الأقل 2 بيدق)
    if (cpLoss < missedWinThreshold) return false;

    // الشرط الثالث: أفضل حركة كانت ستعطي أفضلية حاسمة
    // والحركة المختارة لم تحافظ على الفوز
    bool bestMoveWasWinning = false;
    bool playedMoveNotWinning = false;

    // التحقق من أن أفضل حركة كانت رابحة
    if (alternatives.isNotEmpty) {
      final bestAlternative = _sortedByEval(alternatives).first;
      final bestEvalForPlayer = bestAlternative.effectiveEvalCp;
      bestMoveWasWinning = bestEvalForPlayer >= winningEvalThreshold;
    } else {
      // بدون بدائل، نحسب من cpLoss + playerEvalAfter
      final impliedBestEval = playerEvalAfter + cpLoss;
      bestMoveWasWinning = impliedBestEval >= winningEvalThreshold;
    }

    // الحركة المختارة لا تحافظ على الوضعية الرابحة
    playedMoveNotWinning = playerEvalAfter < winningEvalThreshold;

    return bestMoveWasWinning && playedMoveNotWinning;
  }

  /// فحص الخطأ - Check if the move is a Mistake
  ///
  /// A Mistake occurs when cpLoss is between mistakeThreshold and
  /// blunderThreshold (1.5 - 3.0 pawns lost).
  static bool _isMistake({
    required int cpLoss,
    required int playerEvalBefore,
    required int playerEvalAfter,
  }) {
    // الشرط الأساسي: فقد 1.5 - 3.0 بيدق
    if (cpLoss >= mistakeThreshold && cpLoss < blunderThreshold) {
      return true;
    }

    // شرط إضافي: التحول من وضعية أفضلية إلى وضعية متساوية
    // مع فقد كبير (ولكن ليس كافياً لـ blunder)
    if (playerEvalBefore >= winningEvalThreshold &&
        playerEvalAfter > losingEvalThreshold &&
        playerEvalAfter <= equalEvalThreshold &&
        cpLoss >= mistakeThreshold) {
      return true;
    }

    return false;
  }

  /// فحص عدم الدقة - Check if the move is an Inaccuracy
  ///
  /// An Inaccuracy occurs when cpLoss is between inaccuracyThreshold
  /// and mistakeThreshold (0.5 - 1.5 pawns lost).
  static bool _isInaccuracy({
    required int cpLoss,
    required int playerEvalBefore,
    required int playerEvalAfter,
  }) {
    // الشرط الأساسي: فقد 0.5 - 1.5 بيدق
    if (cpLoss >= inaccuracyThreshold && cpLoss < mistakeThreshold) {
      return true;
    }

    return false;
  }

  /// فحص أفضل حركة - Check if the move is Best
  ///
  /// A Best move matches the engine's top choice or is within
  /// bestMoveThreshold (0.1 pawns = 10 cp) of the best eval.
  static bool _isBestMove({
    required int cpLoss,
    required List<EngineLine> alternatives,
  }) {
    // cpLoss قريب جداً من الصفر = اختيار المحرك الأول
    if (cpLoss <= bestMoveThreshold) {
      return true;
    }

    return false;
  }

  /// فحص الحركة الممتازة - Check if the move is Great
  ///
  /// A Great move is one of the top moves:
  /// 1. cpLoss is within greatMoveThreshold (0.5 pawns = 50 cp)
  /// 2. The eval is maintained or improved
  /// 3. OR: the move saves a losing position when most moves would lose
  static bool _isGreatMove({
    required int cpLoss,
    required int playerEvalBefore,
    required int playerEvalAfter,
    required bool isOnlyMove,
    required List<EngineLine> alternatives,
  }) {
    // الشرط الأول: الحركة ضمن أفضل 0.5 بيدق من المحرك
    if (cpLoss <= greatMoveThreshold) {
      // تحقق إضافي: الحركة ضمن أفضل 3 خطوط للمحرك
      if (alternatives.length <= 3 || _isInTopNMoves(alternatives, 3)) {
        return true;
      }
    }

    // الشرط الثاني: الحركة أنقذت وضعية خاسرة
    // معظم الحركات كانت ستجعل الوضعية أسوأ، لكن هذه الحركة حافظت عليها
    if (isOnlyMove && playerEvalAfter >= losingEvalThreshold) {
      // اللاعب كان في وضعية صعبة ووجد الحركة الوحيدة التي تنقذ الموقف
      // لكنها ليست brilliant لأنها لا تتضمن تضحية
      if (playerEvalBefore <= equalEvalThreshold) {
        return true;
      }
    }

    // شرط إضافي: الحركة حافظت على أفضلية كبيرة
    // (تحويل وضعية رابحة إلى وضعية رابحة بنفس القوة أو أقوى بقليل)
    if (cpLoss <= greatMoveThreshold &&
        playerEvalBefore >= winningEvalThreshold &&
        playerEvalAfter >= winningEvalThreshold) {
      return true;
    }

    return false;
  }

  // ===========================================================================
  // ACCURACY CALCULATIONS
  // ===========================================================================

  /// حساب دقة الحركة الواحدة - Calculate accuracy for a single move
  ///
  /// Uses Chess.com's published formula:
  ///   accuracy = 103.1667 * exp(-0.0437 * cpLoss) - 3.1667
  ///
  /// This produces:
  ///   cpLoss = 0   → accuracy ≈ 100.0%
  ///   cpLoss = 10  → accuracy ≈ 95.5%
  ///   cpLoss = 25  → accuracy ≈ 89.6%
  ///   cpLoss = 50  → accuracy ≈ 81.2%
  ///   cpLoss = 100 → accuracy ≈ 64.6%
  ///   cpLoss = 200 → accuracy ≈ 38.3%
  ///   cpLoss = 300 → accuracy ≈ 20.1%
  ///   cpLoss = 500 → accuracy ≈ 2.7%
  ///   cpLoss = 600+→ accuracy ≈ 0.0%
  ///
  /// The result is clamped to [0, 100].
  static double calculateAccuracy(int cpLoss) {
    // معادلة Chess.com لحساب الدقة
    // accuracy = 103.1667 * e^(-0.0437 * cpLoss) - 3.1667
    const double a = 103.1667;
    const double b = -0.0437;
    const double c = -3.1667;

    final double accuracy = a * exp(b * cpLoss) + c;

    // تقييد النتيجة بين 0 و 100
    return accuracy.clamp(0.0, 100.0);
  }

  /// حساب دقة المباراة الكاملة - Calculate overall game accuracy
  ///
  /// Computes the weighted average accuracy across all moves for
  /// a single player. Each move's accuracy is calculated individually,
  /// then averaged. The formula weights all moves equally.
  ///
  /// Special handling:
  /// - Moves with cpLoss = 0 (perfect moves) contribute 100%
  /// - Book moves are included with cpLoss = 0
  /// - The first few moves may be weighted differently if desired
  ///
  /// Returns a value between 0 and 100.
  static double calculateGameAccuracy(List<int> cpLosses) {
    if (cpLosses.isEmpty) return 100.0;

    double totalAccuracy = 0.0;
    for (final cpLoss in cpLosses) {
      totalAccuracy += calculateAccuracy(cpLoss);
    }

    final double avgAccuracy = totalAccuracy / cpLosses.length;
    return avgAccuracy.clamp(0.0, 100.0);
  }

  /// حساب الدقة المرجحة - Calculate weighted game accuracy
  ///
  /// Unlike the simple average, this gives more weight to moves
  /// in critical positions (where the eval was close to 0).
  /// Moves in already-decided positions have less impact.
  ///
  /// The weight for each move is calculated as:
  ///   weight = 1.0 / (1.0 + abs(evalBefore) / 200.0)
  ///
  /// This means:
  /// - Equal position (eval = 0): weight = 1.0
  /// - Slight advantage (eval = 100): weight = 0.67
  /// - Large advantage (eval = 400): weight = 0.33
  static double calculateWeightedGameAccuracy(
    List<int> cpLosses,
    List<int> evalsBefore,
  ) {
    assert(cpLosses.length == evalsBefore.length,
        'cpLosses and evalsBefore must have the same length');

    if (cpLosses.isEmpty) return 100.0;

    double totalWeightedAccuracy = 0.0;
    double totalWeight = 0.0;

    for (int i = 0; i < cpLosses.length; i++) {
      final double moveAccuracy = calculateAccuracy(cpLosses[i]);
      final double weight = 1.0 / (1.0 + (evalsBefore[i].abs() / 200.0));

      totalWeightedAccuracy += moveAccuracy * weight;
      totalWeight += weight;
    }

    if (totalWeight == 0) return 100.0;
    final double weightedAvg = totalWeightedAccuracy / totalWeight;
    return weightedAvg.clamp(0.0, 100.0);
  }

  // ===========================================================================
  // GAME PHASE DETECTION
  // ===========================================================================

  /// تحديد مرحلة اللعبة - Determine game phase from FEN
  ///
  /// Uses material count to classify the game phase:
  ///
  /// - Opening: Both sides have most of their material and the king
  ///   hasn't castled or just castled. Typically the first 10-15 moves.
  ///
  /// - Middlegame: Pieces are developed, tactical play begins.
  ///   At least queens or rooks are still on the board.
  ///
  /// - Endgame: Most pieces have been exchanged. Characterized by
  ///   few pieces remaining (typically just kings + pawns + 1-2 minor pieces).
  ///
  /// Material values (for phase calculation):
  ///   Pawn = 1, Knight = 3, Bishop = 3, Rook = 5, Queen = 9
  ///
  /// Phase thresholds:
  ///   Total material > 52 → Opening (full armies)
  ///   Total material 26-52 → Middlegame
  ///   Total material < 26 → Endgame
  static GamePhase determineGamePhase(String fen) {
    // استخراج جزء القطع من FEN (الجزء الأول قبل المسافة)
    final piecePlacement = fen.split(' ').first;

    int whiteMaterial = 0;
    int blackMaterial = 0;

    for (final char in piecePlacement.split('')) {
      switch (char) {
        // قطع الأبيض (أحرف كبيرة)
        case 'P':
          whiteMaterial += 1;
        case 'N':
          whiteMaterial += 3;
        case 'B':
          whiteMaterial += 3;
        case 'R':
          whiteMaterial += 5;
        case 'Q':
          whiteMaterial += 9;
        // قطع الأسود (أحرف صغيرة)
        case 'p':
          blackMaterial += 1;
        case 'n':
          blackMaterial += 3;
        case 'b':
          blackMaterial += 3;
        case 'r':
          blackMaterial += 5;
        case 'q':
          blackMaterial += 9;
      }
    }

    final totalMaterial = whiteMaterial + blackMaterial;

    // عتبات تحديد المرحلة
    // الوضعية المبدئية: 8*1 + 2*3 + 2*3 + 2*5 + 1*9 = 39 لكل لاعب = 78 إجمالي
    if (totalMaterial > 52) {
      return GamePhase.opening;
    } else if (totalMaterial > 26) {
      return GamePhase.middlegame;
    } else {
      return GamePhase.endgame;
    }
  }

  /// تحديد مرحلة اللعبة من عدد الحركات والقطع
  /// Determine game phase from move count and piece counts
  ///
  /// Alternative method that considers both move count and material.
  /// More accurate than FEN-only for games with unusual development.
  static GamePhase determineGamePhaseFromContext({
    required int fullMoveNumber,
    required int whitePieceCount,
    required int blackPieceCount,
    required bool whiteHasCastled,
    required bool blackHasCastled,
  }) {
    final totalPieces = whitePieceCount + blackPieceCount;

    // الافتتاح: الحركات الأولى مع تطوير القطع
    // بشكل عام أول 10-15 حركة كاملة
    if (fullMoveNumber <= 10 && totalPieces >= 24) {
      // لا يزال لدى اللاعبين معظم القطع
      return GamePhase.opening;
    }

    // النهاية: عدد قليل من القطع
    if (totalPieces <= 10) {
      return GamePhase.endgame;
    }

    // منتصف اللعبة: الحالة الافتراضية
    return GamePhase.middlegame;
  }

  // ===========================================================================
  // SACRIFICE DETECTION
  // ===========================================================================

  /// كشف التضحية - Detect if a move involves a sacrifice
  ///
  /// A sacrifice is detected when:
  /// 1. The move gives up material (capture by opponent is possible
  ///    and the captured piece is more valuable), OR
  /// 2. The move puts a piece on a square where it can be captured
  ///    without immediate recapture, AND
  /// 3. The engine's evaluation after the sacrifice is positive
  ///    (the sacrifice is justified by compensation)
  ///
  /// This method uses material counting on the board before and after
  /// the move, combined with the engine's PV analysis.
  static bool detectSacrifice({
    required String fenBefore,
    required String fenAfter,
    required int evalAfter,
    required bool isWhite,
    required String uciMove,
  }) {
    final int materialBefore = _countMaterial(fenBefore, isWhite);
    final int materialAfter = _countMaterial(fenAfter, isWhite);

    // الفقد المادي بعد الحركة
    final int materialLoss = materialBefore - materialAfter;

    // إذا فقد اللاعب مادة (بيدق أو أكثر)
    if (materialLoss >= 1) {
      // لكن التقييم بعد الحركة لا يزال إيجابياً أو متساوياً
      // من وجهة نظر اللاعب
      final int playerEval = isWhite ? evalAfter : -evalAfter;
      if (playerEval >= -equalEvalThreshold) {
        return true;
      }
    }

    return false;
  }

  /// حساب المادة - Count material value for one side from FEN
  static int _countMaterial(String fen, bool forWhite) {
    final piecePlacement = fen.split(' ').first;
    int material = 0;

    for (final char in piecePlacement.split('')) {
      if (forWhite) {
        switch (char) {
          case 'P':
            material += 1;
          case 'N':
            material += 3;
          case 'B':
            material += 3;
          case 'R':
            material += 5;
          case 'Q':
            material += 9;
        }
      } else {
        switch (char) {
          case 'p':
            material += 1;
          case 'n':
            material += 3;
          case 'b':
            material += 3;
          case 'r':
            material += 5;
          case 'q':
            material += 9;
        }
      }
    }

    return material;
  }

  // ===========================================================================
  // ONLY-MOVE DETECTION
  // ===========================================================================

  /// كشف الحركة الوحيدة - Detect if the move is the only non-losing option
  ///
  /// A move is considered "only" when:
  /// 1. The gap between the best move and the second-best move
  ///    is at least onlyMoveThreshold (2 pawns = 200 cp), OR
  /// 2. The best move maintains the position but all alternatives
  ///    make it significantly worse (losing or much worse)
  ///
  /// This is important for Brilliant classification because finding
  /// the only good move in a difficult position is exceptional.
  static bool detectOnlyMove({
    required List<EngineLine> alternatives,
    required int evalAfter,
    required bool isWhite,
  }) {
    if (alternatives.length < 2) return true; // لا توجد بدائل كافية

    final sorted = _sortedByEval(alternatives, forWhite: isWhite);

    if (sorted.length < 2) return true;

    final bestEval = sorted[0].effectiveEvalCp;
    final secondBestEval = sorted[1].effectiveEvalCp;

    // حساب الفرق مع مراعاة اتجاه اللاعب
    final int gap;
    if (isWhite) {
      gap = bestEval - secondBestEval;
    } else {
      gap = secondBestEval - bestEval;
    }

    // إذا كان الفرق كبيراً جداً بين الأفضل والثاني
    return gap >= onlyMoveThreshold;
  }

  // ===========================================================================
  // UTILITY METHODS
  // ===========================================================================

  /// ترتيب خطوط المحرك حسب التقييم - Sort engine lines by evaluation
  ///
  /// Lines are sorted from best to worst.
  /// For White, higher eval = better; for Black, lower eval = better.
  static List<EngineLine> _sortedByEval(
    List<EngineLine> lines, {
    bool forWhite = true,
  }) {
    final sorted = List<EngineLine>.from(lines);
    sorted.sort((a, b) {
      final evalA = a.effectiveEvalCp;
      final evalB = b.effectiveEvalCp;
      // للأبيض: الترتيب تنازلي (الأعلى أولاً)
      // للأسود: الترتيب تصاعدي (الأدنى أولاً)
      return forWhite ? evalB.compareTo(evalA) : evalA.compareTo(evalB);
    });
    return sorted;
  }

  /// فحص هل الحركة ضمن أفضل N حركات
  /// Check if the played move is among the top N engine lines
  static bool _isInTopNMoves(List<EngineLine> alternatives, int n) {
    // إذا كان عدد البدائل أقل من أو يساوي N
    // فكل الحركات ضمن أفضل N
    return alternatives.length <= n;
  }

  /// حساب فقد السنتيبيدق - Calculate centipawn loss
  ///
  /// cpLoss = max(0, bestEval - playedMoveEval)
  /// Always returns a non-negative value.
  /// From the moving player's perspective.
  static int calculateCpLoss({
    required int evalBefore,
    required int evalAfter,
    required bool isWhite,
  }) {
    // تقييم أفضل حركة ممكنة = التقييم قبل الحركة (من وجهة نظر الأبيض)
    // نحتاج لتحويل التقييم لوجهة نظر اللاعب
    final int playerEvalBefore = isWhite ? evalBefore : -evalBefore;
    final int playerEvalAfter = isWhite ? evalAfter : -evalAfter;

    // الفقد = التقييم قبل الحركة - التقييم بعد الحركة
    // (من وجهة نظر اللاعب: إيجابي يعني فقد)
    final int loss = playerEvalBefore - playerEvalAfter;

    // لا يمكن أن يكون الفقد سلبياً (يعني الحركة حسّنت التقييم أكثر من المتوقع)
    return loss > 0 ? loss : 0;
  }

  /// حساب فقد السنتيبيدق من خطوط MultiPV
  /// Calculate cpLoss from MultiPV lines
  ///
  /// When MultiPV data is available, cpLoss is the difference
  /// between the best line's eval and the played move's eval.
  static int calculateCpLossFromMultiPV({
    required List<EngineLine> alternatives,
    required String playedUci,
    required bool isWhite,
  }) {
    if (alternatives.isEmpty) return 0;

    // ترتيب الخطوط
    final sorted = _sortedByEval(alternatives, forWhite: isWhite);
    final bestEval = sorted.first.effectiveEvalCp;

    // البحث عن خط الحركة المختارة
    EngineLine? playedLine;
    for (final line in alternatives) {
      if (line.uciMove == playedUci) {
        playedLine = line;
        break;
      }
    }

    if (playedLine == null) {
      // الحركة غير موجودة في خطوط MultiPV
      // هذا يعني أنها ليست ضمن أفضل N حركات
      // نستخدم أسوأ تقييم متاح كتقدير
      final worstEval = sorted.last.effectiveEvalCp;
      final int loss;
      if (isWhite) {
        loss = bestEval - worstEval;
      } else {
        loss = worstEval - bestEval;
      }
      return loss > 0 ? loss : 0;
    }

    final playedEval = playedLine.effectiveEvalCp;
    final int loss;
    if (isWhite) {
      loss = bestEval - playedEval;
    } else {
      loss = playedEval - bestEval;
    }

    return loss > 0 ? loss : 0;
  }

  // ===========================================================================
  // ANALYSIS SUMMARY GENERATION
  // ===========================================================================

  /// إنشاء ملخص التحليل - Generate analysis summary from moves
  ///
  /// Processes all analyzed moves to produce aggregated statistics
  /// including accuracy, classification counts, and notable moments.
  static AnalysisSummary generateSummary(List<AnalyzedMove> moves) {
    // فصل حركات الأبيض والأسود
    final whiteMoves = moves.where((m) => m.color.isWhite).toList();
    final blackMoves = moves.where((m) => m.color != PlayerColor.white).toList();

    // حساب الدقة
    final whiteAccuracy = calculateGameAccuracy(
      whiteMoves.map((m) => m.cpLoss).toList(),
    );
    final blackAccuracy = calculateGameAccuracy(
      blackMoves.map((m) => m.cpLoss).toList(),
    );

    // عد التصنيفات
    final whiteClassCounts = _countClassifications(whiteMoves);
    final blackClassCounts = _countClassifications(blackMoves);

    // متوسط الفقد
    final whiteAvgCpLoss = whiteMoves.isEmpty
        ? 0.0
        : whiteMoves.map((m) => m.cpLoss).reduce((a, b) => a + b) /
            whiteMoves.length;
    final blackAvgCpLoss = blackMoves.isEmpty
        ? 0.0
        : blackMoves.map((m) => m.cpLoss).reduce((a, b) => a + b) /
            blackMoves.length;

    // أسوأ حركة
    AnalyzedMove? worstMove;
    int maxCpLoss = 0;
    for (final move in moves) {
      if (move.cpLoss > maxCpLoss) {
        maxCpLoss = move.cpLoss;
        worstMove = move;
      }
    }

    // أفضل حركة (أقل فقد مع تصنيف مميز)
    AnalyzedMove? bestAnalyzedMove;
    for (final move in moves) {
      if (move.classification == MoveClassification.brilliant ||
          move.classification == MoveClassification.great) {
        if (bestAnalyzedMove == null ||
            move.cpLoss < bestAnalyzedMove.cpLoss) {
          bestAnalyzedMove = move;
        }
      }
    }

    // نقطة التحول
    AnalyzedMove? turningPointMove;
    int biggestEvalSwing = 0;
    for (int i = 1; i < moves.length; i++) {
      final swing = (moves[i].evalAfter - moves[i - 1].evalAfter).abs();
      if (swing > biggestEvalSwing && moves[i].classification.isError) {
        biggestEvalSwing = swing;
        turningPointMove = moves[i];
      }
    }

    // عد الحركات في كل مرحلة
    final phaseCounts = <GamePhase, int>{
      GamePhase.opening: 0,
      GamePhase.middlegame: 0,
      GamePhase.endgame: 0,
    };
    for (final move in moves) {
      phaseCounts[move.phase] = (phaseCounts[move.phase] ?? 0) + 1;
    }

    return AnalysisSummary(
      whiteAccuracy: whiteAccuracy,
      blackAccuracy: blackAccuracy,
      whiteClassificationCounts: whiteClassCounts,
      blackClassificationCounts: blackClassCounts,
      whiteAvgCpLoss: whiteAvgCpLoss,
      blackAvgCpLoss: blackAvgCpLoss,
      worstMove: worstMove,
      bestMove: bestAnalyzedMove,
      turningPointMove: turningPointMove,
      phaseMoveCounts: phaseCounts,
    );
  }

  /// عد التصنيفات في قائمة الحركات
  static Map<MoveClassification, int> _countClassifications(
    List<AnalyzedMove> moves,
  ) {
    final counts = <MoveClassification, int>{
      for (final c in MoveClassification.values) c: 0,
    };

    for (final move in moves) {
      counts[move.classification] = (counts[move.classification] ?? 0) + 1;
    }

    return counts;
  }

  // ===========================================================================
  // EVAL INTERPRETATION HELPERS
  // ===========================================================================

  /// تفسير التقييم - Interpret centipawn evaluation in Arabic
  ///
  /// Converts a raw centipawn value into a human-readable
  /// Arabic description of the position's evaluation.
  static String interpretEval(int evalCp, {bool isMate = false, int? mateIn}) {
    if (isMate && mateIn != null) {
      if (mateIn > 0) {
        return 'كش مات للأبيض خلال $mateIn حركة';
      } else {
        return 'كش مات للأسود خلال ${mateIn.abs()} حركة';
      }
    }

    final double pawns = evalCp / cpPerPawn;

    if (pawns.abs() < 0.3) {
      return 'وضعية متساوية';
    } else if (pawns > 0 && pawns < 1) {
      return 'أفضلية طفيفة للأبيض';
    } else if (pawns >= 1 && pawns < 2) {
      return 'أفضلية للأبيض';
    } else if (pawns >= 2 && pawns < 4) {
      return 'أفضلية كبيرة للأبيض';
    } else if (pawns >= 4) {
      return 'أفضلية حاسمة للأبيض';
    } else if (pawns < 0 && pawns > -1) {
      return 'أفضلية طفيفة للأسود';
    } else if (pawns <= -1 && pawns > -2) {
      return 'أفضلية للأسود';
    } else if (pawns <= -2 && pawns > -4) {
      return 'أفضلية كبيرة للأسود';
    } else {
      return 'أفضلية حاسمة للأسود';
    }
  }

  /// تنسيق عرض التقييم - Format evaluation for display
  ///
  /// Returns a short string like "+1.5", "-0.3", "M3" (mate in 3)
  static String formatEval(int evalCp, {bool isMate = false, int? mateIn}) {
    if (isMate && mateIn != null) {
      return 'M${mateIn.abs()}';
    }
    final double pawns = evalCp / cpPerPawn;
    final sign = pawns >= 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(1)}';
  }

  /// حساب أفضلية اللاعب - Calculate player's advantage
  ///
  /// Returns a descriptive string of the player's current advantage
  /// in Arabic, from the specified player's perspective.
  static String describePlayerAdvantage({
    required int evalCp,
    required bool isWhite,
    required bool isMate,
    required int? mateIn,
  }) {
    // تحويل التقييم لوجهة نظر اللاعب
    final int playerEval = isWhite ? evalCp : -evalCp;
    final bool playerIsMating = isMate &&
        mateIn != null &&
        ((isWhite && mateIn > 0) || (!isWhite && mateIn < 0));
    final int? playerMateIn = playerIsMating ? mateIn!.abs() : null;

    if (playerIsMating && playerMateIn != null) {
      return 'كش مات خلال $playerMateIn حركة';
    }

    final double pawns = playerEval / cpPerPawn;

    if (pawns.abs() < 0.3) return 'وضعية متساوية';
    if (pawns < 0 && pawns > -1) return 'تأخر طفيف';
    if (pawns >= 0 && pawns < 1) return 'أفضلية طفيفة';
    if (pawns >= 1 && pawns < 2) return 'أفضلية واضحة';
    if (pawns >= 2) return 'أفضلية كبيرة';
    if (pawns <= -1 && pawns > -2) return 'تأخر واضح';
    if (pawns <= -2) return 'وضعية صعبة';

    return 'وضعية غير محددة';
  }

  // ===========================================================================
  // CP LOSS TO VERDICT CONVERSION
  // ===========================================================================

  /// تحويل الفقد إلى حكم موجز - Convert cpLoss to a brief verdict
  ///
  /// Used for quick move annotations without full classification.
  static String cpLossToVerdict(int cpLoss) {
    if (cpLoss == 0) return 'مثالي';
    if (cpLoss <= bestMoveThreshold) return 'أفضل حركة';
    if (cpLoss <= greatMoveThreshold) return 'ممتاز';
    if (cpLoss <= goodMoveThreshold) return 'جيد';
    if (cpLoss < mistakeThreshold) return 'عدم دقة';
    if (cpLoss < blunderThreshold) return 'خطأ';
    return 'خطأ فادح';
  }
}
