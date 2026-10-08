import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../filters/normalizer.dart';
import '../models/models.dart';

class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class CancelledException implements Exception {
  const CancelledException();
}

/// عدّاد الطلبات لكل جلسة بحث (Search Session Logging).
class RequestCounter {
  int requests = 0;
  int success = 0;
  int failed = 0;
}

class SearchContext {
  final String query;
  final String sessionId;
  final String requestedSource;
  final SearchLimits limits;
  final CancelToken cancel;
  final http.Client client;
  final RequestCounter counter;

  const SearchContext({
    required this.query,
    required this.sessionId,
    required this.requestedSource,
    required this.limits,
    required this.cancel,
    required this.client,
    required this.counter,
  });
}

/// الواجهة الموحدة لكل Connector.
abstract class SourceConnector {
  String get id;
  String get name;
  SourceType get type;
  Capability get capability;

  /// طريقة الجلب (تُعرض في النتيجة كـ searchMethod).
  String get methodLabel => 'api';

  /// هل نتيجة الاستعلام تعتمد على نص الاستعلام؟ إن لا، يُنفَّذ استعلام واحد فقط.
  bool get queryDependent => true;

  /// هل يطبّق المصدر الفلترة على الخادم؟ (يمنع إسقاط نتائج لا تحتوي المصطلح حرفياً)
  bool get serverSideMatch => false;

  /// الكتابة الفعلية للشبكة. يرمي ConnectorException عند الفشل.
  Future<dynamic> fetch(String query, SearchContext ctx);

  /// تحويل الاستجابة الخام إلى نتائج موحّدة.
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query);

  /// البث: كل نتيجة تُرسل فور جاهزيتها (Streaming).
  Stream<SearchResult> search(String query, SearchContext ctx) async* {
    final raw = await fetch(query, ctx);
    for (final r in parse(raw, ctx, query)) {
      if (ctx.cancel.isCancelled) return;
      yield r;
    }
  }

  /// يُنشئ نتيجة موحّدة من سجل خام (Normalize).
  SearchResult? normalize({
    required SearchContext ctx,
    required String query,
    required String title,
    required String url,
    String author = '',
    String content = '',
    DateTime? publishedAt,
    String language = '',
    String country = '',
    double authority = 50,
    String actualSource = '',
    SourceType? typeOverride,
  }) =>
      normalizeRecord(
        query: query,
        sessionId: ctx.sessionId,
        requestedSource: ctx.requestedSource,
        connectorId: id,
        connectorName: name,
        methodLabel: methodLabel,
        actualSource: actualSource,
        type: typeOverride ?? type,
        title: title,
        url: url,
        author: author,
        content: content,
        publishedAt: publishedAt,
        language: language,
        country: country,
        authority: authority,
        serverSideMatch: serverSideMatch,
        maxContentChars: ctx.limits.maxStoredContentChars,
      );
}

/// يُنفّذ طلبات HTTP بمهلة 10 ثوانٍ، وتدوير User-Agent، وحد معدل، وحد حجم، وإعادة محاولة.
class SafeHttp {
  SafeHttp._();

  static final Map<String, DateTime> _lastRequestByHost = {};
  static final Random _rng = Random();

  static String randomUserAgent() =>
      AppConfig.userAgents[_rng.nextInt(AppConfig.userAgents.length)];

  static Future<http.Response> get(
    Uri uri,
    SearchContext ctx, {
    Map<String, String> headers = const {},
    String method = 'GET',
    String? body,
  }) async {
    var attempt = 0;
    while (true) {
      if (ctx.cancel.isCancelled) throw const CancelledException();
      await _throttle(uri.host, ctx.limits.maxRequestsPerMinute);
      ctx.counter.requests++;
      final reqHeaders = {
        'User-Agent': randomUserAgent(),
        'Accept': 'application/json, application/rss+xml, application/xml, text/html;q=0.9, */*;q=0.5',
        ...headers,
      };
      http.Response resp;
      try {
        final future = method == 'POST'
            ? ctx.client.post(uri, headers: reqHeaders, body: body)
            : ctx.client.get(uri, headers: reqHeaders);
        resp = await future.timeout(AppConfig.requestTimeout);
      } on TimeoutException {
        ctx.counter.failed++;
        if (attempt < AppConfig.maxRetries) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
          continue;
        }
        throw ConnectorException(
          ErrorCode.networkError,
          ConnectorStatus.failed,
          'Timeout after ${AppConfig.requestTimeout.inSeconds}s',
        );
      } on CancelledException {
        rethrow;
      } catch (_) {
        // لا نُسرّب الرابط (قد يحتوي مفاتيح API) في رسالة الخطأ.
        ctx.counter.failed++;
        if (attempt < AppConfig.maxRetries) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
          continue;
        }
        throw ConnectorException(
          ErrorCode.networkError,
          ConnectorStatus.failed,
          'Network error (${uri.host})',
        );
      }

      if (resp.bodyBytes.length > ctx.limits.maxResponseBytes) {
        ctx.counter.failed++;
        throw ConnectorException(
          ErrorCode.networkError,
          ConnectorStatus.failed,
          'Response exceeds ${ctx.limits.maxResponseBytes} bytes limit',
          httpStatus: resp.statusCode,
        );
      }
      final code = resp.statusCode;
      if (code >= 200 && code < 300) {
        ctx.counter.success++;
        return resp;
      }
      ctx.counter.failed++;
      if (code == 429) {
        throw ConnectorException(ErrorCode.rateLimited, ConnectorStatus.rateLimited,
            'HTTP 429 - rate limited by provider', httpStatus: code);
      }
      if (code == 401) {
        throw ConnectorException(ErrorCode.loginRequired, ConnectorStatus.loginRequired,
            'HTTP 401 - provider requires authentication', httpStatus: code);
      }
      if (code == 403) {
        throw ConnectorException(ErrorCode.accessRestricted, ConnectorStatus.blocked,
            'HTTP 403 - provider restricts anonymous access', httpStatus: code);
      }
      if (code >= 500 && attempt < AppConfig.maxRetries) {
        attempt++;
        await Future<void>.delayed(Duration(milliseconds: 400 * (1 << attempt)));
        continue;
      }
      throw ConnectorException(ErrorCode.networkError, ConnectorStatus.failed,
          'HTTP $code', httpStatus: code);
    }
  }

  static Future<void> _throttle(String host, int maxPerMinute) async {
    if (maxPerMinute <= 0) return;
    final gap = Duration(milliseconds: (60000 / maxPerMinute).ceil());
    final last = _lastRequestByHost[host];
    final now = DateTime.now();
    if (last != null) {
      final wait = last.add(gap).difference(now);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequestByHost[host] = DateTime.now();
  }
}

/// Connector يعرض حالته الحقيقية بدون بحث (API/Login/Blocked/Not supported).
class StatusOnlyConnector extends SourceConnector {
  @override
  final String id;
  @override
  final String name;
  @override
  final SourceType type;
  @override
  final Capability capability;
  final ConnectorStatus status;
  final ErrorCode errorCode;
  final String reason;

  StatusOnlyConnector({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.errorCode,
    required this.reason,
    required this.capability,
  });

  @override
  String get methodLabel => 'none';

  @override
  Future<dynamic> fetch(String query, SearchContext ctx) async =>
      throw ConnectorException(errorCode, status, reason);

  @override
  List<SearchResult> parse(dynamic raw, SearchContext ctx, String query) => const [];
}
