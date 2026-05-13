import 'package:flutter/material.dart';
import '../models/chess_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Loading Overlay
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen semi-transparent loading overlay with a spinner and message.
class LoadingOverlay extends StatelessWidget {
  final String message;
  final double? progress;

  const LoadingOverlay({
    super.key,
    this.message = 'جاري التحميل...',
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spinner
              if (progress != null)
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 4,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF5DADE2),
                        ),
                      ),
                      Text(
                        '${(progress! * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF5DADE2),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Message
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontFamily: 'Tajawal',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Error display widget with icon, message, and retry button.
class AppErrorWidget extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const AppErrorWidget({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: Colors.red.shade300,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontFamily: 'Tajawal',
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE94560),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontFamily: 'Tajawal',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Classification Badge
// ─────────────────────────────────────────────────────────────────────────────

/// Badge showing move classification with symbol and color.
///
/// Supports compact mode (dot + symbol) and full mode (symbol + Arabic label).
class ClassificationBadge extends StatelessWidget {
  final MoveClassification classification;
  final bool compact;

  const ClassificationBadge({
    super.key,
    required this.classification,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final info = _classificationInfo(classification);

    if (compact) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: info.color.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(
            color: info.color.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            info.symbol,
            style: TextStyle(
              color: info.color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: info.color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: info.color.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.symbol,
            style: TextStyle(
              color: info.color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            info.arabicLabel,
            style: TextStyle(
              color: info.color,
              fontSize: 10,
              fontFamily: 'Tajawal',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static _ClassificationInfo _classificationInfo(MoveClassification classification) {
    switch (classification) {
      case MoveClassification.brilliant:
        return _ClassificationInfo(
          symbol: '★★',
          arabicLabel: 'ممتاز',
          color: const Color(0xFF26A69A),
        );
      case MoveClassification.great:
        return _ClassificationInfo(
          symbol: '★',
          arabicLabel: 'رائع',
          color: const Color(0xFF66BB6A),
        );
      case MoveClassification.best:
        return _ClassificationInfo(
          symbol: '!',
          arabicLabel: 'أفضل',
          color: const Color(0xFF90CAF9),
        );
      case MoveClassification.good:
        return _ClassificationInfo(
          symbol: '✓',
          arabicLabel: 'جيد',
          color: const Color(0xFF64B5F6),
        );
      case MoveClassification.inaccuracy:
        return _ClassificationInfo(
          symbol: '?!',
          arabicLabel: 'عدم دقة',
          color: const Color(0xFFFFB74D),
        );
      case MoveClassification.mistake:
        return _ClassificationInfo(
          symbol: '?',
          arabicLabel: 'خطأ',
          color: const Color(0xFFFF8A65),
        );
      case MoveClassification.blunder:
        return _ClassificationInfo(
          symbol: '??',
          arabicLabel: 'خطأ فادح',
          color: const Color(0xFFE57373),
        );
      case MoveClassification.book:
        return _ClassificationInfo(
          symbol: '📖',
          arabicLabel: 'كتاب',
          color: const Color(0xFFCE93D8),
        );
    }
  }
}

class _ClassificationInfo {
  final String symbol;
  final String arabicLabel;
  final Color color;

  const _ClassificationInfo({
    required this.symbol,
    required this.arabicLabel,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Engine Line Card
// ─────────────────────────────────────────────────────────────────────────────

/// Card displaying a single engine analysis line (PV) with evaluation.
class EngineLineCard extends StatelessWidget {
  final EngineLine line;
  final bool isDark;

  const EngineLineCard({
    super.key,
    required this.line,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final evalText = _formatEval();
    final evalColor = _getEvalColor();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        children: [
          // Line number indicator
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _getLineBackgroundColor(),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${line.id}',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Eval display
          Container(
            constraints: const BoxConstraints(minWidth: 50),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: evalColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              evalText,
              style: TextStyle(
                color: evalColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),

          // PV (Principal Variation) moves
          Expanded(
            child: Text(
              line.pv,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
            ),
          ),

          // Depth
          if (line.depth > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                'd${line.depth}',
                style: TextStyle(
                  color: isDark ? Colors.white24 : Colors.black26,
                  fontSize: 9,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatEval() {
    if (line.mateScore != null) {
      final mate = int.tryParse(line.mateScore!) ?? 0;
      if (mate > 0) return '+M$mate';
      return '-M${mate.abs()}';
    }
    final eval = line.evalScore ?? 0.0;
    final sign = eval > 0 ? '+' : '';
    return '$sign${eval.toStringAsFixed(1)}';
  }

  Color _getEvalColor() {
    if (line.mateScore != null) {
      final mate = int.tryParse(line.mateScore!) ?? 0;
      return mate > 0 ? Colors.green.shade400 : Colors.red.shade400;
    }
    final eval = line.evalScore ?? 0.0;
    if (eval > 2.0) return Colors.green.shade400;
    if (eval > 0.5) return const Color(0xFF66BB6A);
    if (eval > -0.5) return Colors.amber.shade400;
    if (eval > -2.0) return Colors.orange.shade400;
    return Colors.red.shade400;
  }

  Color _getLineBackgroundColor() {
    switch (line.id) {
      case 1:
        return const Color(0xFF5DADE2).withOpacity(0.2);
      case 2:
        return const Color(0xFF66BB6A).withOpacity(0.2);
      case 3:
        return const Color(0xFFFFB74D).withOpacity(0.2);
      default:
        return (isDark ? Colors.white : Colors.black).withOpacity(0.05);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Game Result Chip
// ─────────────────────────────────────────────────────────────────────────────

/// Chip displaying game result (1-0, 0-1, ½-½, *) with color coding.
class GameResultChip extends StatelessWidget {
  final String result;
  final double fontSize;

  const GameResultChip({
    super.key,
    required this.result,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, textColor, icon) = _getResultStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: textColor.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: fontSize, color: textColor),
          const SizedBox(width: 3),
          Text(
            _getResultArabic(),
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
        ],
      ),
    );
  }

  (Color, Color, IconData) _getResultStyle() {
    switch (result) {
      case '1-0':
        return (Colors.green.shade900.withOpacity(0.3), Colors.green.shade300, Icons.emoji_events);
      case '0-1':
        return (Colors.red.shade900.withOpacity(0.3), Colors.red.shade300, Icons.emoji_events_outlined);
      case '½-½':
        return (Colors.grey.shade700.withOpacity(0.3), Colors.grey.shade300, Icons.handshake_outlined);
      default:
        return (Colors.blue.shade900.withOpacity(0.3), Colors.blue.shade300, Icons.help_outline);
    }
  }

  String _getResultArabic() {
    switch (result) {
      case '1-0':
        return 'فوز الأبيض';
      case '0-1':
        return 'فوز الأسود';
      case '½-½':
        return 'تعادل';
      case '*':
        return 'قيد اللعب';
      default:
        return result;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analysis Progress Indicator
// ─────────────────────────────────────────────────────────────────────────────

/// Circular or linear progress indicator with analysis depth info.
class AnalysisProgressIndicator extends StatelessWidget {
  final double progress;
  final int depth;
  final int nodes;
  final int speed; // kn/s
  final bool isCompact;

  const AnalysisProgressIndicator({
    super.key,
    required this.progress,
    required this.depth,
    this.nodes = 0,
    this.speed = 0,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 2,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5DADE2)),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'عمق $depth',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontFamily: 'Tajawal',
          ),
        ),
      ],
    );
  }

  Widget _buildFull() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
              const Text(
                'تقدم التحليل',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Color(0xFF5DADE2),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5DADE2)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _statItem('العمق', '$depth'),
              if (nodes > 0) _statItem('العقد', _formatNumber(nodes)),
              if (speed > 0) _statItem('السرعة', '${_formatNumber(speed)} kn/s'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontFamily: 'Tajawal',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}
