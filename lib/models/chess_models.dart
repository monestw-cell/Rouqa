/// Ruq'a Chess Analyzer - Data Models
/// نماذج بيانات محلل الشطرنج رقعة
///
/// Complete data model layer for the chess analysis engine.
/// Includes all enums, value objects, and entity models needed
/// for move classification, game analysis, and puzzle generation.

import 'dart:math';

// ============================================================================
// ENUMS
// ============================================================================

/// تصنيف الحركة - Move classification (9 levels matching Chess.com/Lichess)
///
/// Each level represents a qualitative assessment of a move's strength
/// relative to the engine's evaluation. The classification considers
/// centipawn loss, positional context, sacrifice detection, and
/// whether the move is the only non-losing option.
enum MoveClassification {
  brilliant,
  great,
  best,
  good,
  book,
  inaccuracy,
  mistake,
  blunder,
  missedWin;

  /// الرمز المرئي لتصنيف الحركة
  /// Visual symbol displayed next to the move notation
  String get symbol => switch (this) {
        MoveClassification.brilliant => '♪',
        MoveClassification.great => '!',
        MoveClassification.best => '!!',
        MoveClassification.good => '✓',
        MoveClassification.book => '📚',
        MoveClassification.inaccuracy => '?!',
        MoveClassification.mistake => '?',
        MoveClassification.blunder => '??',
        MoveClassification.missedWin => '∓',
      };

  /// التسمية العربية للتصنيف
  /// Arabic label for this classification
  String get arabicLabel => switch (this) {
        MoveClassification.brilliant => 'رائع',
        MoveClassification.great => 'ممتاز',
        MoveClassification.best => 'أفضل حركة',
        MoveClassification.good => 'حركة جيدة',
        MoveClassification.book => 'حركة كتابية',
        MoveClassification.inaccuracy => 'عدم دقة',
        MoveClassification.mistake => 'خطأ',
        MoveClassification.blunder => 'خطأ فادح',
        MoveClassification.missedWin => 'فوز ضائع',
      };

  /// الوصف العربي المفصل للتصنيف
  /// Detailed Arabic description explaining what this classification means
  String get arabicDescription => switch (this) {
        MoveClassification.brilliant =>
          'حركة رائعة! التضحية الوحيدة التي تنقذ الموقف أو تحافظ على أفضل استمرارية',
        MoveClassification.great =>
          'حركة ممتازة! من أفضل الحركات المتاحة وتحافظ على التفوق',
        MoveClassification.best =>
          'أفضل حركة ممكنة! اختيار المحرك الأول',
        MoveClassification.good =>
          'حركة جيدة ومعقولة لكنها ليست المثالية',
        MoveClassification.book =>
          'حركة من نظرية الافتتاحيات المعروفة',
        MoveClassification.inaccuracy =>
          'عدم دقة! خسارة طفيفة في التقييم مقارنة بأفضل حركة',
        MoveClassification.mistake =>
          'خطأ! خسارة كبيرة في التقييم يمكن تجنبها',
        MoveClassification.blunder =>
          'خطأ فادح! خسارة كبيرة جداً تغير مسار اللعبة',
        MoveClassification.missedWin =>
          'فوز ضائع! تفويت حركة كانت ستحسم المباراة',
      };

  /// اللون المرئي للتصنيف (كود CSS سداسي عشري)
  /// Visual color for UI rendering (hex CSS color code)
  String get color => switch (this) {
        MoveClassification.brilliant => '#53B8EC',
        MoveClassification.great => '#56B870',
        MoveClassification.best => '#56B870',
        MoveClassification.good => '#A0A0A0',
        MoveClassification.book => '#A07030',
        MoveClassification.inaccuracy => '#E6B422',
        MoveClassification.mistake => '#E68A22',
        MoveClassification.blunder => '#E64545',
        MoveClassification.missedWin => '#E66DB4',
      };

  /// هل التصنيف يشير إلى خطأ؟
  /// Whether this classification indicates an error
  bool get isError => switch (this) {
        MoveClassification.inaccuracy => true,
        MoveClassification.mistake => true,
        MoveClassification.blunder => true,
        MoveClassification.missedWin => true,
        _ => false,
      };

  /// هل التصنيف يشير إلى حركة مميزة؟
  /// Whether this classification indicates a notable/good move
  bool get isNotable => switch (this) {
        MoveClassification.brilliant => true,
        MoveClassification.great => true,
        MoveClassification.best => true,
        _ => false,
      };

  /// ترتيب شدة التصنيف (للمقارنة)
  /// Severity ordering for comparison (lower = worse)
  int get severityIndex => switch (this) {
        MoveClassification.brilliant => 0,
        MoveClassification.great => 1,
        MoveClassification.best => 2,
        MoveClassification.good => 3,
        MoveClassification.book => 4,
        MoveClassification.inaccuracy => 5,
        MoveClassification.mistake => 6,
        MoveClassification.blunder => 7,
        MoveClassification.missedWin => 8,
      };

  /// تحويل من فهرس إلى تصنيف
  /// Create classification from index
  static MoveClassification fromIndex(int index) {
    if (index < 0 || index >= MoveClassification.values.length) {
      throw RangeError('Invalid MoveClassification index: $index');
    }
    return MoveClassification.values[index];
  }

