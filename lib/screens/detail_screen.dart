import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/providers.dart';
import '../widgets/common_widgets.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final SearchResult result;
  const DetailScreen({super.key, required this.result});

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  late bool _favorite = widget.result.favorite;
  late final Future<List<SearchResult>> _related =
      ref.read(databaseProvider).resultsByEvent(widget.result.eventId);

  Future<void> _toggleFavorite() async {
    final next = !_favorite;
    await ref.read(databaseProvider).setFavorite(widget.result.id, next);
    ref.invalidate(favoritesProvider);
    ref.invalidate(resultsProvider);
    setState(() => _favorite = next);
  }

  Future<void> _openSource() async {
    final uri = Uri.tryParse(widget.result.url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _snack(tr(context, 'تعذّر فتح الرابط', 'Could not open the link'));
  }

  void _share() {
    final r = widget.result;
    Share.share('${r.title}\n${r.source} · ${formatDateTime(r.publishedAt)}\n${r.url}',
        subject: r.title);
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _snack(tr(context, 'تم النسخ', 'Copied'));
  }

  Future<void> _translate() async {
    final text = widget.result.snippet.isNotEmpty ? widget.result.snippet : widget.result.title;
    final uri = Uri.https('translate.google.com', '/', {
      'sl': 'auto',
      'tl': Localizations.localeOf(context).languageCode,
      'text': text,
      'op': 'translate',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'التفاصيل', 'Details')),
        actions: [
          IconButton(
            tooltip: tr(context, 'مفضلة', 'Favorite'),
            icon: Icon(_favorite ? Icons.star : Icons.star_border, color: _favorite ? Colors.amber : null),
            onPressed: _toggleFavorite,
          ),
          IconButton(icon: const Icon(Icons.share), tooltip: tr(context, 'مشاركة', 'Share'), onPressed: _share),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(r.title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Chip(label: Text(typeLabel(r.sourceType))),
            RankBadge(level: r.rankLevel),
            Chip(label: Text(r.source)),
          ]),
          const SizedBox(height: 6),
          Text(
            '${tr(context, 'التاريخ', 'Published')}: ${formatDateTime(r.publishedAt)}'
            '  ·  ${tr(context, 'الكاتب', 'Author')}: ${r.author.isEmpty ? '—' : r.author}',
            style: theme.textTheme.bodySmall,
          ),
          SectionCard(
            title: tr(context, '1. المحتوى الأصلي (Original)', '1. Original content'),
            child: r.content.isEmpty
                ? Text(tr(context, 'لا يوجد نص أصلي متاح من المصدر.', 'No original text provided by the source.'))
                : HighlightedText(text: r.content, terms: r.keywords, style: theme.textTheme.bodyMedium),
          ),
          SectionCard(
            title: tr(context, '2. ملخص استخراجي (AI Summary — مقتطفات حرفية)',
                '2. Extractive summary (verbatim excerpts)'),
            child: Text(r.aiSummary.isEmpty
                ? tr(context, 'Insufficient evidence', 'Insufficient evidence')
                : r.aiSummary),
          ),
          SectionCard(
            title: tr(context, '3. لماذا ظهرت النتيجة', '3. Why matched'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.whyMatched, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in r.keywords) Chip(label: Text(k), visualDensity: VisualDensity.compact),
              ]),
            ]),
          ),
          SectionCard(
            title: tr(context, 'الكيانات المرتبطة', 'Related entities'),
            child: r.entities.isEmpty
                ? Text(tr(context, 'لا توجد كيانات', 'None'))
                : Wrap(spacing: 6, children: [for (final e in r.entities) Chip(label: Text(e))]),
          ),
          SectionCard(
            title: tr(context, 'مصادر أخرى لنفس الحدث', 'Other sources for this event'),
            child: FutureBuilder<List<SearchResult>>(
              future: _related,
              builder: (context, snap) {
                final others = (snap.data ?? const <SearchResult>[])
                    .where((o) => o.id != r.id)
                    .toList();
                if (others.isEmpty) {
                  return Text(tr(context, 'لا توجد مصادر أخرى مجمّعة', 'No other grouped sources'));
                }
                return Column(
                  children: [
                    for (final o in others)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(o.source),
                        subtitle: Text(o.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => launchUrl(Uri.parse(o.url), mode: LaunchMode.externalApplication),
                      ),
                  ],
                );
              },
            ),
          ),
          SectionCard(
            title: tr(context, '4. الدليل المصدري (Source Evidence)', '4. Source evidence'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv('URL', r.url),
              _kv(tr(context, 'المصدر', 'Source'), r.source),
              _kv(tr(context, 'وقت الاكتشاف', 'Discovered'), formatDateTime(r.discoveredAt)),
              _kv(tr(context, 'وقت النشر', 'Published'), formatDateTime(r.publishedAt)),
              _kv(tr(context, 'طريقة الاستخراج', 'Extraction method'), r.searchMethod),
              _kv(tr(context, 'الثقة', 'Confidence'), r.confidenceScore.toStringAsFixed(0)),
              _kv('Requested source', r.requestedSource),
              _kv('Actual source queried', r.actualSource),
              _kv('Connector ID', r.connectorId),
              _kv('Search session', r.searchSessionId),
              _kv('Evidence ID', r.evidenceId),
              _kv(tr(context, 'درجات', 'Scores'),
                  'Relevance ${r.relevanceScore.toStringAsFixed(0)} · Freshness ${r.freshnessScore.toStringAsFixed(0)} · Authority ${r.sourceAuthorityScore.toStringAsFixed(0)} · Confidence ${r.confidenceScore.toStringAsFixed(0)}'),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: _openSource,
              icon: const Icon(Icons.open_in_new),
              label: Text(tr(context, 'فتح المصدر', 'Open source')),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy(r.url),
              icon: const Icon(Icons.link),
              label: Text(tr(context, 'نسخ الرابط', 'Copy link')),
            ),
            OutlinedButton.icon(
              onPressed: () => _copy('${r.title}\n\n${r.content}\n\n${r.url}'),
              icon: const Icon(Icons.copy),
              label: Text(tr(context, 'نسخ النص', 'Copy text')),
            ),
            OutlinedButton.icon(
              onPressed: _translate,
              icon: const Icon(Icons.translate),
              label: Text(tr(context, 'ترجمة (Google Translate)', 'Translate (Google Translate)')),
            ),
          ]),
          const SizedBox(height: 16),
          Text(
            '${AppConfig.appName} v${AppConfig.versionName} (${AppConfig.versionCode})',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText.rich(TextSpan(children: [
          TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: v.isEmpty ? '—' : v),
        ])),
      );
}
