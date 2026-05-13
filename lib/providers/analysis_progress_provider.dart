/// analysis_progress_provider.dart
/// مزود تقدم التحليل — Analysis Progress Provider
///
/// يتتبع تقدم التحليل فقط دون باقي الحالة.
/// مزود مُشتق يُستخدم في عناصر واجهة المستخدم التي تحتاج فقط
/// معرفة حالة التقدم (شريط التقدم، مؤشر التحميل، إلخ).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'analysis_provider.dart';

// ============================================================================
// حالة تقدم التحليل — Analysis Progress State
// ============================================================================

/// حالة تقدم التحليل — Analysis progress state
///
/// تحتوي فقط على بيانات تقدم التحليل:
/// هل يتم التحليل؟ التقدم، الحركة الحالية، الأخطاء.
class AnalysisProgressState {
  /// هل يتم التحليل حاليًا؟
  final bool isAnalyzing;

  /// تقدم التحليل (0.0 - 1.0)
  final double progress;

  /// نص الحركة الحالية أثناء التحليل
  final String currentMove;

  /// هل المحرك في وضع التحليل التفاعلي؟
  final bool isInteractiveAnalysis;

  /// رسالة الخطأ
  final String? errorMessage;

  const AnalysisProgressState({
    this.isAnalyzing = false,
    this.progress = 0.0,
    this.currentMove = '',
    this.isInteractiveAnalysis = false,
    this.errorMessage,
  });

  /// نسخ مع تعديل
  AnalysisProgressState copyWith({
    bool? isAnalyzing,
    double? progress,
    String? currentMove,
    bool? isInteractiveAnalysis,
    String? Function()? errorMessage,
  }) {
    return AnalysisProgressState(
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      progress: progress ?? this.progress,
      currentMove: currentMove ?? this.currentMove,
      isInteractiveAnalysis: isInteractiveAnalysis ?? this.isInteractiveAnalysis,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }

  /// نسبة التقدم كنص (مثل: "75%")
  String get progressPercentage => '${(progress * 100).toStringAsFixed(0)}%';

  /// هل اكتمل التحليل؟
  bool get isComplete => progress >= 1.0 && !isAnalyzing;

  /// هل هناك خطأ؟
  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;
}

// ============================================================================
// مزود Riverpod — Riverpod Provider
// ============================================================================

/// مزود تقدم التحليل — Analysis progress provider
///
/// مزود مُشتق من analysisProvider يُقدم فقط بيانات التقدم.
/// يُستخدم في عناصر واجهة المستخدم التي تحتاج فقط معرفة
/// حالة التقدم دون الاشتراك في كامل حالة التحليل.
///
/// الاستخدام:
/// ```dart
/// // قراءة حالة التقدم
/// final progress = ref.watch(analysisProgressProvider);
/// if (progress.isAnalyzing) {
///   showProgressBar(progress.progressPercentage);
/// }
/// ```
final analysisProgressProvider = Provider<AnalysisProgressState>((ref) {
  final analysis = ref.watch(analysisProvider);
  return AnalysisProgressState(
    isAnalyzing: analysis.isAnalyzing,
    progress: analysis.analysisProgress,
    currentMove: analysis.currentAnalyzingMove,
    isInteractiveAnalysis: analysis.isInteractiveAnalysis,
    errorMessage: analysis.errorMessage,
  );
});
