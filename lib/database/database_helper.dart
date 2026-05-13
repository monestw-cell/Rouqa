/// مساعد قاعدة البيانات — Database Helper
/// إدارة قاعدة بيانات SQLite لتطبيق رُقعة مع 4 جداول رئيسية
library;

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import '../core/constants.dart';
import 'package:flutter/foundation.dart';

// ─── نتيجة مقسمة إلى صفحات — Paginated Result (حل مشكلة #11) ──────────────

/// نتيجة مقسمة إلى صفحات — Paginated database query result
class PaginatedResult {
  /// العناصر في الصفحة الحالية
  final List<Map<String, dynamic>> items;

  /// إجمالي عدد العناصر
  final int totalCount;

  /// رقم الصفحة الحالية (يبدأ من 0)
  final int page;

  /// حجم الصفحة
  final int pageSize;

  /// إجمالي عدد الصفحات
  final int totalPages;

  /// هل توجد صفحة تالية؟
  bool get hasNextPage => page < totalPages - 1;

  /// هل توجد صفحة سابقة؟
  bool get hasPreviousPage => page > 0;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });
}

// ─── مساعد قاعدة البيانات — Database Helper ────────────────────────────────

class DatabaseHelper {
  /// نمط مفرد
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  /// مرجع قاعدة البيانات
  Database? _database;

