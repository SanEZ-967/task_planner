// Priority is a number from Task.minPriority (1, lowest) to Task.maxPriority
// (10, highest). Tasks saved back when it was low/medium/high are mapped onto
// the new scale when they load.
int _priorityFromJson(dynamic value) {
  if (value is int) {
    return value.clamp(Task.minPriority, Task.maxPriority).toInt();
  }
  switch (value) {
    case 'low':
      return 2;
    case 'high':
      return 9;
    default: // 'medium' or anything unrecognised
      return Task.defaultPriority;
  }
}

// none     = normal one-off task
// daily    = every day
// interval = every [repeatInterval] days (counted from the task's start date)
// weekdays = on the days listed in [repeatWeekdays] (DateTime.monday = 1 ... DateTime.sunday = 7)
enum RepeatType { none, daily, interval, weekdays }

class Subtask {
  final String id;
  String title;
  bool isDone;

  Subtask({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isDone': isDone,
    };
  }

  factory Subtask.fromJson(Map<String, dynamic> json) {
    return Subtask(
      id: json['id'],
      title: json['title'],
      isDone: json['isDone'],
    );
  }
}

// "2026-09-21"-style key used to remember which days a repeating task was done.
String _dateKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _subtaskKeyForDay(String dayKey, Subtask subtask) {
  return '$dayKey|${subtask.id}';
}

String _subtaskKey(DateTime date, Subtask subtask) {
  return _subtaskKeyForDay(_dateKey(date), subtask);
}

void _setKey(Set<String> keys, String key, bool present) {
  if (present) {
    keys.add(key);
  } else {
    keys.remove(key);
  }
}

class Task {
  static const int minPriority = 1;
  static const int maxPriority = 10;
  static const int defaultPriority = 5;

  static const List<String> _weekdayShortNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  final String id;
  String title;
  String? description;
  bool isDone;
  int priority;
  DateTime? dueDate;
  // The first day the task is active. null (older tasks) means "the day it was
  // created" - see [startDay].
  DateTime? startDate;
  String? category;
  List<Subtask> subtasks;
  DateTime? completedDate;
  bool isTimeBased;
  int targetDurationSeconds;
  int loggedSeconds;
  DateTime? timerStartedAt;
  bool isCountBased;
  int targetCount;
  int completedCount;

  // Repeating tasks. Completion is tracked per day in [completedDates] (and
  // per subtask in [completedSubtasks]) instead of the single isDone flag.
  // For a recurring + count-based task, [dailyCounts] holds each day's own
  // rep count, and completedDates is kept in sync automatically once that
  // day's count reaches targetCount.
  RepeatType repeatType;
  int repeatInterval;
  List<int> repeatWeekdays;
  Set<String> completedDates;
  Set<String> completedSubtasks;
  Map<String, int> dailyCounts;

  // Repeating + time-based tasks: the seconds logged on each day (finished
  // stretches only; the stretch running right now is added on top, see
  // loggedDurationOn), and which day the running timer is counting towards.
  // The day is fixed when the timer starts, so a session that runs past
  // midnight still counts fully for the day it was started on.
  Map<String, int> dailySeconds;
  String? timerDayKey;

  Task({
    required this.id,
    required this.title,
    this.description,
    this.isDone = false,
    this.priority = defaultPriority,
    this.dueDate,
    this.startDate,
    this.category,
    List<Subtask>? subtasks,
    this.completedDate,
    this.isTimeBased = false,
    this.targetDurationSeconds = 0,
    this.loggedSeconds = 0,
    this.timerStartedAt,
    this.isCountBased = false,
    this.targetCount = 0,
    this.completedCount = 0,
    this.repeatType = RepeatType.none,
    this.repeatInterval = 2,
    List<int>? repeatWeekdays,
    Set<String>? completedDates,
    Set<String>? completedSubtasks,
    Map<String, int>? dailyCounts,
    Map<String, int>? dailySeconds,
    this.timerDayKey,
  })  : subtasks = subtasks ?? [],
        repeatWeekdays = repeatWeekdays ?? <int>[],
        completedDates = completedDates ?? <String>{},
        completedSubtasks = completedSubtasks ?? <String>{},
        dailyCounts = dailyCounts ?? <String, int>{},
        dailySeconds = dailySeconds ?? <String, int>{};

  DateTime get createdDate {
    final millis = int.tryParse(id);
    final moment = millis != null
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : DateTime.now();
    return DateTime(moment.year, moment.month, moment.day);
  }

  /// The first day the task is active (date only). Falls back to the creation
  /// day for tasks saved before start dates existed.
  DateTime get startDay {
    final start = startDate;
    if (start == null) return createdDate;
    return DateTime(start.year, start.month, start.day);
  }

  Duration get targetDuration => Duration(seconds: targetDurationSeconds);

