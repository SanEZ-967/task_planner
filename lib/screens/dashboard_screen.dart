import 'dart:math';
import 'package:flutter/material.dart';
import '../models/task.dart';

class _OverallStats {
  final int currentStreak;
  final int bestStreak;
  final int totalCompleted;
  final int totalTasks;
  final int totalPerfectDays;
  final int monthPerfectDays;

  _OverallStats({
    required this.currentStreak,
    required this.bestStreak,
    required this.totalCompleted,
    required this.totalTasks,
    required this.totalPerfectDays,
    required this.monthPerfectDays,
  });
}

class DashboardScreen extends StatefulWidget {
  final List<Task> tasks;
  final String username;
  final ValueChanged<Task> onTaskChanged;
  final VoidCallback onSeeAllTasks;

  const DashboardScreen({
    super.key,
    required this.tasks,
    required this.username,
    required this.onTaskChanged,
    required this.onSeeAllTasks,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;
  DateTime _weekStartDate = DateTime.now();

  static const List<String> _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static const List<String> _weekdayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  String _getMonthYearLabel() {
    return '${_monthNames[_selectedMonth - 1]} $_selectedYear';
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
      });
    }
  }

  Future<void> _pickWeekStart() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _weekStartDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null) {
      setState(() {
        _weekStartDate = pickedDate;
      });
    }
  }

  Widget _buildQuickStat({required String label, required String value, required IconData icon}) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: colors.primaryContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodayTaskRow(Task task, DateTime todayDate) {
    final isDone = task.isDoneOn(todayDate);
    final canToggle = !task.isRecurring || task.occursOn(todayDate);

    Widget leading;
    if (task.isTimeBased) {
      leading = Icon(
        isDone ? Icons.check_circle : Icons.timer_outlined,
        color: isDone ? Colors.green : Colors.grey,
      );
    } else if (task.isCountBased) {
      final count = task.countOn(todayDate);
      leading = CircleAvatar(
        radius: 15,
        backgroundColor: isDone ? Colors.green : Colors.grey[300],
        child: Text(
          '$count/${task.targetCount}',
          style: TextStyle(
            fontSize: 9,
            color: isDone ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else {
      leading = Checkbox(
        value: isDone,
        onChanged: canToggle
            ? (value) {
                setState(() {
                  task.setDoneOn(todayDate, value!);
                });
                widget.onTaskChanged(task);
              }
            : null,
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: leading,
      title: Text(
        task.title,
        style: TextStyle(decoration: isDone ? TextDecoration.lineThrough : null),
      ),
    );
  }

  Widget _buildTodaySection(DateTime todayDate) {
    final todaysTasks = widget.tasks.where((t) => t.isActiveOn(todayDate)).toList()
      ..sort((a, b) {
        final aDone = a.isDoneOn(todayDate);
        final bDone = b.isDoneOn(todayDate);
        if (aDone == bDone) return 0;
        return aDone ? 1 : -1;
      });

    if (todaysTasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.celebration_outlined, size: 36, color: Colors.grey[400]),
              const SizedBox(height: 8),
              const Text(
                'Nothing due today — enjoy the clear day!',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final previewTasks = todaysTasks.take(5).toList();

    return Column(
      children: [
        ...previewTasks.map((task) => _buildTodayTaskRow(task, todayDate)),
        if (todaysTasks.length > 5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '+ ${todaysTasks.length - 5} more today',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.onSeeAllTasks,
            child: const Text('See all tasks'),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required int count,
    required int total,
  }) {
    final percent = total == 0 ? 0 : ((count / total) * 100).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label: $count ($percent%)', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildMonthPieChart(int ongoing, int completed, int total) {
    return Column(
      children: [
        SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(160, 160),
                painter: _DonutChartPainter(ongoing: ongoing, completed: completed),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const Text('total', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegendItem(color: Colors.red, label: 'Ongoing', count: ongoing, total: total),
            const SizedBox(width: 24),
            _buildLegendItem(color: Colors.green, label: 'Completed', count: completed, total: total),
          ],
        ),
      ],
    );
  }

  Widget _buildWeeklyChart() {
    const maxBarHeight = 150.0;
    final weekDates = List.generate(7, (i) => _weekStartDate.add(Duration(days: i)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 36,
              height: maxBarHeight,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('100%', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('75%', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('50%', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('25%', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  Text('0%', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: weekDates.map((date) => _buildDayBar(date, maxBarHeight)).toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const SizedBox(width: 44),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: weekDates
                    .map((date) => SizedBox(
                          width: 28,
                          child: Center(
                            child: Text(
                              _weekdayNames[date.weekday - 1],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 12, height: 12, color: Colors.green),
            const SizedBox(width: 6),
            const Text('Completed'),
            const SizedBox(width: 20),
            Container(width: 12, height: 12, color: Colors.red),
            const SizedBox(width: 6),
            const Text('Ongoing'),
          ],
        ),
      ],
    );
  }

  Widget _buildDayBar(DateTime date, double maxBarHeight) {
    const barWidth = 28.0;

    // A day that hasn't happened yet can't be complete or incomplete, so it
    // gets an empty slot (same width, so the other bars stay where they are).
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    if (DateTime(date.year, date.month, date.day).isAfter(todayDate)) {
      return SizedBox(width: barWidth, height: maxBarHeight);
    }

    final tasksForDay = widget.tasks.where((task) => task.isActiveOn(date)).toList();

    final total = tasksForDay.length;
    final completed = tasksForDay.where((t) => t.completedOn(date)).length;
    final ongoing = total - completed;

    final completedPercent = total == 0 ? 0.0 : completed / total;
    final ongoingPercent = total == 0 ? 0.0 : ongoing / total;

    return SizedBox(
      width: barWidth,
      height: maxBarHeight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(width: barWidth, height: maxBarHeight * ongoingPercent, color: Colors.red),
          Container(width: barWidth, height: maxBarHeight * completedPercent, color: Colors.green),
        ],
      ),
    );
  }

  Widget _buildWeekSummary(List<DateTime> weekDates) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    final arrivedDates = weekDates.where((date) {
      final compareDate = DateTime(date.year, date.month, date.day);
      return !compareDate.isAfter(todayDate);
    }).toList();

    double percentSum = 0;
    int daysWithTasks = 0;
    final completedTaskIds = <String>{};

    for (final date in arrivedDates) {
      final tasksForDay = widget.tasks.where((task) => task.isActiveOn(date)).toList();
      if (tasksForDay.isEmpty) continue;

      final completed = tasksForDay.where((task) => task.completedOn(date)).length;
      percentSum += completed / tasksForDay.length;
      daysWithTasks++;

      for (final task in tasksForDay) {
        if (task.completedOn(date)) {
          completedTaskIds.add(task.id);
        }
      }
    }

    final hasData = daysWithTasks > 0;
    final averageRatePercent = hasData ? ((percentSum / daysWithTasks) * 100).round() : 0;

    return Row(
      children: [
        _buildQuickStat(
          label: 'Avg rate (week)',
          value: hasData ? '$averageRatePercent%' : 'N/A',
          icon: Icons.percent,
        ),
        const SizedBox(width: 12),
        _buildQuickStat(
          label: 'Completed (week)',
          value: '${completedTaskIds.length}',
          icon: Icons.done_all,
        ),
      ],
    );
  }

  _OverallStats _computeOverallStats() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    DateTime? earliestDate;
    for (final task in widget.tasks) {
      if (earliestDate == null || task.startDay.isBefore(earliestDate)) {
        earliestDate = task.startDay;
      }
    }
    earliestDate ??= todayDate;

    int bestStreak = 0;
    int runningStreak = 0;
    int totalPerfectDays = 0;
    int monthPerfectDays = 0;

    DateTime cursor = earliestDate;
    while (!cursor.isAfter(todayDate)) {
      final tasksForDay = widget.tasks.where((task) => task.isActiveOn(cursor)).toList();

      if (tasksForDay.isNotEmpty) {
        final isPerfectDay = tasksForDay.every((task) => task.completedOn(cursor));
        if (isPerfectDay) {
          runningStreak++;
          totalPerfectDays++;
          if (cursor.month == _selectedMonth && cursor.year == _selectedYear) {
            monthPerfectDays++;
          }
          if (runningStreak > bestStreak) {
            bestStreak = runningStreak;
          }
        } else {
          // Today still has unfinished tasks, but the day isn't over yet, so
          // it shouldn't wipe out the streak built up through yesterday.
          final isToday = cursor.year == todayDate.year &&
              cursor.month == todayDate.month &&
              cursor.day == todayDate.day;
          if (!isToday) {
            runningStreak = 0;
          }
        }
      }

      cursor = cursor.add(const Duration(days: 1));
    }

    // A one-off task counts once. A repeating task never sets isDone (it tracks
    // completion per day), so it counts once per scheduled day instead: a daily
    // task done on 5 of its 7 days adds 5 completed out of 7.
    int totalCompleted = 0;
    int totalTasks = 0;
    for (final task in widget.tasks) {
      if (task.isRecurring) {
        totalCompleted += task.recurringCompletedCount;
        totalTasks += task.recurringTotalCount;
      } else {
        totalTasks++;
        if (task.isDone) totalCompleted++;
      }
    }

    return _OverallStats(
      currentStreak: runningStreak,
      bestStreak: bestStreak,
      totalCompleted: totalCompleted,
      totalTasks: totalTasks,
      totalPerfectDays: totalPerfectDays,
      monthPerfectDays: monthPerfectDays,
    );
  }

  Widget _buildOverallStatsSection(_OverallStats stats) {
    final rate = stats.totalTasks == 0 ? 0 : ((stats.totalCompleted / stats.totalTasks) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('All-Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildQuickStat(
              label: 'Best Streak',
              value: '${stats.bestStreak}',
              icon: Icons.emoji_events,
            ),
            const SizedBox(width: 12),
            _buildQuickStat(
              label: 'Total Completed',
              value: '${stats.totalCompleted}',
              icon: Icons.check_circle,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildQuickStat(
              label: 'Completion Rate',
              value: '$rate%',
              icon: Icons.insights,
            ),
            const SizedBox(width: 12),
            _buildQuickStat(
              label: 'Perfect Days',
              value: '${stats.totalPerfectDays}',
              icon: Icons.star,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final stats = _computeOverallStats();

    final tasksThisMonth = widget.tasks.where((task) {
      if (task.dueDate == null) return true;
      return task.dueDate!.month == _selectedMonth && task.dueDate!.year == _selectedYear;
    }).toList();

    final completedCount =
        tasksThisMonth.where((task) => task.completedInMonth(_selectedMonth, _selectedYear)).length;
    final ongoingCount = tasksThisMonth.length - completedCount;
    final totalCount = tasksThisMonth.length;

    final todaysActive = widget.tasks.where((t) => t.isActiveOn(todayDate)).toList();
    final todaysDone = todaysActive.where((t) => t.isDoneOn(todayDate)).length;

    final weekDates = List.generate(7, (i) => _weekStartDate.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_getGreeting()}, ${widget.username}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              "Let's keep productive!",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Today', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildQuickStat(
                    label: 'Done today',
                    value: '$todaysDone/${todaysActive.length}',
                    icon: Icons.task_alt,
                  ),
                  const SizedBox(width: 12),
                  _buildQuickStat(
                    label: 'Current streak',
                    value: '${stats.currentStreak}',
                    icon: Icons.local_fire_department,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTodaySection(todayDate),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text('This Month', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
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
              const SizedBox(height: 4),
              Text(
                '${stats.monthPerfectDays} perfect day${stats.monthPerfectDays == 1 ? "" : "s"} this month',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Center(child: _buildMonthPieChart(ongoingCount, completedCount, totalCount)),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text('This Week', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickWeekStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Week of ${_weekStartDate.day}/${_weekStartDate.month}/${_weekStartDate.year}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildWeeklyChart(),
              const SizedBox(height: 16),
              _buildWeekSummary(weekDates),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              _buildOverallStatsSection(stats),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final int ongoing;
  final int completed;

  _DonutChartPainter({required this.ongoing, required this.completed});

  @override
  void paint(Canvas canvas, Size size) {
    final total = ongoing + completed;
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 24.0;
    final rect = Rect.fromCircle(center: center, radius: size.width / 2 - strokeWidth / 2);

    if (total == 0) {
      final emptyPaint = Paint()
        ..color = Colors.grey[300]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, 0, 2 * pi, false, emptyPaint);
      return;
    }

    final ongoingSweep = 2 * pi * (ongoing / total);
    final completedSweep = 2 * pi * (completed / total);

    final ongoingPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final completedPaint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    double startAngle = -pi / 2;
    if (ongoing > 0) {
      canvas.drawArc(rect, startAngle, ongoingSweep, false, ongoingPaint);
      startAngle += ongoingSweep;
    }
    if (completed > 0) {
      canvas.drawArc(rect, startAngle, completedSweep, false, completedPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.ongoing != ongoing || oldDelegate.completed != completed;
  }
}