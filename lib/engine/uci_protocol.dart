/// uci_protocol.dart
/// محلل بروتوكول UCI (Universal Chess Interface) الكامل لتطبيق رُقعة
///
/// يدعم هذا الملف تحليل جميع أنواع استجابات UCI من محرك الشطرنج:
/// - id: معلومات المحرك (الاسم والمؤلف)
/// - uciok: تأكيد تهيئة UCI
/// - readyok: تأكيد جاهزية المحرك
/// - bestmove: أفضل حركة وجدتها
/// - info: معلومات التحليل (العمق، التقييم، العقد، إلخ)
/// - option: خيارات المحرك المتاحة
///
/// تم تصميم المحلل ليتعامل مع الأسطر المشوهة بأمان
/// ويدعم التقييم من منظور الأبيض والأسود

// ============================================================================
// أنواع التقييم (Score Types)
// ============================================================================

/// نوع التقييم: بالسنتمتر أو كش مات
enum ScoreType {
  /// التقييم بالسنتمتر (centipawns) - وحدة القياس الأساسية
  centipawns,

  /// التقييم بعدد حركات كش المات (الإيجابي = كش مات للأبيض، السلبي = للأسود)
  mate,
}

/// التقييم من المحرك - يمثل تقييم الموقف إما بالسنتمتر أو بحركات كش المات
///
/// في بروتوكول UCI، التقييم يكون دائماً من منظور الجانب الذي يلعب:
/// - `score cp 100` يعني أن الجانب الحالي متفوق بـ 1 بيدق تقريباً
/// - `score mate 3` يعني كش مات في 3 حركات للجانب الحالي
/// - `score cp -50` يعني أن الجانب الحالي متأخر بنصف بيدق تقريباً
class EngineScore {
  /// نوع التقييم
  final ScoreType type;

  /// قيمة التقييم:
  /// - إذا كان النوع centipawns: القيمة بالسنتمتر (100 = بيدق واحد تقريباً)
  /// - إذا كان النوع mate: عدد الحركات حتى كش المات (موجب = فوز، سالب = خسارة)
  final int value;

  /// ما إذا كان التقييم من الحد الأدنى (lowerbound) - لم يكتمل البحث بعد
  final bool lowerbound;

  /// ما إذا كان التقييم من الحد الأعلى (upperbound) - لم يكتمل البحث بعد
  final bool upperbound;

  const EngineScore({
    required this.type,
    required this.value,
    this.lowerbound = false,
    this.upperbound = false,
  });

  /// يحول التقييم إلى منظور الأبيض
  /// [isWhiteToMove] - هل دور الأبيض للعب؟
  ///
  /// في UCI، التقييم يكون من منظور اللاعب الحالي.
  /// هذه الدالة تحوله لمنظور الأبيض دائماً لتسهيل العرض.
  EngineScore fromWhitePerspective(bool isWhiteToMove) {
    if (isWhiteToMove) return this;
    return EngineScore(
      type: type,
      value: -value,
      lowerbound: lowerbound,
      upperbound: upperbound,
    );
  }

  /// يحول التقييم إلى سلسلة نصية مفهومة
  ///
  /// أمثلة:
  /// - cp 150 → "+1.50"
  /// - cp -80 → "-0.80"
  /// - mate 3 → "M3" (كش مات في 3)
  /// - mate -5 → "-M5" (كش مات عليك في 5)
  String toDisplayString() {
    if (type == ScoreType.mate) {
      if (value > 0) return 'M$value';
      return '-M${value.abs()}';
    }
    final pawns = value / 100.0;
    return '${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(2)}';
  }

  /// يحول التقييم إلى سلسلة مفصلة بالعربية
  String toArabicDisplayString() {
    if (type == ScoreType.mate) {
      if (value > 0) return 'كش مات في $value';
      return 'كش مات في ${value.abs()} للخصم';
    }
    final pawns = value / 100.0;
    final sign = pawns >= 0 ? '+' : '';
    return '$sign${pawns.toStringAsFixed(2)} بيدق';
  }

  @override
  String toString() {
    final flags = <String>[
      if (lowerbound) 'lowerbound',
      if (upperbound) 'upperbound',
    ];
    final flagStr = flags.isEmpty ? '' : ' ${flags.join(' ')}';
    if (type == ScoreType.mate) {
      return 'mate $value$flagStr';
    }
    return 'cp $value$flagStr';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EngineScore &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          value == other.value &&
          lowerbound == other.lowerbound &&
          upperbound == other.upperbound;

  @override
  int get hashCode =>
      type.hashCode ^ value.hashCode ^ lowerbound.hashCode ^ upperbound.hashCode;
}

// ============================================================================
// أنواع استجابات UCI
// ============================================================================

/// نوع خيار المحرك
enum OptionType {
  check,
  spin,
  combo,
  button,
  string,
  unknown;

