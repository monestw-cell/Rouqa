/// puzzle_screen.dart
/// شاشة حل الألغاز — Puzzle Solving Screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess/chess.dart' as chess;
import '../widgets/chess_board.dart';
import '../training/puzzles/tactical_puzzle_engine.dart';
import '../training/hint_system.dart';
import '../models/chess_models.dart';

/// مزود حالة اللغز
final puzzleProvider = StateNotifierProvider<PuzzleNotifier, PuzzleState>(
  (ref) => PuzzleNotifier(),
);

/// حالة اللغز
class PuzzleState {
  final PuzzleData? puzzle;
  final int solvedIndex;
  final bool isSolved;
  final bool isFailed;
  final int hintsUsed;
  final HintLevel currentHintLevel;
  final Hint? currentHint;
  final int ratingChange;
  final int playerRating;

  const PuzzleState({
    this.puzzle,
    this.solvedIndex = 0,
    this.isSolved = false,
    this.isFailed = false,
    this.hintsUsed = 0,
    this.currentHintLevel = HintLevel.zone,
    this.currentHint,
    this.ratingChange = 0,
    this.playerRating = 1200,
  });

  PuzzleState copyWith({
    PuzzleData? puzzle,
    int? solvedIndex,
    bool? isSolved,
    bool? isFailed,
    int? hintsUsed,
    HintLevel? currentHintLevel,
    Hint? currentHint,
    int? ratingChange,
    int? playerRating,
  }) {
    return PuzzleState(
      puzzle: puzzle ?? this.puzzle,
      solvedIndex: solvedIndex ?? this.solvedIndex,
      isSolved: isSolved ?? this.isSolved,
      isFailed: isFailed ?? this.isFailed,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      currentHintLevel: currentHintLevel ?? this.currentHintLevel,
      currentHint: currentHint ?? this.currentHint,
      ratingChange: ratingChange ?? this.ratingChange,
      playerRating: playerRating ?? this.playerRating,
    );
  }
}

/// مُخطر حالة اللغز
class PuzzleNotifier extends StateNotifier<PuzzleState> {
  final HintSystem _hintSystem = HintSystem();

  PuzzleNotifier() : super(const PuzzleState());

  /// تحميل لغز جديد
  void loadNewPuzzle({int? targetRating}) {
    final puzzle = TacticalPuzzleEngine.getPuzzleByRating(
      targetRating ?? state.playerRating,
    );
    _hintSystem.reset();
    state = PuzzleState(
      puzzle: puzzle,
      playerRating: state.playerRating,
    );
  }

  /// التحقق من حركة اللاعب
  bool checkMove(String from, String to) {
    if (state.puzzle == null || state.isSolved || state.isFailed) return false;

    final expectedUci = state.puzzle!.solution[state.solvedIndex];
    final playedUci = '$from$to';

    if (playedUci == expectedUci) {
      // حركة صحيحة
      final newIndex = state.solvedIndex + 1;
      final isComplete = newIndex >= state.puzzle!.solution.length;

      if (isComplete) {
        // حل اللغز بالكامل
        final ratingChange = _calculateRatingChange(true, state.hintsUsed);
        state = state.copyWith(
          solvedIndex: newIndex,
          isSolved: true,
          ratingChange: ratingChange,
          playerRating: state.playerRating + ratingChange,
        );
      } else {
        state = state.copyWith(solvedIndex: newIndex);
      }
      return true;
    } else {
      // حركة خاطئة
      if (state.solvedIndex == 0) {
        // أول حركة خاطئة = فشل
        final ratingChange = _calculateRatingChange(false, state.hintsUsed);
        state = state.copyWith(
          isFailed: true,
          ratingChange: ratingChange,
          playerRating: (state.playerRating + ratingChange).clamp(100, 3500),
        );
      }
      return false;
    }
  }

  /// الحصول على تلميح
  Hint getHint(String fen) {
    final hint = _hintSystem.getHint(fen);
    state = state.copyWith(
      hintsUsed: state.hintsUsed + 1,
      currentHintLevel: _hintSystem.currentLevel,
      currentHint: hint,
    );
    return hint;
  }

  /// حساب تغيير التقييم
  int _calculateRatingChange(bool success, int hintsUsed) {
    if (!success) return -8;
    final base = 10;
    final hintPenalty = hintsUsed * 2;
    return (base - hintPenalty).clamp(2, 15);
  }
}

