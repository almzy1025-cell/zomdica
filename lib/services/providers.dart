import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../collectors/registry.dart';
import '../collectors/source_connector.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../filters/pipeline.dart';
import '../models/models.dart';
import 'search_orchestrator.dart';
import 'secure_store.dart';

final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider must be overridden in main()'),
);

final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('prefsProvider must be overridden in main()'),
);

final secureStoreProvider = Provider<ApiKeyStore>((ref) => ApiKeyStore());

// ---------- Settings ----------

class AppSettings {
  final ThemeMode themeMode;
  final String language; // 'ar' | 'en'
  final int maxResultsPerQuery;
  final int maxConcurrentConnectors;
  final bool backgroundEnabled;
  final int backgroundIntervalMinutes; // 5 / 15 / 30 / 60 (Android يفرض 15 كحد أدنى)

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.language = 'ar',
    this.maxResultsPerQuery = 30,
    this.maxConcurrentConnectors = 4,
    this.backgroundEnabled = false,
    this.backgroundIntervalMinutes = 60,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? language,
    int? maxResultsPerQuery,
    int? maxConcurrentConnectors,
    bool? backgroundEnabled,
    int? backgroundIntervalMinutes,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        language: language ?? this.language,
        maxResultsPerQuery: maxResultsPerQuery ?? this.maxResultsPerQuery,
        maxConcurrentConnectors: maxConcurrentConnectors ?? this.maxConcurrentConnectors,
        backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
        backgroundIntervalMinutes: backgroundIntervalMinutes ?? this.backgroundIntervalMinutes,
      );

  SearchLimits get limits => AppConfig.defaultLimits.copyWith(
        maxResultsPerQuery: maxResultsPerQuery,
        maxConcurrentConnectors: maxConcurrentConnectors,
      );
}

AppSettings loadSettings(SharedPreferences p) => SettingsNotifier._load(p);

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(_load(_prefs));

  static AppSettings _load(SharedPreferences p) => AppSettings(
        themeMode: ThemeMode.values[(p.getInt('theme') ?? 0).clamp(0, 2).toInt()],
        language: p.getString('lang') ?? 'ar',
        maxResultsPerQuery: p.getInt('max_results') ?? 30,
        maxConcurrentConnectors: (p.getInt('max_conc') ?? 4).clamp(4, 8).toInt(),
        backgroundEnabled: p.getBool('bg_enabled') ?? false,
        backgroundIntervalMinutes: p.getInt('bg_interval') ?? 60,
      );

  Future<void> update(AppSettings s) async {
    state = s;
    await _prefs.setInt('theme', s.themeMode.index);
    await _prefs.setString('lang', s.language);
    await _prefs.setInt('max_results', s.maxResultsPerQuery);
    await _prefs.setInt('max_conc', s.maxConcurrentConnectors);
    await _prefs.setBool('bg_enabled', s.backgroundEnabled);
    await _prefs.setInt('bg_interval', s.backgroundIntervalMinutes);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.watch(prefsProvider)),
);

// ---------- Data providers ----------

final sourcesProvider = FutureProvider<List<SourceConfig>>(
  (ref) => ref.watch(databaseProvider).sources(),
);

final keywordsProvider = FutureProvider<List<Keyword>>(
  (ref) => ref.watch(databaseProvider).keywords(),
);

final watchlistsProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(databaseProvider).watchlists(),
);

final resultsProvider = FutureProvider<List<SearchResult>>(
  (ref) => ref.watch(databaseProvider).results(limit: 500),
);

final favoritesProvider = FutureProvider<List<SearchResult>>(
  (ref) => ref.watch(databaseProvider).favorites(),
);

final sessionsProvider = FutureProvider<List<SearchSession>>(
  (ref) => ref.watch(databaseProvider).sessions(),
);

final historyProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(databaseProvider).searchHistory(),
);

final healthRowsProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(databaseProvider).healthRows(),
);

final apiKeyHintsProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(databaseProvider).apiKeyHints(),
);

/// يفتح ويغلق بيانات المفاتيح المخزنة (للتحقق من وجودها فقط).
final apiKeyPresenceProvider = FutureProvider<Map<String, bool>>((ref) async {
  final store = ref.watch(secureStoreProvider);
  final out = <String, bool>{};
  for (final p in ApiKeyStore.providers.keys) {
    final v = await store.read(p);
    out[p] = v != null && v.isNotEmpty;
  }
  return out;
});

// ---------- Search ----------

class SearchState {
  final bool running;
  final String query;
  final String sessionId;
  final List<String> expanded;
  final List<SearchResult> results;
  final Map<String, SourceHealth> health;
  final Map<String, String> activeConnectors;
  final int duplicates;
  final SearchSession? lastSession;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final Set<String> knownBefore;

  const SearchState({
    this.running = false,
    this.query = '',
    this.sessionId = '',
    this.expanded = const [],
    this.results = const [],
    this.health = const {},
    this.activeConnectors = const {},
    this.duplicates = 0,
    this.lastSession,
    this.startedAt,
    this.finishedAt,
    this.knownBefore = const {},
  });

  int get newCount => results.where((r) => !knownBefore.contains(r.canonicalUrl)).length;

  Duration get elapsed => (finishedAt ?? DateTime.now()).difference(startedAt ?? DateTime.now());

