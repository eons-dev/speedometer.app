import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(SpeedometerApp());
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
  Location _location = Location();
  double _speed = 0.0;
  bool _isSending = false;
  String _serverUrl = 'http://localhost:6969/message';
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndStartUpdates();
  }

  Future<void> _checkPermissionsAndStartUpdates() async {
    bool _serviceEnabled;
    PermissionStatus _permissionGranted;

    // Check if location service is enabled
    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    // Check for location permissions
    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }

    // Start listening to location updates
    _location.onLocationChanged.listen((LocationData currentLocation) {
      setState(() {
        _speed = currentLocation.speed ?? 0.0; // Speed in m/s
      });

      if (_serverUrl.isNotEmpty) {
        _sendSpeedToServer(_speed * 3.6); // Convert m/s to km/h
      }
    });
  }

  Future<void> _sendSpeedToServer(double speed) async {
    if (_isSending) return; // Prevent multiple requests in parallel
    setState(() {
      _isSending = true;
    });

    try {
      final url = Uri.parse(_serverUrl);

      // Construct the multipart request
      final request = http.MultipartRequest('POST', url)
        ..fields['message'] = '${speed.toStringAsFixed(2)} KMpH';

      final response = await request.send();

      if (response.statusCode == 200) {
        print('Speed sent successfully');
      } else {
        print('Failed to send speed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending speed: $e');
    }

    setState(() {
      _isSending = false;
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
              onChanged: (value) {
                setState(() {
                  _serverUrl = value.trim();
                });
              },
            ),
            SizedBox(height: 20),

            // Display current speed
            Text(
              'Current Speed:',
              style: TextStyle(fontSize: 24),
            ),
            Text(
              '${(_speed * 3.6).toStringAsFixed(2)} km/h', // Convert m/s to km/h
              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),

            // Show sending status
            if (_isSending)
              CircularProgressIndicator()
            else
              Text(
                'Ready to send speed to the server',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}
