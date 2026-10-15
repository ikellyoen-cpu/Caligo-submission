//Latest change : 13/OCT/2026 - Vino
//devnote : Added multiple stuff im too lazy to mention all of them
import 'package:webview_flutter/webview_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_analog_clock/flutter_analog_clock.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:geolocator/geolocator.dart';
// import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

final _appName = "Caligo";

//Set this variable to the desfired app name - vino
final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const caligo());
  await loadMultiplier();

  // UI first
  // backgroundMusic.stop();
  // backgroundMusic.dispose();
  _Permissions(); // setup runs in the background
}

double multiplier = 1.0;
Future<void> loadMultiplier() async {
  final prefs = await SharedPreferences.getInstance();
  multiplier = prefs.getDouble("MULTIPLIER") ?? 1.0;
}

Future<void> saveMultiplier() async {
  multiplier = (multiplier * 10).round() / 10;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble("MULTIPLIER", multiplier);
}

Future<void> _Permissions() async {
  try {
    await Permission.phone.request();
    tz.initializeTimeZones();
    final String zoneName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(zoneName));
    await notifications.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/caligo_appicon'),
    ));
    await notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await Geolocator.requestPermission();
  } catch (e) {
    debugPrint("Init error: $e");
  }
}

AudioPlayer? backgroundMusic;
final ValueNotifier<String?> currentTrack = ValueNotifier(null);

Future<void> _stopBackgroundMusic() async {
  final player = backgroundMusic;
  backgroundMusic = null;
  currentTrack.value = null;
  if (player != null) {
    await player.stop();
    await player.dispose();
  }
}

Future<void> _startBackgroundMusic(String filename) async {
  if (currentTrack.value == filename &&
      backgroundMusic?.state == PlayerState.playing) return;

  await _stopBackgroundMusic();

  final player = AudioPlayer();
  backgroundMusic = player;
  currentTrack.value = filename;

  await player.setReleaseMode(ReleaseMode.loop);
  await player.play(AssetSource('sounds/$filename'));
}

Future<void> _pauseBackgroundMusic() async => backgroundMusic?.pause();
Future<void> _resumeBackgroundMusic() async => backgroundMusic?.resume();

class caligo extends StatelessWidget {
  const caligo({super.key});

  @override
  Widget build(BuildContext context) {
    final acmeText = GoogleFonts.acmeTextTheme();

    return MaterialApp(
      title: _appName,
      theme: ThemeData(
        primarySwatch: Colors.lightGreen,
        textTheme: acmeText,
        primaryTextTheme: acmeText,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blueGrey.shade800,
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.acme(fontSize: 20, color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade400,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.acme(fontSize: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue.shade700,
            textStyle: GoogleFonts.acme(fontSize: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          hintStyle: GoogleFonts.acme(),
          labelStyle: GoogleFonts.acme(),
        ),
        snackBarTheme: SnackBarThemeData(
          contentTextStyle: GoogleFonts.acme(color: Colors.white),
        ),
      ),
      builder: (context, child) => SafeArea(
        top: false,
        child: child!,
      ),
      home: const StartMenu(),
    );
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => SchedulePageState();
}

class SchedulePageState extends State<SchedulePage> {
  Timer? _timer;
  Map<String, TimeOfDay> _dailySchedule = {};
  List<int> _currentTime = [0, 0, 0];
  List<int> _timeLeft = [0, 0, 0];
  //String _timeLeftText = "";
  //String _timeLeftText = "";
  void _continuousTicks() {
    _timer = Timer.periodic(Duration(milliseconds: 50), (timer) {
      setState(() {
        _currentTime = [
          DateTime.now().hour,
          DateTime.now().minute,
          DateTime.now().second
        ];
      });
    });
  }

  String _timeLeftFor(TimeOfDay task) {
    final now = DateTime.now();
    var schedule =
        DateTime(now.year, now.month, now.day, task.hour, task.minute);

    // already passed today -> count to tomorrow
    if (schedule.isBefore(now)) {
      schedule =
          DateTime(now.year, now.month, now.day + 1, task.hour, task.minute);
    }

    final diff = schedule.difference(now);
    final hour = diff.inHours;
    final minute = diff.inMinutes % 60;
    final second = diff.inSeconds % 60;

    return [hour, minute, second]
        .map((n) => n.toString().padLeft(2, '0'))
        .join(':');
  }

  Future<void> _scheduleNotif(int id, String task, TimeOfDay time) async {
    final now = tz.TZDateTime.now(tz.local);

    var scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }
    List<int> scheduledTimeList = [
      scheduledTime.hour,
      scheduledTime.minute,
      scheduledTime.second
    ];
    setState(() {
      _timeLeft = List.generate(
          3,
          (i) => scheduledTimeList[i] > _currentTime[i]
              ? scheduledTimeList[i] - _currentTime[i]
              : scheduledTimeList[i] - _currentTime[i]);
      // List.generate(3, (i) => scheduledTimeList[i] - _currentTime[i]);
      //_timeLeftText = _timeLeft.map((n) => n.toString().padLeft(2, '0')).join(':');
    });

    await notifications.zonedSchedule(
      id,
      'Caligo Reminder',
      'Remember to $task',
      scheduledTime,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'caligo_reminders',
          'Caligo Reminders',
          channelDescription: 'Reminders from Caligo',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleAll() async {
    await notifications.cancelAll();
    int id = 0;
    for (final entry in _dailySchedule.entries) {
      await _scheduleNotif(id++, entry.key, entry.value);
    }
  }

  Future<void> _parseUserScheduleData(bool save) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (!save) {
        final List<String>? _rawData = prefs.getStringList("SCHEDULE");
        _dailySchedule.clear();
        for (var raw in _rawData ?? []) {
          int _hourTime = int.parse(raw.substring(0, 2));
          int _minuteTime = int.parse(raw.substring(3, 5));
          String _taskName = raw.substring(6);

          _dailySchedule[_taskName] =
              TimeOfDay(hour: _hourTime, minute: _minuteTime);
          debugPrint("Successfully fetched raw data of user's schedule : $raw");
        }
      } else {
        List<String>? _rawData = [];
        _dailySchedule.forEach((taskName, timeObject) {
          _rawData.add(
            "${timeObject.hour.toString().padLeft(2, '0')}:"
            "${timeObject.minute.toString().padLeft(2, '0')},$taskName",
          );
        });
        prefs.setStringList("SCHEDULE", _rawData);
      }
    });
  }

  Future<void> _addSchedule(BuildContext context) async {
    TimeOfDay? selectedTime;
    final TextEditingController textController = TextEditingController();
    String _alertText = "";

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text("New schedule", style: GoogleFonts.acme(fontSize: 20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      labelText: "Type your task here...",
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 15),
                  // Time picker button
                  ElevatedButton(
                    onPressed: () async {
                      final TimeOfDay? time = await showTimePicker(
                        context: context,
                        initialTime: selectedTime ?? TimeOfDay.now(),
                      );

                      if (time != null) {
                        setDialogState(() {
                          selectedTime = time;
                        });
                      }
                    },
                    child: Text(
                      selectedTime == null
                          ? "Select time"
                          : selectedTime!.format(context),
                    ),
                  ),

                  const SizedBox(height: 15),

                  Text(
                    _alertText,
                    style: GoogleFonts.acme(fontSize: 15, color: Colors.red),
                  ),

                  // String input
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: GoogleFonts.acme(fontSize: 15)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _alertText = (selectedTime == null)
                          ? "Select time first!"
                          : ((textController.text.isEmpty)
                              ? "Fill up the text field first!"
                              : "");
                    });
                    if (selectedTime == null || textController.text.isEmpty)
                      return;
                    _dailySchedule[textController.text] = selectedTime!;
                    _parseUserScheduleData(true);
                    _scheduleAll();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child:
                      Text("Create +", style: GoogleFonts.acme(fontSize: 15)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Row _displayTime(List<int> timeData,
      [Color? _primaryColor,
      Color _secondaryColor = Colors.black,
      double boxSize = 50]) {
    final _actualPrimaryColor = _primaryColor ?? Colors.blue.shade100;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        timeData.length,
        (index) => Row(
          children: [
            Container(
                width: boxSize,
                height: boxSize,
                decoration: BoxDecoration(
                  color: _actualPrimaryColor,
                  borderRadius: BorderRadius.circular(7.0),
                  border: Border.all(
                    color: Colors.black,
                    width: 2.0,
                  ),
                ),
                child: Center(
                    child: Text(timeData[index].toString().padLeft(2, '0'),
                        style: GoogleFonts.acme(
                            fontSize: boxSize / 2, color: _secondaryColor)))),
            SizedBox(width: 5),
            if (index < timeData.length - 1)
              Text(":",
                  style: TextStyle(
                      fontSize: boxSize * 0.6,
                      color: _actualPrimaryColor,
                      fontWeight: FontWeight.bold)),
            if (index < timeData.length - 1) SizedBox(width: 5),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _continuousTicks();
    _parseUserScheduleData(false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   _timer?.cancel();
  //   _stopBackgroundMusic();
  // }

  Widget build(BuildContext context) {
    final Size _screenSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/Schedule", style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.home, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: _screenSize.width,
        height: _screenSize.height,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/daily_schedule_bg.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
            child: SingleChildScrollView(
                child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 20),
            Text("Your daily schedule",
                style: GoogleFonts.acme(fontSize: 30, color: Colors.white)),
            SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 250,
                height: 250,
                child: AnalogClock(
                  dialColor: Colors.white,
                  dialBorderColor: Colors.black,
                  markingColor: Colors.grey,
                  hourHandColor: Colors.black,
                  minuteHandColor: Colors.blue,
                  secondHandColor: Colors.red,
                  centerPointColor: Colors.red,
                  isKeepTime: true,
                ),
              ),
            ),
            SizedBox(height: 20),
            _displayTime(_currentTime),
            ElevatedButton(
                onPressed: () async => _addSchedule(context),
                child: Text("Add schedule",
                    style: GoogleFonts.acme(fontSize: 25))),
            SizedBox(height: 20),
            for (var entry in _dailySchedule.entries)
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: _screenSize.width * 0.9,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(
                        color: Colors.orange.shade300,
                        width: 5.0,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(" TASK: ${entry.key}",
                                style: GoogleFonts.acme(
                                    fontSize: 20, color: Colors.black)),
                            Row(
                              children: [
                                Text(" at  ",
                                    style: GoogleFonts.acme(
                                        fontSize: 10, color: Colors.black)),
                                _displayTime(
                                    [entry.value.hour, entry.value.minute],
                                    Colors.black,
                                    Colors.white,
                                    25),
                                Text("  in ${_timeLeftFor(entry.value)}",
                                    style: GoogleFonts.acme(
                                        fontSize: 10, color: Colors.black)),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                    onPressed: () => showDialog(
                                        context: context,
                                        barrierDismissible: true,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                            title: Text("Confirm deletion",
                                                style: GoogleFonts.acme(
                                                    fontSize: 25)),
                                            content: Text(
                                                "Are you sure you want to delete task [${entry.key}] occuring at [${entry.value.hour}:${entry.value.minute}]?",
                                                style: GoogleFonts.acme(
                                                    fontSize: 15)),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () {
                                                  // Close the dialog and pass a response if needed
                                                  Navigator.pop(context);
                                                },
                                                child: Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  _dailySchedule
                                                      .remove(entry.key);
                                                  _parseUserScheduleData(true);
                                                  _scheduleAll();
                                                  Navigator.pop(context);
                                                },
                                                style: TextButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                ),
                                                child: Text('Delete',
                                                    style: GoogleFonts.acme(
                                                        fontSize: 15,
                                                        color: Colors.white)),
                                              ),
                                            ],
                                          );
                                        }),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                    ),
                                    child:
                                        Icon(Icons.delete_forever, size: 15)),
                                SizedBox(height: 5),
                                ElevatedButton(
                                    onPressed: () => showDialog(
                                        context: context,
                                        barrierDismissible: true,
                                        builder: (BuildContext context) {
                                          TimeOfDay selectedTime = entry.value;
                                          final TextEditingController
                                              textController =
                                              TextEditingController();
                                          return AlertDialog(
                                            title: Text("Editting task",
                                                style: GoogleFonts.acme(
                                                    fontSize: 25)),
                                            content: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextField(
                                                  controller: textController,
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText:
                                                        "Type your task here...",
                                                    border:
                                                        OutlineInputBorder(),
                                                  ),
                                                ),
                                                const SizedBox(height: 15),
                                                ElevatedButton(
                                                  onPressed: () async {
                                                    final TimeOfDay? time =
                                                        await showTimePicker(
                                                      context: context,
                                                      initialTime: selectedTime,
                                                    );

                                                    if (time != null) {
                                                      setState(() {
                                                        selectedTime = time;
                                                      });
                                                    }
                                                  },
                                                  child: Text(
                                                      selectedTime
                                                          .format(context),
                                                      style: GoogleFonts.acme(
                                                          fontSize: 15)),
                                                ),
                                              ],
                                            ),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () {
                                                  // Close the dialog and pass a response if needed
                                                  Navigator.pop(context);
                                                },
                                                child: Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  if (textController
                                                      .text.isEmpty) return;

                                                  _dailySchedule
                                                      .remove(entry.key);
                                                  _dailySchedule[textController
                                                      .text] = selectedTime;
                                                  _parseUserScheduleData(true);
                                                  _scheduleAll();
                                                  Navigator.pop(context);
                                                },
                                                style: TextButton.styleFrom(
                                                  backgroundColor: Colors.green,
                                                ),
                                                child: Text('Save',
                                                    style: GoogleFonts.acme(
                                                        fontSize: 15,
                                                        color: Colors.white)),
                                              ),
                                            ],
                                          );
                                        }),
                                    // _dailySchedule.remove(entry.key);
                                    // await _parseUserScheduleData(true);
                                    // await _scheduleAll();
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade600,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12.0)),
                                    ),
                                    child: Icon(Icons.edit, size: 15)),
                              ],
                            ),
                            SizedBox(width: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10),
                ],
              ),
          ],
        ))),
      ),
    );
  }
}

class VinoPage extends StatefulWidget {
  const VinoPage({super.key});

  @override
  State<VinoPage> createState() => _VinoPageState();
}

class _VinoPageState extends State<VinoPage> {
  late final WebViewController vinoController;

  @override
  void initState() {
    super.initState();
    vinoController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse('https://vinoscape.netlify.app'),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/Vinoscape",
                style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.map, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: WebViewWidget(controller: vinoController),
      ),
    );
  }
}

class AIChatPage extends StatefulWidget {
  const AIChatPage({super.key});

  @override
  State<AIChatPage> createState() => _AIChatPageState();
}

class _AIChatPageState extends State<AIChatPage> {
  final TextEditingController messageController = TextEditingController();
  Map<String, dynamic> userData = {};
  final List<Map<String, String>> messages = [
    {"sender": "ai", "message": "Hello! I'm Caligo AI. How can I help you?"}
  ];

  bool isLoading = false;
  List<String> _decodeBitString(String bits, List<String> labels) {
    List<String> result = [];
    for (int i = 0; i < bits.length && i < labels.length; i++) {
      if (bits[i] == '1') {
        result.add(labels[i]);
      }
    }
    return result;
  }

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    // This also asks for the microphone permission
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        // "done" / "notListening" fires when it stops by itself (silence timeout)
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (error) {
        debugPrint("Speech error: ${error.errorMsg}");
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Speech recognition isn't available.")),
      );
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (result) {
          setState(() {
            messageController.text = result.recognizedWords;
            // keep the cursor at the end
            messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: messageController.text.length),
            );
          });
        },
        // localeId: "id_ID", // optional: choose the language
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 4), // stop after 4s of silence
      );
    }
  }

  @override
  void dispose() {
    _speech.cancel();
    messageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();

    final symptomsLabels = [
      "Memory-loss",
      "Constant brain fogs",
      "Communicating issues",
      "Struggle learning new things",
    ];

    final dietLabels = [
      "Standard/Omnivore (eats both veggies + meat)",
      "Vegetarian (no meat, only dairy and plants)",
      "Vegan (100% plant based)",
      "Pescatarian (vegan + seafood)",
      "Keto/lowcarb",
      "Gluten-free",
      "Mediterranian",
    ];

    final allergyLabels = [
      "Peanuts",
      "Dairy",
      "Gluten",
      "Soy",
      "Eggs",
      "Shellfish",
      "None",
    ];

    setState(() {
      userData = {
        "name": prefs.getString("NAME") ?? "",
        "age": prefs.getInt("AGE") ?? 0,
        "sleep": prefs.getInt("SLEEP") ?? 0,
        "symptoms":
            _decodeBitString(prefs.getString("SYMPTOMS") ?? "", symptomsLabels)
                .join(", "),
        "diet": dietLabels[prefs.getInt("DIET") ?? 0],
        "allergies":
            _decodeBitString(prefs.getString("ALLERGIES") ?? "", allergyLabels)
                .join(", "),
        "emergency": prefs.getString("EMERGENCY") ?? "",
      };
    });
  }

  Future<void> sendMessage() async {
    final message = messageController.text.trim();

    if (message.isEmpty || isLoading) {
      return;
    }

    setState(() {
      messages.add({
        "sender": "user",
        "message": message,
      });

      isLoading = true;
    });

    messageController.clear();

    try {
      final response = await http.post(
        Uri.parse("https://caligo-backend-production.up.railway.app/chat"),
        headers: {
          "Content-Type": "application/json",
          "ngrok-skip-browser-warning": "true",
        },
        body: jsonEncode({
          "message": message,
          "userData": userData,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        setState(() {
          messages.add({
            "sender": "ai",
            "message": data["reply"],
          });
        });
      } else {
        setState(() {
          messages.add({
            "sender": "ai",
            "message": "Sorry, I couldn't connect to Caligo AI."
          });
        });
      }
    } catch (e) {
      setState(() {
        messages.add({
          "sender": "ai",
          "message": "Something went wrong while connecting to the AI."
        });
      });
    }

    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("{_appName}/AI Chatbot"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];

                final bool isUser = message["sender"] == "user";

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 5,
                    ),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.brown : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      message["message"] ?? "",
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onSubmitted: (_) {
                      sendMessage();
                    },
                  ),
                ),
                IconButton(
                  onPressed: _toggleListening,
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? Colors.red : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: sendMessage,
                  icon: const Icon(
                    Icons.send,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   _stopBackgroundMusic();
  // }
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final MapController _mapController = MapController();
  final TextEditingController _markerNameController = TextEditingController();
  Future<Position?> getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  final List<IconData> _markerIcons = [
    Icons.location_pin,
    Icons.home,
    Icons.local_hospital,
    Icons.shopping_cart,
    Icons.restaurant,
    Icons.park,
    Icons.school,
    Icons.people,
  ];
  Marker createMarker(
      double latitude, double longitude, String name, IconData icon) {
    return Marker(
      point: LatLng(latitude, longitude),
      width: 50,
      height: 50,
      child: Tooltip(
        message: name,
        child: GestureDetector(
          onTap: () {
            print("Marker touched!");
          },
          child: Icon(
            icon,
            size: 40,
          ),
        ),
      ),
    );
  }

  Future<void> addNewMarker(double latitude, double longitude) async {
    _markerNameController.clear();
    IconData selectedIcon = _markerIcons[0];

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: Text(
                "New Marker",
                style:
                    GoogleFonts.acme(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _markerNameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter what this place is called",
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text("Pick an icon", style: GoogleFonts.acme(fontSize: 18)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final icon in _markerIcons)
                        GestureDetector(
                          onTap: () {
                            dialogSetState(() {
                              selectedIcon = icon;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selectedIcon == icon
                                  ? Colors.amber.shade200
                                  : Colors.transparent,
                              border: Border.all(
                                color: selectedIcon == icon
                                    ? Colors.orange
                                    : Colors.grey,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(icon, size: 30),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text("CANCEL", style: GoogleFonts.acme(fontSize: 20)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text("OK", style: GoogleFonts.acme(fontSize: 20)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      markers.add(
        createMarker(
          latitude,
          longitude,
          _markerNameController.text.trim(),
          selectedIcon,
        ),
      );
    });
  }

  List<Marker> markers = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/Map", style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.map, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(-7.25, 112.75),
              initialZoom: 13,
              onTap: (tapPosition, point) {
                print("User clicked the map!");
                print("Latitude: ${point.latitude}");
                print("Longitude: ${point.longitude}");
                addNewMarker(point.latitude, point.longitude);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.app.caligo',
              ),
              MarkerLayer(
                markers: markers,
              ),
            ],
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final position = await getLocation();
                  if (position != null) {
                    _mapController.move(
                      LatLng(position.latitude, position.longitude),
                      17,
                    );
                  }
                },
                child: Text("Go to current Location"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showMultiplierExplanation(BuildContext context, double currentPoints) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text("Multipliers",
            style: GoogleFonts.acme(fontSize: 18, color: Colors.black)),
        content: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  "Using multipliers, you can earn extra points per minigame completed. Multipliers can be earned by upgrading your Caligo Tower.",
                  style: GoogleFonts.acme(fontSize: 14, color: Colors.black)),
              const SizedBox(height: 10),
              Text("- Current stats - ",
                  style: GoogleFonts.acme(fontSize: 12, color: Colors.black)),
              const SizedBox(height: 5),
              Text("${multiplier}x points Multiplier",
                  style: GoogleFonts.acme(fontSize: 12, color: Colors.red)),
              Text("${currentPoints} points earned so far",
                  style: GoogleFonts.acme(fontSize: 12, color: Colors.black)),
            ]),
        actions: [
          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                style: TextButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(3.0),
                    side: BorderSide(
                        width: 2,
                        color:
                            Colors.blue.shade800), // Adjust value for roundness
                  ),
                ),
                child: Text('OK', style: GoogleFonts.acme(fontSize: 12)),
              ),
            ),
          ]),
        ],
      );
    },
  );
}

