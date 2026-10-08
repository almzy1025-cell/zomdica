import 'dart:convert';

import 'package:xml/xml.dart';

import '../filters/normalizer.dart';
import '../models/models.dart';
import 'source_connector.dart';

String _childText(XmlElement e, String local) {
  for (final c in e.childElements) {
    if (c.name.local == local) return c.innerText.trim();
  }
  return '';
}

Map<String, dynamic> _asMap(Object? v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

List<dynamic> _asList(Object? v) => v is List ? v : const [];

Map<String, dynamic> _decodeJson(String body, String label) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List) return {'items': decoded};
    throw const FormatException('unexpected root');
  } catch (_) {
    throw ConnectorException(ErrorCode.networkError, ConnectorStatus.failed,
        '$label returned non-JSON content');
  }
}

/// Google News RSS (بحث عام، بدون مفتاح).
class GoogleNewsConnector extends SourceConnector {
  static const _host = 'news.google.com';

  @override
  String get id => 'google_news';
  @override
  String get name => 'Google News';
  @override
  SourceType get type => SourceType.news;
  @override
  String get methodLabel => 'rss';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability =>
      const Capability(free: true, rssSupported: true, scrapingSupported: false);

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final uri = Uri.https(_host, '/rss/search', {
      'q': query,
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });
    final resp = await SafeHttp.get(uri, ctx, headers: {'Accept': 'application/rss+xml'});
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final doc = XmlDocument.parse(raw as String);
    final out = <SearchResult>[];
    for (final item in doc.findAllElements('item')) {
      if (out.length >= ctx.limits.maxResultsPerQuery) break;
      final r = normalize(
        ctx: ctx,
        query: query,
        title: _childText(item, 'title'),
        url: _childText(item, 'link'),
        author: _childText(item, 'source'),
        content: _childText(item, 'description'),
        publishedAt: parseLooseDate(_childText(item, 'pubDate')),
        language: 'en',
        authority: 70,
        actualSource: _host,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// GDELT DOC 2.0 API (بدون مفتاح). قد يفرض حداً أدنى بين الطلبات.
class GdeltConnector extends SourceConnector {
  static const _host = 'api.gdeltproject.org';

  @override
  String get id => 'gdelt';
  @override
  String get name => 'GDELT';
  @override
  SourceType get type => SourceType.news;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(free: true);

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final uri = Uri.https(_host, '/api/v2/doc/doc', {
      'query': query,
      'mode': 'artlist',
      'format': 'json',
      'maxrecords': '${ctx.limits.maxResultsPerQuery}',
      'sort': 'datedesc',
    });
    final resp = await SafeHttp.get(uri, ctx);
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final root = _decodeJson(raw as String, 'GDELT');
    final out = <SearchResult>[];
    for (final a in _asList(root['articles'])) {
      final m = _asMap(a);
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (m['title'] as String?) ?? '',
        url: (m['url'] as String?) ?? '',
        author: (m['domain'] as String?) ?? '',
        publishedAt: parseLooseDate(m['seendate'] as String?),
        language: (m['language'] as String?) ?? '',
        country: (m['sourcecountry'] as String?) ?? '',
        authority: 60,
        actualSource: _host,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// Reddit search.json (قد يُحجب بدون OAuth — الحالة الفعلية تُعرض في Source Health).
class RedditConnector extends SourceConnector {
  static const _host = 'www.reddit.com';

  @override
  String get id => 'reddit';
  @override
  String get name => 'Reddit';
  @override
  SourceType get type => SourceType.forum;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(free: true, scrapingSupported: false);

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final uri = Uri.https(_host, '/search.json', {
      'q': query,
      'sort': 'new',
      'limit': '${ctx.limits.maxResultsPerQuery}',
      'raw_json': '1',
    });
    final resp = await SafeHttp.get(uri, ctx);
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final root = _decodeJson(raw as String, 'Reddit');
    final children = _asList(_asMap(root['data'])['children']);
    final out = <SearchResult>[];
    for (final c in children) {
      final d = _asMap(_asMap(c)['data']);
      final created = d['created_utc'];
      final permalink = (d['permalink'] as String?) ?? '';
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (d['title'] as String?) ?? '',
        url: permalink.isEmpty ? '' : 'https://www.reddit.com$permalink',
        author: 'r/${d['subreddit'] ?? ''} · u/${d['author'] ?? ''}',
        content: (d['selftext'] as String?) ?? '',
        publishedAt: created is num
            ? DateTime.fromMillisecondsSinceEpoch(created.toInt() * 1000, isUtc: true)
            : null,
        authority: 40,
        actualSource: _host,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// Hacker News عبر Algolia (واجهة عامة بدون مفتاح).
class HackerNewsConnector extends SourceConnector {
  static const _host = 'hn.algolia.com';

  @override
  String get id => 'hacker_news';
  @override
  String get name => 'Hacker News';
  @override
  SourceType get type => SourceType.forum;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(free: true);

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final uri = Uri.https(_host, '/api/v1/search', {
      'query': query,
      'tags': 'story',
      'hitsPerPage': '${ctx.limits.maxResultsPerQuery}',
    });
    final resp = await SafeHttp.get(uri, ctx);
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final root = _decodeJson(raw as String, 'Hacker News');
    final out = <SearchResult>[];
    for (final h in _asList(root['hits'])) {
      final m = _asMap(h);
      final objectId = (m['objectID'] ?? '').toString();
      final url = (m['url'] as String?) ?? '';
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (m['title'] as String?) ?? '',
        url: url.isNotEmpty ? url : 'https://news.ycombinator.com/item?id=$objectId',
        author: (m['author'] as String?) ?? '',
        content: (m['story_text'] as String?) ?? '',
        publishedAt: parseLooseDate(m['created_at'] as String?),
        authority: 50,
        actualSource: _host,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// PubMed عبر NCBI E-utilities (بدون مفتاح للاستخدام المحدود).
class PubMedConnector extends SourceConnector {
  static const _host = 'eutils.ncbi.nlm.nih.gov';

  @override
  String get id => 'pubmed';
  @override
  String get name => 'PubMed';
  @override
  SourceType get type => SourceType.academic;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(free: true);

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final searchUri = Uri.https(_host, '/entrez/eutils/esearch.fcgi', {
      'db': 'pubmed',
      'term': query,
      'retmax': '${ctx.limits.maxResultsPerQuery}',
      'retmode': 'json',
    });
    final searchRoot = _decodeJson((await SafeHttp.get(searchUri, ctx)).body, 'PubMed');
    final ids = _asList(_asMap(searchRoot['esearchresult'])['idlist']).cast<String>();
    if (ids.isEmpty) return <String, dynamic>{};
    final sumUri = Uri.https(_host, '/entrez/eutils/esummary.fcgi', {
      'db': 'pubmed',
      'id': ids.join(','),
      'retmode': 'json',
    });
    return _decodeJson((await SafeHttp.get(sumUri, ctx)).body, 'PubMed');
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final result = _asMap(_asMap(raw)['result']);
    final out = <SearchResult>[];
    for (final uid in _asList(result['uids']).cast<String>()) {
      if (out.length >= ctx.limits.maxResultsPerQuery) break;
      final m = _asMap(result[uid]);
      final authors = _asList(m['authors'])
          .map((a) => (_asMap(a)['name'] as String?) ?? '')
          .where((s) => s.isNotEmpty)
          .join(', ');
      final journal = (m['source'] as String?) ?? '';
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (m['title'] as String?) ?? '',
        url: 'https://pubmed.ncbi.nlm.nih.gov/$uid/',
        author: authors,
        content: '$journal ${(m['pubdate'] as String?) ?? ''} $authors',
        publishedAt: _pubmedDate((m['pubdate'] as String?) ?? ''),
        language: 'en',
        authority: 90,
        actualSource: _host,
        typeOverride: SourceType.academic,
      );
      if (r != null) out.add(r);
    }
    return out;
  }

  static DateTime? _pubmedDate(String s) {
    final parts = s.split(' ');
    final year = int.tryParse(parts.isNotEmpty ? parts[0] : '');
    if (year == null) return null;
    final month = parts.length > 1 ? _monthNumber(parts[1]) : 1;
    final day = parts.length > 2 ? int.tryParse(parts[2]) ?? 1 : 1;
    return DateTime.utc(year, month, day);
  }

  static int _monthNumber(String m) {
    const names = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final i = names.indexOf(m.toLowerCase().substring(0, m.length >= 3 ? 3 : m.length));
    return i < 0 ? 1 : i + 1;
  }
}

/// YouTube Data API v3 — يتطلب مفتاحاً اختيارياً من إعدادات API Keys.
class YouTubeConnector extends SourceConnector {
  static const _host = 'www.googleapis.com';
  final String? apiKey;

  YouTubeConnector({this.apiKey});

  @override
  String get id => 'youtube';
  @override
  String get name => 'YouTube';
  @override
  SourceType get type => SourceType.video;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(
        free: true,
        apiRequired: true,
        currentlyAvailable: true,
        unavailableReason: 'يتطلب مفتاح YouTube Data API v3',
      );

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw const ConnectorException(ErrorCode.apiRequired, ConnectorStatus.apiRequired,
          'Requires YouTube Data API key (add it in API Keys)');
    }
    final uri = Uri.https(_host, '/youtube/v3/search', {
      'part': 'snippet',
      'type': 'video',
      'order': 'date',
      'maxResults': '${ctx.limits.maxResultsPerQuery.clamp(1, 50)}',
      'q': query,
      'key': key,
    });
    final resp = await SafeHttp.get(uri, ctx);
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final root = _decodeJson(raw as String, 'YouTube');
    final out = <SearchResult>[];
    for (final it in _asList(root['items'])) {
      final m = _asMap(it);
      final vid = (_asMap(m['id'])['videoId'] as String?) ?? '';
      final s = _asMap(m['snippet']);
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (s['title'] as String?) ?? '',
        url: vid.isEmpty ? '' : 'https://www.youtube.com/watch?v=$vid',
        author: (s['channelTitle'] as String?) ?? '',
        content: (s['description'] as String?) ?? '',
        publishedAt: parseLooseDate(s['publishedAt'] as String?),
        authority: 60,
        actualSource: _host,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}

/// USPTO PatentSearch API (PatentsView) — يتطلب مفتاح X-Api-Key.
class UsptoPatentConnector extends SourceConnector {
  static const _host = 'search.patentsview.org';
  final String? apiKey;

  UsptoPatentConnector({this.apiKey});

  @override
  String get id => 'uspto_patents';
  @override
  String get name => 'USPTO Patents';
  @override
  SourceType get type => SourceType.patent;
  @override
  String get methodLabel => 'api';
  @override
  bool get serverSideMatch => true;
  @override
  Capability get capability => const Capability(
        free: true,
        apiRequired: true,
        unavailableReason: 'يتطلب مفتاح PatentSearch API (مجاني بعد التسجيل)',
      );

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final key = apiKey;
    if (key == null || key.isEmpty) {
      throw const ConnectorException(ErrorCode.apiRequired, ConnectorStatus.apiRequired,
          'Requires PatentSearch API key (add it in API Keys)');
    }
    final payload = {
      'q': {'_text_any': {'patent_title': query}},
      'f': [
        'patent_id',
        'patent_title',
        'patent_date',
        'inventors.inventor_name_first',
        'inventors.inventor_name_last',
      ],
      's': [
        {'patent_date': 'desc'}
      ],
      'o': {'size': ctx.limits.maxResultsPerQuery},
    };
    final resp = await SafeHttp.get(
      Uri.https(_host, '/api/v1/patent/'),
      ctx,
      method: 'POST',
      body: jsonEncode(payload),
      headers: {'X-Api-Key': key, 'Content-Type': 'application/json'},
    );
    return resp.body;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final root = _decodeJson(raw as String, 'USPTO');
    final out = <SearchResult>[];
    for (final p in _asList(root['patents'])) {
      final m = _asMap(p);
      final pid = (m['patent_id'] ?? '').toString();
      final inventors = _asList(m['inventors']).map((i) {
        final im = _asMap(i);
        return '${im['inventor_name_first'] ?? ''} ${im['inventor_name_last'] ?? ''}'.trim();
      }).where((s) => s.isNotEmpty).join(', ');
      final r = normalize(
        ctx: ctx,
        query: query,
        title: (m['patent_title'] as String?) ?? '',
        url: pid.isEmpty ? '' : 'https://patents.google.com/patent/US$pid',
        author: inventors,
        publishedAt: DateTime.tryParse((m['patent_date'] as String?) ?? ''),
        authority: 95,
        actualSource: _host,
        typeOverride: SourceType.patent,
      );
      if (r != null) out.add(r);
    }
    return out;
  }
}