  static OptionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'check':
        return OptionType.check;
      case 'spin':
        return OptionType.spin;
      case 'combo':
        return OptionType.combo;
      case 'button':
        return OptionType.button;
      case 'string':
        return OptionType.string;
      default:
        return OptionType.unknown;
    }
  }
}

/// استجابة id - معلومات تعريف المحرك
///
/// مثال: `id name Stockfish 16.1`
/// مثال: `id author the Stockfish contributors`
class UciIdResponse {
  /// اسم المحرك
  final String? name;

  /// مؤلف المحرك
  final String? author;

  const UciIdResponse({this.name, this.author});

  @override
  String toString() => 'UciIdResponse(name: $name, author: $author)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UciIdResponse && name == other.name && author == other.author;

  @override
  int get hashCode => name.hashCode ^ author.hashCode;
}

/// استجابة uciok - تأكيد أن المحرك جاهز لاستقبال الأوامر
///
/// يُرسلها المحرك بعد تلقي أمر `uci`
class UciOkResponse {
  const UciOkResponse();

  @override
  String toString() => 'UciOkResponse()';
}

/// استجابة readyok - تأكيد أن المحرك جاهز لاستقبال أوامر جديدة
///
/// يُرسلها المحرك بعد تلقي أمر `isready`
class ReadyOkResponse {
  const ReadyOkResponse();

  @override
  String toString() => 'ReadyOkResponse()';
}

/// استجابة bestmove - أفضل حركة وجدتها المحرك
///
/// مثال: `bestmove e2e4 ponder e7e5`
/// مثال: `bestmove a7a8q` (ترقية البيدق)
class BestMoveResponse {
  /// أفضل حركة بصيغة UCI (مثل: e2e4, a7a8q)
  final String bestMove;

  /// الحركة المقترحة للتفكير المسبق (ponder) - اختيارية
  final String? ponder;

  const BestMoveResponse({required this.bestMove, this.ponder});

  @override
  String toString() =>
      'BestMoveResponse(bestMove: $bestMove, ponder: $ponder)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BestMoveResponse &&
          bestMove == other.bestMove &&
          ponder == other.ponder;

  @override
  int get hashCode => bestMove.hashCode ^ ponder.hashCode;
}

/// استجابة info - معلومات التحليل من المحرك
///
/// هذه أكثر الاستجابات تعقيداً في بروتوكول UCI.
/// تحتوي على معلومات مثل العمق والتقييم وعدد العقد وخط اللعب.
///
/// مثال: `info depth 20 seldepth 25 multipv 1 score cp 45 nodes 1234567 nps 2500000 tbhits 0 time 494 pv e2e4 e7e5 g1f3`
///
/// ليس كل الحقول موجودة دائماً - المحرك يرسل ما يتوفر عليه
class InfoResponse {
  /// عمق البحث الرئيسي (depth)
  final int? depth;

  /// عمق البحث الانتقائي (selective depth) - عادة أعمق من depth
  final int? selDepth;

  /// رقم خط اللعب المتعدد (MultiPV) - 1 هو الأفضل، 2 هو الثاني، إلخ
  final int? multiPv;

  /// تقييم الموقف
  final EngineScore? score;

  /// عدد العقد (positions) التي تم تقييمها
  final int? nodes;

  /// عدد العقد في الثانية (Nodes Per Second)
  final int? nps;

  /// عدد ضربات طاولة النهاية (Tablebase hits)
  final int? tbHits;

  /// الوقت المستغرق بالمللي ثانية
  final int? timeMs;

  /// خط اللعب المتوقع (Principal Variation) - سلسلة الحركات المتوقعة
  final List<String> pv;

  /// الحركة الحالية قيد التحليل
  final String? currMove;

  /// رقم الحركة الحالية في قائمة الحركات
  final int? currMoveNumber;

  /// تكرار الموقف الحالي (عدد مرات حدوثه)
  final int? repetition;

  /// استخدام الذاكرة بالـ MB
  final int? hashFull;

  /// عدد وحدات المعالجة (CPUs) المستخدمة
  final int? cpuload;

  /// سلسلة عرض نصية من المحرك (للعرض فقط)
  final String? stringDisplay;

  /// تقييم المحرك المتعدد العمق (multipv) لهذا الخط
  final int? multipvLine;

