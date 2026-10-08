import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/models.dart';

/// إشعارات محلية فقط (لا Firebase/Push في v1).
/// قناة High لبراءات الاختراع/العلامات (أهمية قصوى + اهتزاز مختلف).
/// قناة Normal للأخبار/السوشيال/الفيديو. Android يحترم DND تلقائياً عبر إعدادات القناة.
class RadarNotifications {
  RadarNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _highChannel = AndroidNotificationChannel(
    'radar_high',
    'Legal & IP (High)',
    description: 'براءات الاختراع والعلامات التجارية',
    importance: Importance.max,
    enableVibration: true,
  );

  static const _normalChannel = AndroidNotificationChannel(
    'radar_normal',
    'News & Social (Normal)',
    description: 'الأخبار والمنصات الاجتماعية والفيديو',
    importance: Importance.defaultImportance,
  );

  static Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    final impl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await impl?.createNotificationChannel(_highChannel);
    await impl?.createNotificationChannel(_normalChannel);
    await impl?.requestNotificationsPermission();
    _ready = true;
  }

  static String priorityFor(SourceType t) =>
      (t == SourceType.patent || t == SourceType.trademark) ? 'HIGH' : 'NORMAL';

  static Future<void> showResult(SearchResult r, int id) async {
    await init();
    final high = priorityFor(r.sourceType) == 'HIGH';
    final ch = high ? _highChannel : _normalChannel;
    await _plugin.show(
      id,
      high ? '⚠ ${r.title}' : r.title,
      r.source,
      NotificationDetails(
        android: AndroidNotificationDetails(
          ch.id,
          ch.name,
          channelDescription: ch.description,
          importance: high ? Importance.max : Importance.defaultImportance,
          priority: high ? Priority.high : Priority.defaultPriority,
          styleInformation: BigTextStyleInformation(r.snippet),
        ),
      ),
    );
  }
}