  /// تحويل من الاسم الإنجليزي
  /// Create classification from English name string
  static MoveClassification? fromName(String name) {
    return MoveClassification.values.cast<MoveClassification?>().firstWhere(
          (e) => e?.name == name,
          orElse: () => null,
        );
  }
}

/// مرحلة اللعبة - Game phase classification
///
/// Determined by material count on the board.
/// Used for context-aware evaluation and phase-specific analysis.
enum GamePhase {
  opening,
  middlegame,
  endgame;

  /// التسمية العربية
  String get arabicLabel => switch (this) {
        GamePhase.opening => 'الافتتاح',
        GamePhase.middlegame => 'منتصف اللعبة',
        GamePhase.endgame => 'النهاية',
      };

  /// الوصف العربي
  String get arabicDescription => switch (this) {
        GamePhase.opening => 'مرحلة الافتتاح - تطوير القطع والسيطرة على المركز',
        GamePhase.middlegame => 'مرحلة وسط اللعبة - الهجوم والدفاع والتكتيك',
        GamePhase.endgame => 'مرحلة النهاية - تحويل الأفضلية إلى فوز',
      };

  /// الرمز المرئي
  String get icon => switch (this) {
        GamePhase.opening => '🏛️',
        GamePhase.middlegame => '⚔️',
        GamePhase.endgame => '👑',
      };
}

/// نتيجة المباراة - Game result
enum GameResult {
  whiteWins,
  blackWins,
  draw,
  incomplete;

  /// التسمية العربية
  String get arabicLabel => switch (this) {
        GameResult.whiteWins => 'فوز الأبيض',
        GameResult.blackWins => 'فوز الأسود',
        GameResult.draw => 'تعادل',
        GameResult.incomplete => 'غير مكتملة',
      };

  /// رمز النتيجة القياسي
  /// Standard result notation (1-0, 0-1, ½-½, *)
  String get notation => switch (this) {
        GameResult.whiteWins => '1-0',
        GameResult.blackWins => '0-1',
        GameResult.draw => '½-½',
        GameResult.incomplete => '*',
      };

  /// تحليل من رمز PGN القياسي
  /// Parse from standard PGN result string
  static GameResult fromPgn(String result) => switch (result.trim()) {
        '1-0' => GameResult.whiteWins,
        '0-1' => GameResult.blackWins,
        '1/2-1/2' || '½-½' => GameResult.draw,
        _ => GameResult.incomplete,
      };
}

/// طريقة انتهاء المباراة - Game termination method
enum Termination {
  checkmate,
  resignation,
  timeout,
  stalemate,
  agreement,
  insufficientMaterial,
  repetition,
  fiftyMoveRule,
  abandoned;

  /// التسمية العربية
  String get arabicLabel => switch (this) {
        Termination.checkmate => 'كش مات',
        Termination.resignation => 'استسلام',
        Termination.timeout => 'انتهاء الوقت',
        Termination.stalemate => 'بات',
        Termination.agreement => 'اتفاق',
        Termination.insufficientMaterial => 'مواد غير كافية',
        Termination.repetition => 'تكرار',
        Termination.fiftyMoveRule => 'قاعدة الخمسين حركة',
        Termination.abandoned => 'تخلي',
      };
}

/// لون اللاعب - Player color
enum PlayerColor {
  white,
  black;

  /// هل اللاعب أبيض؟
  bool get isWhite => this == PlayerColor.white;

  /// اللون المعاكس
  PlayerColor get opposite => isWhite ? PlayerColor.black : PlayerColor.white;

  /// التسمية العربية
  String get arabicLabel => isWhite ? 'الأبيض' : 'الأسود';
}

// ============================================================================
// VALUE OBJECTS
// ============================================================================

/// بيانات الافتتاحية - Opening information
///
/// Represents a chess opening with ECO code and Arabic description.
class OpeningData {
  /// اسم الافتتاحية (عربي)
  final String nameAr;

  /// اسم الافتتاحية (إنجليزي)
  final String nameEn;

  /// رمز ECO (Encyclopaedia of Chess Openings)
  final String eco;

  /// التسلسل الحركي للافتتاحية (بصيغة PGN)
  final String moves;

  /// وصف الافتتاحية بالعربية
  final String descriptionAr;

  /// الفئة الرئيسية للافتتاحية
  final String category;

  const OpeningData({
    required this.nameAr,
    required this.nameEn,
    required this.eco,
    required this.moves,
    required this.descriptionAr,
    required this.category,
  });

  OpeningData copyWith({
    String? nameAr,
    String? nameEn,
    String? eco,
    String? moves,
    String? descriptionAr,
    String? category,
  }) {
    return OpeningData(
      nameAr: nameAr ?? this.nameAr,
      nameEn: nameEn ?? this.nameEn,
      eco: eco ?? this.eco,
      moves: moves ?? this.moves,
      descriptionAr: descriptionAr ?? this.descriptionAr,
      category: category ?? this.category,
    );
  }

