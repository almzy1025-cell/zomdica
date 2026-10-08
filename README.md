# Zomedica Radar

**الإصدار:** `versionName = 1.0.0` · `versionCode = 1` (يظهر في الإعدادات ← حول التطبيق)

تطبيق Android (Flutter + Material 3) للمراقبة الاستخباراتية (OSINT) لشركة **Zomedica** (الصحة البيطرية): منتجاتها، تقنياتها، براءاتها، علاماتها التجارية، مخترعوها، مدراؤها، شراكاتها، وظهورها في الأخبار والمنتديات والمنصات العامة.

> **مبدأ التشغيل:** Maximum Available Coverage — التطبيق لا يدّعي تغطية "كل الإنترنت". كل مصدر يعرض حالته الفعلية (SUCCESS / FAILED / BLOCKED / LOGIN_REQUIRED / API_REQUIRED / RATE_LIMITED / NOT_SUPPORTED / DISABLED)، وعدد نتائجه، وسبب أي فشل.

---

## 1. ما الذي يفعله التطبيق

- **بحث متوازٍ وبثّ مباشر (Streaming):** عند الضغط على "بحث الآن" تبدأ المصادر بالتوازي (4–8 حسب الإعداد)، وتظهر كل نتيجة فور وصولها، ويزيد العداد تدريجياً. انتهاء مصدر لا يعني انتهاء البحث.
- **إلغاء فوري:** زر "إيقاف" يلغي الطلبات المعلّقة ويحفظ الجلسة بحالة `CANCELLED`.
- **لا بيانات وهمية:** لا توجد نتائج تجريبية في التطبيق. إن لم يوجد دليل تظهر الرسالة `Insufficient evidence`.
- **تتبّع كامل:** كل نتيجة تحمل: الرابط، المصدر، وقت النشر والاكتشاف، طريقة الاستخراج، الـConnector، الاستعلام المطلوب (`requestedSource`)، المصدر الفعلي المستعلَم منه (`actualSource`)، معرّف الجلسة، ومعرّف الدليل (`evidenceId`).
- **ملخص استخراجي فقط:** "AI Summary" هو جمل حرفية مُستخرجة من النص الأصلي، ولا يُولَّد نص جديد. المصدر الأصلي هو المرجع الدائم.
- **إزالة التكرار والتجميع:** تطابق الرابط القانوني، وهاش المحتوى، وتشابه العناوين (Jaccard ≥ 0.8) لتجميع النسخ المنشورة عبر عدة مواقع في "حدث" واحد.
- **الترتيب:** مستويات `VERY HIGH / HIGH / MEDIUM / LOW` مع سبب (الصلة، الحداثة، سلطة المصدر، الثقة).
- **التبويبات السبعة:** الكل · الأخبار · براءات الاختراع · العلامات التجارية · المخترعون · الفيديوهات · المفضلة. كل تبويب يعرض شارة بعدد النتائج الجديدة.
- **الفلاتر:** آخر ساعة / يوم / أسبوع / الكل / مخصص (نطاق تاريخ)، و"عالية فأعلى".
- **الشاشات:** الرئيسية، البحث، التفاصيل (4 أقسام: Original / AI Summary / Why Matched / Source Evidence)، إدارة المصادر، الكلمات المفتاحية، قوائم المراقبة، المفضلة، سجل البحث، سجل الجلسات، حالة المصادر ومصفوفة القدرات، مفاتيح API، الإعدادات، حول التطبيق.
- **اللغات:** العربية (RTL) والإنجليزية. المظهر: فاتح / داكن / حسب النظام.

---

## 2. طريقة الاستخدام

1. **الرئيسية:** ملخص آخر 24 ساعة، عدد الأحداث، المصادر النشطة، حالة الـConnectors، أهم النتائج، والأحداث القانونية.
2. **بحث:** اكتب الاستعلام (افتراضياً `Zomedica`) واضغط **بحث الآن**. ستظهر الاستعلامات الموسّعة المستخدمة (من الكلمات المفتاحية المفعّلة فقط، بحد أقصى 5).
3. **التفاصيل:** اضغط على أي نتيجة. يمكنك فتح المصدر، مشاركة النتيجة، نسخ الرابط أو النص، إضافتها للمفضلة، أو ترجمتها عبر Google Translate.
4. **نسخ سريع:** اضغط مطولاً على أي نتيجة لنسخ رابطها.

