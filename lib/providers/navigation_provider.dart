/// navigation_provider.dart
/// مزود التنقل — Navigation State Provider
///
/// إدارة التنقل بين الحركات، قلب اللوحة، وحالة العرض.
/// تم فصل هذا عن analysis_provider لتقليل التعقيد.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/board_arrow.dart';
import '../models/chess_models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// حالة التنقل — Navigation State
// ═══════════════════════════════════════════════════════════════════════════

/// حالة التنقل والعرض
class NavigationState {
  /// FEN الموقف الحالي
  final String currentFEN;

  /// فهرس الحركة الحالية (-1 = موقف البداية)
  final int currentMoveIndex;

  /// هل اللوحة مقلوبة؟
  final bool isBoardFlipped;

  /// أسهم اللوحة
  final List<BoardArrow> arrows;

  /// اسم اللاعب الأبيض
  final String whiteName;

  /// اسم اللاعب الأسود
  final String blackName;

  /// تصنيف الأبيض
  final int? whiteElo;

  /// تصنيف الأسود
  final int? blackElo;

  const NavigationState({
    this.currentFEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    this.currentMoveIndex = -1,
    this.isBoardFlipped = false,
    this.arrows = const [],
    this.whiteName = 'الأبيض',
    this.blackName = 'الأسود',
    this.whiteElo,
    this.blackElo,
  });

  NavigationState copyWith({
    String? currentFEN,
    int? currentMoveIndex,
    bool? isBoardFlipped,
    List<BoardArrow>? arrows,
    String? whiteName,
    String? blackName,
    int? Function()? whiteElo,
    int? Function()? blackElo,
  }) {
    return NavigationState(
      currentFEN: currentFEN ?? this.currentFEN,
      currentMoveIndex: currentMoveIndex ?? this.currentMoveIndex,
      isBoardFlipped: isBoardFlipped ?? this.isBoardFlipped,
      arrows: arrows ?? this.arrows,
      whiteName: whiteName ?? this.whiteName,
      blackName: blackName ?? this.blackName,
      whiteElo: whiteElo != null ? whiteElo() : this.whiteElo,
      blackElo: blackElo != null ? blackElo() : this.blackElo,
    );
  }

  /// هل نحن في موقف البداية؟
  bool get isAtStart => currentMoveIndex == -1;

  /// هل دور الأبيض للعب؟
  bool get isWhiteToMove => currentFEN.contains(' w ');
}

// ═══════════════════════════════════════════════════════════════════════════
// مُخطر التنقل — Navigation Notifier
// ═══════════════════════════════════════════════════════════════════════════

/// مُخطر حالة التنقل
class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier() : super(const NavigationState());

  /// الانتقال إلى موقف محدد
  void navigateToPosition({
    required String fen,
    required int moveIndex,
    List<BoardArrow> arrows = const [],
  }) {
    state = state.copyWith(
      currentFEN: fen,
      currentMoveIndex: moveIndex,
      arrows: arrows,
    );
  }

  /// قلب اللوحة
  void flipBoard() {
    state = state.copyWith(isBoardFlipped: !state.isBoardFlipped);
  }

  /// تحديث أسماء اللاعبين
  void updatePlayerNames({
    String? whiteName,
    String? blackName,
    int? whiteElo,
    int? blackElo,
  }) {
    state = state.copyWith(
      whiteName: whiteName,
      blackName: blackName,
      whiteElo: whiteElo != null ? () => whiteElo : null,
      blackElo: blackElo != null ? () => blackElo : null,
    );
  }

  /// إعادة التعيين
  void reset() {
    state = const NavigationState();
  }
}

/// مزود حالة التنقل
final navigationProvider = StateNotifierProvider<NavigationNotifier, NavigationState>(
  (ref) => NavigationNotifier(),
);
