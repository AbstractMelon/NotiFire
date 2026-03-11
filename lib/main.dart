// main.dart - Main entry point for NotiFire app

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initNotifications();
  tz.initializeTimeZones();
  runApp(
    ChangeNotifierProvider(
      create: (context) => ReminderProvider(),
      child: const NotiFire(),
    ),
  );
}

// Models
class Reminder {
  final String id;
  final String title;
  final String description;
  final DateTime dateTime;
  final bool isRepeating;
  final RepeatType repeatType;
  final List<int> repeatDays; // For weekly repeats, days 1-7 (Monday-Sunday)
  final bool isWakeUpReminder;
  bool isCompleted;

  Reminder({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    this.isRepeating = false,
    this.repeatType = RepeatType.daily,
    this.repeatDays = const [],
    this.isWakeUpReminder = false,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dateTime': dateTime.toIso8601String(),
      'isRepeating': isRepeating,
      'repeatType': repeatType.toString(),
      'repeatDays': repeatDays,
      'isWakeUpReminder': isWakeUpReminder,
      'isCompleted': isCompleted,
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      dateTime: DateTime.parse(json['dateTime']),
      isRepeating: json['isRepeating'],
      repeatType: RepeatType.values.firstWhere(
        (e) => e.toString() == json['repeatType'],
        orElse: () => RepeatType.daily,
      ),
      repeatDays: List<int>.from(json['repeatDays']),
      isWakeUpReminder: json['isWakeUpReminder'],
      isCompleted: json['isCompleted'],
    );
  }

  Reminder copyWith({
    String? title,
    String? description,
    DateTime? dateTime,
    bool? isRepeating,
    RepeatType? repeatType,
    List<int>? repeatDays,
    bool? isWakeUpReminder,
    bool? isCompleted,
  }) {
    return Reminder(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      isRepeating: isRepeating ?? this.isRepeating,
      repeatType: repeatType ?? this.repeatType,
      repeatDays: repeatDays ?? this.repeatDays,
      isWakeUpReminder: isWakeUpReminder ?? this.isWakeUpReminder,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }
}

enum RepeatType { daily, weekly, monthly, yearly }

// State Management
class ReminderProvider extends ChangeNotifier {
  List<Reminder> _reminders = [];
  bool _isLoading = true;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  List<Reminder> get reminders => _reminders;
  bool get isLoading => _isLoading;

  ReminderProvider() {
    loadReminders();
  }

  Future<void> loadReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remindersJson = prefs.getStringList('reminders') ?? [];
      _reminders =
          remindersJson
              .map((json) => Reminder.fromJson(jsonDecode(json)))
              .toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('Error loading reminders: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remindersJson =
          _reminders.map((reminder) => jsonEncode(reminder.toJson())).toList();
      await prefs.setStringList('reminders', remindersJson);
    } catch (e) {
      print('Error saving reminders: $e');
    }
  }

  Future<void> addReminder(Reminder reminder) async {
    _reminders.add(reminder);
    await _scheduleNotification(reminder);
    await saveReminders();
    notifyListeners();
  }

  Future<void> updateReminder(Reminder reminder) async {
    final index = _reminders.indexWhere((r) => r.id == reminder.id);
    if (index != -1) {
      _reminders[index] = reminder;
      final int notificationId = reminder.id.hashCode;
      await _cancelNotification(notificationId);
      await _scheduleNotification(reminder);
      await saveReminders();
      notifyListeners();
    }
  }

  Future<void> toggleCompleted(String id) async {
    final index = _reminders.indexWhere((r) => r.id == id);
    if (index != -1) {
      _reminders[index] = _reminders[index].copyWith(
        isCompleted: !_reminders[index].isCompleted,
      );
      await saveReminders();
      notifyListeners();
    }
  }

  Future<void> deleteReminder(String id) async {
    _reminders.removeWhere((reminder) => reminder.id == id);
    await _cancelNotification(int.parse(id));
    await saveReminders();
    notifyListeners();
  }