/// شاشة حل الألغاز
class PuzzleScreen extends ConsumerStatefulWidget {
  const PuzzleScreen({super.key});

  @override
  ConsumerState<PuzzleScreen> createState() => _PuzzleScreenState();
}

class _PuzzleScreenState extends ConsumerState<PuzzleScreen>
    with TickerProviderStateMixin {
  late AnimationController _successController;
  late AnimationController _failController;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _failController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // تحميل أول لغز
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(puzzleProvider.notifier).loadNewPuzzle();
    });
  }

  @override
  void dispose() {
    _successController.dispose();
    _failController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(puzzleProvider);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'حل الألغاز',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.skip_next),
              tooltip: 'لغز جديد',
              onPressed: () => ref.read(puzzleProvider.notifier).loadNewPuzzle(),
            ),
          ],
        ),
        body: state.puzzle == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // معلومات اللغز
                  _buildPuzzleInfo(state, theme),

                  // رقعة الشطرنج
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: ChessBoard(
                          fen: state.puzzle!.fen,
                          onMove: (from, to, promotion) {
                            _handleMove(from, to);
                          },
                          enableMoveInput: !state.isSolved && !state.isFailed,
                          showCoordinates: true,
                        ),
                      ),
                    ),
                  ),

                  // منطقة التلميح
                  if (state.currentHint != null)
                    _buildHintDisplay(state.currentHint!, theme),

                  // أزرار التحكم
                  _buildControls(state, theme),

                  // رسالة النجاح أو الفشل
                  if (state.isSolved) _buildSuccessOverlay(theme),
                  if (state.isFailed) _buildFailOverlay(theme),
                ],
              ),
      ),
    );
  }

  Widget _buildPuzzleInfo(PuzzleState state, ThemeData theme) {
    final puzzle = state.puzzle!;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  puzzle.themeAr,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'الصعوبة: ${puzzle.difficultyAr} • التقييم: ${puzzle.rating}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'Tajawal',
                    color: theme.colorScheme.onSurface.withAlpha(130),
                  ),
                ),
              ],
            ),
          ),
          // تقييم اللاعب
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${state.playerRating}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHintDisplay(Hint hint, ThemeData theme) {
    final levelColor = switch (hint.level) {
      HintLevel.zone => Colors.amber.shade700,
      HintLevel.piece => Colors.orange.shade700,
      HintLevel.direction => Colors.deepOrange.shade700,
      HintLevel.fullMove => Colors.green.shade700,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: levelColor.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: levelColor.withAlpha(40)),
      ),
      child: Row(
        children: [
          Text(hint.level.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${hint.level.arabicLabel}: ${hint.textAr}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Tajawal',
                    color: levelColor,
                  ),
                ),
                if (hint.descriptionAr != null)
                  Text(
                    hint.descriptionAr!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'Tajawal',
                      color: levelColor.withAlpha(180),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(PuzzleState state, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // تلميح
          OutlinedButton.icon(
            onPressed: (state.isSolved || state.isFailed)
                ? null
                : () {
                    final hint = ref.read(puzzleProvider.notifier).getHint(
                      state.puzzle!.fen,
                    );
                    setState(() {});
                  },
            icon: const Icon(Icons.lightbulb_outline, size: 18),
            label: Text(
              'تلميح (${state.hintsUsed})',
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ),

          // لغز جديد
          ElevatedButton.icon(
            onPressed: () => ref.read(puzzleProvider.notifier).loadNewPuzzle(),
            icon: const Icon(Icons.skip_next, size: 18),
            label: const Text(
              'لغز جديد',
              style: TextStyle(fontFamily: 'Tajawal'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'أحسنت! 🎉',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Tajawal',
                  ),
                ),
                Text(
                  '+${ref.read(puzzleProvider).ratingChange} نقطة تقييم',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailOverlay(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade700, Colors.red.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.close, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'حركة خاطئة!',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Tajawal',
                  ),
                ),
                Text(
                  '${ref.read(puzzleProvider).ratingChange} نقطة تقييم',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref.read(puzzleProvider.notifier).loadNewPuzzle(),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('التالي', style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
  }

  void _handleMove(String from, String to) {
    final notifier = ref.read(puzzleProvider.notifier);
    final correct = notifier.checkMove(from, to);

    if (correct) {
      _successController.forward(from: 0);
    } else {
      _failController.forward(from: 0);
    }
  }
}