  const InfoResponse({
    this.depth,
    this.selDepth,
    this.multiPv,
    this.score,
    this.nodes,
    this.nps,
    this.tbHits,
    this.timeMs,
    this.pv = const [],
    this.currMove,
    this.currMoveNumber,
    this.repetition,
    this.hashFull,
    this.cpuload,
    this.stringDisplay,
    this.multipvLine,
  });

  /// هل هذه استجابة تحليل مفيدة (تحتوي على عمق وتقييم)؟
  bool get hasUsefulData => depth != null && score != null;

  /// هل هذه استجابة كش مات؟
  bool get isMate => score?.type == ScoreType.mate;

  /// التقييم بالبيدق (للعرض) - null إذا لم يوجد تقييم
  double? get pawns => score?.type == ScoreType.centipawns
      ? (score!.value / 100.0)
      : null;

  /// نسخة مع تقييم من منظور الأبيض
  InfoResponse withWhitePerspectiveScore(bool isWhiteToMove) {
    if (score == null) return this;
    return InfoResponse(
      depth: depth,
      selDepth: selDepth,
      multiPv: multiPv,
      score: score!.fromWhitePerspective(isWhiteToMove),
      nodes: nodes,
      nps: nps,
      tbHits: tbHits,
      timeMs: timeMs,
      pv: pv,
      currMove: currMove,
      currMoveNumber: currMoveNumber,
      repetition: repetition,
      hashFull: hashFull,
      cpuload: cpuload,
      stringDisplay: stringDisplay,
      multipvLine: multipvLine,
    );
  }

  @override
  String toString() {
    final parts = <String>[
      if (depth != null) 'depth=$depth',
      if (selDepth != null) 'seldepth=$selDepth',
      if (multiPv != null) 'multipv=$multiPv',
      if (score != null) 'score=$score',
      if (nodes != null) 'nodes=$nodes',
      if (nps != null) 'nps=$nps',
      if (tbHits != null) 'tbhits=$tbHits',
      if (timeMs != null) 'time=${timeMs}ms',
      if (pv.isNotEmpty) 'pv=${pv.join(' ')}',
      if (currMove != null) 'currmove=$currMove',
      if (currMoveNumber != null) 'currmovenumber=$currMoveNumber',
    ];
    return 'InfoResponse(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InfoResponse &&
          depth == other.depth &&
          selDepth == other.selDepth &&
          multiPv == other.multiPv &&
          score == other.score &&
          nodes == other.nodes &&
          nps == other.nps &&
          tbHits == other.tbHits &&
          timeMs == other.timeMs &&
          _listEquals(pv, other.pv) &&
          currMove == other.currMove &&
          currMoveNumber == other.currMoveNumber;

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      depth.hashCode ^
      selDepth.hashCode ^
      multiPv.hashCode ^
      score.hashCode ^
      nodes.hashCode ^
      nps.hashCode ^
      tbHits.hashCode ^
      timeMs.hashCode ^
      pv.hashCode ^
      currMove.hashCode ^
      currMoveNumber.hashCode;
}

/// استجابة option - خيار متاح في المحرك
///
/// مثال: `option name Threads type spin default 1 min 1 max 1024`
/// مثال: `option name Hash type spin default 16 min 1 max 33554432`
/// مثال: `option name Style type combo default Normal var Normal var Aggressive var Defensive`
class OptionResponse {
  /// اسم الخيار
  final String name;

  /// نوع الخيار
  final OptionType type;

  /// القيمة الافتراضية
  final String? defaultValue;

  /// الحد الأدنى (للنوع spin فقط)
  final int? min;

  /// الحد الأقصى (للنوع spin فقط)
  final int? max;

  /// القيم المتاحة (للنوع combo فقط)
  final List<String> vars;

  const OptionResponse({
    required this.name,
    required this.type,
    this.defaultValue,
    this.min,
    this.max,
    this.vars = const [],
  });

  @override
  String toString() {
    final parts = <String>[
      'name=$name',
      'type=$type',
      if (defaultValue != null) 'default=$defaultValue',
      if (min != null) 'min=$min',
      if (max != null) 'max=$max',
      if (vars.isNotEmpty) 'vars=${vars.join('|')}',
    ];
    return 'OptionResponse(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OptionResponse &&
          name == other.name &&
          type == other.type &&
          defaultValue == other.defaultValue &&
          min == other.min &&
          max == other.max &&
          InfoResponse._listEquals(vars, other.vars);

  @override
  int get hashCode =>
      name.hashCode ^
      type.hashCode ^
      defaultValue.hashCode ^
      min.hashCode ^
      max.hashCode ^
      vars.hashCode;
}

/// استجابة غير معروفة أو لا يمكن تحليلها
class UnknownResponse {
  /// السطر الأصلي كما هو
  final String rawLine;

