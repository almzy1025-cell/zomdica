import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collectors/registry.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import '../services/providers.dart';
import '../services/search_orchestrator.dart';
import '../services/secure_store.dart';
import '../widgets/common_widgets.dart';
import '../widgets/result_card.dart';
import 'detail_screen.dart';
import 'home_screen.dart';

// =====================================================================
// Sources Manager
// =====================================================================

class SourcesScreen extends ConsumerWidget {
  const SourcesScreen({super.key});

  /// تبديل الأولوية بين مصدرين (إعادة ترتيب).
  Future<void> _swap(WidgetRef ref, SourceConfig a, SourceConfig b) async {
    final db = ref.read(databaseProvider);
    await db.upsertSource(a.copyWith(priority: b.priority));
    await db.upsertSource(b.copyWith(priority: a.priority));
    ref.invalidate(sourcesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'إدارة المصادر', 'Sources Manager'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'إضافة مصدر', 'Add source')),
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddSourceScreen()));
          ref.invalidate(sourcesProvider);
        },
      ),
      body: sources.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => const EmptyState(icon: Icons.error_outline, message: 'DB error'),
        data: (list) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final s = list[i];
            final db = ref.read(databaseProvider);
            return Card(
              child: ListTile(
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${typeLabel(s.type)} · ${s.method.name} · ${s.connectorId.isEmpty ? "custom" : s.connectorId}\n'
                  '${tr(context, "الأولوية", "Priority")}: ${s.priority} · '
                  '${tr(context, "الفحص", "Poll")}: ${s.pollingMinutes}m · ${s.url}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr(context, 'اختبار', 'Test'),
                    icon: const Icon(Icons.play_circle_outline),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final noConnector = tr(context, 'لا يوجد Connector', 'No connector');
                      messenger.showSnackBar(SnackBar(content: Text(
                          tr(context, 'جارٍ الاختبار...', 'Testing...'))));
                      final h = await testConnector(s);
                      ref.invalidate(healthRowsProvider);
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(SnackBar(content: Text(h == null
                          ? noConnector
                          : '${s.name}: ${statusLabel(h.status)} · ${h.resultCount} ${h.reason}')));
                    },
                  ),
                  IconButton(
                    tooltip: tr(context, 'أعلى', 'Up'),
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: i == 0 ? null : () => _swap(ref, list[i - 1], s),
                  ),
                  IconButton(
                    tooltip: tr(context, 'أسفل', 'Down'),
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: i == list.length - 1 ? null : () => _swap(ref, s, list[i + 1]),
                  ),
                  if (!s.isBuiltin)
                    IconButton(
                      tooltip: tr(context, 'حذف', 'Delete'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await db.deleteSource(s.id);
                        ref.invalidate(sourcesProvider);
                      },
                    ),
                  Switch(
                    value: s.enabled,
                    onChanged: (v) async {
                      await db.upsertSource(s.copyWith(enabled: v));
                      ref.invalidate(sourcesProvider);
                    },
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class AddSourceScreen extends ConsumerStatefulWidget {
  const AddSourceScreen({super.key});

  @override
  ConsumerState<AddSourceScreen> createState() => _AddSourceScreenState();
}

class _AddSourceScreenState extends ConsumerState<AddSourceScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _sel = {
    for (final k in const ['item', 'title', 'link', 'content', 'date', 'author']) k: TextEditingController(),
  };
  SourceType _type = SourceType.news;
  SourceMethod _method = SourceMethod.rss;
  int _poll = 60;
  int _priority = 50;
  bool _enabled = true;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    for (final c in _sel.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _validateUrl(String? v) {
    final u = Uri.tryParse((v ?? '').trim());
    if (u == null || (u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) {
      return tr(context, 'أدخل رابط https صحيح', 'Enter a valid https URL');
    }
    if ((_method == SourceMethod.searchUrl || _method == SourceMethod.api) &&
        !v!.contains('{query}')) {
      return tr(context, 'يجب أن يحتوي الرابط على {query}', 'URL must contain {query}');
    }
    return null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final selectors = <String, String>{
      for (final e in _sel.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    final cfg = SourceConfig(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      type: _type,
      method: _method,
      url: _url.text.trim(),
      connectorId: '',
      enabled: _enabled,
      priority: _priority,
      pollingMinutes: _poll,
      selectors: selectors,
    );
    await ref.read(databaseProvider).upsertSource(cfg);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'إضافة مصدر', 'Add source'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: tr(context, 'الاسم', 'Name'), border: const OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? tr(context, 'مطلوب', 'Required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'URL', hintText: 'https://example.com/feed.xml',
                border: OutlineInputBorder()),
            validator: _validateUrl,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SourceMethod>(
            initialValue: _method,
            decoration: InputDecoration(labelText: tr(context, 'طريقة الجلب', 'Acquisition method'),
                border: const OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: SourceMethod.rss, child: Text('RSS / Atom')),
              DropdownMenuItem(value: SourceMethod.sitemap, child: Text('Sitemap (XML)')),
              DropdownMenuItem(value: SourceMethod.searchUrl, child: Text('Search URL ({query})')),
              DropdownMenuItem(value: SourceMethod.webPage, child: Text('Web Page')),
              DropdownMenuItem(value: SourceMethod.api, child: Text('JSON API ({query})')),
            ],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<SourceType>(
            initialValue: _type,
            decoration: InputDecoration(labelText: tr(context, 'النوع', 'Type'), border: const OutlineInputBorder()),
            items: [for (final t in SourceType.values) DropdownMenuItem(value: t, child: Text(typeLabel(t)))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _poll,
            decoration: InputDecoration(labelText: tr(context, 'فترة الفحص (دقيقة)', 'Polling interval (min)'),
                border: const OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 5, child: Text('5')),
              DropdownMenuItem(value: 15, child: Text('15')),
              DropdownMenuItem(value: 30, child: Text('30')),
              DropdownMenuItem(value: 60, child: Text('60')),
            ],
            onChanged: (v) => setState(() => _poll = v ?? _poll),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('${tr(context, 'الأولوية', 'Priority')}: $_priority')),
            Slider(
              value: _priority.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '$_priority',
              onChanged: (v) => setState(() => _priority = v.round()),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(context, 'مفعّل', 'Enabled')),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          ExpansionTile(
            title: Text(tr(context, 'محدِّدات CSS متقدمة (اختياري)', 'Advanced CSS selectors (optional)')),
            subtitle: Text(tr(context, 'تُستخدم مع Web Page / Search URL', 'Used with Web Page / Search URL')),
            children: [
              for (final e in _sel.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: e.value,
                    decoration: InputDecoration(
                      labelText: '${e.key} selector',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              Text(tr(context,
                      'XPath غير مدعوم حالياً (انظر Known Limitations في README).',
                      'XPath is not supported yet (see Known Limitations in README).'),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(tr(context, 'حفظ', 'Save')),
          ),
        ]),
      ),
    );
  }
}

/// Source Health + Capability Matrix.
class SourceHealthScreen extends ConsumerWidget {
  const SourceHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <SourceConfig>[];
    final rows = ref.watch(healthRowsProvider).valueOrNull ?? const [];
    final byId = {for (final r in rows) r['connector_id'] as String: r};
    final live = ref.watch(searchProvider).health;
    final cs = Theme.of(context).colorScheme;

    String yn(bool v) => v ? '✔' : '—';

    final dataRows = <DataRow>[];
    for (final cfg in sources) {
      final c = connectorFor(cfg);
      final cap = c?.capability ?? const Capability(currentlyAvailable: false);
      final row = byId[c?.id ?? cfg.connectorId];
      final liveH = live[c?.id ?? cfg.connectorId];
      final status = liveH?.status ??
          (row == null ? null : statusFromName(row['status'] as String?));
      final count = liveH?.resultCount ?? (row?['last_result_count'] as int?);
      final reason = liveH?.reason ?? (row?['reason'] as String? ?? '');
      final tested = liveH?.lastTested ??
          (row?['last_tested'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row!['last_tested'] as int));
      dataRows.add(DataRow(cells: [
        DataCell(Text(cfg.name)),
        DataCell(status == null ? const Text('NOT TESTED') : StatusChip(status: status)),
        DataCell(Text(count?.toString() ?? '—')),
        DataCell(Text(cap.free ? tr(context, 'مجاني', 'Free') : tr(context, 'مدفوع', 'Paid'))),
        DataCell(Text(yn(cap.apiRequired))),
        DataCell(Text(yn(cap.loginRequired))),
        DataCell(Text(yn(cap.rssSupported))),
        DataCell(Text(yn(cap.scrapingSupported))),
        DataCell(Text(yn(cap.currentlyAvailable), style: TextStyle(color: cap.currentlyAvailable ? Colors.green : cs.error))),
        DataCell(Text(formatDateTime(tested))),
        DataCell(SizedBox(width: 260, child: Text(reason.isEmpty ? cap.unavailableReason : reason,
            maxLines: 3, overflow: TextOverflow.ellipsis))),
      ]));
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'حالة المصادر', 'Source Health'))),
      body: sources.isEmpty
          ? const EmptyState(icon: Icons.hub_outlined, message: 'No sources')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  columns: const [
                    DataColumn(label: Text('Source')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Results')),
                    DataColumn(label: Text('Free/Paid')),
                    DataColumn(label: Text('API')),
                    DataColumn(label: Text('Login')),
                    DataColumn(label: Text('RSS')),
                    DataColumn(label: Text('Scrape')),
                    DataColumn(label: Text('Available')),
                    DataColumn(label: Text('Last tested')),
                    DataColumn(label: Text('Reason')),
                  ],
                  rows: dataRows,
                ),
              ),
            ),
    );
  }
}

