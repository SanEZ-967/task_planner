import 'package:flutter/material.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int taskCount;
  // Resolves to true only if the tasks were actually cleared.
  final Future<bool> Function() onClearAllTasks;
  final bool remindersEnabled;
  final TimeOfDay reminderTime;
  final int reminderDaysBefore;
  final ValueChanged<bool> onRemindersEnabledChanged;
  final ValueChanged<TimeOfDay> onReminderTimeChanged;
  final ValueChanged<int> onReminderDaysBeforeChanged;
  final Future<bool> Function() onRequestNotificationPermission;
  final String timerSoundId;
  final ValueChanged<String> onTimerSoundChanged;
  final ValueChanged<String> onPreviewTimerSound;

  const SettingsScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.taskCount,
    required this.onClearAllTasks,
    required this.remindersEnabled,
    required this.reminderTime,
    required this.reminderDaysBefore,
    required this.onRemindersEnabledChanged,
    required this.onReminderTimeChanged,
    required this.onReminderDaysBeforeChanged,
    required this.onRequestNotificationPermission,
    required this.timerSoundId,
    required this.onTimerSoundChanged,
    required this.onPreviewTimerSound,
  });

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System default';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  Future<void> _showThemePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: RadioGroup<ThemeMode>(
            groupValue: themeMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Theme',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                ...[ThemeMode.light, ThemeMode.dark].map((mode) {
                  return RadioListTile<ThemeMode>(
                    secondary: Icon(_themeModeIcon(mode)),
                    title: Text(_themeModeLabel(mode)),
                    value: mode,
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != themeMode) {
      onThemeModeChanged(selected);
    }
  }

  Future<void> _handleRemindersToggled(BuildContext context, bool value) async {
    if (value) {
      final granted = await onRequestNotificationPermission();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Notifications are off for this app. Enable them in system settings to get reminders.",
              ),
            ),
          );
        }
        return;
      }
    }
    onRemindersEnabledChanged(value);
  }

  Future<void> _pickReminderTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: reminderTime,
    );
    if (picked != null) {
      onReminderTimeChanged(picked);
    }
  }

  Future<void> _pickDaysBefore(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) => _EditDaysBeforeDialog(initialDays: reminderDaysBefore),
    );
    if (result != null && result != reminderDaysBefore) {
      onReminderDaysBeforeChanged(result);
    }
  }

  String _daysBeforeSubtitle() {
    if (reminderDaysBefore == 0) {
      return 'Only on the due date';
    }
    final dayWord = reminderDaysBefore == 1 ? 'day' : 'days';
    return '$reminderDaysBefore $dayWord before, every day until done';
  }

  Future<void> _pickTimerSound(BuildContext context) async {
    // Alerts (and the preview) can't show without notification permission.
    final granted = await onRequestNotificationPermission();
    if (!granted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Notifications are off for this app. Enable them in system settings to get timer alerts.",
            ),
          ),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _TimerSoundSheet(
        initialSoundId: timerSoundId,
        onSelected: onTimerSoundChanged,
        onPreview: onPreviewTimerSound,
      ),
    );
  }

  Future<void> _confirmClearTasks(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all tasks?'),
        content: Text(
          taskCount == 0
              ? 'You have no tasks to clear.'
              : 'This will permanently delete all $taskCount task${taskCount == 1 ? '' : 's'}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: taskCount == 0 ? null : () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final cleared = await onClearAllTasks();
      if (cleared && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All tasks cleared')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: Icon(_themeModeIcon(themeMode)),
            title: const Text('Theme'),
            subtitle: Text(_themeModeLabel(themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showThemePicker(context),
          ),
          const Divider(height: 32),
          const _SectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Due date reminders'),
            subtitle: Text(
              remindersEnabled
                  ? 'Reminds you at ${reminderTime.format(context)}'
                  : 'Get notified as a task\'s due date approaches',
            ),
            value: remindersEnabled,
            onChanged: (value) => _handleRemindersToggled(context, value),
          ),
          if (remindersEnabled) ...[
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('Reminder time'),
              subtitle: Text(reminderTime.format(context)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickReminderTime(context),
            ),
            ListTile(
              leading: const Icon(Icons.date_range),
              title: const Text('Remind me starting'),
              subtitle: Text(_daysBeforeSubtitle()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickDaysBefore(context),
            ),
          ],
          const Divider(height: 32),
          const _SectionHeader('Timer alert'),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('Alert sound'),
            subtitle: Text(
              '${NotificationService.soundById(timerSoundId).label} — plays when a timed task reaches its target',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTimerSound(context),
          ),
          const Divider(height: 32),
          const _SectionHeader('Data'),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Clear all tasks'),
            subtitle: Text(
              '$taskCount task${taskCount == 1 ? '' : 's'} stored on this device',
            ),
            onTap: () => _confirmClearTasks(context),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// Owns its own controller so it is disposed together with the dialog route,
// after the closing animation has finished — same pattern as ProfileScreen's
// name-edit dialog.
class _EditDaysBeforeDialog extends StatefulWidget {
  final int initialDays;

  const _EditDaysBeforeDialog({required this.initialDays});

  @override
  State<_EditDaysBeforeDialog> createState() => _EditDaysBeforeDialogState();
}

class _EditDaysBeforeDialogState extends State<_EditDaysBeforeDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialDays.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null) return;
    final clamped = parsed.clamp(0, NotificationService.maxDaysBefore).toInt();
    Navigator.pop(context, clamped);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remind me starting'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Days before the due date (0-${NotificationService.maxDaysBefore}). '
            "You'll get a reminder every day in that window until the task is marked done.",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Lets the person try each sound with the play button and pick one with the
// radio button. Keeps its own selection so the check mark updates instantly
// while the sheet is open.
class _TimerSoundSheet extends StatefulWidget {
  final String initialSoundId;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onPreview;

  const _TimerSoundSheet({
    required this.initialSoundId,
    required this.onSelected,
    required this.onPreview,
  });

  @override
  State<_TimerSoundSheet> createState() => _TimerSoundSheetState();
}

class _TimerSoundSheetState extends State<_TimerSoundSheet> {
  late String _selectedId = widget.initialSoundId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: RadioGroup<String>(
          groupValue: _selectedId,
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _selectedId = value;
            });
            widget.onSelected(value);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  'Timer alert sound',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Tap the play button to hear a sound, then select the one you want.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              ...NotificationService.timerSounds.map((sound) {
                return RadioListTile<String>(
                  value: sound.id,
                  title: Text(sound.label),
                  secondary: IconButton(
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Preview',
                    onPressed: () => widget.onPreview(sound.id),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}