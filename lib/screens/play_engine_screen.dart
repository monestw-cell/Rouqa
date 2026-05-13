/// play_engine_screen.dart
/// شاشة اللعب ضد المحرك — Play vs Engine Screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chess/chess.dart' as chess;
import '../widgets/chess_board.dart';
import '../training/training_engine.dart';
import '../models/chess_models.dart';

/// مزود محرك التدريب
final trainingEngineProvider = StateNotifierProvider<PlayEngineNotifier, PlayEngineState>(
  (ref) => PlayEngineNotifier(),
);

/// حالة اللعب ضد المحرك
class PlayEngineState {
  final TrainingEngine engine;
  final TrainingGameState? gameState;
  final int engineElo;
  final bool userPlaysWhite;
  final bool isNewGame;

  const PlayEngineState({
    required this.engine,
    this.gameState,
    this.engineElo = 1500,
    this.userPlaysWhite = true,
    this.isNewGame = true,
  });

  PlayEngineState copyWith({
    TrainingGameState? gameState,
    int? engineElo,
    bool? userPlaysWhite,
    bool? isNewGame,
  }) {
    return PlayEngineState(
      engine: engine,
      gameState: gameState ?? this.gameState,
      engineElo: engineElo ?? this.engineElo,
      userPlaysWhite: userPlaysWhite ?? this.userPlaysWhite,
      isNewGame: isNewGame ?? this.isNewGame,
    );
  }
}

/// مُخطر حالة اللعب
class PlayEngineNotifier extends StateNotifier<PlayEngineState> {
  PlayEngineNotifier() : super(PlayEngineState(engine: TrainingEngine()));

  /// بدء لعبة جديدة
  Future<void> startNewGame({int? elo, bool? userPlaysWhite}) async {
    final e = elo ?? state.engineElo;
    final u = userPlaysWhite ?? state.userPlaysWhite;

    state = PlayEngineState(
      engine: TrainingEngine(),
      engineElo: e,
      userPlaysWhite: u,
      isNewGame: false,
    );

    state.engine.onStateChanged = (gameState) {
      if (mounted) {
        state = state.copyWith(gameState: gameState);
      }
    };

    state.engine.onGameEnded = (status, message) {
      if (mounted) {
        // سيتم التعامل معها في الشاشة
      }
    };

    await state.engine.newGame(engineElo: e, userPlaysWhite: u);
  }

  /// تنفيذ حركة
  bool makeMove(String from, String to, {String? promotion}) {
    return state.engine.makePlayerMove(from, to, promotion: promotion);
  }

  /// تغيير ELO
  void setElo(int elo) {
    state = state.copyWith(engineElo: elo);
  }

  /// تغيير لون اللاعب
  void setUserColor(bool isWhite) {
    state = state.copyWith(userPlaysWhite: isWhite);
  }

  /// الاستسلام
  void resign() {
    state.engine.resign();
  }

  /// عرض التعادل
  void offerDraw() {
    state.engine.offerDraw();
  }

  @override
  void dispose() {
    state.engine.dispose();
    super.dispose();
  }
}

/// شاشة اللعب ضد المحرك
class PlayEngineScreen extends ConsumerStatefulWidget {
  const PlayEngineScreen({super.key});

  @override
  ConsumerState<PlayEngineScreen> createState() => _PlayEngineScreenState();
}

