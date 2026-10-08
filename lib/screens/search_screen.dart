import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../filters/pipeline.dart';
import '../models/models.dart';
import '../services/providers.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';
import '../widgets/result_card.dart';
import 'detail_screen.dart';

enum _TimeFilter { hour, day, week, all, custom }

const _tabKeys = ['all', 'news', 'patents', 'trademarks', 'inventors', 'videos', 'favorites'];

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController(text: 'Zomedica');
  late final TabController _tabs;
  Timer? _ticker;
  _TimeFilter _time = _TimeFilter.all;
  DateTimeRange? _range;
  bool _highOnly = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabKeys.length, vsync: this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ref.read(searchProvider).running) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _tabLabel(BuildContext c, String key) {
    switch (key) {
      case 'all':
        return tr(c, 'الكل', 'All');
      case 'news':
        return tr(c, 'الأخبار', 'News');
      case 'patents':
        return tr(c, 'براءات الاختراع', 'Patents');
      case 'trademarks':
        return tr(c, 'العلامات', 'Trademarks');
      case 'inventors':
        return tr(c, 'المخترعون', 'Inventors');
      case 'videos':
        return tr(c, 'الفيديوهات', 'Videos');
      default:
        return tr(c, 'المفضلة', 'Favorites');
    }
  }

  bool _matchesTab(String key, SearchResult r) {
    switch (key) {
      case 'news':
        return r.sourceType == SourceType.news || r.sourceType == SourceType.pressRelease;
      case 'patents':
        return r.sourceType == SourceType.patent;
      case 'trademarks':
        return r.sourceType == SourceType.trademark;
      case 'inventors':
        return r.sourceType == SourceType.inventor ||
            (r.sourceType == SourceType.patent && r.author.isNotEmpty);
      case 'videos':
        return r.sourceType == SourceType.video;
      default:
        return true;
    }
  }

  bool _passesFilters(SearchResult r) {
    final ts = r.publishedAt ?? r.discoveredAt;
    final age = DateTime.now().difference(ts);
    switch (_time) {
      case _TimeFilter.hour:
        if (age > const Duration(hours: 1)) return false;
      case _TimeFilter.day:
        if (age > const Duration(days: 1)) return false;
      case _TimeFilter.week:
        if (age > const Duration(days: 7)) return false;
      case _TimeFilter.custom:
        final range = _range;
        if (range != null &&
            (ts.isBefore(range.start) || ts.isAfter(range.end.add(const Duration(days: 1))))) {
          return false;
        }
      case _TimeFilter.all:
        break;
    }
    if (_highOnly && r.rankLevel.index > RankLevel.high.index) return false;
    return true;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 2)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _range = picked;
        _time = _TimeFilter.custom;
      });
    }
  }

  void _openDetail(SearchResult r) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(result: r)));
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final favorites = ref.watch(favoritesProvider).valueOrNull ?? const <SearchResult>[];
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final ranked = ResultPipeline.rank(st.results);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  enabled: !st.running,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => notifier.start(_controller.text),
                  decoration: InputDecoration(
                    hintText: tr(context, 'اكتب الاستعلام (مثال: Zomedica)', 'Query (e.g. Zomedica)'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (st.running)
                FilledButton.tonalIcon(
                  onPressed: notifier.stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(tr(context, 'إيقاف', 'Stop')),
                )
              else
                FilledButton.icon(
                  onPressed: () => notifier.start(_controller.text),
                  icon: const Icon(Icons.radar),
                  label: Text(tr(context, 'بحث الآن', 'Search now')),
                ),
            ]),
          ),
          if (st.running) const LinearProgressIndicator(minHeight: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${tr(context, 'النتائج', 'Results')}: ${st.results.length}'
                  '${st.newCount > 0 ? '  (+${st.newCount} ${tr(context, 'جديد', 'new')})' : ''}',
                  style: theme.textTheme.labelLarge,
                ),
                Text('${tr(context, 'المدة', 'Duration')}: ${_fmt(st.elapsed)}',
                    style: theme.textTheme.labelMedium),
                Text('${tr(context, 'مكرر/مجمّع', 'Dup/grouped')}: ${st.duplicates}',
                    style: theme.textTheme.labelMedium),
                if (st.running && st.activeConnectors.isNotEmpty)
                  Text(
                    '${tr(context, 'جارٍ', 'Active')}: ${st.activeConnectors.values.join(', ')}',
                    style: theme.textTheme.labelMedium?.copyWith(color: cs.primary),
                  ),
                if (!st.running && st.query.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => notifier.start(st.query),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(tr(context, 'تحديث', 'Refresh')),
                  ),
              ],
            ),
          ),
          if (st.expanded.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${tr(context, 'الاستعلامات الموسّعة', 'Expanded queries')}: ${st.expanded.join(' · ')}',
                style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
            ),
          if (st.health.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: st.health.values
                    .map((h) => Padding(
                          padding: const EdgeInsets.only(right: 8, top: 6, bottom: 6),
                          child: Tooltip(
                            message: h.reason,
                            child: Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text('${h.name} · ${h.resultCount}'),
                              avatar: CircleAvatar(
                                radius: 5,
                                backgroundColor: statusColor(h.status, cs),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  for (final t in const [_TimeFilter.hour, _TimeFilter.day, _TimeFilter.week, _TimeFilter.all])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(_timeLabel(context, t)),
                        selected: _time == t,
                        onSelected: (_) => setState(() => _time = t),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(_range == null
                          ? tr(context, 'مخصص', 'Custom')
                          : '${formatDateTime(_range!.start).substring(0, 10)} → ${formatDateTime(_range!.end).substring(0, 10)}'),
                      selected: _time == _TimeFilter.custom,
                      onSelected: (_) => _pickCustomRange(),
                    ),
                  ),
                  FilterChip(
                    label: Text(tr(context, 'عالية فأعلى', 'HIGH+')),
                    selected: _highOnly,
                    onSelected: (v) => setState(() => _highOnly = v),
                  ),
                ]),
              ),
            ),
          ]),
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final key in _tabKeys)
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_tabLabel(context, key)),
                    const SizedBox(width: 6),
                    _badge(key, ranked, favorites, st.knownBefore, cs),
                  ]),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final key in _tabKeys)
                  _tabList(context, key, ranked, favorites, st),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String key, List<SearchResult> ranked, List<SearchResult> favorites,
      Set<String> known, ColorScheme cs) {
    final n = key == 'favorites'
        ? favorites.length
        : ranked.where((r) => _matchesTab(key, r) && !known.contains(r.canonicalUrl)).length;
    if (n == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: cs.tertiary, borderRadius: BorderRadius.circular(10)),
      child: Text('$n', style: TextStyle(color: cs.onTertiary, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }

  Widget _tabList(BuildContext context, String key, List<SearchResult> ranked,
      List<SearchResult> favorites, SearchState st) {
    final source = key == 'favorites' ? favorites : ranked.where((r) => _matchesTab(key, r));
    final items = source.where(_passesFilters).toList();
    if (items.isEmpty) {
      return EmptyState(
        icon: st.running ? Icons.hourglass_top : Icons.inbox_outlined,
        message: st.running
            ? tr(context, 'جارٍ البحث... ستظهر النتائج هنا فور وصولها.',
                'Searching... results appear here as they arrive.')
            : st.query.isEmpty
                ? tr(context, 'ابدأ بحثاً لعرض النتائج. Insufficient evidence حتى الآن.',
                    'Start a search. Insufficient evidence so far.')
                : tr(context, 'لا توجد نتائج مطابقة (Insufficient evidence).',
                    'No matching results (Insufficient evidence).'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final r = items[i];
        return ResultCard(
          result: r,
          isNew: !st.knownBefore.contains(r.canonicalUrl),
          onTap: () => _openDetail(r),
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: r.url));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr(context, 'تم نسخ الرابط', 'Link copied')),
            ));
          },
        );
      },
    );
  }

  String _timeLabel(BuildContext c, _TimeFilter t) {
    switch (t) {
      case _TimeFilter.hour:
        return tr(c, 'آخر ساعة', 'Last hour');
      case _TimeFilter.day:
        return tr(c, 'آخر يوم', 'Last day');
      case _TimeFilter.week:
        return tr(c, 'آخر أسبوع', 'Last week');
      case _TimeFilter.all:
        return tr(c, 'الكل', 'All time');
      case _TimeFilter.custom:
        return tr(c, 'مخصص', 'Custom');
    }
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }
}

