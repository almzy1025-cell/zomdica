import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../filters/pipeline.dart';
import '../models/models.dart';
import '../services/providers.dart';
import '../widgets/common_widgets.dart';
import '../widgets/result_card.dart';
import 'detail_screen.dart';
import 'manage_screens.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

final shellIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    const pages = [HomeScreen(), SearchScreen(), FavoritesScreen(), SettingsScreen()];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(shellIndexProvider.notifier).state = i,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home),
              label: tr(context, 'الرئيسية', 'Home')),
          NavigationDestination(icon: const Icon(Icons.radar_outlined), selectedIcon: const Icon(Icons.radar),
              label: tr(context, 'بحث', 'Search')),
          NavigationDestination(icon: const Icon(Icons.star_outline), selectedIcon: const Icon(Icons.star),
              label: tr(context, 'المفضلة', 'Favorites')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings),
              label: tr(context, 'الإعدادات', 'Settings')),
        ],
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final results = ref.watch(resultsProvider).valueOrNull ?? const <SearchResult>[];
    final sources = ref.watch(sourcesProvider).valueOrNull ?? const <SourceConfig>[];
    final history = ref.watch(historyProvider).valueOrNull ?? const [];
    final health = ref.watch(healthRowsProvider).valueOrNull ?? const [];
    final search = ref.watch(searchProvider);

    final since = DateTime.now().subtract(const Duration(hours: 24));
    final last24 = results.where((r) => r.discoveredAt.isAfter(since)).toList();
    final events = last24.map((r) => r.eventId.isEmpty ? r.id : r.eventId).toSet().length;
    final activeSources = sources.where((s) => s.enabled).length;
    final top = ResultPipeline.rank(last24).take(5).toList();
    final legal = last24
        .where((r) => r.sourceType == SourceType.patent || r.sourceType == SourceType.trademark)
        .take(5)
        .toList();

    final statusCounts = <ConnectorStatus, int>{};
    for (final h in health) {
      final s = statusFromName(h['status'] as String?);
      statusCounts[s] = (statusCounts[s] ?? 0) + 1;
    }

    final lastSearch = history.isEmpty ? null : history.first;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(resultsProvider);
          ref.invalidate(healthRowsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(children: [
              Expanded(
                child: Text(AppConfig.appName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text('v${AppConfig.versionName}', style: theme.textTheme.labelMedium),
            ]),
            Text(tr(context, 'مراقبة Zomedica — Maximum Available Coverage',
                'Zomedica monitoring — Maximum Available Coverage'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Row(children: [
              _stat(context, tr(context, 'نتائج 24س', 'Results 24h'), '${last24.length}'),
              _stat(context, tr(context, 'أحداث 24س', 'Events 24h'), '$events'),
              _stat(context, tr(context, 'مصادر نشطة', 'Active sources'), '$activeSources'),
            ]),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: search.running
                  ? null
                  : () {
                      ref.read(searchProvider.notifier).start('Zomedica');
                      ref.read(shellIndexProvider.notifier).state = 1;
                    },
              icon: const Icon(Icons.radar),
              label: Text(tr(context, 'بحث الآن', 'Search now')),
            ),
            const SizedBox(height: 6),
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(tr(context, 'آخر بحث', 'Last search')),
                subtitle: Text(lastSearch == null
                    ? tr(context, 'لا يوجد بعد', 'None yet')
                    : '${lastSearch['query']} · ${formatDateTime(DateTime.fromMillisecondsSinceEpoch(lastSearch['created_at'] as int))} · ${lastSearch['status']}'),
              ),
            ),
            SectionCard(
              title: tr(context, 'حالة الـConnectors', 'Connector status'),
              child: statusCounts.isEmpty
                  ? Text(tr(context, 'لم يُختبر أي مصدر بعد — شغّل بحثاً أولاً.',
                      'No source has been tested yet — run a search first.'))
                  : Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in statusCounts.entries)
                        Chip(label: Text('${statusLabel(e.key)}: ${e.value}')),
                    ]),
            ),
            SectionCard(
              title: tr(context, 'أهم النتائج', 'Top results'),
              child: top.isEmpty
                  ? Text(tr(context, 'Insufficient evidence في آخر 24 ساعة.',
                      'Insufficient evidence in the last 24 hours.'))
                  : Column(children: [
                      for (final r in top)
                        ResultCard(result: r, onTap: () => _open(context, r)),
                    ]),
            ),
            SectionCard(
              title: tr(context, 'الأحداث القانونية (براءات / علامات)', 'Legal events (patents / trademarks)'),
              child: legal.isEmpty
                  ? Text(tr(context, 'لا توجد أحداث قانونية في آخر 24 ساعة.',
                      'No legal events in the last 24 hours.'))
                  : Column(children: [
                      for (final r in legal)
                        ResultCard(result: r, onTap: () => _open(context, r)),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, SearchResult r) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailScreen(result: r)));

  Widget _stat(BuildContext context, String label, String value) => Expanded(
        child: Card(
          margin: const EdgeInsets.all(4),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            ]),
          ),
        ),
      );
}