class Minigame extends StatefulWidget {
  const Minigame({super.key});

  @override
  State<Minigame> createState() => _MinigameState();
}

class _MinigameState extends State<Minigame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pointsSpinController;
  TextEditingController numberController = TextEditingController();

  List<int> pattern = [];
  List<int> playerPattern = [];
  Set<int> glowingButtons = {};

  double points = 0.0;
  Widget _pts(num n) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset("assets/pointsicon.png", width: 15, height: 15),
          const SizedBox(width: 5),
          Text("$n pts", style: GoogleFonts.acme(fontSize: 15)),
        ],
      );
  Future<void> _configPointsData(bool save) async {
    final prefs = await SharedPreferences.getInstance();

    if (save) {
      points = (points * 100).round() / 100; //round pts to 1 decimal place
      await prefs.setDouble("POINTS", points);
    } else {
      setState(() {
        points = prefs.getDouble("POINTS") ?? 0;
      });
    }
  }

  void _awardUserPoints(String minigameName, int ptsReward,
      [bool? showClaimAnimation]) {
    bool pointsAnimEffect = false;
    final double _finalReward = (ptsReward * multiplier * 100).round() / 100;
    double _percentage = 1;
    Timer? _subtimer;

    //this will be used later -Vino
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(builder: (context, setDialogState) {
            void _decreasePointsAnim() {
              _subtimer = Timer.periodic(
                  Duration(milliseconds: 32),
                  (timer) => setDialogState(() {
                        if (_percentage > 0) {
                          _percentage -= 0.02;
                          if (_percentage <= 0) {
                            _percentage = 0;
                            pointsAnimEffect = false;
                            _subtimer?.cancel();
                          }
                        }
                      }));
            }

            return AlertDialog(
              title: Center(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("- Point Rewards - ",
                          style: GoogleFonts.acme(fontSize: 17)),
                      const SizedBox(height: 3),
                      Text("from ${minigameName}",
                          style: GoogleFonts.acme(fontSize: 15))
                    ]),
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text("Rewards:", style: GoogleFonts.acme(fontSize: 14)),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Text("$ptsReward pts",
                                  style: GoogleFonts.acme(
                                      fontSize: 14, color: Colors.black)),
                              const SizedBox(width: 5),
                              SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: Image.asset("assets/pointsicon.png",
                                      fit: BoxFit.contain)),
                            ]),
                        // _pts(ptsReward),
                      ]),
                  const SizedBox(height: 5),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text("Multiplier:",
                            style: GoogleFonts.acme(fontSize: 14)),
                        Text("${multiplier}x",
                            style: GoogleFonts.acme(fontSize: 14)),
                      ]),
                  const SizedBox(height: 5),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Text("Final score:",
                            style: GoogleFonts.acme(fontSize: 14)),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              SizedBox(
                                width: 45,
                                height: 45,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Continuously spinning image.
                                    RotationTransition(
                                      turns: _pointsSpinController,
                                      child: Image.asset(
                                        "assets/reward_icon.png",
                                        fit: BoxFit.contain,
                                      ),
                                    ),

                                    // Stationary foreground text.
                                    Center(
                                      child: Text(
                                        (_finalReward * _percentage)
                                            .toStringAsFixed(2),
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.acme(
                                            fontSize: 20, color: Colors.black),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text("pts",
                                  style: GoogleFonts.acme(
                                      fontSize: 14, color: Colors.black)),
                              const SizedBox(width: 5),
                              SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: Image.asset("assets/pointsicon.png",
                                      fit: BoxFit.contain)),
                            ]),
                        // _pts((ptsReward * multiplier * 100).round() / 100)
                      ]),
                  const SizedBox(height: 5),
                  if (_percentage < 1.0)
                    Text(
                        pointsAnimEffect
                            ? "Claiming points..."
                            : "Claim successful!",
                        style: GoogleFonts.acme(
                            fontSize: 20, color: Colors.green)),
                  const SizedBox(height: 5),
                  ElevatedButton(
                    onPressed: pointsAnimEffect
                        ? null
                        : () => setState(() {
                              if (_percentage > 0) {
                                if (showClaimAnimation ?? true) {
                                  points += _finalReward;
                                  _configPointsData(true);
                                  pointsAnimEffect = true;
                                  _decreasePointsAnim();
                                } else {
                                  _subtimer?.cancel();
                                  points += _finalReward;
                                  _configPointsData(true);
                                  Navigator.pop(dialogContext);
                                }
                              } else {
                                Navigator.pop(dialogContext);
                                _subtimer?.cancel();
                              }
                            }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pointsAnimEffect
                          ? Colors.grey
                          : (_percentage > 0 ? Colors.green : Colors.red),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                        side: BorderSide(
                            color: pointsAnimEffect
                                ? Colors.grey.shade800
                                : (_percentage > 0
                                    ? Colors.green.shade800
                                    : Colors.red.shade800),
                            width: 2.0),
                      ),
                    ),
                    child: Text(_percentage > 0 ? "CLAIM" : "CLOSE",
                        style: GoogleFonts.acme(fontSize: 15)),
                  ),
                ],
              ),
            );
          });
        });
  }

  void _PatternMemory() {
    const List<List<dynamic>> _difficultyData = [
      ["Easy", 4, 1, Colors.green],
      ["Medium", 7, 2, Colors.yellow],
      ["Hard", 10, 3, Colors.orange],
    ]; //[Name, pattern length, point reward, diff color]

    String _currentDiff = "";
    int _patternLength = 0;
    int _pointReward = 0;
    bool showingPattern = false;

    bool PatternPlaying = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        final _dialogSize = MediaQuery.sizeOf(context);

        return StatefulBuilder(
          builder: (context, dialogSetState) {
            Widget memoryButton(int index) {
              bool glowing = glowingButtons.contains(index);

              return GestureDetector(
                onTap: () {
                  if (showingPattern || !PatternPlaying) return;

                  dialogSetState(() {
                    playerPattern.add(index);
                    glowingButtons.add(index);
                  });

                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) {
                      dialogSetState(() {
                        glowingButtons.remove(index);
                      });
                    }
                  });

                  int currentPosition = playerPattern.length - 1;

                  if (index != pattern[currentPosition]) {
                    playerPattern.clear();
                    setState(() {
                      PatternPlaying = false;
                    });
                    showDialog(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: Text(
                            "Incorrect!",
                            style: GoogleFonts.acme(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: Text(
                            "Try again!",
                            style: GoogleFonts.acme(fontSize: 20),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: Text(
                                "OK",
                                style: GoogleFonts.acme(fontSize: 20),
                              ),
                            ),
                          ],
                        );
                      },
                    );

                    return;
                  }

                  if (playerPattern.length == pattern.length) {
                    setState(() {
                      points = points + _pointReward * multiplier;
                      _configPointsData(true);
                      PatternPlaying = false;
                    });
                    playerPattern.clear();

                    _awardUserPoints(
                        "Pattern Memory ($_currentDiff)", _pointReward);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: glowing
                        ? [
                            const BoxShadow(
                              color: Colors.yellowAccent,
                              blurRadius: 25,
                              spreadRadius: 8,
                            ),
                          ]
                        : [],
                  ),
                  child: const Icon(
                    Icons.star,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              );
            }

            void startPattern() async {
              pattern.clear();
              playerPattern.clear();
              glowingButtons.clear();
              showingPattern = true;
              Random random = Random();
              PatternPlaying = true;
              for (int i = 0; i < _patternLength; i++) {
                pattern.add(random.nextInt(9));
              }

              for (int button in pattern) {
                await Future.delayed(
                  const Duration(milliseconds: 300),
                );

                if (!mounted) return;

                dialogSetState(() {
                  glowingButtons.add(button);
                });

                await Future.delayed(
                  const Duration(milliseconds: 500),
                );

                if (!mounted) return;

                dialogSetState(() {
                  glowingButtons.remove(button);
                });
              }
              showingPattern = false;
            }

            return AlertDialog(
              title: Column(children: [
                Text(
                  "Pattern Memory",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.acme(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_currentDiff != "")
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Difficulty:",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.acme(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          decoration: BoxDecoration(
                            color: _difficultyData[_difficultyData.indexWhere(
                                (element) => element[0] == _currentDiff)][3],
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: Text(
                            " $_currentDiff ",
                            textAlign: TextAlign.center,
                            style: GoogleFonts.acme(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ]),
              ]),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(fit: StackFit.loose, children: [
                    SizedBox(
                      width: _dialogSize.width * 0.6,
                      height: _dialogSize.width * 0.6,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: 9,
                        itemBuilder: (context, index) {
                          return memoryButton(index);
                        },
                      ),
                    ),
                    if (!PatternPlaying)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.5),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded,
                                    size: 20.0, color: Colors.white),
                                Text("Game hasn't begun",
                                    style: GoogleFonts.acme(
                                        fontSize: 15, color: Colors.white))
                              ],
                            ),
                          ),
                        ),
                      ),
                  ]),
                  SizedBox(height: 10),
                  Text(
                    _currentDiff != ""
                        ? (PatternPlaying)
                            ? "Repeat the pattern"
                            : "Press [START]"
                        : "Choose a difficulty",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.acme(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 5),
                  for (var data in _difficultyData)
                    Column(children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              dialogSetState(() {
                                if (PatternPlaying) return;
                                _currentDiff = data[0];
                                _patternLength = data[1];
                                _pointReward = data[2];
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  PatternPlaying ? Colors.grey : data[3],
                              foregroundColor: Colors.white,
                              elevation: _currentDiff == data[0] ? 12 : 2,
                              shadowColor: _currentDiff == data[0]
                                  ? Colors.yellowAccent
                                  : Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(
                                    color: PatternPlaying
                                        ? Colors.grey.shade800
                                        : data[3].shade800,
                                    width: 4.0),
                              ),
                            ),
                            child: Text(data[0],
                                style: GoogleFonts.acme(fontSize: 15)),
                          ),
                          _pts(data[2])
                        ],
                      ),
                      const SizedBox(height: 5),
                    ]),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: PatternPlaying || _currentDiff == ""
                      ? null
                      : startPattern,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    "Start",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    "CLOSE",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _PuzzleGame() {
    final List<List<dynamic>> pieceAssetData = [
      [
        "forest_puzzle_piece_",
        [3, 2]
      ],
      [
        "utopia_",
        [3, 2]
      ],
      [
        "chickenontree_",
        [3, 3]
      ],
    ];
    //[path_keyword, board_size in width x height ]
    int usingAssetPack = 0;
    int movesMade = 0;
    final Random _random = Random();

    // final pieces = [
    //   "assets/forest_puzzle_piece_1.png",
    //   "assets/forest_puzzle_piece_2.png",
    //   "assets/forest_puzzle_piece_3.png",
    //   "assets/forest_puzzle_piece_4.png",
    //   "assets/forest_puzzle_piece_5.png",
    //   "assets/forest_puzzle_piece_6.png",
    // ];

    List<int> order = List.generate(
        pieceAssetData[usingAssetPack][1][0] *
            pieceAssetData[usingAssetPack][1][1],
        (index) => index); //[0, 1, 2, 3, 4, 5];
    order.shuffle(_random);

    int? selectedPiece;
    bool completed = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            void newGame() {
              dialogSetState(() {
                selectedPiece = null;
                completed = false;
                movesMade = 0;
                usingAssetPack = _random.nextInt(pieceAssetData.length);
                order = List.generate(
                    pieceAssetData[usingAssetPack][1][0] *
                        pieceAssetData[usingAssetPack][1][1],
                    (index) => index);
                order.shuffle(_random);
              });
            }

            void selectPiece(int index) {
              if (completed) return;

              if (selectedPiece == null) {
                dialogSetState(() {
                  selectedPiece = index;
                });
              } else if (selectedPiece == index) {
                dialogSetState(() {
                  selectedPiece = null;
                });
              } else {
                dialogSetState(() {
                  final temp = order[selectedPiece!];
                  order[selectedPiece!] = order[index];
                  order[index] = temp;
                  selectedPiece = null;
                  movesMade++;
                });

                bool solved = true;

                for (int i = 0; i < order.length; i++) {
                  if (order[i] != i) {
                    solved = false;
                    break;
                  }
                }

                if (solved) {
                  completed = true;
                  _awardUserPoints("Puzzle Game", 2);
                }
              }
            }

            return AlertDialog(
              title:
                  Text("Picture Puzzle", style: GoogleFonts.acme(fontSize: 20)),
              content: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width:
                          150.0 * (pieceAssetData[usingAssetPack][1][0] as int),
                      height:
                          100.0 * (pieceAssetData[usingAssetPack][1][1] as int),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: pieceAssetData[usingAssetPack][1][0],
                          crossAxisSpacing: 0,
                          mainAxisSpacing: 0,
                        ),
                        itemCount: order.length,
                        itemBuilder: (context, index) {
                          final isSelected = selectedPiece == index;

                          return GestureDetector(
                            onTap: () {
                              selectPiece(index);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.yellow
                                      : Colors.transparent,
                                  width: isSelected ? 4 : 0,
                                ),
                              ),
                              child: Image.asset(
                                "assets/puzzlePieces/${pieceAssetData[usingAssetPack][0]}${order[index] + 1}.png",
                                fit: BoxFit.fill,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Text(
                        !completed
                            ? "$movesMade moves have been made"
                            : "Completed in $movesMade moves",
                        style: GoogleFonts.acme(fontSize: 20)),
                    Text("Puzzle pack: ${pieceAssetData[usingAssetPack][0]}",
                        style: GoogleFonts.acme(fontSize: 10)),
                  ]),
              actions: [
                ElevatedButton(
                  onPressed: newGame,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side:
                          BorderSide(color: Colors.green.shade800, width: 4.0),
                    ),
                  ),
                  child: Text(completed ? "PLAY ANOTHER" : "SHUFFLE",
                      style: GoogleFonts.acme(fontSize: 15)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: BorderSide(color: Colors.red.shade800, width: 4.0),
                    ),
                  ),
                  child: Text("CLOSE", style: GoogleFonts.acme(fontSize: 15)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _TicTacToe() {
    // 0 = empty
    // 1 = Player 1 / Circle
    // 2 = Player 2 / X
    List<int> board = List.filled(9, 0);

    int playerSymbol = 0;
    int botSymbol = 0;
    int currentTurn = 1;

    bool gameStarted = false;
    bool gameOver = false;
    double maxBotIntelligence = 0.0;
    int finalResult = 0;
    List<int> winningLine = [];
    const List<List<dynamic>> _gameDifficulties = [
      ["EASY", 0.1, 2, Colors.green],
      ["MEDIUM", 0.4, 3, Colors.amber],
      ["HARD", 0.8, 4, Colors.orange]
    ];

    final Random random = Random();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            int checkWinner() {
              const List<List<int>> winningLines = [
                [0, 1, 2],
                [3, 4, 5],
                [6, 7, 8],
                [0, 3, 6],
                [1, 4, 7],
                [2, 5, 8],
                [0, 4, 8],
                [2, 4, 6],
              ];

              for (final line in winningLines) {
                final a = line[0];
                final b = line[1];
                final c = line[2];

                if (board[a] != 0 &&
                    board[a] == board[b] &&
                    board[a] == board[c]) {
                  winningLine = line;
                  return board[a];
                }
              }

              if (!board.contains(0)) {
                return 3; // Draw
              }

              return 0; // Game still going
            }

            void checkGame() {
              setState(() {
                finalResult = checkWinner();

                if (finalResult == 0) return;

                gameOver = true;
              });

              if (finalResult == playerSymbol) {
                final reward = _gameDifficulties[_gameDifficulties.indexWhere(
                    (element) => element[1] == maxBotIntelligence)][2] as int;

                _awardUserPoints(
                    "Tic-Tac-Toe (${_gameDifficulties[_gameDifficulties.indexWhere((element) => element[1] == maxBotIntelligence)][0]})",
                    reward);
              }
            }

            List<int> getEmptySpaces() {
              final List<int> empty = [];

              for (int i = 0; i < board.length; i++) {
                if (board[i] == 0) {
                  empty.add(i);
                }
              }

              return empty;
            }

            int findWinningMove(int symbol) {
              for (final position in getEmptySpaces()) {
                board[position] = symbol;

                if (checkWinner() == symbol) {
                  board[position] = 0;
                  return position;
                }

                board[position] = 0;
              }

              return -1;
            }

            int getBotMove() {
              final emptySpaces = getEmptySpaces();

              if (emptySpaces.isEmpty) {
                return -1;
              }

              final bool smartMove = random.nextDouble() <
                  maxBotIntelligence; // determines how smart the bot is

              if (!smartMove) {
                return emptySpaces[random.nextInt(emptySpaces.length)];
              }

              // 1. Try to win immediately.
              final winningMove = findWinningMove(botSymbol);

              if (winningMove != -1) {
                return winningMove;
              }

              // 2. Try to block the player's immediate win.
              final blockingMove = findWinningMove(playerSymbol);

              if (blockingMove != -1) {
                return blockingMove;
              }

              // 3. Sometimes take the center.
              if (board[4] == 0 && random.nextDouble() < maxBotIntelligence) {
                return 4;
              }

              // 4. Sometimes take a corner.
              final corners = [0, 2, 6, 8];
              final availableCorners =
                  corners.where((position) => board[position] == 0).toList();

              if (availableCorners.isNotEmpty &&
                  random.nextDouble() < maxBotIntelligence) {
                return availableCorners[
                    random.nextInt(availableCorners.length)];
              }

              // 5. Otherwise choose a random legal position.
              return emptySpaces[random.nextInt(emptySpaces.length)];
            }

            void botTurn() async {
              if (gameOver) {
                return;
              }

              await Future.delayed(const Duration(seconds: 3));

              final move = getBotMove();

              if (move == -1) {
                return;
              }

              setState(() {
                board[move] = botSymbol;
                currentTurn = playerSymbol;
              });

              checkGame();
            }

            void playerMove(int position) {
              if (!gameStarted ||
                  gameOver ||
                  currentTurn != playerSymbol ||
                  board[position] != 0) {
                return;
              }

              setState(() {
                board[position] = playerSymbol;
                currentTurn = botSymbol;
              });

              checkGame();

              if (!gameOver) {
                botTurn();
              }
            }

            void selectPlayer(int selectedPlayer) {
              setState(() {
                playerSymbol = selectedPlayer;
                botSymbol = selectedPlayer == 1 ? 2 : 1;

                board = List.filled(9, 0);
                gameStarted = true;
                gameOver = false;
                finalResult = 0;

                // Player 1 always starts.
                currentTurn = 1;
              });

              // If the bot is Player 1, the bot starts.
              if (botSymbol == 1) {
                botTurn();
              }
            }

            Widget buildCell(int index) {
              final value = board[index];

              return Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.black,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: ElevatedButton(
                        onPressed: () => playerMove(index),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: winningLine.contains(index) &&
                                    (finalResult == 1 || finalResult == 2)
                                ? Colors.red
                                : Colors.black,
                            shadowColor: Colors.transparent),
                        child: Center(
                            child: Icon(
                                <IconData?>[
                                  null,
                                  Icons.circle_outlined,
                                  Icons.close
                                ][value],
                                size: 35))),
                  ));
            }

            return AlertDialog(
              title: Center(
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text("Tic-Tac-Toe ",
                      style:
                          GoogleFonts.acme(fontSize: 20, color: Colors.black)),
                  if (maxBotIntelligence != 0.0)
                    Row(children: [
                      Text(r"(",
                          style: GoogleFonts.acme(
                              fontSize: 20, color: Colors.black)),
                      Text(
                          _gameDifficulties[_gameDifficulties.indexWhere(
                              (element) =>
                                  element[1] == maxBotIntelligence)][0],
                          style: GoogleFonts.acme(
                              fontSize: 20,
                              color: _gameDifficulties[
                                  _gameDifficulties.indexWhere((element) =>
                                      element[1] == maxBotIntelligence)][3])),
                      Text(r")",
                          style: GoogleFonts.acme(
                              fontSize: 20, color: Colors.black)),
                    ]),
                ]),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!gameStarted)
                    Padding(
                      padding: EdgeInsets.only(bottom: 15),
                      child: Text(
                        (maxBotIntelligence == 0.0)
                            ? "Choose difficulty"
                            : "Choose your player",
                        style: GoogleFonts.acme(fontSize: 16),
                      ),
                    ),

                  if (gameStarted && !gameOver)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        currentTurn == playerSymbol
                            ? "Your turn (Player $playerSymbol)"
                            : "Bot is thinking... (Player $botSymbol)",
                        style: GoogleFonts.acme(fontSize: 16),
                      ),
                    ),

                  if (gameOver)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        children: [
                          Text(
                            (finalResult == 3)
                                ? "DRAW!"
                                : (finalResult == playerSymbol)
                                    ? "Human wins!"
                                    : "Computer wins!",
                            style: GoogleFonts.acme(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            (finalResult != playerSymbol)
                                ? r"You get 0 points :("
                                : "You get ${_gameDifficulties[_gameDifficulties.indexWhere((element) => element[1] == maxBotIntelligence)][2] as int} points!",
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),

                  // Tic-Tac-Toe board
                  Stack(children: [
                    Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildCell(0),
                            buildCell(1),
                            buildCell(2),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildCell(3),
                            buildCell(4),
                            buildCell(5),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            buildCell(6),
                            buildCell(7),
                            buildCell(8),
                          ],
                        ),
                      ],
                    ),
                    if (!gameStarted)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withOpacity(0.5),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.lock_rounded,
                                    size: 20.0, color: Colors.white),
                                Text("Game hasn't begun",
                                    style: GoogleFonts.acme(
                                        fontSize: 15, color: Colors.white))
                              ],
                            ),
                          ),
                        ),
                      ),
                  ]),

                  const SizedBox(height: 20),

                  // P1 / P2 / CLOSE buttons
                  if (maxBotIntelligence != 0.0)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: gameStarted
                                ? null
                                : () {
                                    selectPlayer(1);
                                  },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.circle_outlined),
                            label: const Text("P1"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: gameStarted
                                ? null
                                : () {
                                    selectPlayer(2);
                                  },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.close),
                            label: const Text("P2"),
                          ),
                        ),
                      ],
                    ),
                  if (maxBotIntelligence == 0.0 && !gameStarted)
                    Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          for (var data in _gameDifficulties)
                            Column(children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    ElevatedButton(
                                        onPressed: () => setState(() {
                                              maxBotIntelligence = data[1];
                                            }),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor: data[3],
                                            foregroundColor: Colors.white),
                                        child: Text(data[0],
                                            style: GoogleFonts.acme(
                                                fontSize: 15))),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          _pts(data[2] as int),
                                          SizedBox(width: 10),
                                        ]),
                                  ]),
                              SizedBox(height: 5),
                            ]),
                        ]),

                  SizedBox(height: 8),

                  Row(children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: Text("CLOSE",
                            style: GoogleFonts.acme(fontSize: 15)),
                      ),
                    ),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<Directory> _familyPhotoDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/family_photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _copyPictureToStorage(XFile picture) async {
    final Directory dir = await _familyPhotoDir();
    final String ext =
        picture.path.contains('.') ? picture.path.split('.').last : 'jpg';
    final String newPath =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await File(picture.path).copy(newPath);
    return newPath;
  }

  Future<List<Map<String, String>>> _loadFamilyData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString("FAMILY_PHOTOS");
    final List<Map<String, String>> result = [];
    if (raw == null) return result;

    try {
      final List<dynamic> decoded = jsonDecode(raw);
      for (final item in decoded) {
        final String path = item["path"] as String;
        final String name = item["name"] as String;
        // skip photos whose file no longer exists
        if (await File(path).exists()) {
          result.add({"path": path, "name": name});
        }
      }
    } catch (e) {
      debugPrint("Failed to load family photos: $e");
    }
    return result;
  }

  Future<void> _saveFamilyData(List<Map<String, String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("FAMILY_PHOTOS", jsonEncode(data));
  }

  Future<void> _FamilyGame() async {
    // photos + names saved from last time
    final List<Map<String, String>> family = await _loadFamilyData();
    if (!mounted) return;

    final TextEditingController familyGameController = TextEditingController();
    final Random random = Random();
    bool showPictures = true;
    int randomNumber = 0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            // keeps the index valid even after deleting photos
            final int currentIndex =
                randomNumber < family.length ? randomNumber : 0;

            Future<void> pickPictures() async {
              final ImagePicker picker = ImagePicker();
              final List<XFile> pictures = await picker.pickMultiImage();

              for (final picture in pictures) {
                final TextEditingController nameController =
                    TextEditingController();

                await showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: Text(
                        "Who is this?",
                        style: GoogleFonts.acme(fontSize: 25),
                      ),
                      content: TextField(
                        controller: nameController,
                        maxLength: 9,
                        decoration: const InputDecoration(
                          hintText: "Enter name",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("ADD"),
                        ),
                      ],
                    );
                  },
                );

                final String name = nameController.text.trim();
                if (name.isEmpty) continue;

                final String savedPath = await _copyPictureToStorage(picture);
                family.add({"path": savedPath, "name": name});
                await _saveFamilyData(family);
                dialogSetState(() {});
              }
            }

            Future<void> deletePicture(int index) async {
              final String path = family[index]["path"]!;
              family.removeAt(index); // removes photo AND its name together
              await _saveFamilyData(family);
              try {
                final File file = File(path);
                if (await file.exists()) await file.delete();
              } catch (_) {}
              dialogSetState(() {});
            }

            return AlertDialog(
              title: Text(
                "Family Game",
                style: GoogleFonts.acme(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 500,
                height: 400,
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: pickPictures,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: Text(
                        "IMPORT PHOTOS",
                        style: GoogleFonts.acme(fontSize: 20),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: family.isEmpty
                          ? Center(
                              child: Text(
                                "No photos imported yet",
                                style: GoogleFonts.acme(fontSize: 20),
                              ),
                            )
                          : (showPictures
                              // ----- photo grid -----
                              ? GridView.builder(
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 10,
                                    mainAxisSpacing: 10,
                                    childAspectRatio: 0.75,
                                  ),
                                  itemCount: family.length,
                                  itemBuilder: (context, index) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: Container(
                                                  color: Colors.black12,
                                                  child: Image.file(
                                                    File(
                                                        family[index]["path"]!),
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                top: 5,
                                                right: 5,
                                                child: GestureDetector(
                                                  onTap: () =>
                                                      deletePicture(index),
                                                  child: Container(
                                                    decoration:
                                                        const BoxDecoration(
                                                      color: Colors.red,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(
                                                      Icons.close,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          family[index]["name"]!,
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.acme(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                )
                              // ----- guessing mode -----
                              : SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 300,
                                        height: 200,
                                        color: Colors.blue,
                                        child: Image.file(
                                          File(family[currentIndex]["path"]!),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller: familyGameController,
                                        decoration: const InputDecoration(
                                          hintText: "Enter name",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!showPictures && family.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      final String answer =
                          familyGameController.text.trim().toLowerCase();
                      final String correct =
                          family[currentIndex]["name"]!.trim().toLowerCase();

                      if (answer == correct) {
                        setState(() {
                          points++;
                        });
                        _configPointsData(true);
                        familyGameController.clear();

                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(
                                "Correct!",
                                style: GoogleFonts.acme(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: Text(
                                "+1 Point!\nYour points: ${points.toStringAsFixed(2)}",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.acme(fontSize: 20),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "OK",
                                    style: GoogleFonts.acme(fontSize: 20),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      } else {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(
                                "Incorrect!",
                                style: GoogleFonts.acme(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: Text(
                                "Try again!",
                                style: GoogleFonts.acme(fontSize: 20),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "OK",
                                    style: GoogleFonts.acme(fontSize: 20),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      "Submit",
                      style: GoogleFonts.acme(fontSize: 20),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    if (family.isNotEmpty) {
                      dialogSetState(() {
                        showPictures = !showPictures;
                        randomNumber = random.nextInt(family.length);
                      });
                    }
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    "hide/show",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    "CLOSE",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _MathGame() async {
    int number1 = 0;
    int number2 = 0;
    int operators = 0;
    String operatorText = "";
    int answerMath = 0;
    int answerPlayerMath = 1000000;
    int number_range = 5;
    int levelPoint = 0;
    bool isFirstQuestion = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            void StartMath() {
              int newNumber1 = Random().nextInt(number_range);
              int newNumber2 = Random().nextInt(number_range);
              int newOperator = Random().nextInt(3) + 1;

              dialogSetState(() {
                number1 = newNumber1;
                number2 = newNumber2;
                operators = newOperator;

                if (operators == 1) {
                  answerMath = number1 + number2;
                  operatorText = "+";
                } else if (operators == 2) {
                  answerMath = number1 - number2;
                  operatorText = "-";
                } else {
                  answerMath = number1 * number2;
                  operatorText = "x";
                }

                numberController.clear();
              });
            }

            return AlertDialog(
              scrollable: true,
              title: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Math Game",
                      style: GoogleFonts.acme(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: (levelPoint == 1)
                            ? Colors.green
                            : (levelPoint == 3
                                ? Colors.yellow
                                : (levelPoint == 5
                                    ? Colors.red
                                    : Colors.black)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        levelPoint == 1
                            ? " EASY mode (1 pts) "
                            : (levelPoint == 3
                                ? " MEDIUM mode (3 pts) "
                                : (levelPoint == 5
                                    ? " HARD mode (5 pts) "
                                    : " Select a difficulty to play! ")),
                        style: GoogleFonts.acme(
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ]),
              content: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "$number1",
                        style: GoogleFonts.acme(fontSize: 30),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        operatorText,
                        style: GoogleFonts.acme(fontSize: 30),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "$number2",
                        style: GoogleFonts.acme(fontSize: 30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: numberController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Enter your answer",
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      int? answerPlayerMath =
                          int.tryParse(numberController.text);

                      if (answerPlayerMath == null || levelPoint == 0) {
                        return;
                      }

                      if (answerPlayerMath != answerMath) {
                        showDialog(
                          context: context,
                          builder: (context) {
                            return AlertDialog(
                              title: Text(
                                "Incorrect!",
                                style: GoogleFonts.acme(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              content: Text(
                                "Try again!",
                                style: GoogleFonts.acme(fontSize: 20),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                  },
                                  child: Text(
                                    "OK",
                                    style: GoogleFonts.acme(fontSize: 20),
                                  ),
                                ),
                              ],
                            );
                          },
                        );

                        return;
                      }

                      _awardUserPoints(
                          "Arithmetic Speedrun", levelPoint, isFirstQuestion);
                      isFirstQuestion = false;
                      StartMath();

                      // setState(() {
                      //   points = points + levelPoint * multiplier;
                      //   _configPointsData(true);
                      // });

                      // showDialog(
                      //   context: context,
                      //   builder: (context) {
                      //     return AlertDialog(
                      //       title: Text(
                      //         "Correct!",
                      //         style: GoogleFonts.acme(
                      //           fontSize: 30,
                      //           fontWeight: FontWeight.bold,
                      //         ),
                      //       ),
                      //       content: Text(
                      //         "+ $levelPoint points!\nYour points: $points",
                      //         textAlign: TextAlign.center,
                      //         style: GoogleFonts.acme(fontSize: 20),
                      //       ),
                      //       actions: [
                      //         TextButton(
                      //           onPressed: () {
                      //             Navigator.pop(context);
                      //             StartMath();
                      //           },
                      //           child: Text(
                      //             "OK",
                      //             style: GoogleFonts.acme(fontSize: 20),
                      //           ),
                      //         ),
                      //       ],
                      //     );
                      //   },
                      // );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          levelPoint == 0 ? Colors.grey : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Submit"),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          dialogSetState(() {
                            levelPoint = 1;
                            number_range = 10;
                            if (operators == 0 || levelPoint != 1) StartMath();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          elevation: levelPoint == 1 ? 12 : 2,
                          shadowColor: levelPoint == 1
                              ? Colors.yellowAccent
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                                color: Colors.green.shade800, width: 4.0),
                          ),
                        ),
                        child:
                            Text("Easy", style: GoogleFonts.acme(fontSize: 15)),
                      ),
                      _pts(1)
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          dialogSetState(() {
                            levelPoint = 3;
                            number_range = 20;
                            if (operators == 0 || levelPoint != 3) StartMath();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow,
                          foregroundColor: Colors.white,
                          elevation: levelPoint == 3 ? 12 : 2,
                          shadowColor: levelPoint == 3
                              ? Colors.yellowAccent
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                                color: Colors.yellow.shade800, width: 4.0),
                          ),
                        ),
                        child: Text("Medium",
                            style: GoogleFonts.acme(fontSize: 15)),
                      ),
                      _pts(3)
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          dialogSetState(() {
                            levelPoint = 5;
                            number_range = 50;
                            if (operators == 0 || levelPoint != 5) StartMath();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: levelPoint == 5 ? 12 : 2,
                          shadowColor: levelPoint == 5
                              ? Colors.yellowAccent
                              : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: BorderSide(
                                color: Colors.red.shade800, width: 4.0),
                          ),
                        ),
                        child:
                            Text("Hard", style: GoogleFonts.acme(fontSize: 15)),
                      ),
                      _pts(5)
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: levelPoint == 0 ? null : StartMath,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        levelPoint == 0 ? Colors.grey : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    operators != 0 ? "SKIP" : "Start",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    "CLOSE",
                    style: GoogleFonts.acme(fontSize: 20),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  late final Map<String, List<dynamic>> _minigameData = {
    "Pattern Memory": [_PatternMemory, "patternmemory_icon.png"],
    "My Family": [_FamilyGame, "family_icon.png"],
    "Arithmetic Speedrun": [_MathGame, "arithmetic_icon.png"],
    "Puzzle Game": [_PuzzleGame, "puzzlegame_icon.png"],
    "Tic-Tac-Toe VS Bot": [_TicTacToe, "tictactoe_icon.png"],
  };

  @override
  void initState() {
    super.initState();
    _configPointsData(false);

    _pointsSpinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    //WidgetsBinding.instance.addPostFrameCallback((_) => _awardUserPoints("Testificate", 5));
  }

  @override
  void dispose() {
    _configPointsData(true);
    _pointsSpinController.dispose();
    super.dispose();
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   _stopBackgroundMusic();
  // }

  @override
  Widget build(BuildContext context) {
    final Size _screenSize = MediaQuery.of(context).size;
    final double _minigameBoxHeight = _screenSize.height * 0.1;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/Minigames",
                style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.videogame_asset_sharp, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Container(
        width: _screenSize.width,
        height: _screenSize.height,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/game_bg.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
            child: SingleChildScrollView(
          child: Container(
            width: _screenSize.width * 0.8,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 5),
                          Text("Games to train your brain",
                              style: GoogleFonts.acme(
                                  fontSize: 17, color: Colors.white))
                        ]),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset("assets/pointsicon.png",
                            width: 30, height: 30),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Points: ${points.toStringAsFixed(2)}",
                                  style: GoogleFonts.acme(
                                      fontSize: 12, color: Colors.white)),
                              Text("Multiplier: ${multiplier}x",
                                  style: GoogleFonts.acme(
                                      fontSize: 12, color: Colors.white)),
                            ]),
                        SizedBox(width: 5),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                      onPressed: () =>
                          _showMultiplierExplanation(context, points),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.purple.shade300,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                          side: const BorderSide(
                            color: Colors.purple,
                            width: 3.0,
                          ),
                        ),
                      ),
                      label: Text("What are multipliers?",
                          style: GoogleFonts.acme(
                              fontSize: 12,
                              decoration: TextDecoration.underline)),
                      icon: const Icon(Icons.info_rounded, size: 14.0)),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var minigameEntry in _minigameData.entries)
                        Column(children: [
                          Container(
                            width: _screenSize.width * 0.75,
                            height: _minigameBoxHeight,
                            decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(5.0)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                SizedBox(width: 5),
                                Image.asset("assets/${minigameEntry.value[1]}",
                                    width: _minigameBoxHeight * 0.8,
                                    height: _minigameBoxHeight * 0.8),
                                SizedBox(width: 10),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(minigameEntry.key,
                                        style: GoogleFonts.acme(fontSize: 20)),
                                    ElevatedButton(
                                        onPressed: () =>
                                            minigameEntry.value[0](),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          side: BorderSide(
                                            color: Colors.green.shade900,
                                            width: 5,
                                          ),
                                        ),
                                        child: Text("PLAY NOW",
                                            style:
                                                GoogleFonts.acme(fontSize: 15)))
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ]),
                    ],
                  ),
                ]),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

class MusicLibrary extends StatefulWidget {
  const MusicLibrary({Key? key}) : super(key: key);

  @override
  State<MusicLibrary> createState() => _MusicLibraryState();
}

class _MusicLibraryState extends State<MusicLibrary> {
  Timer? _timer;
  final List<List<String>> _musicData = [
    [
      "Classical",
      "For those who have a similar music taste with Mozart himself"
    ],
    ["Nature", "Sounds from mother nature herself, but in mp3 file format"],
    ["Relaxing", "Tired of all the stress? Here's a cure for that."]
  ];

  final List<String> _splashText = [
    "Calm soothing music 4 u",
    "Having a rough day? Listen to us!",
    "For those with good taste of music",
    "Noises to cure anxiety",
    "You'll love our music picks"
  ];
  int _unixTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  int _cSTIndex = 0; //_currentSplashTextIndex
  String _tempSplashText = "";
  int _splashTextUnixTimer = 0; //these will be used later - vino
  bool _splashTextTypingState = true; //true = typing, false = backspacing

  void _continuousTicks() {
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      setState(() {
        _unixTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (_tempSplashText !=
                (_splashTextTypingState ? _splashText[_cSTIndex] : "") &&
            _splashTextUnixTimer < _unixTime) {
          if (_splashTextTypingState)
            _tempSplashText += _splashText[_cSTIndex][_tempSplashText.length];
          else
            _tempSplashText =
                _tempSplashText.substring(0, _tempSplashText.length - 1);

          if (_tempSplashText ==
              (_splashTextTypingState ? _splashText[_cSTIndex] : "")) {
            if (_splashTextTypingState)
              _splashTextUnixTimer = _unixTime + 3;
            else {
              _cSTIndex++;
              _cSTIndex = _cSTIndex % _splashText.length;
            }
            _splashTextTypingState = !_splashTextTypingState;
          }
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _continuousTicks();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   _timer?.cancel();
  //   _stopBackgroundMusic();
  // }

  @override
  Widget build(BuildContext context) {
    final Size _screenSize = MediaQuery.of(context).size;
    return Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text("${_appName}/Music Library",
                  style: GoogleFonts.acme(fontSize: 20)),
              SizedBox(width: 20),
              Icon(Icons.videogame_asset_sharp, size: 20),
            ],
          ),
          backgroundColor: Colors.blueGrey.shade800,
          foregroundColor: Colors.white,
        ),
        body: Container(
          width: _screenSize.width,
          height: _screenSize.height,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/music_bg.png"),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 20),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 20),
                      Center(
                          child: Text(_tempSplashText,
                              style: GoogleFonts.acme(
                                  fontSize: 20,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold))),
                      for (List<String> data in _musicData)
                        Column(
                          children: [
                            SizedBox(height: 20),
                            Container(
                              width: _screenSize.width * 0.9,
                              height: _screenSize.height * 0.2,
                              decoration: BoxDecoration(
                                color: Colors.lightGreen.shade300,
                                border: Border.all(
                                  color: Colors.lightGreen.shade800,
                                  width: 4.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(128),
                                    spreadRadius: 2,
                                    blurRadius: 5,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(width: 10),
                                      Image.asset(
                                        'assets/albumIcons/${data[0]}.png',
                                        width: _screenSize.height *
                                            0.15, // <- yes this is intentional, i want width:height ratio to be 1:1
                                        height: _screenSize.height * 0.15,
                                        fit: BoxFit.cover,
                                      ),
                                      SizedBox(width: 10),
                                      Container(
                                        width: _screenSize.width * 0.3,
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text("${data[0]}.mp3",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15.0)),
                                              Text("Description: ${data[1]}",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 10.0)),
                                            ]),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      ValueListenableBuilder<String?>(
                                        valueListenable: currentTrack,
                                        builder: (context, track, _) {
                                          final isPlaying =
                                              track == "${data[0]}.mp3";
                                          return SizedBox(
                                            width: _screenSize.width * 0.1,
                                            height: _screenSize.width * 0.1,
                                            child: ElevatedButton(
                                              onPressed: () async {
                                                if (isPlaying) {
                                                  await _startBackgroundMusic(
                                                      "default_bgm.mp3"); // back to default
                                                } else {
                                                  await _startBackgroundMusic(
                                                      "${data[0]}.mp3");
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                padding: EdgeInsets.zero,
                                                backgroundColor: isPlaying
                                                    ? Colors.red
                                                    : Colors.green,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          _screenSize.width *
                                                              0.05),
                                                  side: BorderSide(
                                                    color: isPlaying
                                                        ? Colors.red.shade800
                                                        : Colors.green.shade800,
                                                    width: 3.0,
                                                  ),
                                                ),
                                                elevation: 8,
                                                shadowColor:
                                                    Colors.black.withAlpha(128),
                                              ),
                                              child: Icon(isPlaying
                                                  ? Icons.stop
                                                  : Icons.play_arrow),
                                            ),
                                          );
                                        },
                                      ),
                                      SizedBox(width: 10),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  )
                ],
              ),
            ),
          ),
        ));
  }
}

class Towerpage extends StatefulWidget {
  const Towerpage({super.key});

  @override
  State<Towerpage> createState() => _TowerpageState();
}

class _TowerpageState extends State<Towerpage> {
  Timer? _timer;
  double _points = 0.0;
  int _towerHeight = 0;
  List<String> _tierData = [];
  List<String> _balconyData = [];
  String _username = "user123";
  bool _showTowerSettings = false;
  double _scrollHeight = 0;
  double _scrollMax = 0;
  bool _scrollingEnabled = true;
  int _unixSeconds = 0;
  double _towerUpgradesUISize = 0.0;
  Map<String, dynamic> _towerBuildTransitionData = {
    "delay": 0,
    "craneHeight": 0.0,
    "craneHeightMax": 0.0,
    "craneHeightMin": 0.0,
    "flash": 0
  };

  final List<String> _tierNames = ["A", "B", "C"];
  final Map<String, MaterialColor> _tierColors = {
    "A": Colors.red,
    "B": Colors.blue,
    "C": Colors.amber
  };

  final AudioPlayer _towerBuildSound = AudioPlayer();
  final List<double> _towerFloorSizes = [0.7, 0.1];
  final ScrollController _scrollController = ScrollController();

  final List<List<dynamic>> _towerUpgradesData = [
    ["INCREASE HEIGHT", 4, 0, 0.2],
    ["UPGRADE FLOOR", 3, 5, 0.1],
    ["ADD BALCONY", 2, 7, 0.1],
  ]; //upgrade name, points price, floor requirement
  String _currentRunningUpgrade = "";
  void _endUpgradeRun() {
    setState(() {
      debugPrint("Ending upgrade run : $_currentRunningUpgrade");
      _currentRunningUpgrade = "";
      _showTowerSettings = true;
    });
  }

  Container _renderTower(Size _screenSize, int index, String assetPath) {
    return Container(
      width: _screenSize.width * _towerFloorSizes[0],
      height: _screenSize.height * _towerFloorSizes[1],
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              assetPath,
              fit: BoxFit.fill,
            ),
          ),
          if (_balconyData[index] != "0")
            Center(
              child: Transform.translate(
                offset: const Offset(0, 23),
                child: SizedBox(
                  width: _screenSize.width * _towerFloorSizes[0] * 0.4,
                  height: _screenSize.height * _towerFloorSizes[1] * 0.4,
                  child: Image.asset(
                    "assets/balcony_${_balconyData[index]}.png",
                    fit: BoxFit.fill,
                  ),
                ),
              ),
            ),

          // Text goes here
          Positioned(
            top: 5,
            left: 10,
            child: Text(
              "Floor ${index + 1}",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
          ),
          SizedBox(height: 5),

          if (_tierData[index] != "A")
            Positioned(
              top: 38,
              left: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: _tierColors[_tierData[index]],
                  borderRadius: BorderRadius.circular(5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey,
                        blurRadius: 5,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: Center(
                    child: Text("Tier ${_tierData[index]}",
                        style: GoogleFonts.acme(
                            fontSize: 10, color: Colors.white))),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _configUserData(bool save) async {
    final prefs = await SharedPreferences.getInstance();

    if (save) {
      await prefs.setDouble("POINTS", _points);
      await prefs.setInt("TOWER_HEIGHT", _towerHeight);
      await prefs.setString("TOWER_TIERDATA", _tierData.join(","));
      await prefs.setString("TOWER_BALCONIES", _balconyData.join(","));
      debugPrint("parsed TIER DATA : $_tierData");
      debugPrint("raw TIER DATA : ${_tierData.join(",")}");
    } else {
      setState(() {
        _points = prefs.getDouble("POINTS") ?? 0.0;
        _towerHeight = prefs.getInt("TOWER_HEIGHT") ?? 0;
        _tierData = (prefs.getString("TOWER_TIERDATA") ?? "").split(",");
        if (_tierData.length != _towerHeight) {
          _tierData.clear();
          _tierData = List.generate(_towerHeight, (index) => "A");
        }

        _balconyData = (prefs.getString("TOWER_BALCONIES") ?? "").split(",");
        if (_balconyData.length != _towerHeight) {
          _balconyData.clear();
          _balconyData = List.generate(_towerHeight, (index) => "0");
        }
        debugPrint("parsed TIER DATA : $_tierData");
        debugPrint(_tierData.isEmpty
            ? "Parsed data is empty"
            : "Parsed data is NOT empty");
        debugPrint(
            "raw TIER DATA : ${prefs.getString("TOWER_TIERDATA") ?? ""}");
      });
    }
  }

  void continuousTicks() {
    _timer?.cancel();

    _timer = Timer.periodic(Duration(milliseconds: 16), (Timer timer) {
      setState(() {
        _unixSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (_showTowerSettings && _currentRunningUpgrade == "") {
          if (_towerUpgradesUISize <= 0.55) {
            _towerUpgradesUISize += (0.6 - _towerUpgradesUISize) * 0.2;
          } else {
            _towerUpgradesUISize = 0.6;
          }
        } else {
          if (_towerUpgradesUISize >= 0.05) {
            _towerUpgradesUISize -= _towerUpgradesUISize * 0.2;
          } else {
            _towerUpgradesUISize = 0;
          }
        }

        if (_currentRunningUpgrade == "INCREASE HEIGHT") {
          if ((_towerBuildTransitionData["delay"] ?? 0) < _unixSeconds &&
              (_towerBuildTransitionData["delay"] ?? 0) > 0 &&
              (_towerBuildTransitionData["flash"] ?? 0) > 0) {
            if (_towerBuildTransitionData["flash"] >= 255) {
              () async {
                await _towerBuildSound.stop();
                await _towerBuildSound
                    .play(AssetSource("sounds/buildingComplete_sfx.mp3"));
              }();
            }
            _towerBuildTransitionData["flash"] =
                _towerBuildTransitionData["flash"]! - 5;
            _showTowerSettings = false;
            if (_towerBuildTransitionData["flash"]! <= 0) {
              _towerBuildTransitionData["delay"] = 0;
              _scrollingEnabled = true;
              _showTowerSettings = true;
              _towerBuildTransitionData["craneHeightMax"] = 0.0;
              //_towerBuildSound.stop();
            }
          }

          if ((_towerBuildTransitionData["craneHeightMax"] ?? 0) >
              (_towerBuildTransitionData["craneHeight"] ?? 0)) {
            _towerBuildTransitionData["craneHeight"] +=
                (_towerBuildTransitionData["craneHeightMax"] -
                        _towerBuildTransitionData["craneHeight"]) *
                    0.2;
          } else if ((_towerBuildTransitionData["craneHeightMax"] ?? 0.0) ==
                  0.0 &&
              (_towerBuildTransitionData["craneHeight"] ?? 0) > 0) {
            _towerBuildTransitionData["craneHeight"] -=
                _towerBuildTransitionData["craneHeight"] * 0.2;

            debugPrint(
                "${_towerBuildTransitionData["craneHeight"].toInt().toString()} / ${_towerBuildTransitionData["craneHeightMin"].toInt().toString()}");
            if (_towerBuildTransitionData["craneHeight"] <
                _towerBuildTransitionData["craneHeightMin"]) {
              _endUpgradeRun();
              _towerBuildTransitionData["craneHeight"] = 0.0;
            }
          }
        } else if ((_currentRunningUpgrade == "UPGRADE FLOOR" ||
                _currentRunningUpgrade == "ADD BALCONY") &&
            !_towerBuildTransitionData["showDialog"]) {
          if (_towerBuildTransitionData["flash"] > 0) {
            if (_towerBuildTransitionData["flash"] == 255) {
              _towerBuildSound.stop();
              _towerBuildSound
                  .play(AssetSource("sounds/towerFloor_upgrade.mp3"));

              if (_currentRunningUpgrade == "UPGRADE FLOOR") {
                _tierData[_towerBuildTransitionData["selectedFloor"]] =
                    _tierNames[_tierNames.indexOf(_tierData[
                            _towerBuildTransitionData["selectedFloor"]]) +
                        1];
                _points -= 3;
              } else {
                _balconyData[_towerBuildTransitionData["selectedFloor"]] =
                    _towerBuildTransitionData["selectedBalcony"].toString();
                debugPrint("NEW BALCONY DATA: ${_balconyData}");
                _points -= 2;
              }

              debugPrint(
                  "new tier for floor ${_towerBuildTransitionData["selectedFloor"]} : ${_tierData[_towerBuildTransitionData["selectedFloor"]]}");
              _configUserData(true);
            }
            _towerBuildTransitionData["flash"] -= 5;
          } else {
            _endUpgradeRun();
          }
        }
      });
    });
  }

  Future<void> _upgradeTower(
      String upgradeType, int upgradePrice, Size screenSize) async {
    setState(() {
      // _towerBuildTransitionData.clear();
      _currentRunningUpgrade = upgradeType;
      debugPrint("Current running upgrade : $_currentRunningUpgrade");
    });
    if (upgradeType == "INCREASE HEIGHT") {
      setState(() {
        _scrollingEnabled = false;
        _showTowerSettings = false;
        multiplier += 0.2;
        multiplier = (multiplier * 10).round() / 10;
        _towerHeight++;
        _points -= upgradePrice;
        _tierData.add("A");
        _balconyData.add("0");

        _towerBuildTransitionData["delay"] = _unixSeconds + 3;
        _towerBuildTransitionData["flash"] = 255;
        _towerBuildTransitionData["craneHeightMax"] = _towerFloorSizes[1] *
            screenSize.height *
            (_towerHeight.clamp(1, 5) + 1);
        _towerBuildTransitionData["craneHeight"] = 0;
        _towerBuildTransitionData["craneHeightMin"] = screenSize.height * 0.1;
      });

      await _towerBuildSound.stop();
      await _towerBuildSound.play(AssetSource("sounds/building_sfx.mp3"));

      await WidgetsBinding.instance.endOfFrame;

      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } else if (upgradeType == "UPGRADE FLOOR") {
      setState(() {
        _towerBuildTransitionData["showDialog"] = true;
        _towerBuildTransitionData["selectedFloor"] = -1;
        _towerBuildTransitionData["flash"] = 0;
      });
    } else if (upgradeType == "FREE POINTS") {
      setState(() {
        _points += 5.0;
        _currentRunningUpgrade = "";
      });
    } else if (upgradeType == "RESET TOWER HEIGHT") {
      setState(() {
        _towerHeight = 0;
        _currentRunningUpgrade = "";
      });
    } else if (upgradeType == "MAXTOWER") {
      setState(() {
        for (var i = _towerHeight; i <= 50; i++) _tierData.add("A");
        _towerHeight = 50;
        _endUpgradeRun();
      });
    } else if (upgradeType == "ADD BALCONY") {
      _towerBuildTransitionData["showDialog"] = true;
      _towerBuildTransitionData["selectedFloor"] = -1;
      _towerBuildTransitionData["flash"] = 0;
      _towerBuildTransitionData["selectedBalcony"] = 0;
    }
    await _configUserData(true);
    await saveMultiplier();
  }

  @override
  void initState() {
    super.initState();

    continuousTicks();

    _scrollController.addListener(() {
      if (!mounted) return;

      setState(() {
        _scrollHeight = _scrollController.offset;
        _scrollMax = _scrollController.position.maxScrollExtent;
      });
    });

    _initializeTower();
  }

  Future<void> _initializeTower() async {
    await _configUserData(false);

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _username = prefs.getString("NAME") ?? "user";
    });

    if (_towerHeight == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        showDialog(
          barrierDismissible: false,
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Center(
                child: Text(
                  "Welcome to Caligo Tower!",
                  style: GoogleFonts.acme(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              content: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Start building your tower by spending your points to construct new floors!",
                    style: GoogleFonts.acme(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  if (_points == 0)
                    Text(
                      "It seems like you dont have points yet, let's gather some!",
                      style: GoogleFonts.acme(
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                ],
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_points == 0.0) {
                            debugPrint("Redirecting to minigames!");

                            Navigator.pop(context);
                            Navigator.pop(context);

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => Minigame(),
                              ),
                            );
                          } else {
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              _points == 0.0 ? Colors.green : Colors.amber,
                          foregroundColor:
                              _points == 0.0 ? Colors.white : Colors.black,
                        ),
                        child: Text(
                          _points == 0.0
                              ? "GATHER POINTS"
                              : "Start Construction",
                          style: GoogleFonts.acme(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   _timer?.cancel();
  //   _stopBackgroundMusic();
  // }

  @override
  Widget build(BuildContext context) {
    final Size _screenSize = MediaQuery.of(context).size;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/MyTower", style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.videogame_asset_sharp, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/tower_skybg.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // Second background image (e.g., top/overlay layer)
          // Positioned(
          //   bottom: 0,
          //   left: 0,
          //   right: 0,
          //   child: Image.asset(
          //     'assets/images/background_overlay.png',
          //     fit: BoxFit.cover,
          //   ),
          // ),
          // Your actual page content goes here

          Positioned(
              bottom: _scrollHeight - _scrollMax,
              left: 0,
              child: Container(
                width: _screenSize.width,
                height: _towerFloorSizes[1] * _screenSize.height,
                child:
                    Image.asset('assets/ground_level_1.png', fit: BoxFit.fill),
              )),

          Center(
            child: SafeArea(
              child: SingleChildScrollView(
                physics: !_scrollingEnabled
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                controller: _scrollController,
                child: Column(
                  children: [
                    SizedBox(
                      height: _screenSize.height *
                          ((10 - _towerHeight).clamp(4, 10) / 10),
                    ),
                    for (var i = _towerHeight - 1; i >= 0; i--)
                      Stack(
                        children: [
                          ((_currentRunningUpgrade == "UPGRADE FLOOR" ||
                                      _currentRunningUpgrade ==
                                          "ADD BALCONY") &&
                                  _towerBuildTransitionData["showDialog"] &&
                                  _tierData[i] !=
                                      _tierNames[_tierNames.length - 1])
                              ? GestureDetector(
                                  onTap: () => setState(() =>
                                      _towerBuildTransitionData[
                                          "selectedFloor"] = i),
                                  child: _renderTower(_screenSize, i,
                                      "assets/Tower${_tierData[i]}.png"),
                                )
                              : _renderTower(_screenSize, i,
                                  "assets/Tower${_tierData[i]}.png"),
                          if ((_currentRunningUpgrade == "INCREASE HEIGHT")
                              ? (i == _towerHeight - 1 &&
                                  (_towerBuildTransitionData["flash"] ?? 0) > 0)
                              : ((_currentRunningUpgrade == "UPGRADE FLOOR" ||
                                      _currentRunningUpgrade == "ADD BALCONY")
                                  ? (i ==
                                      _towerBuildTransitionData[
                                          "selectedFloor"])
                                  : false))
                            Container(
                              width: _towerFloorSizes[0] * _screenSize.width,
                              height: _towerFloorSizes[1] * _screenSize.height,
                              color: Colors.white.withAlpha(
                                  (_currentRunningUpgrade ==
                                              "INCREASE HEIGHT" ||
                                          ((_currentRunningUpgrade ==
                                                      "UPGRADE FLOOR" ||
                                                  _currentRunningUpgrade ==
                                                      "ADD BALCONY") &&
                                              !_towerBuildTransitionData[
                                                  "showDialog"]))
                                      ? _towerBuildTransitionData["flash"]
                                      : 128),
                            )
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: _screenSize.height - _towerBuildTransitionData["craneHeight"],
            left: 0,
            child: Container(
              // width: _screenSize.width * _towerFloorSizes[0],
              height: _towerFloorSizes[1] * _screenSize.height * 6,
              child: Image.asset(
                'assets/crane.png',
                fit: BoxFit.cover,
              ),
            ),
          ),

          if ((_towerBuildTransitionData["showDialog"] ?? false) &&
              _currentRunningUpgrade == "UPGRADE FLOOR")
            Positioned(
              top: 50,
              left: 10,
              child: Container(
                height: 200,
                width: 200,
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(128),
                  borderRadius: BorderRadius.circular(10.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 10.0,
                      spreadRadius: 2.0,
                      offset: const Offset(0, 4), // Moves shadow down slightly
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 10),
                    Center(
                      child: Text("Tap a floor to upgrade.",
                          style: GoogleFonts.acme(
                              fontSize: 15, color: Colors.white)),
                    ),
                    Center(
                        child: Text(
                            "Selecting : floor ${((_towerBuildTransitionData["selectedFloor"] ?? -1) + 1) != 0 ? _towerBuildTransitionData["selectedFloor"] + 1 : "NONE"}",
                            style: GoogleFonts.acme(
                                fontSize: 12, color: Colors.white))),
                    if (_towerBuildTransitionData["selectedFloor"] != -1)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(width: 5),
                              Text("Floor Tier:",
                                  style: GoogleFonts.acme(
                                      fontSize: 18, color: Colors.white)),
                              SizedBox(width: 5),
                              Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  color: _tierColors[_tierData[
                                      _towerBuildTransitionData[
                                              "selectedFloor"] ??
                                          0]],
                                  borderRadius: BorderRadius.circular(4.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(50),
                                      blurRadius: 10.0,
                                      spreadRadius: 2.0,
                                      offset: const Offset(
                                          0, 4), // Moves shadow down slightly
                                    ),
                                  ],
                                ),
                                child: Center(
                                    child: Text(
                                        _tierData[_towerBuildTransitionData[
                                            "selectedFloor"]],
                                        style: GoogleFonts.acme(
                                            fontSize: 15,
                                            color: Colors.white))),
                              ),
                              SizedBox(width: 5),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 20.0, color: Colors.white),
                              SizedBox(width: 5),
                              Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  color: _tierColors[_tierNames[
                                      _tierNames.indexOf(_tierData[
                                              _towerBuildTransitionData[
                                                  "selectedFloor"]]) +
                                          1]],
                                  borderRadius: BorderRadius.circular(4.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(50),
                                      blurRadius: 10.0,
                                      spreadRadius: 2.0,
                                      offset: const Offset(
                                          0, 4), // Moves shadow down slightly
                                    ),
                                  ],
                                ),
                                child: Center(
                                    child: Text(
                                        _tierNames[_tierNames.indexOf(_tierData[
                                                _towerBuildTransitionData[
                                                    "selectedFloor"]]) +
                                            1],
                                        style: GoogleFonts.acme(
                                            fontSize: 15,
                                            color: Colors.white))),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          Row(
                            children: [
                              SizedBox(width: 5),
                              SizedBox(
                                height: 20,
                                width: 60,
                                child: Image.asset(
                                    "assets/Tower${_tierData[_towerBuildTransitionData["selectedFloor"]]}.png",
                                    fit: BoxFit.fill),
                              ),
                              SizedBox(width: 5),
                              Icon(Icons.arrow_forward_rounded,
                                  size: 20, color: Colors.white),
                              SizedBox(width: 5),
                              SizedBox(
                                height: 20,
                                width: 60,
                                child: Image.asset(
                                    "assets/Tower${_tierNames[_tierNames.indexOf(_tierData[_towerBuildTransitionData["selectedFloor"]]) + 1]}.png",
                                    fit: BoxFit.fill),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      debugPrint(
                                          "Cancelling upgrade for floor ${_towerBuildTransitionData["selectedFloor"]}");
                                      _towerBuildTransitionData["showDialog"] =
                                          false;
                                      _towerBuildTransitionData[
                                          "selectedFloor"] = 0;
                                      _endUpgradeRun();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.red,
                                      shadowColor: Colors.transparent),
                                  child: Text("Cancel",
                                      style: GoogleFonts.acme(fontSize: 15)),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    //actually upgrade the floor
                                    if (_towerBuildTransitionData[
                                            "selectedFloor"] ==
                                        -1) return;
                                    setState(() {
                                      multiplier += 0.1;
                                      debugPrint(
                                          "Upgrading floor ${_towerBuildTransitionData["selectedFloor"]}");
                                      _towerBuildTransitionData["showDialog"] =
                                          false;
                                      _towerBuildTransitionData["flash"] = 255;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          10.0), // Adjust corner radius
                                      side: BorderSide(
                                        color: Colors.green
                                            .shade900, // Outline border color
                                        width: 4.0, // Outline border thickness
                                      ),
                                    ),
                                  ),
                                  child: Text("UPGRADE",
                                      style: GoogleFonts.acme(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (_towerBuildTransitionData["selectedFloor"] == -1)
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(5.0),
                                border: Border.all(
                                    color: Colors.amber.shade900, width: 3.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey
                                        .withAlpha(128), // 4. Drop shadow
                                    spreadRadius: 2,
                                    blurRadius: 7,
                                    offset: const Offset(
                                        0, 3), // Changes position of shadow
                                  ),
                                ],
                              ),
                              child: Text(" TIP: Tap a floor to upgrade! ",
                                  style: GoogleFonts.acme(fontSize: 15)),
                            ),
                            SizedBox(height: 10),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  debugPrint(
                                      "Cancelling upgrade for floor ${_towerBuildTransitionData["selectedFloor"]}");
                                  _towerBuildTransitionData["showDialog"] =
                                      false;
                                  _towerBuildTransitionData["selectedFloor"] =
                                      0;
                                  _endUpgradeRun();
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.red,
                                  shadowColor: Colors.transparent),
                              child: Text("Cancel",
                                  style: GoogleFonts.acme(fontSize: 15)),
                            ),
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),

          if ((_towerBuildTransitionData['showDialog'] ?? false) &&
              _currentRunningUpgrade == "ADD BALCONY")
            Positioned(
              top: 60,
              left: 10,
              child: Container(
                  height: 280,
                  width: 260,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(128),
                    borderRadius: BorderRadius.circular(10.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(50),
                        blurRadius: 10.0,
                        spreadRadius: 2.0,
                        offset:
                            const Offset(0, 4), // Moves shadow down slightly
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 10),
                        Center(
                          child: Text("Tap a floor to add/change balcony.",
                              style: GoogleFonts.acme(
                                  fontSize: 14, color: Colors.white)),
                        ),
                        Center(
                            child: Text(
                                "Selecting : floor ${((_towerBuildTransitionData["selectedFloor"] ?? -1) + 1) != 0 ? _towerBuildTransitionData["selectedFloor"] + 1 : "NONE"}",
                                style: GoogleFonts.acme(
                                    fontSize: 12, color: Colors.white))),
                        if (_towerBuildTransitionData["selectedFloor"] != -1)
                          Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 10),
                              Row(children: [
                                const SizedBox(width: 10),
                                Text("Current balcony: ",
                                    style: GoogleFonts.acme(
                                        fontSize: 14, color: Colors.white)),
                                const SizedBox(width: 5),
                                if (_balconyData[_towerBuildTransitionData[
                                        "selectedFloor"]] ==
                                    "0")
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(0.0),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.block,
                                          size: 15, color: Colors.white),
                                      const SizedBox(width: 5),
                                      Text("NONE",
                                          style: GoogleFonts.acme(
                                              fontSize: 15,
                                              color: Colors.white))
                                    ]),
                                  ),
                                if (_balconyData[_towerBuildTransitionData[
                                        "selectedFloor"]] !=
                                    "0")
                                  SizedBox(
                                    height: 20,
                                    width: 60,
                                    child: Image.asset(
                                      "assets/balcony_${_balconyData[_towerBuildTransitionData["selectedFloor"]]}.png",
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                              ]),
                              SizedBox(height: 10),
                              Row(children: [
                                const SizedBox(width: 10),
                                Text("New balcony: ",
                                    style: GoogleFonts.acme(
                                        fontSize: 14, color: Colors.white)),
                                const SizedBox(width: 5),
                                if (_towerBuildTransitionData[
                                        "selectedBalcony"] ==
                                    0)
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(0.0),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.block,
                                          size: 15, color: Colors.white),
                                      const SizedBox(width: 5),
                                      Text("NONE",
                                          style: GoogleFonts.acme(
                                              fontSize: 15,
                                              color: Colors.white))
                                    ]),
                                  ),
                                if (_towerBuildTransitionData[
                                        "selectedBalcony"] >
                                    0)
                                  SizedBox(
                                    height: 20,
                                    width: 60,
                                    child: Image.asset(
                                      "assets/balcony_${_towerBuildTransitionData["selectedBalcony"]}.png",
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                              ]),
                              SizedBox(height: 10),
                              Center(
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ElevatedButton(
                                          onPressed: () => setState(() {
                                                _towerBuildTransitionData[
                                                    "selectedBalcony"]--;
                                                _towerBuildTransitionData[
                                                        "selectedBalcony"] =
                                                    _towerBuildTransitionData[
                                                            "selectedBalcony"] %
                                                        7;
                                              }),
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                          child: const Icon(Icons.arrow_back,
                                              size: 15)),
                                      const SizedBox(width: 5),
                                      if (_towerBuildTransitionData[
                                              "selectedBalcony"] >
                                          0)
                                        SizedBox(
                                          height: 20,
                                          width: 60,
                                          child: Image.asset(
                                              "assets/balcony_${_towerBuildTransitionData["selectedBalcony"]}.png",
                                              fit: BoxFit.fill),
                                        ),
                                      if (_towerBuildTransitionData[
                                              "selectedBalcony"] ==
                                          0)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.red,
                                            borderRadius:
                                                BorderRadius.circular(0.0),
                                          ),
                                          child: Row(children: [
                                            const Icon(Icons.block,
                                                size: 15, color: Colors.white),
                                            const SizedBox(width: 5),
                                            Text("NONE",
                                                style: GoogleFonts.acme(
                                                    fontSize: 15,
                                                    color: Colors.white))
                                          ]),
                                        ),
                                      const SizedBox(width: 5),
                                      ElevatedButton(
                                          onPressed: () => setState(() {
                                                _towerBuildTransitionData[
                                                    "selectedBalcony"]++;
                                                _towerBuildTransitionData[
                                                        "selectedBalcony"] =
                                                    _towerBuildTransitionData[
                                                            "selectedBalcony"] %
                                                        7;
                                              }),
                                          style: ElevatedButton.styleFrom(
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(5),
                                            ),
                                          ),
                                          child: const Icon(Icons.arrow_forward,
                                              size: 15)),
                                    ]),
                              ),
                              SizedBox(height: 20),
                              Center(
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton(
                                      onPressed: () {
                                        setState(() {
                                          debugPrint(
                                              "Cancelling upgrade for floor ${_towerBuildTransitionData["selectedFloor"]}");
                                          _towerBuildTransitionData[
                                              "showDialog"] = false;
                                          _towerBuildTransitionData[
                                              "selectedFloor"] = 0;
                                          _endUpgradeRun();
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          foregroundColor: Colors.red,
                                          shadowColor: Colors.transparent),
                                      child: Text("Cancel",
                                          style:
                                              GoogleFonts.acme(fontSize: 15)),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        //actually add the balcony

                                        if ((_towerBuildTransitionData[
                                                    "selectedFloor"] ==
                                                -1
                                            ? true
                                            : _balconyData[
                                                    _towerBuildTransitionData[
                                                        "selectedFloor"]] ==
                                                _towerBuildTransitionData[
                                                        "selectedBalcony"]
                                                    .toString())) return;

                                        setState(() {
                                          if (_balconyData[
                                                  _towerBuildTransitionData[
                                                      "selectedFloor"]] ==
                                              "0") {
                                            multiplier += 0.1;
                                            debugPrint(
                                                "[Caligo Tower Balcony] Increasing multiplier by 0.1");
                                          } else if (_towerBuildTransitionData[
                                                      "selectedBalcony"] ==
                                                  0 &&
                                              _balconyData[
                                                      _towerBuildTransitionData[
                                                          "selectedFloor"]] !=
                                                  "0") {
                                            multiplier -= 0.1;
                                            debugPrint(
                                                "[Caligo Tower Balcony] Decreasing multiplier by 0.1");
                                          }
                                          debugPrint(
                                              "[Caligo Tower Balcony] Balcony-izing floor ${_towerBuildTransitionData["selectedFloor"]}");
                                          _towerBuildTransitionData[
                                              "showDialog"] = false;
                                          _towerBuildTransitionData["flash"] =
                                              255;
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              10.0), // Adjust corner radius
                                          side: BorderSide(
                                            color: Colors.green
                                                .shade900, // Outline border color
                                            width:
                                                4.0, // Outline border thickness
                                          ),
                                        ),
                                      ),
                                      child: Text("ADD BALCONY",
                                          style:
                                              GoogleFonts.acme(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                  "Removing a balcony will also remove it's multiplier effect.",
                                  style: GoogleFonts.acme(
                                      fontSize: 10,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.white))
                            ],
                          ),
                        if (_towerBuildTransitionData["selectedFloor"] == -1)
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.amber,
                                    borderRadius: BorderRadius.circular(5.0),
                                    border: Border.all(
                                        color: Colors.amber.shade900,
                                        width: 3.0),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey
                                            .withAlpha(128), // 4. Drop shadow
                                        spreadRadius: 2,
                                        blurRadius: 7,
                                        offset: const Offset(
                                            0, 3), // Changes position of shadow
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                      " TIP: Tap a floor to add balcony! ",
                                      style: GoogleFonts.acme(fontSize: 15)),
                                ),
                                SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      debugPrint(
                                          "Cancelling balcony addition for floor ${_towerBuildTransitionData["selectedFloor"]}");
                                      _towerBuildTransitionData["showDialog"] =
                                          false;
                                      _towerBuildTransitionData[
                                          "selectedFloor"] = 0;
                                      _endUpgradeRun();
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: Colors.red,
                                      shadowColor: Colors.transparent),
                                  child: Text("Cancel",
                                      style: GoogleFonts.acme(fontSize: 15)),
                                ),
                              ],
                            ),
                          )
                      ],
                    ),
                  )),
            ),

          Positioned(
            top: 0,
            left: 0,
            width: _screenSize.width,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  color: Colors.brown.shade400,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 2),
                            ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _showTowerSettings = !_showTowerSettings;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.blue,
                                  backgroundColor: Colors.white,
                                  shape:
                                      const CircleBorder(), // Makes the button circular
                                  side: BorderSide(
                                    color: Colors.blue,
                                    width: 6,
                                  ),
                                ),
                                child: Icon(
                                    _showTowerSettings &&
                                            _currentRunningUpgrade == ""
                                        ? Icons.arrow_drop_down
                                        : Icons.arrow_right,
                                    size: 20)),
                            const SizedBox(width: 2),
                            SizedBox(
                              width: _screenSize.width * 0.4,
                              child: Text("$_username's Tower",
                                  style: GoogleFonts.acme(
                                      fontSize: 20, color: Colors.white)),
                            ),
                          ],
                        ),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              Image.asset("assets/pointsicon.png",
                                  width: 30, height: 30),
                              const SizedBox(width: 10),
                              Text("Pts: ${_points.toStringAsFixed(2)}",
                                  style: GoogleFonts.acme(
                                      fontSize: 15, color: Colors.white)),
                              const SizedBox(width: 10),
                            ]),
                      ]),
                ),
                if (_towerUpgradesUISize >= 0.0 && _currentRunningUpgrade == "")
                  Container(
                      color: Colors.brown.shade300,
                      width: _screenSize.width,
                      height: _screenSize.height * _towerUpgradesUISize,
                      child: (_towerUpgradesUISize >= 0.5)
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 10),
                                Center(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.blue.shade700,
                                          Colors.purple.shade300
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(5),
                                      boxShadow: [
                                        // Drop shadows
                                        BoxShadow(
                                          color: Colors.black.withAlpha(128),
                                          spreadRadius: 2,
                                          blurRadius: 5,
                                          offset: Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      " Tower Upgrades ",
                                      style: GoogleFonts.acme(
                                          fontSize: 25, color: Colors.white),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Container(
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              mainAxisSize: MainAxisSize.max,
                                              children: [
                                                Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    children: [
                                                      const SizedBox(width: 5),
                                                      Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                                "Points Multiplier: ${multiplier.toStringAsFixed(2)}x",
                                                                style: GoogleFonts.acme(
                                                                    fontSize:
                                                                        15,
                                                                    color: Colors
                                                                        .white)),
                                                            const SizedBox(
                                                                height: 5),
                                                            TextButton.icon(
                                                                onPressed: () =>
                                                                    _showMultiplierExplanation(
                                                                        context,
                                                                        _points),
                                                                style: TextButton
                                                                    .styleFrom(
                                                                  backgroundColor:
                                                                      Colors
                                                                          .purple
                                                                          .shade300,
                                                                  foregroundColor:
                                                                      Colors
                                                                          .white,
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(5),
                                                                    side:
                                                                        const BorderSide(
                                                                      color: Colors
                                                                          .purple,
                                                                      width:
                                                                          3.0,
                                                                    ),
                                                                  ),
                                                                ),
                                                                label: Text(
                                                                    "What are multipliers?",
                                                                    style: GoogleFonts.acme(
                                                                        fontSize:
                                                                            12,
                                                                        decoration:
                                                                            TextDecoration
                                                                                .underline)),
                                                                icon: const Icon(
                                                                    Icons
                                                                        .info_rounded,
                                                                    size:
                                                                        14.0)),
                                                          ]),
                                                    ]),
                                                Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      const Icon(
                                                          Icons.castle_rounded,
                                                          size: 20.0,
                                                          color: Colors.white),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                          "Floors constructed: $_towerHeight \nKeep going!",
                                                          style:
                                                              GoogleFonts.acme(
                                                                  fontSize: 15,
                                                                  color: Colors
                                                                      .white)),
                                                      const SizedBox(width: 5),
                                                    ]),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            for (var upgradeData
                                                in _towerUpgradesData)
                                              Stack(
                                                children: [
                                                  Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Container(
                                                        width:
                                                            _screenSize.width *
                                                                0.9,
                                                        height: 100,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: Colors.amber,
                                                          border: Border.all(
                                                            color: Colors.amber
                                                                .shade700, // Outline color
                                                            width:
                                                                5.0, // Outline thickness
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      10.0),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: Colors
                                                                  .black
                                                                  .withAlpha(
                                                                      50),
                                                              blurRadius: 10.0,
                                                              spreadRadius: 2.0,
                                                              offset: const Offset(
                                                                  0,
                                                                  4), // Moves shadow down slightly
                                                            ),
                                                          ],
                                                        ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .center,
                                                          mainAxisSize:
                                                              MainAxisSize.max,
                                                          children: [
                                                            Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .start,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                SizedBox(
                                                                    width: 10),
                                                                Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  crossAxisAlignment:
                                                                      CrossAxisAlignment
                                                                          .start,
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Text(
                                                                        upgradeData[
                                                                            0],
                                                                        style: GoogleFonts.acme(
                                                                            fontSize:
                                                                                20)),
                                                                    Text(
                                                                        "Costs ${upgradeData[1]} points",
                                                                        style: GoogleFonts.acme(
                                                                            fontSize:
                                                                                10)),
                                                                    Text(
                                                                        "Multiplier: ${upgradeData[3]}",
                                                                        style: GoogleFonts.acme(
                                                                            fontSize:
                                                                                10)),
                                                                  ],
                                                                ),
                                                              ],
                                                            ),
                                                            Row(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .end,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .max,
                                                              children: [
                                                                Container(
                                                                  width: _screenSize
                                                                          .width *
                                                                      0.2,
                                                                  height: 35,
                                                                  child:
                                                                      ElevatedButton(
                                                                    onPressed:
                                                                        () {
                                                                      if (_points >=
                                                                              upgradeData[
                                                                                  1] &&
                                                                          _towerHeight >=
                                                                              upgradeData[2]) {
                                                                        debugPrint(
                                                                            "Doing upgrade : ${upgradeData[0]}");
                                                                        _upgradeTower(
                                                                            upgradeData[0],
                                                                            upgradeData[1],
                                                                            _screenSize);
                                                                      } else {
                                                                        debugPrint(
                                                                            "Insufficient requirements for upgrade : ${upgradeData[0]}");
                                                                      }
                                                                    },
                                                                    style: ElevatedButton
                                                                        .styleFrom(
                                                                      padding:
                                                                          EdgeInsets
                                                                              .zero,
                                                                      foregroundColor:
                                                                          Colors
                                                                              .white,
                                                                      backgroundColor: _points >= upgradeData[1] && _towerHeight >= upgradeData[2]
                                                                          ? Colors
                                                                              .green
                                                                              .shade600
                                                                          : Colors
                                                                              .red
                                                                              .shade600,
                                                                      shape:
                                                                          RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(5),
                                                                        side:
                                                                            BorderSide(
                                                                          color: _points >= upgradeData[1] && _towerHeight >= upgradeData[2]
                                                                              ? Colors.green.shade800
                                                                              : Colors.red.shade800,
                                                                          width:
                                                                              5,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                    child:
                                                                        FittedBox(
                                                                      fit: BoxFit
                                                                          .scaleDown,
                                                                      child:
                                                                          Text(
                                                                        _towerHeight >=
                                                                                upgradeData[2]
                                                                            ? "BUY"
                                                                            : "LOCKED",
                                                                        maxLines:
                                                                            1,
                                                                        softWrap:
                                                                            false,
                                                                        style: GoogleFonts.acme(
                                                                            fontSize:
                                                                                12),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                    width: 10),
                                                              ],
                                                            ),
                                                          ], // children of the spaceBetween Row
                                                        ), // spaceBetween Row
                                                      ), // Container (height: 100)
                                                      SizedBox(height: 15),
                                                    ], // children of the Column
                                                  ), // Column
                                                  if (_towerHeight <
                                                      upgradeData[2])
                                                    Positioned.fill(
                                                      child: Container(
                                                        color: Colors.black
                                                            .withAlpha(200),
                                                        child: Center(
                                                          child: Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .center,
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                const Icon(
                                                                    Icons.lock,
                                                                    size: 20.0,
                                                                    color: Colors
                                                                        .white),
                                                                Text(
                                                                    "Reach floor ${upgradeData[2]} to unlock!",
                                                                    style: GoogleFonts.acme(
                                                                        fontSize:
                                                                            20,
                                                                        color: Colors
                                                                            .white))
                                                              ]),
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
                                ),
                                SizedBox(height: 10),
                              ],
                            )
                          : SizedBox(
                              height: _screenSize.height * _towerUpgradesUISize,
                            )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StartMenu extends StatefulWidget {
  const StartMenu({super.key});

  @override
  State<StartMenu> createState() => _StartMenuState();
}