  Future<void> _scheduleNotification(Reminder reminder) async {
    final int notificationId = reminder.id.hashCode;

    if (reminder.isWakeUpReminder) {
      // For wake-up reminders, we'll use a different approach
      // Store it with a flag and handle it separately
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      'notifire_channel',
      'NotiFire Reminders',
      channelDescription: 'Notifications for NotiFire reminders',
      importance: Importance.max,
      priority: Priority.high,
      color: Colors.deepOrange,
    );

    final platformDetails = NotificationDetails(android: androidDetails);
    final scheduledDate = tz.TZDateTime.from(reminder.dateTime, tz.local);

    if (!Platform.isAndroid && !Platform.isIOS) {
      // On Desktop platforms (Linux/Windows/macOS), fallback to showing immediately
      await flutterLocalNotificationsPlugin.show(
        notificationId,
        reminder.title,
        reminder.description,
        platformDetails,
      );
      return;
    }

    if (reminder.isRepeating) {
      // Handle repeating notifications based on type
      switch (reminder.repeatType) {
        case RepeatType.daily:
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId,
            reminder.title,
            reminder.description,
            scheduledDate,
            platformDetails,
            matchDateTimeComponents: DateTimeComponents.time,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          break;
        case RepeatType.weekly:
          if (reminder.repeatDays.isNotEmpty) {
            for (final day in reminder.repeatDays) {
              await flutterLocalNotificationsPlugin.zonedSchedule(
                notificationId + day, // Use different IDs for each day
                reminder.title,
                reminder.description,
                _nextInstanceOfWeekday(
                  day,
                  scheduledDate.hour,
                  scheduledDate.minute,
                ),
                platformDetails,
                matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              );
            }
          }
          break;
        case RepeatType.monthly:
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId,
            reminder.title,
            reminder.description,
            scheduledDate,
            platformDetails,
            matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          break;
        case RepeatType.yearly:
          await flutterLocalNotificationsPlugin.zonedSchedule(
            notificationId,
            reminder.title,
            reminder.description,
            scheduledDate,
            platformDetails,
            matchDateTimeComponents: DateTimeComponents.dateAndTime,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          );
          break;
      }
    } else {
      // One-time notification
      await flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        reminder.title,
        reminder.description,
        scheduledDate,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> _cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    // For weekly repeating reminders with multiple days
    for (int i = 1; i <= 7; i++) {
      await flutterLocalNotificationsPlugin.cancel(id + i);
    }
  }

  // Helper for getting next instance of a particular weekday
  tz.TZDateTime _nextInstanceOfWeekday(int day, int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    while (scheduledDate.weekday != day) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    return scheduledDate;
  }

  // Methods for wake-up reminder functionality
  Future<void> setWakeUpTime(TimeOfDay time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wakeup_hour', time.hour);
    await prefs.setInt('wakeup_minute', time.minute);

    // Update any wake-up reminders
    for (final reminder in _reminders.where((r) => r.isWakeUpReminder)) {
      final updatedDateTime = DateTime(
        reminder.dateTime.year,
        reminder.dateTime.month,
        reminder.dateTime.day,
        time.hour,
        time.minute,
      );
      await updateReminder(reminder.copyWith(dateTime: updatedDateTime));
    }
  }

  Future<TimeOfDay> getWakeUpTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt('wakeup_hour') ?? 7; // Default 7:00 AM
    final minute = prefs.getInt('wakeup_minute') ?? 0;
    return TimeOfDay(hour: hour, minute: minute);
  }
}

// Notifications setup
Future<void> initNotifications() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final androidInitializationSettings = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  final linuxInitializationSettings = LinuxInitializationSettings(
    defaultActionName: 'Open notification',
  );

  final initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
    linux: linuxInitializationSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

