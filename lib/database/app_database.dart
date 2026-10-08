import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../models/models.dart';

/// قاعدة SQLite مع Schema Versioning + Migrations.
/// عند إضافة نسخة جديدة: أضف خطوة في _migrate بدل تعديل CREATE القديمة.
class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static Future<AppDatabase> open({String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await getDatabasesPath(), 'zomedica_radar.db');
    final database = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: AppConfig.schemaVersion,
        onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) async => _migrate(d, 0, v),
        onUpgrade: (d, o, n) async => _migrate(d, o, n),
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _migrate(Database d, int from, int to) async {
    if (from < 1) {
      await _createV1(d);
    }
    // مثال للخطوات المستقبلية: if (from < 2) { await d.execute('ALTER TABLE ...'); }
  }

  static Future<void> _createV1(Database d) async {
    final batch = d.batch();
    batch.execute('''
      CREATE TABLE results (
        id TEXT PRIMARY KEY, title TEXT, source TEXT, source_type TEXT, url TEXT,
        canonical_url TEXT, published_at INTEGER, discovered_at INTEGER, author TEXT,
        content TEXT, snippet TEXT, language TEXT, country TEXT, keywords TEXT,
        entities TEXT, relevance_score REAL, freshness_score REAL,
        source_authority_score REAL, confidence_score REAL, search_method TEXT,
        requested_source TEXT, actual_source TEXT, connector_id TEXT,
        search_session_id TEXT, evidence_id TEXT, event_id TEXT, content_hash TEXT,
        ai_summary TEXT, why_matched TEXT, other_sources TEXT,
        favorite INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('CREATE INDEX idx_results_canonical ON results(canonical_url)');
    batch.execute('CREATE INDEX idx_results_session ON results(search_session_id)');
    batch.execute('CREATE INDEX idx_results_hash ON results(content_hash)');
    batch.execute('''
      CREATE TABLE sources (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT, method TEXT, url TEXT,
        enabled INTEGER NOT NULL DEFAULT 1, priority INTEGER, polling_minutes INTEGER,
        connector_id TEXT, is_builtin INTEGER NOT NULL DEFAULT 0, selectors TEXT
      )''');
    batch.execute('''
      CREATE TABLE keywords (
        id TEXT PRIMARY KEY, term TEXT NOT NULL, category TEXT, aliases TEXT,
        enabled INTEGER NOT NULL DEFAULT 1, group_name TEXT
      )''');
    batch.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT, reason TEXT,
        sources TEXT, confidence REAL, status TEXT, discovered_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE inventors (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, patent_count INTEGER,
        first_seen INTEGER, last_seen INTEGER
      )''');
    batch.execute('''
      CREATE TABLE patents (
        id TEXT PRIMARY KEY, title TEXT, url TEXT, number TEXT, published_at INTEGER,
        result_id TEXT
      )''');
    batch.execute('''
      CREATE TABLE trademarks (
        id TEXT PRIMARY KEY, mark TEXT, owner TEXT, status TEXT, url TEXT, result_id TEXT
      )''');
    batch.execute('''
      CREATE TABLE favorites (
        result_id TEXT PRIMARY KEY, saved_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE watchlists (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, terms TEXT, created_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE search_history (
        id TEXT PRIMARY KEY, query TEXT, created_at INTEGER, result_count INTEGER, status TEXT
      )''');
    batch.execute('''
      CREATE TABLE search_sessions (
        id TEXT PRIMARY KEY, query TEXT, expanded_queries TEXT, connectors TEXT,
        requests INTEGER, successful_requests INTEGER, failed_requests INTEGER,
        results_found INTEGER, duplicates_removed INTEGER, duration_ms INTEGER,
        errors TEXT, cancelled INTEGER, started_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE connector_health (
        connector_id TEXT PRIMARY KEY, name TEXT, status TEXT, error_code TEXT,
        reason TEXT, last_result_count INTEGER, last_duration_ms INTEGER,
        http_status INTEGER, last_tested INTEGER, free INTEGER, api_required INTEGER,
        login_required INTEGER, rss_supported INTEGER, scraping_supported INTEGER,
        currently_available INTEGER, current_health TEXT
      )''');
    batch.execute('''
      CREATE TABLE api_keys (
        provider TEXT PRIMARY KEY, key_hint TEXT, updated_at INTEGER
      )''');
    batch.execute('''
      CREATE TABLE notifications (
        id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT, body TEXT, priority TEXT,
        result_id TEXT, created_at INTEGER, read INTEGER NOT NULL DEFAULT 0
      )''');
    batch.execute('''
      CREATE TABLE sync_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT, started_at INTEGER, finished_at INTEGER,
        new_results INTEGER, status TEXT
      )''');
    await batch.commit(noResult: true);
  }

  Future<void> close() => db.close();

  // ---------- Results ----------

  /// يُرجع true إذا أُدرجت النتيجة، false إذا كانت موجودة (Idempotent).
  Future<bool> insertResult(SearchResult r) async {
    final n = await db.insert('results', r.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
    return n > 0;
  }

  Future<List<SearchResult>> results({int limit = 500, String? sessionId}) async {
    final rows = await db.query(
      'results',
      where: sessionId == null ? null : 'search_session_id = ?',
      whereArgs: sessionId == null ? null : [sessionId],
      orderBy: 'discovered_at DESC',
      limit: limit,
    );
    return rows.map(SearchResult.fromMap).toList();
  }

  Future<SearchResult?> resultById(String id) async {
    final rows = await db.query('results', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : SearchResult.fromMap(rows.first);
  }

  Future<Set<String>> knownCanonicalUrls() async {
    final rows = await db.rawQuery('SELECT DISTINCT canonical_url FROM results');
    return rows.map((r) => r['canonical_url'] as String).toSet();
  }

  /// كل النسخ/المصادر المجمّعة تحت الحدث نفسه (Other Sources).
  Future<List<SearchResult>> resultsByEvent(String eventId) async {
    final rows = await db.query('results', where: 'event_id = ?', whereArgs: [eventId]);
    return rows.map(SearchResult.fromMap).toList();
  }

  Future<void> setFavorite(String resultId, bool fav) async {
    if (fav) {
      await db.insert('favorites', {
        'result_id': resultId,
        'saved_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete('favorites', where: 'result_id = ?', whereArgs: [resultId]);
    }
    await db.update('results', {'favorite': fav ? 1 : 0}, where: 'id = ?', whereArgs: [resultId]);
  }

  Future<List<SearchResult>> favorites() async {
    final rows = await db.rawQuery('''
      SELECT r.* FROM results r INNER JOIN favorites f ON f.result_id = r.id
      ORDER BY f.saved_at DESC''');
    return rows.map((m) => SearchResult.fromMap(m)).toList();
  }

  Future<void> pruneResults({int keep = 2000}) async {
    await db.rawDelete('''
      DELETE FROM results WHERE favorite = 0 AND id NOT IN (
        SELECT id FROM results ORDER BY discovered_at DESC LIMIT ?)''', [keep]);
  }

  // ---------- Sessions / History / Logs ----------

  Future<void> saveSession(SearchSession s, {required int resultCount, required String status}) async {
    await db.insert('search_sessions', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('search_history', {
      'id': s.id,
      'query': s.query,
      'created_at': s.startedAt.millisecondsSinceEpoch,
      'result_count': resultCount,
      'status': status,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    // الاحتفاظ بآخر 20 بحثاً فقط.
    await db.rawDelete('''
      DELETE FROM search_history WHERE id NOT IN (
        SELECT id FROM search_history ORDER BY created_at DESC LIMIT 20)''');
  }

  Future<List<Map<String, Object?>>> searchHistory() =>
      db.query('search_history', orderBy: 'created_at DESC', limit: 20);

  Future<List<SearchSession>> sessions({int limit = 50}) async {
    final rows = await db.query('search_sessions', orderBy: 'started_at DESC', limit: limit);
    return rows.map(SearchSession.fromMap).toList();
  }

  // ---------- Connector health (Capability Matrix) ----------

  Future<void> upsertHealth(SourceHealth h, Capability c) async {
    await db.insert(
      'connector_health',
      {
        ...h.toMap(),
        'free': c.free ? 1 : 0,
        'api_required': c.apiRequired ? 1 : 0,
        'login_required': c.loginRequired ? 1 : 0,
        'rss_supported': c.rssSupported ? 1 : 0,
        'scraping_supported': c.scrapingSupported ? 1 : 0,
        'currently_available': c.currentlyAvailable ? 1 : 0,
        'current_health': h.status.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> healthRows() => db.query('connector_health');

  // ---------- Sources ----------

  Future<void> upsertSource(SourceConfig s) async =>
      db.insert('sources', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteSource(String id) async =>
      db.delete('sources', where: 'id = ? AND is_builtin = 0', whereArgs: [id]);

  Future<List<SourceConfig>> sources() async {
    final rows = await db.query('sources', orderBy: 'priority ASC, name ASC');
    return rows.map(SourceConfig.fromMap).toList();
  }

  // ---------- Keywords & Watchlists ----------

  Future<void> upsertKeyword(Keyword k) async =>
      db.insert('keywords', k.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteKeyword(String id) async =>
      db.delete('keywords', where: 'id = ?', whereArgs: [id]);

  Future<List<Keyword>> keywords() async {
    final rows = await db.query('keywords', orderBy: 'group_name ASC, term ASC');
    return rows.map(Keyword.fromMap).toList();
  }

  Future<void> upsertWatchlist(String id, String name, List<String> terms) async {
    await db.insert('watchlists', {
      'id': id,
      'name': name,
      'terms': terms.join('\n'),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> watchlists() => db.query('watchlists', orderBy: 'created_at ASC');

  Future<void> deleteWatchlist(String id) async =>
      db.delete('watchlists', where: 'id = ?', whereArgs: [id]);

  // ---------- API keys (hints only; الأسرار في Android Keystore) ----------

  Future<void> upsertApiKeyHint(String provider, String hint) async {
    await db.insert('api_keys', {
      'provider': provider,
      'key_hint': hint,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteApiKeyHint(String provider) async =>
      db.delete('api_keys', where: 'provider = ?', whereArgs: [provider]);

  Future<List<Map<String, Object?>>> apiKeyHints() => db.query('api_keys');

  // ---------- Notifications / Sync ----------

  Future<void> addNotification({
    required String title,
    required String body,
    required String priority,
    required String resultId,
  }) async {
    await db.insert('notifications', {
      'title': title,
      'body': body,
      'priority': priority,
      'result_id': resultId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'read': 0,
    });
  }

  Future<int> addSyncRun(int startedAt, int finishedAt, int newResults, String status) =>
      db.insert('sync_runs', {
        'started_at': startedAt,
        'finished_at': finishedAt,
        'new_results': newResults,
        'status': status,
      });
}
