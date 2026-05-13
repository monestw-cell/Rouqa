/// settings_screen.dart
/// شاشة الإعدادات — Settings Screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../core/constants.dart';
import '../database/database_helper.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _db = DatabaseHelper();

  // إعدادات التحليل
  int _analysisDepth = kDefaultAnalysisDepth;
  int _multiPV = kDefaultMultiPV;
  bool _autoAnalyze = true;

  // إعدادات اللوحة
  String _boardTheme = 'brown';
  bool _showCoordinates = true;
  bool _showArrows = true;
  bool _soundEffects = false;

  // إعدادات المحرك
  int _threads = 2;
  int _hashSize = 128;
  String _syzygyPath = '';

  // إعدادات عامة
  String _language = 'ar';
  ThemeMode _themeMode = ThemeMode.dark;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _analysisDepth = int.tryParse(await _db.getSetting(kPrefAnalysisDepth) ?? '') ?? kDefaultAnalysisDepth;
      _multiPV = int.tryParse(await _db.getSetting(kPrefMultiPV) ?? '') ?? kDefaultMultiPV;
      _boardTheme = await _db.getSetting(kPrefBoardTheme) ?? 'brown';
      _showCoordinates = (await _db.getSetting(kPrefShowCoordinates)) != 'false';
      _showArrows = (await _db.getSetting(kPrefShowArrows)) != 'false';

      final appTheme = await _db.getSetting(kPrefAppTheme) ?? 'dark';
      _themeMode = switch (appTheme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };
    } catch (_) {}

    setState(() => _isLoading = false);
  }

  Future<void> _saveSetting(String key, String value) async {
    await _db.setSetting(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'الإعدادات',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            // ─── التحليل ────────────────────────────────────
            _buildSectionHeader('التحليل', Icons.psychology, theme),
            _buildSliderTile(
              title: 'عمق التحليل',
              subtitle: 'عمق البحث الافتراضي: $_analysisDepth',
              value: _analysisDepth.toDouble(),
              min: 10,
              max: 30,
              onChanged: (v) {
                setState(() => _analysisDepth = v.round());
                _saveSetting(kPrefAnalysisDepth, '$_analysisDepth');
              },
            ),
            _buildSliderTile(
              title: 'عدد الخطوط (MultiPV)',
              subtitle: 'عدد الخطوط البديلة: $_multiPV',
              value: _multiPV.toDouble(),
              min: 1,
              max: 5,
              onChanged: (v) {
                setState(() => _multiPV = v.round());
                _saveSetting(kPrefMultiPV, '$_multiPV');
              },
            ),
            SwitchListTile(
              title: const Text('تحليل تلقائي', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: const Text('بدء التحليل عند تحميل مباراة', style: TextStyle(fontFamily: 'Tajawal')),
              value: _autoAnalyze,
              onChanged: (v) => setState(() => _autoAnalyze = v),
            ),

            const Divider(),

            // ─── اللوحة ────────────────────────────────────
            _buildSectionHeader('اللوحة', Icons.dashboard, theme),
            ListTile(
              title: const Text('سمة اللوحة', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: Text(
                _getBoardThemeName(_boardTheme),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _showBoardThemePicker(),
            ),
            SwitchListTile(
              title: const Text('إظهار الإحداثيات', style: TextStyle(fontFamily: 'Tajawal')),
              value: _showCoordinates,
              onChanged: (v) {
                setState(() => _showCoordinates = v);
                _saveSetting(kPrefShowCoordinates, '$v');
              },
            ),
            SwitchListTile(
              title: const Text('إظهار الأسهم', style: TextStyle(fontFamily: 'Tajawal')),
              value: _showArrows,
              onChanged: (v) {
                setState(() => _showArrows = v);
                _saveSetting(kPrefShowArrows, '$v');
              },
            ),
            SwitchListTile(
              title: const Text('المؤثرات الصوتية', style: TextStyle(fontFamily: 'Tajawal')),
              value: _soundEffects,
              onChanged: (v) => setState(() => _soundEffects = v),
            ),

            const Divider(),

            // ─── المحرك ────────────────────────────────────
            _buildSectionHeader('المحرك', Icons.memory, theme),
            _buildSliderTile(
              title: 'الخيوط (Threads)',
              subtitle: 'عدد خيوط المعالجة: $_threads',
              value: _threads.toDouble(),
              min: 1,
              max: 8,
              onChanged: (v) => setState(() => _threads = v.round()),
            ),
            _buildSliderTile(
              title: 'حجم التجزئة (Hash)',
              subtitle: 'حجم الذاكرة: ${_hashSize} MB',
              value: _hashSize.toDouble(),
              min: 32,
              max: 2048,
              onChanged: (v) => setState(() => _hashSize = v.round()),
            ),
            ListTile(
              title: const Text('مسار Syzygy', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: Text(
                _syzygyPath.isEmpty ? 'غير محدد' : _syzygyPath,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.folder_open),
              onTap: () {
                // سيتم إضافة اختيار الملف
              },
            ),

            const Divider(),

            // ─── عام ──────────────────────────────────────
            _buildSectionHeader('عام', Icons.settings, theme),
            ListTile(
              title: const Text('اللغة', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: const Text('العربية', style: TextStyle(fontFamily: 'Tajawal')),
              trailing: const Icon(Icons.chevron_left),
              onTap: () {
                // سيتم إضافة اختيار اللغة
              },
            ),
            ListTile(
              title: const Text('سمة التطبيق', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: Text(
                _getThemeModeName(_themeMode),
                style: const TextStyle(fontFamily: 'Tajawal'),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => _showThemeModePicker(),
            ),

            const Divider(),

            // ─── حول ──────────────────────────────────────
            _buildSectionHeader('حول', Icons.info_outline, theme),
            const ListTile(
              title: Text('إصدار التطبيق', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: Text('1.0.0', style: TextStyle(fontFamily: 'monospace')),
            ),
            const ListTile(
              title: Text('رُقعة — محلل الشطرنج الذكي', style: TextStyle(fontFamily: 'Tajawal')),
              subtitle: Text(
                'محلل مباريات شطرنج عربي يعتمد على محرك Stockfish',
                style: TextStyle(fontFamily: 'Tajawal'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontFamily: 'Tajawal')),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subtitle, style: const TextStyle(fontFamily: 'Tajawal', fontSize: 12)),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _getBoardThemeName(String id) {
    return switch (id) {
      'brown' => 'بني • Brown',
      'blue' => 'أزرق • Blue',
      'green' => 'أخضر • Green',
      'dark' => 'داكن • Dark',
      _ => id,
    };
  }

  String _getThemeModeName(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.dark => 'مظلم',
      ThemeMode.light => 'فاتح',
      ThemeMode.system => 'تلقائي',
    };
  }

  void _showBoardThemePicker() {
    final themes = [
      ('brown', 'بني • Brown', const Color(0xFFB58863)),
      ('blue', 'أزرق • Blue', const Color(0xFF8CA2AD)),
      ('green', 'أخضر • Green', const Color(0xFF6D9B51)),
      ('dark', 'داكن • Dark', const Color(0xFF2D2D2D)),
    ];

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('سمة اللوحة', style: TextStyle(fontFamily: 'Tajawal')),
          children: themes.map((t) {
            final (id, name, color) = t;
            return SimpleDialogOption(
              onPressed: () {
                setState(() => _boardTheme = id);
                _saveSetting(kPrefBoardTheme, id);
                ref.read(boardThemeProvider.notifier).setBoardTheme(id);
                Navigator.pop(context);
              },
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _boardTheme == id
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(name, style: const TextStyle(fontFamily: 'Tajawal')),
                  const Spacer(),
                  if (_boardTheme == id)
                    Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showThemeModePicker() {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('سمة التطبيق', style: TextStyle(fontFamily: 'Tajawal')),
          children: [
            _themeOption(ThemeMode.dark, 'مظلم', Icons.dark_mode),
            _themeOption(ThemeMode.light, 'فاتح', Icons.light_mode),
            _themeOption(ThemeMode.system, 'تلقائي', Icons.brightness_auto),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(ThemeMode mode, String name, IconData icon) {
    return SimpleDialogOption(
      onPressed: () {
        setState(() => _themeMode = mode);
        _saveSetting(kPrefAppTheme, switch (mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        });
        ref.read(appThemeProvider.notifier).setTheme(mode);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Text(name, style: const TextStyle(fontFamily: 'Tajawal')),
          const Spacer(),
          if (_themeMode == mode)
            Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
        ],
      ),
    );
  }
}
