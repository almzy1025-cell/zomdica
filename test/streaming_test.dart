import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zomedica_radar/collectors/registry.dart';
import 'package:zomedica_radar/config/app_config.dart';
import 'package:zomedica_radar/collectors/source_connector.dart';
import 'package:zomedica_radar/models/models.dart';
import 'package:zomedica_radar/services/search_orchestrator.dart';

/// Connector اختباري يبث نتائجه تباعاً (Test fixture فقط).
class _SlowStreamConnector extends SourceConnector {
  final String _id;
  final int delayMs;
  final int count;
  final bool fail;

  _SlowStreamConnector(this._id, {this.delayMs = 10, this.count = 2, this.fail = false});

  @override
  String get id => _id;
  @override
  String get name => _id;
  @override
  SourceType get type => SourceType.news;
  @override
  Capability get capability => const Capability();
  @override
  bool get serverSideMatch => true;

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async => null;

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) => const [];

  @override
  Stream<SearchResult> search(String query, SearchContext ctx) async* {
    if (fail) throw const ConnectorException(ErrorCode.networkError, ConnectorStatus.failed, 'boom');
    for (var i = 0; i < count; i++) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (ctx.cancel.isCancelled) return;
      yield normalize(
        ctx: ctx,
        query: query,
        title: 'Zomedica item $_id number$i',
        url: 'https://$_id.example.com/item/$i',
        content: 'Zomedica content $i',
        authority: 50,
        actualSource: '$_id.example.com',
      )!;
    }
  }
}

ConnectorEntry _e(SourceConnector c, {int priority = 50}) => ConnectorEntry(
      c,
      SourceConfig(
        id: c.id,
        name: c.name,
        type: c.type,
        method: SourceMethod.builtin,
        url: '',
        connectorId: c.id,
        priority: priority,
        isBuiltin: true,
      ),
    );

void main() {
  test('results are streamed before all connectors finish', () async {
    final fast = _SlowStreamConnector('fast', delayMs: 5, count: 2);
    final slow = _SlowStreamConnector('slow', delayMs: 400, count: 1);
    final orch = SearchOrchestrator(
      entries: [_e(fast), _e(slow)],
      limits: const SearchLimits(maxConcurrentConnectors: 4),
    );
    final events = <SearchEvent>[];
    final sub = orch
        .search(query: 'Zomedica', expandedQueries: const ['Zomedica'], requestedSource: 't')
        .listen((e) {
      events.add(e);
    });
    await sub.asFuture<void>();
    // لا نعتمد على الترتيب الدقيق، بل على أن الحدث الأول وصل قبل نهاية الثاني.
    final slowDone = events.indexWhere((e) => e is ConnectorFinished && e.health.connectorId == 'slow');
    final firstResult = events.indexWhere((e) => e is ResultFound);
    expect(firstResult, greaterThanOrEqualTo(0));
    expect(firstResult < slowDone, isTrue, reason: 'first result must arrive before slow connector finishes');
  });

  test('a failing connector does not stop the rest of the search', () async {
    final bad = _SlowStreamConnector('bad', fail: true);
    final good = _SlowStreamConnector('good', count: 2);
    final orch = SearchOrchestrator(entries: [_e(bad), _e(good)], limits: const SearchLimits());
    final events = await orch
        .search(query: 'Zomedica', expandedQueries: const ['Zomedica'], requestedSource: 't')
        .toList();
    final health = events.whereType<ConnectorFinished>().map((e) => e.health).toList();
    expect(health.firstWhere((h) => h.connectorId == 'bad').status, ConnectorStatus.failed);
    expect(health.firstWhere((h) => h.connectorId == 'good').status, ConnectorStatus.success);
    expect(events.whereType<ResultFound>().length, 2);
    expect(events.last, isA<SessionFinished>());
  });

  test('cancel stops remaining work and reports cancelled session', () async {
    final slow = _SlowStreamConnector('slow', delayMs: 200, count: 10);
    final token = CancelToken();
    final orch = SearchOrchestrator(entries: [_e(slow)], limits: const SearchLimits());
    final events = <SearchEvent>[];
    final sub = orch
        .search(
          query: 'Zomedica',
          expandedQueries: const ['Zomedica'],
          requestedSource: 't',
          cancel: token,
        )
        .listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    token.cancel();
    await sub.asFuture<void>();
    final found = events.whereType<ResultFound>().length;
    expect(found, lessThan(10));
    final finished = events.last as SessionFinished;
    expect(finished.session.cancelled, isTrue);
  });

  test('disabled connectors are reported as DISABLED and never queried', () async {
    final disabledEntry = ConnectorEntry(
      _SlowStreamConnector('off'),
      const SourceConfig(
        id: 'off',
        name: 'off',
        type: SourceType.news,
        method: SourceMethod.builtin,
        url: '',
        connectorId: 'off',
        enabled: false,
        isBuiltin: true,
      ),
    );
    final orch = SearchOrchestrator(entries: [disabledEntry], limits: const SearchLimits());
    final events = await orch
        .search(query: 'Zomedica', expandedQueries: const ['Zomedica'], requestedSource: 't')
        .toList();
    final h = events.whereType<ConnectorFinished>().single.health;
    expect(h.status, ConnectorStatus.disabled);
    expect(events.whereType<ResultFound>(), isEmpty);
  });

  test('expandQueries is bounded and only uses enabled company/product terms', () {
    final kws = [
      const Keyword(id: '1', term: 'Zomedica', category: KeywordCategory.company,
          aliases: ['Zomedica Corp', 'ZOM']),
      const Keyword(id: '2', term: 'PulseVet', category: KeywordCategory.product, enabled: false),
      const Keyword(id: '3', term: 'TRUVIEW', category: KeywordCategory.product),
    ];
    final q = expandQueries('Zomedica', kws, 3);
    expect(q.first, 'Zomedica');
    expect(q.length, lessThanOrEqualTo(3));
    expect(q, isNot(contains('PulseVet')));
  });

  test('registry returns real connectors for built-in ids and status-only ones', () {
    final seeds = builtinSourceSeeds();
    expect(seeds.where((s) => connectorFor(s) != null).length, seeds.length);
    final x = connectorFor(seeds.firstWhere((s) => s.connectorId == 'x_twitter'));
    expect(x?.capability.apiRequired, isTrue);
  });
}
