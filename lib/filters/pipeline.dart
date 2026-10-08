import '../models/models.dart';

enum DedupKind { accepted, duplicate, syndicated }

class DedupResult {
  final DedupKind kind;
  final String eventId;
  const DedupResult(this.kind, this.eventId);
}

/// Deduplication (canonical URL + content hash + title similarity) + تجميع الأحداث.
class ResultPipeline {
  static const syndicationThreshold = 0.8;

  final Map<String, String> _eventByCanonical = {};
  final Map<String, String> _eventByHash = {};
  final Map<String, Set<String>> _eventTokens = {};
  int duplicatesRemoved = 0;

  DedupResult add(SearchResult r) {
    final known = _eventByCanonical[r.canonicalUrl];
    if (known != null) {
      duplicatesRemoved++;
      return DedupResult(DedupKind.duplicate, known);
    }
    if (r.contentHash.isNotEmpty) {
      final byHash = _eventByHash[r.contentHash];
      if (byHash != null) {
        duplicatesRemoved++;
        _eventByCanonical[r.canonicalUrl] = byHash;
        return DedupResult(DedupKind.duplicate, byHash);
      }
    }
    final tokens = titleTokens(r.title);
    for (final entry in _eventTokens.entries) {
      if (jaccard(entry.value, tokens) >= syndicationThreshold) {
        duplicatesRemoved++;
        _eventByCanonical[r.canonicalUrl] = entry.key;
        return DedupResult(DedupKind.syndicated, entry.key);
      }
    }
    final eventId = r.id;
    _eventTokens[eventId] = tokens;
    _eventByCanonical[r.canonicalUrl] = eventId;
    if (r.contentHash.isNotEmpty) _eventByHash[r.contentHash] = eventId;
    return DedupResult(DedupKind.accepted, eventId);
  }

  static Set<String> titleTokens(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.length >= 2)
      .toSet();

  static double jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final inter = a.intersection(b).length;
    final union = a.union(b).length;
    return union == 0 ? 0 : inter / union;
  }

  /// ترتيب: مستوى الترتيب ثم الصلة ثم الحداثة.
  static List<SearchResult> rank(List<SearchResult> items) {
    final copy = [...items];
    copy.sort((a, b) {
      final byLevel = a.rankLevel.index.compareTo(b.rankLevel.index);
      if (byLevel != 0) return byLevel;
      final byRel = b.relevanceScore.compareTo(a.relevanceScore);
      if (byRel != 0) return byRel;
      return b.freshnessScore.compareTo(a.freshnessScore);
    });
    return copy;
  }
}

