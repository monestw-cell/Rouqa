/// library_screen.dart
/// شاشة مكتبة المباريات — Game Library Screen
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_provider.dart';
import '../models/chess_models.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _sortBy = 'date_desc';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryProvider);
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'مكتبة المباريات',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: 'ترتيب',
              onSelected: (value) {
                setState(() => _sortBy = value);
                ref.read(libraryProvider.notifier).changeSortBy(value);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'date_desc', child: Text('الأحدث أولاً')),
                const PopupMenuItem(value: 'date_asc', child: Text('الأقدم أولاً')),
                const PopupMenuItem(value: 'accuracy_desc', child: Text('أعلى دقة')),
                const PopupMenuItem(value: 'accuracy_asc', child: Text('أقل دقة')),
                const PopupMenuItem(value: 'result', child: Text('حسب النتيجة')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط البحث
            _buildSearchBar(theme),

            // إحصائيات سريعة
            if (state.stats.isNotEmpty) _buildStatsBar(state, theme),

            // قائمة المباريات
            Expanded(
              child: state.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : state.matches.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildGameList(state, theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _searchController,
        onChanged: (query) => ref.read(libraryProvider.notifier).searchGames(query),
        decoration: InputDecoration(
          hintText: 'ابحث باللاعب أو الافتتاحية...',
          hintStyle: const TextStyle(fontFamily: 'Tajawal'),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(libraryProvider.notifier).searchGames('');
                  },
                )
              : null,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBar(LibraryState state, ThemeData theme) {
    final total = state.stats['total'] as int? ?? 0;
    final whiteWins = state.stats['white_wins'] as int? ?? 0;
    final blackWins = state.stats['black_wins'] as int? ?? 0;
    final draws = state.stats['draws'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('المجموع', '$total', theme),
          _statItem('فوز أبيض', '$whiteWins', theme),
          _statItem('فوز أسود', '$blackWins', theme),
          _statItem('تعادل', '$draws', theme),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, ThemeData theme) {
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontFamily: 'Tajawal',
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontFamily: 'Tajawal',
            color: theme.colorScheme.onSurface.withAlpha(130),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: theme.colorScheme.onSurface.withAlpha(50),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد مباريات محفوظة',
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: 'Tajawal',
              color: theme.colorScheme.onSurface.withAlpha(130),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'استورد مبارياتك من Chess.com أو Lichess أو الصق PGN',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Tajawal',
              color: theme.colorScheme.onSurface.withAlpha(80),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildGameList(LibraryState state, ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: state.matches.length,
      itemBuilder: (context, index) {
        final match = state.matches[index];
        return _buildGameCard(match, theme);
      },
    );
  }

  Widget _buildGameCard(Map<String, dynamic> match, ThemeData theme) {
    final whitePlayer = match['white_player'] as String? ?? 'أبيض';
    final blackPlayer = match['black_player'] as String? ?? 'أسود';
    final result = match['result'] as String? ?? '*';
    final opening = match['opening'] as String?;
    final whiteAccuracy = match['white_accuracy'] as double?;
    final blackAccuracy = match['black_accuracy'] as double?;
    final dateStr = match['date'] as String?;
    final source = match['source'] as String? ?? 'manual';

    final resultColor = result == '1-0'
        ? Colors.green.shade700
        : result == '0-1'
            ? Colors.red.shade700
            : Colors.grey.shade600;

    final sourceIcon = switch (source) {
      'chesscom' => Icons.public,
      'lichess' => Icons.nature,
      'pgn' => Icons.insert_drive_file,
      _ => Icons.edit,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          // فتح في شاشة التحليل
          Navigator.of(context).pushNamed('/analysis', arguments: match);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // أيقونة المصدر
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sourceIcon, color: theme.colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 12),

              // معلومات المباراة
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('♔', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            whitePlayer,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Tajawal',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (whiteAccuracy != null)
                          Text(
                            '${whiteAccuracy.toStringAsFixed(0)}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade600,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('♚', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            blackPlayer,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Tajawal',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (blackAccuracy != null)
                          Text(
                            '${blackAccuracy.toStringAsFixed(0)}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.green.shade600,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                    if (opening != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        opening,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'Tajawal',
                          color: theme.colorScheme.onSurface.withAlpha(100),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // النتيجة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: resultColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  result,
                  style: TextStyle(
                    color: resultColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),

              // حذف
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.error.withAlpha(150),
                ),
                onPressed: () => _confirmDelete(match['id'] as int),
                tooltip: 'حذف',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text(
            'حذف المباراة',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          content: const Text(
            'هل تريد حذف هذه المباراة؟ لا يمكن التراجع.',
            style: TextStyle(fontFamily: 'Tajawal'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ref.read(libraryProvider.notifier).deleteGame(id);
              },
              child: Text(
                'حذف',
                style: TextStyle(
                  fontFamily: 'Tajawal',
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