---

## 3. المصادر

### 3.1 إدارة المصادر (الإعدادات ← إدارة المصادر)
- كل مصدر له: الاسم، الرابط، النوع، طريقة الجلب، مفعّل/معطّل، الأولوية، فترة الفحص.
- الأزرار: تفعيل/تعطيل، اختبار (يشغّل Connector واحداً بالاستعلام "Zomedica" ويعرض حالته الفعلية)، إعادة الترتيب (أعلى/أسفل)، حذف (للمصادر المخصّصة فقط).
- **"+ إضافة مصدر"** يدعم خمس طرق جلب:
  - **RSS / Atom** — رابط تغذية.
  - **Sitemap** — ملف `sitemap.xml`، ويُفلتر بالمصطلحات على الرابط/الـslug.
  - **Search URL** — رابط بحث يحتوي `{query}`، ويُستخرج منه روابط نصها يحتوي المصطلح.
  - **Web Page** — صفحة واحدة (العنوان، الوصف، التاريخ)، أو قائمة عناصر بمحدِّد `item`.
  - **JSON API** — رابط يعيد JSON، ويحتوي `{query}`.
- **محدِّدات CSS اختيارية** (`item`, `title`, `link`, `content`, `date`, `author`).
- `{page}` في الرابط يفعّل الترقيم حتى `maxPagesPerSource`.
- **XPath غير مدعوم حالياً.**

### 3.2 الموصلات المدمجة (Built-in)

| الموصل | الطريقة | الحالة في v1.0.0 |
|---|---|---|
| Google News | RSS عام | مُنفّذ |
| GDELT | DOC 2.0 API عام | مُنفّذ |
| Reddit | `search.json` | مُنفّذ — قد يُحجب بدون OAuth (تظهر الحالة الفعلية) |
| Hacker News | Algolia API عام | مُنفّذ |
| PubMed | NCBI E-utilities | مُنفّذ |
| YouTube | YouTube Data API v3 | مُنفّذ — **يتطلب مفتاح** |
| USPTO Patents | PatentSearch API | مُنفّذ — **يتطلب مفتاح** |
| X, Instagram, Facebook, LinkedIn, VIN, VetSurgeon, Google Patents, USPTO Trademarks, EUIPO, WIPO Brand DB, Bing News, DuckDuckGo News | — | حالة فعلية فقط (انظر التصنيف أدناه) |

---

## 4. الكلمات المفتاحية والمراقبة

- **الكلمات المفتاحية** (الإعدادات ← الكلمات المفتاحية): الأنواع `Company, Product, Executive, Inventor, Competitor, Custom`. كل كلمة قابلة للتفعيل/التعطيل، ولها مرادفات، وتُجمَّع في مجموعات.
- **الافتراضي:** Zomedica (مع مرادفات: Zomedica Corp, Zomedica Pharmaceuticals, Zomedica Inc, ZOM, ZOMDF)، والمنتجات: PulseVet, Assisi Loop, TRUFORMA, TRUVIEW, VetGuardian, VETIGEL, DentaLoop, Calmer Canine, Loop Lounge، وأنواع المحتوى (montage, video, ad, campaign, ...).
- **New Entity Discovery:** يُقترح أسماء المخترعين المكتشفة في نتائج البراءات مع المصادر وسبب الاكتشاف ودرجة الثقة. **لا تُضاف تلقائياً** — تضيفها أنت أو تتجاهلها.
- **قوائم المراقبة:** افتراضياً: Zomedica · Competitors · Veterinary Market · Legal & IP. يمكن إنشاء قوائم جديدة. الضغط على القائمة يشغّل بحثاً بمصطلحها.

---

## 5. إضافة API (اختياري تماماً)

الإعدادات ← مفاتيح API. المزودون: YouTube Data API v3، USPTO PatentSearch، OpenAI، NewsAPI، Reddit، X.
- **التطبيق يعمل بالمصادر المجانية دون أي مفتاح.**
- المفاتيح **مشفّرة عبر Android Keystore** (EncryptedSharedPreferences) ولا تُعرض كاملة ولا تُسجَّل ولا تُضمَّن في الكود. تُخزَّن في قاعدة البيانات **آخر 4 أحرف فقط** كتلميح.
- المفاتيح المُخزَّنة لمزودين لا يستخدمهم أي Connector حالياً (OpenAI, NewsAPI, Reddit, X) تُحفظ ولا تُستخدم بعد، والواجهة تعرض ذلك صراحةً.