enum queType { FILLBLANK, PILGAN, NUMERIC, PILGANKOMPLEKS, PHONENUM }

class _StartMenuState extends State<StartMenu> with WidgetsBindingObserver {
  Timer? _timer;
  int Tower_height = 1;
  double Point = 0.0;
  int _formQueIndex = 0;
  String _decodeBits(String bits, int questionIndex) {
    final labels = questionFormats[questionIndex][1] as List<String>;
    final chosen = <String>[];
    for (int i = 0; i < bits.length && i < labels.length; i++) {
      if (bits[i] == '1') chosen.add(labels[i].replaceAll('\n', ''));
    }
    return chosen.isEmpty ? 'None' : chosen.join(', ');
  }

  Future<void> callNumber() async {
    final prefs = await SharedPreferences.getInstance();
    final number = (prefs.getString("EMERGENCY") ?? "").trim();

    if (number.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No emergency number saved yet.")),
      );
      return;
    }

    var status = await Permission.phone.status;
    if (!status.isGranted) {
      status = await Permission.phone.request();
    }

    if (status.isGranted) {
      await FlutterPhoneDirectCaller.callNumber(number);
    }
  }

  final List<String> questions = [
    "How should we call you?",
    "What is your age?",
    "How many hours do you sleep per day?",
    "What symptoms do you have?",
    "What is your usual daily diet?",
    "What are your allergies?",
    "Who should we call incase emergency?",
  ];
  final List<List<Object>> questionFormats = [
    [queType.FILLBLANK, 9],
    [
      queType.NUMERIC,
      [0, 100],
    ],
    [
      queType.NUMERIC,
      [0, 24],
    ],
    [
      queType.PILGANKOMPLEKS,
      [
        "Memory-loss",
        "Constant brain fogs",
        "Communicating issues",
        "Struggle learning new things",
      ],
    ],
    [
      queType.PILGAN,
      [
        "Standard/Omnivore \n(eats both veggies + meat)",
        "Vegetarian (no meat, \nonly dairy and plants)",
        "Vegan (100% plant based)",
        "Pescatarian (vegan + seafood)",
        "Keto/lowcarb",
        "Gluten-free",
        "Mediterranian",
      ],
    ],
    [
      queType.PILGANKOMPLEKS,
      ["Peanuts", "Dairy", "Gluten", "Soy", "Eggs", "Shellfish", "None"],
    ],
    [queType.PHONENUM],
  ];
  final List<String> _prefUserdataTags = [
    "NAME",
    "AGE",
    "SLEEP",
    "SYMPTOMS",
    "DIET",
    "ALLERGIES",
    "EMERGENCY"
  ];
  //The second element in every sub-list serves a different purpose based off the queType
  //if queType.FILLBLANK then 2nd element is used for char limit
  //if queType.NUMERIC then 2nd element is numeric range
  //if queType.PILGANKOMPLEKS then 2nd element are the choices provided

  bool showForm = false;
  bool accountSetup = false; //will be used for later purposes
  String username = '';
  TextEditingController usernameController = TextEditingController();
  String condition = '';
  TextEditingController conditionController = TextEditingController();
  String symptoms = '';
  TextEditingController symptomsController = TextEditingController();
  String sleep_schedule = '';
  TextEditingController sleep_scheduleController = TextEditingController();
  String diet = '';
  TextEditingController dietController = TextEditingController();
  String emergency = '';
  TextEditingController emergencyController = TextEditingController();
  List<Object> _registrationData = [];
  Map<String, dynamic> _userData = {};
  File? _loadedPFP;

  String _formAlertText = "";
  // int _currentUnixTime = 0;
  int _unixDelayVariable = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  String _tempString = "";
  List<bool> _showProfileUI = [true, true];

  void _Calendar() {
    DateTime selectedDay = DateTime.now();
    DateTime focusedDay = DateTime.now();

    Map<String, List<String>> importantDates = {};

    String dateKey(DateTime date) {
      return "${date.year}-${date.month}-${date.day}";
    }

    Future<void> loadDates() async {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString("IMPORTANT_DATES");

      if (saved != null) {
        final Map<String, dynamic> decoded = jsonDecode(saved);

        importantDates = decoded.map(
          (key, value) => MapEntry(
            key,
            List<String>.from(value),
          ),
        );
      }
    }

    Future<void> saveDates() async {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        "IMPORTANT_DATES",
        jsonEncode(importantDates),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            final key = dateKey(selectedDay);
            final events = importantDates[key] ?? [];
            TextEditingController eventController = TextEditingController();

            Future<void> addEvent() async {
              await showDialog(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: Text(
                      "Add Important Date",
                      style: GoogleFonts.acme(fontSize: 25),
                    ),
                    content: TextField(
                      controller: eventController,
                      decoration: const InputDecoration(
                        hintText: "Event name",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        child: const Text("CANCEL"),
                      ),
                      TextButton(
                        onPressed: () async {
                          if (eventController.text.trim().isNotEmpty) {
                            importantDates.putIfAbsent(
                              key,
                              () => [],
                            );

                            importantDates[key]!.add(
                              eventController.text.trim(),
                            );

                            await saveDates();

                            dialogSetState(() {});

                            Navigator.pop(context);
                          }
                        },
                        child: const Text("ADD"),
                      ),
                    ],
                  );
                },
              );

              //eventController.dispose();
            }

            return FutureBuilder(
              future: loadDates(),
              builder: (context, snapshot) {
                final screenHeight = MediaQuery.of(context).size.height;
                final screenWidth = MediaQuery.of(context).size.width;

                return AlertDialog(
                  title: Text(
                    "Important Dates",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.acme(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // IMPORTANT: Give the dialog a limited height
                  content: SizedBox(
                    width: screenWidth * 0.85,
                    height: screenHeight * 0.65,
                    child: Column(
                      children: [
                        // Calendar
                        TableCalendar(
                          firstDay: DateTime(2020),
                          lastDay: DateTime(2100),
                          focusedDay: focusedDay,

                          selectedDayPredicate: (day) {
                            return isSameDay(selectedDay, day);
                          },

                          onDaySelected: (selected, focused) {
                            dialogSetState(() {
                              selectedDay = selected;
                              focusedDay = focused;
                            });
                          },

                          // Prevent the month name from becoming vertical
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            leftChevronIcon: const Icon(
                              Icons.chevron_left,
                              size: 20,
                            ),
                            rightChevronIcon: const Icon(
                              Icons.chevron_right,
                              size: 20,
                            ),
                            titleTextStyle: GoogleFonts.acme(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          // Make the calendar slightly more compact
                          daysOfWeekHeight: 25,
                          rowHeight: 35,

                          calendarStyle: const CalendarStyle(
                            cellMargin: EdgeInsets.all(2),
                            markerSize: 7,
                          ),

                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (context, day, events) {
                              if (importantDates.containsKey(dateKey(day))) {
                                return Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                );
                              }

                              return null;
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          "Events on ${selectedDay.day}/${selectedDay.month}/${selectedDay.year}",
                          style: GoogleFonts.acme(fontSize: 14),
                        ),

                        const SizedBox(height: 5),

                        // Event list gets its own limited space
                        Expanded(
                          child: events.isEmpty
                              ? Center(
                                  child: Text(
                                    "No important dates",
                                    style: GoogleFonts.acme(fontSize: 14),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: events.length,
                                  itemBuilder: (context, index) {
                                    return ListTile(
                                      dense: true,
                                      leading: const Icon(
                                        Icons.event,
                                        color: Colors.red,
                                      ),
                                      title: Text(
                                        events[index],
                                        style: GoogleFonts.acme(
                                          fontSize: 14,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: () async {
                                          dialogSetState(() {
                                            events.removeAt(index);
                                          });

                                          if (events.isEmpty) {
                                            importantDates.remove(key);
                                          }

                                          await saveDates();
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),

                        const SizedBox(height: 5),

                        ElevatedButton.icon(
                          onPressed: addEvent,
                          icon: const Icon(Icons.add),
                          label: Text(
                            "ADD IMPORTANT DATE",
                            style: GoogleFonts.acme(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                  actions: [
                    TextButton(
                      onPressed: () {
                        eventController.dispose();
                        Navigator.pop(dialogContext);
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        "CLOSE",
                        style: GoogleFonts.acme(fontSize: 18),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    _continuousTicks();
    _startBackgroundMusic("default_bgm.mp3");

    for (var i = 0; i < questionFormats.length; i++) {
      //init temporal regis data
      final _qformatData = questionFormats[i][0] as queType;
      if (_qformatData == queType.FILLBLANK ||
          _qformatData == queType.PHONENUM) {
        _registrationData.add(TextEditingController());
      } else if (_qformatData == queType.PILGANKOMPLEKS) {
        _registrationData.add(
          List.generate(
            (questionFormats[i][1] as List<String>).length,
            (index) => false,
          ),
        );
      } else if (_qformatData == queType.PILGAN) {
        _registrationData.add(-1);
      } else if (_qformatData == queType.NUMERIC) {
        _registrationData.add((questionFormats[i][1] as List<int>)[0]);
      }
    }
    () async {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey("LOGGEDIN?")) {
        await prefs.setBool("LOGGEDIN?", false);
      } else if (prefs.getBool("LOGGEDIN?") == true) {
        await _loadUserProfile();
        if (mounted) setState(() => accountSetup = true);
      }
    }();
  }

  void _continuousTicks() {
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      setState(() {
        _unixDelayVariable = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (showForm) {
          if (showForm && _formQueIndex < questions.length) {
            if (_tempString != questions[_formQueIndex]) {
              _tempString += questions[_formQueIndex][_tempString.length];
            }
          }
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
    // backgroundMusic.stop();
    // backgroundMusic.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _timer?.cancel();
    _stopBackgroundMusic();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Stop music when app is minimized or backgrounded
      _stopBackgroundMusic();
    } else if (state == AppLifecycleState.resumed) {
      // Optional: Resume music when app returns to foreground
      // player.play();
      _startBackgroundMusic("default_bgm.mp3");
    }
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();

    //initialize user pfp
    final imagePath = prefs.getString("ProfilePicture");
    if (imagePath != null && await File(imagePath).exists()) {
      _loadedPFP = File(imagePath);
    } else if (imagePath != null) {
      prefs.remove("ProfilePicture");
    } else {
      _loadedPFP = null;
    }
    setState(() {
      _userData["NAME"] = prefs.getString("NAME") ?? "";
      _userData["AGE"] = prefs.getInt("AGE") ?? 0;
      _userData["SLEEP"] = prefs.getInt("SLEEP") ?? 0;
      _userData["SYMPTOMS"] = prefs.getString("SYMPTOMS") ?? "";
      _userData["DIET"] = prefs.getInt("DIET") ?? 0;
      _userData["ALLERGIES"] = prefs.getString("ALLERGIES") ?? "";
      _userData["EMERGENCY"] = prefs.getString("EMERGENCY") ?? "";
      _userData["POINTS"] = prefs.getDouble("POINTS") ?? 0.0;
      _userData["TOWER_HEIGHT"] = prefs.getInt("TOWER_HEIGHT") ?? 0;
      _userData["SCHEDULE"] = prefs.getStringList("SCHEDULE") ?? <String>[];
      _userData["TOWER_BALCONIES"] = prefs.getString("TOWER_BALCONIES") ?? "";
    });
  }

  Future<void> _saveUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var data in _userData.entries) {
        if (data.runtimeType.toString() == "String")
          prefs.setString(data.key, data.value);
        else if (data.runtimeType.toString() == "int")
          prefs.setInt(data.key, data.value);
        else if (data.runtimeType.toString() == "bool")
          prefs.setBool(data.key, data.value);
        else if (data.runtimeType.toString() == "List<String>")
          prefs.setStringList(data.key, data.value);

        debugPrint(
            "[_saveUserProfile() function] Saved key ${data.key} with value ${data.value}, datatype = ${data.runtimeType.toString()}");
      }
    });
  }

  Future<void> _updatePFP(bool add) async {
    final prefs = await SharedPreferences.getInstance();
    // if add is true = change/add pfp, else = remove user pfp
    if (add) {
      final XFile? pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );

      if (pickedFile == null) return;

      final directory = await getApplicationDocumentsDirectory();

      final extension = pickedFile.name.contains('.')
          ? pickedFile.name.split('.').last
          : 'jpg';

      final savedFile = await File(pickedFile.path).copy(
        '${directory.path}/uploaded_image.$extension',
      );

      await prefs.setString("ProfilePicture", savedFile.path);
      debugPrint("[_updatePFP] saved pfp with directory ${savedFile.path}");
      //if (!mounted) return;

      setState(() {
        _loadedPFP = savedFile;
      });
    } else {
      await prefs.remove("ProfilePicture");

      if (_loadedPFP != null && await _loadedPFP!.exists()) {
        await _loadedPFP!.delete();
      }

      debugPrint("[_updatePFP] successfully deleted pfp");

      //if (!mounted) return;

      setState(() => _loadedPFP = null);
    }
  }

  late final List<List<dynamic>> _pageDirectionData = [
    //["Account Info", _AccountInfo, Icons.info],
    ["Calendar", _Calendar, Icons.calendar_month],
    ["MyTower", (context) => const Towerpage(), Icons.castle],
    ["Minigame", (context) => const Minigame(), Icons.videogame_asset_sharp],
    ["AI Chat page", (context) => const AIChatPage(), Icons.chat],
    ["Music Library", (context) => const MusicLibrary(), Icons.music_note],
    ["Schedule", (context) => const SchedulePage(), Icons.schedule],
    ["Map", (context) => const LocationPage(), Icons.map],
    ["Vinoscape", (context) => const VinoPage(), Icons.location_city_rounded],
  ];
  Future<void> _finishRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    for (var i = 0; i < questionFormats.length; i++) {
      final t = questionFormats[i][0] as queType;
      if (t == queType.FILLBLANK || t == queType.PHONENUM) {
        await prefs.setString(_prefUserdataTags[i],
            (_registrationData[i] as TextEditingController).text);
      } else if (t == queType.NUMERIC || t == queType.PILGAN) {
        await prefs.setInt(_prefUserdataTags[i], _registrationData[i] as int);
      } else if (t == queType.PILGANKOMPLEKS) {
        final bits = (_registrationData[i] as List<bool>)
            .map((v) => v ? "1" : "0")
            .join();
        await prefs.setString(_prefUserdataTags[i], bits);
      }
    }
    await prefs.setBool("LOGGEDIN?", true);
    await prefs.setDouble("MULTIPLIER", 1.0);
    multiplier = 1.0;
    await prefs.setDouble("POINTS", 0);
    await prefs.setInt("TOWER_HEIGHT", 0);
    await prefs.setStringList("SCHEDULE", []);
    await prefs.setString("TOWER_TIERDATA", "");
    await prefs.setString("TOWER_BALCONIES", "");
    await _loadUserProfile();
    if (!mounted) return;
    setState(() {
      _tempString = "";
      showForm = false;
      _formQueIndex = 0;
      _formAlertText = "";
      accountSetup = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size _screenSize = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.blueAccent.shade100,
      appBar: AppBar(
        title: Row(
          children: [
            Text("${_appName}/home", style: GoogleFonts.acme(fontSize: 20)),
            SizedBox(width: 20),
            Icon(Icons.home, size: 20),
          ],
        ),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      drawer: Drawer(
        child: SafeArea(
          //make sure UI isnt covered by built-in internal OS interface
          child: SingleChildScrollView(
            //scrollable
            child: accountSetup
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 20),
                      Center(
                        child: Text(
                          "${_appName} Navigator",
                          style: GoogleFonts.acme(fontSize: 20),
                        ),
                      ),
                      GridView.count(
                        shrinkWrap: true,
                        crossAxisCount: 2, // Displays 2 squares per row
                        crossAxisSpacing: 2, // Horizontal space between squares
                        mainAxisSpacing: 2, // Vertical space between squares
                        padding:
                            const EdgeInsets.all(5), // Padding around the grid
                        children: [
                          for (List<dynamic> pagedata in _pageDirectionData)
                            ElevatedButton(
                                onPressed: () async {
                                  if (pagedata[1] is Widget Function(
                                      BuildContext)) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: pagedata[1] as Widget
                                              Function(BuildContext)),
                                    );
                                    _loadUserProfile();
                                  } else if (pagedata[1] is Function) {
                                    pagedata[1]();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 1.0,
                                  child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF5563A2),
                                        borderRadius: BorderRadius.circular(
                                            5), // Slightly rounded corners
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(pagedata[2], size: 50.0),
                                            Text(pagedata[0],
                                                style: GoogleFonts.acme(
                                                    fontSize: 15)),
                                          ],
                                        ),
                                      )),
                                ))
                        ],
                      ),
                      ElevatedButton(
                        onPressed: callNumber,
                        child: Text('Contact Family 📞'),
                      ),
                      SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () async {
                          showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                    title: Text(
                                      "Confirmation",
                                      style: GoogleFonts.acme(fontSize: 25),
                                    ),
                                    content: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Center(
                                            child: Text(
                                                "Are you sure you want to delete your ${_appName} account??",
                                                style: TextStyle(fontSize: 20)),
                                          ),
                                          const SizedBox(height: 10),
                                          ElevatedButton.icon(
                                            onPressed: () async {
                                              final prefs =
                                                  await SharedPreferences
                                                      .getInstance();
                                              await prefs.clear();
                                              if (mounted)
                                                setState(
                                                    () => accountSetup = false);
                                              showDialog(
                                                  barrierDismissible: false,
                                                  context: context,
                                                  builder: (context) {
                                                    return AlertDialog(
                                                        title: Text(
                                                          "Success!",
                                                          style:
                                                              GoogleFonts.acme(
                                                                  fontSize: 25),
                                                        ),
                                                        content: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Text(
                                                                  "Account deleted succesfully!"),
                                                              const SizedBox(
                                                                  height: 10),
                                                              Icon(
                                                                  Icons
                                                                      .check_circle,
                                                                  size: 30,
                                                                  color: Colors
                                                                      .green),
                                                              Text(
                                                                  "Please exit then restart ${_appName} to finish account deletion."),
                                                              const SizedBox(
                                                                  height: 10),
                                                              ElevatedButton(
                                                                  onPressed:
                                                                      () {
                                                                    if (Platform
                                                                        .isIOS) {
                                                                      exit(0);
                                                                    } else {
                                                                      // For Android and other platforms
                                                                      SystemChannels
                                                                          .platform
                                                                          .invokeMethod(
                                                                              'SystemNavigator.pop');
                                                                    }
                                                                  },
                                                                  style: ElevatedButton
                                                                      .styleFrom(
                                                                    backgroundColor:
                                                                        Colors
                                                                            .red,
                                                                    foregroundColor:
                                                                        Colors
                                                                            .white,
                                                                    shape:
                                                                        RoundedRectangleBorder(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                              5.0),
                                                                    ),
                                                                  ),
                                                                  child: Text(
                                                                      "EXIT APP")),
                                                            ]));
                                                  });

                                              print("All saved data deleted");
                                            },
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white),
                                            icon: Icon(Icons.delete),
                                            label:
                                                const Text("Delete All data"),
                                          ),
                                          SizedBox(height: 10),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.pop(context);
                                            },
                                            style: TextButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              foregroundColor: Colors.red,
                                            ),
                                            child: Text(
                                              "Nevermind, keep my account!",
                                              style: GoogleFonts.acme(
                                                  fontSize: 18),
                                            ),
                                          ),
                                        ]));
                              });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text("Delete account"),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(height: 20),
                      Text(
                        "${_appName} Navigator",
                        style: GoogleFonts.acme(fontSize: 20),
                      ),
                      SizedBox(height: 20),
                      Icon(Icons.lock, size: 40),
                      Text(
                        "Please register an account first to use the navigator.",
                        style: GoogleFonts.acme(fontSize: 15),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      body: Container(
        width: _screenSize.width,
        height: _screenSize.height,
        decoration: const BoxDecoration(
            image: DecorationImage(
                image: AssetImage("assets/homepage_bg.png"),
                fit: BoxFit.cover)),
        child: Center(
          child: SafeArea(
            child: SingleChildScrollView(
              child: SizedBox(
                width: _screenSize.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Image.asset(
                        "assets/logo.png",
                        fit: BoxFit.fitWidth,
                      ),
                    ),
                    const SizedBox(height: 50),
                    if (!accountSetup)
                      Container(
                        width: _screenSize.width * 0.85,
                        height: _screenSize.height * 0.5,
                        color: Colors.amber.shade100,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              color: Colors.amber,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  Text(
                                    "  requirement.txt",
                                    style: GoogleFonts.acme(fontSize: 15),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.minimize, size: 20),
                                      Icon(Icons.crop_square, size: 20),
                                      Icon(Icons.close, size: 20),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              "WAIT!!!",
                              style: GoogleFonts.acme(
                                fontSize: 30,
                                color: Colors.red,
                              ),
                            ),
                            Text(
                              "Before you use the app, please fulfill your biodata so we can personalize our features\n",
                              style: GoogleFonts.acme(fontSize: 15),
                            ),
                            Text(
                              "Make sure the registration form is filled by your non-alzheimer's friend.",
                              style: GoogleFonts.acme(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 30),
                            if (!showForm)
                              ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    debugPrint("Registering account...");
                                    showForm = true;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  side: BorderSide(
                                    color: Colors.green.shade900,
                                    width: 5,
                                  ),
                                ),
                                child: Text(
                                  "FILL DATA",
                                  style: GoogleFonts.bebasNeue(fontSize: 40),
                                ),
                              ),
                            if (showForm)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Text(
                                    "SCROLL DOWN PLEASE",
                                    style: GoogleFonts.bebasNeue(fontSize: 40),
                                  ),
                                  Icon(Icons.arrow_circle_down_rounded,
                                      size: 64),
                                ],
                              ),
                          ],
                        ),
                      ),
                    if (showForm)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: 150),
                          Text(
                            "REGISTER HERE",
                            style: GoogleFonts.acme(
                              fontSize: 50,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Container(
                            width: _screenSize.width,
                            color: Colors.purple.shade600,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "  register.txt",
                                  style: GoogleFonts.acme(
                                    fontSize: 20,
                                    color: Colors.white,
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (int i = 0; i < 3; i++)
                                      Icon(
                                        Icons.circle,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: _screenSize.width,
                            color: Colors.amber.shade50,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_formQueIndex < questions.length)
                                  Text(
                                    _tempString,
                                    style: GoogleFonts.acme(fontSize: 20),
                                  ),
                                if (_formQueIndex < questions.length)
                                  if (questionFormats[_formQueIndex][0]
                                          as queType ==
                                      queType.FILLBLANK)
                                    SizedBox(
                                      width: _screenSize.width * 0.8,
                                      height: 50,
                                      child: TextField(
                                        controller:
                                            _registrationData[_formQueIndex]
                                                as TextEditingController,
                                        decoration: InputDecoration(
                                          labelText: "",
                                          hintText: "Enter your answer here...",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                if (_formQueIndex < questions.length)
                                  if (questionFormats[_formQueIndex][0]
                                              as queType ==
                                          queType.PILGANKOMPLEKS ||
                                      questionFormats[_formQueIndex][0]
                                              as queType ==
                                          queType.PILGAN)
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (var i = 0;
                                            i <
                                                (questionFormats[_formQueIndex]
                                                        [1] as List<String>)
                                                    .length;
                                            i++)
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ElevatedButton(
                                                onPressed: () {
                                                  setState(() {
                                                    if (questionFormats[
                                                                _formQueIndex]
                                                            [0] as queType ==
                                                        queType
                                                            .PILGANKOMPLEKS) {
                                                      if ((questionFormats[
                                                                  _formQueIndex][1]
                                                              as List<
                                                                  String>)[i] ==
                                                          "None") {
                                                        for (var j = 0;
                                                            j <
                                                                (_registrationData[
                                                                            _formQueIndex]
                                                                        as List<
                                                                            bool>)
                                                                    .length;
                                                            j++) {
                                                          (_registrationData[
                                                                  _formQueIndex]
                                                              as List<
                                                                  bool>)[j] = (j ==
                                                              (_registrationData[
                                                                              _formQueIndex]
                                                                          as List<
                                                                              bool>)
                                                                      .length -
                                                                  1);
                                                        }
                                                      } else {
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as List<
                                                                    bool>)[i] =
                                                            !(_registrationData[
                                                                    _formQueIndex]
                                                                as List<
                                                                    bool>)[i];
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as List<bool>)[
                                                            (_registrationData[
                                                                            _formQueIndex]
                                                                        as List<
                                                                            bool>)
                                                                    .length -
                                                                1] = false;
                                                      }
                                                    } else {
                                                      _registrationData[
                                                          _formQueIndex] = i;
                                                    }
                                                  });
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  shadowColor:
                                                      Colors.transparent,
                                                  elevation: 0,
                                                  foregroundColor: (questionFormats[
                                                                  _formQueIndex]
                                                              [0] as queType ==
                                                          queType
                                                              .PILGANKOMPLEKS)
                                                      ? ((_registrationData[
                                                                  _formQueIndex]
                                                              as List<bool>)[i]
                                                          ? Colors.green
                                                          : Colors.red)
                                                      : Colors.lightBlue,
                                                ),
                                                child: Icon(
                                                  (questionFormats[
                                                                  _formQueIndex]
                                                              [0] ==
                                                          queType
                                                              .PILGANKOMPLEKS)
                                                      ? ((_registrationData[
                                                                  _formQueIndex]
                                                              as List<bool>)[i]
                                                          ? Icons.check_box
                                                          : Icons
                                                              .check_box_outline_blank)
                                                      : ((_registrationData[
                                                                  _formQueIndex] ==
                                                              i)
                                                          ? Icons
                                                              .radio_button_checked
                                                          : Icons
                                                              .radio_button_unchecked),
                                                  size: 20,
                                                ),
                                              ),
                                              Text(
                                                (questionFormats[_formQueIndex]
                                                    [1] as List<String>)[i],
                                                style: GoogleFonts.acme(
                                                    fontSize: 20),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                if (_formQueIndex < questions.length)
                                  if (questionFormats[_formQueIndex][0]
                                          as queType ==
                                      queType.NUMERIC)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(height: 50),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.max,
                                          children: [
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  if ((_registrationData[
                                                                  _formQueIndex]
                                                              as int) -
                                                          5 >=
                                                      (questionFormats[
                                                              _formQueIndex][1]
                                                          as List<int>)[0]) {
                                                    _registrationData[
                                                            _formQueIndex] =
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as int) -
                                                            5;
                                                  }
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.red.shade900,
                                                  width: 5,
                                                ),
                                              ),
                                              child: Text("-5",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 20)),
                                            ),
                                            SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  if ((_registrationData[
                                                                  _formQueIndex]
                                                              as int) -
                                                          1 >=
                                                      (questionFormats[
                                                              _formQueIndex][1]
                                                          as List<int>)[0]) {
                                                    _registrationData[
                                                            _formQueIndex] =
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as int) -
                                                            1;
                                                  }
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.red.shade900,
                                                  width: 5,
                                                ),
                                              ),
                                              child: Text("-1",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 20)),
                                            ),
                                            SizedBox(width: 10),
                                            Text(
                                                "${_registrationData[_formQueIndex] as int}",
                                                style: GoogleFonts.acme(
                                                    fontSize: 40)),
                                            SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  if ((_registrationData[
                                                                  _formQueIndex]
                                                              as int) +
                                                          1 <=
                                                      (questionFormats[
                                                              _formQueIndex][1]
                                                          as List<int>)[1]) {
                                                    _registrationData[
                                                            _formQueIndex] =
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as int) +
                                                            1;
                                                  }
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.green.shade900,
                                                  width: 5,
                                                ),
                                              ),
                                              child: Text("+1",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 20)),
                                            ),
                                            SizedBox(width: 10),
                                            ElevatedButton(
                                              onPressed: () {
                                                setState(() {
                                                  if ((_registrationData[
                                                                  _formQueIndex]
                                                              as int) +
                                                          5 <=
                                                      (questionFormats[
                                                              _formQueIndex][1]
                                                          as List<int>)[1]) {
                                                    _registrationData[
                                                            _formQueIndex] =
                                                        (_registrationData[
                                                                    _formQueIndex]
                                                                as int) +
                                                            5;
                                                  }
                                                });
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                ),
                                                side: BorderSide(
                                                  color: Colors.green.shade900,
                                                  width: 5,
                                                ),
                                              ),
                                              child: Text("+5",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 20)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                if (_formQueIndex < questions.length)
                                  if (questionFormats[_formQueIndex][0]
                                          as queType ==
                                      queType.PHONENUM)
                                    SizedBox(
                                      width: _screenSize.width * 0.8,
                                      height: 50,
                                      child: TextField(
                                        controller:
                                            _registrationData[_formQueIndex]
                                                as TextEditingController,
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\+?[0-9]*$'),
                                          ),
                                        ],
                                        decoration: InputDecoration(
                                          labelText: "Phone Number",
                                          hintText: "e.g. +62 123-4567-890",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                if (_formQueIndex >= questions.length)
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.max,
                                      children: [
                                        Text("Registration complete!",
                                            style:
                                                GoogleFonts.acme(fontSize: 30)),
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 60,
                                          color: Colors.green,
                                        ),
                                        Text(
                                            "Click [DONE] to finish & register",
                                            style:
                                                GoogleFonts.acme(fontSize: 20)),
                                      ],
                                    ),
                                  ),
                                SizedBox(height: 50),
                                Row(
                                    mainAxisAlignment: (_formQueIndex > 0 &&
                                            _formQueIndex <
                                                questions.length - 1)
                                        ? MainAxisAlignment.spaceBetween
                                        : MainAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.max,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (_formQueIndex > 0 &&
                                          _formQueIndex < questions.length - 1)
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(width: 10),
                                              ElevatedButton.icon(
                                                  onPressed: () => setState(() {
                                                        _tempString = "";
                                                        _formQueIndex--;
                                                      }),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.lightBlue,
                                                    foregroundColor:
                                                        Colors.white,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              5),
                                                    ),
                                                    side: BorderSide(
                                                      color: Colors
                                                          .lightBlue.shade900,
                                                      width: 5,
                                                    ),
                                                  ),
                                                  label: Text("PREV",
                                                      style: TextStyle(
                                                          fontSize: 15.0)),
                                                  icon: Icon(Icons.chevron_left,
                                                      size: 13.0)),
                                            ]),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          Text("${_formAlertText}  ",
                                              style: GoogleFonts.acme(
                                                  fontSize: 20,
                                                  color: Colors.red)),
                                          ElevatedButton(
                                            onPressed: () {
                                              if (_formQueIndex >=
                                                  questions.length) {
                                                _finishRegistration();
                                                return;
                                              }

                                              //final prefs = await SharedPreferences.getInstance();
                                              setState((_formQueIndex <
                                                      questions.length)
                                                  ? () {
                                                      if (questionFormats[
                                                                      _formQueIndex][0]
                                                                  as queType ==
                                                              queType
                                                                  .FILLBLANK ||
                                                          questionFormats[
                                                                      _formQueIndex][0]
                                                                  as queType ==
                                                              queType
                                                                  .PHONENUM) {
                                                        if ((_registrationData[
                                                                        _formQueIndex]
                                                                    as TextEditingController)
                                                                .text
                                                                .isNotEmpty &&
                                                            (_registrationData[
                                                                            _formQueIndex]
                                                                        as TextEditingController)
                                                                    .text
                                                                    .length <=
                                                                (questionFormats[_formQueIndex]
                                                                            [
                                                                            0] ==
                                                                        queType
                                                                            .FILLBLANK
                                                                    ? (questionFormats[
                                                                            _formQueIndex]
                                                                        [
                                                                        1] as int)
                                                                    : 15)) {
                                                          _formAlertText = "";
                                                          _formQueIndex++;
                                                        } else {
                                                          _formAlertText = questionFormats[
                                                                          _formQueIndex][0]
                                                                      as queType ==
                                                                  queType
                                                                      .FILLBLANK
                                                              ? "Character range should be 1 to ${(questionFormats[_formQueIndex][1] as int)}"
                                                              : "Invalid phone number.";
                                                        }
                                                      } else if (questionFormats[
                                                                  _formQueIndex]
                                                              [0] as queType ==
                                                          queType
                                                              .PILGANKOMPLEKS) {
                                                        if ((_registrationData[
                                                                    _formQueIndex]
                                                                as List<bool>)
                                                            .contains(true)) {
                                                          _formAlertText = "";
                                                          _formQueIndex++;
                                                        } else {
                                                          _formAlertText =
                                                              "Tick atleast one box please";
                                                        }
                                                      } else if (questionFormats[
                                                                  _formQueIndex]
                                                              [0] as queType ==
                                                          queType.PILGAN) {
                                                        if ((_registrationData[
                                                                    _formQueIndex]
                                                                as int) >=
                                                            0) {
                                                          _formAlertText = "";
                                                          _formQueIndex++;
                                                        } else {
                                                          _formAlertText =
                                                              "Choose one option please";
                                                        }
                                                      } else if (questionFormats[
                                                                  _formQueIndex]
                                                              [0] as queType ==
                                                          queType.NUMERIC) {
                                                        _formAlertText = "";
                                                        _formQueIndex++;
                                                      }
                                                      _tempString = "";
                                                    }
                                                  : () async {
                                                      final prefs =
                                                          await SharedPreferences
                                                              .getInstance();
                                                      setState(() {
                                                        _tempString = "";
                                                        showForm = false;
                                                        _formQueIndex = 0;
                                                        _formAlertText = "";
                                                        prefs.setBool(
                                                            "LOGGEDIN?", true);
                                                        accountSetup = true;
                                                      });
                                                      for (var i = 0;
                                                          i <
                                                              questionFormats
                                                                  .length;
                                                          i++) {
                                                        if (questionFormats[i]
                                                                        [0]
                                                                    as queType ==
                                                                queType
                                                                    .FILLBLANK ||
                                                            questionFormats[i]
                                                                        [0]
                                                                    as queType ==
                                                                queType
                                                                    .PHONENUM) {
                                                          prefs.setString(
                                                              _prefUserdataTags[
                                                                  i],
                                                              (_registrationData[
                                                                          i]
                                                                      as TextEditingController)
                                                                  .text);
                                                          debugPrint(
                                                              "[REGISTRATION] Saving ${(_registrationData[i] as TextEditingController).text} with tag : ${_prefUserdataTags[i]}");
                                                        } else if (questionFormats[
                                                                        i][0]
                                                                    as queType ==
                                                                queType
                                                                    .NUMERIC ||
                                                            questionFormats[i]
                                                                        [0]
                                                                    as queType ==
                                                                queType
                                                                    .PILGAN) {
                                                          prefs.setInt(
                                                              _prefUserdataTags[
                                                                  i],
                                                              _registrationData[
                                                                  i] as int);
                                                          debugPrint(
                                                              "[REGISTRATION] Saving ${_registrationData[i] as int} with tag : ${_prefUserdataTags[i]}");
                                                        } else if (questionFormats[
                                                                    i][0]
                                                                as queType ==
                                                            queType
                                                                .PILGANKOMPLEKS) {
                                                          String temp = "";
                                                          for (bool value
                                                              in _registrationData[
                                                                      i]
                                                                  as List<
                                                                      bool>) {
                                                            temp += value
                                                                ? "1"
                                                                : "0";
                                                          }
                                                          prefs.setString(
                                                              _prefUserdataTags[
                                                                  i],
                                                              temp);
                                                          debugPrint(
                                                              "[REGISTRATION] Saving ${temp} with tag : ${_prefUserdataTags[i]}");
                                                        }
                                                      }
                                                      prefs.setDouble(
                                                          "MULTIPLIER", 1.0);
                                                      multiplier = 1.0;
                                                      prefs.setDouble(
                                                          "POINTS", 0);
                                                      prefs.setInt(
                                                          "TOWER_HEIGHT", 0);
                                                      prefs.setStringList(
                                                          "SCHEDULE", []);
                                                      prefs.setString(
                                                          "TOWER_TIERDATA", "");
                                                      prefs.setString(
                                                          "TOWER_BALCONIES",
                                                          "");
                                                      await _loadUserProfile();
                                                    });
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              side: BorderSide(
                                                color: Colors.green.shade900,
                                                width: 5,
                                              ),
                                            ),
                                            child: Text(
                                              _formQueIndex < questions.length
                                                  ? "Next"
                                                  : "Done",
                                              style: GoogleFonts.bebasNeue(
                                                  fontSize: 20),
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                        ],
                                      ),
                                    ]),
                                SizedBox(height: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    if (accountSetup)
                      Container(
                        width: _screenSize.width * 0.95,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    debugPrint("Editting profile pic...");
                                    showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return AlertDialog(
                                          title: const Text(
                                              'Modify profile picture'),
                                          content: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _updatePFP(true),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.yellow,
                                                    foregroundColor:
                                                        Colors.black,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      side: BorderSide(
                                                          color: Colors
                                                              .yellow.shade800,
                                                          width: 2.0),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.cloud_upload,
                                                      size: 20,
                                                      color: Colors.black),
                                                  label: Text(
                                                      "Upload / Change Profile Picture")),
                                              const SizedBox(height: 10),
                                              ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _updatePFP(false),
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                    foregroundColor:
                                                        Colors.black,
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              6),
                                                      side: BorderSide(
                                                          color: Colors
                                                              .red.shade800,
                                                          width: 2.0),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                      Icons.cloud_upload,
                                                      size: 20,
                                                      color: Colors.black),
                                                  label: Text(
                                                      "Delete Profile Picture")),
                                            ],
                                          ),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                foregroundColor:
                                                    Colors.blueAccent,
                                                elevation: 0.0,
                                                shadowColor: Colors.transparent,
                                              ),
                                              child: Text("Cancel"),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    shadowColor: Colors.transparent,
                                    backgroundColor: Colors.transparent,
                                    elevation: 0,
                                  ),
                                  child: Container(
                                    width: _screenSize.width * 0.25,
                                    height: _screenSize.width * 0.25,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          5.0), // Adjust the roundness here
                                      image: DecorationImage(
                                        image: (_loadedPFP == null)
                                            ? const AssetImage(
                                                'assets/EmptyProfilePic.png')
                                            : FileImage(_loadedPFP!)
                                                as ImageProvider,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: _screenSize.width * 0.5,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text("Welcome, ${_userData["NAME"]}!",
                                          style:
                                              GoogleFonts.nunito(fontSize: 20)),
                                      Text("How can we get started today?",
                                          style:
                                              GoogleFonts.nunito(fontSize: 10))
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),
                            Container(
                              width: _screenSize.width * 0.9,
                              decoration: BoxDecoration(
                                color: Colors.amber
                                    .shade200, // 1. Background color goes here!
                                borderRadius: BorderRadius.circular(
                                    10), // 2. Rounded corners
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha(128), // 4. Drop shadow
                                    spreadRadius: 2,
                                    blurRadius: 7,
                                    offset: const Offset(
                                        0, 3), // Changes position of shadow
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: _screenSize.width * 0.9,
                                      //height:50,

                                      decoration: BoxDecoration(
                                        color: Colors.amber
                                            .shade700, // 1. Background color goes here!
                                        borderRadius: BorderRadius.circular(
                                            10), // 2. Rounded corners
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(height: 5),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              ElevatedButton(
                                                onPressed: () => setState(() =>
                                                    _showProfileUI[0] =
                                                        !_showProfileUI[0]),
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.blue,
                                                  backgroundColor: Colors.white,
                                                  shape:
                                                      const CircleBorder(), // Makes the button circular
                                                  side: BorderSide(
                                                    color: Colors.blue,
                                                    width: 3,
                                                  ),
                                                ),
                                                child: Icon(
                                                    _showProfileUI[0]
                                                        ? Icons.arrow_drop_down
                                                        : Icons.arrow_right,
                                                    size: 20),
                                              ),
                                              SizedBox(width: 5),
                                              Text("User data",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15)),
                                            ],
                                          ),
                                          SizedBox(height: 5),
                                        ],
                                      )),
                                  if (_showProfileUI[0])
                                    Column(children: [
                                      SizedBox(height: 10),
                                      Center(
                                        child: Text(
                                            "${_userData["NAME"]}'s Biodata",
                                            style:
                                                GoogleFonts.acme(fontSize: 25)),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.max,
                                        children: [
                                          SizedBox(width: 15),
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                  "Age : ${_userData["AGE"]} year${_userData["AGE"] > 1 ? "s" : ""} old",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15)),
                                              Text(
                                                  "Sleep schedule : ${_userData["SLEEP"]} hour${_userData["SLEEP"] > 1 ? "s" : ""} per day",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15)),
                                              Text("Symptoms :",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15)),
                                              for (var i = 0;
                                                  i <
                                                      _userData["SYMPTOMS"]
                                                          .length;
                                                  i++)
                                                if (_userData["SYMPTOMS"][i] ==
                                                    "1")
                                                  Row(
                                                    children: [
                                                      SizedBox(width: 5),
                                                      Icon(Icons.circle,
                                                          size: 5),
                                                      SizedBox(width: 5),
                                                      Text(
                                                          (questionFormats[3][1]
                                                              as List<
                                                                  String>)[i],
                                                          style:
                                                              GoogleFonts.acme(
                                                                  fontSize:
                                                                      15)),
                                                    ],
                                                  ),
                                              Text(
                                                  "Diet : ${(questionFormats[4][1] as List<String>)[_userData["DIET"] as int]}",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15)),
                                              Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                        "Emergency Contact : ${_userData["EMERGENCY"] as String}",
                                                        style: GoogleFonts.acme(
                                                            fontSize: 15)),
                                                    const Text("*",
                                                        style: TextStyle(
                                                            fontSize: 17,
                                                            color: Colors.red))
                                                  ]),

                                              const SizedBox(height: 20),

                                              SizedBox(
                                                width: _screenSize.width * 0.75,
                                                child: const Text(
                                                    "*Contact your family in Caligo Navigator tab during emergencies",
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.red)),
                                              ),
                                              // for (var i = 0;
                                              //     i < _userData["DIET"].length;
                                              //     i++)
                                              //   if (_userData["DIET"][i] == "1")
                                              //     Row(
                                              //       children: [
                                              //         SizedBox(width: 5),
                                              //         Icon(Icons.circle,
                                              //             size: 5),
                                              //         SizedBox(width: 5),
                                              //         Text(
                                              //             (questionFormats[4][1]
                                              //                 as List<
                                              //                     String>)[i],
                                              //             style:
                                              //                 GoogleFonts.acme(
                                              //                     fontSize:
                                              //                         15)),
                                              //       ],
                                              //     ),
                                              SizedBox(height: 20)
                                            ],
                                          )
                                        ],
                                      ),
                                    ])
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            Container(
                              width: _screenSize.width * 0.9,
                              decoration: BoxDecoration(
                                color: Colors
                                    .black, // 1. Background color goes here!
                                borderRadius: BorderRadius.circular(
                                    10), // 2. Rounded corners
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha(128), // 4. Drop shadow
                                    spreadRadius: 2,
                                    blurRadius: 7,
                                    offset: const Offset(
                                        0, 3), // Changes position of shadow
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: _screenSize.width * 0.9,
                                      //height:50,

                                      decoration: BoxDecoration(
                                        color: Colors.blue
                                            .shade400, // 1. Background color goes here!
                                        borderRadius: BorderRadius.circular(
                                            10), // 2. Rounded corners
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(height: 5),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.start,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.max,
                                            children: [
                                              ElevatedButton(
                                                onPressed: () => setState(() =>
                                                    _showProfileUI[1] =
                                                        !_showProfileUI[1]),
                                                style: ElevatedButton.styleFrom(
                                                  foregroundColor: Colors.amber,
                                                  backgroundColor: Colors.white,
                                                  shape:
                                                      const CircleBorder(), // Makes the button circular
                                                  side: BorderSide(
                                                    color: Colors.amber,
                                                    width: 3,
                                                  ),
                                                ),
                                                child: Icon(
                                                    _showProfileUI[1]
                                                        ? Icons.arrow_drop_down
                                                        : Icons.arrow_right,
                                                    size: 20),
                                              ),
                                              SizedBox(width: 5),
                                              Text("Game statistics",
                                                  style: GoogleFonts.acme(
                                                      fontSize: 15,
                                                      color: Colors.white)),
                                            ],
                                          ),
                                          SizedBox(height: 5),
                                        ],
                                      )),
                                  if (_showProfileUI[1])
                                    Column(
                                      children: [
                                        SizedBox(height: 10),
                                        Center(
                                          child: Text(
                                              "${_userData["NAME"]}'s Game stats",
                                              style: GoogleFonts.acme(
                                                  fontSize: 25,
                                                  color: Colors.white)),
                                        ),
                                        Stack(
                                          children: [
                                            Positioned(
                                              bottom: 0,
                                              left: 0,
                                              child: SizedBox(
                                                width: _screenSize.width * 0.5,
                                                height:
                                                    _screenSize.height * 0.3,
                                                child: Image.asset(
                                                  "assets/gamesandtowers.png",
                                                  fit: BoxFit.contain,
                                                  alignment:
                                                      Alignment.bottomLeft,
                                                ),
                                              ),
                                            ),
                                            Center(
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.end,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 25,
                                                            height: 25,
                                                            child: Image.asset(
                                                                "assets/pointsicon.png",
                                                                fit: BoxFit
                                                                    .cover),
                                                          ),
                                                          SizedBox(width: 10),
                                                          Text(
                                                              "${_userData["POINTS"].toStringAsFixed(2)} Point${_userData["POINTS"] > 1 ? "s" : ""}",
                                                              style: GoogleFonts.acme(
                                                                  fontSize: 15,
                                                                  color: Colors
                                                                      .white)),
                                                        ],
                                                      ),
                                                      SizedBox(height: 5),
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 25,
                                                            height: 25,
                                                            child: Image.asset(
                                                                "assets/TowerA.png",
                                                                fit: BoxFit
                                                                    .cover),
                                                          ),
                                                          SizedBox(width: 10),
                                                          Text(
                                                              "Tower height: ${_userData["TOWER_HEIGHT"]}\n floor${_userData["TOWER_HEIGHT"] > 1 ? "s" : ""}",
                                                              style: GoogleFonts.acme(
                                                                  fontSize: 15,
                                                                  color: Colors
                                                                      .white)),
                                                        ],
                                                      ),
                                                      Text(
                                                          "Multiplier: ${multiplier.toStringAsFixed(2)}x",
                                                          style:
                                                              GoogleFonts.acme(
                                                                  fontSize: 15,
                                                                  color: Colors
                                                                      .white)),
                                                      ElevatedButton(
                                                          onPressed: () {
                                                            debugPrint(
                                                                "Viewing tower...");
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (context) =>
                                                                        const Towerpage(),
                                                              ),
                                                            );
                                                          },
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.blue
                                                                    .shade300,
                                                            foregroundColor: Colors
                                                                .white, // Shadow height
                                                            shape:
                                                                RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            10),
                                                                    side:
                                                                        BorderSide(
                                                                      color: Colors
                                                                          .blue
                                                                          .shade800,
                                                                      width:
                                                                          4.0,
                                                                      style: BorderStyle
                                                                          .solid,
                                                                    ) // Rounded corners
                                                                    ),
                                                          ),
                                                          child: Text(
                                                              "VIEW TOWER",
                                                              style: GoogleFonts
                                                                  .acme(
                                                                      fontSize:
                                                                          15))),
                                                      SizedBox(height: 10),
                                                      ElevatedButton(
                                                          onPressed: () {
                                                            debugPrint(
                                                                "Viewing minigames");
                                                            Navigator.push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (context) =>
                                                                        const Minigame(),
                                                              ),
                                                            );
                                                          },
                                                          style: ElevatedButton
                                                              .styleFrom(
                                                            backgroundColor:
                                                                Colors.green
                                                                    .shade300,
                                                            foregroundColor: Colors
                                                                .white, // Shadow height
                                                            shape:
                                                                RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                            10),
                                                                    side:
                                                                        BorderSide(
                                                                      color: Colors
                                                                          .green
                                                                          .shade800,
                                                                      width:
                                                                          4.0,
                                                                      style: BorderStyle
                                                                          .solid,
                                                                    ) // Rounded corners
                                                                    ),
                                                          ),
                                                          child: Text(
                                                              "GATHER POINTS",
                                                              style: GoogleFonts
                                                                  .acme(
                                                                      fontSize:
                                                                          12))),
                                                      SizedBox(height: 50),
                                                    ],
                                                  ),
                                                  SizedBox(width: 15),
                                                ],
                                              ),
                                            )
                                          ],
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 50),
                            Center(
                              child: ElevatedButton(
                                  onPressed: () =>
                                      showDevelopersDialog(context),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple.shade400,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          4.0), // Adjust radius as needed
                                      side: BorderSide(
                                        color: Colors
                                            .purple.shade600, // Border color
                                        width: 3, // Border thickness
                                      ),
                                    ),
                                  ),
                                  child: Text("See the devs behind $_appName")),
                            ),
                            const Divider(height: 28),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showDevelopersDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (dialogContext) {
      Size _dialogSize = MediaQuery.sizeOf(dialogContext);
      return AlertDialog(
        title: const Text(
          'Meet the Developers',
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Developer 1
              _developerSection(
                name: 'Marvino Drake S.',
                role: 'UI/UX Designer & Front-end Developer',
                desc:
                    'Designed most of the UI, managed the front-end code of the app, and mainly worked on the Caligo Tower system and Minigames.',
                desc_width: _dialogSize.width * 0.9,
              ),

              const Divider(height: 28),

              // Developer 2
              _developerSection(
                name: 'Ilona Kelly Oen',
                role: 'Backend Developer & Software Engineer',
                desc:
                    'Implemented the AI-powered chatbot assistant aswell as adding the Maps, Schedule, and other features',
                desc_width: _dialogSize.width * 0.9,
              ),

              const Divider(height: 28),

              // Developer 3
              _developerSection(
                name: 'Jayson',
                role: 'Vinoscape Developer',
                desc:
                    'Mainly responsible for the implementation of Vinoscape, the 3D sandbox calming construction game in this app.',
                desc_width: _dialogSize.width * 0.9,
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CLOSE'),
          ),
        ],
      );
    },
  );
}

Widget _developerSection({
  required String name,
  required String role,
  required String desc,
  required double desc_width,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        name,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
      SizedBox(
          width: desc_width,
          child: Text(
            role,
            style: const TextStyle(color: Colors.grey),
          )),
      const SizedBox(height: 10),
      SizedBox(width: desc_width, child: Text(desc)),
    ],
  );
}
