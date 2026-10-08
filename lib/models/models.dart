import 'dart:convert';

enum ConnectorStatus {
  ready, running, success, failed, blocked, loginRequired,
  apiRequired, rateLimited, notSupported, disabled,
}

enum ErrorCode {
  none, accessRestricted, loginRequired, apiRequired,
  rateLimited, networkError, notSupported,
}

enum SourceType {
  news, forum, social, video, patent, trademark, inventor,
  academic, pressRelease, job, archive, other,
}

enum SourceMethod { builtin, rss, sitemap, searchUrl, webPage, api }

enum KeywordCategory { company, product, executive, inventor, competitor, custom }

enum RankLevel { veryHigh, high, medium, low }

String rankLevelLabel(RankLevel l) {
  switch (l) {
    case RankLevel.veryHigh:
      return 'VERY HIGH';
    case RankLevel.high:
      return 'HIGH';
    case RankLevel.medium:
      return 'MEDIUM';
    case RankLevel.low:
      return 'LOW';
  }
}

/// قدرات الـConnector (Source Capability Matrix).
class Capability {
  final bool free;
  final bool apiRequired;
  final bool loginRequired;
  final bool rssSupported;
  final bool scrapingSupported;
  final bool currentlyAvailable;
  final String unavailableReason;

  const Capability({
    this.free = true,
    this.apiRequired = false,
    this.loginRequired = false,
    this.rssSupported = false,
    this.scrapingSupported = false,
    this.currentlyAvailable = true,
    this.unavailableReason = '',
  });
}

class ConnectorException implements Exception {
  final ErrorCode code;
  final ConnectorStatus status;
  final String message;
  final int? httpStatus;

  const ConnectorException(this.code, this.status, this.message, {this.httpStatus});

  @override
  String toString() => 'ConnectorException(${code.name}): $message';
}

class SourceHealth {
  final String connectorId;
  final String name;
  final ConnectorStatus status;
  final ErrorCode errorCode;
  final String reason;
  final int resultCount;
  final int durationMs;
  final int? httpStatus;
  final DateTime? lastTested;
  final String requestedSource;
  final String actualSource;

  const SourceHealth({
    required this.connectorId,
    required this.name,
    required this.status,
    this.errorCode = ErrorCode.none,
    this.reason = '',
    this.resultCount = 0,
    this.durationMs = 0,
    this.httpStatus,
    this.lastTested,
    this.requestedSource = '',
    this.actualSource = '',
  });

  Map<String, Object?> toMap() => {
        'connector_id': connectorId,
        'name': name,
        'status': status.name,
        'error_code': errorCode.name,
        'reason': reason,
        'last_result_count': resultCount,
        'last_duration_ms': durationMs,
        'http_status': httpStatus,
        'last_tested': lastTested?.millisecondsSinceEpoch,
      };

  factory SourceHealth.fromMap(Map<String, Object?> m) => SourceHealth(
        connectorId: m['connector_id'] as String,
        name: (m['name'] as String?) ?? '',
        status: ConnectorStatus.values.byName((m['status'] as String?) ?? 'ready'),
        errorCode: ErrorCode.values.byName((m['error_code'] as String?) ?? 'none'),
        reason: (m['reason'] as String?) ?? '',
        resultCount: (m['last_result_count'] as int?) ?? 0,
        durationMs: (m['last_duration_ms'] as int?) ?? 0,
        httpStatus: m['http_status'] as int?,
        lastTested: m['last_tested'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_tested'] as int),
      );
}

class SearchResult {
  final String id;
  final String title;
  final String source;
  final SourceType sourceType;
  final String url;
  final String canonicalUrl;
  final DateTime? publishedAt;
  final DateTime discoveredAt;
  final String author;
  final String content;
  final String snippet;
  final String language;
  final String country;
  final List<String> keywords;
  final List<String> entities;
  final double relevanceScore;
  final double freshnessScore;
  final double sourceAuthorityScore;
  final double confidenceScore;
  final String searchMethod;
  final String requestedSource;
  final String actualSource;
  final String connectorId;
  final String searchSessionId;
  final String evidenceId;
  final String eventId;
  final String contentHash;
  final String aiSummary;
  final String whyMatched;
  final List<String> otherSources;
  final bool favorite;