---

## 6. الإشعارات والمراقبة في الخلفية

- **إشعارات محلية فقط** (لا Firebase/Push في v1).
- الأولوية: **Normal** للأخبار والمنصات والفيديو، **High** للبراءات والعلامات (قناة بأهمية قصوى).
- الإشعارات تُحترم وفق إعدادات Android (بما فيها Do Not Disturb عبر إعدادات القناة).
- **WorkManager:** فترات 5/15/30/60 دقيقة، **لكن Android يفرض حداً أدنى 15 دقيقة** للمهام الدورية، وقد تتأخر المهام حسب قيود البطارية. التطبيق يعرض الفترة الفعلية المطبّقة.
- **Smart polling المطبّق:** المصدر الذي فشل أو حُجب خلال الساعة الأخيرة يُتجاوز في الدورة التالية (backoff مبسّط).

---

## 7. Offline Mode والنسخ الاحتياطي

- كل النتائج تُحفظ محلياً في SQLite. عند انقطاع الإنترنت تبقى النتائج والمفضلة وسجل البحث متاحة.
- **النسخ الاحتياطي:** الإعدادات ← النسخ الاحتياطي ← تصدير. يُشارَك ملف قاعدة البيانات عبر Android Share Sheet.
- **الاستعادة غير مدعومة بعد** (انظر Known Limitations).

---

## 8. تصنيف المصادر (مطلوب)

### A. موصلات مُنفّذة ومُختبرة (Unit tests بـ fixtures داخل `test/`)
- **Google News (RSS):** تحليل الخلاصة، التطبيع، روابط، التواريخ، الملخص الاستخراجي.
- **Reddit (JSON):** تحليل الاستجابة، وحالة `403 → BLOCKED`.
- **GDELT:** مسار `429 → RATE_LIMITED`.
- **YouTube:** مسار `بدون مفتاح → API_REQUIRED` دون أي طلب شبكة.
- **المحرك:** البث التدريجي، فشل موصل لا يوقف الباقي، الإلغاء، التعطيل، حد حجم الاستجابة، حدود الاستعلامات.

> ملاحظة: الاختبارات تُشغَّل في GitHub Actions. التحقق من الاتصال الحي بالمصادر لم يُجرَ في بيئة التطوير.

### B. مُنفّذة لكن قد تكون غير متاحة حالياً
- **GDELT:** قد يفرض حد معدل (`RATE_LIMITED`).
- **Reddit:** قد يرفض الطلبات المجهولة (`BLOCKED`).
- **Hacker News، PubMed:** مُنفّذة بواجهات عامة، لم تُختبر على الشبكة الحية.
- **المصادر المخصّصة:** تعتمد على الرابط الذي تضيفه.

### C. مخطط لها / مستقبلية (غير مُنفّذة كـ Connectors)
Stack Exchange (Biology/Pets/Skeptics)، Lemmy، Bluesky، Mastodon، Quora، Medium، Substack، Dev.to، Telegram، TikTok، Threads، Pinterest، Tumblr، Flickr، Snapchat، Lens.org، Espacenet، JPO، PatentScope، FreePatentsOnline، Trademarkia، TMview، ResearchGate، Semantic Scholar، ClinicalTrials.gov، Google Scholar، Crunchbase، PitchBook، Glassdoor، Indeed، Wikipedia/Wikidata، Archive.org/Wayback، AVMA، DVM360، Today's Veterinary Practice، Vet Times، Vet Record، JAVMA، Fierce Biotech، إلخ.
يمكن إضافتها الآن كمصادر **RSS** أو **Sitemap** أو **Search URL** أو **JSON API** من Sources Manager إن كانت تتيح ذلك.