  const UnknownResponse(this.rawLine);

  @override
  String toString() => 'UnknownResponse("$rawLine")';
}

// ============================================================================
// الاتحاد الرئيسي للاستجابات (UciResponse)
// ============================================================================

/// أنواع استجابات UCI الممكنة
enum UciResponseType {
  id,
  uciok,
  readyok,
  bestmove,
  info,
  option,
  unknown,
}

/// الغلاف الموحد لجميع استجابات UCI
///
/// يمثل أي استجابة ممكنة من محرك UCI.
/// استخدم [type] لمعرفة نوع الاستجابة ثم الوصول للبيانات المناسبة.
class UciResponse {
  final UciResponseType type;

  /// بيانات id - ليست null فقط إذا كان النوع id
  final UciIdResponse? id;

  /// بيانات bestmove - ليست null فقط إذا كان النوع bestmove
  final BestMoveResponse? bestMove;

  /// بيانات info - ليست null فقط إذا كان النوع info
  final InfoResponse? info;

  /// بيانات option - ليست null فقط إذا كان النوع option
  final OptionResponse? option;

  /// بيانات unknown - ليست null فقط إذا كان النوع unknown
  final UnknownResponse? unknown;

  const UciResponse._({
    required this.type,
    this.id,
    this.bestMove,
    this.info,
    this.option,
    this.unknown,
  });

  /// إنشاء استجابة id
  factory UciResponse.id(UciIdResponse id) =>
      UciResponse._(type: UciResponseType.id, id: id);

  /// إنشاء استجابة uciok
  factory UciResponse.uciok() =>
      const UciResponse._(type: UciResponseType.uciok);

  /// إنشاء استجابة readyok
  factory UciResponse.readyok() =>
      const UciResponse._(type: UciResponseType.readyok);

  /// إنشاء استجابة bestmove
  factory UciResponse.bestMove(BestMoveResponse bestMove) =>
      UciResponse._(type: UciResponseType.bestmove, bestMove: bestMove);

  /// إنشاء استجابة info
  factory UciResponse.info(InfoResponse info) =>
      UciResponse._(type: UciResponseType.info, info: info);

  /// إنشاء استجابة option
  factory UciResponse.option(OptionResponse option) =>
      UciResponse._(type: UciResponseType.option, option: option);

  /// إنشاء استجابة غير معروفة
  factory UciResponse.unknown(String rawLine) =>
      UciResponse._(type: UciResponseType.unknown, unknown: UnknownResponse(rawLine));

  @override
  String toString() {
    switch (type) {
      case UciResponseType.id:
        return 'UciResponse.id($id)';
      case UciResponseType.uciok:
        return 'UciResponse.uciok()';
      case UciResponseType.readyok:
        return 'UciResponse.readyok()';
      case UciResponseType.bestmove:
        return 'UciResponse.bestMove($bestMove)';
      case UciResponseType.info:
        return 'UciResponse.info($info)';
      case UciResponseType.option:
        return 'UciResponse.option($option)';
      case UciResponseType.unknown:
        return 'UciResponse.unknown($unknown)';
    }
  }
}

// ============================================================================
// محلل UCI الرئيسي (UciParser)
// ============================================================================

/// محلل بروتوكول UCI - يحول أسطر النص إلى كائنات UciResponse مهيكلة
///
/// الاستخدام الأساسي:
/// ```dart
/// final response = UciParser.parseLine('info depth 20 score cp 45 nodes 1234567 pv e2e4 e7e5');
/// if (response.type == UciResponseType.info) {
///   print('العمق: ${response.info!.depth}');
///   print('التقييم: ${response.info!.score}');
/// }
/// ```
///
/// المحلل مصمم ليتعامل مع:
/// - الأسطر المشوهة بأمان (يرجع UnknownResponse)
/// - جميع حقول info المعروفة
/// - التقييم من كلا المنظورين
/// - خيارات المحرك المعقدة
class UciParser {
  /// يحلل سطر واحد من استجابة UCI ويرجع UciResponse مناسبة
  ///
  /// [line] - السطر النصي القادم من المحرك
  ///
  /// يرجع UciResponse من النوع المناسب.
  /// إذا لم يتم التعرف على السطر، يرجع UnknownResponse.
  static UciResponse parseLine(String line) {
    // إزالة المسافات الزائدة من البداية والنهاية
    final trimmed = line.trim();
    if (trimmed.isEmpty) return UciResponse.unknown('');

    // تقسيم السطر إلى أجزاء
    final tokens = _tokenize(trimmed);
    if (tokens.isEmpty) return UciResponse.unknown(trimmed);

    try {
      switch (tokens[0]) {
        case 'id':
          return _parseId(tokens, trimmed);
        case 'uciok':
          return UciResponse.uciok();
        case 'readyok':
          return UciResponse.readyok();
        case 'bestmove':
          return _parseBestMove(tokens, trimmed);
        case 'info':
          return _parseInfo(tokens, trimmed);
        case 'option':
          return _parseOption(tokens, trimmed);
        default:
          return UciResponse.unknown(trimmed);
      }
    } catch (e) {
      // في حالة حدوث أي خطأ أثناء التحليل، نعيد السطر كغير معروف
      return UciResponse.unknown(trimmed);
    }
  }

