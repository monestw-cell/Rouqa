/// eval_bar.dart
/// ويدجت شريط التقييم العمودي (إصلاح #15)
///
/// يحل مشكلة تأخر شريط التقييم (Eval Bar Lag)
/// باستخدام ValueNotifier<double> بدل rebuild كامل للشاشة.
///
/// كيف يحلها ChessIs:
/// - Eval layer منفصلة
/// - AnimatedBuilder / ValueNotifier<double>
///
/// في Flutter:
/// - ValueNotifier<double> للـ eval
/// - AnimatedBuilder بدل setState على الشاشة كاملة
/// - RepaintBoundary للطبقة المنفصلة

import 'package:flutter/material.dart';

/// شريط التقييم العمودي — Eval Bar
///
/// يستخدم ValueNotifier<double> للتحديث الفوري بدون
/// إعادة بناء الشاشة كاملة.
///
/// الاستخدام:
/// ```dart
/// // إنشاء ValueNotifier
/// final evalNotifier = ValueNotifier<double>(0.0);
///
/// // في الشجرة
/// EvalBar(
///   evalNotifier: evalNotifier,
///   isAnalyzingNotifier: analyzingNotifier,
///   height: 400,
/// )
///
/// // تحديث التقييم (بدون rebuild)
/// evalNotifier.value = 1.5;
/// ```
class EvalBar extends StatelessWidget {
  /// ValueNotifier للتقييم الحالي (إصلاح #15 — بدون rebuild للشاشة)
  final ValueNotifier<double> evalNotifier;

  /// ValueNotifier لحالة التحليل
  final ValueNotifier<bool>? isAnalyzingNotifier;

  /// ارتفاع الشريط. إذا null، يملأ المساحة المتاحة
  final double? height;

  /// عرض الشريط. الافتراضي: 28
  final double width;

  /// الحد الأقصى المطلق للتقييم
  final double maxEval;

  const EvalBar({
    super.key,
    required this.evalNotifier,
    this.isAnalyzingNotifier,
    this.height,
    this.width = 28,
    this.maxEval = 10.0,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: Colors.white12,
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: ValueListenableBuilder<double>(
            valueListenable: evalNotifier,
            builder: (context, evalScore, _) {
              return _EvalBarContent(
                evalScore: evalScore,
                isAnalyzingNotifier: isAnalyzingNotifier,
                height: height,
                width: width,
                maxEval: maxEval,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// محتوى شريط التقييم — يُعاد بناؤه فقط عند تغير التقييم
class _EvalBarContent extends StatefulWidget {
  final double evalScore;
  final ValueNotifier<bool>? isAnalyzingNotifier;
  final double? height;
  final double width;
  final double maxEval;

  const _EvalBarContent({
    required this.evalScore,
    this.isAnalyzingNotifier,
    this.height,
    this.width = 28,
    this.maxEval = 10.0,
  });

  @override
  State<_EvalBarContent> createState() => _EvalBarContentState();
}

class _EvalBarContentState extends State<_EvalBarContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _indicatorAnimation;
  double _previousEval = 0.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _indicatorAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _previousEval = widget.evalScore;
    _animationController.value = 1.0;
  }

  @override
  void didUpdateWidget(_EvalBarContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.evalScore != widget.evalScore) {
      _previousEval = oldWidget.evalScore;
      _animationController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  /// تحويل التقييم إلى موقع عمودي (0.0 = أعلى/أبيض، 1.0 = أسفل/أسود)
  double _evalToPosition(double eval) {
    final clamped = eval.clamp(-widget.maxEval, widget.maxEval);
    return 1.0 - ((clamped + widget.maxEval) / (2 * widget.maxEval));
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = widget.height ?? 300;

    return Stack(
      children: [
        // خلفية متدرجة
        Positioned.fill(
          child: CustomPaint(
            painter: _EvalBarGradientPainter(),
          ),
        ),

        // خط المؤشر المتحرك
        AnimatedBuilder(
          animation: _indicatorAnimation,
          builder: (context, child) {
            final currentEval = _previousEval +
                (widget.evalScore - _previousEval) *
                    _indicatorAnimation.value;
            final position = _evalToPosition(currentEval);

            return Positioned(
              top: position * barHeight - 1.5,
              left: 0,
              right: 0,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: _getIndicatorColor(currentEval),
                  boxShadow: [
                    BoxShadow(
                      color: _getIndicatorColor(currentEval).withOpacity(0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        // نص التقييم
        _buildEvalText(barHeight),

        // علامات +/-
        _buildLabels(),

        // نبض التحليل
        if (widget.isAnalyzingNotifier != null)
          ValueListenableBuilder<bool>(
            valueListenable: widget.isAnalyzingNotifier!,
            builder: (context, isAnalyzing, _) {
              if (!isAnalyzing) return const SizedBox.shrink();
              return _buildAnalyzingPulse(barHeight);
            },
          ),
      ],
    );
  }

  Color _getIndicatorColor(double eval) {
    if (eval.abs() > widget.maxEval * 0.9) {
      return eval > 0 ? Colors.white : Colors.black;
    }
    return eval > 0 ? const Color(0xFFE8E8E8) : const Color(0xFF333333);
  }

  Widget _buildEvalText(double barHeight) {
    final position = _evalToPosition(widget.evalScore);
    final isTop = position < 0.15;
    final isBottom = position > 0.85;

    double textTop;
    if (isTop) {
      textTop = position * barHeight + 6;
    } else if (isBottom) {
      textTop = position * barHeight - 22;
    } else {
      textTop = position * barHeight - 10;
    }

    return Positioned(
      top: textTop.clamp(2.0, barHeight - 20),
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _formatEval(widget.evalScore),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabels() {
    return Positioned.fill(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              '+',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '−',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzingPulse(double barHeight) {
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1200),
        builder: (context, value, child) {
          return CustomPaint(
            painter: _AnalyzingPulsePainter(
              progress: value,
              evalPosition: _evalToPosition(widget.evalScore),
            ),
          );
        },
        onEnd: () {
          if (mounted) {
            setState(() {}); // إعادة تشغيل الأنيميشن
          }
        },
      ),
    );
  }

  String _formatEval(double eval) {
    if (eval.abs() > 900) {
      final mateIn = (1000 - eval.abs()).toInt();
      return eval > 0 ? 'M$mateIn' : '-M$mateIn';
    }
    final sign = eval > 0 ? '+' : '';
    return '$sign${eval.toStringAsFixed(1)}';
  }
}

// ─── Custom Painters ────────────────────────────────────────────────────────

class _EvalBarGradientPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0xFFF5F5F5),
        Color(0xFFE0E0E0),
        Color(0xFF9E9E9E),
        Color(0xFF424242),
        Color(0xFF1A1A1A),
        Color(0xFF0D0D0D),
      ],
      stops: const [0.0, 0.2, 0.45, 0.55, 0.8, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawRect(rect, paint);

    final centerPaint = Paint()
      ..color = Colors.grey.withOpacity(0.4)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      centerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AnalyzingPulsePainter extends CustomPainter {
  final double progress;
  final double evalPosition;

  _AnalyzingPulsePainter({
    required this.progress,
    required this.evalPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final indicatorY = evalPosition * size.height;
    final radius = 6.0 + progress * 14;
    final opacity = (1.0 - progress) * 0.4;

    final paint = Paint()
      ..color = Colors.amber.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawCircle(
      Offset(size.width / 2, indicatorY),
      radius,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AnalyzingPulsePainter oldDelegate) =>
      progress != oldDelegate.progress;
}
