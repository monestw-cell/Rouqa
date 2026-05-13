/// ثوابت التطبيق — App Constants
/// جميع الثوابت المستخدمة في تطبيق رُقعة
library;

/// اسم التطبيق بالعربية
const String kAppNameAr = 'رُقعة';

/// اسم التطبيق بالإنجليزية
const String kAppNameEn = "Ruq'a";

/// اسم الحزمة
const String kPackageName = 'com.ruqa.chessanalyzer';

// ─── محرك التحليل — Stockfish Engine ───────────────────────────────────────

/// عمق التحليل الافتراضي
const int kDefaultAnalysisDepth = 20;

/// عدد الخطوط البديلة الافتراضي (MultiPV)
const int kDefaultMultiPV = 3;

/// الحد الأقصى لعدد الخطوط البديلة
const int kMaxMultiPV = 5;

/// اسم ملف Stockfish الثنائي
const String kStockfishBinary = 'stockfish';

/// اسم مكتبة Stockfish على أندرويد
const String kStockfishAndroidLib = 'libstockfish.so';

// ─── عتبات التقييم — Eval Thresholds ───────────────────────────────────────

/// عتبة الخطأ الكبير (Centipawns)
const int kBlunderThreshold = 300;

/// عتبة الخطأ (Centipawns)
const int kMistakeThreshold = 100;

/// عتبة عدم الدقة (Centipawns)
const int kInaccuracyThreshold = 50;

/// عتبة الحركة الرائعة (Centipawns)
const int kBrilliantThreshold = -50;

/// عتبة الحركة الممتازة (Centipawns)
const int kGreatMoveThreshold = -25;

// ─── تصنيفات الحركات — Move Classifications ────────────────────────────────

/// حركة رائعة
const String kClassificationBrilliant = 'brilliant';

/// حركة ممتازة
const String kClassificationGreat = 'great';

/// حركة أفضل
const String kClassificationBest = 'best';

/// حركة جيدة
const String kClassificationGood = 'good';

/// حركة مقبولة
const String kClassificationBook = 'book';

/// عدم دقة
const String kClassificationInaccuracy = 'inaccuracy';

/// خطأ
const String kClassificationMistake = 'mistake';

/// خطأ فادح
const String kClassificationBlunder = 'blunder';

/// حركة قسرية
const String kClassificationForced = 'forced';

// ─── قيود اللوح — Board Size Constraints ───────────────────────────────────

/// الحد الأدنى لحجم اللوح
const double kBoardMinSize = 280.0;

/// الحد الأقصى لحجم اللوح
const double kBoardMaxSize = 480.0;

/// حجم المربع الافتراضي
const double kDefaultSquareSize = 48.0;

// ─── مدد الرسوم المتحركة — Animation Durations ────────────────────────────

/// مدة حركة القطعة (مللي ثانية)
const int kMoveAnimationDuration = 200;

/// مدة سحب القطعة (مللي ثانية)
const int kDragAnimationDuration = 150;

/// مدة ظهور التصنيف (مللي ثانية)
const int kClassificationAppearDuration = 300;

/// مدة انتقال الشاشة (مللي ثانية)
const int kPageTransitionDuration = 250;

/// مدة إبراز المربع (مللي ثانية)
const int kHighlightPulseDuration = 600;

// ─── مسارات الأصول — Asset Paths ───────────────────────────────────────────

/// مسار صور القطع بصيغة SVG
const String kPiecesSvgPath = 'assets/pieces/svg/';

/// مسار الأيقونات
const String kIconsPath = 'assets/icons/';

/// مسار محرك Stockfish
const String kStockfishPath = 'assets/stockfish/';

/// امتدادات أسماء ملفات القطع
const List<String> kPieceFileNames = [
  'wK', 'wQ', 'wR', 'wB', 'wN', 'wP',
  'bK', 'bQ', 'bR', 'bB', 'bN', 'bP',
];

// ─── نتائج المباريات — Match Results ───────────────────────────────────────

/// فوز الأبيض
const String kResultWhiteWins = '1-0';

/// فوز الأسود
const String kResultBlackWins = '0-1';

/// تعادل
const String kResultDraw = '1/2-1/2';

/// لم ينتهِ
const String kResultInProgress = '*';

// ─── إعدادات ضبط الوقت — Time Control Presets ─────────────────────────────

/// قائمة إعدادات ضبط الوقت المسبقة
const List<Map<String, dynamic>> kTimeControlPresets = [
  {'name': 'رصاصي • Bullet', 'nameEn': 'Bullet', 'time': 60, 'increment': 0},
  {'name': 'رصاصي +١ • Bullet+1', 'nameEn': 'Bullet+1', 'time': 60, 'increment': 1},
  {'name': 'خاطف +١ • Blitz+1', 'nameEn': 'Blitz+1', 'time': 180, 'increment': 1},
  {'name': 'خاطف +٢ • Blitz+2', 'nameEn': 'Blitz+2', 'time': 180, 'increment': 2},
  {'name': 'خاطف +٣ • Blitz+3', 'nameEn': 'Blitz+3', 'time': 180, 'increment': 3},
  {'name': 'خاطف ٥+٠ • Blitz 5+0', 'nameEn': 'Blitz 5+0', 'time': 300, 'increment': 0},
  {'name': 'خاطف ٥+٣ • Blitz 5+3', 'nameEn': 'Blitz 5+3', 'time': 300, 'increment': 3},
  {'name': 'سريع ١٠+٠ • Rapid 10+0', 'nameEn': 'Rapid 10+0', 'time': 600, 'increment': 0},
  {'name': 'سريع ١٠+٥ • Rapid 10+5', 'nameEn': 'Rapid 10+5', 'time': 600, 'increment': 5},
  {'name': 'سريع ١٥+١٠ • Rapid 15+10', 'nameEn': 'Rapid 15+10', 'time': 900, 'increment': 10},
  {'name': 'كلاسيكي ٣٠+٠ • Classical 30+0', 'nameEn': 'Classical 30+0', 'time': 1800, 'increment': 0},
  {'name': 'كلاسيكي ٣٠+٢٠ • Classical 30+20', 'nameEn': 'Classical 30+20', 'time': 1800, 'increment': 20},
];

// ─── مصادر المباريات — Match Sources ───────────────────────────────────────

/// مصدر يدوي
const String kSourceManual = 'manual';

/// مصدر ملف PGN
const String kSourcePgn = 'pgn';

/// مصدر Lichess
const String kSourceLichess = 'lichess';

/// مصدر Chess.com
const String kSourceChessCom = 'chesscom';

// ─── مفاتيح التخزين — Storage Keys ─────────────────────────────────────────

/// مفتاح عمق التحليل
const String kPrefAnalysisDepth = 'analysis_depth';

/// مفتاح MultiPV
const String kPrefMultiPV = 'multi_pv';

/// مفتاح سمة اللوح
const String kPrefBoardTheme = 'board_theme';

/// مفتاح سمة التطبيق
const String kPrefAppTheme = 'app_theme';

/// مفتاح اللوح المعكوس
const String kPrefFlippedBoard = 'flipped_board';

/// مفتاح إظهار التنسيق
const String kPrefShowCoordinates = 'show_coordinates';

/// مفتاح إظهار الأسهم
const String kPrefShowArrows = 'show_arrows';

/// مفتاح الرسوم المتحركة
const String kPrefAnimations = 'animations';

// ─── قيم افتراضية — Defaults ───────────────────────────────────────────────

/// إصدار قاعدة البيانات
const int kDatabaseVersion = 3;

/// اسم قاعدة البيانات
const String kDatabaseName = 'ruqa.db';