  bool get isTimerRunning => timerStartedAt != null;

  Duration get totalLoggedDuration {
    if (timerStartedAt == null) return Duration(seconds: loggedSeconds);
    return Duration(seconds: loggedSeconds) + DateTime.now().difference(timerStartedAt!);
  }

  /// Time logged towards [date]. For a one-off task that's just the total. For
  /// a repeating task it's that day's own time, including the stretch that is
  /// running right now if the timer is counting towards [date].
  Duration loggedDurationOn(DateTime date) {
    if (!isRecurring) return totalLoggedDuration;
    return _loggedForDayKey(_dateKey(date));
  }

  Duration _loggedForDayKey(String dayKey) {
    var logged = Duration(seconds: dailySeconds[dayKey] ?? 0);
    final startedAt = timerStartedAt;
    if (startedAt != null && timerDayKey == dayKey) {
      logged += DateTime.now().difference(startedAt);
    }
    return logged;
  }

  /// How long the running timer still has to run before it reaches its target
  /// (for a repeating task: the target for the day it is counting towards).
  /// null when no timer is running or that target has already been met.
  Duration? get remainingOnRunningTimer {
    if (!isTimeBased || timerStartedAt == null) return null;
    if (isRecurring) {
      final key = timerDayKey;
      if (key == null || completedDates.contains(key)) return null;
      return targetDuration - _loggedForDayKey(key);
    }
    if (isDone) return null;
    return targetDuration - totalLoggedDuration;
  }

  /// Starts the timer. A repeating task counts the time towards [date], which
  /// must be a day it is scheduled on and not already complete. A one-off task
  /// ignores [date].
  void startTimer([DateTime? date]) {
    if (!isTimeBased || timerStartedAt != null) return;
    if (isRecurring) {
      final day = date ?? DateTime.now();
      if (!occursOn(day) || completedOn(day)) return;
      timerDayKey = _dateKey(day);
    } else if (isDone) {
      return;
    }
    timerStartedAt = DateTime.now();
  }

  void pauseTimer() {
    if (timerStartedAt != null) {
      final elapsed = DateTime.now().difference(timerStartedAt!).inSeconds;
      final dayKey = timerDayKey;
      if (isRecurring && dayKey != null) {
        dailySeconds[dayKey] = (dailySeconds[dayKey] ?? 0) + elapsed;
      } else {
        loggedSeconds += elapsed;
      }
      timerStartedAt = null;
      timerDayKey = null;
    }
  }

  // Repeating + time-based: once the running timer has logged the day's target,
  // stop it and mark that day (and its subtasks) complete.
  void _checkRecurringTimerComplete() {
    final key = timerDayKey;
    if (key == null || timerStartedAt == null || targetDurationSeconds <= 0) return;
    if (_loggedForDayKey(key) < targetDuration) return;
    pauseTimer();
    _setKey(completedDates, key, true);
    for (final subtask in subtasks) {
      _setKey(completedSubtasks, _subtaskKeyForDay(key, subtask), true);
    }
  }

  void incrementCount() {
    if (isCountBased && !isDone) {
      completedCount++;
      checkAutoComplete();
    }
  }

  void decrementCount() {
    if (isCountBased && completedCount > 0) {
      completedCount--;
      if (isDone && completedCount < targetCount) {
        isDone = false;
        completedDate = null;
        for (final subtask in subtasks) {
          subtask.isDone = false;
        }
      }
    }
  }

  /// For a count-based task: how many reps have been logged. For a recurring
  /// one, this is [date]'s own count; for a one-off task, it's the single
  /// lifetime count.
  int countOn(DateTime date) {
    if (!isRecurring) return completedCount;
    return dailyCounts[_dateKey(date)] ?? 0;
  }

  /// Logs one rep on [date] for a recurring, count-based task, marking that
  /// day complete the moment its count reaches the target.
  void incrementCountOn(DateTime date) {
    final key = _dateKey(date);
    final updated = (dailyCounts[key] ?? 0) + 1;
    dailyCounts[key] = updated;
    _setKey(completedDates, key, updated >= targetCount);
  }

  /// Undoes one rep on [date], correctly un-completing that day if it had
  /// already reached the target.
  void decrementCountOn(DateTime date) {
    final key = _dateKey(date);
    final current = dailyCounts[key] ?? 0;
    if (current > 0) {
      final updated = current - 1;
      dailyCounts[key] = updated;
      _setKey(completedDates, key, updated >= targetCount);
    }
  }