### D. مصادر تتطلب مفتاح API
- **YouTube Data API v3** — مُنفّذ، يعمل عند إضافة المفتاح.
- **USPTO PatentSearch API** — مُنفّذ، يعمل عند إضافة المفتاح.
- **EUIPO Trademarks** — يتطلب بيانات اعتماد مسجّلة (غير مُفعَّل).
- **X (Twitter)** — `API_REQUIRED` (البحث يتطلب واجهة مدفوعة).
- **Bing News** — `NOT_SUPPORTED`: أوقفت Microsoft واجهات Bing Search في 2025.

### E. مصادر تتطلب تسجيل دخول
- **VIN Forum** — `LOGIN_REQUIRED`.
- **Facebook / LinkedIn** — `LOGIN_REQUIRED`.
- **USPTO Trademarks (بحث العلامات الرسمي)** — `LOGIN_REQUIRED`.

### F. مصادر محجوبة أو مقيّدة من المزوّد أو غير مدعومة
- **Instagram** — `BLOCKED` (يمنع البحث المجهول والكشط).
- **Google Patents** — `NOT_SUPPORTED` (لا API رسمي؛ الكشط غير مُنفّذ).
- **WIPO Global Brand Database** — `NOT_SUPPORTED` (لا API عام مُتحقَّق منه).
- **DuckDuckGo News** — `NOT_SUPPORTED` (لا API رسمي؛ كشط محركات البحث غير مُنفّذ).
- **VetSurgeon** — `NOT_SUPPORTED` (لا نقطة بحث عامة مُتحقَّق منها؛ أضفه كـ Search URL مخصص).

**القاعدة:** لا يتجاوز التطبيق CAPTCHA أو المصادقة أو الـPaywall أو قيود robots أو حدود المعدل أو ضوابط الوصول. كل موصل يدوّر User-Agent، ولكل طلب مهلة صارمة 10 ثوانٍ، ولكل موصل حد أقصى للطلبات في الدقيقة.

---

## 9. حدود الأمان القابلة للتعديل

| الحد | الافتراضي | قابل للتعديل |
|---|---|---|
| صفحات لكل مصدر | 1 | بالكود (`SearchLimits`) |
| أقصى نتائج لكل استعلام | 30 | نعم (10–100) |
| طلبات/دقيقة لكل مضيف | 20 | بالكود |
| أقصى حجم استجابة | 2 MB | بالكود |
| أقصى مدة للبحث | 60 ثانية | بالكود |
| أقصى محتوى مخزَّن لكل نتيجة | 4000 حرف | بالكود |
| Connectors متوازية | 4 | نعم (4–8) |
| مهلة كل طلب | 10 ثوانٍ | ثابت |

---

## 10. قاعدة البيانات

SQLite بإصدار مخطط (`schemaVersion = 1`) مع آلية Migrations في `lib/database/app_database.dart`. الجداول:
`results, sources, keywords, entities, inventors, patents, trademarks, favorites, watchlists, search_history, search_sessions, connector_health, api_keys, notifications, sync_runs`.
- `connector_health` يحفظ **مصفوفة القدرات**: Free/Paid، API Required، Login Required، RSS، Scraping، Currently Available، Last Tested، Current Health.
- عند إضافة إصدار مخطط جديد: أضف خطوة `if (from < 2)` داخل `_migrate` ولا تعدّل جداول v1.

---

## 11. الهيكل

```
lib/
  main.dart
  config/          app_config.dart        (الإصدار، الحدود، User-Agents، tr())
  models/          models.dart            (النماذج، الحالات، أحداث البث)
  collectors/      source_connector.dart  (الواجهة + SafeHttp: مهلة/إعادة محاولة/حدود)
                   builtin_connectors.dart, custom_connectors.dart, registry.dart
  filters/         normalizer.dart        (تطبيع، روابط، تواريخ، درجات، ملخص استخراجي)
                   pipeline.dart          (Deduplication + Ranking)
  services/        search_orchestrator.dart (البث المتوازي، الإلغاء، الجلسات)
                   providers.dart (Riverpod)  secure_store.dart  notifications.dart
                   background_service.dart    seed.dart
  database/        app_database.dart      (SQLite + Migrations)
  screens/         home, search, detail, manage (مصادر/كلمات/قوائم/API/سجلات), settings
  widgets/         common_widgets.dart, result_card.dart
test/
  database_test.dart, connector_test.dart, deduplication_test.dart, streaming_test.dart
assets/            (مجلد الأصول؛ لا توجد بيانات تجريبية)
scripts/
  ci_patch_android.py   (تعديل Manifest/Gradle في CI: صلاحيات، minSdk=23، Core library desugaring)
.github/workflows/build.yml
```

