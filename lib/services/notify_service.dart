/// Local (on-device) notifications for daily favourite-promo reminders.
///
/// Schedules two repeating daily alarms — morning and evening peak times — that
/// nudge the user to check the day's promotions on their favourite products.
/// No Firebase / server push required; uses inexact alarms via
/// flutter_local_notifications (a few minutes of slack is fine for a daily
/// reminder, and it avoids the Play-restricted USE_EXACT_ALARM permission).
/// (Personalised "X is −30%" content is a future
/// FCM upgrade; the reminder itself is reliable on-device.)
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'local_store.dart';

class NotifyService {
  NotifyService._();
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // Peak times (local): early morning + late evening.
  static const int _morningHour = 7, _morningMin = 30;
  static const int _eveningHour = 20, _eveningMin = 0;
  static const int _idMorning = 4001, _idEvening = 4002;

  static const _channel = AndroidNotificationChannel(
    'fav_promos',
    'Промоции на любими',
    description: 'Сутрешни и вечерни напомняния за намаления на любимите ти продукти',
    importance: Importance.high,
  );

  /// One-time init (call at app startup). Safe to call repeatedly.
  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Sofia'));
    } catch (_) {/* falls back to UTC */}
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    _ready = true;
  }

  /// Ask for the runtime notification permission (Android 13+). Returns granted.
  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true; // non-Android platform
    final req = await android.requestNotificationsPermission();
    if (req == true) return true;
    // requestNotificationsPermission() can return null/false when the system
    // dialog is NOT shown because permission is already granted (or was just
    // granted from Settings). Fall back to the real current state so the toggle
    // reflects reality instead of staying stuck OFF.
    final enabled = await android.areNotificationsEnabled();
    return enabled ?? (req ?? false);
  }

  static tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'fav_promos', 'Промоции на любими',
      channelDescription: 'Намаления на любими продукти',
      importance: Importance.high, priority: Priority.high,
    ),
  );

  /// Enable: request permission and schedule the two daily reminders.
  static Future<bool> enableDailyReminders() async {
    await init();
    final ok = await requestPermission();
    if (!ok) return false;
    // Permission is granted → consider reminders enabled even if scheduling
    // hits a transient hiccup (rescheduleIfEnabled() re-arms on next launch),
    // so the toggle never gets stuck OFF after the user allowed notifications.
    try {
      await _schedule(_idMorning, _morningHour, _morningMin,
          '🌅 Добро утро! Виж днешните промоции', 'Любимите ти продукти може да са намалени днес.');
      await _schedule(_idEvening, _eveningHour, _eveningMin,
          '🌙 Намаления за утре', 'Провери цените на любимите си продукти преди пазар.');
    } catch (_) {/* re-armed on next app launch via rescheduleIfEnabled() */}
    await LocalStore.setNotifyEnabled(true);
    return true;
  }

  static Future<void> _schedule(int id, int hour, int min, String title, String body) async {
    await _plugin.zonedSchedule(
      id, title, body, _nextInstance(hour, min), _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily at this time
    );
  }

  static Future<void> disable() async {
    await init();
    await _plugin.cancel(_idMorning);
    await _plugin.cancel(_idEvening);
    await LocalStore.setNotifyEnabled(false);
  }

  /// Re-arm on startup if the user previously enabled reminders.
  static Future<void> rescheduleIfEnabled() async {
    if (await LocalStore.notifyEnabled()) {
      await init();
      await _schedule(_idMorning, _morningHour, _morningMin,
          '🌅 Добро утро! Виж днешните промоции', 'Любимите ти продукти може да са намалени днес.');
      await _schedule(_idEvening, _eveningHour, _eveningMin,
          '🌙 Намаления за утре', 'Провери цените на любимите си продукти преди пазар.');
    }
  }
}