// =====================================================================
// Keywords Manager + New Entity Discovery
// =====================================================================

class KeywordsScreen extends ConsumerWidget {
  const KeywordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kws = ref.watch(keywordsProvider).valueOrNull ?? const <Keyword>[];
    final results = ref.watch(resultsProvider).valueOrNull ?? const <SearchResult>[];
    final db = ref.read(databaseProvider);
    final prefs = ref.read(prefsProvider);
    final dismissed = (prefs.getStringList('dismissed_entities') ?? const <String>[]).toSet();

    final discovered = _discoverEntities(results, kws, dismissed);

    final groups = <String, List<Keyword>>{};
    for (final k in kws) {
      groups.putIfAbsent(k.group, () => []).add(k);
    }

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'الكلمات المفتاحية', 'Keywords'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'إضافة', 'Add')),
        onPressed: () => _addKeyword(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
        children: [
          if (discovered.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'New Entity Discovered', 'New Entity Discovered'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(tr(context, 'اكتُشفت من أسماء المخترعين في نتائج البراءات. لا تُضاف تلقائياً.',
                      'Found from inventor names in patent results. Never added automatically.'),
                      style: Theme.of(context).textTheme.labelSmall),
                  for (final e in discovered)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name),
                      subtitle: Text('${tr(context, 'السبب', 'Reason')}: ${e.reason}\n'
                          '${tr(context, 'المصادر', 'Sources')}: ${e.sources.join(', ')} · '
                          '${tr(context, 'الثقة', 'Confidence')}: ${e.confidence}'),
                      isThreeLine: true,
                      trailing: Wrap(children: [
                        IconButton(
                          tooltip: tr(context, 'إضافة لقائمة المراقبة', 'Add to watchlist'),
                          icon: const Icon(Icons.person_add_alt_1),
                          onPressed: () async {
                            await db.upsertKeyword(Keyword(
                              id: 'kw_inv_${DateTime.now().millisecondsSinceEpoch}',
                              term: e.name,
                              category: KeywordCategory.inventor,
                              group: 'Inventors',
                            ));
                            ref.invalidate(keywordsProvider);
                          },
                        ),
                        IconButton(
                          tooltip: tr(context, 'تجاهل', 'Dismiss'),
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await prefs.setStringList('dismissed_entities', [...dismissed, e.name]);
                            ref.invalidate(resultsProvider);
                          },
                        ),
                      ]),
                    ),
                ]),
              ),
            ),
          for (final g in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: Text(g.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ),
            for (final k in g.value)
              Card(
                child: ListTile(
                  title: Text(k.term),
                  subtitle: Text('${k.category.name}${k.aliases.isEmpty ? '' : ' · ${k.aliases.join(', ')}'}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: k.enabled,
                      onChanged: (v) async {
                        await db.upsertKeyword(k.copyWith(enabled: v));
                        ref.invalidate(keywordsProvider);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await db.deleteKeyword(k.id);
                        ref.invalidate(keywordsProvider);
                      },
                    ),
                  ]),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<_Discovered> _discoverEntities(List<SearchResult> results, List<Keyword> kws, Set<String> dismissed) {
    final known = kws.map((k) => k.term.toLowerCase()).toSet();
    final counts = <String, Set<String>>{};
    final reasons = <String, String>{};
    for (final r in results) {
      if (r.sourceType != SourceType.patent || r.author.isEmpty) continue;
      for (final raw in r.author.split(',')) {
        final name = raw.trim();
        if (name.length < 4 || !name.contains(' ')) continue;
        if (known.contains(name.toLowerCase()) || dismissed.contains(name)) continue;
        counts.putIfAbsent(name, () => <String>{}).add(r.source);
        reasons[name] = 'Inventor on patent: ${r.title}';
      }
    }
    final list = counts.entries
        .map((e) => _Discovered(
              e.key,
              reasons[e.key] ?? '',
              e.value.toList(),
              (40 + 15 * e.value.length).clamp(0, 95).toInt(),
            ))
        .toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    return list.take(10).toList();
  }

  Future<void> _addKeyword(BuildContext context, WidgetRef ref) async {
    final term = TextEditingController();
    final aliases = TextEditingController();
    var category = KeywordCategory.custom;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr(ctx, 'كلمة مفتاحية جديدة', 'New keyword')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: term, decoration: InputDecoration(labelText: tr(ctx, 'المصطلح', 'Term'))),
            TextField(controller: aliases, decoration: InputDecoration(
                labelText: tr(ctx, 'مرادفات (مفصولة بفاصلة)', 'Aliases (comma separated)'))),
            DropdownButton<KeywordCategory>(
              value: category,
              isExpanded: true,
              items: [for (final c in KeywordCategory.values) DropdownMenuItem(value: c, child: Text(c.name))],
              onChanged: (v) => setS(() => category = v ?? category),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'حفظ', 'Save'))),
          ],
        ),
      ),
    );
    if (ok == true && term.text.trim().isNotEmpty) {
      await ref.read(databaseProvider).upsertKeyword(Keyword(
            id: 'kw_${DateTime.now().millisecondsSinceEpoch}',
            term: term.text.trim(),
            category: category,
            aliases: aliases.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
            group: category == KeywordCategory.custom ? 'Custom' : category.name,
          ));
      ref.invalidate(keywordsProvider);
    }
    term.dispose();
    aliases.dispose();
  }
}

