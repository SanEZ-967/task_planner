import 'package:flutter/material.dart';
import '../models/task.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? taskToEdit;

  const AddTaskScreen({super.key, this.taskToEdit});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  static const List<String> _weekdayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _subtaskController = TextEditingController();
  final TextEditingController _hoursController = TextEditingController(text: '0');
  final TextEditingController _minutesController = TextEditingController(text: '0');
  final TextEditingController _countController = TextEditingController(text: '10');
  final TextEditingController _intervalController = TextEditingController(text: '2');
  int _selectedPriority = Task.defaultPriority;
  DateTime? _selectedDueDate;
  late DateTime _selectedStartDate;
  List<Subtask> _subtasks = [];
  bool _isTimeBased = false;
  bool _isCountBased = false;
  RepeatType _repeatType = RepeatType.none;
  final Set<int> _selectedWeekdays = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedStartDate = DateTime(now.year, now.month, now.day);
    if (widget.taskToEdit != null) {
      _selectedStartDate = widget.taskToEdit!.startDay;
      _titleController.text = widget.taskToEdit!.title;
      _descriptionController.text = widget.taskToEdit!.description ?? '';
      _categoryController.text = widget.taskToEdit!.category ?? '';
      _selectedPriority = widget.taskToEdit!.priority;
      _selectedDueDate = widget.taskToEdit!.dueDate;
      // A copy, so adding/removing subtasks and then backing out doesn't change
      // the task itself.
      _subtasks = List<Subtask>.from(widget.taskToEdit!.subtasks);
      _isTimeBased = widget.taskToEdit!.isTimeBased;
      _isCountBased = widget.taskToEdit!.isCountBased;
      _repeatType = widget.taskToEdit!.repeatType;
      _intervalController.text = widget.taskToEdit!.repeatInterval.toString();
      _selectedWeekdays.addAll(widget.taskToEdit!.repeatWeekdays);
      if (_isTimeBased) {
        final totalMinutes = widget.taskToEdit!.targetDurationSeconds ~/ 60;
        _hoursController.text = (totalMinutes ~/ 60).toString();
        _minutesController.text = (totalMinutes % 60).toString();
      }
      if (_isCountBased) {
        _countController.text = widget.taskToEdit!.targetCount.toString();
      }
    }
  }

  Future<void> _pickStartDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedStartDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate == null) return;

    final due = _selectedDueDate;
    final dueIsBeforeStart = due != null &&
        DateTime(due.year, due.month, due.day).isBefore(pickedDate);

    setState(() {
      _selectedStartDate = pickedDate;
      if (dueIsBeforeStart) {
        _selectedDueDate = null;
      }
    });

    if (dueIsBeforeStart && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Due / end date cleared because it was before the new start date'),
        ),
      );
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDueDate ??
          (_selectedStartDate.isAfter(today) ? _selectedStartDate : today),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDueDate = pickedDate;
      });
    }
  }

  void _addSubtask() {
    if (_subtaskController.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _subtasks.add(Subtask(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _subtaskController.text.trim(),
      ));
    });
    _subtaskController.clear();
  }

  void _saveTask() {
    if (_titleController.text.trim().isEmpty) {
      return;
    }

    final dueDate = _selectedDueDate;
    if (dueDate != null &&
        DateTime(dueDate.year, dueDate.month, dueDate.day)
            .isBefore(_selectedStartDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _repeatType == RepeatType.none
                ? "The due date can't be before the start date"
                : "The end date can't be before the start date",
          ),
        ),
      );
      return;
    }

    if (_repeatType == RepeatType.weekdays && _selectedWeekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one day to repeat on')),
      );
      return;
    }

    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    final category = _categoryController.text.trim().isEmpty
        ? null
        : _categoryController.text.trim();

    final isRepeating = _repeatType != RepeatType.none;
    final trackByTime = _isTimeBased && !_isCountBased;
    final trackByCount = _isCountBased && !_isTimeBased;

    final hours = int.tryParse(_hoursController.text) ?? 0;
    final minutes = int.tryParse(_minutesController.text) ?? 0;
    final targetSeconds = trackByTime ? (hours * 3600) + (minutes * 60) : 0;

    // A 0-minute target would mark the task done a second after pressing play.
    if (trackByTime && targetSeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a target time greater than 0')),
      );
      return;
    }

    final targetCount = trackByCount
        ? (int.tryParse(_countController.text) ?? 10).clamp(1, 9999).toInt()
        : 0;

    final repeatInterval =
        (int.tryParse(_intervalController.text) ?? 2).clamp(1, 365).toInt();
    final repeatWeekdays = _repeatType == RepeatType.weekdays
        ? (_selectedWeekdays.toList()..sort())
        : <int>[];

    if (widget.taskToEdit != null) {
      final editedTask = widget.taskToEdit!;
      final wasRepeating = editedTask.isRecurring;
      editedTask.title = _titleController.text.trim();
      editedTask.description = description;
      editedTask.priority = _selectedPriority;
      editedTask.dueDate = _selectedDueDate;
      editedTask.startDate = _selectedStartDate;
      editedTask.category = category;
      editedTask.subtasks = _subtasks;
      // Turning time tracking off must not leave a timer running in the background.
      if (!trackByTime) editedTask.pauseTimer();
      editedTask.isTimeBased = trackByTime;
      editedTask.targetDurationSeconds = targetSeconds;
      editedTask.isCountBased = trackByCount;
      editedTask.targetCount = targetCount;
      editedTask.repeatType = _repeatType;
      editedTask.repeatInterval = repeatInterval;
      editedTask.repeatWeekdays = repeatWeekdays;
      if (!wasRepeating && isRepeating) {
        editedTask.resetCompletion();
      }
      Navigator.pop(context, editedTask);
    } else {
      final newTask = Task(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        description: description,
        priority: _selectedPriority,
        dueDate: _selectedDueDate,
        startDate: _selectedStartDate,
        category: category,
        subtasks: _subtasks,
        isTimeBased: trackByTime,
        targetDurationSeconds: targetSeconds,
        isCountBased: trackByCount,
        targetCount: targetCount,
        repeatType: _repeatType,
        repeatInterval: repeatInterval,
        repeatWeekdays: repeatWeekdays,
      );
      Navigator.pop(context, newTask);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _subtaskController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _countController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Widget _buildRepeatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<RepeatType>(
          initialValue: _repeatType,
          decoration: const InputDecoration(labelText: 'Repeat'),
          items: const [
            DropdownMenuItem<RepeatType>(
              value: RepeatType.none,
              child: Text('Does not repeat'),
            ),
            DropdownMenuItem<RepeatType>(
              value: RepeatType.daily,
              child: Text('Every day'),
            ),
            DropdownMenuItem<RepeatType>(
              value: RepeatType.interval,
              child: Text('Every few days'),
            ),
            DropdownMenuItem<RepeatType>(
              value: RepeatType.weekdays,
              child: Text('Specific days of the week'),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _repeatType = value!;
            });
          },
        ),
        if (_repeatType == RepeatType.interval) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Every'),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              const Text('days'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Counting from the start date',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        if (_repeatType == RepeatType.weekdays) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: List.generate(7, (index) {
              final weekday = index + 1;
              return FilterChip(
                label: Text(_weekdayLabels[index]),
                selected: _selectedWeekdays.contains(weekday),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedWeekdays.add(weekday);
                    } else {
                      _selectedWeekdays.remove(weekday);
                    }
                  });
                },
              );
            }),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRepeating = _repeatType != RepeatType.none;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskToEdit == null ? 'New Task' : 'Edit Task'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Task title'),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                hintText: 'e.g. Work, Personal, Shopping',
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<int>(
              initialValue: _selectedPriority,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: List.generate(
                Task.maxPriority - Task.minPriority + 1,
                (index) {
                  final level = Task.minPriority + index;
                  final label = level == Task.minPriority
                      ? '$level (lowest)'
                      : level == Task.maxPriority
                          ? '$level (highest)'
                          : '$level';
                  return DropdownMenuItem<int>(
                    value: level,
                    child: Text(label),
                  );
                },
              ),
              onChanged: (value) {
                setState(() {
                  _selectedPriority = value!;
                });
              },
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available),
              title: Text(
                'Starts: ${_selectedStartDate.day}/${_selectedStartDate.month}/${_selectedStartDate.year}',
              ),
              subtitle: const Text('Task shows up from this day onward'),
              onTap: _pickStartDate,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(
                _selectedDueDate == null
                    ? (isRepeating ? 'No end date' : 'No due date')
                    : '${isRepeating ? 'Repeats until' : 'Due'}: ${_selectedDueDate!.day}/${_selectedDueDate!.month}/${_selectedDueDate!.year}',
              ),
              trailing: _selectedDueDate == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear date',
                      onPressed: () {
                        setState(() {
                          _selectedDueDate = null;
                        });
                      },
                    ),
              onTap: _pickDueDate,
            ),
            const SizedBox(height: 10),
            _buildRepeatSection(),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Track by time'),
              subtitle: Text(
                _isCountBased
                    ? 'Not available while tracking by count'
                    : isRepeating
                        ? 'Resets each scheduled day — that day completes once you log the target time'
                        : 'Task completes automatically once target time is logged',
              ),
              value: _isTimeBased,
              onChanged: _isCountBased
                  ? null
                  : (value) {
                      setState(() {
                        _isTimeBased = value;
                      });
                    },
            ),
            if (_isTimeBased) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hoursController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Hours'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _minutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutes'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Track by count'),
              subtitle: Text(
                _isTimeBased
                    ? 'Not available while tracking by time'
                    : isRepeating
                        ? 'Resets each scheduled day — that day completes once you hit the target'
                        : 'Task completes automatically once the target count is reached',
              ),
              value: _isCountBased,
              onChanged: _isTimeBased
                  ? null
                  : (value) {
                      setState(() {
                        _isCountBased = value;
                      });
                    },
            ),
            if (_isCountBased) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _countController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target count (e.g. reps)'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap the task to log one rep; hold it down to undo a mis-tap.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Subtasks', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subtaskController,
                    decoration: const InputDecoration(hintText: 'Add a subtask'),
                    onSubmitted: (_) => _addSubtask(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle),
                  onPressed: _addSubtask,
                ),
              ],
            ),
            ..._subtasks.map((subtask) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(subtask.title),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _subtasks.remove(subtask);
                    });
                  },
                ),
              );
            }),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveTask,
              child: Text(widget.taskToEdit == null ? 'Save Task' : 'Update Task'),
            ),
          ],
        ),
      ),
    );
  }
}