  /// يحلل سطور info المتعددة ويرجع قائمة بالاستجابات
  ///
  /// مفيد لمعالجة دفعة من المعلومات دفعة واحدة
  static List<UciResponse> parseLines(List<String> lines) {
    return lines.map((line) => parseLine(line)).toList();
  }

  // ========================================================================
  // تحليل id
  // ========================================================================

  /// يحلل استجابة id
  /// `id name Stockfish 16.1`
  /// `id author the Stockfish contributors`
  static UciResponse _parseId(List<String> tokens, String rawLine) {
    if (tokens.length < 3) return UciResponse.unknown(rawLine);

    final subType = tokens[1];
    // كل شيء بعد `id name ` أو `id author ` هو القيمة
    final valueStartIndex = rawLine.indexOf(tokens[2], rawLine.indexOf(subType) + subType.length);

    if (subType == 'name') {
      final name = valueStartIndex >= 0 ? rawLine.substring(valueStartIndex).trim() : '';
      return UciResponse.id(UciIdResponse(name: name.isEmpty ? null : name));
    } else if (subType == 'author') {
      final author = valueStartIndex >= 0 ? rawLine.substring(valueStartIndex).trim() : '';
      return UciResponse.id(UciIdResponse(author: author.isEmpty ? null : author));
    }

    return UciResponse.unknown(rawLine);
  }

  // ========================================================================
  // تحليل bestmove
  // ========================================================================

  /// يحلل استجابة bestmove
  /// `bestmove e2e4 ponder e7e5`
  /// `bestmove e2e4`
  /// `bestmove (none)` - لم يجد حركة
  static UciResponse _parseBestMove(List<String> tokens, String rawLine) {
    if (tokens.length < 2) return UciResponse.unknown(rawLine);

    final bestMove = tokens[1];
    String? ponder;

    // البحث عن كلمة ponder
    final ponderIndex = tokens.indexOf('ponder');
    if (ponderIndex != -1 && ponderIndex + 1 < tokens.length) {
      ponder = tokens[ponderIndex + 1];
    }

    return UciResponse.bestMove(BestMoveResponse(
      bestMove: bestMove,
      ponder: ponder,
    ));
  }

  // ========================================================================
  // تحليل info - الأكثر تعقيداً
  // ========================================================================