class _Discovered {
  final String name;
  final String reason;
  final List<String> sources;
  final int confidence;
  const _Discovered(this.name, this.reason, this.sources, this.confidence);
}

// =====================================================================
// Watchlists
// =====================================================================

class WatchlistsScreen extends ConsumerWidget {
  const WatchlistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(watchlistsProvider).valueOrNull ?? const [];
    final db = ref.read(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'قوائم المراقبة', 'Watchlists'))),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(tr(context, 'قائمة جديدة', 'New list')),
        onPressed: () async {
          final name = TextEditingController();
          final terms = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr(ctx, 'قائمة مراقبة جديدة', 'New watchlist')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: InputDecoration(labelText: tr(ctx, 'الاسم', 'Name'))),
                TextField(controller: terms, decoration: InputDecoration(
                    labelText: tr(ctx, 'المصطلحات (مفصولة بفاصلة)', 'Terms (comma separated)'))),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'إلغاء', 'Cancel'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'حفظ', 'Save'))),
              ],
            ),
          );
          if (ok == true && name.text.trim().isNotEmpty) {
            await db.upsertWatchlist(
              'wl_${DateTime.now().millisecondsSinceEpoch}',
              name.text.trim(),
              terms.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
            );
            ref.invalidate(watchlistsProvider);
          }
          name.dispose();
          terms.dispose();
        },
      ),
      body: lists.isEmpty
          ? EmptyState(icon: Icons.visibility_outlined, message: tr(context, 'لا توجد قوائم', 'No watchlists'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 90),
              children: [
                for (final w in lists)
                  Card(
                    child: ListTile(
                      title: Text(w['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(((w['terms'] as String?) ?? '').split('\n').where((s) => s.isNotEmpty).join(' · ')
                          .isEmpty
                          ? tr(context, '(بدون مصطلحات — يستخدم كلمات Zomedica)', '(no terms — uses Zomedica keywords)')
                          : ((w['terms'] as String?) ?? '').split('\n').join(' · ')),
                      onTap: () {
                        final terms = ((w['terms'] as String?) ?? '').split('\n').where((s) => s.isNotEmpty).toList();
                        final query = terms.isEmpty ? 'Zomedica' : terms.first;
                        ref.read(searchProvider.notifier).start(query);
                        ref.read(shellIndexProvider.notifier).state = 1;
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await db.deleteWatchlist(w['id'] as String);
                          ref.invalidate(watchlistsProvider);
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// =====================================================================
// Favorites / History / Search Log
// =====================================================================

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider).valueOrNull ?? const <SearchResult>[];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'المفضلة', 'Favorites'))),
      body: favs.isEmpty
          ? EmptyState(icon: Icons.star_outline, message: tr(context, 'لا توجد عناصر مفضلة بعد', 'No favorites yet'))
          : ListView.builder(
              itemCount: favs.length,
              itemBuilder: (_, i) => ResultCard(
                result: favs[i],
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DetailScreen(result: favs[i]))),
              ),
            ),
    );
  }
}