  @override
  String toString() =>
      'OpeningData(nameAr: $nameAr, eco: $eco, moves: $moves)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpeningData &&
          runtimeType == other.runtimeType &&
          nameAr == other.nameAr &&
          nameEn == other.nameEn &&
          eco == other.eco &&
          moves == other.moves &&
          descriptionAr == other.descriptionAr &&
          category == other.category;

  @override
  int get hashCode => Object.hash(
        nameAr,
        nameEn,
        eco,
        moves,
        descriptionAr,
        category,
      );
}

/// خط المحرك - Single engine analysis line (MultiPV)
///
/// Represents one candidate move from the engine's multi-PV analysis.
/// Each line contains the engine's evaluation, search depth, and
/// principal variation (PV) for that candidate move.
class EngineLine {
  /// الحركة بصيغة UCI (مثل: e2e4)
  final String uciMove;

  /// الحركة بصيغة SAN (مثل: e4)
  final String sanMove;

  /// التقييم بالمئة من بيدق (centipawns)
  /// إيجابي = أفضلية للأبيض، سلبي = أفضلية للأسود
  final int evalCp;

  /// عمق البحث
  final int depth;

  /// التغير الرئيسي - Principal Variation
  /// سلسلة الحركات المتتالية التي يرى المحرك أنها الأفضل
  final String pv;

  /// عدد العقد المبحثة (اختياري)
  final int? nodes;

  /// هل التقييم كش مات؟
  final bool isMate;

  /// عدد حركات الكش مات (إيجابي = كش مات للأبيض، سلبي = للأسود)
  final int? mateIn;

  const EngineLine({
    required this.uciMove,
    required this.sanMove,
    required this.evalCp,
    required this.depth,
    required this.pv,
    this.nodes,
    this.isMate = false,
    this.mateIn,
  });

  /// التقييم الفعال مع مراعاة كش المات
  /// Returns a centipawn value, converting mate scores to large cp values
  int get effectiveEvalCp {
    if (isMate && mateIn != null) {
      // تحويل كش المات إلى قيمة بيدقية كبيرة
      // Mate in N → 100000 - N * 100 (preserving sign)
      return mateIn! > 0
          ? 100000 - mateIn! * 100
          : -100000 - mateIn! * 100;
    }
    return evalCp;
  }

  /// هل هذا الخط يعطي أفضلية حاسمة؟
  bool get isWinning => effectiveEvalCp.abs() > 500;

  EngineLine copyWith({
    String? uciMove,
    String? sanMove,
    int? evalCp,
    int? depth,
    String? pv,
    int? nodes,
    bool? isMate,
    int? mateIn,
  }) {
    return EngineLine(
      uciMove: uciMove ?? this.uciMove,
      sanMove: sanMove ?? this.sanMove,
      evalCp: evalCp ?? this.evalCp,
      depth: depth ?? this.depth,
      pv: pv ?? this.pv,
      nodes: nodes ?? this.nodes,
      isMate: isMate ?? this.isMate,
      mateIn: mateIn ?? this.mateIn,
    );
  }

  @override
  String toString() =>
      'EngineLine(sanMove: $sanMove, evalCp: $evalCp, depth: $depth, '
      'isMate: $isMate, mateIn: $mateIn)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineLine &&
          runtimeType == other.runtimeType &&
          uciMove == other.uciMove &&
          sanMove == other.sanMove &&
          evalCp == other.evalCp &&
          depth == other.depth &&
          pv == other.pv &&
          nodes == other.nodes &&
          isMate == other.isMate &&
          mateIn == other.mateIn;

  @override
  int get hashCode => Object.hash(
        uciMove,
        sanMove,
        evalCp,
        depth,
        pv,
        nodes,
        isMate,
        mateIn,
      );
}

/// نقطة على منحنى التقييم - Single point on the evaluation graph
///
/// Used for plotting the evaluation chart that shows how
/// the advantage shifted throughout the game.
class EvalPoint {
  /// رقم الحركة (تبدأ من 1)
  final int moveNumber;

  /// التقييم بالمئة من بيدق
  final int evalCp;

  /// هل هذه حركة اللاعب الأبيض؟
  final bool isWhite;

  /// تصنيف الحركة (اختياري - للعرض على الرسم البياني)
  final MoveClassification? classification;

  const EvalPoint({
    required this.moveNumber,
    required this.evalCp,
    required this.isWhite,
    this.classification,
  });

  /// تحويل إلى نسبة مئوية للرسم البياني (0-100)
  /// Maps centipawn range to a 0-100 percentage for graph display.
  /// Uses a sigmoid-like mapping for better visualization:
  /// 0 cp → 50%, +1000 cp → ~90%, -1000 cp → ~10%
  double get graphPercentage {
    // دالة سيغمويدية للتحويل السلس
    const double k = 0.003; // عامل التنعيم
    return 100.0 / (1.0 + exp(-k * evalCp));
  }

  EvalPoint copyWith({
    int? moveNumber,
    int? evalCp,
    bool? isWhite,
    MoveClassification? classification,
  }) {
    return EvalPoint(
      moveNumber: moveNumber ?? this.moveNumber,
      evalCp: evalCp ?? this.evalCp,
      isWhite: isWhite ?? this.isWhite,
      classification: classification ?? this.classification,
    );
  }

