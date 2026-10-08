import 'package:flutter_test/flutter_test.dart';
import 'package:zomedica_radar/filters/normalizer.dart';
import 'package:zomedica_radar/filters/pipeline.dart';
import 'package:zomedica_radar/models/models.dart';

SearchResult _r({
  required String id,
  required String url,
  String title = 'Zomedica launches new device',
  String hash = '',
  double relevance = 50,
}) =>
    SearchResult(
      id: id,
      title: title,
      source: 'S',
      sourceType: SourceType.news,
      url: url,
      canonicalUrl: canonicalizeUrl(url),
      discoveredAt: DateTime.utc(2026, 10, 1),
      contentHash: hash,
      relevanceScore: relevance,
      freshnessScore: 80,
      sourceAuthorityScore: 70,
      confidenceScore: 70,
    );

void main() {
  test('canonicalizeUrl strips tracking params, fragments, www and trailing slash', () {
    expect(
      canonicalizeUrl('https://www.Example.com/news/item/?utm_source=x&id=5#top'),
      'https://example.com/news/item?id=5',
    );
  });

  test('canonicalizeUrl leaves non-URL text untouched', () {
    expect(canonicalizeUrl('  not a url  '), 'not a url');
  });

  test('exact canonical duplicate is detected', () {
    final p = ResultPipeline();
    expect(p.add(_r(id: 'a', url: 'https://x.com/a')).kind, DedupKind.accepted);
    expect(p.add(_r(id: 'b', url: 'https://x.com/a?utm_medium=feed')).kind, DedupKind.duplicate);
    expect(p.duplicatesRemoved, 1);
  });

  test('same content hash on another URL is treated as duplicate', () {
    final p = ResultPipeline();
    p.add(_r(id: 'a', url: 'https://one.com/a', hash: 'h1'));
    expect(p.add(_r(id: 'b', url: 'https://two.com/b', hash: 'h1')).kind, DedupKind.duplicate);
  });

  test('syndicated near-identical titles are grouped into one event', () {
    final p = ResultPipeline();
    final first = p.add(_r(id: 'a', url: 'https://one.com/a', title: 'Zomedica launches new PulseVet device today'));
    final second = p.add(_r(id: 'b', url: 'https://two.com/b', title: 'Zomedica launches new PulseVet device today'));
    expect(second.kind, DedupKind.syndicated);
    expect(second.eventId, first.eventId);
  });

  test('unrelated titles are accepted as separate events', () {
    final p = ResultPipeline();
    expect(p.add(_r(id: 'a', url: 'https://one.com/a', title: 'Zomedica quarterly earnings')).kind,
        DedupKind.accepted);
    expect(p.add(_r(id: 'b', url: 'https://two.com/b', title: 'Veterinary imaging market grows')).kind,
        DedupKind.accepted);
  });

  test('ranking orders by level then relevance', () {
    final low = _r(id: 'l', url: 'https://a.com/1', relevance: 5);
    final high = _r(id: 'h', url: 'https://a.com/2', relevance: 95);
    final ranked = ResultPipeline.rank([low, high]);
    expect(ranked.first.id, 'h');
  });

  test('queryTerms keeps quoted phrases as one term', () {
    expect(queryTerms('"Assisi Loop" Zomedica'), containsAll(['assisi loop', 'zomedica']));
  });

  test('parseLooseDate handles RFC-822, ISO and GDELT formats', () {
    expect(parseLooseDate('Tue, 06 Oct 2026 10:00:00 GMT'), DateTime.utc(2026, 10, 6, 10));
    expect(parseLooseDate('20261006T101500Z'), DateTime.utc(2026, 10, 6, 10, 15));
    expect(parseLooseDate('2026-10-06T10:00:00Z'), DateTime.utc(2026, 10, 6, 10));
    expect(parseLooseDate('garbage'), isNull);
  });
}
