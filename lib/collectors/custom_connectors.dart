import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../filters/normalizer.dart';
import '../models/models.dart';
import 'source_connector.dart';

/// مصدر مخصّص يعمل بإحدى الطرق: RSS / Sitemap / Search URL / Web Page / API.
/// الحقول الاختيارية للمحدِّدات: item, title, link, content, date, author (CSS selectors).
/// XPath و pagination متقدّم غير مدعومين حالياً (انظر Known Limitations).
class CustomSourceConnector extends SourceConnector {
  final SourceConfig config;
  CustomSourceConnector(this.config);

  @override
  String get id => config.id;
  @override
  String get name => config.name;
  @override
  SourceType get type => config.type;
  @override
  String get methodLabel => config.method.name;
  @override
  bool get queryDependent => config.url.contains('{query}');

  @override
  Capability get capability => Capability(
        free: true,
        rssSupported: config.method == SourceMethod.rss,
        scrapingSupported: config.method == SourceMethod.searchUrl ||
            config.method == SourceMethod.webPage,
      );

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async {
    final pages = <String>[];
    final maxPages = config.url.contains('{page}') ? ctx.limits.maxPagesPerSource : 1;
    for (var p = 1; p <= maxPages; p++) {
      if (ctx.cancel.isCancelled) break;
      final urlStr = config.url
          .replaceAll('{query}', Uri.encodeQueryComponent(query))
          .replaceAll('{page}', '$p');
      final uri = Uri.tryParse(urlStr);
      if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
        throw const ConnectorException(ErrorCode.notSupported, ConnectorStatus.notSupported,
            'Invalid URL (only http/https allowed)');
      }
      final resp = await SafeHttp.get(uri, ctx);
      pages.add(resp.body);
    }
    return pages;
  }

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) {
    final out = <SearchResult>[];
    for (final body in raw as List<String>) {
      if (out.length >= ctx.limits.maxResultsPerQuery) break;
      final remaining = ctx.limits.maxResultsPerQuery - out.length;
      final items = switch (config.method) {
        SourceMethod.rss => _parseRss(body, ctx, query),
        SourceMethod.sitemap => _parseSitemap(body, ctx, query),
        SourceMethod.searchUrl => _parseHtmlLinks(body, ctx, query),
        SourceMethod.webPage => _parseWebPage(body, ctx, query),
        SourceMethod.api => _parseJsonApi(body, ctx, query),
        SourceMethod.builtin => <SearchResult>[],
      };
      out.addAll(items.take(remaining));
    }
    return out;
  }

  String get _host => Uri.tryParse(config.url)?.host ?? '';

  SearchResult? _build(SearchContext ctx, String query, {
    required String title,
    required String url,
    String author = '',
    String content = '',
    DateTime? date,
  }) =>
      normalize(
        ctx: ctx,
        query: query,
        title: title,
        url: url.isEmpty ? config.url : url,
        author: author,
        content: content,
        publishedAt: date,
        authority: 50,
        actualSource: _host,
      );

  String _childText(XmlElement e, String local) {
    for (final c in e.childElements) {
      if (c.name.local == local) return c.innerText.trim();
    }
    return '';
  }

  List<SearchResult> _parseRss(String body, SearchContext ctx, String query) {
    final doc = XmlDocument.parse(body);
    final out = <SearchResult>[];
    final entries = [
      ...doc.findAllElements('item'),
      ...doc.findAllElements('entry'),
    ];
    for (final item in entries) {
      var link = _childText(item, 'link');
      if (link.isEmpty) {
        for (final c in item.childElements) {
          if (c.name.local == 'link') {
            link = c.getAttribute('href') ?? '';
            break;
          }
        }
      }
      final dateText = [
        _childText(item, 'pubDate'),
        _childText(item, 'published'),
        _childText(item, 'updated'),
      ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
      final r = _build(
        ctx,
        query,
        title: _childText(item, 'title'),
        url: link,
        author: _childText(item, 'creator').isNotEmpty
            ? _childText(item, 'creator')
            : _childText(item, 'author'),
        content: [_childText(item, 'description'), _childText(item, 'summary')]
            .firstWhere((s) => s.isNotEmpty, orElse: () => ''),
        date: parseLooseDate(dateText),
      );
      if (r != null) out.add(r);
    }
    return out;
  }

  List<SearchResult> _parseSitemap(String body, SearchContext ctx, String query) {
    final doc = XmlDocument.parse(body);
    final out = <SearchResult>[];
    for (final url in doc.findAllElements('url')) {
      final loc = _childText(url, 'loc');
      if (loc.isEmpty) continue;
      final uri = Uri.tryParse(loc);
      final segments = (uri?.pathSegments ?? const <String>[])
          .where((s) => s.isNotEmpty)
          .toList();
      final slug = segments.isEmpty ? loc : segments.last;
      final title = slug.replaceAll(RegExp(r'[-_+]+'), ' ').replaceAll('.html', '').trim();
      final r = _build(
        ctx,
        query,
        title: title,
        url: loc,
        date: parseLooseDate(_childText(url, 'lastmod')),
      );
      if (r != null) out.add(r);
    }
    return out;
  }

  T? _first<T>(List<T> l) => l.isEmpty ? null : l.first;

  dom.Document _html(String body) => html_parser.parse(body);

  List<dom.Element> _select(dom.Node scope, String? selector) {
    if (selector == null || selector.isEmpty) return const [];
    try {
      if (scope is dom.Document) return scope.querySelectorAll(selector);
      if (scope is dom.Element) return scope.querySelectorAll(selector);
      return const [];
    } catch (_) {
      throw const ConnectorException(ErrorCode.notSupported, ConnectorStatus.notSupported,
          'Invalid CSS selector in source configuration');
    }
  }

  List<SearchResult> _parseHtmlLinks(String body, SearchContext ctx, String query) {
    final doc = _html(body);
    final base = Uri.tryParse(config.url) ?? Uri();
    final selector = config.selectors['link'] ?? 'a[href]';
    final out = <SearchResult>[];
    for (final a in _select(doc, selector)) {
      final href = a.attributes['href'] ?? '';
      if (href.isEmpty || href.startsWith('#') || href.startsWith('javascript:')) continue;
      final resolved = base.resolve(href).toString();
      final r = _build(ctx, query, title: a.text, url: resolved);
      if (r != null) out.add(r);
    }
    return out;
  }

  List<SearchResult> _parseWebPage(String body, SearchContext ctx, String query) {
    final doc = _html(body);
    final sel = config.selectors;
    final out = <SearchResult>[];
    if ((sel['item'] ?? '').isNotEmpty) {
      for (final node in _select(doc, sel['item'])) {
        final titleEl = _first(_select(node, sel['title'] ?? 'h2, h3, a'));
        final linkEl = _first(_select(node, sel['link'] ?? 'a[href]'));
        final contentEl = _first(_select(node, sel['content']));
        final authorEl = _first(_select(node, sel['author']));
        final dateEl = _first(_select(node, sel['date']));
        final href = linkEl?.attributes['href'] ?? '';
        final r = _build(
          ctx,
          query,
          title: titleEl?.text ?? '',
          url: href.isEmpty ? config.url : Uri.parse(config.url).resolve(href).toString(),
          author: authorEl?.text.trim() ?? '',
          content: contentEl?.text ?? '',
          date: parseLooseDate(dateEl?.attributes['datetime'] ?? dateEl?.text),
        );
        if (r != null) out.add(r);
      }
      return out;
    }
    final title = _first(_select(doc, sel['title'] ?? 'title'))?.text ??
        _first(_select(doc, 'title'))?.text ??
        '';
    final desc = _first(_select(doc, sel['content']))?.text ??
        _first(_select(doc, 'meta[name=description]'))?.attributes['content'] ??
        '';
    final dateEl = _first(_select(doc, sel['date']));
    final r = _build(
      ctx,
      query,
      title: title,
      url: config.url,
      author: _first(_select(doc, sel['author']))?.text.trim() ?? '',
      content: desc,
      date: parseLooseDate(dateEl?.attributes['datetime'] ?? dateEl?.text),
    );
    if (r != null) out.add(r);
    return out;
  }

  List<SearchResult> _parseJsonApi(String body, SearchContext ctx, String query) {
    final decoded = _decodeAny(body);
    final list = decoded is List
        ? decoded
        : _firstList(decoded is Map ? decoded : const {});
    final out = <SearchResult>[];
    for (final it in list) {
      if (it is! Map) continue;
      final r = _build(
        ctx,
        query,
        title: _pick(it, const ['title', 'name', 'headline'])?.toString() ?? '',
        url: _pick(it, const ['url', 'link'])?.toString() ?? '',
        author: _pick(it, const ['author', 'source'])?.toString() ?? '',
        content: _pick(it, const ['description', 'summary', 'content'])?.toString() ?? '',
        date: parseLooseDate(_pick(it, const ['date', 'published_at', 'publishedAt', 'created_at'])?.toString()),
      );
      if (r != null) out.add(r);
    }
    return out;
  }

  Object? _decodeAny(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      throw const ConnectorException(ErrorCode.networkError, ConnectorStatus.failed,
          'API returned non-JSON content');
    }
  }

  List<dynamic> _firstList(Map<dynamic, dynamic> m) {
    for (final k in const ['items', 'results', 'articles', 'data']) {
      final v = m[k];
      if (v is List) return v;
    }
    return const [];
  }

  Object? _pick(Map<dynamic, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v;
    }
    return null;
  }
}