  @override
  String toString() =>
      'EvalPoint(moveNumber: $moveNumber, evalCp: $evalCp, '
      'isWhite: $isWhite, classification: $classification)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EvalPoint &&
          runtimeType == other.runtimeType &&
          moveNumber == other.moveNumber &&
          evalCp == other.evalCp &&
          isWhite == other.isWhite &&
          classification == other.classification;

  @override
  int get hashCode => Object.hash(
        moveNumber,
        evalCp,
        isWhite,
        classification,
      );
}

/// حركة محللة - A single move with full analysis data
///
/// This is the core data structure representing one half-move (ply)
/// in a chess game, along with all the analysis information provided
/// by the engine: evaluation before/after, centipawn loss,
/// classification, principal variation, and timing.
class AnalyzedMove {
  /// رقم الحركة في اللعبة (تبدأ من 1)
  final int moveNumber;

  /// رقم النصف الحركي (ply) - 1 = أول حركة للأبيض، 2 = أول حركة للأسود
  final int plyNumber;

  /// لون اللاعب الذي لعب الحركة
  final PlayerColor color;

  /// التدوين الجبري القياسي (SAN) - مثل: Nf3, e4, O-O
  final String san;

  /// تدوين UCI - مثل: g1f3, e2e4, e1g1
  final String uci;

  /// وضعية اللوحة قبل الحركة (FEN)
  final String fenBefore;

  /// وضعية اللوحة بعد الحركة (FEN)
  final String fenAfter;

  /// التقييم قبل الحركة (centipawns, من وجهة نظر الأبيض)
  final int evalBefore;

  /// التقييم بعد الحركة (centipawns, من وجهة نظر الأبيض)
  final int evalAfter;

  /// الفقد في المئة من بيدق مقارنة بأفضل حركة
  /// Always non-negative; 0 means the move matched the best line.
  final int cpLoss;

  /// تصنيف الحركة
  final MoveClassification classification;

  /// عمق البحث
  final int depth;

  /// خطوط MultiPV البديلة
  final List<EngineLine> alternatives;

  /// التغير الرئيسي (PV) للحركة المختارة
  final String pv;

  /// اسم الافتتاحية (إن وجدت)
  final String? openingName;

  /// الوقت المستغرق في الحركة (بالملي ثانية)
  final int? timeSpentMs;

  /// تعليق PGN (إن وجد)
  final String? comment;

  /// هل الحركة كش مات؟
  final bool isCheckmate;

  /// هل الحركة كش؟
  final bool isCheck;

  /// هل الحركة تبييت؟
  final bool isCastling;

  /// هل الحركة أخذ قطعة؟
  final bool isCapture;

  /// مرحلة اللعبة عند هذه الحركة
  final GamePhase phase;

  const AnalyzedMove({
    required this.moveNumber,
    required this.plyNumber,
    required this.color,
    required this.san,
    required this.uci,
    required this.fenBefore,
    required this.fenAfter,
    required this.evalBefore,
    required this.evalAfter,
    required this.cpLoss,
    required this.classification,
    required this.depth,
    required this.alternatives,
    required this.pv,
    this.openingName,
    this.timeSpentMs,
    this.comment,
    this.isCheckmate = false,
    this.isCheck = false,
    this.isCastling = false,
    this.isCapture = false,
    required this.phase,
  });

  /// التقييم من وجهة نظر اللاعب الذي لعب الحركة
  /// Evaluation from the moving player's perspective
  int get evalFromPlayerPerspective =>
      color.isWhite ? evalAfter : -evalAfter;

  /// التقييم قبل الحركة من وجهة نظر اللاعب
  int get evalBeforeFromPlayerPerspective =>
      color.isWhite ? evalBefore : -evalBefore;

  /// فقد المادة مقارنة بأفضل حركة (بالبيدق)
  double get cpLossInPawns => cpLoss / 100.0;

  /// التقييم قبل الحركة بالبيدق
  double get evalBeforeInPawns => evalBefore / 100.0;

  /// التقييم بعد الحركة بالبيدق
  double get evalAfterInPawns => evalAfter / 100.0;

  /// الوقت المستغق بالثواني
  double? get timeSpentSeconds =>
      timeSpentMs != null ? timeSpentMs! / 1000.0 : null;

