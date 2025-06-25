import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'bounding_boxes.dart';

class RealTimeObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RealTimeObjectDetection({Key? key, required this.cameras}) : super(key: key);

  @override
  _RealTimeObjectDetectionState createState() => _RealTimeObjectDetectionState();
}

class _RealTimeObjectDetectionState extends State<RealTimeObjectDetection> {
  CameraController? _controller;
  bool isModelLoaded = false;
  List<dynamic>? recognitions;
  int imageHeight = 0;
  int imageWidth = 0;
  double _focalLength = 1400;
  double _knownWidth = 0.2;
  bool _isProcessing = false;
  List<String> _labels = [];
  double _obdSpeed = 0.0;
  int _obdRpm = 0;
  int _throttlePosition = 0; // Added for throttle position
  Map<String, dynamic>? _userDetails;
  String _userId = "";
  String _errorMessage = '';
  StreamSubscription? _obdSubscription;
  final _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? _bluetoothConnection;
  String _bluetoothStatus = 'Disconnected';
  bool _isConnecting = false;
  bool _showCameraFrame = true;
  List<String> _speedingWarnings = [];
  Timer? _obdTimer;

// OBD command cycling state
  final List<String> _obdCommands = ['010D\r', '010C\r', '0111\r']; // Speed, RPM, Throttle
  int _currentObdCommandIndex = 0;
  String _obdBuffer = '';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is Map<String, dynamic> && args.containsKey('userId')) {
        _userId = args["userId"].toString();
        print('User ID from arguments: $_userId');
      } else {
        setState(() {
          _errorMessage = 'Invalid user ID provided';
          _userDetails = {
            'full_name': 'Unknown User',
            'score': '0',
            'car_name': 'Unknown',
            'car_number': 'Unknown',
            'obd_name': 'Unknown',
            'bluetooth_mac': 'Unknown'
          };
        });
      }
      _fetchUserDetails();
    });
  }

  @override
  void dispose() {
    _obdSubscription?.cancel();
    _obdTimer?.cancel();
    if (_controller != null) {
      _controller!.stopImageStream();
      _controller!.dispose();
      _controller = null;
    }
    _bluetoothConnection?.dispose();
    Tflite.close();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.storage,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();
    _initializeCamera();
    loadModel();
  }

  Future<void> _initializeCamera() async {
    try {
      final backCamera = widget.cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => throw Exception('No back camera available'),
      );

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (!mounted) return;

      final previewSize = _controller!.value.previewSize;
      if (previewSize != null) {
        setState(() {
          imageWidth = previewSize.width.round();
          imageHeight = previewSize.height.round();
        });
      }

      await _controller!.startImageStream((CameraImage image) {
        if (isModelLoaded && !_isProcessing) {
          runModel(image);
        }
      });

      if (mounted) {
        setState(() {
          _errorMessage = '';
        });
      }
    } catch (e) {
      print('Error initializing back camera: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize back camera: $e';
        });
      }
    }
  }

  Future<void> _fetchUserDetails() async {
    try {
      final response = await http.get(
        Uri.parse('https://adas-backend.onrender.com/api/get_users'),
      );
      print('Fetch user details response: ${response.body}');
      print('Status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['success']) {
            final users = data['users'] as List<dynamic>;
            if (users.isEmpty) {
              throw Exception('No users found in response');
            }
            final user = users.firstWhere(
                  (u) => u['_id'].toString() == _userId,
              orElse: () => {
                'full_name': 'Unknown User',
                'score': '0',
                'car_name': 'Unknown',
                'car_number': 'Unknown',
                'obd_name': 'Unknown',
                'bluetooth_mac': 'Unknown'
              },
            );
            print('Selected user: $user');
            if (mounted) {
              setState(() {
                _userDetails = Map<String, dynamic>.from(user);
                _errorMessage = '';
                print('Updated _userDetails: $_userDetails');
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _errorMessage = 'Failed to fetch user details: ${data['error']}';
                _userDetails = {
                  'full_name': 'Unknown User',
                  'score': '0',
                  'car_name': 'Unknown',
                  'car_number': 'Unknown',
                  'obd_name': 'Unknown',
                  'bluetooth_mac': 'Unknown'
                };
              });
            }
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _errorMessage = 'Invalid response format: $e\nResponse: ${response.body}';
              _userDetails = {
                'full_name': 'Unknown User',
                'score': '0',
                'car_name': 'Unknown',
                'car_number': 'Unknown',
                'obd_name': 'Unknown',
                'bluetooth_mac': 'Unknown'
              };
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Server error: ${response.statusCode}\n${response.body}';
            _userDetails = {
              'full_name': 'Unknown User',
              'score': '0',
              'car_name': 'Unknown',
              'car_number': 'Unknown',
              'obd_name': 'Unknown',
              'bluetooth_mac': 'Unknown'
            };
          });
        }
      }
    } catch (e) {
      print('Fetch user details error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect to server: $e';
          _userDetails = {
            'full_name': 'Unknown User',
            'score': '0',
            'car_name': 'Unknown',
            'car_number': 'Unknown',
            'obd_name': 'Unknown',
            'bluetooth_mac': 'Unknown'
          };
        });
      }
    }
  }

  Future<void> _startOBDPairing() async {
    if (_isConnecting || _bluetoothConnection?.isConnected == true) {
      print('Bluetooth already connecting or connected');
      return;
    }

    final macAddress = _userDetails?['bluetooth_mac'];
    if (macAddress == null || macAddress == 'Unknown' || macAddress.isEmpty) {
      setState(() {
        _errorMessage = 'No valid Bluetooth MAC address provided';
        _bluetoothStatus = 'Failed';
        _obdSpeed = 0.0;
        _obdRpm = 0;
        _throttlePosition = 0;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _bluetoothStatus = 'Connecting';
      _errorMessage = '';
    });

    try {
      if (!(await _bluetooth.isEnabled ?? false)) {
        await _bluetooth.requestEnable();
      }

      print('Connecting to OBD device: $macAddress');
      _bluetoothConnection = await BluetoothConnection.toAddress(macAddress).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Connection timed out'),
      );

      setState(() {
        _bluetoothStatus = 'Connected';
        _isConnecting = false;
      });
      print('Bluetooth connected to $macAddress');

      _obdSubscription?.cancel();
      _obdTimer?.cancel();
      await _initializeOBD();
      _listenForOBDData();
    } catch (e) {
      print('Bluetooth connection error: $e');
      setState(() {
        _bluetoothStatus = 'Failed';
        _isConnecting = false;
        _errorMessage = 'Failed to connect to OBD device: $e';
        _obdSpeed = 0.0;
        _obdRpm = 0;
        _throttlePosition = 0;
      });
      _bluetoothConnection?.dispose();
      _bluetoothConnection = null;
      _obdSubscription?.cancel();
      _obdTimer?.cancel();
    }
  }

  Future<void> _initializeOBD() async {
    try {
      final commands = [
        'ATZ\r',
        'ATE0\r',
        'ATL0\r',
        'ATS0\r',
        'ATSP0\r',
      ];
      for (var cmd in commands) {
        _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
        await Future.delayed(const Duration(milliseconds: 200));
      }
      print('OBD initialized');
    } catch (e) {
      print('OBD initialization error: $e');
      setState(() {
        _bluetoothStatus = 'Failed';
        _errorMessage = 'Failed to initialize OBD: $e';
        _obdSpeed = 0.0;
        _obdRpm = 0;
        _throttlePosition = 0;
      });
      _bluetoothConnection?.dispose();
      _bluetoothConnection = null;
      _obdSubscription?.cancel();
      _obdTimer?.cancel();
    }
  }

  void _listenForOBDData() {
    _obdSubscription?.cancel();
    _obdTimer?.cancel();
    _obdBuffer = '';
    _currentObdCommandIndex = 0;

    _obdSubscription = _bluetoothConnection?.input?.listen(
          (data) {
        final chunk = String.fromCharCodes(data);
        _obdBuffer += chunk;
// ELM327 responses usually end with '>'
        while (_obdBuffer.contains('>')) {
          final parts = _obdBuffer.split('>');
          final response = parts.first.trim();
          _obdBuffer = parts.sublist(1).join('>').trim();
          _processObdResponse(response);
          _sendNextObdCommand();
        }
      },
      onError: (e) {
        print('Bluetooth stream error: $e');
        setState(() {
          _bluetoothStatus = 'Failed';
          _errorMessage = 'Bluetooth connection lost: $e';
          _obdSpeed = 0.0;
          _obdRpm = 0;
          _throttlePosition = 0;
        });
        _bluetoothConnection?.dispose();
        _bluetoothConnection = null;
        _obdSubscription?.cancel();
        _obdTimer?.cancel();
      },
      onDone: () {
        print('Bluetooth connection closed');
        setState(() {
          _bluetoothStatus = 'Disconnected';
          _obdSpeed = 0.0;
          _obdRpm = 0;
          _throttlePosition = 0;
        });
        _bluetoothConnection = null;
        _obdSubscription?.cancel();
        _obdTimer?.cancel();
      },
      cancelOnError: true,
    );

// Start polling with a small delay to allow connection to settle
    _obdTimer = Timer(const Duration(milliseconds: 500), _sendNextObdCommand);
  }

  void _sendNextObdCommand() {
    if (_bluetoothConnection?.isConnected != true) {
      return;
    }
    try {
      final cmd = _obdCommands[_currentObdCommandIndex];
      _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
      _currentObdCommandIndex = (_currentObdCommandIndex + 1) % _obdCommands.length;
// Schedule next command after a short delay
      _obdTimer = Timer(const Duration(milliseconds: 400), _sendNextObdCommand);
    } catch (e) {
      print('Error sending OBD request: $e');
      setState(() {
        _bluetoothStatus = 'Failed';
        _errorMessage = 'Failed to request OBD data: $e';
        _obdSpeed = 0.0;
        _obdRpm = 0;
        _throttlePosition = 0;
      });
      _bluetoothConnection?.dispose();
      _bluetoothConnection = null;
      _obdSubscription?.cancel();
      _obdTimer?.cancel();
    }
  }

  void _processObdResponse(String response) {
// Remove echo and whitespace
    response = response.replaceAll(RegExp(r'\r|\n'), ' ').replaceAll('>', '').trim();
    print('OBD data received: $response');
    final parts = response.split(' ');
    if (response.startsWith('41 0D') && parts.length >= 3) {
      try {
        final speedHex = parts[2];
        final speed = int.parse(speedHex, radix: 16);
        setState(() {
          _obdSpeed = speed.toDouble();
        });
        print('Parsed OBD speed: $_obdSpeed km/h');
      } catch (e) {
        print('Error parsing OBD speed: $e');
      }
    } else if (response.startsWith('41 0C') && parts.length >= 4) {
      try {
        final rpmHex1 = parts[2];
        final rpmHex2 = parts[3];
        final rpm = (256 * int.parse(rpmHex1, radix: 16) + int.parse(rpmHex2, radix: 16)) / 4;
        setState(() {
          _obdRpm = rpm.round();
        });
        print('Parsed OBD RPM: $_obdRpm');
      } catch (e) {
        print('Error parsing OBD RPM: $e');
      }
    } else if (response.startsWith('41 11') && parts.length >= 3) {
      try {
        final throttleHex = parts[2];
        final throttle = int.parse(throttleHex, radix: 16);
        setState(() {
          _throttlePosition = throttle;
        });
        print('Parsed OBD Throttle Position: $_throttlePosition');
      } catch (e) {
        print('Error parsing OBD throttle position: $e');
      }
    }
  }

  Future<void> loadModel() async {
    try {
      String labelContent = await rootBundle.loadString('assets/labelmap.txt');
      _labels = labelContent.trim().split('\n').where((label) => label.isNotEmpty).toList();

      String? res = await Tflite.loadModel(
        model: 'assets/detect.tflite',
        labels: 'assets/labelmap.txt',
      );
      print('Model loaded: $res');
      if (mounted) {
        setState(() {
          isModelLoaded = res != null;
        });
      }
    } catch (e) {
      print('Error loading model: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load model: $e';
        });
      }
    }
  }

  double calculateDistance(double pixelWidth) {
    return (_knownWidth * _focalLength) / pixelWidth;
  }

  Future<void> runModel(CameraImage image) async {
    if (_isProcessing || image.planes.isEmpty) {
      print('Skipping model run: Processing=$_isProcessing, Planes=${image.planes.length}');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      var recognitions = await Tflite.detectObjectOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        model: 'SSDMobileNet',
        imageHeight: image.height,
        imageWidth: image.width,
        imageMean: 127.5,
        imageStd: 127.5,
        numResultsPerClass: 1,
        threshold: 0.4,
      );

      if (recognitions != null) {
        recognitions = recognitions.where((rec) {
          if (rec['rect'] == null ||
              rec['detectedClass'] == null ||
              rec['confidenceInClass'] == null) {
            print('Invalid recognition: Missing required fields - $rec');
            return false;
          }
          String detectedClass = rec['detectedClass'].toString();
          if (!_labels.contains(detectedClass)) {
            print('Invalid class label: $detectedClass');
            return false;
          }
          return true;
        }).toList();

        _speedingWarnings.clear();
        for (var rec in recognitions) {
          String detectedClass = rec['detectedClass'].toString();
          if (detectedClass.contains('speed_limit')) {
            double detectedSpeed = double.tryParse(detectedClass.replaceAll('speed_limit_', '')) ?? 0;
            if (_obdSpeed > detectedSpeed) {
              String description = 'Speeding detected: Car speed ${_obdSpeed.toStringAsFixed(1)} km/h, Limit $detectedSpeed km/h';
              _speedingWarnings.add(description);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(description),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              try {
                final response = await http.post(
                  Uri.parse('https://adas-backend.onrender.com/api/log_event'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'user_id': _userId,
                    'event_type': 'speeding',
                    'event_description': description,
                  }),
                );
                print('Log event response: ${response.body}');
              } catch (e) {
                print('Failed to log event: $e');
              }
            }
          }
        }
      } else {
        print('Warning: Recognitions is null from Tflite.detectObjectOnFrame');
      }

      if (mounted) {
        setState(() {
          this.recognitions = recognitions ?? [];
          imageHeight = image.height;
          imageWidth = image.width;
        });
      }
    } catch (e) {
      print('Error running model: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Model processing error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _logEvent(String eventType, String description) async {
    try {
      final response = await http.post(
        Uri.parse('https://adas-backend.onrender.com/api/log_event'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'event_type': eventType,
          'event_description': description,
        }),
      );
      print('Log event response: ${response.body}');
    } catch (e) {
      print('Failed to log event: $e');
    }
  }

  String _formatMacAddress(String? mac) {
    if (mac == null || mac == 'Unknown' || mac.isEmpty) return 'N/A';
    if (mac.length < 10) return mac;
    return '${mac.substring(0, 6)}...${mac.substring(mac.length - 4)}';
  }

  void _toggleCameraFrame() {
    setState(() {
      _showCameraFrame = !_showCameraFrame;
    });
  }

  Widget _buildDetectionOutput() {
    if (recognitions == null || recognitions!.isEmpty) {
      return const Center(
        child: Text(
          'No objects detected',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: recognitions!.length,
      itemBuilder: (context, index) {
        final rec = recognitions![index];
        final label = rec['detectedClass'].toString();
        final confidence = (rec['confidenceInClass'] * 100).toStringAsFixed(1);
        return Card(
          color: Colors.black54,
          child: ListTile(
            title: Text(
              'Object: $label',
              style: const TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              'Confidence: $confidence%',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCameraFrame(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized || _controller!.value.previewSize == null) {
      return Container(
        color: Colors.grey,
        child: const Center(
          child: Text(
            'Camera not initialized',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
    }

    final previewSize = _controller!.value.previewSize!;
    final aspectRatio = previewSize.width / previewSize.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Positioned.fill(
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
            if (recognitions != null && recognitions!.isNotEmpty)
              BoundingBoxes(
                recognitions: recognitions!,
                previewH: imageHeight.toDouble(),
                previewW: imageWidth.toDouble(),
                screenH: constraints.maxHeight,
                screenW: constraints.maxWidth,
                calculateDistance: calculateDistance,
                logEvent: _logEvent,
              ),
          ],
        );
      },
    );
  }

  Widget _buildDashboardContent(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Driver Score: ${_userDetails?['score'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Car: ${_userDetails?['car_name'] ?? 'N/A'} (${_userDetails?['car_number'] ?? 'N/A'})',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'OBD Device: ${_userDetails?['obd_name'] ?? 'N/A'}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Bluetooth MAC: ${_formatMacAddress(_userDetails?['bluetooth_mac'])}',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'OBD Speed: ${_obdSpeed.toStringAsFixed(1)} km/h',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'OBD RPM: $_obdRpm rpm',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Throttle Position: $_throttlePosition',
            style: const TextStyle(fontSize: 16),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            'Bluetooth Status: $_bluetoothStatus',
            style: TextStyle(
              fontSize: 16,
              color: _bluetoothStatus == 'Connected'
                  ? Colors.green
                  : _bluetoothStatus == 'Failed'
                  ? Colors.red
                  : Colors.orange,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton(
            onPressed: _isConnecting || _bluetoothConnection?.isConnected == true
                ? null
                : _startOBDPairing,
            child: const Text('Start OBD Pairing'),
          ),
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_errorMessage, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: _buildDetectionOutput(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Dashboard - ${_userDetails?['full_name'] ?? 'Loading...'}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: _controller != null && _controller!.value.isInitialized
                  ? _toggleCameraFrame
                  : null,
              child: Text(_showCameraFrame ? 'Hide Camera Frame' : 'Show Camera Frame'),
            ),
          ),
          Expanded(
            child: _showCameraFrame
                ? _buildCameraFrame(context)
                : _buildDashboardContent(context),
          ),
        ],
      ),
    );
  }
}