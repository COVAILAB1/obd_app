import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'package:flutter/services.dart' show rootBundle, SystemChrome, DeviceOrientation;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'bounding_boxes.dart';
import 'obd_service.dart';
import 'user_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  int _throttlePosition = 0;
  Map<String, dynamic>? _userDetails;
  String _userId = '';
  String _errorMessage = '';
  List<String> _speedingWarnings = [];
  late OBDService _obdService;
  // Speed monitoring
  List<double> _speedHistory = []; // For smoothing
  static const int _speedHistoryWindow = 3; // Number of samples for smoothing
  DateTime? _lastSpeedWarningTime; // Debounce speed warnings
  static const Duration _speedWarningDebounce = Duration(seconds: 2); // Debounce interval
  // Warning positioning
  int _activeWarningCount = 0; // Track number of active warnings
  static const double _warningVerticalSpacing = 60.0; // Vertical offset between warnings
  // Collision warning management

  // Settings for overlays
  bool _showCamera = false;
  bool _showDetections = false;
  bool _showOBDData = true;
  // Location tracking for API
  LatLng? _startLocation; // Store start location
  LatLng? _endLocation; // Store end location
  bool _showConnectionStatus = false;
  bool _showSpeedWarnings = true;
  bool _showMap = true;
  bool _showDistanceTraveled = true;

  // Speed source selection
  String _selectedSpeedSource = 'GPS';

  // GPS speed and position tracking
  double _gpsSpeed = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _lastPosition;
  DateTime? _lastPositionTime;

  // Path and distance tracking
  List<LatLng> _traveledPath = [];
  double _totalDistanceTraveled = 0.0;

  // Speed monitoring
  double _previousSpeed = 0.0;
  DateTime? _lastSpeedUpdate;
  final double _suddenSpeedThreshold = 15.0; // Reduced for faster detection
  final Duration _speedCheckInterval = Duration(milliseconds: 50); // Faster interval

  // Constants for speed calculation
  static const double _minSpeedThreshold = 0.2; // Lowered for faster response
  static const double _maxSpeedThreshold = 300.0;
  static const int _speedSmoothingWindow = 1; // Reduced for less delay
  List<double> _gpsSpeedHistory = [];
  DateTime? _lastValidGPSTime;
  static const Duration _gpsValidityTimeout = Duration(seconds: 10);
  // Error popup debouncing
  DateTime? _lastErrorPopupTime;
  static const Duration _errorPopupDebounce = Duration(seconds: 10);

  // Orientation handling
  bool _isLandscape = false;
  Orientation? _lastOrientation;
  late bool _enableSpeedSmoothing;

  // Draggable overlay positions
  Offset _liveDataOverlayPosition = Offset.zero;
  Offset _distanceOverlayPosition = Offset.zero;
  Map<String, Offset> _individualOverlayPositions = {
    'RPM': Offset.zero,
    'Throttle': Offset.zero,
    'Connection': Offset.zero,
  };

  // Timers
  Timer? _modelDebounceTimer;
  static const Duration _modelDebounceDuration = Duration(milliseconds: 200);

  Timer? _gpsSpeedUpdateTimer;
  Timer? _obdStatusCheckTimer;