  /// تنسيق عرض الوقت
  String get timeSpentFormatted {
    if (timeSpentMs == null) return '--:--';
    final seconds = timeSpentMs! / 1000.0;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}ث';
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).toStringAsFixed(0);
    return '$minutes:$remainingSeconds';
  }

  /// سلسلة عرض الحركة مع تصنيفها
  String get displayWithClassification {
    final prefix = classification.symbol;
    return '$san $prefix';
  }

  AnalyzedMove copyWith({
    int? moveNumber,
    int? plyNumber,
    PlayerColor? color,
    String? san,
    String? uci,
    String? fenBefore,
    String? fenAfter,
    int? evalBefore,
    int? evalAfter,
    int? cpLoss,
    MoveClassification? classification,
    int? depth,
    List<EngineLine>? alternatives,
    String? pv,
    String? openingName,
    int? timeSpentMs,
    String? comment,
    bool? isCheckmate,
    bool? isCheck,
    bool? isCastling,
    bool? isCapture,
    GamePhase? phase,
  }) {
    return AnalyzedMove(
      moveNumber: moveNumber ?? this.moveNumber,
      plyNumber: plyNumber ?? this.plyNumber,
      color: color ?? this.color,
      san: san ?? this.san,
      uci: uci ?? this.uci,
      fenBefore: fenBefore ?? this.fenBefore,
      fenAfter: fenAfter ?? this.fenAfter,
      evalBefore: evalBefore ?? this.evalBefore,
      evalAfter: evalAfter ?? this.evalAfter,
      cpLoss: cpLoss ?? this.cpLoss,
      classification: classification ?? this.classification,
      depth: depth ?? this.depth,
      alternatives: alternatives ?? this.alternatives,
      pv: pv ?? this.pv,
      openingName: openingName ?? this.openingName,
      timeSpentMs: timeSpentMs ?? this.timeSpentMs,
      comment: comment ?? this.comment,
      isCheckmate: isCheckmate ?? this.isCheckmate,
      isCheck: isCheck ?? this.isCheck,
      isCastling: isCastling ?? this.isCastling,
      isCapture: isCapture ?? this.isCapture,
      phase: phase ?? this.phase,
    );
  }

  @override
  String toString() =>
      'AnalyzedMove(ply: $plyNumber, san: $san, classification: '
      '${classification.arabicLabel}, cpLoss: $cpLoss, eval: '
      '$evalBefore→$evalAfter)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalyzedMove &&
          runtimeType == other.runtimeType &&
          plyNumber == other.plyNumber &&
          san == other.san &&
          uci == other.uci &&
          fenBefore == other.fenBefore &&
          fenAfter == other.fenAfter &&
          evalBefore == other.evalBefore &&
          evalAfter == other.evalAfter &&
          cpLoss == other.cpLoss &&
          classification == other.classification &&
          depth == other.depth &&
          pv == other.pv &&
          openingName == other.openingName &&
          timeSpentMs == other.timeSpentMs &&
          comment == other.comment &&
          isCheckmate == other.isCheckmate &&
          isCheck == other.isCheck &&
          isCastling == other.isCastling &&
          isCapture == other.isCapture &&
          phase == other.phase;

  @override
  int get hashCode => Object.hash(
        plyNumber,
        san,
        uci,
        fenBefore,
        fenAfter,
        evalBefore,
        evalAfter,
        cpLoss,
        classification,
        depth,
        pv,
        openingName,
        timeSpentMs,
        comment,
        isCheckmate,
        isCheck,
        isCastling,
        isCapture,
        phase,
      );
}

/// مباراة شطرنج - Complete chess game data
///
/// Represents a full chess game with all metadata, moves,
/// and analysis results. Supports PGN import/export.
class ChessMatch {
  /// المعرف الفريد
  final String id;

  /// اسم اللاعب الأبيض
  final String whiteName;

  /// اسم اللاعب الأسود
  final String blackName;

  /// تصنيف اللاعب الأبيض (ELO)
  final int? whiteElo;

  /// تصنيف اللاعب الأسود (ELO)
  final int? blackElo;

  /// نتيجة المباراة
  final GameResult result;

  /// طريقة انتهاء المباراة
  final Termination? termination;

  /// تاريخ المباراة
  final DateTime? date;

  /// اسم البطولة أو الحدث
  final String? event;

  /// مكان اللعب
  final String? site;

  /// الجولة (في البطولات)
  final int? round;

  /// قائمة الحركات المحللة
  final List<AnalyzedMove> moves;

  /// بيانات الافتتاحية
  final OpeningData? opening;

  /// نقاط التقييم على الرسم البياني
  final List<EvalPoint> evalPoints;

  /// دقة الأبيض الإجمالية (0-100)
  final double whiteAccuracy;

  /// دقة الأسود الإجمالية (0-100)
  final double blackAccuracy;

  /// عدد الأخطاء للأبيض
  final int whiteInaccuracies;

  /// عدد الأخطاء الفادحة للأبيض
  final int whiteMistakes;

  /// عدد الأخطاء الكارثية للأبيض
  final int whiteBlunders;

  /// عدد الأخطاء للأسود
  final int blackInaccuracies;

  /// عدد الأخطاء الفادحة للأسود
  final int blackMistakes;

  /// عدد الأخطاء الكارثية للأسود
  final int blackBlunders;

  /// عدد الحركات الرائعة للأبيض
  final int whiteBrilliants;

  /// عدد الحركات الرائعة للأسود
  final int blackBrilliants;

  /// عدد الحركات الممتازة للأبيض
  final int whiteGreatMoves;

  /// عدد الحركات الممتازة للأسود
  final int blackGreatMoves;

  /// الحركة الأولى مع أفضلية حاسمة (نقطة التحول)
  final int? turningPoint;

  /// FEN مبدئي (للمباريات غير القياسية)
  final String? initialFen;

  /// وقت اللعب المبدئي بالثواني
  final int? timeControlInitial;

