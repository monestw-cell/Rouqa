/// import_screen.dart
/// شاشة الاستيراد — Import Screen
///
/// 3 تبويبات: Chess.com، Lichess، PGN/FEN
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/library_provider.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _chesscomController = TextEditingController();
  final _lichessController = TextEditingController();
  final _pgnController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chesscomController.dispose();
    _lichessController.dispose();
    _pgnController.dispose();
    super.dispose();
  }

  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }

  Future<void> _importChessCom() async {
    final username = _chesscomController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال اسم المستخدم');
      return;
    }

    _clearMessages();
    setState(() => _isLoading = true);

    try {
      await ref.read(libraryProvider.notifier).importFromChessCom(username);
      setState(() {
        _isLoading = false;
        _successMessage = 'تم استيراد المباريات من Chess.com بنجاح!';
      });
      _chesscomController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل الاستيراد: $e';
      });
    }
  }

  Future<void> _importLichess() async {
    final username = _lichessController.text.trim();
    if (username.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال اسم المستخدم');
      return;
    }

    _clearMessages();
    setState(() => _isLoading = true);

    try {
      await ref.read(libraryProvider.notifier).importFromLichess(username);
      setState(() {
        _isLoading = false;
        _successMessage = 'تم استيراد المباريات من Lichess بنجاح!';
      });
      _lichessController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل الاستيراد: $e';
      });
    }
  }

  Future<void> _importPGN() async {
    final text = _pgnController.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'يرجى لصق PGN أو FEN');
      return;
    }

    _clearMessages();
    setState(() => _isLoading = true);

    try {
      await ref.read(libraryProvider.notifier).importFromPGN(text);
      setState(() {
        _isLoading = false;
        _successMessage = 'تم استيراد المباريات من PGN بنجاح!';
      });
      _pgnController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'فشل الاستيراد: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'استيراد مباريات',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
          ),
          bottom: TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
            tabs: const [
              Tab(icon: Icon(Icons.public), text: 'Chess.com'),
              Tab(icon: Icon(Icons.nature), text: 'Lichess'),
              Tab(icon: Icon(Icons.insert_drive_file), text: 'PGN / FEN'),
            ],
          ),
        ),
        body: Column(
          children: [
            // رسائل الحالة
            if (_errorMessage != null || _successMessage != null)
              _buildStatusMessage(theme),

            // محتوى التبويبات
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildChessComTab(theme),
                  _buildLichessTab(theme),
                  _buildPgnTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusMessage(ThemeData theme) {
    final isError = _errorMessage != null;
    final message = isError ? _errorMessage! : _successMessage!;
    final color = isError ? theme.colorScheme.error : Colors.green.shade700;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontFamily: 'Tajawal',
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: color),
            onPressed: _clearMessages,
          ),
        ],
      ),
    );
  }

  Widget _buildChessComTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شعار Chess.com
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF769656).withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.public, size: 40, color: Color(0xFF769656)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Chess.com',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'استورد مبارياتك من حسابك على Chess.com',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Tajawal',
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _chesscomController,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'اسم المستخدم',
              labelStyle: const TextStyle(fontFamily: 'Tajawal'),
              hintText: 'مثال: Hikaru',
              hintStyle: TextStyle(
                fontFamily: 'Tajawal',
                color: theme.colorScheme.onSurface.withAlpha(80),
              ),
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importChessCom,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: Text(
                _isLoading ? 'جاري الاستيراد...' : 'استيراد المباريات',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLichessTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شعار Lichess
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(Icons.nature, size: 40, color: Colors.white70),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Lichess.org',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'استورد مبارياتك من حسابك على Lichess',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'Tajawal',
                color: theme.colorScheme.onSurface.withAlpha(130),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _lichessController,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'اسم المستخدم',
              labelStyle: const TextStyle(fontFamily: 'Tajawal'),
              hintText: 'مثال: DrNykterstein',
              hintStyle: TextStyle(
                fontFamily: 'Tajawal',
                color: theme.colorScheme.onSurface.withAlpha(80),
              ),
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importLichess,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: Text(
                _isLoading ? 'جاري الاستيراد...' : 'استيراد المباريات',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPgnTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الصق PGN أو FEN',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يمكنك لصق نص PGN كامل لمباراة واحدة أو أكثر، أو FEN لموقف محدد.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'Tajawal',
              color: theme.colorScheme.onSurface.withAlpha(130),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TextField(
              controller: _pgnController,
              maxLines: null,
              expands: true,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                hintText: '[Event "مباراة ودية"]\n1. e4 e5 2. Nf3 Nc6 ...\n\nأو FEN:\nrnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR',
                hintStyle: TextStyle(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurface.withAlpha(60),
                  fontSize: 11,
                ),
                alignLabelWithHint: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _importPGN,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download),
              label: Text(
                _isLoading ? 'جاري التحليل...' : 'استيراد',
                style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