// Safe driving tracking
  static const Duration _safeDrivingLogInterval = Duration(seconds: 30); // Log safe driving every 30 seconds
  bool _hasAdverseEvent = false;
  Timer? _safeDrivingTimer;
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _obdService = OBDService();
    _setupOBDCallbacks();
    _obdService.setContext(context);
    _requestPermissions();
    _initializeGPS();
    _setupOrientationListener();
    _startGPSSpeedUpdates();
    _startSafeDrivingCheck();
    _startOBDStatusCheck();
    _enableSpeedSmoothing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is Map<String, dynamic> && args.containsKey('userId')) {
        _userId = args["userId"].toString();
      } else {
        _showErrorPopup('Invalid user ID provided', isOBDError: false);
        _setDefaultUserDetails();
      }
      _fetchUserDetails();
    });
  }

  void _startOBDStatusCheck() {
    _obdStatusCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (_obdService.bluetoothStatus == 'Failed' && mounted) {
        _showErrorPopup('OBD connection failed', isOBDError: true);
      }
    });
  }void _startSafeDrivingCheck() {
    _safeDrivingTimer = Timer.periodic(_safeDrivingLogInterval, (timer) {
      if (!_hasAdverseEvent && mounted) {
        _logEvent('safe_driving', 'No adverse events detected for ${_safeDrivingLogInterval.inSeconds} seconds', _lastPosition);
      }
      _hasAdverseEvent = false; // Reset after each check
    });
  }


  void _setupOrientationListener() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _resetOverlayPositions(BoxConstraints constraints) {
    if (!mounted) return;
    setState(() {
      final double baseTop = _isLandscape ? 30.0 : 60.0;
      final double baseLeft = 8.0;
      final double rightEdge = constraints.maxWidth - 150.0;
      final double spacing = 60.0;

      _liveDataOverlayPosition = Offset(baseLeft, baseTop);
      _distanceOverlayPosition = Offset(rightEdge, baseTop + spacing);
      _individualOverlayPositions['RPM'] = Offset(baseLeft, baseTop + spacing);
      _individualOverlayPositions['Throttle'] = Offset(baseLeft, baseTop + 2 * spacing);
      _individualOverlayPositions['Connection'] = Offset(baseLeft, baseTop + 3 * spacing);
    });
  }
  Future<void> _initializeGPS() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          _showErrorPopup('Location permission denied', isOBDError: false);
          return;
        }
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        const LocationSettings locationSettings = LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        );

        _positionStreamSubscription = Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen((Position position) {

          _updateDistanceTracking(position);

          _lastPosition = position;
          _lastPositionTime = DateTime.now();
          _lastValidGPSTime = DateTime.now();
        }, onError: (e) {
          if (mounted) {
            setState(() {
              _gpsSpeed = 0.0;
            });
            _showErrorPopup('GPS error: $e', isOBDError: false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showErrorPopup('Failed to initialize GPS: $e', isOBDError: false);
      }
    }
  }

  void _startGPSSpeedUpdates() {
    _gpsSpeedUpdateTimer?.cancel();
    _gpsSpeedUpdateTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (_lastPosition != null && mounted) {
        // Check if GPS data is recent
        if (_lastValidGPSTime != null &&
            DateTime.now().difference(_lastValidGPSTime!).inSeconds < _gpsValidityTimeout.inSeconds) {
          _calculateGPSSpeed(_lastPosition!);
        } else {
          // GPS data is too old, set speed to 0
          if (mounted) {
            setState(() {
              _gpsSpeed = 0.0;
            });
          }
        }
      }
    });
  }
  void _updateDistanceTracking(Position position) {
    LatLng currentPoint = LatLng(position.latitude, position.longitude);

    if (_lastPosition == null) {
      _startLocation = currentPoint; // Set start location on first GPS update
    }

    if (_lastPosition != null) {
      double distance = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      ) / 1000;

      if (_isValidDistanceJump(distance) && distance >= 0.001) {
        if (mounted) {
          setState(() {
            _totalDistanceTraveled += distance;
          });
        }
        _traveledPath.add(currentPoint);
      } else if (distance > 1.0) {
        _traveledPath.add(currentPoint);
      } else {
        _traveledPath.add(currentPoint);
      }
    } else {
      _traveledPath.add(currentPoint);
    }

    _endLocation = currentPoint; // Update end location with latest position
    _lastPosition = position;
    _lastPositionTime = DateTime.now();
  }
  Future<void> _sendLocationData() async {
    if (_traveledPath.isEmpty || _startLocation == null || _endLocation == null) {
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://adas-backend.onrender.com/api/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'start_location': {
            'latitude': _startLocation!.latitude,
            'longitude': _startLocation!.longitude,
          },
          'end_location': {
            'latitude': _endLocation!.latitude,
            'longitude': _endLocation!.longitude,
          },
          'traveled_path': _traveledPath
              .map((point) => {
            'latitude': point.latitude,
            'longitude': point.longitude,
          })
              .toList(),
          'timestamp': DateTime.now().toIso8601String(),
          'total_distance': _totalDistanceTraveled,
        }),
      );

      if (response.statusCode != 200) {
      }
    } catch (e) {
      print('Error sending location data: $e');
    }
  }
  void _calculateGPSSpeed(Position position) {
    double speedInMPS = position.speed;

    if (speedInMPS < 0) {
      speedInMPS = 0.0;
    }

    double speedInKMH = speedInMPS * 3.6;

    if (speedInKMH < _minSpeedThreshold) {
      speedInKMH = 0.0;
    }

    if (speedInKMH > _maxSpeedThreshold) {
      speedInKMH = _maxSpeedThreshold;
    }

    if (_enableSpeedSmoothing) {
      _gpsSpeedHistory.add(speedInKMH);
      if (_gpsSpeedHistory.length > _speedSmoothingWindow) {
        _gpsSpeedHistory.removeAt(0);
      }
      speedInKMH = _gpsSpeedHistory.reduce((a, b) => a + b) / _gpsSpeedHistory.length;
    }

    if (mounted) {
      setState(() {
        _gpsSpeed = speedInKMH;
      });

      if (_selectedSpeedSource == 'GPS') {
        _checkForSuddenSpeedChanges(_gpsSpeed, 'GPS', position);
      }
    }
  }

  void _toggleSpeedSmoothing(bool enable) {
    _enableSpeedSmoothing = enable;
    if (!enable) {
      _gpsSpeedHistory.clear();
    }
  }

