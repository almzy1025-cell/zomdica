import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../collectors/registry.dart';
import '../collectors/source_connector.dart';
import '../config/app_config.dart';
import '../filters/pipeline.dart';
import '../models/models.dart';

/// توسيع الاستعلام المحدود: الاستعلام الأصلي + مرادفات/منتجات مفعّلة فقط (بحد أقصى).
List<String> expandQueries(String base, List<Keyword> keywords, int maxQueries) {
  final out = <String>[base];
  final lowerBase = base.toLowerCase();
  final candidates = keywords
      .where((k) => k.enabled && (k.category == KeywordCategory.company ||
          k.category == KeywordCategory.product))
      .expand((k) => [k.term, ...k.aliases]);
  for (final term in candidates) {
    if (out.length >= maxQueries) break;
    final t = term.trim();
    if (t.isEmpty) continue;
    if (lowerBase.contains(t.toLowerCase())) continue;
    if (out.any((o) => o.toLowerCase() == t.toLowerCase())) continue;
    out.add(t);
  }
  return out;
}

class SearchOrchestrator {
  final List<ConnectorEntry> entries;
  final SearchLimits limits;

  SearchOrchestrator({required this.entries, required this.limits});

  /// يبدأ بحثاً ويُرجع Stream أحداث تصل تباعاً.
  /// الإلغاء: token.cancel() يوقف العمل المتبقي فوراً ثم يصدر SessionFinished(cancelled).
  Stream<SearchEvent> search({
    required String query,
    required List<String> expandedQueries,
    required String requestedSource,
    CancelToken? cancel,
  }) {
    final token = cancel ?? CancelToken();
    final controller = StreamController<SearchEvent>();
    final run = _SearchRun(
      entries: entries,
      limits: limits,
      query: query,
      queries: expandedQueries.take(limits.maxQueriesPerSearch).toList(),
      requestedSource: requestedSource,
      token: token,
      out: controller,
    );
    unawaited(run.execute());
    controller.onCancel = token.cancel;
    return controller.stream;
  }
}

class _QueryResult {
  final int added;
  final bool ok;
  final ConnectorException? error;
  const _QueryResult(this.added, this.ok, this.error);
}

class _SearchRun {
  final List<ConnectorEntry> entries;
  final SearchLimits limits;
  final String query;
  final List<String> queries;
  final String requestedSource;
  final CancelToken token;
  final StreamController<SearchEvent> out;

  final String sessionId = _newId();
  final DateTime startedAt = DateTime.now();
  final RequestCounter counter = RequestCounter();
  final ResultPipeline pipeline = ResultPipeline();
  final List<String> errors = [];
  final List<String> usedConnectors = [];
  final http.Client client = http.Client();
  int total = 0;
  bool timedOut = false;

  _SearchRun({
    required this.entries,
    required this.limits,
    required this.query,
    required this.queries,
    required this.requestedSource,
    required this.token,
    required this.out,
  });

  static String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${Random().nextInt(1 << 20).toRadixString(36)}';

  void _emit(SearchEvent e) {
    if (!out.isClosed) out.add(e);
  }

  Future<void> execute() async {
    final enabled = entries.where((e) => e.config.enabled).toList()
      ..sort((a, b) => a.config.priority.compareTo(b.config.priority));
    final disabled = entries.where((e) => !e.config.enabled);

    _emit(SessionStarted(sessionId, query, queries, enabled.map((e) => e.connector.id).toList()));
    for (final d in disabled) {
      _emit(ConnectorFinished(SourceHealth(
        connectorId: d.connector.id,
        name: d.connector.name,
        status: ConnectorStatus.disabled,
        reason: 'Disabled by user',
        requestedSource: requestedSource,
        lastTested: DateTime.now(),
      )));
    }

    final deadline = Timer(Duration(seconds: limits.maxSearchDurationSeconds), () {
      timedOut = true;
      token.cancel();
    });

    final queue = Queue<ConnectorEntry>.of(enabled);
    Future<void> worker() async {
      while (queue.isNotEmpty && !token.isCancelled) {
        await _runConnector(queue.removeFirst());
      }
    }

    final workers = min(limits.maxConcurrentConnectors, max(1, enabled.length));
    try {
      await Future.wait(List.generate(workers, (_) => worker()));
    } finally {
      deadline.cancel();
      final finishedAt = DateTime.now();
      if (timedOut) errors.add('Search time limit reached (${limits.maxSearchDurationSeconds}s)');
      _emit(SessionFinished(SearchSession(
        id: sessionId,
        query: query,
        expandedQueries: queries,
        connectorsUsed: usedConnectors,
        requests: counter.requests,
        successfulRequests: counter.success,
        failedRequests: counter.failed,
        resultsFound: total,
        duplicatesRemoved: pipeline.duplicatesRemoved,
        durationMs: finishedAt.difference(startedAt).inMilliseconds,
        errors: errors,
        cancelled: token.isCancelled && !timedOut,
        startedAt: startedAt,
      )));
      await out.close();
      client.close();
    }
  }