class _PlayEngineScreenState extends ConsumerState<PlayEngineScreen> {
  int _selectedElo = 1500;
  bool _userPlaysWhite = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(trainingEngineProvider);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'العب ضد المحرك',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'لعبة جديدة',
              onPressed: () => _showNewGameDialog(),
            ),
          ],
        ),
        body: state.isNewGame
            ? _buildNewGameSetup(theme)
            : _buildGameView(state, theme),
      ),
    );
  }

  Widget _buildNewGameSetup(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان
          Center(
            child: Column(
              children: [
                Icon(
                  Icons.sports_esports,
                  size: 64,
                  color: theme.colorScheme.primary.withAlpha(150),
                ),
                const SizedBox(height: 12),
                Text(
                  'العب ضد المحرك',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'اختر مستوى الصعوبة وابدأ اللعب',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Tajawal',
                    color: theme.colorScheme.onSurface.withAlpha(130),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // مستوى ELO
          Text(
            'مستوى المحرك: $_selectedElo ELO',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getEloDescription(_selectedElo),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Tajawal',
              color: theme.colorScheme.onSurface.withAlpha(100),
            ),
          ),
          Slider(
            value: _selectedElo.toDouble(),
            min: 800,
            max: 3200,
            divisions: 48,
            label: '$_selectedElo',
            onChanged: (v) => setState(() => _selectedElo = v.round()),
          ),

          // اختيار اللون
          const SizedBox(height: 20),
          Text(
            'اختر لونك',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ColorChoiceCard(
                  label: '♔ أبيض',
                  isSelected: _userPlaysWhite,
                  onTap: () => setState(() => _userPlaysWhite = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ColorChoiceCard(
                  label: '♚ أسود',
                  isSelected: !_userPlaysWhite,
                  onTap: () => setState(() => _userPlaysWhite = false),
                ),
              ),
            ],
          ),

          const Spacer(),

          // زر البدء
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ref.read(trainingEngineProvider.notifier).startNewGame(
                  elo: _selectedElo,
                  userPlaysWhite: _userPlaysWhite,
                );
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text(
                'ابدأ اللعب',
                style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildGameView(PlayEngineState state, ThemeData theme) {
    final gs = state.gameState;

    return Column(
      children: [
        // شريط معلومات الخصم
        _buildPlayerBar(
          name: 'المحرك (${state.engineElo})',
          isWhite: !state.userPlaysWhite,
          capturedPieces: state.userPlaysWhite
              ? (gs?.capturedByBlack ?? [])
              : (gs?.capturedByWhite ?? []),
          timeMs: state.userPlaysWhite ? gs?.blackTimeMs : gs?.whiteTimeMs,
          theme: theme,
        ),

        // رقعة الشطرنج
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: ChessBoard(
                fen: gs?.fen ?? chess.Chess().fen,
                onMove: (from, to, promotion) {
                  ref.read(trainingEngineProvider.notifier).makeMove(
                    from,
                    to,
                    promotion: promotion,
                  );
                },
                flipped: !state.userPlaysWhite,
                enableMoveInput: gs?.isPlaying ?? false,
                showCoordinates: true,
              ),
            ),
          ),
        ),

        // شريط معلومات اللاعب
        _buildPlayerBar(
          name: 'أنت',
          isWhite: state.userPlaysWhite,
          capturedPieces: state.userPlaysWhite
              ? (gs?.capturedByWhite ?? [])
              : (gs?.capturedByBlack ?? []),
          timeMs: state.userPlaysWhite ? gs?.whiteTimeMs : gs?.blackTimeMs,
          theme: theme,
        ),

        // قائمة الحركات
        if (gs != null && gs.movesSan.isNotEmpty)
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: gs.movesSan.length,
              itemBuilder: (context, index) {
                final moveNum = (index ~/ 2) + 1;
                final isWhiteMove = index % 2 == 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isWhiteMove
                          ? Colors.white.withAlpha(15)
                          : Colors.black.withAlpha(15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isWhiteMove ? '$moveNum. ${gs.movesSan[index]}' : gs.movesSan[index],
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withAlpha(180),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // أزرار التحكم
        _buildGameControls(state, theme),
      ],
    );
  }

  Widget _buildPlayerBar({
    required String name,
    required bool isWhite,
    required List<String> capturedPieces,
    required int? timeMs,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // أيقونة اللاعب
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isWhite ? Colors.white : const Color(0xFF333333),
              shape: BoxShape.circle,
              border: Border.all(color: theme.colorScheme.primary.withAlpha(50)),
            ),
            child: Center(
              child: Text(
                isWhite ? '♔' : '♚',
                style: TextStyle(
                  fontSize: 16,
                  color: isWhite ? Colors.black : Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // الاسم
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
          // القطع المأسورة
          if (capturedPieces.isNotEmpty)
            Text(
              capturedPieces.take(8).join(' '),
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(width: 8),
          // الساعة
          if (timeMs != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatTime(timeMs),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGameControls(PlayEngineState state, ThemeData theme) {
    final gs = state.gameState;
    final isPlaying = gs?.isPlaying ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // استسلام
          TextButton.icon(
            onPressed: isPlaying
                ? () {
                    ref.read(trainingEngineProvider.notifier).resign();
                    _showGameResultDialog('استسلمت. خسارة!', theme);
                  }
                : null,
            icon: const Icon(Icons.flag, size: 18),
            label: const Text('استسلام', style: TextStyle(fontFamily: 'Tajawal')),
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          ),
          // تعادل
          TextButton.icon(
            onPressed: isPlaying
                ? () {
                    ref.read(trainingEngineProvider.notifier).offerDraw();
                  }
                : null,
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const Text('تعادل', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          // لعبة جديدة
          ElevatedButton.icon(
            onPressed: () => _showNewGameDialog(),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('جديدة', style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    );
  }

  String _getEloDescription(int elo) {
    if (elo < 1000) return 'مبتدئ — حركات بسيطة وأخطاء كثيرة';
    if (elo < 1400) return 'متوسط — يلعب بشكل معقول';
    if (elo < 1800) return 'متقدم — تكتيك جيد';
    if (elo < 2200) return 'خبير — حرفية عالية';
    if (elo < 2800) return 'أستاذ — مستوى احترافي';
    return 'خارق — مستوى المحرك الكامل';
  }

  String _formatTime(int? ms) {
    if (ms == null) return '--:--';
    final seconds = (ms / 1000).floor();
    final mins = (seconds / 60).floor();
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showNewGameDialog() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('لعبة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('مستوى ELO: $_selectedElo', style: const TextStyle(fontFamily: 'Tajawal')),
              Slider(
                value: _selectedElo.toDouble(),
                min: 800,
                max: 3200,
                divisions: 48,
                onChanged: (v) {
                  setState(() => _selectedElo = v.round());
                  Navigator.pop(context);
                  _showNewGameDialog();
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('♔ أبيض', style: TextStyle(fontFamily: 'Tajawal')),
                      selected: _userPlaysWhite,
                      onSelected: (_) {
                        setState(() => _userPlaysWhite = true);
                        Navigator.pop(context);
                        _showNewGameDialog();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('♚ أسود', style: TextStyle(fontFamily: 'Tajawal')),
                      selected: !_userPlaysWhite,
                      onSelected: (_) {
                        setState(() => _userPlaysWhite = false);
                        Navigator.pop(context);
                        _showNewGameDialog();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(trainingEngineProvider.notifier).startNewGame(
                  elo: _selectedElo,
                  userPlaysWhite: _userPlaysWhite,
                );
              },
              child: const Text('ابدأ', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
  }

  void _showGameResultDialog(String message, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Text(message, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 16)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(trainingEngineProvider.notifier).startNewGame(
                  elo: _selectedElo,
                  userPlaysWhite: _userPlaysWhite,
                );
              },
              child: const Text('لعبة جديدة', style: TextStyle(fontFamily: 'Tajawal')),
            ),
          ],
        ),
      ),
    );
  }
}

/// بطاقة اختيار اللون
class _ColorChoiceCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorChoiceCard({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withAlpha(15)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
              color: isSelected ? theme.colorScheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}