  void checkAutoComplete() {
    if (isTimeBased && isRecurring) {
      _checkRecurringTimerComplete();
      return;
    }
    if (isTimeBased && !isDone && totalLoggedDuration >= targetDuration) {
      pauseTimer();
      isDone = true;
      completedDate = DateTime.now();
      for (final subtask in subtasks) {
        subtask.isDone = true;
      }
    }
    if (isCountBased && !isDone && targetCount > 0 && completedCount >= targetCount) {
      isDone = true;
      completedDate = DateTime.now();
      for (final subtask in subtasks) {
        subtask.isDone = true;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Repeating tasks
  // ---------------------------------------------------------------------------

  bool get isRecurring => repeatType != RepeatType.none;

  /// Whether a repeating task is scheduled on [date] (always false for
  /// one-off tasks).
  bool occursOn(DateTime date) {
    if (!isRecurring) return false;

    final day = DateTime(date.year, date.month, date.day);
    if (day.isBefore(startDay)) return false;

    // The deadline doubles as the end date: no occurrences after it.
    final deadline = dueDate;
    if (deadline != null &&
        day.isAfter(DateTime(deadline.year, deadline.month, deadline.day))) {
      return false;
    }

    switch (repeatType) {
      case RepeatType.none:
        return false;
      case RepeatType.daily:
        return true;
      case RepeatType.interval:
        final interval = repeatInterval < 1 ? 1 : repeatInterval;
        // UTC dates keep the day count exact across daylight-saving changes.
        final start = startDay;
        final daysSinceStart = DateTime.utc(day.year, day.month, day.day)
            .difference(DateTime.utc(start.year, start.month, start.day))
            .inDays;
        return daysSinceStart % interval == 0;
      case RepeatType.weekdays:
        return repeatWeekdays.contains(day.weekday);
    }
  }

  /// Short description of the repeat rule, e.g. "Every day", "Every 3 days",
  /// "Every Mon, Wed, Fri". Empty for one-off tasks.
  String get repeatSummary {
    switch (repeatType) {
      case RepeatType.none:
        return '';
      case RepeatType.daily:
        return 'Every day';
      case RepeatType.interval:
        return repeatInterval <= 1 ? 'Every day' : 'Every $repeatInterval days';
      case RepeatType.weekdays:
        final days = List<int>.from(repeatWeekdays)..sort();
        if (days.length == 7) return 'Every day';
        return 'Every ${days.map((d) => _weekdayShortNames[d - 1]).join(', ')}';
    }
  }

  /// For a recurring task: how many of its scheduled days from creation
  /// through today have actually been completed.
  int get recurringCompletedCount {
    if (!isRecurring) return 0;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    int completed = 0;
    DateTime cursor = startDay;
    while (!cursor.isAfter(todayDate)) {
      if (occursOn(cursor) && completedOn(cursor)) completed++;
      cursor = cursor.add(const Duration(days: 1));
    }
    return completed;
  }

  /// For a recurring task: how many days it has been scheduled to occur on,
  /// from creation through today.
  int get recurringTotalCount {
    if (!isRecurring) return 0;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    int total = 0;
    DateTime cursor = startDay;
    while (!cursor.isAfter(todayDate)) {
      if (occursOn(cursor)) total++;
      cursor = cursor.add(const Duration(days: 1));
    }
    return total;
  }

  /// Whether the task counts as done when looking at [date]. For repeating
  /// tasks this is per day; [date] may be null when no specific day is in view.
  bool isDoneOn(DateTime? date) {
    if (isRecurring) return date != null && completedOn(date);
    return isDone;
  }

  bool isSubtaskDoneOn(Subtask subtask, DateTime? date) {
    if (isRecurring) {
      return date != null && completedSubtasks.contains(_subtaskKey(date, subtask));
    }
    return subtask.isDone;
  }

  /// Marks the task (and all its subtasks) done or not done. Repeating tasks
  /// are only affected for [date]; one-off tasks ignore [date]. Not used for
  /// count-based recurring tasks — those go through incrementCountOn instead.
  void setDoneOn(DateTime date, bool value) {
    if (isRecurring) {
      _setKey(completedDates, _dateKey(date), value);
      for (final subtask in subtasks) {
        _setKey(completedSubtasks, _subtaskKey(date, subtask), value);
      }
    } else {
      isDone = value;
      completedDate = value ? DateTime.now() : null;
      for (final subtask in subtasks) {
        subtask.isDone = value;
      }
    }
  }

  /// Marks one subtask done or not done, and completes/uncompletes the task
  /// once every subtask is done.
  void setSubtaskDoneOn(Subtask subtask, DateTime date, bool value) {
    if (isRecurring) {
      _setKey(completedSubtasks, _subtaskKey(date, subtask), value);
      final allDone = subtasks.every(
        (s) => completedSubtasks.contains(_subtaskKey(date, s)),
      );
      _setKey(completedDates, _dateKey(date), allDone);
    } else {
      subtask.isDone = value;
      isDone = subtasks.every((s) => s.isDone);
      completedDate = isDone ? DateTime.now() : null;
    }
  }

  /// Clears all completion state. Used when a one-off task is turned into a
  /// repeating one so it starts fresh.
  void resetCompletion() {
    isDone = false;
    completedDate = null;
    for (final subtask in subtasks) {
      subtask.isDone = false;
    }
    completedDates.clear();
    completedSubtasks.clear();
    completedCount = 0;
    dailyCounts.clear();
    loggedSeconds = 0;
    timerStartedAt = null;
    timerDayKey = null;
    dailySeconds.clear();
  }

  // ---------------------------------------------------------------------------

  bool isActiveOn(DateTime date) {
    if (isRecurring) return occursOn(date);

    final targetDate = DateTime(date.year, date.month, date.day);
    if (targetDate.isBefore(startDay)) return false;

    if (isDone) {
      if (completedDate == null) return false;
      final completedDay = DateTime(completedDate!.year, completedDate!.month, completedDate!.day);
      return !targetDate.isAfter(completedDay);
    }

    return true;
  }

  bool completedOn(DateTime date) {
    if (isRecurring) return completedDates.contains(_dateKey(date));

    if (!isDone || completedDate == null) return false;
    final completedDay = DateTime(completedDate!.year, completedDate!.month, completedDate!.day);
    final targetDate = DateTime(date.year, date.month, date.day);
    return targetDate == completedDay;
  }

  bool completedInMonth(int month, int year) {
    if (isRecurring) {
      final prefix = '$year-${month.toString().padLeft(2, '0')}-';
      return completedDates.any((key) => key.startsWith(prefix));
    }

    if (!isDone || completedDate == null) return false;
    return completedDate!.month == month && completedDate!.year == year;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isDone': isDone,
      'priority': priority,
      'dueDate': dueDate?.toIso8601String(),
      'startDate': startDate?.toIso8601String(),
      'category': category,
      'subtasks': subtasks.map((s) => s.toJson()).toList(),
      'completedDate': completedDate?.toIso8601String(),
      'isTimeBased': isTimeBased,
      'targetDurationSeconds': targetDurationSeconds,
      'loggedSeconds': loggedSeconds,
      'timerStartedAt': timerStartedAt?.toIso8601String(),
      'isCountBased': isCountBased,
      'targetCount': targetCount,
      'completedCount': completedCount,
      'repeatType': repeatType.name,
      'repeatInterval': repeatInterval,
      'repeatWeekdays': repeatWeekdays,
      'completedDates': completedDates.toList(),
      'completedSubtasks': completedSubtasks.toList(),
      'dailyCounts': dailyCounts,
      'dailySeconds': dailySeconds,
      'timerDayKey': timerDayKey,
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      isDone: json['isDone'],
      priority: _priorityFromJson(json['priority']),
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      // Tasks saved before start dates existed have no startDate key.
      startDate:
          json['startDate'] != null ? DateTime.parse(json['startDate']) : null,
      category: json['category'],
      subtasks: json['subtasks'] != null
          ? (json['subtasks'] as List).map((s) => Subtask.fromJson(s)).toList()
          : [],
      completedDate: json['completedDate'] != null
          ? DateTime.parse(json['completedDate'])
          : null,
      isTimeBased: json['isTimeBased'] ?? false,
      targetDurationSeconds: json['targetDurationSeconds'] ?? 0,
      loggedSeconds: json['loggedSeconds'] ?? 0,
      timerStartedAt: json['timerStartedAt'] != null
          ? DateTime.parse(json['timerStartedAt'])
          : null,
      isCountBased: json['isCountBased'] ?? false,
      targetCount: json['targetCount'] ?? 0,
      completedCount: json['completedCount'] ?? 0,
      // Tasks saved before repeating existed have none of these keys.
      repeatType: RepeatType.values.byName(json['repeatType'] ?? 'none'),
      repeatInterval: json['repeatInterval'] ?? 2,
      repeatWeekdays: json['repeatWeekdays'] != null
          ? (json['repeatWeekdays'] as List).map((d) => d as int).toList()
          : <int>[],
      completedDates: json['completedDates'] != null
          ? (json['completedDates'] as List).map((d) => d as String).toSet()
          : <String>{},
      completedSubtasks: json['completedSubtasks'] != null
          ? (json['completedSubtasks'] as List).map((d) => d as String).toSet()
          : <String>{},

      dailyCounts: json['dailyCounts'] != null
          ? (json['dailyCounts'] as Map).map(
              (key, value) => MapEntry(key as String, (value as num).toInt()),
            )
          : <String, int>{},
      dailySeconds: json['dailySeconds'] != null
          ? (json['dailySeconds'] as Map).map(
              (key, value) => MapEntry(key as String, (value as num).toInt()),
            )
          : <String, int>{},
      timerDayKey: json['timerDayKey'],
    );
  }
}