class SearchHistoryScreen extends ConsumerWidget {
  const SearchHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hist = ref.watch(historyProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'سجل البحث (آخر 20)', 'Search history (last 20)'))),
      body: hist.isEmpty
          ? EmptyState(icon: Icons.history, message: tr(context, 'لا يوجد سجل', 'No history'))
          : ListView(children: [
              for (final h in hist)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(h['query'] as String),
                  subtitle: Text('${formatDateTime(DateTime.fromMillisecondsSinceEpoch(h['created_at'] as int))}'
                      ' · ${h['result_count']} · ${h['status']}'),
                  trailing: const Icon(Icons.replay),
                  onTap: () {
                    ref.read(searchProvider.notifier).start(h['query'] as String);
                    ref.read(shellIndexProvider.notifier).state = 1;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
            ]),
    );
  }
}

class SearchLogScreen extends ConsumerWidget {
  const SearchLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider).valueOrNull ?? const <SearchSession>[];
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'سجل الجلسات', 'Search Session Log'))),
      body: sessions.isEmpty
          ? EmptyState(icon: Icons.receipt_long, message: tr(context, 'لا توجد جلسات بحث', 'No search sessions'))
          : ListView(children: [
              for (final s in sessions)
                ExpansionTile(
                  title: Text(s.query),
                  subtitle: Text('${formatDateTime(s.startedAt)} · ${s.resultsFound} results · '
                      '${s.cancelled ? "CANCELLED" : (s.errors.isEmpty ? "DONE" : "PARTIAL")}'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Search ID: ${s.id}'),
                        Text('Original query: ${s.query}'),
                        Text('Expanded queries: ${s.expandedQueries.join(' | ')}'),
                        Text('Connectors used: ${s.connectorsUsed.join(', ')}'),
                        Text('Requests: ${s.requests} · OK: ${s.successfulRequests} · Failed: ${s.failedRequests}'),
                        Text('Results found: ${s.resultsFound} · Duplicates removed: ${s.duplicatesRemoved}'),
                        Text('Duration: ${s.durationMs} ms'),
                        Text('Cancellation state: ${s.cancelled ? "cancelled by user / limit" : "not cancelled"}'),
                        Text('Errors: ${s.errors.isEmpty ? "none" : s.errors.join(' | ')}'),
                      ]),
                    ),
                  ],
                ),
            ]),
    );
  }
}