// App Widget
class NotiFire extends StatelessWidget {
  const NotiFire({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NotiFire',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepOrange,
        canvasColor: Color(0xFF121212),
        colorScheme: ColorScheme.dark(
          primary: Colors.deepOrange,
          secondary: Colors.amber,
          surface: Color(0xFF1E1E1E),
          error: Colors.redAccent,
        ),
        appBarTheme: AppBarTheme(backgroundColor: Colors.black, elevation: 0),
        cardTheme: CardTheme(
          color: Color(0xFF1E1E1E),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        textTheme: TextTheme(
          headlineMedium: TextStyle(
            color: Colors.deepOrangeAccent,
            fontWeight: FontWeight.bold,
          ),
          bodyLarge: TextStyle(color: Colors.white),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.amber,
          foregroundColor: Colors.black,
        ),
      ),
      home: HomeScreen(),
    );
  }
}

// Home Screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.local_fire_department, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text(
              'NotiFire',
              style: TextStyle(
                color: Colors.deepOrange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          tabs: [
            Tab(text: 'Active', icon: Icon(Icons.calendar_month_outlined)),
            Tab(text: 'Completed', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (context) => SettingsScreen()));
            },
          ),
        ],
      ),
      body: Consumer<ReminderProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(
              child: CircularProgressIndicator(color: Colors.deepOrange),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: [
              // Active reminders tab
              ReminderList(
                reminders:
                    provider.reminders
                        .where((reminder) => !reminder.isCompleted)
                        .toList(),
              ),
              // Completed reminders tab
              ReminderList(
                reminders:
                    provider.reminders
                        .where((reminder) => reminder.isCompleted)
                        .toList(),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => AddReminderSheet(),
          );
        },
        label: Text('Add Reminder'),
        icon: Icon(Icons.add),
      ),
    );
  }
}

// Reminder List Widget
class ReminderList extends StatelessWidget {
  final List<Reminder> reminders;

  const ReminderList({super.key, required this.reminders});

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_fire_department,
              size: 80,
              color: Colors.grey[700],
            ),
            SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: TextStyle(color: Colors.grey[500], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: reminders.length,
      itemBuilder: (context, index) {
        final reminder = reminders[index];
        return ReminderCard(reminder: reminder);
      },
    );
  }
}

// Reminder Card Widget
class ReminderCard extends StatelessWidget {
  final Reminder reminder;

  const ReminderCard({super.key, required this.reminder});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ReminderProvider>(context, listen: false);

    // Format date and time
    String dateString = DateFormat('EEE, MMM d').format(reminder.dateTime);
    String timeString = DateFormat('h:mm a').format(reminder.dateTime);
    String repeatText = '';

    if (reminder.isRepeating) {
      switch (reminder.repeatType) {
        case RepeatType.daily:
          repeatText = 'Repeats daily';
          break;
        case RepeatType.weekly:
          if (reminder.repeatDays.isNotEmpty) {
            final dayNames = reminder.repeatDays
                .map((day) {
                  switch (day) {
                    case 1:
                      return 'Mon';
                    case 2:
                      return 'Tue';
                    case 3:
                      return 'Wed';
                    case 4:
                      return 'Thu';
                    case 5:
                      return 'Fri';
                    case 6:
                      return 'Sat';
                    case 7:
                      return 'Sun';
                    default:
                      return '';
                  }
                })
                .join(', ');
            repeatText = 'Repeats weekly on $dayNames';
          } else {
            repeatText = 'Repeats weekly';
          }
          break;
        case RepeatType.monthly:
          repeatText = 'Repeats monthly';
          break;
        case RepeatType.yearly:
          repeatText = 'Repeats yearly';
          break;
      }
    }

