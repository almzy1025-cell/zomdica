import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/models.dart';

const _trackingPrefixes = ['utm_', 'fbclid', 'gclid', 'mc_cid', 'mc_eid', 'ref_src'];

String sha1Hex(String s) => sha1.convert(utf8.encode(s)).toString();

/// توحيد الرابط: حذف تتبّع، توحيد المضيف، إزالة الشرطة النهائية والـ fragment.
String canonicalizeUrl(String raw) {
  final trimmed = raw.trim();
  final u = Uri.tryParse(trimmed);
  if (u == null || !u.hasScheme || u.host.isEmpty) return trimmed;
  final params = Map<String, String>.from(u.queryParameters)
    ..removeWhere((k, _) {
      final lk = k.toLowerCase();
      return _trackingPrefixes.any(lk.startsWith);
    });
  var path = u.path;
  if (path.length > 1 && path.endsWith('/')) path = path.substring(0, path.length - 1);
  final host = u.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  final port = (u.hasPort && u.port != 80 && u.port != 443) ? u.port : null;
  return Uri(
    scheme: u.scheme.toLowerCase(),
    host: host,
    port: port,
    path: path,
    queryParameters: params.isEmpty ? null : params,
  ).toString();
}

String stripHtml(String s) {
  var t = s
      .replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m[1]!);
    return code == null ? m[0]! : String.fromCharCode(code);
  });
  t = t
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// يحلل ISO-8601 و RFC-822 (RSS) و yyyyMMddTHHmmssZ (GDELT).
DateTime? parseLooseDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final s = raw.trim();
  final gdelt = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$').firstMatch(s);
  if (gdelt != null) {
    final g = gdelt;
    return DateTime.utc(
      int.parse(g[1]!), int.parse(g[2]!), int.parse(g[3]!),
      int.parse(g[4]!), int.parse(g[5]!), int.parse(g[6]!),
    );
  }
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso.toUtc();
  final rfc = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?').firstMatch(s);
  if (rfc != null) {
    final month = _months[rfc[2]!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(rfc[3]!), month, int.parse(rfc[1]!),
      int.parse(rfc[4]!), int.parse(rfc[5]!), int.parse(rfc[6] ?? '0'),
    );
  }
  return null;
}

/// مصطلحات البحث (العبارات بين علامات التنصيص تُعامل كمصطلح واحد).
List<String> queryTerms(String query) {
  final terms = <String>[];
  final phrase = RegExp(r'"([^"]+)"');
  var rest = query;
  for (final m in phrase.allMatches(query)) {
    terms.add(m[1]!.toLowerCase().trim());
  }
  rest = rest.replaceAll(phrase, ' ');
  for (final w in rest.split(RegExp(r'\s+'))) {
    final t = w.toLowerCase().trim();
    if (t.length >= 2) terms.add(t);
  }
  return terms.where((t) => t.isNotEmpty).toSet().toList();
}

double _freshness(DateTime? published) {
  if (published == null) return 30;
  final days = DateTime.now().toUtc().difference(published).inHours / 24;
  if (days <= 1) return 100;
  if (days <= 7) return 80;
  if (days <= 30) return 60;
  if (days <= 180) return 40;
  return 20;
}

/// يُنشئ SearchResult موحّداً مع الدرجات والتتبع. يُرجع null إذا لا يوجد دليل مطابق.
SearchResult? normalizeRecord({
  required String query,
  required String sessionId,
  required String requestedSource,
  required String connectorId,
  required String connectorName,
  required String methodLabel,
  required String actualSource,
  required SourceType type,
  required String title,
  required String url,
  String author = '',
  String content = '',
  DateTime? publishedAt,
  String language = '',
  String country = '',
  double authority = 50,
  bool serverSideMatch = false,
  int maxContentChars = 4000,
}) {
  final cleanTitle = stripHtml(title);
  final cleanContent = stripHtml(content);
  if (cleanTitle.isEmpty || url.trim().isEmpty) return null;
  final canonical = canonicalizeUrl(url);
  final terms = queryTerms(query);
  final lowerTitle = cleanTitle.toLowerCase();
  final lowerText = '$cleanTitle $cleanContent'.toLowerCase();
  final matched = terms.where(lowerText.contains).toList();
  final titleHits = terms.where(lowerTitle.contains).length;

  var relevance = terms.isEmpty
      ? 0.0
      : (titleHits / terms.length) * 60 + (matched.length / terms.length) * 40;
  if (serverSideMatch && relevance < 30) relevance = 30;
  if (matched.isEmpty && !serverSideMatch) return null;

  final freshness = _freshness(publishedAt);
  final confidence = (authority * 0.4 + relevance * 0.4 + (publishedAt != null ? 20 : 0))
      .clamp(0, 100)
      .toDouble();

  final truncated = cleanContent.length > maxContentChars
      ? cleanContent.substring(0, maxContentChars)
      : cleanContent;
  final snippet = truncated.length > 240 ? '${truncated.substring(0, 240)}…' : truncated;

  return SearchResult(
    id: sha1Hex(canonical),
    title: cleanTitle,
    source: author.isNotEmpty && type == SourceType.news ? author : connectorName,
    sourceType: type,
    url: url.trim(),
    canonicalUrl: canonical,
    publishedAt: publishedAt,
    discoveredAt: DateTime.now(),
    author: author,
    content: truncated,
    snippet: snippet,
    language: language,
    country: country,
    keywords: matched,
    entities: matched,
    relevanceScore: relevance.clamp(0, 100).toDouble(),
    freshnessScore: freshness,
    sourceAuthorityScore: authority,
    confidenceScore: confidence,
    searchMethod: methodLabel,
    requestedSource: requestedSource,
    actualSource: actualSource,
    connectorId: connectorId,
    searchSessionId: sessionId,
    evidenceId: 'ev_${sha1Hex('$canonical|$sessionId').substring(0, 16)}',
    contentHash: truncated.isEmpty
        ? ''
        : sha1Hex(truncated.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')),
    aiSummary: _extractiveSummary(truncated, snippet, matched),
    whyMatched: _whyMatched(matched, titleHits > 0, authority, connectorName, methodLabel),
  );
}

/// ملخص استخراجي: جمل حرفية من المصدر فقط — لا توليد.
String _extractiveSummary(String content, String snippet, List<String> matched) {
  if (content.isEmpty) return snippet;
  final sentences = content.split(RegExp(r'(?<=[.!?؟])\s+'));
  final picked = sentences
      .where((s) => matched.any(s.toLowerCase().contains))
      .take(2)
      .toList();
  if (picked.isEmpty) return snippet;
  return picked.join(' ');
}

String _whyMatched(List<String> matched, bool inTitle, double authority, String connector, String method) {
  final parts = <String>[
    'Matched: ${matched.isEmpty ? "server-side match" : matched.join(", ")}',
    inTitle ? 'In title: yes' : 'In title: no',
    'Authority: ${authority.toStringAsFixed(0)}',
    'Connector: $connector',
    'Method: $method',
  ];
  return parts.join(' | ');
}
