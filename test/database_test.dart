import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zomedica_radar/database/app_database.dart';
import 'package:zomedica_radar/models/models.dart';

SearchResult _sample({String id = 'r1', String url = 'https://example.com/a', bool fav = false}) =>
    SearchResult(
      id: id,
      title: 'Zomedica announces update',
      source: 'Example',
      sourceType: SourceType.news,
      url: url,
      canonicalUrl: url,
      discoveredAt: DateTime.utc(2026, 10, 1),
      keywords: const ['zomedica'],
      entities: const ['zomedica'],
      relevanceScore: 80,
      freshnessScore: 60,
      sourceAuthorityScore: 70,
      confidenceScore: 75,
      searchSessionId: 's1',
      evidenceId: 'ev1',
      connectorId: 'google_news',
      requestedSource: 'Enabled sources',
      actualSource: 'news.google.com',
      favorite: fav,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
  });

  tearDown(() async {
    await db.close();
  });

  test('insert is idempotent (duplicate canonical id ignored)', () async {
    expect(await db.insertResult(_sample()), isTrue);
    expect(await db.insertResult(_sample()), isFalse);
    expect((await db.results()).length, 1);
  });

  test('round-trips a result through SQLite', () async {
    await db.insertResult(_sample());
    final back = await db.resultById('r1');
    expect(back, isNotNull);
    expect(back!.title, 'Zomedica announces update');
    expect(back.keywords, ['zomedica']);
    expect(back.actualSource, 'news.google.com');
    expect(back.requestedSource, 'Enabled sources');
  });

  test('favorites toggle and listing', () async {
    await db.insertResult(_sample());
    await db.setFavorite('r1', true);
    expect((await db.favorites()).map((e) => e.id), ['r1']);
    await db.setFavorite('r1', false);
    expect(await db.favorites(), isEmpty);
  });

  test('search history keeps only the latest 20 sessions', () async {
    for (var i = 0; i < 25; i++) {
      await db.saveSession(
        SearchSession(
          id: 'sess$i',
          query: 'q$i',
          expandedQueries: const ['q'],
          connectorsUsed: const ['gdelt'],
          requests: 1,
          successfulRequests: 1,
          failedRequests: 0,
          resultsFound: 0,
          duplicatesRemoved: 0,
          durationMs: 10,
          errors: const [],
          cancelled: false,
          startedAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
        ),
        resultCount: 0,
        status: 'DONE',
      );
    }
    final hist = await db.searchHistory();
    expect(hist.length, 20);
    expect(hist.first['id'], 'sess24');
  });

  test('connector health persists capability matrix columns', () async {
    const h = SourceHealth(
      connectorId: 'x_twitter',
      name: 'X',
      status: ConnectorStatus.apiRequired,
      errorCode: ErrorCode.apiRequired,
      reason: 'API required',
    );
    await db.upsertHealth(h, const Capability(free: false, apiRequired: true, currentlyAvailable: false));
    final rows = await db.healthRows();
    expect(rows.single['status'], 'apiRequired');
    expect(rows.single['api_required'], 1);
    expect(rows.single['currently_available'], 0);
  });

  test('keywords and sources round-trip', () async {
    await db.upsertKeyword(const Keyword(
      id: 'k1',
      term: 'PulseVet',
      category: KeywordCategory.product,
      aliases: ['Pulse Vet'],
    ));
    final kws = await db.keywords();
    expect(kws.single.term, 'PulseVet');
    expect(kws.single.aliases, ['Pulse Vet']);

    await db.upsertSource(const SourceConfig(
      id: 's1',
      name: 'Custom',
      type: SourceType.news,
      method: SourceMethod.rss,
      url: 'https://example.com/feed',
      connectorId: '',
      selectors: {'title': 'h2'},
    ));
    final src = await db.sources();
    expect(src.single.selectors, {'title': 'h2'});
    expect(src.single.method, SourceMethod.rss);
  });

  test('built-in sources are not deletable by deleteSource', () async {
    await db.upsertSource(const SourceConfig(
      id: 'b1',
      name: 'Builtin',
      type: SourceType.news,
      method: SourceMethod.builtin,
      url: '',
      connectorId: 'google_news',
      isBuiltin: true,
    ));
    await db.deleteSource('b1');
    expect((await db.sources()).length, 1);
  });
}