  /// يحلل استجابة info - أكثر الاستجابات تعقيداً في UCI
  ///
  /// الحقول المحتملة في سطر info:
  /// depth <int>           - عمق البحث
  /// seldepth <int>        - عمق البحث الانتقائي
  /// time <int>            - الوقت بالمللي ثانية
  /// nodes <int>           - عدد العقد
  /// pv <move1> ... <movei> - خط اللعب المتوقع
  /// multipv <int>         - رقم خط اللعب (لـ MultiPV)
  /// score                 - التقييم (انظر التحليل الفرعي)
  /// currmove <move>       - الحركة الحالية قيد التحليل
  /// currmovenumber <int>  - رقم الحركة الحالية
  /// hashfull <int>        - نسبة امتلاء جدول التجزئة (per mille)
  /// nps <int>             - عدد العقد في الثانية
  /// tbhits <int>          - عدد ضربات طاولة النهاية
  /// cpuload <int>         - نسبة تحميل المعالج (per mille)
  /// string <str>          - نص عرض من المحرك
  /// refutation <move> <move1> ... <movei>  - دحض الحركة
  /// currline <cpunr> <move1> ... <movei>   - خط اللعب الحالي لمعالج معين
  ///
  /// التقييم (score):
  /// score cp <x>          - تقييم بالسنتمتر
  /// score mate <y>        - كش مات في y حركة
  /// score cp <x> lowerbound  - حد أدنى
  /// score cp <x> upperbound  - حد أعلى
  static UciResponse _parseInfo(List<String> tokens, String rawLine) {
    int? depth;
    int? selDepth;
    int? multiPv;
    EngineScore? score;
    int? nodes;
    int? nps;
    int? tbHits;
    int? timeMs;
    List<String> pv = [];
    String? currMove;
    int? currMoveNumber;
    int? hashFull;
    int? cpuload;
    String? stringDisplay;
    int? repetition;

    int i = 1; // نتخطى 'info'

    while (i < tokens.length) {
      final token = tokens[i];

      switch (token) {
        case 'depth':
          depth = _parseInt(tokens, i + 1);
          if (depth != null) i++;
          break;

        case 'seldepth':
          selDepth = _parseInt(tokens, i + 1);
          if (selDepth != null) i++;
          break;

        case 'multipv':
          multiPv = _parseInt(tokens, i + 1);
          if (multiPv != null) i++;
          break;

        case 'score':
          final scoreResult = _parseScore(tokens, i + 1);
          if (scoreResult != null) {
            score = scoreResult.score;
            i = scoreResult.nextIndex - 1; // -1 لأن i++ في نهاية الحلقة
          }
          break;

        case 'nodes':
          nodes = _parseInt(tokens, i + 1);
          if (nodes != null) i++;
          break;

        case 'nps':
          nps = _parseInt(tokens, i + 1);
          if (nps != null) i++;
          break;

        case 'tbhits':
          tbHits = _parseInt(tokens, i + 1);
          if (tbHits != null) i++;
          break;

        case 'time':
          timeMs = _parseInt(tokens, i + 1);
          if (timeMs != null) i++;
          break;

        case 'pv':
          // قراءة جميع الحركات حتى نصل لكلمة مفتاحية معروفة أو نهاية السطر
          pv = _parseMoves(tokens, i + 1);
          // لا نزيد i لأن _parseMoves تستهلك جميع الحركات
          i = tokens.length; // نخرج من الحلقة
          continue;

        case 'currmove':
          if (i + 1 < tokens.length) {
            currMove = tokens[i + 1];
            i++;
          }
          break;

        case 'currmovenumber':
          currMoveNumber = _parseInt(tokens, i + 1);
          if (currMoveNumber != null) i++;
          break;

        case 'hashfull':
          hashFull = _parseInt(tokens, i + 1);
          if (hashFull != null) i++;
          break;

        case 'cpuload':
          cpuload = _parseInt(tokens, i + 1);
          if (cpuload != null) i++;
          break;

        case 'string':
          // كل ما تبقى هو النص
          stringDisplay = tokens.sublist(i + 1).join(' ');
          i = tokens.length;
          continue;

        case 'refutation':
          // نتخطى دحض الحركات - ليست شائعة الاستخدام
          i = tokens.length;
          continue;

        case 'currline':
          // نتخطى خط اللعب الحالي - ليس شائع الاستخدام
          i = tokens.length;
          continue;

        case 'multipvline':
          // حقل غير قياسي لكن بعض المحركات تستخدمه
          final val = _parseInt(tokens, i + 1);
          if (val != null) i++;
          break;

        case 'upperbound':
        case 'lowerbound':
          // هذه تتبع حقل score مباشرة، تُعالج هناك
          break;

        default:
          // حقل غير معروف - نتخطاه
          break;
      }

      i++;
    }

    return UciResponse.info(InfoResponse(
      depth: depth,
      selDepth: selDepth,
      multiPv: multiPv,
      score: score,
      nodes: nodes,
      nps: nps,
      tbHits: tbHits,
      timeMs: timeMs,
      pv: pv,
      currMove: currMove,
      currMoveNumber: currMoveNumber,
      hashFull: hashFull,
      cpuload: cpuload,
      stringDisplay: stringDisplay,
    ));
  }

  // ========================================================================
  // تحليل score
  // ========================================================================

  /// نتيجة تحليل التقييم مع الفهرس التالي
  static _ScoreParseResult? _parseScore(List<String> tokens, int startIndex) {
    if (startIndex >= tokens.length) return null;

    final scoreType = tokens[startIndex];

    if (scoreType == 'cp') {
      final value = _parseInt(tokens, startIndex + 1);
      if (value == null) return null;

      bool lowerbound = false;
      bool upperbound = false;
      int nextIndex = startIndex + 2;

      // التحقق من وجود lowerbound/upperbound
      if (nextIndex < tokens.length) {
        if (tokens[nextIndex] == 'lowerbound') {
          lowerbound = true;
          nextIndex++;
        } else if (tokens[nextIndex] == 'upperbound') {
          upperbound = true;
          nextIndex++;
        }
      }

      return _ScoreParseResult(
        score: EngineScore(
          type: ScoreType.centipawns,
          value: value,
          lowerbound: lowerbound,
          upperbound: upperbound,
        ),
        nextIndex: nextIndex,
      );
    }

    if (scoreType == 'mate') {
      final value = _parseInt(tokens, startIndex + 1);
      if (value == null) return null;

      bool lowerbound = false;
      bool upperbound = false;
      int nextIndex = startIndex + 2;

      if (nextIndex < tokens.length) {
        if (tokens[nextIndex] == 'lowerbound') {
          lowerbound = true;
          nextIndex++;
        } else if (tokens[nextIndex] == 'upperbound') {
          upperbound = true;
          nextIndex++;
        }
      }

      return _ScoreParseResult(
        score: EngineScore(
          type: ScoreType.mate,
          value: value,
          lowerbound: lowerbound,
          upperbound: upperbound,
        ),
        nextIndex: nextIndex,
      );
    }

    return null;
  }