// Enhanced helper function to validate distance jumps
  bool _isValidDistanceJump(double distanceKM) {
    // Reject distances greater than 1km between readings (likely GPS error)
    // Also reject negative distances
    if (distanceKM < 0 || distanceKM > 1.0) {
      return false;
    }

    // Additional validation: check if the distance makes sense based on time elapsed
    if (_lastPositionTime != null) {
      double timeDifferenceSeconds = DateTime.now().difference(_lastPositionTime!).inMilliseconds / 1000.0;
      if (timeDifferenceSeconds > 0) {
        // Calculate implied speed (km/h)
        double impliedSpeed = (distanceKM / timeDifferenceSeconds) * 3600;
        // Reject if implied speed is unrealistic (> 300 km/h)
        if (impliedSpeed > 300) {
          return false;
        }
      }
    }

    return true;
  }
  void _checkForSuddenSpeedChanges(double currentSpeed, String source, Position position) {
    DateTime now = DateTime.now();

    if (_lastSpeedUpdate != null &&
        now.difference(_lastSpeedUpdate!).inMilliseconds >= _speedCheckInterval.inMilliseconds &&
        (_lastSpeedWarningTime == null ||
            now.difference(_lastSpeedWarningTime!).inSeconds >= _speedWarningDebounce.inSeconds)) {
      double speedDifference = currentSpeed - _previousSpeed;
      double dynamicThreshold = currentSpeed > 100 ? _suddenSpeedThreshold * 1.2 : _suddenSpeedThreshold;

      _speedHistory.add(currentSpeed);
      if (_speedHistory.length > _speedHistoryWindow) {
        _speedHistory.removeAt(0);
      }
      double smoothedSpeed = _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

      if (speedDifference > dynamicThreshold && _showSpeedWarnings) {
        String description = 'Sudden speed increase detected: ${speedDifference.toStringAsFixed(1)} km/h via $source';
        _showSpeedWarning(description, Colors.orange);
        _logEvent('sudden_acceleration', description, position);
        _hasAdverseEvent = true;
        _lastSpeedWarningTime = now;
      } else if (speedDifference < -dynamicThreshold && _showSpeedWarnings) {
        String description = 'Sudden braking detected: ${speedDifference.abs().toStringAsFixed(1)} km/h via $source';
        _showSpeedWarning(description, Colors.red);
        _logEvent('sudden_braking', description, position);
        _hasAdverseEvent = true;
        _lastSpeedWarningTime = now;
      }

      _previousSpeed = smoothedSpeed;
      _lastSpeedUpdate = now;
    } else if (_lastSpeedUpdate == null) {
      _previousSpeed = currentSpeed;
      _lastSpeedUpdate = now;
    }
  }
  void _showSpeedWarning(String message, Color color) {
    if (mounted) {
      final warningIndex = _activeWarningCount++;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning, color: Colors.white),
              SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(
            bottom: _isLandscape
                ? 20 + (warningIndex * _warningVerticalSpacing)
                : MediaQuery.of(context).size.height - 150 - (warningIndex * _warningVerticalSpacing),
            left: 20,
            right: 20,
          ),
          onVisible: () {
            // Optional: Handle visibility if needed
          },
          action: SnackBarAction(
            label: 'Dismiss',
            onPressed: () {
              _activeWarningCount = (_activeWarningCount - 1).clamp(0, double.infinity).toInt();
            },
          ),
        ),
      ).closed.then((_) {
        if (mounted) {
          setState(() {
            _activeWarningCount = (_activeWarningCount - 1).clamp(0, double.infinity).toInt();
          });
        }
      });
    }
  }
  void _showMapDialog() {
    if (_traveledPath.isEmpty || _lastPosition == null) {
      _showErrorPopup('No GPS data available for map', isOBDError: false);
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            height: 400,
            width: 300,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Traveled Path',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: FlutterMap(
                    options: MapOptions(
                      center: LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
                      zoom: 15.0,
                      interactiveFlags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                        subdomains: ['a', 'b', 'c'],
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _traveledPath,
                            strokeWidth: 4.0,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers: [
                          if (_traveledPath.isNotEmpty) // Start point
                            Marker(
                              point: _traveledPath[0],
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.location_pin,
                                color: Colors.green,
                                size: 40,
                              ),
                            ),
                          Marker( // End point
                            point: LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
                            width: 40,
                            height: 40,
                            child: Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 40,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  void _setupOBDCallbacks() {
    _obdService.onStatusChanged = (status) {
      if (mounted && status == 'Failed') {
        _showErrorPopup('OBD Connection Failed', isOBDError: true);
      }
    };

    _obdService.onSpeedChanged = (speed) {
      if (mounted && (_obdSpeed - speed).abs() > 0.1) {
        setState(() {
          _obdSpeed = speed;
        });
        if (_selectedSpeedSource == 'OBD') {
          _checkForSuddenSpeedChanges(_obdSpeed, 'OBD', _lastPosition ?? Position(
            latitude: 0.0,
            longitude: 0.0,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            heading: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            altitudeAccuracy: 0.0,
            headingAccuracy: 0.0,
          ));
        }
      }
    };
    _obdService.onRpmChanged = (rpm) {
      if (mounted && _obdRpm != rpm) {
        setState(() {
          _obdRpm = rpm;
        });
      }
    };
    _obdService.onThrottleChanged = (throttle) {
      if (mounted && _throttlePosition != throttle) {
        setState(() {
          _throttlePosition = throttle;
        });
      }
    };
  }

  void _setDefaultUserDetails() {
    if (mounted) {
      setState(() {
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

  void _showErrorPopup(String message, {required bool isOBDError}) {
    if (mounted &&
        (_lastErrorPopupTime == null ||
            DateTime.now().difference(_lastErrorPopupTime!).inSeconds >= _errorPopupDebounce.inSeconds)) {
      _lastErrorPopupTime = DateTime.now();
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Error'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (isOBDError &&
                    _userDetails != null &&
                    _userDetails!['obd_name'] != null &&
                    _userDetails!['obd_name'] != 'Unknown')
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Bluetooth Device: ${_userDetails!['obd_name']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.settings, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Settings'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExpansionTile(
                      leading: Icon(Icons.person),
                      title: Text('Profile'),
                      children: [
                        _buildProfileRow('Name', _userDetails?['full_name']?.toString() ?? 'N/A', Icons.person),
                        _buildProfileRow('Score', _userDetails?['score']?.toString() ?? 'N/A', Icons.star),
                        _buildProfileRow(
                            'Car',
                            '${_userDetails?['car_name']?.toString() ?? 'N/A'} (${_userDetails?['car_number']?.toString() ?? 'N/A'})',
                            Icons.directions_car),
                        _buildProfileRow('OBD Device', _userDetails?['obd_name']?.toString() ?? 'N/A', Icons.device_hub),
                        _buildProfileRow(
                            'MAC Address', _formatMacAddress(_userDetails?['bluetooth_mac']?.toString()), Icons.bluetooth),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.account_circle),
                            label: Text('View Profile'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => UserPage(cameras: widget.cameras),
                                  settings: RouteSettings(arguments: {'userId': _userId}),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      leading: Icon(Icons.bluetooth),
                      title: Text('OBD Connection'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Status:'),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _obdService.bluetoothStatus == 'Connected'
                                          ? Colors.green
                                          : _obdService.bluetoothStatus == 'Failed'
                                          ? Colors.red
                                          : Colors.orange,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _obdService.bluetoothStatus,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(
                                    onPressed: _obdService.bluetoothStatus == 'Connecting' ||
                                        _obdService.bluetoothStatus == 'Connected'
                                        ? null
                                        : () => _obdService.startOBDPairing(_userDetails?['bluetooth_mac']?.toString()),
                                    child: _obdService.bluetoothStatus == 'Connecting'
                                        ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                        : const Text('Connect'),
                                  ),
                                  ElevatedButton(
                                    onPressed: _obdService.bluetoothStatus == 'Connected' ? _obdService.disconnectOBD : null,
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),
                              _buildConnectionQuality(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      leading: Icon(Icons.speed),
                      title: Text('Speed Source'),
                      children: [
                        ListTile(
                          title: Text('Use GPS Speed'),
                          leading: Radio<String>(
                            value: 'GPS',
                            groupValue: _selectedSpeedSource,
                            onChanged: (value) {
                              setDialogState(() => _selectedSpeedSource = value!);
                              setState(() => _selectedSpeedSource = value!);
                            },
                          ),
                        ),
                        ListTile(
                          title: Text('Use OBD Speed'),
                          leading: Radio<String>(
                            value: 'OBD',
                            groupValue: _selectedSpeedSource,
                            onChanged: (value) {
                              setDialogState(() => _selectedSpeedSource = value!);
                              setState(() => _selectedSpeedSource = value!);
                            },
                          ),
                        ),
                      ],
                    ),
                    ExpansionTile(
                      leading: Icon(Icons.display_settings),
                      title: Text('Display Options'),
                      children: [
                        SwitchListTile(
                          title: Text('Show Camera'),
                          subtitle: Text('Display camera feed'),
                          value: _showCamera,
                          onChanged: (value) {
                            setDialogState(() => _showCamera = value);
                            setState(() => _showCamera = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text('Show Detections'),
                          subtitle: Text('Enable object detection'),
                          value: _showDetections,
                          onChanged: (value) async {
                            setDialogState(() => _showDetections = value);
                            setState(() => _showDetections = value);
                            if (_controller != null && _controller!.value.isInitialized) {
                              if (!value && !_showCamera) {
                                await _controller!.stopImageStream();
                              } else if (value && !_controller!.value.isStreamingImages) {
                                await _controller!.startImageStream((CameraImage image) {
                                  if (isModelLoaded && !_isProcessing && _showDetections) {
                                    _debounceModel(image);
                                  }
                                });
                              }
                            }
                          },
                        ),

                        SwitchListTile(
                          title: Text('Show All OBD Data'),
                          subtitle: Text('OBD speed, RPM and throttle overlay'),
                          value: _showOBDData,
                          onChanged: (value) {
                            setDialogState(() => _showOBDData = value);
                            setState(() => _showOBDData = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text('Show Connection Status'),
                          subtitle: Text('OBD connection quality'),
                          value: _showConnectionStatus,
                          onChanged: (value) {
                            setDialogState(() => _showConnectionStatus = value);
                            setState(() => _showConnectionStatus = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text('Show Speed Warnings'),
                          subtitle: Text('Sudden speed change and speed limit alerts'),
                          value: _showSpeedWarnings,
                          onChanged: (value) {
                            setDialogState(() => _showSpeedWarnings = value);
                            setState(() => _showSpeedWarnings = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text('Show Map'),
                          subtitle: Text('Map icon to view traveled path'),
                          value: _showMap,
                          onChanged: (value) {
                            setDialogState(() => _showMap = value);
                            setState(() => _showMap = value);
                          },
                        ),
                        SwitchListTile(
                          title: Text('Show Distance Traveled'),
                          subtitle: Text('Total distance traveled overlay'),
                          value: _showDistanceTraveled,
                          onChanged: (value) {
                            setDialogState(() => _showDistanceTraveled = value);
                            setState(() => _showDistanceTraveled = value);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _modelDebounceTimer?.cancel();
    _gpsSpeedUpdateTimer?.cancel();
    _obdStatusCheckTimer?.cancel();
    _safeDrivingTimer?.cancel();

    _sendLocationData();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (_controller != null) {
      _controller!.stopImageStream();
      _controller!.dispose();
      _controller = null;
    }
    _positionStreamSubscription?.cancel();
    _obdService.dispose();
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
      Permission.location,
      Permission.locationWhenInUse,
    ].request();
    await _initializeCamera();
    await loadModel();
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
        if (isModelLoaded && !_isProcessing && _showDetections) {
          _debounceModel(image);
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
        _showErrorPopup('Failed to initialize back camera: $e', isOBDError: false);
      }
    }
  }

  Future<void> _fetchUserDetails() async {
    try {
      final response = await http.get(
        Uri.parse('https://adas-backend.onrender.com/api/get_users'),
      );

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
              _showErrorPopup('Failed to fetch user details: ${data['error']}', isOBDError: false);
              _setDefaultUserDetails();
            }
          }
        } catch (e) {
          if (mounted) {
            _showErrorPopup('Invalid response format: $e', isOBDError: false);
            _setDefaultUserDetails();
          }
        }
      } else {
        if (mounted) {
          _showErrorPopup('Server error: ${response.statusCode}', isOBDError: false);
          _setDefaultUserDetails();
        }
      }
    } catch (e) {
      print('Fetch user details error: $e');
      if (mounted) {
        _showErrorPopup('Failed to connect to server: $e', isOBDError: false);
        _setDefaultUserDetails();
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
        _showErrorPopup('Failed to load model: $e', isOBDError: false);
      }
    }
  }

  void _debounceModel(CameraImage image) {
    if (_modelDebounceTimer?.isActive ?? false) return;
    _modelDebounceTimer = Timer(_modelDebounceDuration, () {
      runModel(image);
    });
  }


  double calculateDistance(double pixelWidth) {
    return (_knownWidth * _focalLength) / pixelWidth;
  }

  Future<void> runModel(CameraImage image) async {
    if (_isProcessing || image.planes.isEmpty) return;

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

      print('Recognitions: $recognitions');

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

        for (var rec in recognitions) {
          String detectedClass = rec['detectedClass'].toString();
          if (detectedClass.contains('speed_limit')) {
            double detectedSpeed = double.tryParse(detectedClass.replaceAll('speed_limit_', '')) ?? 0;
            if (_obdSpeed > detectedSpeed) {
              String description = 'Speeding detected: Car speed $_obdSpeed km/h, Limit $detectedSpeed km/h';
              _logEvent('speed_limit_detected', description);

            }
          }
        }
      }

      if (mounted) {
        setState(() {
          this.recognitions = recognitions;
          imageHeight = image.height;
          imageWidth = image.width;
        });
      }
    } catch (e) {
      print('Error running model: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  Future<void> _logEvent(String eventType, String description, [Position? position]) async {
    try {
      final response = await http.post(
        Uri.parse('https://adas-backend.onrender.com/api/log_event'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': _userId,
          'event_type': eventType,
          'event_description': description,
          'timestamp': DateTime.now().toIso8601String(),
          'speed_obd': _obdSpeed,
          'speed_gps': _gpsSpeed,
          'latitude': position?.latitude ?? 0.0,
          'longitude': position?.longitude ?? 0.0,
        }),
      );
    } catch (e) {
      print('Failed to log event: $e');
    }
  }

  String _formatMacAddress(String? mac) {
    if (mac == null || mac.isEmpty) return 'N/A';
    if (mac.length < 10) return mac;
    return '${mac.substring(0, 6)}...${mac.substring(mac.length - 4)}';
  }



  Widget _buildDistanceOverlay(BoxConstraints constraints) {
    if (!_showDistanceTraveled) return SizedBox.shrink();

    return Positioned(
      left: _distanceOverlayPosition.dx.clamp(0, constraints.maxWidth - 150),
      top: _distanceOverlayPosition.dy.clamp(0, constraints.maxHeight - 100),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _distanceOverlayPosition += details.delta;
            _distanceOverlayPosition = Offset(
              _distanceOverlayPosition.dx.clamp(0, constraints.maxWidth - 150),
              _distanceOverlayPosition.dy.clamp(0, constraints.maxHeight - 100),
            );
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.yellow, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text(
                    '${_totalDistanceTraveled.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _isLandscape ? 16 : 20,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'km',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _isLandscape ? 10 : 12,
                    ),
                  ),
                ],
              ),
              Text(
                'Distance Traveled',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildLiveDataOverlay(BoxConstraints constraints) {
    if (!_showOBDData) return SizedBox.shrink();

    return Positioned(
      left: _liveDataOverlayPosition.dx.clamp(0, constraints.maxWidth - 240),
      top: _liveDataOverlayPosition.dy.clamp(0, constraints.maxHeight - 60),
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _liveDataOverlayPosition += details.delta;
            _liveDataOverlayPosition = Offset(
              _liveDataOverlayPosition.dx.clamp(0, constraints.maxWidth - 240),
              _liveDataOverlayPosition.dy.clamp(0, constraints.maxHeight - 60),
            );
          });
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCompactCardDataTile(
                  'Speed ($_selectedSpeedSource)',
                  '${(_selectedSpeedSource == 'OBD' ? _obdSpeed : _gpsSpeed).toInt()} km/h',
                  Colors.blue),
              _buildCompactCardDataTile('RPM', '$_obdRpm', Colors.orange),
              _buildCompactCardDataTile('Throttle', '$_throttlePosition%', Colors.green),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildIndividualOverlays(BoxConstraints constraints) {
    List<Widget> overlays = [];

    if (_showConnectionStatus) {
      overlays.add(
        Positioned(
          top: _individualOverlayPositions['Connection']!.dy.clamp(0, constraints.maxHeight - 60),
          left: _individualOverlayPositions['Connection']!.dx.clamp(0, constraints.maxWidth - 120),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _individualOverlayPositions['Connection'] = _individualOverlayPositions['Connection']! + details.delta;
                _individualOverlayPositions['Connection'] = Offset(
                  _individualOverlayPositions['Connection']!.dx.clamp(0, constraints.maxWidth - 120),
                  _individualOverlayPositions['Connection']!.dy.clamp(0, constraints.maxHeight - 60),
                );
              });
            },
            child: _buildIndividualCardDataTile(
              'Connection',
              _obdService.bluetoothStatus,
              _obdService.bluetoothStatus == 'Connected' ? Colors.green : Colors.red,
              Icons.bluetooth,
            ),
          ),
        ),
      );
    }

    return Stack(children: overlays);
  }
  Widget _buildIndividualCardDataTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactCardDataTile(String label, String value, Color color) {
    return SizedBox(
      width: _isLandscape ? 100 : 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: _isLandscape ? 16 : 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: _isLandscape ? 10 : 8,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionQuality() {
    final recentData = _obdService.lastUpdateTimes.values.where((time) => DateTime.now().difference(time).inSeconds < 5).length;

    String quality;
    Color color;

    if (recentData >= 3) {
      quality = 'Excellent';
      color = Colors.green;
    } else if (recentData >= 2) {
      quality = 'Good';
      color = Colors.orange;
    } else if (recentData >= 1) {
      quality = 'Poor';
      color = Colors.red;
    } else {
      quality = 'No Data';
      color = Colors.grey;
    }

    return Row(
      children: [
        Icon(Icons.signal_cellular_alt, color: color, size: 20),
        SizedBox(width: 4),
        Text(
          'Data: $quality',
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
// Add this to the parent widget's state class
// Add this to the parent widget's state class
  List<DateTime> _collisionLogTimestamps = [];

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
        final currentOrientation = MediaQuery.of(context).orientation;
        if (_lastOrientation == null || _lastOrientation != currentOrientation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _resetOverlayPositions(constraints);
              setState(() {
                _lastOrientation = currentOrientation;
              });
            }
          });
        }

        // Detect and log collision warnings for up to 3 different objects per minute
        if (_showDetections && recognitions != null && recognitions!.isNotEmpty) {
          final now = DateTime.now();
          // Clean up timestamps older than 60 seconds
          _collisionLogTimestamps.removeWhere((t) => now.difference(t).inSeconds > 60);

          // Only log if fewer than 3 events in the last 60 seconds
          if (_collisionLogTimestamps.length < 3) {
            // Track logged objects in this frame to ensure uniqueness
            Set<String> loggedObjects = {};

            for (var rec in recognitions!) {
              double w = rec["rect"]["w"] * constraints.maxWidth;
              double distance = calculateDistance(w);
              if (distance <= 1.5) {
                // Generate a unique key for the object (coarser rounding for stability)
                double centerX = (rec["rect"]["x"] + rec["rect"]["w"] / 2) * constraints.maxWidth;
                double centerY = (rec["rect"]["y"] + rec["rect"]["h"] / 2) * constraints.maxHeight;
                String objectKey = '${rec["detectedClass"]}_${(centerX / 10).round() * 10}_${(centerY / 10).round() * 10}';

                // Log only if this object hasn't been logged in this frame and limit not reached
                if (!loggedObjects.contains(objectKey) && _collisionLogTimestamps.length < 3) {
                  _logEvent(
                    'collision_warning',
                    'Object ${rec["detectedClass"]} detected within 1.5 meters',
                    _lastPosition,
                  );
                  _collisionLogTimestamps.add(now);
                  loggedObjects.add(objectKey);
                  // Limit to one log per frame to prevent bursts
                  break;
                }
              }
            }
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: _showCamera
                  ? AspectRatio(
                aspectRatio: aspectRatio,
                child: CameraPreview(_controller!),
              )
                  : Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.videocam_off, color: Colors.white, size: 50),
                      SizedBox(height: 16),
                      Text(
                        'Camera Feed Disabled',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      Text(
                        'Enable Camera in settings to view feed',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_showDetections && recognitions != null && recognitions!.isNotEmpty)
              BoundingBoxes(
                recognitions: recognitions!,
                previewH: imageHeight.toDouble(),
                previewW: imageWidth.toDouble(),
                screenH: constraints.maxHeight,
                screenW: constraints.maxWidth,
                calculateDistance: calculateDistance,
                logEvent: (eventType, description) => _logEvent(eventType, description, _lastPosition),
              ),
            _buildLiveDataOverlay(constraints),
            _buildIndividualOverlays(constraints),
            _buildDistanceOverlay(constraints),
            if (_isLandscape)
              Positioned(
                top: 30,
                left: 60,
                child: IconButton(
                  icon: Icon(Icons.settings, color: Colors.white),
                  onPressed: _showSettingsDialog,
                ),
              ),
            if (_isLandscape && _showMap)
              Positioned(
                top: 80,
                left: 60,
                child: IconButton(
                  icon: Icon(Icons.map, color: Colors.white),
                  onPressed: _showMapDialog,
                ),
              ),
          ],
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    _isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      appBar: _isLandscape
          ? null
          : AppBar(
        title: Text('ADAS - ${_userDetails?['full_name'] ?? 'Loading...'}'),
        actions: [
          if (_showMap)
            IconButton(
              onPressed: _showMapDialog,
              icon: Icon(Icons.map, color: Colors.white),
            ),
          IconButton(
            onPressed: _showSettingsDialog,
            icon: Icon(Icons.settings, color: Colors.white),
          ),
          SizedBox(width: 8),
        ],
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: _buildCameraFrame(context),
    );
  }
}