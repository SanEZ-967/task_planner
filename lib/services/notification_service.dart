import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../models/task.dart' show Task;

/// One selectable sound for the "timer complete" alert.
///
/// Exactly one of [rawResource] / [systemUri] is set for a real sound:
///  - [rawResource]: file name (no extension) inside android/app/src/main/res/raw
///  - [systemUri]:   a sound that ships with the phone
/// If both are null and [silent] is false, the phone's default notification
/// sound is used. [silent] means vibrate only.
class TimerSound {
  final String id;
  final String label;
  final String? rawResource;
  final String? systemUri;
  final bool silent;

  const TimerSound({
    required this.id,
    required this.label,
    this.rawResource,
    this.systemUri,
    this.silent = false,
  });
}

class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelId = 'due_date_reminders';
  static const _channelName = 'Due date reminders';
  static const _channelDescription = 'Reminders for tasks with a due date';

  static const _timerChannelDescription = 'Alerts when a timed task reaches its target duration';

  static const int maxDaysBefore = 30;

  // ---------------------------------------------------------------------------
  // Timer alert sounds
  // ---------------------------------------------------------------------------

  static const String timerSoundPrefKey = 'timerSoundId';
  static const String _exactAlarmPromptedKey = 'exactAlarmPrompted';

  // Timer notifications carry this prefix in their payload so that
  // cancelAllReminders() can tell them apart from due-date reminders and
  // leave them alone.
  static const String _timerPayloadPrefix = 'timer:';

  static const int _previewNotificationId = 2147483646;

  /// The sounds shown in Settings. To add your own, drop the file into
  /// android/app/src/main/res/raw (lowercase name, no spaces) and add a line
  /// here with rawResource set to the file name without its extension.
  static const List<TimerSound> timerSounds = [
    TimerSound(id: 'default', label: 'Default notification'),
    TimerSound(
      id: 'system_alarm',
      label: 'Device alarm',
      systemUri: 'content://settings/system/alarm_alert',
    ),
    TimerSound(id: 'chime', label: 'Chime', rawResource: 'timer_chime'),
    TimerSound(id: 'bell', label: 'Bell', rawResource: 'timer_bell'),
    TimerSound(id: 'beep', label: 'Alarm clock beeps', rawResource: 'timer_beep'),
    TimerSound(id: 'digital', label: 'Digital', rawResource: 'timer_digital'),
    TimerSound(id: 'gentle', label: 'Gentle ding-dong', rawResource: 'timer_gentle'),
    TimerSound(id: 'silent', label: 'Vibrate only', silent: true),
  ];

  static TimerSound soundById(String? id) {
    return timerSounds.firstWhere(
      (s) => s.id == id,
      orElse: () => timerSounds.first,
    );
  }

  Future<TimerSound> currentTimerSound() async {
    final prefs = await SharedPreferences.getInstance();
    return soundById(prefs.getString(timerSoundPrefKey));
  }

  Future<void> setTimerSound(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(timerSoundPrefKey, id);
  }

  AndroidNotificationSound? _androidSoundFor(TimerSound sound) {
    if (sound.rawResource != null) {
      return RawResourceAndroidNotificationSound(sound.rawResource);
    }
    if (sound.systemUri != null) {
      return UriAndroidNotificationSound(sound.systemUri!);
    }
    return null; // phone's default notification sound
  }

  // On Android 8+ a notification's sound belongs to its *channel* and can't be
  // changed once the channel exists. So every sound gets its own channel, and
  // picking a different sound just means using a different channel.
  String _timerChannelIdFor(TimerSound sound) => 'timer_alerts_${sound.id}';
  String _timerChannelNameFor(TimerSound sound) => 'Timer alert: ${sound.label}';

  Future<String> _ensureTimerChannel(TimerSound sound) async {
    final channelId = _timerChannelIdFor(sound);
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      AndroidNotificationChannel(
        channelId,
        _timerChannelNameFor(sound),
        description: _timerChannelDescription,
        importance: Importance.max,
        playSound: !sound.silent,
        sound: _androidSoundFor(sound),
        enableVibration: true,
        // Plays on the alarm volume, so it is heard even if the ringer or
        // notification volume is turned down.
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    return channelId;
  }

  AndroidNotificationDetails _timerAndroidDetails(
    TimerSound sound,
    String channelId, {
    int? timeoutAfterMs,
  }) {
    return AndroidNotificationDetails(
      channelId,
      _timerChannelNameFor(sound),
      channelDescription: _timerChannelDescription,
      importance: Importance.max,
      priority: Priority.max,
      playSound: !sound.silent,
      sound: _androidSoundFor(sound),
      enableVibration: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      timeoutAfter: timeoutAfterMs,
    );
  }

  /// Fires a notification right now using [soundId]'s channel, so the person
  /// hears exactly what the real alert will sound like. Disappears by itself.
  Future<void> previewTimerSound(String soundId) async {
    final sound = soundById(soundId);
    final channelId = await _ensureTimerChannel(sound);
    await _plugin.cancel(id: _previewNotificationId);
    await _plugin.show(
      id: _previewNotificationId,
      title: 'Sound preview',
      body: sound.label,
      notificationDetails: NotificationDetails(
        android: _timerAndroidDetails(sound, channelId, timeoutAfterMs: 4000),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: '${_timerPayloadPrefix}preview',
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _plugin.initialize(settings: initSettings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    // Timer-alert channels are created on demand (see _ensureTimerChannel).

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted ?? true;
    }

    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }

    return true;
  }

  /// On Android 12+ an alarm only fires at the exact second if the person has
  /// allowed "Alarms & reminders" for the app; otherwise Android may hold the
  /// alert back by several minutes while the phone is idle. This opens that
  /// system screen once (never nags again if declined).
  Future<void> requestExactAlarmPermissionOnce() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    if (await androidPlugin.canScheduleExactNotifications() ?? true) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_exactAlarmPromptedKey) ?? false) return;
    await prefs.setBool(_exactAlarmPromptedKey, true);
    await androidPlugin.requestExactAlarmsPermission();
  }

  Future<AndroidScheduleMode> _timerScheduleMode() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return AndroidScheduleMode.exactAllowWhileIdle;
    final canExact = await androidPlugin.canScheduleExactNotifications() ?? false;
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  int _idFor(String taskId, int dayOffset) => '${taskId}_$dayOffset'.hashCode & 0x7fffffff;

  // A separate ID "namespace" (different prefix) so a timer alert can never
  // collide with one of that same task's due-date reminder slots.
  int _timerIdFor(String taskId) => 'timer_$taskId'.hashCode & 0x7fffffff;

  tz.TZDateTime _asTz(DateTime local) => tz.TZDateTime.from(local.toUtc(), tz.UTC);

  Future<void> scheduleForTask(
    Task task, {
    required int hour,
    required int minute,
    required int daysBefore,
  }) async {
    for (int offset = 0; offset <= maxDaysBefore; offset++) {
      await _plugin.cancel(id: _idFor(task.id, offset));
    }

    if (task.isDone || task.dueDate == null) return;

    final due = task.dueDate!;
    final dueDateOnly = DateTime(due.year, due.month, due.day);
    final clampedDaysBefore = daysBefore.clamp(0, maxDaysBefore);

    for (int offset = 0; offset <= clampedDaysBefore; offset++) {
      final reminderDay = dueDateOnly.subtract(Duration(days: offset));
      // No reminders for a task that hasn't started yet.
      if (reminderDay.isBefore(task.startDay)) continue;
      final scheduledLocal =
          DateTime(reminderDay.year, reminderDay.month, reminderDay.day, hour, minute);
      if (scheduledLocal.isBefore(DateTime.now())) continue;

      final title = offset == 0
          ? 'Task due today'
          : 'Task due in $offset day${offset == 1 ? '' : 's'}';

      await _plugin.zonedSchedule(
        id: _idFor(task.id, offset),
        title: title,
        body: task.title,
        scheduledDate: _asTz(scheduledLocal),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
    }
  }

  /// Schedules a one-time alert for the moment a running, time-based task
  /// will reach its target duration, using the sound chosen in Settings.
  /// Always cancels any previous alert for this task first, so it's safe to
  /// call again to reschedule (e.g. on resume, since the remaining time has
  /// changed, or after the person picks a different sound).
  Future<void> scheduleTimerAlert(Task task) async {
    await cancelTimerAlert(task.id);

    if (!task.isTimeBased || !task.isTimerRunning) return;

    // For a repeating task this is the time left for the day the timer is
    // counting towards.
    final remaining = task.remainingOnRunningTimer;
    if (remaining == null || remaining <= Duration.zero) return;

    // Work out the fire time before any awaiting so setup work can't make
    // the alert late.
    final fireAt = DateTime.now().add(remaining);

    final sound = await currentTimerSound();
    final channelId = await _ensureTimerChannel(sound);
    final scheduleMode = await _timerScheduleMode();

    if (!fireAt.isAfter(DateTime.now())) return;

    await _plugin.zonedSchedule(
      id: _timerIdFor(task.id),
      title: 'Timer complete!',
      body: '"${task.title}" has reached its target time.',
      scheduledDate: _asTz(fireAt),
      notificationDetails: NotificationDetails(
        android: _timerAndroidDetails(sound, channelId),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: scheduleMode,
      payload: '$_timerPayloadPrefix${task.id}',
    );
  }

  /// Cancels a pending timer alert — call on pause, deletion of a time-based
  /// task, or when its target changes. (Don't call it when the timer simply
  /// finishes: the scheduled alert is what tells the person it's done.)
  Future<void> cancelTimerAlert(String taskId) async {
    await _plugin.cancel(id: _timerIdFor(taskId));
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// Cancels every pending due-date reminder but leaves running-timer alerts
  /// (and the sound preview) alone. This is what the reminder code should use
  /// instead of cancelAll(), which would also wipe out every timer alert.
  Future<void> cancelAllReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final request in pending) {
      final payload = request.payload;
      if (payload != null && payload.startsWith(_timerPayloadPrefix)) continue;
      await _plugin.cancel(id: request.id);
    }
  }

  Future<void> rescheduleAll(
    List<Task> tasks, {
    required int hour,
    required int minute,
    required int daysBefore,
  }) async {
    await cancelAllReminders();
    for (final task in tasks) {
      await scheduleForTask(task, hour: hour, minute: minute, daysBefore: daysBefore);
    }
  }
}