**إدارة الحالة:** Riverpod (`StateNotifier` لمحرك البحث والإعدادات، و`FutureProvider` للبيانات).

---

## 12. بناء APK عبر GitHub Actions

> التطبيق **لا يُبنى محلياً** في بيئة التطوير. البناء يتم تلقائياً على GitHub.

1. **ارفع المشروع** إلى مستودع GitHub جديد (فرع `main`).
2. **افتح تبويب Actions** ← `Build Android APK` ← اضغط **Run workflow** (أو يبدأ تلقائياً عند الدفع).
3. **حمّل الملف** من قسم **Artifacts**: `zomedica-radar-debug-apk` ثم ثبّت `app-debug.apk` على جهاز Android 8.0+.

**ما يقوم به الـworkflow** (`.github/workflows/build.yml`):
- Java 17 (Temurin) + Flutter stable.
- إنشاء مجلد `android/` عبر `flutter create` إن لم يكن موجوداً، مع إعادة الكود الخاص بنا كما هو.
- تشغيل `scripts/ci_patch_android.py`: صلاحيات `INTERNET` و`POST_NOTIFICATIONS` و`RECEIVE_BOOT_COMPLETED`، واسم التطبيق، و`minSdk = 23`، وتفعيل Core library desugaring (مطلوب لـ flutter_local_notifications).
- `flutter pub get` ← `flutter analyze` ← `flutter test` ← `flutter build apk --debug` ← رفع APK كـ artifact.

**ملاحظة:** `versionName` و`versionCode` مأخوذان من `pubspec.yaml` (`1.0.0+1`).

---

## 13. Known Limitations

1. لم يُبنَ APK ولم تُشغَّل الاختبارات محلياً (لا يوجد Flutter SDK في بيئة التطوير)؛ التحقق يتم في GitHub Actions.
2. مجلد `android/` غير مُضمَّن في المشروع ويُنشأ تلقائياً في CI.
3. موصلات Google Patents وWIPO وBing وDuckDuckGo وVetSurgeon: `NOT_SUPPORTED` (السبب موثّق أعلاه).
4. X, Instagram, Facebook, LinkedIn, VIN, USPTO Trademarks, EUIPO: حالة فعلية فقط ولا تنفّذ بحثاً.
5. YouTube وUSPTO Patents تتطلبان مفتاحاً؛ تكامل USPTO مبني على الوثائق العامة ويحتاج تحققاً مباشراً مع المفتاح على الجهاز.
6. Reddit وGDELT قد يحجبان الطلبات المجهولة أو يفرضان حد معدل؛ تظهر الحالة الفعلية.
7. **XPath** غير مدعوم؛ محدِّدات CSS مدعومة. الترقيم عبر `{page}` فقط.
8. الترجمة: زر يفتح Google Translate، لا توجد ترجمة داخلية.
9. الملخص: استخراجي فقط (جمل حرفية)، لا توليد بنماذج لغوية.
10. اكتشاف الكيانات: مُطبَّق على أسماء المخترعين في نتائج البراءات فقط.
11. الاستعادة من النسخة الاحتياطية غير مدعومة (التصدير فقط).
12. Statistics Page، Widget، Voice Search، Archive Monitoring (Wayback)، Social Connectors الفعلية (Priority C): غير مُنفّذة في v1.0.0.
13. الإشعارات: صوت مخصص غير مُضمَّن؛ الأولوية تُفرَّق بالقنوات.
14. WorkManager: حد أدنى 15 دقيقة على Android؛ الفترات 5 دقائق تُطبَّق كـ 15.
15. الترجمة والكيانات والتنبيهات تعتمد على المصادر المتاحة فعلياً وقت البحث.

---

## 14. الترخيص والملاحظات القانونية

التطبيق أداة مراقبة للمحتوى العام. احترم شروط خدمة كل مزود ومتطلبات robots وحقوق النشر. لا يتجاوز التطبيق أي حماية تقنية أو قيود وصول.