  // ========================================================================
  // تحليل option
  // ========================================================================

  /// يحلل استجابة option
  ///
  /// `option name Threads type spin default 1 min 1 max 1024`
  /// `option name Hash type spin default 16 min 1 max 33554432`
  /// `option name Style type combo default Normal var Normal var Aggressive var Defensive`
  /// `option name Ponder type check default true`
  /// `option name Clear Hash type button`
  /// `option name SyzygyPath type string default <empty>`
  static UciResponse _parseOption(List<String> tokens, String rawLine) {
    if (tokens.length < 5) return UciResponse.unknown(rawLine);

    // العثور على اسم الخيار - كل شيء بين `name` و `type`
    final nameStart = tokens.indexOf('name');
    final typeIndex = tokens.indexOf('type');

    if (nameStart == -1 || typeIndex == -1 || typeIndex <= nameStart + 1) {
      return UciResponse.unknown(rawLine);
    }

    // اسم الخيار قد يتكون من عدة كلمات
    final name = tokens.sublist(nameStart + 1, typeIndex).join(' ');
    final optionTypeStr = tokens[typeIndex + 1];
    final optionType = OptionType.fromString(optionTypeStr);

    String? defaultValue;
    int? min;
    int? max;
    List<String> vars = [];

    // البحث عن default
    final defaultIndex = tokens.indexOf('default');
    if (defaultIndex != -1 && defaultIndex + 1 < tokens.length) {
      defaultValue = tokens[defaultIndex + 1];
      // بعض القيم الافتراضية قد تكون "<empty>" - نحولها لـ null
      if (defaultValue == '<empty>') defaultValue = null;
    }

    // البحث عن min
    final minIndex = tokens.indexOf('min');
    if (minIndex != -1 && minIndex + 1 < tokens.length) {
      min = int.tryParse(tokens[minIndex + 1]);
    }

    // البحث عن max
    final maxIndex = tokens.indexOf('max');
    if (maxIndex != -1 && maxIndex + 1 < tokens.length) {
      max = int.tryParse(tokens[maxIndex + 1]);
    }

    // البحث عن جميع var
    for (int i = typeIndex; i < tokens.length; i++) {
      if (tokens[i] == 'var' && i + 1 < tokens.length) {
        vars.add(tokens[i + 1]);
      }
    }

    return UciResponse.option(OptionResponse(
      name: name,
      type: optionType,
      defaultValue: defaultValue,
      min: min,
      max: max,
      vars: vars,
    ));
  }

  // ========================================================================
  // دوال مساعدة
  // ========================================================================

  /// يحول سلسلة نصية إلى أجزاء مع الحفاظ على الكلمات المتصلة
  static List<String> _tokenize(String line) {
    return line.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  }

  /// يحاول قراءة عدد صحيح من الموضع المحدد
  static int? _parseInt(List<String> tokens, int index) {
    if (index >= tokens.length) return null;
    return int.tryParse(tokens[index]);
  }

