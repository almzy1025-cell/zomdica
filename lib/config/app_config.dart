import 'package:flutter/widgets.dart';

class AppConfig {
  AppConfig._();

  static const appName = 'Zomedica Radar';
  static const versionName = '1.0.0';
  static const versionCode = 1;
  static const schemaVersion = 1;

  /// مهلة صارمة لكل طلب شبكة.
  static const requestTimeout = Duration(seconds: 10);

  /// لا ينتظر أي Connector أكثر من هذه المدة (تشمل المحاولات).
  static const connectorHardTimeout = Duration(seconds: 12);

  static const maxRetries = 1;

  static const userAgents = <String>[
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    'Mozilla/5.0 (X11; Linux x86_64; rv:126.0) Gecko/20100101 Firefox/126.0',
    'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
  ];

  /// الحد الافتراضي المحافظ (قابل للتعديل من الإعدادات).
  static const defaultLimits = SearchLimits();
}

@immutable
class SearchLimits {
  final int maxPagesPerSource;
  final int maxResultsPerQuery;
  final int maxRequestsPerMinute;
  final int maxResponseBytes;
  final int maxSearchDurationSeconds;
  final int maxStoredContentChars;
  final int maxConcurrentConnectors;
  final int maxQueriesPerSearch;

  const SearchLimits({
    this.maxPagesPerSource = 1,
    this.maxResultsPerQuery = 30,
    this.maxRequestsPerMinute = 20,
    this.maxResponseBytes = 2 * 1024 * 1024,
    this.maxSearchDurationSeconds = 60,
    this.maxStoredContentChars = 4000,
    this.maxConcurrentConnectors = 4,
    this.maxQueriesPerSearch = 5,
  });

  SearchLimits copyWith({int? maxResultsPerQuery, int? maxConcurrentConnectors}) => SearchLimits(
        maxPagesPerSource: maxPagesPerSource,
        maxResultsPerQuery: maxResultsPerQuery ?? this.maxResultsPerQuery,
        maxRequestsPerMinute: maxRequestsPerMinute,
        maxResponseBytes: maxResponseBytes,
        maxSearchDurationSeconds: maxSearchDurationSeconds,
        maxStoredContentChars: maxStoredContentChars,
        maxConcurrentConnectors: maxConcurrentConnectors ?? this.maxConcurrentConnectors,
        maxQueriesPerSearch: maxQueriesPerSearch,
      );
}

/// نص ثنائي اللغة بسيط بدون حزم توطين إضافية.
String tr(BuildContext context, String ar, String en) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
