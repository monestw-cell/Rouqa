/// board_state_provider.dart
/// مزود حالة اللوحة — Board State Provider
///
/// يدير الحالة البصرية للوحة فقط (FEN، الأسهم، القلب).
/// مزود خفيف يُشتق من حالة التحليل الكاملة لتقليل إعادة البناء
/// في عناصر واجهة المستخدم التي تحتاج فقط بيانات اللوحة.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/board_arrow.dart';
import 'analysis_provider.dart';

// ============================================================================
// حالة اللوحة — Board State
// ============================================================================

/// حالة اللوحة البصرية — Visual board state
///
/// تحتوي فقط على البيانات التي تهم عرض اللوحة:
/// FEN الحالي، الأسهم، القلب، فهرس الحركة.
class BoardState {
  /// FEN الموقف الحالي
  final String currentFEN;

  /// أسهم اللوحة (حركات المحرك المقترحة)
  final List<BoardArrow> arrows;

  /// هل اللوحة مقلوبة؟
  final bool isBoardFlipped;

  /// فهرس الحركة الحالية (-1 = موقف البداية)
  final int currentMoveIndex;

  /// إجمالي عدد الحركات
  final int totalMoves;

  const BoardState({
    this.currentFEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    this.arrows = const [],
    this.isBoardFlipped = false,
    this.currentMoveIndex = -1,
    this.totalMoves = 0,
  });

  /// نسخ مع تعديل
  BoardState copyWith({
    String? currentFEN,
    List<BoardArrow>? arrows,
    bool? isBoardFlipped,
    int? currentMoveIndex,
    int? totalMoves,
  }) {
    return BoardState(
      currentFEN: currentFEN ?? this.currentFEN,
      arrows: arrows ?? this.arrows,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      totalMoves: totalMoves ?? this.totalMoves,
    );
  }

  /// هل نحن في موقف البداية؟
  bool get isAtStart => currentMoveIndex == -1;

  /// هل نحن في آخر موقف؟
  bool get isAtEnd => currentMoveIndex >= totalMoves - 1;

  /// هل دور الأبيض للعب في الموقف الحالي؟
  bool get isWhiteToMove => currentFEN.contains(' w ');
}

// ============================================================================
// مُخطر حالة اللوحة — Board State Notifier
// ============================================================================

/// مُخطر حالة اللوحة — Manages the visual board state
///
/// يستمع إلى تغييرات حالة التحليل ويُحدّث حالة اللوحة تلقائيًا.
/// يسمح أيضًا بقلب اللوحة بشكل مستقل.
class BoardStateNotifier extends StateNotifier<BoardState> {
  BoardStateNotifier() : super(const BoardState());

  /// تحديث حالة اللوحة من حالة التحليل — Update from analysis state
  void updateFromAnalysis(AnalysisState analysis) {
    state = BoardState(
      currentFEN: analysis.currentFEN,
      arrows: analysis.arrows,
      isBoardFlipped: analysis.isBoardFlipped,
      currentMoveIndex: analysis.currentMoveIndex,
      totalMoves: analysis.moves.length,
    );
  }

  /// قلب اللوحة — Flip the board
  void flipBoard() {
    state = state.copyWith(isBoardFlipped: !state.isBoardFlipped);
  }
}

// ============================================================================
// مزود Riverpod — Riverpod Provider
// ============================================================================

/// مزود حالة اللوحة — Board state provider
///
/// الاستخدام:
/// ```dart
/// // قراءة حالة اللوحة
/// final boardState = ref.watch(boardStateProvider);
///
/// // قلب اللوحة
/// ref.read(boardStateProvider.notifier).flipBoard();
/// ```
final boardStateProvider = StateNotifierProvider<BoardStateNotifier, BoardState>(
  (ref) {
    final notifier = BoardStateNotifier();

    // الاستماع إلى تغييرات حالة التحليل وتحديث حالة اللوحة
    ref.listen(analysisProvider, (previous, next) {
      notifier.updateFromAnalysis(next);
    });

    return notifier;
  },
);
