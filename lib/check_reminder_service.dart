import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'check_repository.dart';

/// Shows a local reminder when the app opens and finds checks due today,
/// tomorrow, or overdue. This intentionally does not claim background scheduling.
class CheckReminderService {
  CheckReminderService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  static const _channel = AndroidNotificationChannel(
    'check_due_reminders',
    'یادآوری سررسید چک‌ها',
    description: 'یادآوری چک‌های سررسیدشده و نزدیک به سررسید',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    await android?.requestNotificationsPermission();
  }

  Future<int> notifyDueChecks(CheckRepository repository) async {
    final checks = await repository.getDueChecks();
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final due = checks.where((check) {
      final raw = check['due_date']?.toString();
      final date = raw == null ? null : DateTime.tryParse(raw);
      return date != null &&
          !date.isAfter(DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
    }).toList(growable: false);

    if (due.isEmpty) return 0;

    final overdue = due.where((check) {
      final date = DateTime.parse(check['due_date'].toString());
      return date.isBefore(DateTime(today.year, today.month, today.day));
    }).length;
    final dueToday = due.where((check) {
      final date = DateTime.parse(check['due_date'].toString());
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).length;
    final dueTomorrow = due.length - overdue - dueToday;

    final parts = <String>[];
    if (overdue > 0) parts.add('$overdue چک معوق');
    if (dueToday > 0) parts.add('$dueToday چک سررسید امروز');
    if (dueTomorrow > 0) parts.add('$dueTomorrow چک سررسید فردا');

    await _plugin.show(
      71001,
      'یادآوری چک‌های فروشگاه',
      parts.join('، '),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(parts.join('، ')),
        ),
      ),
    );
    return due.length;
  }
}
