import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chess_models.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F3460),
                Color(0xFF16213E),
                Color(0xFF1A1A2E),
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ─── Logo & Title ─────────────────────────────
                  SliverToBoxAdapter(
                    child: _buildHeader(theme, size),
                  ),

                  // ─── Quick Actions ────────────────────────────
                  SliverToBoxAdapter(
                    child: _buildQuickActions(theme),
                  ),

                  // ─── Daily Puzzle ─────────────────────────────
                  SliverToBoxAdapter(
                    child: _buildDailyPuzzle(theme),
                  ),

                  // ─── Recent Games ─────────────────────────────
                  SliverToBoxAdapter(
                    child: _buildRecentGamesSection(theme),
                  ),

                  // Bottom padding for nav bar
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ─── شريط التنقل السفلي — Bottom Navigation Bar ───────────────
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F3460), Color(0xFF16213E)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _navItem(Icons.home, 'الرئيسية', true),
                  _navItem(Icons.analytics_outlined, 'التحليل', false, onTap: _navigateToAnalysis),
                  _navItem(Icons.library_books_outlined, 'المكتبة', false, onTap: _navigateToLibrary),
                  _navItem(Icons.school_outlined, 'التدريب', false, onTap: _navigateToTraining),
                  _navItem(Icons.settings_outlined, 'الإعدادات', false, onTap: _navigateToSettings),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(ThemeData theme, Size size) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        children: [
          // Logo
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Color(0xFFE94560),
                  Color(0xFFC81E45),
                ],
                center: Alignment.center,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE94560).withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Center(
              child: Text(
                '♜',
                style: TextStyle(
                  fontSize: 44,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // App name
          Text(
            'رقعة',
            style: theme.textTheme.headlineLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 36,
              fontFamily: 'Tajawal',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          // Subtitle
          Text(
            'محلل الشطرنج الذكي',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white60,
              fontFamily: 'Tajawal',
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // Tagline
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFE94560).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFE94560).withOpacity(0.3),
              ),
            ),
            child: Text(
              'حلل • تعلّم • تطوّر',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFE94560),
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Quick Actions ────────────────────────────────────────────────────────

  Widget _buildQuickActions(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 12),
            child: Text(
              'إجراءات سريعة',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white70,
                fontFamily: 'Tajawal',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.add_circle_outline,
                  title: 'تحليل جديد',
                  subtitle: 'ابدأ تحليل لعبة جديدة',
                  gradientColors: [
                    const Color(0xFF0F3460),
                    const Color(0xFF1A5276),
                  ],
                  iconColor: const Color(0xFF5DADE2),
                  onTap: () => _navigateToAnalysis(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.file_download_outlined,
                  title: 'استيراد لعبة',
                  subtitle: 'PGN أو FEN',
                  gradientColors: [
                    const Color(0xFF1B4332),
                    const Color(0xFF2D6A4F),
                  ],
                  iconColor: const Color(0xFF52B788),
                  onTap: () => _showImportDialog(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.school_outlined,
                  title: 'تدريب',
                  subtitle: 'تمارين وتكتيك',
                  gradientColors: [
                    const Color(0xFF4A1942),
                    const Color(0xFF6C3483),
                  ],
                  iconColor: const Color(0xFFBB8FCE),
                  onTap: () => _navigateToTraining(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Daily Puzzle ─────────────────────────────────────────────────────────

  Widget _buildDailyPuzzle(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFE94560),
              Color(0xFFC81E45),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE94560).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _navigateToDailyPuzzle(),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        '♟',
                        style: TextStyle(fontSize: 28, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'لغز اليوم',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Tajawal',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'جديد',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'حل التكتيك اليومي وتحدّى نفسك',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            fontFamily: 'Tajawal',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_back,
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Recent Games ─────────────────────────────────────────────────────────

  Widget _buildRecentGamesSection(ThemeData theme) {
    // Sample recent games data
    final recentGames = [
      _RecentGameData(
        white: 'أحمد',
        black: 'محمد',
        result: '1-0',
        date: 'اليوم',
        classification: MoveClassification.brilliant,
      ),
      _RecentGameData(
        white: 'سارة',
        black: 'فاطمة',
        result: '½-½',
        date: 'أمس',
        classification: MoveClassification.good,
      ),
      _RecentGameData(
        white: 'أنت',
        black: 'المحرك',
        result: '0-1',
        date: 'قبل يومين',
        classification: MoveClassification.mistake,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الألعاب الأخيرة',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'عرض الكل',
                  style: TextStyle(
                    color: Color(0xFF5DADE2),
                    fontFamily: 'Tajawal',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recentGames.map((game) => _buildGameCard(game, theme)),
        ],
      ),
    );
  }

  Widget _buildGameCard(_RecentGameData game, ThemeData theme) {
    final resultColor = game.result == '1-0'
        ? Colors.white
        : game.result == '0-1'
            ? const Color(0xFF333333)
            : const Color(0xFF888888);

    final resultBg = game.result == '1-0'
        ? Colors.green.shade700
        : game.result == '0-1'
            ? Colors.red.shade700
            : Colors.grey.shade600;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _navigateToAnalysis(),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Players
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('♔', style: TextStyle(color: Colors.white70)),
                            const SizedBox(width: 6),
                            Text(
                              game.white,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontFamily: 'Tajawal',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('♚', style: TextStyle(color: Colors.white38)),
                            const SizedBox(width: 6),
                            Text(
                              game.black,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.white70,
                                fontFamily: 'Tajawal',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Classification badge
                  ClassificationBadge(classification: game.classification),
                  const SizedBox(width: 12),
                  // Result
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: resultBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      game.result,
                      style: TextStyle(
                        color: resultColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Date
                  Text(
                    game.date,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white38,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _navigateToAnalysis() {
    Navigator.of(context).pushNamed('/analysis');
  }

  void _navigateToTraining() {
    Navigator.of(context).pushNamed('/training');
  }

  void _navigateToDailyPuzzle() {
    Navigator.of(context).pushNamed('/puzzle');
  }

  void _navigateToLibrary() {
    Navigator.of(context).pushNamed('/library');
  }

  void _navigateToSettings() {
    Navigator.of(context).pushNamed('/settings');
  }

  void _navigateToImport() {
    Navigator.of(context).pushNamed('/import');
  }

  // ─── Nav Item ──────────────────────────────────────────────────────────

  Widget _navItem(IconData icon, String label, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFE94560) : Colors.white54,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFFE94560) : Colors.white54,
                fontSize: 10,
                fontFamily: 'Tajawal',
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportDialog() {
    final pgnController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'استيراد لعبة',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pgnController,
                maxLines: 5,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  hintText: 'الصق PGN أو FEN هنا...',
                  hintStyle: TextStyle(
                    color: Colors.white38,
                    fontFamily: 'Tajawal',
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE94560)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _navigateToAnalysis();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.file_download),
                      label: const Text(
                        'استيراد',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Camera/scan PGN
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: const BorderSide(color: Colors.white24),
                      ),
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text(
                        'مسح',
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
}

// ─── Quick Action Card ──────────────────────────────────────────────────────

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'Tajawal',
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Recent Game Data ───────────────────────────────────────────────────────

class _RecentGameData {
  final String white;
  final String black;
  final String result;
  final String date;
  final MoveClassification classification;

  const _RecentGameData({
    required this.white,
    required this.black,
    required this.result,
    required this.date,
    required this.classification,
  });
}