  const SearchResult({
    required this.id,
    required this.title,
    required this.source,
    required this.sourceType,
    required this.url,
    required this.canonicalUrl,
    required this.discoveredAt,
    this.publishedAt,
    this.author = '',
    this.content = '',
    this.snippet = '',
    this.language = '',
    this.country = '',
    this.keywords = const [],
    this.entities = const [],
    this.relevanceScore = 0,
    this.freshnessScore = 0,
    this.sourceAuthorityScore = 0,
    this.confidenceScore = 0,
    this.searchMethod = '',
    this.requestedSource = '',
    this.actualSource = '',
    this.connectorId = '',
    this.searchSessionId = '',
    this.evidenceId = '',
    this.eventId = '',
    this.contentHash = '',
    this.aiSummary = '',
    this.whyMatched = '',
    this.otherSources = const [],
    this.favorite = false,
  });

  SearchResult copyWith({String? eventId, List<String>? otherSources, bool? favorite}) {
    return SearchResult(
      id: id,
      title: title,
      source: source,
      sourceType: sourceType,
      url: url,
      canonicalUrl: canonicalUrl,
      discoveredAt: discoveredAt,
      publishedAt: publishedAt,
      author: author,
      content: content,
      snippet: snippet,
      language: language,
      country: country,
      keywords: keywords,
      entities: entities,
      relevanceScore: relevanceScore,
      freshnessScore: freshnessScore,
      sourceAuthorityScore: sourceAuthorityScore,
      confidenceScore: confidenceScore,
      searchMethod: searchMethod,
      requestedSource: requestedSource,
      actualSource: actualSource,
      connectorId: connectorId,
      searchSessionId: searchSessionId,
      evidenceId: evidenceId,
      eventId: eventId ?? this.eventId,
      contentHash: contentHash,
      aiSummary: aiSummary,
      whyMatched: whyMatched,
      otherSources: otherSources ?? this.otherSources,
      favorite: favorite ?? this.favorite,
    );
  }

  /// مستوى الترتيب مع السبب (Ranking).
  RankLevel get rankLevel {
    final s = relevanceScore * 0.4 + freshnessScore * 0.2 +
        sourceAuthorityScore * 0.2 + confidenceScore * 0.2;
    if (s >= 80) return RankLevel.veryHigh;
    if (s >= 60) return RankLevel.high;
    if (s >= 40) return RankLevel.medium;
    return RankLevel.low;
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'source': source,
        'source_type': sourceType.name,
        'url': url,
        'canonical_url': canonicalUrl,
        'published_at': publishedAt?.millisecondsSinceEpoch,
        'discovered_at': discoveredAt.millisecondsSinceEpoch,
        'author': author,
        'content': content,
        'snippet': snippet,
        'language': language,
        'country': country,
        'keywords': jsonEncode(keywords),
        'entities': jsonEncode(entities),
        'relevance_score': relevanceScore,
        'freshness_score': freshnessScore,
        'source_authority_score': sourceAuthorityScore,
        'confidence_score': confidenceScore,
        'search_method': searchMethod,
        'requested_source': requestedSource,
        'actual_source': actualSource,
        'connector_id': connectorId,
        'search_session_id': searchSessionId,
        'evidence_id': evidenceId,
        'event_id': eventId,
        'content_hash': contentHash,
        'ai_summary': aiSummary,
        'why_matched': whyMatched,
        'other_sources': jsonEncode(otherSources),
        'favorite': favorite ? 1 : 0,
      };