  /// الزيادة بالثواني
  final int? timeControlIncrement;

  /// PGM الخام (للرجوع إليه)
  final String? rawPgn;

  const ChessMatch({
    required this.id,
    required this.whiteName,
    required this.blackName,
    this.whiteElo,
    this.blackElo,
    required this.result,
    this.termination,
    this.date,
    this.event,
    this.site,
    this.round,
    required this.moves,
    this.opening,
    required this.evalPoints,
    this.whiteAccuracy = 0,
    this.blackAccuracy = 0,
    this.whiteInaccuracies = 0,
    this.whiteMistakes = 0,
    this.whiteBlunders = 0,
    this.blackInaccuracies = 0,
    this.blackMistakes = 0,
    this.blackBlunders = 0,
    this.whiteBrilliants = 0,
    this.blackBrilliants = 0,
    this.whiteGreatMoves = 0,
    this.blackGreatMoves = 0,
    this.turningPoint,
    this.initialFen,
    this.timeControlInitial,
    this.timeControlIncrement,
    this.rawPgn,
  });

  /// إجمالي عدد الحركات
  int get totalMoves => moves.length;

  /// إجمالي عدد الحركات الكاملة (زوج الحركات الأبيض+الأسود)
  int get fullMoveCount =>
      (moves.where((m) => m.color.isWhite).length);

  /// مدة المباراة المقدرة (بناءً على أوقات الحركات)
  Duration? get estimatedDuration {
    final totalMs = moves
        .where((m) => m.timeSpentMs != null)
        .map((m) => m.timeSpentMs!)
        .fold<int>(0, (a, b) => a + b);
    if (totalMs == 0) return null;
    return Duration(milliseconds: totalMs);
  }

  /// الحركات ذات التصنيفات المميزة
  List<AnalyzedMove> get notableMoves =>
      moves.where((m) => m.classification.isNotable).toList();

  /// الحركات ذات الأخطاء
  List<AnalyzedMove> get errorMoves =>
      moves.where((m) => m.classification.isError).toList();

  /// ملخص المباراة بالعربية
  String get arabicSummary {
    final buffer = StringBuffer();
    buffer.writeln('مباراة: $whiteName مقابل $blackName');
    buffer.writeln('النتيجة: ${result.arabicLabel} (${result.notation})');
    if (whiteElo != null) buffer.writeln('تصنيف الأبيض: $whiteElo');
    if (blackElo != null) buffer.writeln('تصنيف الأسود: $blackElo');
    buffer.writeln('عدد الحركات: $totalMoves');
    buffer.writeln('دقة الأبيض: ${whiteAccuracy.toStringAsFixed(1)}%');
    buffer.writeln('دقة الأسود: ${blackAccuracy.toStringAsFixed(1)}%');
    buffer.writeln('أخطاء الأبيض: $whiteInaccuracies عدم دقة، '
        '$whiteMistakes خطأ، $whiteBlunders خطأ فادح');
    buffer.writeln('أخطاء الأسود: $blackInaccuracies عدم دقة، '
        '$blackMistakes خطأ، $blackBlunders خطأ فادح');
    if (opening != null) {
      buffer.writeln('الافتتاحية: ${opening!.nameAr}');
    }
    return buffer.toString();
  }

  ChessMatch copyWith({
    String? id,
    String? whiteName,
    String? blackName,
    int? whiteElo,
    int? blackElo,
    GameResult? result,
    Termination? termination,
    DateTime? date,
    String? event,
    String? site,
    int? round,
    List<AnalyzedMove>? moves,
    OpeningData? opening,
    List<EvalPoint>? evalPoints,
    double? whiteAccuracy,
    double? blackAccuracy,
    int? whiteInaccuracies,
    int? whiteMistakes,
    int? whiteBlunders,
    int? blackInaccuracies,
    int? blackMistakes,
    int? blackBlunders,
    int? whiteBrilliants,
    int? blackBrilliants,
    int? whiteGreatMoves,
    int? blackGreatMoves,
    int? turningPoint,
    String? initialFen,
    int? timeControlInitial,
    int? timeControlIncrement,
    String? rawPgn,
  }) {
    return ChessMatch(
      id: id ?? this.id,
      whiteName: whiteName ?? this.whiteName,
      blackName: blackName ?? this.blackName,
      whiteElo: whiteElo ?? this.whiteElo,
      blackElo: blackElo ?? this.blackElo,
      result: result ?? this.result,
      termination: termination ?? this.termination,
      date: date ?? this.date,
      event: event ?? this.event,
      site: site ?? this.site,
      round: round ?? this.round,
      moves: moves ?? this.moves,
      opening: opening ?? this.opening,
      evalPoints: evalPoints ?? this.evalPoints,
      whiteAccuracy: whiteAccuracy ?? this.whiteAccuracy,
      blackAccuracy: blackAccuracy ?? this.blackAccuracy,
      whiteInaccuracies: whiteInaccuracies ?? this.whiteInaccuracies,
      whiteMistakes: whiteMistakes ?? this.whiteMistakes,
      whiteBlunders: whiteBlunders ?? this.whiteBlunders,
      blackInaccuracies: blackInaccuracies ?? this.blackInaccuracies,
      blackMistakes: blackMistakes ?? this.blackMistakes,
      blackBlunders: blackBlunders ?? this.blackBlunders,
      whiteBrilliants: whiteBrilliants ?? this.whiteBrilliants,
      blackBrilliants: blackBrilliants ?? this.blackBrilliants,
      whiteGreatMoves: whiteGreatMoves ?? this.whiteGreatMoves,
      blackGreatMoves: blackGreatMoves ?? this.blackGreatMoves,
      turningPoint: turningPoint ?? this.turningPoint,
      initialFen: initialFen ?? this.initialFen,
      timeControlInitial: timeControlInitial ?? this.timeControlInitial,
      timeControlIncrement: timeControlIncrement ?? this.timeControlIncrement,
      rawPgn: rawPgn ?? this.rawPgn,
    );
  }

