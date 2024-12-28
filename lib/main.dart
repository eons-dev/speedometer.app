import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeForegroundService();
  runApp(ProviderScope(child: SpeedometerApp()));
}

void initializeForegroundService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'speedometer_service',
      channelName: 'Speedometer Service',
      channelImportance: NotificationChannelImportance.MIN,
      iconData: null,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      isOnceEvent: false,
    ),
  );
}

// Provider to manage and display the current speed
final speedProvider = StateNotifierProvider<SpeedNotifier, double>((ref) => SpeedNotifier());

class SpeedNotifier extends StateNotifier<double> {
  SpeedNotifier() : super(0.0);

  void updateSpeed(double newSpeed) {
    state = newSpeed;
  }
}

class SpeedometerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SpeedometerScreen(),
    );
  }
}

class SpeedometerScreen extends StatefulWidget {
  @override
  _SpeedometerScreenState createState() => _SpeedometerScreenState();
}

class _SpeedometerScreenState extends State<SpeedometerScreen> {
  final TextEditingController _urlController = TextEditingController(text: 'http://localhost:6969/message');
  bool _isServiceRunning = false;

  Future<void> _startForegroundService() async {
    // Save the server URL to SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', _urlController.text.trim());

    // Start the foreground service
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.restartService();
    } else {
      FlutterForegroundTask.startService(
        notificationTitle: 'Speedometer Running',
        notificationText: 'Tracking your speed...',
        callback: _startForegroundCallback,
      );
    }

    setState(() {
      _isServiceRunning = true;
    });
  }

  void _stopForegroundService() {
    FlutterForegroundTask.stopService();
    setState(() {
      _isServiceRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Speedometer'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isServiceRunning ? null : _startForegroundService,
                  child: Text('Start Service'),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isServiceRunning ? _stopForegroundService : null,
                  child: Text('Stop Service'),
                ),
              ],
            ),
            SizedBox(height: 40),
            // Display the current speed
            Consumer(
              builder: (context, ref, child) {
                final speed = ref.watch(speedProvider);
                return Text(
                  '${speed.toStringAsFixed(2)} km/h',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
void _startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(SpeedometerTaskHandler());
}

class SpeedometerTaskHandler extends TaskHandler {
  late Location _location;
  String? _serverUrl;
  SendPort? _sendPort;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;

    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('serverUrl') ?? 'http://localhost:6969/message';

    _location = Location();
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
    }
    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
    }

    print('Speedometer foreground service started.');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    LocationData? locationData = await _location.getLocation();
    double speed = locationData.speed ?? 0.0; // Speed in m/s
    double speedKmh = speed * 3.6; // Convert m/s to km/h

    // Update the UI with the current speed
    sendPort?.send(speedKmh);

    try {
      final url = Uri.parse(_serverUrl!);
      final request = http.MultipartRequest('POST', url)
        ..fields['message'] = '${speedKmh.toStringAsFixed(2)} KMpH';

      final response = await request.send();
      if (response.statusCode != 200) {
        print('Failed to send speed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending speed: $e');
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    print('Speedometer foreground service stopped.');
  }
}