// =====================================================================
// API Keys
// =====================================================================

class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key});

  static const _usedBy = {
    ApiKeyStore.youtube: 'YouTube connector',
    ApiKeyStore.uspto: 'USPTO Patents connector',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presence = ref.watch(apiKeyPresenceProvider).valueOrNull ?? const <String, bool>{};
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'مفاتيح API (اختيارية)', 'API Keys (optional)'))),
      body: ListView(padding: const EdgeInsets.all(8), children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(tr(context,
              'التطبيق يعمل بالمصادر المجانية دون مفاتيح. المفاتيح مشفّرة عبر Android Keystore ولا تُعرض كاملة.',
              'The app works with free sources without keys. Keys are encrypted with Android Keystore and never shown in full.')),
        ),
        for (final e in ApiKeyStore.providers.entries)
          Card(
            child: ListTile(
              title: Text(e.value),
              subtitle: Text(
                '${presence[e.key] == true ? tr(context, 'مضبوط', 'Set') : tr(context, 'غير مضبوط', 'Not set')}'
                ' · ${_usedBy[e.key] ?? tr(context, 'لا يوجد Connector يستخدمه بعد (مخزَّن فقط)', 'No connector uses it yet (stored only)')}',
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editKey(context, ref, e.key, e.value),
                ),
                if (presence[e.key] == true)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await ref.read(secureStoreProvider).delete(e.key);
                      await ref.read(databaseProvider).deleteApiKeyHint(e.key);
                      ref.invalidate(apiKeyPresenceProvider);
                    },
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Future<void> _editKey(BuildContext context, WidgetRef ref, String provider, String label) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: tr(ctx, 'المفتاح', 'Key')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(ctx, 'حفظ', 'Save'))),
        ],
      ),
    );
    final value = ctrl.text.trim();
    ctrl.dispose();
    if (ok == true && value.isNotEmpty) {
      await ref.read(secureStoreProvider).write(provider, value);
      await ref.read(databaseProvider).upsertApiKeyHint(provider, ApiKeyStore.hint(value));
      ref.invalidate(apiKeyPresenceProvider);
    }
  }
}

// =====================================================================
// Connector test (زر "اختبار" في Sources Manager)
// =====================================================================

/// يشغّل Connector واحداً بالاستعلام "Zomedica" ويُرجع حالته الفعلية.
Future<SourceHealth?> testConnector(SourceConfig cfg, {String query = 'Zomedica'}) async {
  final c = connectorFor(cfg);
  if (c == null) return null;
  final orch = SearchOrchestrator(
    entries: [ConnectorEntry(c, cfg)],
    limits: AppConfig.defaultLimits.copyWith(maxResultsPerQuery: 5),
  );
  final completer = Completer<SourceHealth?>();
  orch.search(query: query, expandedQueries: [query], requestedSource: 'Test: ${cfg.name}').listen(
    (ev) {
      if (ev is ConnectorFinished && ev.health.connectorId == c.id) {
        completer.complete(ev.health);
      }
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete(null);
    },
  );
  return completer.future.timeout(const Duration(seconds: 60), onTimeout: () => null);
}
