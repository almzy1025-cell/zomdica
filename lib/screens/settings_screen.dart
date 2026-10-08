import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../services/background_service.dart';
import '../services/providers.dart';
import '../widgets/common_widgets.dart';
import 'manage_screens.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(tr(context, 'الإعدادات', 'Settings'), style: theme.textTheme.headlineSmall),
          SectionCard(
            title: tr(context, 'المظهر', 'Appearance'),
            child: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(tr(context, 'النظام', 'System'))),
                ButtonSegment(value: ThemeMode.light, label: Text(tr(context, 'فاتح', 'Light'))),
                ButtonSegment(value: ThemeMode.dark, label: Text(tr(context, 'داكن', 'Dark'))),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => notifier.update(s.copyWith(themeMode: v.first)),
            ),
          ),
          SectionCard(
            title: tr(context, 'اللغة', 'Language'),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ar', label: Text('العربية')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.language},
              onSelectionChanged: (v) => notifier.update(s.copyWith(language: v.first)),
            ),
          ),
          SectionCard(
            title: tr(context, 'حدود البحث (قابلة للتعديل)', 'Search limits (configurable)'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${tr(context, 'أقصى نتائج لكل استعلام', 'Max results per query')}: ${s.maxResultsPerQuery}'),
              Slider(
                value: s.maxResultsPerQuery.toDouble(),
                min: 10,
                max: 100,
                divisions: 9,
                label: '${s.maxResultsPerQuery}',
                onChanged: (v) => notifier.update(s.copyWith(maxResultsPerQuery: v.round())),
              ),
              Text('${tr(context, 'أقصى Connectors متوازية', 'Max concurrent connectors')}: ${s.maxConcurrentConnectors}'),
              Slider(
                value: s.maxConcurrentConnectors.toDouble(),
                min: 4,
                max: 8,
                divisions: 4,
                label: '${s.maxConcurrentConnectors}',
                onChanged: (v) => notifier.update(s.copyWith(maxConcurrentConnectors: v.round())),
              ),
              Text(tr(context,
                  'ثوابت الأمان: مهلة 10 ثوانٍ لكل طلب، 20 طلب/دقيقة لكل مضيف، 2MB حد أقصى للاستجابة، 60 ثانية لكل بحث، صفحة واحدة لكل مصدر.',
                  'Safety constants: 10s timeout per request, 20 req/min per host, 2MB max response, 60s per search, 1 page per source.'),
                  style: theme.textTheme.labelSmall),
            ]),
          ),
          SectionCard(
            title: tr(context, 'المراقبة في الخلفية', 'Background monitoring'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr(context, 'تفعيل الفحص الدوري', 'Enable periodic checks')),
                value: s.backgroundEnabled,
                onChanged: (v) async {
                  await notifier.update(s.copyWith(backgroundEnabled: v));
                  await applyBackgroundSchedule(
                      enabled: v, requestedMinutes: s.backgroundIntervalMinutes);
                },
              ),
              DropdownButtonFormField<int>(
                initialValue: s.backgroundIntervalMinutes,
                decoration: InputDecoration(
                    labelText: tr(context, 'الفترة (دقيقة)', 'Interval (min)'),
                    border: const OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5')),
                  DropdownMenuItem(value: 15, child: Text('15')),
                  DropdownMenuItem(value: 30, child: Text('30')),
                  DropdownMenuItem(value: 60, child: Text('60')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await notifier.update(s.copyWith(backgroundIntervalMinutes: v));
                  if (s.backgroundEnabled) {
                    await applyBackgroundSchedule(enabled: true, requestedMinutes: v);
                  }
                },
              ),
              const SizedBox(height: 6),
              Text(
                tr(context,
                    'الفعلي: ${effectiveBackgroundMinutes(s.backgroundIntervalMinutes)} دقيقة. ${backgroundLimitNote()}',
                    'Effective: ${effectiveBackgroundMinutes(s.backgroundIntervalMinutes)} min. ${backgroundLimitNote()}'),
                style: theme.textTheme.labelSmall,
              ),
            ]),
          ),
          SectionCard(
            title: tr(context, 'إدارة', 'Management'),
            child: Column(children: [
              _nav(context, Icons.hub_outlined, tr(context, 'إدارة المصادر', 'Sources Manager'), const SourcesScreen()),
              _nav(context, Icons.monitor_heart_outlined, tr(context, 'حالة المصادر + مصفوفة القدرات', 'Source Health + Capability Matrix'), const SourceHealthScreen()),
              _nav(context, Icons.label_outline, tr(context, 'الكلمات المفتاحية', 'Keywords Manager'), const KeywordsScreen()),
              _nav(context, Icons.visibility_outlined, tr(context, 'قوائم المراقبة', 'Watchlists'), const WatchlistsScreen()),
              _nav(context, Icons.history, tr(context, 'سجل البحث', 'Search history'), const SearchHistoryScreen()),
              _nav(context, Icons.receipt_long, tr(context, 'سجل الجلسات', 'Search Session Log'), const SearchLogScreen()),
              _nav(context, Icons.key_outlined, tr(context, 'مفاتيح API (اختياري)', 'API Keys (optional)'), const ApiKeysScreen()),
            ]),
          ),
          SectionCard(
            title: tr(context, 'النسخ الاحتياطي', 'Backup'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context,
                  'تصدير قاعدة البيانات (ملف SQLite) عبر Share Sheet. الاستعادة غير مدعومة بعد (انظر Known Limitations).',
                  'Export the SQLite database via the Share sheet. Restore is not supported yet (see Known Limitations).')),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.backup_outlined),
                label: Text(tr(context, 'تصدير نسخة احتياطية', 'Export backup')),
                onPressed: () async {
                  final path = p.join(await getDatabasesPath(), 'zomedica_radar.db');
                  await Share.shareXFiles([XFile(path)], subject: 'Zomedica Radar backup');
                },
              ),
            ]),
          ),
          SectionCard(
            title: tr(context, 'حول التطبيق', 'About'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(AppConfig.appName, style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('versionName: ${AppConfig.versionName}'),
              const Text('versionCode: ${AppConfig.versionCode}'),
              const Text('SQLite schema: v${AppConfig.schemaVersion}'),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutLimitationsScreen())),
                child: Text(tr(context, 'Known Limitations', 'Known Limitations')),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _nav(BuildContext context, IconData icon, String label, Widget page) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      );
}