  Future<void> _runConnector(ConnectorEntry e) async {
    final c = e.connector;
    usedConnectors.add(c.id);
    _emit(ConnectorStarted(c.id, c.name));
    final t0 = DateTime.now();
    var added = 0;
    var anyOk = false;
    ConnectorException? lastError;

    final qs = c.queryDependent ? queries : [queries.first];
    for (final q in qs) {
      if (token.isCancelled) break;
      final r = await _runQuery(c, q);
      added += r.added;
      if (r.ok) anyOk = true;
      if (r.error != null) lastError = r.error;
    }

    final duration = DateTime.now().difference(t0).inMilliseconds;
    late final SourceHealth health;
    if (!anyOk && token.isCancelled) {
      health = _health(c, ConnectorStatus.ready, ErrorCode.none, 'Cancelled', added, duration);
    } else if (anyOk) {
      final partial = lastError != null ? 'Partial: ${lastError.message}' : '';
      health = _health(c, ConnectorStatus.success, ErrorCode.none,
          partial.isNotEmpty ? partial : (added == 0 ? 'No matching evidence' : ''), added, duration);
    } else {
      final msg = lastError?.message ?? 'Unknown failure';
      errors.add('${c.name}: $msg');
      health = SourceHealth(
        connectorId: c.id,
        name: c.name,
        status: lastError?.status ?? ConnectorStatus.failed,
        errorCode: lastError?.code ?? ErrorCode.networkError,
        reason: msg,
        resultCount: added,
        durationMs: duration,
        httpStatus: lastError?.httpStatus,
        lastTested: DateTime.now(),
        requestedSource: requestedSource,
        actualSource: c.name,
      );
    }
    _emit(ConnectorFinished(health));
  }

  SourceHealth _health(SourceConnector c, ConnectorStatus s, ErrorCode code, String reason,
      int count, int duration) =>
      SourceHealth(
        connectorId: c.id,
        name: c.name,
        status: s,
        errorCode: code,
        reason: reason,
        resultCount: count,
        durationMs: duration,
        lastTested: DateTime.now(),
        requestedSource: requestedSource,
        actualSource: c.name,
      );

  Future<_QueryResult> _runQuery(SourceConnector c, String q) async {
    final ctx = SearchContext(
      query: q,
      sessionId: sessionId,
      requestedSource: requestedSource,
      limits: limits,
      cancel: token,
      client: client,
      counter: counter,
    );
    final done = Completer<void>();
    ConnectorException? error;
    var cancelledNow = false;
    var added = 0;
    StreamSubscription<SearchResult>? sub;

    // استجابة سريعة للإلغاء: لا ننتظر الطلبات المعلّقة.
    final poll = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (token.isCancelled && !done.isCompleted) done.complete();
    });
    try {
      sub = c.search(q, ctx).listen(
        (r) {
          if (token.isCancelled) return;
          final d = pipeline.add(r);
          if (d.kind == DedupKind.accepted) {
            total++;
            added++;
            _emit(ResultFound(r.copyWith(eventId: d.eventId), total));
          } else {
            _emit(ResultDuplicate(r.copyWith(eventId: d.eventId), d.kind.name));
          }
        },
        onError: (Object err, StackTrace _) {
          if (err is CancelledException) {
            cancelledNow = true;
          } else if (err is ConnectorException) {
            error = err;
          } else {
            error = ConnectorException(
                ErrorCode.networkError, ConnectorStatus.failed,
                'Unexpected error (${err.runtimeType})');
          }
          if (!done.isCompleted) done.complete();
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      await done.future.timeout(AppConfig.connectorHardTimeout);
    } on TimeoutException {
      error = ConnectorException(ErrorCode.networkError, ConnectorStatus.failed,
          'Connector timeout (${AppConfig.connectorHardTimeout.inSeconds}s)');
    } finally {
      poll.cancel();
      await sub?.cancel();
    }
    final ok = error == null && !cancelledNow;
    return _QueryResult(added, ok, error);
  }
}
