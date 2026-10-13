import 'dart:async';
import 'package:flutter/material.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import 'add_task_screen.dart';

enum SortOption { none, priorityHighToLow, dueDateSoonest, alphabetical }

class TaskListScreen extends StatefulWidget {
  final List<Task> tasks;
  final ValueChanged<Task> onTaskChanged;
  final ValueChanged<Task> onTaskDeleted;

  const TaskListScreen({
    super.key,
    required this.tasks,
    required this.onTaskChanged,
    required this.onTaskDeleted,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  int? _selectedDay;
  SortOption _sortOption = SortOption.none;
  Timer? _tickTimer;

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const List<String> _weekdayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final runningTasks = widget.tasks.where((task) => task.isTimerRunning).toList();
      if (runningTasks.isEmpty) return;

      final justCompleted = <Task>[];
      setState(() {
        for (final task in runningTasks) {
          final wasRunning = task.isTimerRunning;
          task.checkAutoComplete();
          // Reaching the target stops the timer, for one-off and repeating tasks alike.
          if (wasRunning && !task.isTimerRunning) {
            justCompleted.add(task);
          }
        }
      });
      for (final task in justCompleted) {
        // Deliberately NOT cancelling the timer alert here: the scheduled
        // notification is what plays the sound, and cancelling it as the
        // timer finishes (which is what used to happen) silenced the alarm.
        widget.onTaskChanged(task);
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _getMonthYearLabel() {
    return '${_monthNames[_selectedMonth - 1]} $_selectedYear';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  String _sortOptionLabel(SortOption option) {
    switch (option) {
      case SortOption.none:
        return 'Default order';
      case SortOption.priorityHighToLow:
        return 'Priority (high to low)';
      case SortOption.dueDateSoonest:
        return 'Due date (soonest first)';
      case SortOption.alphabetical:
        return 'Alphabetical (A-Z)';
    }
  }

  List<Task> _applySorting(List<Task> tasks) {
    final sorted = List<Task>.from(tasks);
    switch (_sortOption) {
      case SortOption.none:
        break;
      case SortOption.priorityHighToLow:
        sorted.sort((a, b) => b.priority.compareTo(a.priority));
        break;
      case SortOption.dueDateSoonest:
        sorted.sort((a, b) {
          if (a.dueDate == null && b.dueDate == null) return 0;
          if (a.dueDate == null) return 1;
          if (b.dueDate == null) return -1;
          return a.dueDate!.compareTo(b.dueDate!);
        });
        break;
      case SortOption.alphabetical:
        sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return sorted;
  }

  Future<void> _pickMonthYear() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(_selectedYear, _selectedMonth),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (pickedDate != null) {
      setState(() {
        _selectedMonth = pickedDate.month;
        _selectedYear = pickedDate.year;
        _selectedDay = null;
      });
    }
  }

  Widget _buildDateStrip() {
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final itemWidth = MediaQuery.of(context).size.width / 5;

    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: daysInMonth,
        itemBuilder: (context, index) {
          final day = index + 1;
          final isSelected = day == _selectedDay;
          final weekday = DateTime(_selectedYear, _selectedMonth, day).weekday;
          final weekdayLabel = _weekdayNames[weekday - 1];

          return SizedBox(
            width: itemWidth,
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedDay = isSelected ? null : day;
                });
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey[300],
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    weekdayLabel,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  DateTime? get _viewDate {
    if (_selectedDay != null) {
      return DateTime(_selectedYear, _selectedMonth, _selectedDay!);
    }
    final now = DateTime.now();
    if (_selectedYear == now.year && _selectedMonth == now.month) {
      return DateTime(now.year, now.month, now.day);
    }
    return null;
  }

  bool _canToggle(Task task) {
    if (!task.isRecurring) return true;
    final date = _viewDate;
    return date != null && task.occursOn(date);
  }

  Widget _buildSquareBadge({required IconData icon, required bool filled}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: filled ? colors.primary : Colors.transparent,
        border: Border.all(color: colors.primary, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        icon,
        size: 16,
        color: filled ? colors.onPrimary : colors.primary,
      ),
    );
  }

  String _buildSubtitle(Task task) {
    final parts = <String>['Priority ${task.priority}'];
    if (task.category != null) {
      parts.add(task.category!);
    }
    if (task.isRecurring) {
      parts.add(task.repeatSummary);
      parts.add('${task.recurringCompletedCount}/${task.recurringTotalCount} days');
      if (!_canToggle(task)) {
        parts.add('Select a day to check off');
      }
    }
    final now = DateTime.now();
    if (task.startDay.isAfter(DateTime(now.year, now.month, now.day))) {
      parts.add(
        'Starts ${task.startDay.day}/${task.startDay.month}/${task.startDay.year}',
      );
    }
    if (task.dueDate != null) {
      final dateLabel = task.isRecurring ? 'Until' : 'Due';
      parts.add(
        '$dateLabel ${task.dueDate!.day}/${task.dueDate!.month}/${task.dueDate!.year}',
      );
    }
    if (task.subtasks.isNotEmpty) {
      final viewDate = _viewDate;
      final doneCount =
          task.subtasks.where((s) => task.isSubtaskDoneOn(s, viewDate)).length;
      parts.add('$doneCount/${task.subtasks.length} subtasks');
    }
    if (task.isTimeBased) {
      parts.add(
        '${_formatDuration(task.loggedDurationOn(_viewDate ?? DateTime.now()))} / ${_formatDuration(task.targetDuration)}',
      );
    }
    if (task.isCountBased) {
      final count = task.countOn(_viewDate ?? DateTime.now());
      parts.add('$count/${task.targetCount} reps');
    }
    return parts.join(' • ');
  }

  Widget _buildSubtitleWidget(Task task) {
    final infoLine = _buildSubtitle(task);
    if (task.description == null || task.description!.trim().isEmpty) {
      return Text(infoLine);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(infoLine),
        const SizedBox(height: 2),
        Text(
          task.description!,
          style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  List<Task> _getFilteredTasks() {
    if (_searchQuery.isNotEmpty) {
      return widget.tasks
          .where((task) =>
              task.title.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    if (_selectedDay != null) {
      final selectedDate = DateTime(_selectedYear, _selectedMonth, _selectedDay!);
      return widget.tasks.where((task) => task.isActiveOn(selectedDate)).toList();
    }

    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    return widget.tasks.where((task) {
      for (int day = 1; day <= daysInMonth; day++) {
        if (task.isActiveOn(DateTime(_selectedYear, _selectedMonth, day))) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _applySorting(_getFilteredTasks());

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 160,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _pickMonthYear,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getMonthYearLabel(),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _buildDateStrip(),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search tasks...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<SortOption>(
                  icon: const Icon(Icons.sort),
                  tooltip: 'Sort tasks',
                  onSelected: (value) {
                    setState(() {
                      _sortOption = value;
                    });
                  },
                  itemBuilder: (context) => SortOption.values.map((option) {
                    return PopupMenuItem<SortOption>(
                      value: option,
                      child: Row(
                        children: [
                          if (_sortOption == option)
                            const Icon(Icons.check, size: 18)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(_sortOptionLabel(option)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: filteredTasks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty ? Icons.checklist : Icons.search_off,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No tasks yet'
                              : 'No tasks match "$_searchQuery"',
                          style: const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        if (_searchQuery.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Tap + to add your first task',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredTasks.length,
                    itemBuilder: (context, index) {
                      final task = filteredTasks[index];
                      final viewDate = _viewDate;
                      final canToggle = _canToggle(task);
                      final isDone = task.isDoneOn(viewDate);

                      final checkbox = Checkbox(
                        value: isDone,
                        onChanged: canToggle
                            ? (value) {
                                setState(() {
                                  task.setDoneOn(viewDate ?? DateTime.now(), value!);
                                });
                                widget.onTaskChanged(task);
                              }
                            : null,
                      );

                      Widget leadingWidget;
                      if (task.isTimeBased) {
                        leadingWidget = isDone
                            ? SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: _buildSquareBadge(icon: Icons.check, filled: true),
                                ),
                              )
                            : IconButton(
                                icon: _buildSquareBadge(
                                  icon: task.isTimerRunning ? Icons.pause : Icons.play_arrow,
                                  filled: task.isTimerRunning,
                                ),
                                // A running timer can always be paused; starting one on a
                                // repeating task needs a day it's scheduled on.
                                onPressed: (task.isTimerRunning || canToggle)
                                    ? () async {
                                        if (task.isTimerRunning) {
                                          setState(() {
                                            task.pauseTimer();
                                          });
                                          await NotificationService.instance
                                              .cancelTimerAlert(task.id);
                                        } else {
                                          await NotificationService.instance
                                              .requestPermissions();
                                          await NotificationService.instance
                                              .requestExactAlarmPermissionOnce();
                                          setState(() {
                                            task.startTimer(viewDate ?? DateTime.now());
                                          });
                                          await NotificationService.instance
                                              .scheduleTimerAlert(task);
                                        }
                                        widget.onTaskChanged(task);
                                      }
                                    : null,
                              );
                      } else if (task.isCountBased) {
                        final canLogReps = task.isRecurring ? canToggle : true;
                        // Looks the same as before (check badge when done, "+"
                        // badge otherwise), but long-press now works in both
                        // states, so a mis-tap on the final rep can be undone.
                        leadingWidget = GestureDetector(
                          onTap: (canLogReps && !isDone)
                              ? () {
                                  setState(() {
                                    if (task.isRecurring) {
                                      task.incrementCountOn(viewDate ?? DateTime.now());
                                    } else {
                                      task.incrementCount();
                                    }
                                  });
                                  widget.onTaskChanged(task);
                                }
                              : null,
                          onLongPress: canLogReps
                              ? () {
                                  setState(() {
                                    if (task.isRecurring) {
                                      task.decrementCountOn(viewDate ?? DateTime.now());
                                    } else {
                                      task.decrementCount();
                                    }
                                  });
                                  widget.onTaskChanged(task);
                                }
                              : null,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: _buildSquareBadge(
                                icon: isDone ? Icons.check : Icons.add,
                                filled: isDone,
                              ),
                            ),
                          ),
                        );
                      } else {
                        leadingWidget = checkbox;
                      }

                      final titleText = Text(
                        task.title,
                        style: TextStyle(
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                      );

                      final editButton = IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final updatedTask = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => AddTaskScreen(taskToEdit: task)),
                          );
                          if (updatedTask != null) {
                            setState(() {
                              final originalIndex = widget.tasks.indexOf(task);
                              widget.tasks[originalIndex] = updatedTask;
                            });
                            if (updatedTask.isTimeBased && updatedTask.isTimerRunning) {
                              await NotificationService.instance.scheduleTimerAlert(updatedTask);
                            } else {
                              await NotificationService.instance.cancelTimerAlert(updatedTask.id);
                            }
                            widget.onTaskChanged(updatedTask);
                          }
                        },
                      );

                      return Dismissible(
                        key: Key(task.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          final removedTask = task;
                          final originalIndex = widget.tasks.indexOf(removedTask);

                          setState(() {
                            widget.tasks.remove(removedTask);
                          });

                          final controller = ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"${removedTask.title}" deleted'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () {
                                  setState(() {
                                    widget.tasks.insert(
                                      originalIndex.clamp(0, widget.tasks.length),
                                      removedTask,
                                    );
                                  });
                                },
                              ),
                            ),
                          );

                          controller.closed.then((reason) {
                            if (reason != SnackBarClosedReason.action) {
                              if (removedTask.isTimerRunning) {
                                NotificationService.instance.cancelTimerAlert(removedTask.id);
                              }
                              widget.onTaskDeleted(removedTask);
                            }
                          });
                        },
                        child: task.subtasks.isEmpty
                            ? ListTile(
                                leading: leadingWidget,
                                title: titleText,
                                subtitle: _buildSubtitleWidget(task),
                                trailing: editButton,
                              )
                            : ExpansionTile(
                                leading: leadingWidget,
                                title: titleText,
                                subtitle: _buildSubtitleWidget(task),
                                trailing: editButton,
                                children: task.subtasks.map((subtask) {
                                  final subtaskDone =
                                      task.isSubtaskDoneOn(subtask, viewDate);
                                  return CheckboxListTile(
                                    contentPadding: const EdgeInsets.only(left: 32),
                                    value: subtaskDone,
                                    title: Text(
                                      subtask.title,
                                      style: TextStyle(
                                        decoration: subtaskDone
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                    onChanged: canToggle
                                        ? (value) {
                                            setState(() {
                                              task.setSubtaskDoneOn(
                                                subtask,
                                                viewDate ?? DateTime.now(),
                                                value!,
                                              );
                                            });
                                            widget.onTaskChanged(task);
                                          }
                                        : null,
                                  );
                                }).toList(),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}