  @override
  String toString() =>
      'ChessMatch(id: $id, white: $whiteName, black: $blackName, '
      'result: ${result.notation}, moves: ${moves.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChessMatch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          whiteName == other.whiteName &&
          blackName == other.blackName &&
          whiteElo == other.whiteElo &&
          blackElo == other.blackElo &&
          result == other.result &&
          termination == other.termination &&
          date == other.date &&
          event == other.event &&
          site == other.site &&
          round == other.round &&
          moves.length == other.moves.length &&
          opening == other.opening &&
          whiteAccuracy == other.whiteAccuracy &&
          blackAccuracy == other.blackAccuracy &&
          whiteInaccuracies == other.whiteInaccuracies &&
          whiteMistakes == other.whiteMistakes &&
          whiteBlunders == other.whiteBlunders &&
          blackInaccuracies == other.blackInaccuracies &&
          blackMistakes == other.blackMistakes &&
          blackBlunders == other.blackBlunders &&
          whiteBrilliants == other.whiteBrilliants &&
          blackBrilliants == other.blackBrilliants &&
          whiteGreatMoves == other.whiteGreatMoves &&
          blackGreatMoves == other.blackGreatMoves &&
          turningPoint == other.turningPoint &&
          initialFen == other.initialFen &&
          timeControlInitial == other.timeControlInitial &&
          timeControlIncrement == other.timeControlIncrement;

  @override
  int get hashCode => Object.hash(
    Object.hash(id, whiteName, blackName, whiteElo, blackElo, result,
        termination, date, event, site, round),
    Object.hash(Object.hashAll(moves), opening, whiteAccuracy, blackAccuracy,
        whiteInaccuracies, whiteMistakes, whiteBlunders,
        blackInaccuracies, blackMistakes, blackBlunders),
    Object.hash(whiteBrilliants, blackBrilliants, whiteGreatMoves,
        blackGreatMoves, turningPoint, initialFen,
        timeControlInitial, timeControlIncrement),
  );
}

/// بيانات اللغز - Puzzle data for tactical training
///
/// Represents a chess puzzle extracted from game analysis or
/// curated from a puzzle database.
class PuzzleData {
  /// المعرف الفريد
  final String id;

  /// وضعية اللوحة (FEN)
  final String fen;

  /// الحلول الممكنة (بصيغة UCI)
  final List<String> solution;

  /// التقييم الأولي (centipawns من وجهة نظر الأبيض)
  final int initialEval;

  /// التصنيف المبدئي للغز
  final int rating;

  /// عدد المحاولات
  final int plays;

  /// الفئة التكتيكية
  final String theme;

  /// الفئة التكتيكية بالعربية
  final String themeAr;

  /// رابط المباراة الأصلية
  final String? gameUrl;

  /// اسم الافتتاحية
  final String? openingName;

  const PuzzleData({
    required this.id,
    required this.fen,
    required this.solution,
    required this.initialEval,
    required this.rating,
    required this.plays,
    required this.theme,
    required this.themeAr,
    this.gameUrl,
    this.openingName,
  });

  /// الحركة الأولى في الحل
  String get firstMove => solution.first;

  /// هل اللغز يتطلب سلسلة حركات طويلة؟
  bool get isLongPuzzle => solution.length > 3;

  /// صعوبة اللغز بالعربية
  String get difficultyAr {
    if (rating < 1000) return 'مبتدئ';
    if (rating < 1400) return 'متوسط';
    if (rating < 1800) return 'متقدم';
    if (rating < 2200) return 'خبير';
    return 'أستاذ';
  }

  PuzzleData copyWith({
    String? id,
    String? fen,
    List<String>? solution,
    int? initialEval,
    int? rating,
    int? plays,
    String? theme,
    String? themeAr,
    String? gameUrl,
    String? openingName,
  }) {
    return PuzzleData(
      id: id ?? this.id,
      fen: fen ?? this.fen,
      solution: solution ?? this.solution,
      initialEval: initialEval ?? this.initialEval,
      rating: rating ?? this.rating,
      plays: plays ?? this.plays,
      theme: theme ?? this.theme,
      themeAr: themeAr ?? this.themeAr,
      gameUrl: gameUrl ?? this.gameUrl,
      openingName: openingName ?? this.openingName,
    );
  }

