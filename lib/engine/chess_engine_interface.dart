/// chess_engine_interface.dart
/// واجهة محرك الشطرنج المشتركة — Chess Engine Interface
///
/// تحدد الواجهة المشتركة بين جميع محركات الشطرنج:
/// - StockfishEngine (Process-based)
/// - StockfishPackageEngine (Package/FFI-based)
///
/// هذا يسمح للتطبيق بالعمل مع أي محرك بدون تغيير الكود.

import 'dart:async';

import 'uci_protocol.dart';
import 'stockfish_engine.dart' show EngineState, StockfishException;

/// واجهة محرك الشطرنج — Chess Engine Interface
///
/// يجب أن يحققها أي محرك شطرنج يُستخدم في التطبيق.
/// توفر واجهة موحدة للتحليل وإدارة اللعبة.
abstract class ChessEngine {
  // ── الحالة ─────────────────────────────────────────────────────────────

  /// حالة المحرك الحالية
  EngineState get state;

  /// هل المحرك جاهز؟
  bool get isReady;

  /// هل المحرك يحلل حالياً؟
  bool get isAnalyzing;

  /// هل المحرك تم التخلص منه؟
  bool get isDisposed;

  /// هل دور الأبيض للعب؟
  bool get isWhiteToMove;

  /// اسم المحرك
  String? get engineName;

  /// آخر تحليل info لكل خط MultiPV
  Map<int, InfoResponse> get latestInfoByPv;

  /// آخر تحليل info تم استلامه
  InfoResponse? get lastInfoResponse;

  /// تدفق استجابات UCI الحية
  Stream<UciResponse> get responses;

  /// هل المحرك يعتمد على الحزمة؟
  bool get isPackageBased;

  // ── Callbacks ──────────────────────────────────────────────────────────

  /// يُستدعى عند تلقي تحليل جديد
  void Function(InfoResponse info)? onAnalysisUpdate;

  /// يُستدعى عند العثور على أفضل حركة
  void Function(BestMoveResponse bestMove)? onBestMove;

  /// يُستدعى عندما يصبح المحرك جاهزاً
  void Function()? onReady;

  /// يُستدعى عند حدوث خطأ
  void Function(StockfishException error)? onError;

  /// يُستدعى عند تغير حالة المحرك
  void Function(EngineState state)? onStateChanged;

  /// يُستدعى عند تلقي أي استجابة UCI
  void Function(UciResponse response)? onRawResponse;

  // ── التهيئة والإغلاق ─────────────────────────────────────────────────

  /// تهيئة المحرك
  Future<void> initialize();

  /// إغلاق المحرك وتحرير الموارد
  Future<void> dispose();

  // ── إرسال الأوامر ────────────────────────────────────────────────────

  /// إرسال أمر UCI
  void sendCommand(String command);

  // ── إعداد الخيارات ───────────────────────────────────────────────────

  /// ضبط عدد الخيوط
  void setThreads(int threads);

  /// ضبط حجم التجزئة (MB)
  void setHashSize(int sizeMb);

  /// ضبط عدد خطوط MultiPV
  void setMultiPv(int lines);

  /// ضبط مستوى المهارة
  void setSkillLevel(int level);

  /// ضبط مستوى ELO
  void setElo(int elo);

  /// ضبط خيار عام
  void setOption(String name, String value);

  /// مسح التجزئة
  void clearHash();

  // ── إعداد الموقف ─────────────────────────────────────────────────────

  /// ضبط الموقف من وضع البداية
  void setPositionFromStart({List<String> moves});

  /// ضبط الموقف من FEN
  void setPositionFromFen(String fen, {List<String> moves});

  // ── التحليل ──────────────────────────────────────────────────────────

  /// التحليل بعمق محدد
  Future<BestMoveResponse> analyzeDepth(int depth);

  /// التحليل بوقت محدد
  Future<BestMoveResponse> analyzeTime(int timeMs);

  /// التحليل بقيود زمنية
  Future<BestMoveResponse> analyzeWithTimeControls({
    int? wtime,
    int? btime,
    int? winc,
    int? binc,
    int? movestogo,
    int? depth,
    int? nodes,
  });

  /// تحليل غير محدود
  void analyzeInfinite();

  /// إيقاف التحليل
  Future<BestMoveResponse?> stopAnalysis();

  /// إيقاف التحليل فوراً
  void stopAnalysisImmediate();
}