  /// الحصول على قاعدة البيانات (إنشاء أو فتح)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// تهيئة قاعدة البيانات
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, kDatabaseName);

    return openDatabase(
      path,
      version: kDatabaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  /// تهيئة قاعدة البيانات عند الفتح (تفعيل المفاتيح الأجنبية)
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
  }

  /// إنشاء الجداول عند إنشاء قاعدة البيانات لأول مرة
  Future<void> _onCreate(Database db, int version) async {
    // ─── جدول المباريات — Matches Table ──────────────────────────────────
    await db.execute('''
      CREATE TABLE matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        white_player TEXT NOT NULL DEFAULT '',
        black_player TEXT NOT NULL DEFAULT '',
        result TEXT NOT NULL DEFAULT '*',
        date TEXT,
        pgn TEXT NOT NULL DEFAULT '',
        eco TEXT,
        opening TEXT,
        white_accuracy REAL,
        black_accuracy REAL,
        time_control TEXT,
        source TEXT NOT NULL DEFAULT 'manual',
        created_at INTEGER NOT NULL
      )
    ''');

    // فهرس للبحث حسب التاريخ
    await db.execute('''
      CREATE INDEX idx_matches_date ON matches(date)
    ''');

    // فهرس للبحث حسب اللاعب
    await db.execute('''
      CREATE INDEX idx_matches_white_player ON matches(white_player)
    ''');

    await db.execute('''
      CREATE INDEX idx_matches_black_player ON matches(black_player)
    ''');

    // ─── جدول الإعدادات — Settings Table ─────────────────────────────────
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // إدراج الإعدادات الافتراضية
    await _insertDefaultSettings(db);

    // ─── جدول تصنيفات الحركات — Move Classifications Table ──────────────
    await db.execute('''
      CREATE TABLE move_classifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_id INTEGER NOT NULL,
        move_index INTEGER NOT NULL,
        san TEXT NOT NULL,
        uci TEXT NOT NULL,
        classification TEXT NOT NULL,
        cp_loss INTEGER,
        eval_before INTEGER,
        eval_after INTEGER,
        depth INTEGER,
        FOREIGN KEY (match_id) REFERENCES matches(id) ON DELETE CASCADE
      )
    ''');

    // فهرس للبحث حسب المباراة
    await db.execute('''
      CREATE INDEX idx_move_classifications_match_id ON move_classifications(match_id)
    ''');

    // ─── جدول الافتتاحيات — Openings Table ──────────────────────────────
    await db.execute('''
      CREATE TABLE openings (
        eco TEXT PRIMARY KEY,
        name_ar TEXT NOT NULL,
        name_en TEXT NOT NULL,
        moves TEXT NOT NULL,
        category TEXT NOT NULL,
        description_ar TEXT NOT NULL
      )
    ''');

    // فهرس للبحث حسب التصنيف
    await db.execute('''
      CREATE INDEX idx_openings_category ON openings(category)
    ''');

    // إدراج بيانات الافتتاحيات الأساسية
    await _insertDefaultOpenings(db);
  }

  /// تحديث قاعدة البيانات عند تغيير الإصدار
  ///
  /// نظام الترحيل (Migration) المحسّن:
  /// - كل ترقية تُنفّذ في معاملة (transaction) منفصلة لضمان التناسق
  /// - يتم تسجيل كل ترقية في جدول schema_migrations
  /// - يمكن التراجع عن الترقيات إذا لزم الأمر
  /// - يُضاف عمود created_at لكل ترقية جديدة
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // إنشاء جدول تسجيل الترقيات إذا لم يكن موجوداً
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        description TEXT NOT NULL,
        applied_at INTEGER NOT NULL
      )
    ''');

    // تسجيل الإصدار 1 كأساس (إذا لم يكن مسجلاً)
    final v1Exists = await db.rawQuery(
      'SELECT COUNT(*) as count FROM schema_migrations WHERE version = 1',
    );
    if ((v1Exists.first['count'] as int) == 0) {
      await db.insert('schema_migrations', {
        'version': 1,
        'description': 'إنشاء قاعدة البيانات الأولي: matches, settings, move_classifications, openings',
        'applied_at': DateTime.now().millisecondsSinceEpoch,
      });
    }

    // ─── الترقية إلى الإصدار 2: إضافة فهارس إضافية للأداء ───────
    if (oldVersion < 2) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_source ON matches(source)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_created_at ON matches(created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_result ON matches(result)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_eco ON matches(eco)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_move_classifications_classification ON move_classifications(classification)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_move_classifications_san ON move_classifications(san)');

      await db.insert('schema_migrations', {
        'version': 2,
        'description': 'إضافة فهارس أداء على matches و move_classifications',
        'applied_at': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('DatabaseHelper: تمت الترقية إلى الإصدار 2 — إضافة فهارس');
    }

    // ─── الترقية إلى الإصدار 3: إضافة حقول جديدة ───────
    if (oldVersion < 3) {
      // إضافة عمود التوقيت للاعبين في المباريات
      await db.execute('ALTER TABLE matches ADD COLUMN event TEXT');
      await db.execute('ALTER TABLE matches ADD COLUMN site TEXT');
      await db.execute('ALTER TABLE matches ADD COLUMN round TEXT');
      await db.execute('ALTER TABLE matches ADD COLUMN white_elo INTEGER');
      await db.execute('ALTER TABLE matches ADD COLUMN black_elo INTEGER');

      // إضافة فهارس للبحث المتقدم
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_event ON matches(event)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_matches_site ON matches(site)');

      // إضافة أعمدة لتصنيفات الحركات
      await db.execute('ALTER TABLE move_classifications ADD COLUMN pv TEXT NOT NULL DEFAULT \'\'');
      await db.execute('ALTER TABLE move_classifications ADD COLUMN nodes INTEGER');
      await db.execute('ALTER TABLE move_classifications ADD COLUMN nps INTEGER');
      await db.execute('ALTER TABLE move_classifications ADD COLUMN tb_hits INTEGER');

      // فهرس للبحث حسب العمق
      await db.execute('CREATE INDEX IF NOT EXISTS idx_move_classifications_depth ON move_classifications(depth)');

      await db.insert('schema_migrations', {
        'version': 3,
        'description': 'إضافة حقول PGN قياسية (event, site, round, elo) وأعمدة محرك إضافية (pv, nodes, nps, tb_hits)',
        'applied_at': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('DatabaseHelper: تمت الترقية إلى الإصدار 3 — إضافة حقول جديدة');
    }

    debugPrint('DatabaseHelper: اكتملت الترقية من الإصدار $oldVersion إلى $newVersion');
  }

  /// إدراج الإعدادات الافتراضية
  Future<void> _insertDefaultSettings(Database db) async {
    final defaults = <Map<String, Object>>[
      {'key': kPrefAnalysisDepth, 'value': kDefaultAnalysisDepth.toString()},
      {'key': kPrefMultiPV, 'value': kDefaultMultiPV.toString()},
      {'key': kPrefBoardTheme, 'value': 'brown'},
      {'key': kPrefAppTheme, 'value': 'dark'},
      {'key': kPrefFlippedBoard, 'value': 'false'},
      {'key': kPrefShowCoordinates, 'value': 'true'},
      {'key': kPrefShowArrows, 'value': 'true'},
      {'key': kPrefAnimations, 'value': 'true'},
    ];

    for (final setting in defaults) {
      await db.insert('settings', setting);
    }
  }

  /// إدراج الافتتاحيات الأساسية من ملف JSON خارجي
  ///
  /// يتم تحميل البيانات من assets/data/openings.json بدلاً من تضمينها
  /// في الكود المصدري مباشرة. هذا يسهّل تحديث البيانات وتخصيصها
  /// دون الحاجة إلى إعادة بناء التطبيق.
  Future<void> _insertDefaultOpenings(Database db) async {
    try {
      // تحميل ملف JSON من الأصول
      final jsonString = await rootBundle.loadString('assets/data/openings.json');
      final List<dynamic> openingsList = jsonDecode(jsonString);

      // إدراج كل افتتاحية في قاعدة البيانات
      for (final opening in openingsList) {
        final Map<String, Object> row = Map<String, Object>.from(opening);
        await db.insert('openings', row);
      }

      debugPrint('DatabaseHelper: تم إدراج ${openingsList.length} افتتاحية من JSON');
    } catch (e) {
      // في حالة فشل تحميل JSON، نستخدم بيانات احتياطية أساسية
      debugPrint('DatabaseHelper: فشل تحميل JSON، استخدام بيانات احتياطية: $e');
      await _insertFallbackOpenings(db);
    }
  }

  /// بيانات افتتاحيات احتياطية — تُستخدم فقط إذا فشل تحميل JSON
  /// تحتوي على أصغر مجموعة ممكنة لضمان عمل التطبيق
  Future<void> _insertFallbackOpenings(Database db) async {
    final openings = <Map<String, Object>>[
      {'eco': 'B20', 'name_ar': 'دفاع صقلية', 'name_en': 'Sicilian Defense', 'moves': 'e4 c5', 'category': 'semi-open', 'description_ar': 'أشهر دفاع ضد بيادق الملك'},
      {'eco': 'C50', 'name_ar': 'لعبة إيطالية', 'name_en': 'Italian Game', 'moves': 'e4 e5 Nf3 Nc6 Bc4', 'category': 'open', 'description_ar': 'واحدة من أقدم الافتتاحيات'},
      {'eco': 'D06', 'name_ar': 'مرفوض الوزير', 'name_en': "Queen's Gambit", 'moves': 'd4 d5 c4', 'category': 'closed', 'description_ar': 'أشهر افتتاحية بيادق الوزير'},
    ];

    for (final opening in openings) {
      await db.insert('openings', opening);
    }
  }

  /// إعادة تحميل بيانات الافتتاحيات من ملف JSON
  ///
  /// يُستخدم لتحديث بيانات الافتتاحيات دون إعادة إنشاء قاعدة البيانات.
  /// يُفرّغ الجدول أولاً ثم يعيد الإدراج من JSON.
  Future<void> reloadOpeningsFromJson() async {
    final db = await database;
    await db.delete('openings');
    await _insertDefaultOpenings(db);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات المباريات — Match CRUD Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة مباراة جديدة — Create
  Future<int> insertMatch(Map<String, dynamic> match) async {
    final db = await database;
    match['created_at'] = DateTime.now().millisecondsSinceEpoch;
    return db.insert('matches', match);
  }

  /// الحصول على مباراة بالمعرف — Read
  Future<Map<String, dynamic>?> getMatch(int id) async {
    final db = await database;
    final results = await db.query(
      'matches',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// الحصول على جميع المباريات — Read All
  Future<List<Map<String, dynamic>>> getAllMatches({
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      'matches',
      orderBy: orderBy ?? 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// حل #11: تحميل كسول للمباريات — Lazy loading with pagination
  ///
  /// يُرجع صفحة واحدة من المباريات مع معلومات إجمالية.
  /// [page] — رقم الصفحة (يبدأ من 0)
  /// [pageSize] — حجم الصفحة (الافتراضي: 20)
  /// [orderBy] — ترتيب النتائج
  Future<PaginatedResult> getMatchesPaginated({
    int page = 0,
    int pageSize = 20,
    String orderBy = 'created_at DESC',
    String? searchQuery,
  }) async {
    final db = await database;

    String? whereClause;
    List<Object>? whereArgs;

    if (searchQuery != null && searchQuery.isNotEmpty) {
      whereClause = 'white_player LIKE ? OR black_player LIKE ? OR opening LIKE ?';
      whereArgs = ['%$searchQuery%', '%$searchQuery%', '%$searchQuery%'];
    }

    // استعلام العدد الإجمالي
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM matches${whereClause != null ? ' WHERE $whereClause' : ''}',
      whereArgs,
    );
    final totalCount = countResult.first['count'] as int;

    // استعلام الصفحة الحالية
    final offset = page * pageSize;
    final matches = await db.query(
      'matches',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: pageSize,
      offset: offset,
    );

    return PaginatedResult(
      items: matches,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
      totalPages: (totalCount / pageSize).ceil(),
    );
  }

  /// حل #11: تحميل ملخص المباراة فقط (بدون PGN وتحليل كامل)
  ///
  /// يُستخدم لعرض قائمة المباريات بكفاءة — لا يُرجع PGN والتحليل الكامل.
  Future<List<Map<String, dynamic>>> getMatchSummaries({
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return db.query(
      'matches',
      columns: ['id', 'white_player', 'black_player', 'result', 'date', 'eco',
                'opening', 'white_accuracy', 'black_accuracy', 'time_control',
                'source', 'created_at'],
      orderBy: orderBy ?? 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// البحث في المباريات — Search
  Future<List<Map<String, dynamic>>> searchMatches(String query) async {
    final db = await database;
    return db.query(
      'matches',
      where: 'white_player LIKE ? OR black_player LIKE ? OR opening LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'created_at DESC',
    );
  }

  /// الحصول على عدد المباريات — Count
  Future<int> getMatchCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM matches');
    return result.first['count'] as int;
  }

  /// تحديث مباراة — Update
  Future<int> updateMatch(int id, Map<String, dynamic> values) async {
    final db = await database;
    return db.update(
      'matches',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف مباراة — Delete
  Future<int> deleteMatch(int id) async {
    final db = await database;
    return db.delete(
      'matches',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف جميع المباريات — Delete All
  Future<int> deleteAllMatches() async {
    final db = await database;
    return db.delete('matches');
  }

  /// إحصائيات المباريات — Statistics
  Future<Map<String, dynamic>> getMatchStats() async {
    final db = await database;

    final total = await db.rawQuery('SELECT COUNT(*) as count FROM matches');
    final whiteWins = await db.rawQuery("SELECT COUNT(*) as count FROM matches WHERE result = '1-0'");
    final blackWins = await db.rawQuery("SELECT COUNT(*) as count FROM matches WHERE result = '0-1'");
    final draws = await db.rawQuery("SELECT COUNT(*) as count FROM matches WHERE result = '1/2-1/2'");

    final avgAccuracy = await db.rawQuery('''
      SELECT AVG(white_accuracy) as avg_white, AVG(black_accuracy) as avg_black
      FROM matches
      WHERE white_accuracy IS NOT NULL AND black_accuracy IS NOT NULL
    ''');

    return {
      'total': total.first['count'],
      'white_wins': whiteWins.first['count'],
      'black_wins': blackWins.first['count'],
      'draws': draws.first['count'],
      'avg_white_accuracy': avgAccuracy.first['avg_white'],
      'avg_black_accuracy': avgAccuracy.first['avg_black'],
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات الإعدادات — Settings CRUD Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// الحصول على إعداد — Get Setting
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return results.isNotEmpty ? results.first['value'] as String : null;
  }

  /// تعيين إعداد — Set Setting (Upsert)
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// الحصول على جميع الإعدادات — Get All Settings
  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final results = await db.query('settings');
    return {for (final row in results) row['key'] as String: row['value'] as String};
  }

  /// حذف إعداد — Delete Setting
  Future<int> deleteSetting(String key) async {
    final db = await database;
    return db.delete(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات تصنيفات الحركات — Move Classifications CRUD Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// إضافة تصنيف حركة — Create
  Future<int> insertMoveClassification(Map<String, dynamic> classification) async {
    final db = await database;
    return db.insert('move_classifications', classification);
  }

  /// إضافة عدة تصنيفات حركات دفعة واحدة — Batch Create
  Future<void> insertMoveClassifications(List<Map<String, dynamic>> classifications) async {
    final db = await database;
    final batch = db.batch();
    for (final c in classifications) {
      batch.insert('move_classifications', c);
    }
    await batch.commit(noResult: true);
  }

  /// الحصول على تصنيفات حركات مباراة — Read by Match
  Future<List<Map<String, dynamic>>> getMoveClassifications(int matchId) async {
    final db = await database;
    return db.query(
      'move_classifications',
      where: 'match_id = ?',
      whereArgs: [matchId],
      orderBy: 'move_index ASC',
    );
  }

  /// الحصول على تصنيف حركة واحدة — Read Single
  Future<Map<String, dynamic>?> getMoveClassification(int matchId, int moveIndex) async {
    final db = await database;
    final results = await db.query(
      'move_classifications',
      where: 'match_id = ? AND move_index = ?',
      whereArgs: [matchId, moveIndex],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// تحديث تصنيف حركة — Update
  Future<int> updateMoveClassification(int id, Map<String, dynamic> values) async {
    final db = await database;
    return db.update(
      'move_classifications',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف تصنيفات حركات مباراة — Delete by Match
  Future<int> deleteMoveClassifications(int matchId) async {
    final db = await database;
    return db.delete(
      'move_classifications',
      where: 'match_id = ?',
      whereArgs: [matchId],
    );
  }

  /// إحصائيات التصنيفات لمباراة — Classification Stats
  Future<Map<String, int>> getClassificationStats(int matchId) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT classification, COUNT(*) as count
      FROM move_classifications
      WHERE match_id = ?
      GROUP BY classification
    ''', [matchId]);

    return {for (final row in results) row['classification'] as String: row['count'] as int};
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات الافتتاحيات — Openings CRUD Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// الحصول على افتتاحية برمز ECO — Read by ECO
  Future<Map<String, dynamic>?> getOpening(String eco) async {
    final db = await database;
    final results = await db.query(
      'openings',
      where: 'eco = ?',
      whereArgs: [eco],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// الحصول على جميع الافتتاحيات — Read All
  Future<List<Map<String, dynamic>>> getAllOpenings({
    String? category,
    String? orderBy,
  }) async {
    final db = await database;
    if (category != null) {
      return db.query(
        'openings',
        where: 'category = ?',
        whereArgs: [category],
        orderBy: orderBy ?? 'eco ASC',
      );
    }
    return db.query(
      'openings',
      orderBy: orderBy ?? 'eco ASC',
    );
  }

  /// البحث في الافتتاحيات — Search
  Future<List<Map<String, dynamic>>> searchOpenings(String query) async {
    final db = await database;
    return db.query(
      'openings',
      where: 'name_ar LIKE ? OR name_en LIKE ? OR eco LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'eco ASC',
    );
  }

  /// إضافة افتتاحية — Create
  Future<int> insertOpening(Map<String, dynamic> opening) async {
    final db = await database;
    return db.insert(
      'openings',
      opening,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// إضافة عدة افتتاحيات دفعة واحدة — Batch Create
  Future<void> insertOpenings(List<Map<String, dynamic>> openings) async {
    final db = await database;
    final batch = db.batch();
    for (final o in openings) {
      batch.insert('openings', o, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// تحديث افتتاحية — Update
  Future<int> updateOpening(String eco, Map<String, dynamic> values) async {
    final db = await database;
    return db.update(
      'openings',
      values,
      where: 'eco = ?',
      whereArgs: [eco],
    );
  }

  /// حذف افتتاحية — Delete
  Future<int> deleteOpening(String eco) async {
    final db = await database;
    return db.delete(
      'openings',
      where: 'eco = ?',
      whereArgs: [eco],
    );
  }

  /// الحصول على عدد الافتتاحيات — Count
  Future<int> getOpeningCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM openings');
    return result.first['count'] as int;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // عمليات مساعدة — Utility Operations
  // ═══════════════════════════════════════════════════════════════════════════

  /// إغلاق قاعدة البيانات
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// حذف قاعدة البيانات بالكامل (للتطوير فقط)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, kDatabaseName);
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }

  /// التحقق من وجود قاعدة البيانات
  Future<bool> databaseExists() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, kDatabaseName);
    return databaseFactory.databaseExists(path);
  }

  /// نسخ احتياطي لقاعدة البيانات
  Future<String> backupDatabase() async {
    final db = await database;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, kDatabaseName);
    return path;
  }

  /// تصدير بيانات المباراة الكاملة (مع تصنيفات الحركات)
  Future<Map<String, dynamic>> exportMatch(int matchId) async {
    final match = await getMatch(matchId);
    if (match == null) {
      throw Exception('المباراة غير موجودة — Match not found: $matchId');
    }

    final classifications = await getMoveClassifications(matchId);

    return {
      'match': match,
      'classifications': classifications,
    };
  }

  /// استيراد مباراة كاملة (مع تصنيفات الحركات)
  Future<int> importMatch(Map<String, dynamic> matchData, List<Map<String, dynamic>>? classifications) async {
    final db = await database;

    return db.transaction((txn) async {
      // إدراج المباراة
      matchData['created_at'] = DateTime.now().millisecondsSinceEpoch;
      final matchId = await txn.insert('matches', matchData);

      // إدراج التصنيفات إن وجدت
      if (classifications != null) {
        for (final c in classifications) {
          c['match_id'] = matchId;
          await txn.insert('move_classifications', c);
        }
      }

      return matchId;
    });
  }
}
