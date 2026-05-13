import 'package:flutter/material.dart';
import '../models/chess_models.dart';
import '../widgets/common_widgets.dart';

/// Scrollable move list widget for chess analysis.
///
/// Displays moves in a horizontal scrollable grid layout with move numbers,
/// SAN notation, and classification badges. The current move is highlighted,
/// and tapping a move navigates to that position.
class MoveList extends StatefulWidget {
  /// List of analyzed moves to display.
  final List<AnalyzedMove> moves;

  /// Index of the currently selected move (-1 for starting position).
  final int currentIndex;

  /// Callback when a move is tapped.
  final ValueChanged<int> onMoveTap;

  /// Whether to use dark theme.
  final bool isDark;

  const MoveList({
    super.key,
    required this.moves,
    required this.currentIndex,
    required this.onMoveTap,
    this.isDark = true,
  });

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _moveKeys = {};

  @override
  void initState() {
    super.initState();
    _initializeKeys();
    // Scroll to current move after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentMove();
    });
  }

  @override
  void didUpdateWidget(MoveList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.moves.length != widget.moves.length) {
      _initializeKeys();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentMove();
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _initializeKeys() {
    _moveKeys.clear();
    for (int i = 0; i < widget.moves.length; i++) {
      _moveKeys[i] = GlobalKey();
    }
  }

  void _scrollToCurrentMove() {
    if (widget.currentIndex < 0 || widget.currentIndex >= widget.moves.length) return;
    final key = _moveKeys[widget.currentIndex];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.moves.isEmpty) {
      return _buildEmptyState();
    }

    // Pair moves into rows: white move + black move
    final movePairs = <_MovePair>[];
    for (int i = 0; i < widget.moves.length; i++) {
      final move = widget.moves[i];
      if (move.isWhiteMove) {
        movePairs.add(_MovePair(
          moveNumber: move.moveNumber,
          whiteMoveIndex: i,
          whiteMove: move,
          blackMoveIndex: (i + 1 < widget.moves.length && !widget.moves[i + 1].isWhiteMove)
              ? i + 1
              : null,
          blackMove: (i + 1 < widget.moves.length && !widget.moves[i + 1].isWhiteMove)
              ? widget.moves[i + 1]
              : null,
        ));
      }
    }

    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: movePairs.length,
      itemBuilder: (context, pairIndex) {
        final pair = movePairs[pairIndex];
        return _buildMovePair(pair);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'لا توجد حركات بعد - ابدأ اللعب أو الاستيراد',
          style: TextStyle(
            color: widget.isDark ? Colors.white38 : Colors.black38,
            fontFamily: 'Tajawal',
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildMovePair(_MovePair pair) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Move number — LTR لمنع انعكاس الأرقام في RTL
        Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: 32,
            alignment: Alignment.center,
            child: Text(
              '${pair.moveNumber}.',
              style: TextStyle(
                color: widget.isDark ? Colors.white38 : Colors.black38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        // White move
        if (pair.whiteMoveIndex != null)
          _buildMoveChip(
            move: pair.whiteMove!,
            moveIndex: pair.whiteMoveIndex!,
            isCurrent: widget.currentIndex == pair.whiteMoveIndex,
          ),
        // Black move
        if (pair.blackMoveIndex != null)
          _buildMoveChip(
            move: pair.blackMove!,
            moveIndex: pair.blackMoveIndex!,
            isCurrent: widget.currentIndex == pair.blackMoveIndex,
          ),
        const SizedBox(width: 2),
      ],
    );
  }

  Widget _buildMoveChip({
    required AnalyzedMove move,
    required int moveIndex,
    required bool isCurrent,
  }) {
    final bgColor = _getMoveBackgroundColor(move.classification, isCurrent);
    final textColor = _getMoveTextColor(move.classification, isCurrent);
    final borderColor = isCurrent
        ? const Color(0xFFE94560)
        : Colors.transparent;

    return GestureDetector(
      key: _moveKeys[moveIndex],
      onTap: () => widget.onMoveTap(moveIndex),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: borderColor,
            width: isCurrent ? 2.0 : 0.0,
          ),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: const Color(0xFFE94560).withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Classification indicator dot
            if (move.classification != null &&
                move.classification != MoveClassification.best &&
                move.classification != MoveClassification.good &&
                move.classification != MoveClassification.book)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: ClassificationBadge(
                  classification: move.classification!,
                  compact: true,
                ),
              ),
            // SAN text — حل مشكلة #10: TextDirection.ltr للترقيع الشطرنجي
            // منع انعكاس notation مثل Qh5+ داخل RTL
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                move.san,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getMoveBackgroundColor(MoveClassification? classification, bool isCurrent) {
    if (isCurrent) {
      return const Color(0xFFE94560).withOpacity(0.25);
    }
    if (classification == null) {
      return widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
    }

    switch (classification) {
      case MoveClassification.brilliant:
        return const Color(0xFF26A69A).withOpacity(0.15);
      case MoveClassification.great:
        return const Color(0xFF66BB6A).withOpacity(0.12);
      case MoveClassification.best:
        return widget.isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);
      case MoveClassification.good:
        return const Color(0xFF90CAF9).withOpacity(0.10);
      case MoveClassification.inaccuracy:
        return const Color(0xFFFFB74D).withOpacity(0.15);
      case MoveClassification.mistake:
        return const Color(0xFFFF8A65).withOpacity(0.15);
      case MoveClassification.blunder:
        return const Color(0xFFE57373).withOpacity(0.18);
      case MoveClassification.book:
        return const Color(0xFFCE93D8).withOpacity(0.10);
    }
  }

  Color _getMoveTextColor(MoveClassification? classification, bool isCurrent) {
    if (isCurrent) {
      return const Color(0xFFE94560);
    }
    if (classification == null) {
      return widget.isDark ? Colors.white70 : Colors.black87;
    }

    switch (classification) {
      case MoveClassification.brilliant:
        return const Color(0xFF26A69A);
      case MoveClassification.great:
        return const Color(0xFF66BB6A);
      case MoveClassification.best:
        return widget.isDark ? Colors.white70 : Colors.black87;
      case MoveClassification.good:
        return const Color(0xFF64B5F6);
      case MoveClassification.inaccuracy:
        return const Color(0xFFFFB74D);
      case MoveClassification.mistake:
        return const Color(0xFFFF8A65);
      case MoveClassification.blunder:
        return const Color(0xFFE57373);
      case MoveClassification.book:
        return const Color(0xFFCE93D8);
    }
  }
}

/// Helper class for pairing white and black moves in the same turn.
class _MovePair {
  final int moveNumber;
  final int? whiteMoveIndex;
  final AnalyzedMove? whiteMove;
  final int? blackMoveIndex;
  final AnalyzedMove? blackMove;

  const _MovePair({
    required this.moveNumber,
    this.whiteMoveIndex,
    this.whiteMove,
    this.blackMoveIndex,
    this.blackMove,
  });
}
