import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/analysis_provider.dart';
import '../widgets/chess_board.dart';
import '../widgets/eval_bar.dart';
import '../widgets/move_list.dart';
import '../widgets/common_widgets.dart';
import '../charts/eval_chart.dart';
import '../models/chess_models.dart';

class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  bool _showEngineLines = true;
  bool _showEvalChart = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analysisProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF0F0F5),
        appBar: _buildAppBar(state, theme, isDark),
        body: Column(
          children: [
            // Analysis progress bar
            if (state.isAnalyzing)
              _buildProgressBar(state, theme),

            // Main content area
            Expanded(
              child: Column(
                children: [
                  // Board + Eval bar section
                  Expanded(
                    flex: 5,
                    child: _buildBoardSection(state, theme, isDark),
                  ),

                  // Engine lines panel
                  if (_showEngineLines && state.engineLines.isNotEmpty)
                    _buildEngineLinesPanel(state, theme, isDark),

                  // Eval chart (toggleable)
                  if (_showEvalChart)
                    _buildEvalChartSection(state, theme, isDark),

                  // Move list
                  _buildMoveListSection(state, theme, isDark),
                ],
              ),
            ),

            // Bottom toolbar
            _buildBottomToolbar(state, theme, isDark),
          ],
        ),
        floatingActionButton: _buildFAB(state, theme, isDark),
      ),
    );
  }

  // ─── App Bar ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(AnalysisState state, ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor: isDark ? const Color(0xFF16213E) : const Color(0xFF2C3E50),
      foregroundColor: Colors.white,
      elevation: 2,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تحليل الشطرنج',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          if (state.summary != null)
            Text(
              state.summary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white70,
                fontFamily: 'Tajawal',
              ),
            ),
        ],
      ),
      actions: [
        // Toggle engine lines
        IconButton(
          icon: Icon(
            _showEngineLines ? Icons.visibility : Icons.visibility_off,
            color: _showEngineLines ? Colors.amber : Colors.white54,
          ),
          tooltip: 'خطوط المحرك',
          onPressed: () => setState(() => _showEngineLines = !_showEngineLines),
        ),
        // Toggle eval chart
        IconButton(
          icon: Icon(
            Icons.show_chart,
            color: _showEvalChart ? Colors.amber : Colors.white54,
          ),
          tooltip: 'رسم التقييم',
          onPressed: () => setState(() => _showEvalChart = !_showEvalChart),
        ),
        // Settings
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: Colors.white70),
          tooltip: 'الإعدادات',
          onPressed: () => _showSettingsDialog(context),
        ),
      ],
    );
  }

  // ─── Progress Bar ─────────────────────────────────────────────────────────

  Widget _buildProgressBar(AnalysisState state, ThemeData theme) {
    return Column(
      children: [
        LinearProgressIndicator(
          value: state.analysisProgress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation<Color>(
            _getProgressColor(state.analysisProgress),
          ),
          minHeight: 3,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'جاري التحليل...',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'Tajawal',
                ),
              ),
              Text(
                '${(state.analysisProgress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'Tajawal',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getProgressColor(double progress) {
    if (progress < 0.3) return Colors.orange;
    if (progress < 0.7) return Colors.amber;
    return Colors.green;
  }

  // ─── Board Section (EvalBar + Board) ──────────────────────────────────────

  Widget _buildBoardSection(AnalysisState state, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Eval bar
              EvalBar(
                evalScore: state.evalScore,
                isAnalyzing: state.isAnalyzing,
                height: availableHeight,
              ),
              const SizedBox(width: 4),
              // Chess board
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: availableHeight,
                    height: availableHeight,
                    child: ChessBoard(
                      fen: state.currentFEN,
                      onMove: (move) {
                        ref.read(analysisProvider.notifier).makeMove(move);
                      },
                      arrows: state.arrows,
                      boardTheme: isDark
                          ? BoardTheme.dark
                          : BoardTheme.green,
                      showCoordinates: true,
                      isFlipped: state.isFlipped,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          );
        },
      ),
    );
  }

  // ─── Engine Lines Panel ───────────────────────────────────────────────────

  Widget _buildEngineLinesPanel(AnalysisState state, ThemeData theme, bool isDark) {
    final topLines = state.engineLines.take(3).toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 140),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.psychology,
                  size: 16,
                  color: isDark ? Colors.amber : Colors.deepOrange,
                ),
                const SizedBox(width: 6),
                Text(
                  'خطوط المحرك',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.amber : Colors.deepOrange,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const Spacer(),
                if (state.engineLines.isNotEmpty)
                  Text(
                    'عمق: ${state.engineLines.first.depth}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontFamily: 'Tajawal',
                    ),
                  ),
              ],
            ),
          ),
          ...topLines.map((line) => EngineLineCard(
            line: line,
            isDark: isDark,
          )),
        ],
      ),
    );
  }

  // ─── Eval Chart Section ───────────────────────────────────────────────────

  Widget _buildEvalChartSection(AnalysisState state, ThemeData theme, bool isDark) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: EvalChart(
        moves: state.moves,
        currentMoveIndex: state.currentMoveIndex,
        isDark: isDark,
      ),
    );
  }

  // ─── Move List Section ────────────────────────────────────────────────────

  Widget _buildMoveListSection(AnalysisState state, ThemeData theme, bool isDark) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F3460) : const Color(0xFFE8EAF0),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Icon(
                  Icons.format_list_numbered,
                  size: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(width: 4),
                Text(
                  'قائمة الحركات',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const Spacer(),
                Text(
                  '${state.moves.length} حركة',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ],
            ),
          ),
          // Move list
          Expanded(
            child: MoveList(
              moves: state.moves,
              currentIndex: state.currentMoveIndex,
              onMoveTap: (index) {
                ref.read(analysisProvider.notifier).goToMove(index);
              },
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Toolbar ───────────────────────────────────────────────────────

  Widget _buildBottomToolbar(AnalysisState state, ThemeData theme, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16213E) : const Color(0xFF2C3E50),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Go to start
              _toolbarButton(
                icon: Icons.skip_previous,
                label: 'البداية',
                onTap: () => ref.read(analysisProvider.notifier).goToStart(),
                isDark: isDark,
              ),
              // Go back
              _toolbarButton(
                icon: Icons.arrow_back,
                label: 'رجوع',
                onTap: () => ref.read(analysisProvider.notifier).goBack(),
                isDark: isDark,
              ),
              // Go forward
              _toolbarButton(
                icon: Icons.arrow_forward,
                label: 'تقدم',
                onTap: () => ref.read(analysisProvider.notifier).goForward(),
                isDark: isDark,
              ),
              // Go to end
              _toolbarButton(
                icon: Icons.skip_next,
                label: 'النهاية',
                onTap: () => ref.read(analysisProvider.notifier).goToEnd(),
                isDark: isDark,
              ),
              // Divider
              SizedBox(
                height: 28,
                child: VerticalDivider(
                  color: Colors.white24,
                  width: 1,
                ),
              ),
              // Flip board
              _toolbarButton(
                icon: Icons.flip,
                label: 'قلب',
                onTap: () => ref.read(analysisProvider.notifier).flipBoard(),
                isDark: isDark,
                highlight: state.isFlipped,
              ),
              // Share
              _toolbarButton(
                icon: Icons.share_outlined,
                label: 'مشاركة',
                onTap: () => _shareAnalysis(context, state),
                isDark: isDark,
              ),
              // Settings
              _toolbarButton(
                icon: Icons.tune,
                label: 'إعدادات',
                onTap: () => _showSettingsDialog(context),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool highlight = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: highlight
                    ? Colors.amber
                    : (isDark ? Colors.white70 : Colors.white70),
                size: 20,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: highlight
                      ? Colors.amber
                      : (isDark ? Colors.white54 : Colors.white54),
                  fontSize: 9,
                  fontFamily: 'Tajawal',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── FAB ──────────────────────────────────────────────────────────────────

  Widget? _buildFAB(AnalysisState state, ThemeData theme, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: FloatingActionButton.extended(
        onPressed: () {
          if (state.isAnalyzing) {
            ref.read(analysisProvider.notifier).stopAnalysis();
          } else {
            ref.read(analysisProvider.notifier).startAnalysis();
          }
        },
        backgroundColor: state.isAnalyzing
            ? Colors.red.shade700
            : const Color(0xFF0F3460),
        foregroundColor: Colors.white,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: state.isAnalyzing
              ? const Icon(Icons.stop, key: 'stop')
              : const Icon(Icons.play_arrow, key: 'play'),
        ),
        label: Text(
          state.isAnalyzing ? 'إيقاف التحليل' : 'بدء التحليل',
          style: const TextStyle(
            fontFamily: 'Tajawal',
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'إعدادات التحليل',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text(
                  'إظهار خطوط المحرك',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
                value: _showEngineLines,
                onChanged: (v) {
                  setState(() => _showEngineLines = v);
                  Navigator.pop(context);
                },
              ),
              SwitchListTile(
                title: const Text(
                  'رسم بياني للتقييم',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
                value: _showEvalChart,
                onChanged: (v) {
                  setState(() => _showEvalChart = v);
                  Navigator.pop(context);
                },
              ),
              const ListTile(
                leading: Icon(Icons.speed),
                title: Text(
                  'عمق التحليل',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
                subtitle: Text(
                  '20 عمق',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.line_style),
                title: Text(
                  'عدد الخطوط',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
                subtitle: Text(
                  '3 خطوط',
                  style: TextStyle(fontFamily: 'Tajawal'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontFamily: 'Tajawal'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _shareAnalysis(BuildContext context, AnalysisState state) {
    // Build shareable PGN-like text
    final buffer = StringBuffer();
    buffer.writeln('تحليل رقعة - Ruq\'a Chess Analyzer');
    buffer.writeln('التقييم: ${_formatEval(state.evalScore)}');
    if (state.summary != null) {
      buffer.writeln('الملخص: ${state.summary}');
    }
    buffer.writeln();
    for (int i = 0; i < state.moves.length; i++) {
      final move = state.moves[i];
      if (move.isWhiteMove) {
        buffer.write('${move.moveNumber}. ');
      }
      buffer.write('${move.san} ');
      if (move.classification != null) {
        buffer.write('${_classificationSymbol(move.classification!)} ');
      }
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مشاركة التحليل',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  buffer.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Copy to clipboard logic
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تم النسخ إلى الحافظة',
                              style: TextStyle(fontFamily: 'Tajawal'),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text(
                        'نسخ',
                        style: TextStyle(fontFamily: 'Tajawal'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatEval(double evalScore) {
    if (evalScore.abs() > 900) {
      final mateIn = (1000 - evalScore.abs()).toInt();
      return evalScore > 0 ? 'كش مات في $mateIn' : 'كش مات في -$mateIn';
    }
    final sign = evalScore > 0 ? '+' : '';
    return '$sign${evalScore.toStringAsFixed(1)}';
  }

  String _classificationSymbol(MoveClassification classification) {
    switch (classification) {
      case MoveClassification.brilliant:
        return '★★';
      case MoveClassification.great:
        return '★';
      case MoveClassification.best:
        return '!'; 
      case MoveClassification.good:
        return '✓';
      case MoveClassification.inaccuracy:
        return '?!';
      case MoveClassification.mistake:
        return '?';
      case MoveClassification.blunder:
        return '??';
      case MoveClassification.book:
        return '📖';
    }
  }
}
