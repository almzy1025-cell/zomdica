import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zomedica_radar/collectors/builtin_connectors.dart';
import 'package:zomedica_radar/collectors/source_connector.dart';
import 'package:zomedica_radar/config/app_config.dart';
import 'package:zomedica_radar/filters/normalizer.dart';
import 'package:zomedica_radar/models/models.dart';

// بيانات اختبار مُدمجة داخل test/ فقط (Test fixtures) — لا تظهر في التطبيق الإنتاجي.
const _rssFixture = '''<?xml version="1.0"?>
<rss version="2.0"><channel>
<item>
  <title>Zomedica reports quarterly update</title>
  <link>https://example.com/news/zomedica-q</link>
  <pubDate>Tue, 06 Oct 2026 10:00:00 GMT</pubDate>
  <description>&lt;p&gt;Zomedica shares details of its platform.&lt;/p&gt;</description>
  <source url="https://example.com">Example Wire</source>
</item>
</channel></rss>''';

SearchContext _ctx(http.Client client, {CancelToken? cancel}) => SearchContext(
      query: 'Zomedica',
      sessionId: 'test-session',
      requestedSource: 'test',
      limits: const SearchLimits(maxRequestsPerMinute: 60000),
      cancel: cancel ?? CancelToken(),
      client: client,
      counter: RequestCounter(),
    );

void main() {
  test('Google News RSS parser produces normalized results with traceable evidence', () async {
    final client = MockClient((req) async => http.Response(_rssFixture, 200,
        headers: {'content-type': 'application/rss+xml'}));
    final c = GoogleNewsConnector();
    final ctx = _ctx(client);
    final results = await c.search('Zomedica', ctx).toList();
    expect(results.length, 1);
    final r = results.single;
    expect(r.title, 'Zomedica reports quarterly update');
    expect(r.source, 'Example Wire');
    expect(r.connectorId, 'google_news');
    expect(r.actualSource, 'news.google.com');
    expect(r.requestedSource, 'test');
    expect(r.evidenceId, startsWith('ev_'));
    expect(r.content, contains('Zomedica shares details'));
    expect(r.aiSummary, contains('Zomedica'));
    expect(r.publishedAt, DateTime.utc(2026, 10, 6, 10));
  });

  test('HTTP 429 maps to RATE_LIMITED, not SUCCESS', () async {
    final client = MockClient((req) async => http.Response('slow down', 429));
    final c = GdeltConnector();
    expect(
      () => c.search('Zomedica', _ctx(client)).toList(),
      throwsA(isA<ConnectorException>()
          .having((e) => e.status, 'status', ConnectorStatus.rateLimited)
          .having((e) => e.code, 'code', ErrorCode.rateLimited)),
    );
  });

  test('HTTP 403 maps to BLOCKED / ACCESS_RESTRICTED', () async {
    final client = MockClient((req) async => http.Response('forbidden', 403));
    final c = RedditConnector();
    expect(
      () => c.search('Zomedica', _ctx(client)).toList(),
      throwsA(isA<ConnectorException>()
          .having((e) => e.status, 'status', ConnectorStatus.blocked)
          .having((e) => e.code, 'code', ErrorCode.accessRestricted)),
    );
  });

  test('YouTube without key reports API_REQUIRED without any network call', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response('', 200);
    });
    final c = YouTubeConnector();
    expect(
      () => c.search('Zomedica', _ctx(client)).toList(),
      throwsA(isA<ConnectorException>()
          .having((e) => e.status, 'status', ConnectorStatus.apiRequired)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
  });

  test('Response size limit is enforced', () async {
    final big = 'x' * 5000;
    final client = MockClient((req) async => http.Response(big, 200));
    final ctx = SearchContext(
      query: 'Zomedica',
      sessionId: 's',
      requestedSource: 'test',
      limits: const SearchLimits(maxResponseBytes: 1000, maxRequestsPerMinute: 60000),
      cancel: CancelToken(),
      client: client,
      counter: RequestCounter(),
    );
    expect(
      () => GoogleNewsConnector().search('Zomedica', ctx).toList(),
      throwsA(isA<ConnectorException>()
          .having((e) => e.code, 'code', ErrorCode.networkError)),
    );
  });

  test('Cancelled token stops before any request is made', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(_rssFixture, 200);
    });
    final token = CancelToken()..cancel();
    expect(
      () => GoogleNewsConnector().search('Zomedica', _ctx(client, cancel: token)).toList(),
      throwsA(isA<CancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 0);
  });

  test('Reddit JSON parser normalizes children', () async {
    final body = jsonEncode({
      'data': {
        'children': [
          {
            'data': {
              'title': 'Zomedica discussion',
              'permalink': '/r/veterinary/comments/abc/zomedica/',
              'selftext': 'People talk about Zomedica devices.',
              'created_utc': 1759744800,
              'author': 'vet_user',
              'subreddit': 'veterinary',
            }
          }
        ]
      }
    });
    final client = MockClient((req) async => http.Response(body, 200));
    final results = await RedditConnector().search('Zomedica', _ctx(client)).toList();
    expect(results.single.url, 'https://www.reddit.com/r/veterinary/comments/abc/zomedica/');
    expect(results.single.sourceType, SourceType.forum);
  });

  test('Server-side search results are kept and labelled as server-side match', () async {
    final body = jsonEncode({
      'data': {
        'children': [
          {
            'data': {
              'title': 'Unrelated cats article',
              'permalink': '/r/cats/x/',
              'selftext': 'nothing relevant',
              'created_utc': 1759744800,
            }
          }
        ]
      }
    });
    final client = MockClient((req) async => http.Response(body, 200));
    final results = await RedditConnector().search('Zomedica', _ctx(client)).toList();
    expect(results.length, 1);
    expect(results.single.whyMatched, contains('server-side match'));
    expect(results.single.keywords, isEmpty);
  });

  test('Client-side normalization drops records with no matching evidence', () {
    final r = normalizeRecord(
      query: 'Zomedica',
      sessionId: 's',
      requestedSource: 'test',
      connectorId: 'custom',
      connectorName: 'Custom',
      methodLabel: 'rss',
      actualSource: 'example.com',
      type: SourceType.news,
      title: 'Unrelated cats article',
      url: 'https://example.com/cats',
      content: 'nothing relevant here',
      serverSideMatch: false,
    );
    expect(r, isNull);
  });

  test('defaults remain conservative and configurable', () {
    const l = AppConfig.defaultLimits;
    expect(l.maxPagesPerSource, 1);
    expect(l.maxRequestsPerMinute, 20);
    expect(l.maxSearchDurationSeconds, 60);
    expect(l.copyWith(maxResultsPerQuery: 80).maxResultsPerQuery, 80);
  });
}
