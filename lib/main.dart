import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  initializeService();
  runApp(SpeedometerApp());
}

void initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'speedometer_service',
      initialNotificationTitle: 'Speedometer Service',
      initialNotificationContent: 'Monitoring speed in the background',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

void onStart(ServiceInstance service) async {
  // Listen for stop service command
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Retrieve the server URL from SharedPreferences
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? serverUrl = prefs.getString('serverUrl') ?? 'http://localhost:6969/message';

  // Initialize location tracking
  Location location = Location();
  bool serviceEnabled = await location.serviceEnabled();
  if (!serviceEnabled) {
    serviceEnabled = await location.requestService();
  }
  PermissionStatus permissionGranted = await location.hasPermission();
  if (permissionGranted == PermissionStatus.denied) {
    permissionGranted = await location.requestPermission();
  }

  // Listen for location changes
  location.onLocationChanged.listen((LocationData currentLocation) async {
    double speed = currentLocation.speed ?? 0.0; // Speed in m/s
    double speedKmh = speed * 3.6; // Convert m/s to km/h

    try {
      final url = Uri.parse(serverUrl);
      final request = http.MultipartRequest('POST', url)
        ..fields['message'] = '${speedKmh.toStringAsFixed(2)} KMpH';

      final response = await request.send();
      if (response.statusCode != 200) {
        print('Failed to send speed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending speed: $e');
    }
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
  bool _isServiceRunning = false;

  void _startService() async {
    // Save the server URL to SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', _urlController.text.trim());

    // Start the background service
    final service = FlutterBackgroundService();
    await service.startService();

    setState(() {
      _isServiceRunning = true;
    });
  }

  void _stopService() async {
    final service = FlutterBackgroundService();
    await service.invoke('stopService');
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
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Input field for server URL
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'http://localhost:6969/message',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),

            // Start/Stop Service Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _isServiceRunning ? null : _startService,
                  child: Text('Start Service'),
                ),
                SizedBox(width: 20),
                ElevatedButton(
                  onPressed: _isServiceRunning ? _stopService : null,
                  child: Text('Stop Service'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
