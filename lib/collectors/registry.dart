import '../models/models.dart';
import 'builtin_connectors.dart';
import 'custom_connectors.dart';
import 'source_connector.dart';

class ConnectorEntry {
  final SourceConnector connector;
  final SourceConfig config;
  const ConnectorEntry(this.connector, this.config);
}

/// المصادر المدمجة كـ Seed في جدول sources. لا توجد مصادر hard-coded داخل منطق البحث.
List<SourceConfig> builtinSourceSeeds() => const [
      SourceConfig(id: 'src_google_news', name: 'Google News', type: SourceType.news, method: SourceMethod.builtin, url: 'https://news.google.com/rss/search', connectorId: 'google_news', isBuiltin: true, priority: 10),
      SourceConfig(id: 'src_gdelt', name: 'GDELT', type: SourceType.news, method: SourceMethod.api, url: 'https://api.gdeltproject.org/api/v2/doc/doc', connectorId: 'gdelt', isBuiltin: true, priority: 12),
      SourceConfig(id: 'src_uspto_patents', name: 'USPTO Patents', type: SourceType.patent, method: SourceMethod.api, url: 'https://search.patentsview.org/api/v1/patent/', connectorId: 'uspto_patents', isBuiltin: true, priority: 15),
      SourceConfig(id: 'src_youtube', name: 'YouTube', type: SourceType.video, method: SourceMethod.api, url: 'https://www.googleapis.com/youtube/v3/search', connectorId: 'youtube', isBuiltin: true, priority: 20),
      SourceConfig(id: 'src_reddit', name: 'Reddit', type: SourceType.forum, method: SourceMethod.api, url: 'https://www.reddit.com/search.json', connectorId: 'reddit', isBuiltin: true, priority: 22),
      SourceConfig(id: 'src_hacker_news', name: 'Hacker News', type: SourceType.forum, method: SourceMethod.api, url: 'https://hn.algolia.com/api/v1/search', connectorId: 'hacker_news', isBuiltin: true, priority: 25),
      SourceConfig(id: 'src_pubmed', name: 'PubMed', type: SourceType.academic, method: SourceMethod.api, url: 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/', connectorId: 'pubmed', isBuiltin: true, priority: 30),
      SourceConfig(id: 'src_x', name: 'X (Twitter)', type: SourceType.social, method: SourceMethod.api, url: 'https://api.x.com', connectorId: 'x_twitter', isBuiltin: true, priority: 80),
      SourceConfig(id: 'src_instagram', name: 'Instagram', type: SourceType.social, method: SourceMethod.webPage, url: 'https://www.instagram.com', connectorId: 'instagram', isBuiltin: true, priority: 81),
      SourceConfig(id: 'src_facebook', name: 'Facebook', type: SourceType.social, method: SourceMethod.webPage, url: 'https://www.facebook.com', connectorId: 'facebook', isBuiltin: true, priority: 82),
      SourceConfig(id: 'src_linkedin', name: 'LinkedIn', type: SourceType.social, method: SourceMethod.webPage, url: 'https://www.linkedin.com', connectorId: 'linkedin', isBuiltin: true, priority: 83),
      SourceConfig(id: 'src_vin', name: 'VIN Forum', type: SourceType.forum, method: SourceMethod.webPage, url: 'https://www.vin.com', connectorId: 'vin', isBuiltin: true, priority: 84),
      SourceConfig(id: 'src_vetsurgeon', name: 'VetSurgeon', type: SourceType.forum, method: SourceMethod.webPage, url: 'https://www.vetsurgeon.org', connectorId: 'vetsurgeon', isBuiltin: true, priority: 85),
      SourceConfig(id: 'src_google_patents', name: 'Google Patents', type: SourceType.patent, method: SourceMethod.webPage, url: 'https://patents.google.com', connectorId: 'google_patents', isBuiltin: true, priority: 86),
      SourceConfig(id: 'src_uspto_tm', name: 'USPTO Trademarks', type: SourceType.trademark, method: SourceMethod.api, url: 'https://tmsearch.uspto.gov', connectorId: 'uspto_trademark', isBuiltin: true, priority: 87),
      SourceConfig(id: 'src_euipo', name: 'EUIPO Trademarks', type: SourceType.trademark, method: SourceMethod.api, url: 'https://euipo.europa.eu', connectorId: 'euipo_trademark', isBuiltin: true, priority: 88),
      SourceConfig(id: 'src_wipo_brands', name: 'WIPO Global Brand Database', type: SourceType.trademark, method: SourceMethod.webPage, url: 'https://www3.wipo.int/brandb', connectorId: 'wipo_brands', isBuiltin: true, priority: 89),
      SourceConfig(id: 'src_bing_news', name: 'Bing News', type: SourceType.news, method: SourceMethod.api, url: 'https://www.bing.com/news', connectorId: 'bing_news', isBuiltin: true, priority: 90),
      SourceConfig(id: 'src_ddg_news', name: 'DuckDuckGo News', type: SourceType.news, method: SourceMethod.webPage, url: 'https://duckduckgo.com', connectorId: 'ddg_news', isBuiltin: true, priority: 91),
    ];

/// Connectors ذات الحالة الفعلية فقط (لا تنفذ بحثاً). كل سبب موثّق في README.
List<StatusOnlyConnector> statusOnlyCatalog() => [
      StatusOnlyConnector(
        id: 'x_twitter', name: 'X (Twitter)', type: SourceType.social,
        status: ConnectorStatus.apiRequired, errorCode: ErrorCode.apiRequired,
        reason: 'X search requires paid API access; no anonymous search is performed.',
        capability: const Capability(free: false, apiRequired: true, currentlyAvailable: false,
            unavailableReason: 'API required'),
      ),
      StatusOnlyConnector(
        id: 'instagram', name: 'Instagram', type: SourceType.social,
        status: ConnectorStatus.blocked, errorCode: ErrorCode.accessRestricted,
        reason: 'Instagram restricts anonymous search and scraping; no public search API.',
        capability: const Capability(loginRequired: true, currentlyAvailable: false,
            unavailableReason: 'Blocked by provider'),
      ),
      StatusOnlyConnector(
        id: 'facebook', name: 'Facebook', type: SourceType.social,
        status: ConnectorStatus.loginRequired, errorCode: ErrorCode.loginRequired,
        reason: 'Facebook public search requires login.',
        capability: const Capability(loginRequired: true, currentlyAvailable: false,
            unavailableReason: 'Login required'),
      ),
      StatusOnlyConnector(
        id: 'linkedin', name: 'LinkedIn', type: SourceType.social,
        status: ConnectorStatus.loginRequired, errorCode: ErrorCode.loginRequired,
        reason: 'LinkedIn search requires login or partner API access.',
        capability: const Capability(loginRequired: true, apiRequired: true, currentlyAvailable: false,
            unavailableReason: 'Login/API required'),
      ),
      StatusOnlyConnector(
        id: 'vin', name: 'VIN Forum', type: SourceType.forum,
        status: ConnectorStatus.loginRequired, errorCode: ErrorCode.loginRequired,
        reason: 'VIN forum content requires a member login.',
        capability: const Capability(loginRequired: true, currentlyAvailable: false,
            unavailableReason: 'Login required'),
      ),
      StatusOnlyConnector(
        id: 'vetsurgeon', name: 'VetSurgeon', type: SourceType.forum,
        status: ConnectorStatus.notSupported, errorCode: ErrorCode.notSupported,
        reason: 'No verified public search endpoint. Add it via Sources Manager as a Custom Web (Search URL) source.',
        capability: const Capability(currentlyAvailable: false,
            unavailableReason: 'No verified endpoint'),
      ),
      StatusOnlyConnector(
        id: 'google_patents', name: 'Google Patents', type: SourceType.patent,
        status: ConnectorStatus.notSupported, errorCode: ErrorCode.notSupported,
        reason: 'Google Patents has no official public search API; HTML scraping is not implemented.',
        capability: const Capability(currentlyAvailable: false,
            unavailableReason: 'No official API'),
      ),
      StatusOnlyConnector(
        id: 'uspto_trademark', name: 'USPTO Trademarks', type: SourceType.trademark,
        status: ConnectorStatus.loginRequired, errorCode: ErrorCode.loginRequired,
        reason: 'USPTO trademark search requires login/API access; the legacy public TESS search is retired.',
        capability: const Capability(loginRequired: true, apiRequired: true, currentlyAvailable: false,
            unavailableReason: 'Login/API required'),
      ),
      StatusOnlyConnector(
        id: 'euipo_trademark', name: 'EUIPO Trademarks', type: SourceType.trademark,
        status: ConnectorStatus.apiRequired, errorCode: ErrorCode.apiRequired,
        reason: 'EUIPO trademark data requires registered API credentials (not configured).',
        capability: const Capability(apiRequired: true, free: false, currentlyAvailable: false,
            unavailableReason: 'API credentials required'),
      ),
      StatusOnlyConnector(
        id: 'wipo_brands', name: 'WIPO Global Brand Database', type: SourceType.trademark,
        status: ConnectorStatus.notSupported, errorCode: ErrorCode.notSupported,
        reason: 'No verified public API; HTML scraping is not implemented.',
        capability: const Capability(currentlyAvailable: false,
            unavailableReason: 'No verified API'),
      ),
      StatusOnlyConnector(
        id: 'bing_news', name: 'Bing News', type: SourceType.news,
        status: ConnectorStatus.notSupported, errorCode: ErrorCode.notSupported,
        reason: 'Microsoft retired the Bing Search APIs in 2025; no free replacement is configured.',
        capability: const Capability(apiRequired: true, currentlyAvailable: false,
            unavailableReason: 'Bing Search API retired'),
      ),
      StatusOnlyConnector(
        id: 'ddg_news', name: 'DuckDuckGo News', type: SourceType.news,
        status: ConnectorStatus.notSupported, errorCode: ErrorCode.notSupported,
        reason: 'No official API; search-engine scraping is not implemented.',
        capability: const Capability(currentlyAvailable: false,
            unavailableReason: 'No official API'),
      ),
    ];

/// يبني Connector لكل مصدر. المصادر المخصّصة تُبنى من الإعداد نفسه.
SourceConnector? connectorFor(SourceConfig cfg, {String? youtubeKey, String? usptoKey}) {
  if (!cfg.isBuiltin) return CustomSourceConnector(cfg);
  switch (cfg.connectorId) {
    case 'google_news':
      return GoogleNewsConnector();
    case 'gdelt':
      return GdeltConnector();
    case 'reddit':
      return RedditConnector();
    case 'hacker_news':
      return HackerNewsConnector();
    case 'pubmed':
      return PubMedConnector();
    case 'youtube':
      return YouTubeConnector(apiKey: youtubeKey);
    case 'uspto_patents':
      return UsptoPatentConnector(apiKey: usptoKey);
  }
  for (final s in statusOnlyCatalog()) {
    if (s.id == cfg.connectorId) return s;
  }
  return null;
}