  factory SearchResult.fromMap(Map<String, Object?> m) => SearchResult(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        source: (m['source'] as String?) ?? '',
        sourceType: SourceType.values.byName((m['source_type'] as String?) ?? 'other'),
        url: (m['url'] as String?) ?? '',
        canonicalUrl: (m['canonical_url'] as String?) ?? '',
        publishedAt: m['published_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['published_at'] as int),
        discoveredAt: DateTime.fromMillisecondsSinceEpoch(m['discovered_at'] as int),
        author: (m['author'] as String?) ?? '',
        content: (m['content'] as String?) ?? '',
        snippet: (m['snippet'] as String?) ?? '',
        language: (m['language'] as String?) ?? '',
        country: (m['country'] as String?) ?? '',
        keywords: _strList(m['keywords']),
        entities: _strList(m['entities']),
        relevanceScore: ((m['relevance_score'] as num?) ?? 0).toDouble(),
        freshnessScore: ((m['freshness_score'] as num?) ?? 0).toDouble(),
        sourceAuthorityScore: ((m['source_authority_score'] as num?) ?? 0).toDouble(),
        confidenceScore: ((m['confidence_score'] as num?) ?? 0).toDouble(),
        searchMethod: (m['search_method'] as String?) ?? '',
        requestedSource: (m['requested_source'] as String?) ?? '',
        actualSource: (m['actual_source'] as String?) ?? '',
        connectorId: (m['connector_id'] as String?) ?? '',
        searchSessionId: (m['search_session_id'] as String?) ?? '',
        evidenceId: (m['evidence_id'] as String?) ?? '',
        eventId: (m['event_id'] as String?) ?? '',
        contentHash: (m['content_hash'] as String?) ?? '',
        aiSummary: (m['ai_summary'] as String?) ?? '',
        whyMatched: (m['why_matched'] as String?) ?? '',
        otherSources: _strList(m['other_sources']),
        favorite: (m['favorite'] as int?) == 1,
      );

  static List<String> _strList(Object? v) {
    if (v is! String || v.isEmpty) return const [];
    return (jsonDecode(v) as List).cast<String>();
  }
}

/// أحداث البث (Streaming) من المنسّق إلى الواجهة.
sealed class SearchEvent {
  const SearchEvent();
}

class SessionStarted extends SearchEvent {
  final String sessionId;
  final String query;
  final List<String> expandedQueries;
  final List<String> connectorIds;
  const SessionStarted(this.sessionId, this.query, this.expandedQueries, this.connectorIds);
}

class ConnectorStarted extends SearchEvent {
  final String connectorId;
  final String name;
  const ConnectorStarted(this.connectorId, this.name);
}

class ResultFound extends SearchEvent {
  final SearchResult result;
  final int totalSoFar;
  const ResultFound(this.result, this.totalSoFar);
}

class ConnectorFinished extends SearchEvent {
  final SourceHealth health;
  const ConnectorFinished(this.health);
}

class SessionFinished extends SearchEvent {
  final SearchSession session;
  const SessionFinished(this.session);
}

class SearchSession {
  final String id;
  final String query;
  final List<String> expandedQueries;
  final List<String> connectorsUsed;
  final int requests;
  final int successfulRequests;
  final int failedRequests;
  final int resultsFound;
  final int duplicatesRemoved;
  final int durationMs;
  final List<String> errors;
  final bool cancelled;
  final DateTime startedAt;

  const SearchSession({
    required this.id,
    required this.query,
    required this.expandedQueries,
    required this.connectorsUsed,
    required this.requests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.resultsFound,
    required this.duplicatesRemoved,
    required this.durationMs,
    required this.errors,
    required this.cancelled,
    required this.startedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'query': query,
        'expanded_queries': jsonEncode(expandedQueries),
        'connectors': jsonEncode(connectorsUsed),
        'requests': requests,
        'successful_requests': successfulRequests,
        'failed_requests': failedRequests,
        'results_found': resultsFound,
        'duplicates_removed': duplicatesRemoved,
        'duration_ms': durationMs,
        'errors': jsonEncode(errors),
        'cancelled': cancelled ? 1 : 0,
        'started_at': startedAt.millisecondsSinceEpoch,
      };

  factory SearchSession.fromMap(Map<String, Object?> m) => SearchSession(
        id: m['id'] as String,
        query: (m['query'] as String?) ?? '',
        expandedQueries: SearchResult._strList(m['expanded_queries']),
        connectorsUsed: SearchResult._strList(m['connectors']),
        requests: (m['requests'] as int?) ?? 0,
        successfulRequests: (m['successful_requests'] as int?) ?? 0,
        failedRequests: (m['failed_requests'] as int?) ?? 0,
        resultsFound: (m['results_found'] as int?) ?? 0,
        duplicatesRemoved: (m['duplicates_removed'] as int?) ?? 0,
        durationMs: (m['duration_ms'] as int?) ?? 0,
        errors: SearchResult._strList(m['errors']),
        cancelled: (m['cancelled'] as int?) == 1,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
      );
}

class Keyword {
  final String id;
  final String term;
  final KeywordCategory category;
  final List<String> aliases;
  final bool enabled;
  final String group;