    if (reminder.isWakeUpReminder) {
      timeString = 'When you wake up';
    }

    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: Dismissible(
        key: Key(reminder.id),
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.only(left: 16),
          child: Icon(Icons.delete, color: Colors.white),
        ),
        secondaryBackground: Container(
          color: Colors.green,
          alignment: Alignment.centerRight,
          padding: EdgeInsets.only(right: 16),
          child: Icon(
            reminder.isCompleted ? Icons.restore : Icons.check,
            color: Colors.white,
          ),
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            // Delete
            return await showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: Color(0xFF1E1E1E),
                  title: Text('Delete Reminder'),
                  content: Text(
                    'Are you sure you want to delete this reminder?',
                  ),
                  actions: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.grey),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    TextButton(
                      child: Text(
                        'Delete',
                        style: TextStyle(color: Colors.red),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                );
              },
            );
          } else {
            // Toggle completed
            provider.toggleCompleted(reminder.id);
            return false;
          }
        },
        onDismissed: (direction) {
          if (direction == DismissDirection.startToEnd) {
            provider.deleteReminder(reminder.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Reminder deleted'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
        child: InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => AddReminderSheet(reminder: reminder),
            );
          },
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors:
                    reminder.isCompleted
                        ? [Color(0xFF2E2E2E), Color(0xFF252525)]
                        : [Color(0xFF3F1500), Color(0xFF2B1500)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      reminder.isWakeUpReminder
                          ? Icons.bedtime
                          : Icons.local_fire_department,
                      color:
                          reminder.isCompleted
                              ? Colors.grey
                              : Colors.deepOrange,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reminder.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              reminder.isCompleted ? Colors.grey : Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        reminder.isCompleted
                            ? Icons.restore
                            : Icons.check_circle_outline,
                        color:
                            reminder.isCompleted ? Colors.grey : Colors.amber,
                      ),
                      onPressed: () => provider.toggleCompleted(reminder.id),
                    ),
                  ],
                ),
                if (reminder.description.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      reminder.description,
                      style: TextStyle(
                        color:
                            reminder.isCompleted
                                ? Colors.grey[600]
                                : Colors.white70,
                      ),
                    ),
                  ),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateString,
                      style: TextStyle(
                        color:
                            reminder.isCompleted
                                ? Colors.grey[600]
                                : Colors.amber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      timeString,
                      style: TextStyle(
                        color:
                            reminder.isCompleted
                                ? Colors.grey[600]
                                : Colors.amber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (repeatText.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      repeatText,
                      style: TextStyle(
                        color:
                            reminder.isCompleted
                                ? Colors.grey[600]
                                : Colors.deepOrangeAccent[100],
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Add/Edit Reminder Sheet
class AddReminderSheet extends StatefulWidget {
  final Reminder? reminder;

  const AddReminderSheet({super.key, this.reminder});

  @override
  _AddReminderSheetState createState() => _AddReminderSheetState();
}

class _AddReminderSheetState extends State<AddReminderSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  bool _isRepeating = false;
  RepeatType _repeatType = RepeatType.daily;
  List<int> _selectedDays = [];
  bool _isWakeUpReminder = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with existing data or defaults
    _titleController = TextEditingController(
      text: widget.reminder?.title ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.reminder?.description ?? '',
    );

    if (widget.reminder != null) {
      _selectedDate = widget.reminder!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.reminder!.dateTime);
      _isRepeating = widget.reminder!.isRepeating;
      _repeatType = widget.reminder!.repeatType;
      _selectedDays = List.from(widget.reminder!.repeatDays);
      _isWakeUpReminder = widget.reminder!.isWakeUpReminder;
    } else {
      _selectedDate = DateTime.now();
      _selectedTime = TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 1)),
      lastDate: DateTime.now().add(Duration(days: 365 * 5)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Colors.deepOrange,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(backgroundColor: Color(0xFF121212)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
        );
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Colors.deepOrange,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(backgroundColor: Color(0xFF121212)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
        _selectedDate = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _saveReminder() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<ReminderProvider>(context, listen: false);

      // Create or update the reminder
      final reminder = Reminder(
        id: widget.reminder?.id ?? const Uuid().v4(),
        title: _titleController.text,
        description: _descriptionController.text,
        dateTime: _selectedDate,
        isRepeating: _isRepeating,
        repeatType: _repeatType,
        repeatDays: _selectedDays,
        isWakeUpReminder: _isWakeUpReminder,
        isCompleted: widget.reminder?.isCompleted ?? false,
      );

      if (widget.reminder == null) {
        await provider.addReminder(reminder);
      } else {
        await provider.updateReminder(reminder);
      }

      if (_isWakeUpReminder) {
        // If this is a wake-up reminder, ensure the wake-up time is set
        final wakeUpTime = TimeOfDay(
          hour: _selectedDate.hour,
          minute: _selectedDate.minute,
        );
        await provider.setWakeUpTime(wakeUpTime);
      }

      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_fire_department, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text(
                      widget.reminder == null
                          ? 'Add Reminder'
                          : 'Edit Reminder',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24),
                TextFormField(
                  controller: _titleController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: TextStyle(color: Colors.amber),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepOrange),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepOrange),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.amber, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    labelStyle: TextStyle(color: Colors.amber),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepOrange),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepOrange),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.amber, width: 2),
                    ),
                  ),
                  maxLines: 3,
                ),
                SizedBox(height: 16),

                // Wake-up reminder toggle
                Container(
                  decoration: BoxDecoration(
                    color: Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bedtime,
                        color:
                            _isWakeUpReminder ? Colors.amber : Colors.grey[600],
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Wake-up Reminder',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Switch(
                        value: _isWakeUpReminder,
                        onChanged: (value) {
                          setState(() {
                            _isWakeUpReminder = value;
                            if (value) {
                              // If wake-up is enabled, disable repeating
                              _isRepeating = false;
                            }
                          });
                        },
                        activeColor: Colors.amber,
                        activeTrackColor: Colors.deepOrange.withOpacity(0.5),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // Only show date/time pickers if not a wake-up reminder
                if (!_isWakeUpReminder)
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _selectDate(context),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Date',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  DateFormat(
                                    'MMM d, yyyy',
                                  ).format(_selectedDate),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _selectTime(context),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'Time',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _selectedTime.format(context),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                // Only show repeating options if not a wake-up reminder
                if (!_isWakeUpReminder) ...[
                  SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.repeat,
                          color: _isRepeating ? Colors.amber : Colors.grey[600],
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Repeating Reminder',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Switch(
                          value: _isRepeating,
                          onChanged: (value) {
                            setState(() {
                              _isRepeating = value;
                            });
                          },
                          activeColor: Colors.amber,
                          activeTrackColor: Colors.deepOrange.withOpacity(0.5),
                        ),
                      ],
                    ),
                  ),
                ],

                // Repeating options
                if (_isRepeating && !_isWakeUpReminder) ...[
                  SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repeat Settings',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRepeatOption(
                                'Daily',
                                RepeatType.daily,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: _buildRepeatOption(
                                'Weekly',
                                RepeatType.weekly,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildRepeatOption(
                                'Monthly',
                                RepeatType.monthly,
                              ),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: _buildRepeatOption(
                                'Yearly',
                                RepeatType.yearly,
                              ),
                            ),
                          ],
                        ),

                        // Weekly specific options
                        if (_repeatType == RepeatType.weekly) ...[
                          SizedBox(height: 16),
                          Text(
                            'Repeat on:',
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildDayChip(1, 'M'),
                              _buildDayChip(2, 'T'),
                              _buildDayChip(3, 'W'),
                              _buildDayChip(4, 'T'),
                              _buildDayChip(5, 'F'),
                              _buildDayChip(6, 'S'),
                              _buildDayChip(7, 'S'),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _saveReminder,
                        child: Text(
                          widget.reminder == null ? 'Add' : 'Save',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRepeatOption(String label, RepeatType type) {
    final bool isSelected = _repeatType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _repeatType = type;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.deepOrange.withOpacity(0.2)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.deepOrange : Colors.grey,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.amber : Colors.grey[400],
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayChip(int day, String label) {
    final bool isSelected = _selectedDays.contains(day);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedDays.remove(day);
          } else {
            _selectedDays.add(day);
          }
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: isSelected ? Colors.amber : Colors.grey),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// Settings Screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TimeOfDay? _wakeUpTime;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWakeUpTime();
  }

  Future<void> _loadWakeUpTime() async {
    final provider = Provider.of<ReminderProvider>(context, listen: false);
    final wakeUpTime = await provider.getWakeUpTime();
    setState(() {
      _wakeUpTime = wakeUpTime;
      _isLoading = false;
    });
  }

  Future<void> _setWakeUpTime(BuildContext context) async {
    final provider = Provider.of<ReminderProvider>(context, listen: false);
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _wakeUpTime ?? TimeOfDay(hour: 7, minute: 0),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: Colors.deepOrange,
              onPrimary: Colors.white,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: DialogThemeData(backgroundColor: Color(0xFF121212)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      await provider.setWakeUpTime(picked);
      setState(() {
        _wakeUpTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: Colors.deepOrange)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.deepOrange),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:
          _isLoading
              ? Center(
                child: CircularProgressIndicator(color: Colors.deepOrange),
              )
              : ListView(
                padding: EdgeInsets.all(16),
                children: [
                  _buildSettingSection(
                    'Wake-up Time',
                    'Set your daily wake-up time for "Remind me when I wake up" feature',
                    Icons.bedtime,
                    trailing: Text(
                      _wakeUpTime?.format(context) ?? 'Not set',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _setWakeUpTime(context),
                  ),
                  Divider(color: Colors.grey[800]),
                  _buildSettingSection(
                    'Notifications',
                    'Manage your notification settings',
                    Icons.notifications,
                    onTap: () {
                      // Navigate to notification settings
                      // This would typically open system settings for app notifications
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Opening notification settings...'),
                          backgroundColor: Colors.deepOrange,
                        ),
                      );
                    },
                  ),
                  Divider(color: Colors.grey[800]),
                  _buildSettingSection(
                    'App Theme',
                    'Change your app appearance',
                    Icons.palette,
                    trailing: Text(
                      'Fire & Dark',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () {
                      // Theme selection would go here
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => _buildThemeSelector(),
                      );
                    },
                  ),
                  Divider(color: Colors.grey[800]),
                  _buildSettingSection(
                    'About NotiFire',
                    'App information and credits',
                    Icons.info_outline,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => _buildAboutDialog(),
                      );
                    },
                  ),
                ],
              ),
    );
  }

  Widget _buildSettingSection(
    String title,
    String subtitle,
    IconData icon, {
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      leading: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.deepOrange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.deepOrange),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[400])),
      trailing: trailing ?? Icon(Icons.arrow_forward_ios, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildThemeSelector() {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme Selection',
            style: TextStyle(
              color: Colors.deepOrange,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 16),
          _buildThemeOption(
            'Fire & Dark',
            'Default fire-inspired dark theme',
            Colors.deepOrange,
            isSelected: true,
          ),
          SizedBox(height: 12),
          _buildThemeOption(
            'Pure Dark',
            'Minimalist dark theme with orange accents',
            Colors.grey[800]!,
          ),
          SizedBox(height: 12),
          _buildThemeOption(
            'Lava',
            'Intense red and black theme',
            Colors.red[900]!,
          ),
          SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.deepOrange,
              minimumSize: Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Done',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(
    String name,
    String description,
    Color color, {
    bool isSelected = false,
  }) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.amber : Colors.transparent,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ),
          ),
          if (isSelected) Icon(Icons.check_circle, color: Colors.amber),
        ],
      ),
    );
  }

  Widget _buildAboutDialog() {
    return AlertDialog(
      backgroundColor: Color(0xFF1E1E1E),
      title: Text('About NotiFire', style: TextStyle(color: Colors.deepOrange)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department, size: 64, color: Colors.deepOrange),
          SizedBox(height: 16),
          Text(
            'NotiFire v1.0.0',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'A fire-themed reminder app with local notifications and custom wake-up reminders.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400]),
          ),
          SizedBox(height: 16),
          Text('© 2025 NotiFire', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
      actions: [
        TextButton(
          child: Text('Close', style: TextStyle(color: Colors.amber)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
