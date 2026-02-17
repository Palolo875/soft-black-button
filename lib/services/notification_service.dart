import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  NotificationService({FlutterLocalNotificationsPlugin? plugin}) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    await init();

    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    bool ok = true;
    if (ios != null) {
      ok = (await ios.requestPermissions(alert: true, badge: false, sound: true)) ?? false;
    }
    if (mac != null) {
      ok = ok && ((await mac.requestPermissions(alert: true, badge: false, sound: true)) ?? false);
    }
    if (android != null) {
      // Android 13+ runtime permission.
      final granted = await android.requestNotificationsPermission();
      ok = ok && (granted ?? true);
    }

    return ok;
  }

  Future<void> show({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    await init();

    const android = AndroidNotificationDetails(
      'horizon_alerts',
      'HORIZON alerts',
      channelDescription: 'Notifications contextuelles météo/itinéraire',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const ios = DarwinNotificationDetails();

    const details = NotificationDetails(android: android, iOS: ios);
    await _plugin.show(1, title, body, details);
  }
}
