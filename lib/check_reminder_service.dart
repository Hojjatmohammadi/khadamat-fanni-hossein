import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'check_repository.dart';

/// Keeps local cheque reminders scheduled, including while the app is closed.
/// Notifications are intentionally inexact so the app does not request the
/// restricted Android exact-alarm permission.
class CheckReminderService {
  CheckReminderService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const int _summaryNotificationId = 71001;
  static const int _notificationIdBase = 100000;
  static const int _maximumCheckId = 1000000000;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'check_due_reminders',
    'یادآوری سررسید چک‌ها',
    description: 'یادآوری چک‌های سررسیدشده و نزدیک به سررسید',
    importance: Importance.high,
  );

  static const NotificationDetails _scheduledDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'check_due_reminders',
      'یادآوری سررسید چک‌ها',
      channelDescription: 'یادآوری چک‌های سررسیدشده و نزدیک به سررسید',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  int _dayBeforeId(int checkId) =>
      _notificationIdBase + (checkId % _maximumCheckId) * 2;

  int _dailyDueId(int checkId) => _dayBeforeId(checkId) + 1;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    final timeZoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timeZoneName));

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channel);
    _initialized = true;
  }

  tz.TZDateTime _atNine(DateTime date) =>
      tz.TZDateTime(tz.local, date.year, date.month, date.day, 9);

  /// Rebuilds reminders from the cheque register.
  /// A one-day-before notice is sent once; an overdue notice repeats daily
  /// until the cheque is cleared, bounced, or cancelled.
  ///
  /// Permission is requested only after the user explicitly saves a cheque.
  Future<bool> synchronize(
    CheckRepository repository, {
    bool requestPermission = false,
  }) async {
    if (!_initialized) await initialize();

    final checks = await repository.getChecks();

    // Remove stale reminders, including those belonging to terminal statuses.
    for (final check in checks) {
      final checkId = (check['id'] as num).toInt();
      await _plugin.cancel(_dayBeforeId(checkId));
      await _plugin.cancel(_dailyDueId(checkId));
    }
    await _plugin.cancel(_summaryNotificationId);

    const activeStatuses = {'received', 'deposited', 'issued'};
    final activeChecks = checks.where(
      (check) => activeStatuses.contains(check['status']),
    ).toList(growable: false);
    if (activeChecks.isEmpty) return true;

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var enabled = await android?.areNotificationsEnabled();
    if (enabled == false && requestPermission) {
      enabled = await android?.requestNotificationsPermission();
    }
    if (enabled == false) return false;

    final now = tz.TZDateTime.now(tz.local);
    for (final check in activeChecks) {
      final checkId = (check['id'] as num).toInt();
      final dueDate = DateTime.tryParse(check['due_date']?.toString() ?? '');
      if (dueDate == null) continue;

      final direction = check['direction'] == 'incoming' ? 'دریافتی' : 'پرداختی';
      final number = check['check_number']?.toString() ?? '';
      final party = check['party_name']?.toString() ?? 'طرف حساب';
      final amount = (check['amount'] as num?)?.toInt() ?? 0;
      final dayBefore = _atNine(
        DateTime(dueDate.year, dueDate.month, dueDate.day - 1),
      );
      final dueAt = _atNine(dueDate);

      if (dayBefore.isAfter(now)) {
        await _plugin.zonedSchedule(
          _dayBeforeId(checkId),
          'یادآوری چک فردا',
          'چک $direction شماره $number از $party، فردا سررسید می‌شود. مبلغ: $amount تومان',
          dayBefore,
          _scheduledDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'check:$checkId:day_before',
        );
      }

      // Start tomorrow if 09:00 on the due date has already passed.
      final firstDailyReminder = dueAt.isAfter(now)
          ? dueAt
          : _atNine(DateTime(dueDate.year, dueDate.month, dueDate.day + 1));

      await _plugin.zonedSchedule(
        _dailyDueId(checkId),
        'یادآوری سررسید چک $number',
        'چک $direction شماره $number مربوط به $party هنوز تعیین تکلیف نشده است. مبلغ: $amount تومان',
        firstDailyReminder,
        _scheduledDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'check:$checkId:due',
      );
    }

    await notifyDueChecks(repository);
    return true;
  }

  /// Displays an immediate summary for overdue, today's, and tomorrow's cheques.
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

    if (due.isEmpty) {
      await _plugin.cancel(_summaryNotificationId);
      return 0;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final enabled = await android?.areNotificationsEnabled();
    if (enabled == false) {
      await _plugin.cancel(_summaryNotificationId);
      return 0;
    }

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
      _summaryNotificationId,
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
