import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true, // Set to false in production
  );

  runApp(SpeedometerApp());
}

// Callback for WorkManager tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    print('[DEBUG] WorkManager task triggered: $task');

    final location = Location();

    // Start location service with error handling
    try {
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        print('[DEBUG] Location service is not enabled. Requesting...');
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          print('[ERROR] Location service is still disabled.');
          return Future.value(false);
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        print('[DEBUG] Location permission not granted. Requesting...');
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('[ERROR] Location permission denied.');
          return Future.value(false);
        }
      }

      print('[DEBUG] Accessing location...');
      final locationData = await location.getLocation();
      double speed = locationData.speed ?? 0.0;
      double speedKmh = speed * 3.6;
      print('[DEBUG] Current speed: $speedKmh km/h');

      // Get server URL and send data
      final prefs = await SharedPreferences.getInstance();
      final serverUrl = prefs.getString('serverUrl') ?? 'http://localhost:6969/message';

      final url = Uri.parse(serverUrl);
      final request = http.MultipartRequest('POST', url)
        ..fields['message'] = '${speedKmh.toStringAsFixed(2)} KMpH';

      final response = await request.send();
      if (response.statusCode == 200) {
        print('[DEBUG] Speed successfully sent to server');
      } else {
        print('[DEBUG] Failed to send speed: ${response.statusCode}');
      }
    } catch (e) {
      print('[ERROR] Error during location access or data send: $e');
      return Future.value(false);
    }

    return Future.value(true);
  });
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
  bool _isTaskScheduled = false;

  Future<void> _startWorkManagerTask() async {
    print('[DEBUG] Scheduling WorkManager task');

    // Check and request permissions
    final location = Location();
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      print('[DEBUG] Location service not enabled. Requesting...');
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        print('[ERROR] Location service still disabled.');
        return;
      }
    }

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      print('[DEBUG] Location permission not granted. Requesting...');
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        print('[ERROR] Location permission denied.');
        return;
      }
    }

    // Save the server URL to SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', _urlController.text.trim());

    // Register a periodic task
    Workmanager().registerPeriodicTask(
      "speedTrackingTask",
      "speedTracking",
      frequency: const Duration(minutes: 15), // Adjust the frequency as needed
    );

    setState(() {
      _isTaskScheduled = true;
    });
  }

  Future<void> _stopWorkManagerTask() async {
    print('[DEBUG] Cancelling WorkManager task');
    Workmanager().cancelByUniqueName("speedTrackingTask");

    setState(() {
      _isTaskScheduled = false;
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
                  onPressed: _isTaskScheduled ? null : _startWorkManagerTask,
                  child: Text('Start Background Task'),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isTaskScheduled ? _stopWorkManagerTask : null,
                  child: Text('Stop Background Task'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
