/// نقطة الدخول الرئيسية لتطبيق رُقعة — Main Entry Point
/// تهيئة التطبيق مع Riverpod ودعم العربية
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/app_theme.dart';
import 'core/constants.dart';
import 'services/app_lifecycle_manager.dart';
import 'services/adaptive_analysis_service.dart';
import 'screens/home_screen.dart';
import 'screens/analysis_screen.dart';
import 'screens/library_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/training_screen.dart';
import 'screens/puzzle_screen.dart';
import 'screens/play_engine_screen.dart';

// ─── مزود الإعدادات — Settings Provider ─────────────────────────────────────

/// مزود التفضيلات المشتركة
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider لم تتم تهيئته');
});

/// مزود سمة التطبيق
final appThemeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier(ref.read(sharedPreferencesProvider));
});

/// مزود سمة اللوح
final boardThemeProvider = StateNotifierProvider<BoardThemeNotifier, String>((ref) {
  return BoardThemeNotifier(ref.read(sharedPreferencesProvider));
});

/// مزود اللغة
final localeProvider = StateProvider<Locale>((ref) => const Locale('ar'));

// ─── مخطط السمة — Theme Notifier ────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final SharedPreferences _prefs;

  ThemeNotifier(this._prefs) : super(ThemeMode.dark) {
    _loadTheme();
  }

  void _loadTheme() {
    final themeStr = _prefs.getString(kPrefAppTheme) ?? 'dark';
    state = _parseThemeMode(themeStr);
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(kPrefAppTheme, _themeModeToString(mode));
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

// ─── مخطط سمة اللوح — Board Theme Notifier ──────────────────────────────────

class BoardThemeNotifier extends StateNotifier<String> {
  final SharedPreferences _prefs;

  BoardThemeNotifier(this._prefs) : super('brown') {
    _loadBoardTheme();
  }

  void _loadBoardTheme() {
    state = _prefs.getString(kPrefBoardTheme) ?? 'brown';
  }

  Future<void> setBoardTheme(String themeId) async {
    state = themeId;
    await _prefs.setString(kPrefBoardTheme, themeId);
  }
}

// ─── الشاشة الرئيسية مستوردة من screens/home_screen.dart ────────────────

// ─── تطبيق رُقعة — Ruq'a App ────────────────────────────────────────────────

class RuqaApp extends ConsumerStatefulWidget {
  const RuqaApp({super.key});

  @override
  ConsumerState<RuqaApp> createState() => _RuqaAppState();
}

class _RuqaAppState extends ConsumerState<RuqaApp> with WidgetsBindingObserver {
  /// إصلاح #12: مدير دورة حياة التطبيق
  AppLifecycleManager? _lifecycleManager;

  /// إصلاح #16: خدمة التحليل التكيفي
  final AdaptiveAnalysisService _adaptiveAnalysis = AdaptiveAnalysisService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // بدء التحليل التكيفي
    _adaptiveAnalysis.start();
    _adaptiveAnalysis.onProfileChanged = (level, profile) {
      debugPrint('RuqaApp: تغير مستوى الأداء: $level');
      // يمكن تحديث إعدادات المحرك هنا
    };
  }

  @override
  void dispose() {
    _lifecycleManager?.dispose();
    _adaptiveAnalysis.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleManager?.handleLifecycleChange(state);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(appThemeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      // اسم التطبيق
      title: kAppNameAr,

      // وصف التطبيق
      debugShowCheckedModeBanner: false,

      // السمة
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,

      // اللغة
      locale: locale,
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        // سيتم إضافة مفوضي التوطين عند الحاجة
      ],

      // اتجاه النص الافتراضي: من اليمين لليسار
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },

      // الشاشة الرئيسية
      home: const HomeScreen(),

      // ─── مسارات التنقل — Navigation Routes ─────────────────────────────
      routes: {
        '/analysis': (context) => const AnalysisScreen(),
        '/library': (context) => const LibraryScreen(),
        '/import': (context) => const ImportScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/training': (context) => const TrainingScreen(),
        '/puzzle': (context) => const PuzzleScreen(),
        '/play-engine': (context) => const PlayEngineScreen(),
      },
    );
  }
}

// ─── نقطة الدخول — Entry Point ──────────────────────────────────────────────

void main() async {
  // التأكد من تهيئة Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // تقييد الاتجاهات (عمودي فقط)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ضبط شريط الحالة
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // تهيئة التفضيلات المشتركة
  final sharedPreferences = await SharedPreferences.getInstance();

  // تشغيل التطبيق
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const RuqaApp(),
    ),
  );
}
