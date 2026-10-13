import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import 'add_task_screen.dart';
import 'task_list_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final double textScale;
  final ValueChanged<double> onTextScaleChanged;
  final Color accentColor;
  final ValueChanged<Color> onAccentColorChanged;

  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.textScale,
    required this.onTextScaleChanged,
    required this.accentColor,
    required this.onAccentColorChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  List<Task> _tasks = [];
  String _username = '';
  bool _remindersEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  int _reminderDaysBefore = 1;
  String _timerSoundId = NotificationService.timerSounds.first.id;

  CollectionReference<Map<String, dynamic>> get _tasksCollection {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('tasks');
  }

  String _friendlyFirestoreError(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return "You don't have permission to do that.";
        case 'unavailable':
          return 'No internet connection. Please check your connection and try again.';
        case 'unauthenticated':
          return "You've been signed out. Please sign in again.";
        case 'deadline-exceeded':
          return 'That took too long. Please try again.';
        default:
          return 'Something went wrong saving your data.';
      }
    }
    return 'Something went wrong. Please try again.';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Future.wait([_loadTasks(), _loadReminderSettings(), _loadTimerSound()]);
    if (_remindersEnabled) {
      await NotificationService.instance.rescheduleAll(
        _tasks,
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        daysBefore: _reminderDaysBefore,
      );
    }
    // Timers that were still running when the app was last closed: make sure
    // their alerts are scheduled (the system can drop them, e.g. on force-stop).
    await _rescheduleRunningTimerAlerts();
  }

  Future<void> _rescheduleRunningTimerAlerts() async {
    for (final task in _tasks) {
      if (task.isTimeBased && task.isTimerRunning && !task.isDone) {
        await NotificationService.instance.scheduleTimerAlert(task);
      }
    }
  }

  Future<void> _loadTimerSound() async {
    final sound = await NotificationService.instance.currentTimerSound();
    if (!mounted) return;
    setState(() {
      _timerSoundId = sound.id;
    });
  }

  Future<void> _setTimerSound(String id) async {
    await NotificationService.instance.setTimerSound(id);
    if (!mounted) return;
    setState(() {
      _timerSoundId = id;
    });
    // Timers that are already running would keep the old sound otherwise.
    await _rescheduleRunningTimerAlerts();
  }

  Future<void> _previewTimerSound(String id) {
    return NotificationService.instance.previewTimerSound(id);
  }

  Future<void> _loadTasks() async {
    try {
      final snapshot = await _tasksCollection.get();
      setState(() {
        _tasks = snapshot.docs.map((doc) => Task.fromJson(doc.data())).toList();
      });
    } catch (e) {
      _showError(_friendlyFirestoreError(e));
    }
  }

  Future<void> _rescheduleReminders() async {
    if (!_remindersEnabled) return;
    await NotificationService.instance.rescheduleAll(
      _tasks,
      hour: _reminderTime.hour,
      minute: _reminderTime.minute,
      daysBefore: _reminderDaysBefore,
    );
  }

  // Runs a Firestore write and shows any failure to the person. Never throws.
  Future<void> _runWrite(Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      _showError(_friendlyFirestoreError(e));
    }
  }

  // The write is started first but the reminders don't wait for it: while the
  // phone is offline Firestore only finishes a write once the server has
  // confirmed it, which would otherwise hold up rescheduling indefinitely.
  Future<void> _handleTaskChanged(Task task) async {
    setState(() {});
    final saving = _runWrite(
      () => _tasksCollection.doc(task.id).set(task.toJson()),
    );
    await _rescheduleReminders();
    await saving;
  }

  Future<void> _handleTaskDeleted(Task task) async {
    setState(() {});
    final deleting = _runWrite(
      () => _tasksCollection.doc(task.id).delete(),
    );
    await _rescheduleReminders();
    await deleting;
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    String? savedName = prefs.getString('username');

    if (savedName == null) {
      final randomNumber = Random().nextInt(90000) + 10000;
      savedName = 'User#$randomNumber';
      await prefs.setString('username', savedName);
    }

    setState(() {
      _username = savedName!;
    });
  }

  Future<void> _saveUsername(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', newName);
    setState(() {
      _username = newName;
    });
  }

  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('remindersEnabled') ?? false;
    final hour = prefs.getInt('reminderHour') ?? 9;
    final minute = prefs.getInt('reminderMinute') ?? 0;
    final daysBefore = prefs.getInt('reminderDaysBefore') ?? 1;
    setState(() {
      _remindersEnabled = enabled;
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
      _reminderDaysBefore = daysBefore;
    });
  }

  Future<bool> _requestNotificationPermission() {
    return NotificationService.instance.requestPermissions();
  }

  Future<void> _setRemindersEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remindersEnabled', enabled);
    setState(() {
      _remindersEnabled = enabled;
    });
    if (enabled) {
      await NotificationService.instance.rescheduleAll(
        _tasks,
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        daysBefore: _reminderDaysBefore,
      );
    } else {
      await NotificationService.instance.cancelAllReminders();
    }
  }

  Future<void> _setReminderTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminderHour', time.hour);
    await prefs.setInt('reminderMinute', time.minute);
    setState(() {
      _reminderTime = time;
    });
    if (_remindersEnabled) {
      await NotificationService.instance.rescheduleAll(
        _tasks,
        hour: time.hour,
        minute: time.minute,
        daysBefore: _reminderDaysBefore,
      );
    }
  }

  Future<void> _setReminderDaysBefore(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reminderDaysBefore', days);
    setState(() {
      _reminderDaysBefore = days;
    });
    if (_remindersEnabled) {
      await NotificationService.instance.rescheduleAll(
        _tasks,
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        daysBefore: days,
      );
    }
  }

  Future<void> _addNewTask() async {
    final newTask = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );
    if (newTask != null) {
      setState(() {
        _tasks.add(newTask);
      });
      final saving = _runWrite(
        () => _tasksCollection.doc(newTask.id).set(newTask.toJson()),
      );
      await _rescheduleReminders();
      await saving;
    }
  }

  // Clearing everything is deliberate and consequential, so unlike the
  // targeted methods above, a failure here leaves the local list untouched
  // entirely rather than risking it drifting out of sync with the cloud.
  Future<bool> _clearAllTasks() async {
    try {
      final existingDocs = await _tasksCollection.get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      _showError(_friendlyFirestoreError(e));
      return false;
    }

    for (final task in _tasks) {
      await NotificationService.instance.cancelTimerAlert(task.id);
    }

    setState(() {
      _tasks.clear();
    });

    if (_remindersEnabled) {
      await NotificationService.instance.rescheduleAll(
        _tasks,
        hour: _reminderTime.hour,
        minute: _reminderTime.minute,
        daysBefore: _reminderDaysBefore,
      );
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = Theme.of(context).colorScheme.primary;

    final screens = [
      DashboardScreen(
        tasks: _tasks,
        username: _username,
        onTaskChanged: _handleTaskChanged,
        onSeeAllTasks: () => setState(() => _selectedIndex = 1),
      ),
      TaskListScreen(
        tasks: _tasks,
        onTaskChanged: _handleTaskChanged,
        onTaskDeleted: _handleTaskDeleted,
      ),
      SettingsScreen(
        themeMode: widget.themeMode,
        onThemeModeChanged: widget.onThemeModeChanged,
        taskCount: _tasks.length,
        onClearAllTasks: _clearAllTasks,
        remindersEnabled: _remindersEnabled,
        reminderTime: _reminderTime,
        reminderDaysBefore: _reminderDaysBefore,
        onRemindersEnabledChanged: _setRemindersEnabled,
        onReminderTimeChanged: _setReminderTime,
        onReminderDaysBeforeChanged: _setReminderDaysBefore,
        onRequestNotificationPermission: _requestNotificationPermission,
        timerSoundId: _timerSoundId,
        onTimerSoundChanged: _setTimerSound,
        onPreviewTimerSound: _previewTimerSound,
      ),
      ProfileScreen(
        username: _username,
        onUsernameChanged: _saveUsername,
        textScale: widget.textScale,
        onTextScaleChanged: widget.onTextScaleChanged,
        accentColor: widget.accentColor,
        onAccentColorChanged: widget.onAccentColorChanged,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: screens,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewTask,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: Icon(Icons.dashboard, color: _selectedIndex == 0 ? activeColor : null),
              onPressed: () => setState(() => _selectedIndex = 0),
            ),
            IconButton(
              icon: Icon(Icons.checklist, color: _selectedIndex == 1 ? activeColor : null),
              onPressed: () => setState(() => _selectedIndex = 1),
            ),
            const SizedBox(width: 40),
            IconButton(
              icon: Icon(Icons.settings, color: _selectedIndex == 2 ? activeColor : null),
              onPressed: () => setState(() => _selectedIndex = 2),
            ),
            IconButton(
              icon: Icon(Icons.person, color: _selectedIndex == 3 ? activeColor : null),
              onPressed: () => setState(() => _selectedIndex = 3),
            ),
          ],
        ),
      ),
    );
  }
}