  const Keyword({
    required this.id,
    required this.term,
    required this.category,
    this.aliases = const [],
    this.enabled = true,
    this.group = 'Zomedica',
  });

  Keyword copyWith({bool? enabled}) => Keyword(
        id: id,
        term: term,
        category: category,
        aliases: aliases,
        enabled: enabled ?? this.enabled,
        group: group,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'term': term,
        'category': category.name,
        'aliases': jsonEncode(aliases),
        'enabled': enabled ? 1 : 0,
        'group_name': group,
      };

  factory Keyword.fromMap(Map<String, Object?> m) => Keyword(
        id: m['id'] as String,
        term: m['term'] as String,
        category: KeywordCategory.values.byName((m['category'] as String?) ?? 'custom'),
        aliases: SearchResult._strList(m['aliases']),
        enabled: (m['enabled'] as int?) != 0,
        group: (m['group_name'] as String?) ?? 'Zomedica',
      );
}

class SourceConfig {
  final String id;
  final String name;
  final SourceType type;
  final SourceMethod method;
  final String url;
  final bool enabled;
  final int priority;
  final int pollingMinutes;
  final String connectorId;
  final bool isBuiltin;
  final Map<String, String> selectors;

  const SourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.method,
    required this.url,
    required this.connectorId,
    this.enabled = true,
    this.priority = 50,
    this.pollingMinutes = 60,
    this.isBuiltin = false,
    this.selectors = const {},
  });

  SourceConfig copyWith({bool? enabled, int? priority, int? pollingMinutes}) => SourceConfig(
        id: id,
        name: name,
        type: type,
        method: method,
        url: url,
        connectorId: connectorId,
        enabled: enabled ?? this.enabled,
        priority: priority ?? this.priority,
        pollingMinutes: pollingMinutes ?? this.pollingMinutes,
        isBuiltin: isBuiltin,
        selectors: selectors,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'method': method.name,
        'url': url,
        'enabled': enabled ? 1 : 0,
        'priority': priority,
        'polling_minutes': pollingMinutes,
        'connector_id': connectorId,
        'is_builtin': isBuiltin ? 1 : 0,
        'selectors': jsonEncode(selectors),
      };

  factory SourceConfig.fromMap(Map<String, Object?> m) => SourceConfig(
        id: m['id'] as String,
        name: m['name'] as String,
        type: SourceType.values.byName((m['type'] as String?) ?? 'other'),
        method: SourceMethod.values.byName((m['method'] as String?) ?? 'builtin'),
        url: (m['url'] as String?) ?? '',
        connectorId: (m['connector_id'] as String?) ?? '',
        enabled: (m['enabled'] as int?) != 0,
        priority: (m['priority'] as int?) ?? 50,
        pollingMinutes: (m['polling_minutes'] as int?) ?? 60,
        isBuiltin: (m['is_builtin'] as int?) == 1,
        selectors: ((jsonDecode((m['selectors'] as String?) ?? '{}')) as Map)
            .map((k, v) => MapEntry(k as String, v as String)),
      );
}

/// نتيجة مكررة/مجمّعة في حدث واحد (لا تُعرض كنتيجة جديدة، تُحفظ مرتبطة بالحدث).
class ResultDuplicate extends SearchEvent {
  final SearchResult result;
  final String kind;
  const ResultDuplicate(this.result, this.kind);
}