  /// يقرأ سلسلة حركات UCI (pv) من الموضع المحدد حتى نهاية القائمة
  /// أو حتى الوصول لكلمة مفتاحية معروفة
  static List<String> _parseMoves(List<String> tokens, int startIndex) {
    final moves = <String>[];
    final stopWords = {
      'depth', 'seldepth', 'time', 'nodes', 'pv', 'multipv', 'score',
      'currmove', 'currmovenumber', 'hashfull', 'nps', 'tbhits',
      'cpuload', 'string', 'refutation', 'currline', 'upperbound',
      'lowerbound',
    };

    for (int i = startIndex; i < tokens.length; i++) {
      final token = tokens[i];
      // نتوقف إذا وصلنا لكلمة مفتاحية معروفة
      if (stopWords.contains(token)) break;
      // التحقق من أن النص يشبه حركة UCI (4 أحرف على الأقل)
      // الحركات تكون مثل: e2e4, e7e5, a7a8q, e1g1 (قلعة)
      if (RegExp(r'^[a-h][1-8][a-h][1-8][qnrb]?$', caseSensitive: false).hasMatch(token) ||
          RegExp(r'^[a-h][1-8][a-h][1-8]$').hasMatch(token)) {
        moves.add(token);
      } else if (token.length >= 4 && !token.contains(RegExp(r'[^\da-h]'))) {
        // بعض المحركات ترسل حركات بأشكال مختلفة - نقبلها إذا بدت معقولة
        moves.add(token);
      } else {
        // إذا لم تبدو كحركة، نتوقف
        break;
      }
    }

    return moves;
  }
}

/// نتيجة تحليل التقييم - كائن داخلي
class _ScoreParseResult {
  final EngineScore score;
  final int nextIndex;

  const _ScoreParseResult({required this.score, required this.nextIndex});
}

// ============================================================================
// دوال مساعدة للتحويل والعرض
// ============================================================================

/// دوال مساعدة لعرض معلومات UCI للمستخدم
class UciDisplayHelper {
  /// يحول الوقت بالمللي ثانية إلى سلسلة مفهومة
  ///
  /// أمثلة:
  /// - 500 → "0.5ث"
  /// - 1500 → "1.5ث"
  /// - 65000 → "1:05"
  static String formatTime(int? timeMs) {
    if (timeMs == null) return '---';
    if (timeMs < 1000) return '${timeMs}ملي ث';
    if (timeMs < 60000) {
      final seconds = timeMs / 1000.0;
      return '${seconds.toStringAsFixed(1)}ث';
    }
    final minutes = timeMs ~/ 60000;
    final seconds = (timeMs % 60000) / 1000.0;
    return '$minutes:${seconds.toStringAsFixed(0).padLeft(2, '0')}';
  }

  /// يحول عدد العقد إلى سلسلة مفهومة
  ///
  /// أمثلة:
  /// - 1234 → "1.2K"
  /// - 1234567 → "1.2M"
  /// - 1234567890 → "1.2B"
  static String formatNodes(int? nodes) {
    if (nodes == null) return '---';
    if (nodes < 1000) return nodes.toString();
    if (nodes < 1000000) return '${(nodes / 1000).toStringAsFixed(1)}K';
    if (nodes < 1000000000) return '${(nodes / 1000000).toStringAsFixed(1)}M';
    return '${(nodes / 1000000000).toStringAsFixed(1)}B';
  }

  /// يحول NPS إلى سلسلة مفهومة
  static String formatNps(int? nps) {
    if (nps == null) return '---';
    if (nps < 1000) return '$nps n/s';
    if (nps < 1000000) return '${(nps / 1000).toStringAsFixed(0)}K n/s';
    return '${(nps / 1000000).toStringAsFixed(1)}M n/s';
  }

  /// يحول العمق إلى سلسلة عرض
  static String formatDepth(int? depth, [int? selDepth]) {
    if (depth == null) return '---';
    if (selDepth != null) return '$depth/$selDepth';
    return '$depth';
  }

  /// يحول التقييم إلى سلسلة عرض بالعربية
  static String formatScore(EngineScore? score, {bool fromWhitePerspective = true, bool isWhiteToMove = true}) {
    if (score == null) return '---';

    EngineScore displayScore = score;
    if (fromWhitePerspective && !isWhiteToMove) {
      displayScore = score.fromWhitePerspective(isWhiteToMove);
    }

    return displayScore.toArabicDisplayString();
  }

  /// يحول سطر info كاملاً إلى ملخص نصي مفيد
  static String formatInfoSummary(InfoResponse info, {bool isWhiteToMove = true}) {
    final parts = <String>[];

    if (info.depth != null) {
      parts.add('العمق: ${formatDepth(info.depth, info.selDepth)}');
    }

    if (info.score != null) {
      final score = info.score!.fromWhitePerspective(isWhiteToMove);
      parts.add('التقييم: ${score.toArabicDisplayString()}');
    }

    if (info.nodes != null) {
      parts.add('العقد: ${formatNodes(info.nodes)}');
    }

    if (info.nps != null) {
      parts.add('السرعة: ${formatNps(info.nps)}');
    }

    if (info.timeMs != null) {
      parts.add('الوقت: ${formatTime(info.timeMs)}');
    }

    if (info.pv.isNotEmpty) {
      parts.add('خط اللعب: ${info.pv.take(5).join(' ')}');
    }

    return parts.join(' | ');
  }
}