  SearchState copyWith({
    bool? running,
    String? query,
    String? sessionId,
    List<String>? expanded,
    List<SearchResult>? results,
    Map<String, SourceHealth>? health,
    Map<String, String>? activeConnectors,
    int? duplicates,
    SearchSession? lastSession,
    DateTime? startedAt,
    DateTime? finishedAt,
    Set<String>? knownBefore,
  }) =>
      SearchState(
        running: running ?? this.running,
        query: query ?? this.query,
        sessionId: sessionId ?? this.sessionId,
        expanded: expanded ?? this.expanded,
        results: results ?? this.results,
        health: health ?? this.health,
        activeConnectors: activeConnectors ?? this.activeConnectors,
        duplicates: duplicates ?? this.duplicates,
        lastSession: lastSession ?? this.lastSession,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        knownBefore: knownBefore ?? this.knownBefore,
      );
}

/// يدير بحثاً واحداً في كل مرة، ويستقبل الأحداث تباعاً (Streaming).
class SearchNotifier extends StateNotifier<SearchState> {
  final AppDatabase _db;
  final ApiKeyStore _secure;
  final SearchLimits Function() _limits;
  final void Function() _onFinished;

  CancelToken? _token;
  StreamSubscription<SearchEvent>? _sub;
  final Map<String, SourceConnector> _capabilityOwners = {};

  SearchNotifier({
    required AppDatabase db,
    required ApiKeyStore secure,
    required SearchLimits Function() limits,
    required void Function() onFinished,
  })  : _db = db,
        _secure = secure,
        _limits = limits,
        _onFinished = onFinished,
        super(const SearchState());

  Future<void> start(String rawQuery) async {
    final q = rawQuery.trim();
    if (q.isEmpty || state.running) return;

    final cfgs = await _db.sources();
    final keywords = await _db.keywords();
    final yt = await _secure.read(ApiKeyStore.youtube);
    final uspto = await _secure.read(ApiKeyStore.uspto);
    final entries = <ConnectorEntry>[];
    for (final cfg in cfgs) {
      final c = connectorFor(cfg, youtubeKey: yt, usptoKey: uspto);
      if (c != null) entries.add(ConnectorEntry(c, cfg));
    }
    _capabilityOwners
      ..clear()
      ..addEntries(entries.map((e) => MapEntry(e.connector.id, e.connector)));

    final limits = _limits();
    final known = await _db.knownCanonicalUrls();
    final expanded = expandQueries(q, keywords, limits.maxQueriesPerSearch);
    final orch = SearchOrchestrator(entries: entries, limits: limits);
    _token = CancelToken();

    state = SearchState(
      running: true,
      query: q,
      expanded: expanded,
      startedAt: DateTime.now(),
      knownBefore: known,
    );

    await _sub?.cancel();
    _sub = orch
        .search(
          query: q,
          expandedQueries: expanded,
          requestedSource: 'Enabled sources',
          cancel: _token,
        )
        .listen(_onEvent, onError: (Object _) {
      state = state.copyWith(running: false, finishedAt: DateTime.now());
    });
  }

  /// إيقاف فوري: يلغي الطلبات المعلّقة ويحفظ الجلسة بحالة CANCELLED.
  void stop() => _token?.cancel();

  void _onEvent(SearchEvent e) {
    switch (e) {
      case SessionStarted(:final sessionId):
        state = state.copyWith(sessionId: sessionId);
      case ConnectorStarted(:final connectorId, :final name):
        state = state.copyWith(activeConnectors: {...state.activeConnectors, connectorId: name});
      case ResultFound(:final result):
        unawaited(_db.insertResult(result));
        state = state.copyWith(results: [...state.results, result]);
      case ResultDuplicate(:final result):
        unawaited(_db.insertResult(result));
        state = state.copyWith(duplicates: state.duplicates + 1);
      case ConnectorFinished(:final health):
        final active = {...state.activeConnectors}..remove(health.connectorId);
        state = state.copyWith(
          health: {...state.health, health.connectorId: health},
          activeConnectors: active,
        );
        final cap = _capabilityOwners[health.connectorId]?.capability ?? const Capability();
        unawaited(_db.upsertHealth(health, cap));
      case SessionFinished(:final session):
        final status = session.cancelled
            ? 'CANCELLED'
            : (session.errors.isEmpty ? 'DONE' : 'PARTIAL');
        unawaited(_db.saveSession(session, resultCount: session.resultsFound, status: status));
        state = state.copyWith(
          running: false,
          finishedAt: DateTime.now(),
          lastSession: session,
          activeConnectors: const {},
        );
        _onFinished();
    }
  }

  /// نتائج مرتبة بحسب مستوى الترتيب ثم الصلة (Ranking).
  List<SearchResult> get rankedResults => ResultPipeline.rank(state.results);

  @override
  void dispose() {
    _token?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(
    db: ref.watch(databaseProvider),
    secure: ref.watch(secureStoreProvider),
    limits: () => ref.read(settingsProvider).limits,
    onFinished: () {
      ref.invalidate(resultsProvider);
      ref.invalidate(sessionsProvider);
      ref.invalidate(healthRowsProvider);
      ref.invalidate(historyProvider);
    },
  );
});