class AboutLimitationsScreen extends StatelessWidget {
  const AboutLimitationsScreen({super.key});

  static const _items = <String>[
    'لم يُبنَ APK محلياً: البناء يتم عبر GitHub Actions (لا يوجد Flutter SDK في بيئة التطوير).',
    'Google Patents: NOT_SUPPORTED — لا API رسمي عام، والكشط غير مُنفّذ.',
    'WIPO Global Brand Database: NOT_SUPPORTED — لا API عام مُتحقَّق منه.',
    'Bing News: NOT_SUPPORTED — أوقفت Microsoft واجهات Bing Search في 2025.',
    'DuckDuckGo News: NOT_SUPPORTED — لا API رسمي، وكشط محركات البحث غير مُنفّذ.',
    'VetSurgeon: NOT_SUPPORTED — لا نقطة بحث عامة مُتحقَّق منها؛ أضفه كمصدر Search URL مخصص.',
    'X (Twitter): API_REQUIRED — البحث يتطلب واجهة مدفوعة.',
    'Instagram: BLOCKED — يمنع البحث المجهول والكشط.',
    'Facebook / LinkedIn / VIN Forum: LOGIN_REQUIRED.',
    'USPTO Trademarks: LOGIN_REQUIRED — بحث العلامات الرسمي يتطلب تسجيل دخول/API.',
    'EUIPO Trademarks: API_REQUIRED — يتطلب بيانات اعتماد API مسجلة.',
    'YouTube و USPTO Patents: يتطلبان مفتاح API (اختياري من الإعدادات).',
    'USPTO PatentSearch: تكامل مبني على الوثائق العامة، ويحتاج تحققاً مباشراً مع المفتاح على الجهاز.',
    'Reddit / GDELT: قد يرفضان الطلبات المجهولة أو يفرضان حد معدل (تظهر الحالة الفعلية).',
    'الترجمة: زر يفتح Google Translate، لا توجد ترجمة داخلية.',
    'ملخص AI: استخراجي فقط (جمل حرفية من المصدر)، لا توليد نصوص.',
    'XPath و pagination متقدم غير مدعومين؛ الصفحات تُدار بالمتغير {page}.',
    'الكشف التلقائي للكيانات: مُطبَّق على أسماء المخترعين في نتائج البراءات فقط.',
    'الإشعارات: صوت مخصص غير مُضمَّن؛ تُستخدم قناة High بأهمية قصوى.',
    'WorkManager: الحد الأدنى 15 دقيقة على Android، وقد تتأخر المهام حسب قيود البطارية.',
    'الاستعادة من النسخة الاحتياطية غير مدعومة بعد.',
    'Statistics / Widget / Voice Search / Archive Monitoring (Wayback): غير مُنفّذة في v1.0.0.',
    'Stack Exchange, Lemmy, Bluesky, Mastodon, Quora, Medium, Substack, Dev.to, TikTok, Threads, Telegram: مخطط لها كمصادر مستقبلية (غير مُنفّذة كـ Connectors).',
    'Crunchbase / PitchBook / Glassdoor / Indeed / Wikipedia / Wikidata / Archive.org: مخطط لها (اختيارية).',
    'المصادر الإخبارية الكبرى (Reuters, Bloomberg, AP, ...) تُضاف عبر RSS مخصص إن توفّر مصدر RSS رسمي لها.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Known Limitations')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [for (final i in _items) ListTile(leading: const Icon(Icons.info_outline), title: Text(i))],
      ),
    );
  }
}
