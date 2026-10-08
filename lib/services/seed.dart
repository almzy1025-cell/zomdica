import '../collectors/registry.dart';
import '../database/app_database.dart';
import '../models/models.dart';

/// بذور أولية: المصادر المدمجة + الكلمات المفتاحية الافتراضية + قوائم المراقبة الأربع.
/// هذه إعدادات بحث (وليست نتائج). لا تُدرج أي نتيجة وهمية.
Future<void> seedDefaults(AppDatabase db) async {
  final existing = await db.sources();
  final have = existing.map((s) => s.id).toSet();
  for (final s in builtinSourceSeeds()) {
    if (!have.contains(s.id)) await db.upsertSource(s);
  }

  if ((await db.keywords()).isEmpty) {
    const company = ['Zomedica Corp', 'Zomedica Pharmaceuticals', 'Zomedica Inc', 'ZOM', 'ZOMDF'];
    await db.upsertKeyword(const Keyword(
      id: 'kw_company',
      term: 'Zomedica',
      category: KeywordCategory.company,
      aliases: company,
      group: 'Zomedica',
    ));
    const products = [
      'PulseVet', 'Assisi Loop', 'TRUFORMA', 'TRUVIEW', 'VetGuardian',
      'VETIGEL', 'DentaLoop', 'Calmer Canine', 'Loop Lounge',
    ];
    for (var i = 0; i < products.length; i++) {
      await db.upsertKeyword(Keyword(
        id: 'kw_product_$i',
        term: products[i],
        category: KeywordCategory.product,
        group: 'Products',
      ));
    }
    const content = ['Zomedica montage', 'Zomedica video', 'Zomedica ad', 'Zomedica campaign',
      'Zomedica product launch', 'Zomedica earnings', 'Zomedica partnership',
      'Zomedica patent', 'Zomedica trademark', 'Zomedica acquisition'];
    for (var i = 0; i < content.length; i++) {
      await db.upsertKeyword(Keyword(
        id: 'kw_content_$i',
        term: content[i],
        category: KeywordCategory.custom,
        group: 'Content types',
      ));
    }
  }

  if ((await db.watchlists()).isEmpty) {
    await db.upsertWatchlist('wl_zomedica', 'Zomedica', const ['Zomedica', 'ZOM', 'ZOMDF']);
    await db.upsertWatchlist('wl_competitors', 'Competitors', const []);
    await db.upsertWatchlist('wl_vet_market', 'Veterinary Market', const ['veterinary diagnostics', 'veterinary medicine']);
    await db.upsertWatchlist('wl_legal_ip', 'Legal & IP', const ['Zomedica patent', 'Zomedica trademark']);
  }
}
