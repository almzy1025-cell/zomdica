import 'dart:math';

import 'package:workmanager/workmanager.dart';

import '../collectors/registry.dart';
import '../config/app_config.dart';
import '../database/app_database.dart';
import '../models/models.dart';
import '../services/notifications.dart';
import '../services/search_orchestrator.dart';
import '../services/secure_store.dart';

const kPeriodicUniqueName = 'zomedica_watch_periodic';
const kPeriodicTaskName = 'zomedica_watch_check';

/// نقطة دخول WorkManager (تعمل في Isolate منفصل).
@pragma('vm:entry-point')
void radarCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kPeriodicTaskName) return true;
    try {
      await runWatchlistCheck();
      return true;
    } catch (_) {
      return false;
    }
  });
}

/// فحص قوائم المراقبة: بحث حقيقي عبر المصادر المفعّلة، ثم إشعار بالنتائج الجديدة فقط.
Future<int> runWatchlistCheck() async {
  final db = await AppDatabase.open();
  final started = DateTime.now().millisecondsSinceEpoch;
  var newCount = 0;
  try {
    final sources = await db.sources();
    final keywords = await db.keywords();
    final secure = ApiKeyStore();
    final ytKey = await secure.read(ApiKeyStore.youtube);
    final usptoKey = await secure.read(ApiKeyStore.uspto);
    final entries = <ConnectorEntry>[];
    for (final cfg in sources) {
      if (!cfg.enabled) continue;
      final c = connectorFor(cfg, youtubeKey: ytKey, usptoKey: usptoKey);
      if (c == null) continue;
      // Backoff بسيط: المصدر الذي فشل أو حُجب مؤخراً (آخر 60 دقيقة) يُتجاوز في هذه الدورة.
      if (await _recentlyFailing(db, c.id)) continue;
      entries.add(ConnectorEntry(c, cfg));
    }
    final terms = keywords
        .where((k) => k.enabled && (k.category == KeywordCategory.company ||
            k.category == KeywordCategory.product))
        .map((k) => k.term)
        .take(3)
        .toList();
    if (terms.isEmpty) {
      await db.addSyncRun(started, DateTime.now().millisecondsSinceEpoch, 0, 'NO_KEYWORDS');
      return 0;
    }
    final known = await db.knownCanonicalUrls();
    const limits = SearchLimits();
    final orch = SearchOrchestrator(entries: entries, limits: limits);
    final stream = orch.search(
      query: terms.first,
      expandedQueries: expandQueries(terms.first, keywords, limits.maxQueriesPerSearch),
      requestedSource: 'Watchlist (background)',
    );
    final rnd = Random();
    await for (final ev in stream) {
      switch (ev) {
        case ResultFound(:final result):
          await db.insertResult(result);
          if (!known.contains(result.canonicalUrl)) {
            newCount++;
            known.add(result.canonicalUrl);
            final priority = RadarNotifications.priorityFor(result.sourceType);
            await db.addNotification(
              title: result.title,
              body: result.source,
              priority: priority,
              resultId: result.id,
            );
            await RadarNotifications.showResult(result, rnd.nextInt(1 << 30));
          }
        case ConnectorFinished(:final health):
          Capability cap = const Capability();
          for (final e in entries) {
            if (e.connector.id == health.connectorId) cap = e.connector.capability;
          }
          await db.upsertHealth(health, cap);
        case SessionFinished(:final session):
          await db.saveSession(session, resultCount: session.resultsFound, status: 'BACKGROUND');
        default:
          break;
      }
    }
    await db.addSyncRun(started, DateTime.now().millisecondsSinceEpoch, newCount, 'DONE');
    await db.pruneResults();
    return newCount;
  } finally {
    await db.close();
  }
}

Future<bool> _recentlyFailing(AppDatabase db, String connectorId) async {
  final rows = await db.healthRows();
  for (final r in rows) {
    if (r['connector_id'] != connectorId) continue;
    final status = r['status'] as String?;
    final last = r['last_tested'] as int?;
    if (last == null) return false;
    final failing = status == ConnectorStatus.failed.name ||
        status == ConnectorStatus.rateLimited.name ||
        status == ConnectorStatus.blocked.name;
    final age = DateTime.now().millisecondsSinceEpoch - last;
    return failing && age < const Duration(minutes: 60).inMilliseconds;
  }
  return false;
}

/// يسجّل/يلغي المهمة الدورية. WorkManager على Android لا يسمح بأقل من 15 دقيقة.
Future<void> applyBackgroundSchedule({required bool enabled, required int requestedMinutes}) async {
  await Workmanager().cancelByUniqueName(kPeriodicUniqueName);
  if (!enabled) return;
  final effective = max(15, requestedMinutes);
  await Workmanager().registerPeriodicTask(
    kPeriodicUniqueName,
    kPeriodicTaskName,
    frequency: Duration(minutes: effective),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// كم دقيقة فعلياً تُطبَّق؟ (للعرض في الإعدادات بصدق)
int effectiveBackgroundMinutes(int requested) => max(15, requested);

Future<void> initBackground() async {
  await Workmanager().initialize(radarCallbackDispatcher, isInDebugMode: false);
}

String backgroundLimitNote() =>
    'Android يفرض حداً أدنى 15 دقيقة للمهام الدورية، وقد تتأخر المهام حسب قيود البطارية ووضع التوفير.';