  @override
  String toString() =>
      'PuzzleData(id: $id, theme: $theme, rating: $rating, '
      'solutionLength: ${solution.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PuzzleData &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fen == other.fen &&
          _listEquals(solution, other.solution) &&
          initialEval == other.initialEval &&
          rating == other.rating &&
          plays == other.plays &&
          theme == other.theme &&
          themeAr == other.themeAr &&
          gameUrl == other.gameUrl &&
          openingName == other.openingName;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        id,
        fen,
        Object.hashAll(solution),
        initialEval,
        rating,
        plays,
        theme,
        themeAr,
        gameUrl,
        openingName,
      );
}

/// ملخص تحليل المباراة - Game analysis summary
///
/// Aggregated statistics from a complete game analysis.
class AnalysisSummary {
  /// دقة الأبيض (0-100)
  final double whiteAccuracy;

  /// دقة الأسود (0-100)
  final double blackAccuracy;

  /// توزيع تصنيفات حركات الأبيض
  final Map<MoveClassification, int> whiteClassificationCounts;

  /// توزيع تصنيفات حركات الأسود
  final Map<MoveClassification, int> blackClassificationCounts;

  /// متوسط فقد المادة للأبيض (centipawns)
  final double whiteAvgCpLoss;

  /// متوسط فقد المادة للأسود (centipawns)
  final double blackAvgCpLoss;

  /// أكبر خطأ في المباراة
  final AnalyzedMove? worstMove;

  /// أفضل حركة في المباراة
  final AnalyzedMove? bestMove;

  /// الحركة التي شكلت نقطة التحول
  final AnalyzedMove? turningPointMove;

  /// عدد الحركات في كل مرحلة
  final Map<GamePhase, int> phaseMoveCounts;

  const AnalysisSummary({
    required this.whiteAccuracy,
    required this.blackAccuracy,
    required this.whiteClassificationCounts,
    required this.blackClassificationCounts,
    required this.whiteAvgCpLoss,
    required this.blackAvgCpLoss,
    this.worstMove,
    this.bestMove,
    this.turningPointMove,
    required this.phaseMoveCounts,
  });

  /// إجمالي أخطاء الأبيض
  int get whiteTotalErrors =>
      whiteClassificationCounts[MoveClassification.inaccuracy]! +
      whiteClassificationCounts[MoveClassification.mistake]! +
      whiteClassificationCounts[MoveClassification.blunder]!;

  /// إجمالي أخطاء الأسود
  int get blackTotalErrors =>
      blackClassificationCounts[MoveClassification.inaccuracy]! +
      blackClassificationCounts[MoveClassification.mistake]! +
      blackClassificationCounts[MoveClassification.blunder]!;

  /// من لعب بشكل أفضل؟
  PlayerColor get betterPlayer =>
      whiteAccuracy >= blackAccuracy ? PlayerColor.white : PlayerColor.black;

  /// فرق الدقة
  double get accuracyDiff =>
      (whiteAccuracy - blackAccuracy).abs();

  AnalysisSummary copyWith({
    double? whiteAccuracy,
    double? blackAccuracy,
    Map<MoveClassification, int>? whiteClassificationCounts,
    Map<MoveClassification, int>? blackClassificationCounts,
    double? whiteAvgCpLoss,
    double? blackAvgCpLoss,
    AnalyzedMove? worstMove,
    AnalyzedMove? bestMove,
    AnalyzedMove? turningPointMove,
    Map<GamePhase, int>? phaseMoveCounts,
  }) {
    return AnalysisSummary(
      whiteAccuracy: whiteAccuracy ?? this.whiteAccuracy,
      blackAccuracy: blackAccuracy ?? this.blackAccuracy,
      whiteClassificationCounts:
          whiteClassificationCounts ?? this.whiteClassificationCounts,
      blackClassificationCounts:
          blackClassificationCounts ?? this.blackClassificationCounts,
      whiteAvgCpLoss: whiteAvgCpLoss ?? this.whiteAvgCpLoss,
      blackAvgCpLoss: blackAvgCpLoss ?? this.blackAvgCpLoss,
      worstMove: worstMove ?? this.worstMove,
      bestMove: bestMove ?? this.bestMove,
      turningPointMove: turningPointMove ?? this.turningPointMove,
      phaseMoveCounts: phaseMoveCounts ?? this.phaseMoveCounts,
    );
  }

  @override
  String toString() =>
      'AnalysisSummary(whiteAcc: ${whiteAccuracy.toStringAsFixed(1)}%, '
      'blackAcc: ${blackAccuracy.toStringAsFixed(1)}%, '
      'whiteErrors: $whiteTotalErrors, blackErrors: $blackTotalErrors)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalysisSummary &&
          runtimeType == other.runtimeType &&
          whiteAccuracy == other.whiteAccuracy &&
          blackAccuracy == other.blackAccuracy &&
          whiteAvgCpLoss == other.whiteAvgCpLoss &&
          blackAvgCpLoss == other.blackAvgCpLoss;

  @override
  int get hashCode => Object.hash(
        whiteAccuracy,
        blackAccuracy,
        whiteAvgCpLoss,
        blackAvgCpLoss,
      );
}
