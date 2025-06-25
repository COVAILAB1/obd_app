

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:obd2_plugin/obd2_plugin.dart'; // Import the Obd2Plugin class

enum ConnectionMode { defaultMode, obd2Plugin }

class OBDService {
  final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection? _bluetoothConnection;
  Obd2Plugin? _obd2Plugin;
  StreamSubscription? _obdSubscription;
  Timer? _obdCommandTimer;
  String _bluetoothStatus = 'Disconnected';
  bool _isConnecting = false;
  bool _isAwaitingResponse = false;
  DateTime? _lastCommandSent;
  DateTime? _lastDataReceived;
  int _consecutiveErrors = 0;
  final int _maxConsecutiveErrors = 5;
  String _obdBuffer = '';
  Map<String, DateTime> _lastUpdateTimes = {};
  List<String> _liveResponses = [];
  BuildContext? _context;
  ConnectionMode _connectionMode = ConnectionMode.defaultMode;

// Enhanced OBD command cycling with fallbacks
  final List<List<String>> _obdCommandSets = [
    ['010D', '010C', '0111'], // Primary set
    ['01 0D', '01 0C', '01 11'], // With spaces
    ['010D\r', '010C\r', '0111\r'], // With carriage return
    ['010D\r\n', '010C\r\n', '0111\r\n'], // With CRLF
  ];
  int _currentCommandSetIndex = 0;
  int _currentObdCommandIndex = 0;
  int _commandSetRetryCount = 0;
  final int _maxCommandSetRetries = 3;

// Comprehensive OBD command mapping
  final Map<String, Map<String, dynamic>> _obdCommandMap = {
    '01 0D': {'name': 'speed', 'description': 'Vehicle Speed'},
    '01 0C': {'name': 'rpm', 'description': 'Engine RPM'},
    '01 11': {'name': 'throttle', 'description': 'Throttle Position'},
    '01 05': {'name': 'coolant_temp', 'description': 'Engine Coolant Temperature'},
    '01 0A': {'name': 'fuel_pressure', 'description': 'Fuel Rail Pressure'},
    '01 0B': {'name': 'intake_pressure', 'description': 'Intake Manifold Pressure'},
    '01 0F': {'name': 'intake_temp', 'description': 'Intake Air Temperature'},
    '01 10': {'name': 'maf', 'description': 'Mass Air Flow Rate'},
    '01 42': {'name': 'control_voltage', 'description': 'Control Module Voltage'},
    '01 46': {'name': 'ambient_temp', 'description': 'Ambient Air Temperature'},
  };

// Callbacks for updating UI
  Function(String)? onStatusChanged;
  Function(String)? onError;
  Function(double)? onSpeedChanged;
  Function(int)? onRpmChanged;
  Function(int)? onThrottleChanged;
  Function(List<String>)? onLiveResponsesChanged;

  String get bluetoothStatus => _bluetoothStatus;
  List<String> get liveResponses => _liveResponses;

  void setContext(BuildContext context) {
    _context = context;
  }

  Future<void> startOBDPairing(String? macAddress) async {
    if (_isConnecting || _bluetoothConnection?.isConnected == true || (await _obd2Plugin?.hasConnection ?? false)) {
      print('Bluetooth already connecting or connected');
      return;
    }

    if (macAddress == null || macAddress == 'Unknown' || macAddress.isEmpty) {
      _showErrorPopup('No valid Bluetooth MAC address provided');
      _setStatus('Failed');
      _resetOBDData();
      return;
    }

    if (_context == null) {
      print('Context not set for popup');
      return;
    }

    // Show popup to select connection mode
    await showConnectionModePopup(macAddress);
  }

// New method to show connection mode selection popup
  Future<void> showConnectionModePopup(String macAddress) async {
    if (_context == null) return;

    await showDialog(
      context: _context!,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Select Connection Mode'),
          content: Text('Choose the mode to connect to the OBD device:'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startConnectionWithMode(macAddress, ConnectionMode.defaultMode);
              },
              child: Text('Default Mode'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _startConnectionWithMode(macAddress, ConnectionMode.obd2Plugin);
              },
              child: Text('Obd2Plugin Mode'),
            ),
          ],
        );
      },
    );
  }

// New method to initiate connection with selected mode
  Future<void> _startConnectionWithMode(String macAddress, ConnectionMode mode) async {
    _connectionMode = mode;
    _setStatus('Connecting');
    _isConnecting = true;
    _clearError();

    if (_connectionMode == ConnectionMode.obd2Plugin) {
      await _connectUsingObd2Plugin(macAddress);
    } else {
      await _connectUsingDefault(macAddress);
    }
  }

  Future<void> _connectUsingDefault(String macAddress) async {
    try {
      if (!(await _bluetooth.isEnabled ?? false)) {
        await _bluetooth.requestEnable();
        await Future.delayed(const Duration(seconds: 2));
      }

      print('Connecting to OBD device (default): $macAddress');
      _bluetoothConnection = await BluetoothConnection.toAddress(macAddress).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Connection timed out'),
      );

      _setStatus('Connected');
      _isConnecting = false;
      print('Bluetooth connected to $macAddress (default)');

      _showSuccessPopup();
      _obdSubscription?.cancel();
      _obdCommandTimer?.cancel();

      await _initializeOBD();
      _listenForOBDData();
    } catch (e) {
      print('Default Bluetooth connection error: $e');
      _showErrorPopup('Default connection failed: ${e.toString()}. Trying Obd2Plugin...');
      _connectionMode = ConnectionMode.obd2Plugin;
      await _connectUsingObd2Plugin(macAddress);
    }
  }

  Future<void> _connectUsingObd2Plugin(String macAddress) async {
    try {
      _obd2Plugin = Obd2Plugin();
      final device = (await _obd2Plugin!.getPairedDevices).firstWhere(
            (d) => d.address == macAddress,
        orElse: () => throw Exception('Device not found in paired devices'),
      );

      await _obd2Plugin!.getConnection(
        device,
            (connection) {
          _bluetoothConnection = connection;
          _setStatus('Connected');
          _isConnecting = false;
          print('Bluetooth connected to $macAddress (Obd2Plugin)');
          _showSuccessPopup();
          _initializeOBDPlugin();
          _listenForOBDData();
        },
            (error) => throw Exception(error),
      );
    } catch (e) {
      print('Obd2Plugin connection error: $e');
      _showErrorPopup('Failed to connect to OBD device: ${e.toString()}');
      _handleConnectionError('Failed to connect to OBD device: $e');
    }
  }

  void _showSuccessPopup() {
    if (_context != null) {
      showDialog(
        context: _context!,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 24),
                    SizedBox(width: 8),
                    Text('OBD Connected Successfully', style: TextStyle(fontSize: 16)),
                  ],
                ),
                content: Container(
                  width: double.maxFinite,
                  height: 400,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live OBD Responses:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 8),
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.black87,
                          ),
                          child: StreamBuilder<List<String>>(
                            stream: Stream.periodic(Duration(milliseconds: 100), (_) => _liveResponses),
                            builder: (context, snapshot) {
                              return ListView.builder(
                                reverse: true,
                                itemCount: _liveResponses.length,
                                itemBuilder: (context, index) {
                                  final reverseIndex = _liveResponses.length - 1 - index;
                                  return Padding(
                                    padding: EdgeInsets.symmetric(vertical: 1),
                                    child: Text(
                                      _liveResponses[reverseIndex],
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text('Parsed Data:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      SizedBox(height: 8),
                      Expanded(
                        flex: 1,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.blue.shade50,
                          ),
                          child: StreamBuilder<Map<String, dynamic>>(
                            stream: Stream.periodic(Duration(milliseconds: 500), (_) => _getCurrentValues()),
                            builder: (context, snapshot) {
                              final values = snapshot.data ?? {};
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDataRow('Speed', '${values['speed']?.toStringAsFixed(1) ?? '0.0'} km/h'),
                                  _buildDataRow('RPM', '${values['rpm'] ?? 0} rpm'),
                                  _buildDataRow('Throttle', '${values['throttle'] ?? 0}%'),
                                ],
                              );
                            },
                          ),
                        ),
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
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          Text(value, style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
        ],
      ),
    );
  }

  Map<String, dynamic> _getCurrentValues() {
    return {
      'speed': _currentSpeed,
      'rpm': _currentRpm,
      'throttle': _currentThrottle,
    };
  }

  double _currentSpeed = 0.0;
  int _currentRpm = 0;
  int _currentThrottle = 0;

  void _showErrorPopup(String error) {
    if (_context != null) {
      showDialog(
        context: _context!,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text('Connection Error', style: TextStyle(fontSize: 16)),
              ],
            ),
            content: Text(error),
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

  Future<void> _initializeOBD() async {
    try {
      final initCommands = [
        'ATZ\r',      // Reset
        'ATE0\r',     // Echo off
        'ATL0\r',     // Line feeds off
        'ATS0\r',     // Spaces off
        'ATH1\r',     // Headers on
        'ATSP0\r',    // Set protocol auto
        'ATAT2\r',    // Adaptive timing auto
        '0100\r',     // Test connectivity
      ];

      for (var cmd in initCommands) {
        print('Sending init command: ${cmd.trim()}');
        _addLiveResponse('TX: ${cmd.trim()}');
        _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
        await _bluetoothConnection?.output.allSent;
        await Future.delayed(const Duration(milliseconds: 800));
      }

      print('OBD initialized successfully');
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      print('OBD initialization error: $e');
      _showErrorPopup('Failed to initialize OBD: ${e.toString()}');
      _handleConnectionError('Failed to initialize OBD: $e');
    }
  }

  Future<void> _initializeOBDPlugin() async {
    try {
      String configJson = '''
      [
        {"command": "ATZ"},
        {"command": "ATE0"},
        {"command": "ATL0"},
        {"command": "ATS0"},
        {"command": "ATH1"},
        {"command": "ATSP0"},
        {"command": "ATAT2"},
        {"command": "0100"}
      ]
      ''';
      int configTime = await _obd2Plugin!.configObdWithJSON(configJson, requestCode: 100);
      await Future.delayed(Duration(milliseconds: configTime));
      print('OBD initialized successfully (Obd2Plugin)');
    } catch (e) {
      print('OBD initialization error (Obd2Plugin): $e');
      _showErrorPopup('Failed to initialize OBD (Obd2Plugin): ${e.toString()}');
      _handleConnectionError('Failed to initialize OBD: $e');
    }
  }

  void _addLiveResponse(String response) {
    _liveResponses.add('${DateTime.now().millisecondsSinceEpoch % 100000}: $response');
    if (_liveResponses.length > 50) {
      _liveResponses.removeAt(0);
    }
    onLiveResponsesChanged?.call(_liveResponses);
  }

  void _listenForOBDData() {
    _obdSubscription?.cancel();
    _obdCommandTimer?.cancel();
    _obdBuffer = '';
    _currentObdCommandIndex = 0;
    _isAwaitingResponse = false;
    _consecutiveErrors = 0;
    _liveResponses.clear();

    if (_connectionMode == ConnectionMode.obd2Plugin) {
      _listenForOBDDataPlugin();
    } else {
      _listenForOBDDataDefault();
    }
  }

  void _listenForOBDDataDefault() {
    _obdSubscription = _bluetoothConnection?.input?.listen(
          (data) {
        try {
          final chunk = String.fromCharCodes(data);
          _obdBuffer += chunk;
          _lastDataReceived = DateTime.now();

          if (chunk.trim().isNotEmpty) {
            _addLiveResponse('RX: ${chunk.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}');
          }

          _processBufferedResponses();
        } catch (e) {
          print('Error processing OBD data: $e');
          _consecutiveErrors++;
          _checkConnectionHealth();
        }
      },
      onError: (e) {
        print('Bluetooth stream error: $e');
        _showErrorPopup('Bluetooth stream error: ${e.toString()}');
        _handleConnectionError('Bluetooth stream error: $e');
      },
      onDone: () {
        print('Bluetooth connection closed');
        _showErrorPopup('Bluetooth connection was closed unexpectedly');
        _handleConnectionError('Connection closed');
      },
      cancelOnError: false,
    );

    _startContinuousCommands();
  }

  void _listenForOBDDataPlugin() {
    String paramJson = '''
    [
      {"PID": "010D", "description": "Speed, [0]", "unit": "km/h"},
      {"PID": "010C", "description": "RPM, (([0] * 256) + [1]) / 4", "unit": "rpm"},
      {"PID": "0111", "description": "Throttle, ([0] * 100) / 255", "unit": "%"}
    ]
    ''';
    _obd2Plugin!.setOnDataReceived((command, response, requestCode) {
      try {
        if (command == "PARAMETER") {
          List<dynamic> params = jsonDecode(response);
          for (var param in params) {
            String type = param['description'].toString().split(', ')[0].toLowerCase();
            String value = param['response'].toString();
            if (type.contains('speed')) {
              double newSpeed = double.parse(value);
              _currentSpeed = newSpeed;
              onSpeedChanged?.call(newSpeed);
              _lastUpdateTimes['speed'] = DateTime.now();
              _addLiveResponse('PARSED: Speed = ${newSpeed.toStringAsFixed(1)} km/h');
            } else if (type.contains('rpm')) {
              int newRpm = double.parse(value).round();
              _currentRpm = newRpm;
              onRpmChanged?.call(newRpm);
              _lastUpdateTimes['rpm'] = DateTime.now();
              _addLiveResponse('PARSED: RPM = $newRpm rpm');
            } else if (type.contains('throttle')) {
              int newThrottle = double.parse(value).round();
              _currentThrottle = newThrottle;
              onThrottleChanged?.call(newThrottle);
              _lastUpdateTimes['throttle'] = DateTime.now();
              _addLiveResponse('PARSED: Throttle = $newThrottle%');
            }
          }
        }
      } catch (e) {
        print('Error processing Obd2Plugin response: $e');
        _consecutiveErrors++;
        _checkConnectionHealth();
      }
    }).then((_) {
      _obd2Plugin!.getParamsFromJSON(paramJson, requestCode: 101);
    });
  }

  void _processBufferedResponses() {
    while (_obdBuffer.contains('\r') || _obdBuffer.contains('>')) {
      String response;
      int endIndex;

      int crIndex = _obdBuffer.indexOf('\r');
      int promptIndex = _obdBuffer.indexOf('>');

      if (crIndex != -1 && (promptIndex == -1 || crIndex < promptIndex)) {
        endIndex = crIndex;
      } else if (promptIndex != -1) {
        endIndex = promptIndex;
      } else {
        break;
      }

      response = _obdBuffer.substring(0, endIndex).trim();
      _obdBuffer = _obdBuffer.substring(endIndex + 1);

      if (response.isNotEmpty &&
          !response.startsWith('AT') &&
          !response.contains('ELM327') &&
          !response.contains('SEARCHING')) {
        _addLiveResponse('PARSED: $response');
        _processObdResponse(response);
        _isAwaitingResponse = false;
        _consecutiveErrors = 0;
      }
    }
  }

  void _startContinuousCommands() {
    _obdCommandTimer?.cancel();
    _obdCommandTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (_bluetoothConnection?.isConnected != true) {
        timer.cancel();
        return;
      }

      if (_isAwaitingResponse && _lastCommandSent != null) {
        final timeSinceLastCommand = DateTime.now().difference(_lastCommandSent!);
        if (timeSinceLastCommand.inMilliseconds > 1500) {
          print('Command timeout detected, sending next command');
          _isAwaitingResponse = false;
          _consecutiveErrors++;
        }
      }

      if (!_isAwaitingResponse) {
        _sendNextObdCommand();
      }

      _checkConnectionHealth();
    });
  }

  void _sendNextObdCommand() {
    if (_bluetoothConnection?.isConnected != true) {
      print('Bluetooth not connected, stopping OBD requests');
      return;
    }

    try {
      final currentCommandSet = _obdCommandSets[_currentCommandSetIndex];
      final baseCmd = currentCommandSet[_currentObdCommandIndex];
      final cmd = baseCmd.endsWith('\r') ? baseCmd : baseCmd + '\r';

      print('Sending OBD command: ${cmd.trim()}');
      _addLiveResponse('TX: ${cmd.trim()}');

      _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
      _bluetoothConnection?.output.allSent;
      _lastCommandSent = DateTime.now();
      _isAwaitingResponse = true;
      _currentObdCommandIndex = (_currentObdCommandIndex + 1) % currentCommandSet.length;

      if (_consecutiveErrors > 0) {
        _consecutiveErrors = 0;
      }
    } catch (e) {
      print('Error sending OBD command: $e');
      _consecutiveErrors++;
      _checkConnectionHealth();
    }
  }

  void _checkConnectionHealth() {
    if (_consecutiveErrors >= _maxConsecutiveErrors) {
      print('Too many consecutive errors, trying next command set...');
      _tryNextCommandSet();
      return;
    }

    if (_lastDataReceived != null) {
      final timeSinceLastData = DateTime.now().difference(_lastDataReceived!);
      if (timeSinceLastData.inSeconds > 8) {
        print('Data timeout detected, trying next command set...');
        _tryNextCommandSet();
        return;
      }
    }

    if (_lastDataReceived != null) {
      final timeSinceConnection = DateTime.now().difference(_lastDataReceived!);
      if (timeSinceConnection.inSeconds > 10 && _currentSpeed == 0.0 && _currentRpm == 0) {
        print('No valid data received, trying next command set...');
        _tryNextCommandSet();
      }
    }
  }

  void _tryNextCommandSet() {
    _commandSetRetryCount++;
    if (_commandSetRetryCount >= _maxCommandSetRetries) {
      _currentCommandSetIndex = (_currentCommandSetIndex + 1) % _obdCommandSets.length;
      _commandSetRetryCount = 0;
      print('Switching to command set ${_currentCommandSetIndex}');
      _addLiveResponse('INFO: Switching to command set ${_currentCommandSetIndex}');
    }

    _consecutiveErrors = 0;
    _currentObdCommandIndex = 0;
    _isAwaitingResponse = false;

    if (_currentCommandSetIndex >= _obdCommandSets.length - 1 && _commandSetRetryCount >= _maxCommandSetRetries) {
      _showErrorPopup('Unable to communicate with OBD device. All command formats failed.');
      _handleConnectionError('All OBD command formats failed');
    }
  }

  void _processObdResponse(String response) {
    response = response.replaceAll(RegExp(r'[\r\n\s>]+'), ' ').trim();

    if (response.isEmpty ||
        response == '>' ||
        response.contains('SEARCHING') ||
        response.contains('UNABLE TO CONNECT') ||
        response.contains('NO DATA') ||
        response.contains('ELM327') ||
        response.contains('OK') ||
        response.length < 6) {
      return;
    }

    print('Processing OBD response: "$response"');

    try {
      _parseObdResponseMethod1(response) ||
          _parseObdResponseMethod2(response) ||
          _parseObdResponseMethod3(response);
    } catch (e) {
      print('Error parsing OBD response "$response": $e');
      _consecutiveErrors++;
    }
  }

  bool _parseObdResponseMethod1(String response) {
    try {
      String cleanResponse = response.replaceAll(' ', '').toUpperCase();
      if (cleanResponse.startsWith('41')) {
        String pid = cleanResponse.substring(2, 4);
        String data = cleanResponse.substring(4);
        return _processObdPid(pid, data);
      }
    } catch (e) {
      print('Method 1 parsing error: $e');
    }
    return false;
  }

  bool _parseObdResponseMethod2(String response) {
    try {
      List<String> parts = response.split(' ');
      if (parts.length >= 3 && parts[0] == '41') {
        String pid = parts[1];
        String data = parts.sublist(2).join('');
        return _processObdPid(pid, data);
      }
    } catch (e) {
      print('Method 2 parsing error: $e');
    }
    return false;
  }

  bool _parseObdResponseMethod3(String response) {
    try {
      RegExp regex = RegExp(r'41\s*([0-9A-F]{2})\s*([0-9A-F\s]+)', caseSensitive: false);
      Match? match = regex.firstMatch(response);
      if (match != null) {
        String pid = match.group(1)!;
        String data = match.group(2)!.replaceAll(' ', '');
        return _processObdPid(pid, data);
      }
    } catch (e) {
      print('Method 3 parsing error: $e');
    }
    return false;
  }

  bool _processObdPid(String pid, String data) {
    switch (pid.toUpperCase()) {
      case '0D': // Speed
        if (data.length >= 2) {
          int speedValue = int.parse(data.substring(0, 2), radix: 16);
          double newSpeed = speedValue.toDouble();
          _currentSpeed = newSpeed;
          onSpeedChanged?.call(newSpeed);
          _lastUpdateTimes['speed'] = DateTime.now();
          print('Updated Speed: ${newSpeed.toStringAsFixed(1)} km/h');
          return true;
        }
        break;

      case '0C': // RPM
        if (data.length >= 4) {
          int rpmHigh = int.parse(data.substring(0, 2), radix: 16);
          int rpmLow = int.parse(data.substring(2, 4), radix: 16);
          int newRpm = ((rpmHigh * 256 + rpmLow) / 4).round();
          _currentRpm = newRpm;
          onRpmChanged?.call(newRpm);
          _lastUpdateTimes['rpm'] = DateTime.now();
          print('Updated RPM: $newRpm rpm');
          return true;
        }
        break;

      case '11': // Throttle Position
        if (data.length >= 2) {
          int throttleValue = int.parse(data.substring(0, 2), radix: 16);
          int newThrottle = ((throttleValue * 100) / 255).round();
          _currentThrottle = newThrottle;
          onThrottleChanged?.call(newThrottle);
          _lastUpdateTimes['throttle'] = DateTime.now();
          print('Updated Throttle: $newThrottle%');
          return true;
        }
        break;

      case '05': // Engine Coolant Temperature
        if (data.length >= 2) {
          int temp = int.parse(data.substring(0, 2), radix: 16) - 40;
          print('Engine Coolant Temperature: ${temp}°C');
          return true;
        }
        break;

      case '0A': // Fuel Rail Pressure
        if (data.length >= 2) {
          int pressure = int.parse(data.substring(0, 2), radix: 16) * 3;
          print('Fuel Rail Pressure: ${pressure} kPa');
          return true;
        }
        break;

      case '0B': // Intake Manifold Pressure
        if (data.length >= 2) {
          int pressure = int.parse(data.substring(0, 2), radix: 16);
          print('Intake Manifold Pressure: ${pressure} kPa');
          return true;
        }
        break;
    }
    return false;
  }

  Future<void> disconnectOBD() async {
    try {
      _obdSubscription?.cancel();
      _obdCommandTimer?.cancel();
      if (_connectionMode == ConnectionMode.obd2Plugin) {
        await _obd2Plugin?.disconnect();
      } else if (_bluetoothConnection?.isConnected == true) {
        await _bluetoothConnection?.close();
      }
      _bluetoothConnection?.dispose();
      _bluetoothConnection = null;
      _obd2Plugin = null;
      _setStatus('Disconnected');
      _resetOBDData();
      _liveResponses.clear();
      print('OBD disconnected successfully');
    } catch (e) {
      print('Error disconnecting OBD: $e');
      _setError('Error disconnecting OBD: $e');
    }
  }

  void _handleConnectionError(String error) {
    _setStatus('Failed');
    _setError(error);
    _obdSubscription?.cancel();
    _obdCommandTimer?.cancel();
    _bluetoothConnection?.dispose();
    _bluetoothConnection = null;
    _obd2Plugin = null;
    _resetOBDData();
    _liveResponses.clear();
    print('Connection error handled: $error');
  }

  void _resetOBDData() {
    _currentSpeed = 0.0;
    _currentRpm = 0;
    _currentThrottle = 0;
    onSpeedChanged?.call(0.0);
    onRpmChanged?.call(0);
    onThrottleChanged?.call(0);
  }

  void _setStatus(String status) {
    _bluetoothStatus = status;
    onStatusChanged?.call(status);
  }

  void _setError(String error) {
    onError?.call(error);
  }

  void _clearError() {
    onError?.call('');
  }

  Map<String, DateTime> get lastUpdateTimes => _lastUpdateTimes;

  void dispose() {
    _obdSubscription?.cancel();
    _obdCommandTimer?.cancel();
    _bluetoothConnection?.dispose();
    _obd2Plugin?.disconnect();
    _obd2Plugin = null;
  }
}


// import 'dart:async';
// import 'dart:typed_data';
// import 'package:flutter/material.dart';
// import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
//
// class OBDService {
//   final FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
//   BluetoothConnection? _bluetoothConnection;
//   StreamSubscription? _obdSubscription;
//   Timer? _obdCommandTimer;
//   String _bluetoothStatus = 'Disconnected';
//   bool _isConnecting = false;
//   bool _isAwaitingResponse = false;
//   DateTime? _lastCommandSent;
//   DateTime? _lastDataReceived;
//   int _consecutiveErrors = 0;
//   final int _maxConsecutiveErrors = 5;
//   String _obdBuffer = '';
//   Map<String, DateTime> _lastUpdateTimes = {};
//   List<String> _liveResponses = [];
//   BuildContext? _context;
//
//   // Enhanced OBD command cycling with fallbacks
//   final List<List<String>> _obdCommandSets = [
//     ['010D', '010C', '0111'], // Primary set
//     ['01 0D', '01 0C', '01 11'], // With spaces
//     ['010D\r', '010C\r', '0111\r'], // With carriage return
//     ['010D\r\n', '010C\r\n', '0111\r\n'], // With CRLF
//   ];
//   int _currentCommandSetIndex = 0;
//   int _currentObdCommandIndex = 0;
//   int _commandSetRetryCount = 0;
//   final int _maxCommandSetRetries = 3;
//
//   // Comprehensive OBD command mapping
//   final Map<String, Map<String, dynamic>> _obdCommandMap = {
//     '01 0D': {'name': 'speed', 'description': 'Vehicle Speed'},
//     '01 0C': {'name': 'rpm', 'description': 'Engine RPM'},
//     '01 11': {'name': 'throttle', 'description': 'Throttle Position'},
//     '01 05': {'name': 'coolant_temp', 'description': 'Engine Coolant Temperature'},
//     '01 0A': {'name': 'fuel_pressure', 'description': 'Fuel Rail Pressure'},
//     '01 0B': {'name': 'intake_pressure', 'description': 'Intake Manifold Pressure'},
//     '01 0F': {'name': 'intake_temp', 'description': 'Intake Air Temperature'},
//     '01 10': {'name': 'maf', 'description': 'Mass Air Flow Rate'},
//     '01 42': {'name': 'control_voltage', 'description': 'Control Module Voltage'},
//     '01 46': {'name': 'ambient_temp', 'description': 'Ambient Air Temperature'},
//   };
//
//   // Callbacks for updating UI
//   Function(String)? onStatusChanged;
//   Function(String)? onError;
//   Function(double)? onSpeedChanged;
//   Function(int)? onRpmChanged;
//   Function(int)? onThrottleChanged;
//   Function(List<String>)? onLiveResponsesChanged;
//
//   String get bluetoothStatus => _bluetoothStatus;
//   List<String> get liveResponses => _liveResponses;
//
//   void setContext(BuildContext context) {
//     _context = context;
//   }
//
//   Future<void> startOBDPairing(String? macAddress) async {
//     if (_isConnecting || _bluetoothConnection?.isConnected == true) {
//       print('Bluetooth already connecting or connected');
//       return;
//     }
//
//     if (macAddress == null || macAddress == 'Unknown' || macAddress.isEmpty) {
//       _showErrorPopup('No valid Bluetooth MAC address provided');
//       _setStatus('Failed');
//       _resetOBDData();
//       return;
//     }
//
//     _setStatus('Connecting');
//     _isConnecting = true;
//     _clearError();
//
//     try {
//       if (!(await _bluetooth.isEnabled ?? false)) {
//         await _bluetooth.requestEnable();
//         await Future.delayed(const Duration(seconds: 2));
//       }
//
//       print('Connecting to OBD device: $macAddress');
//       _bluetoothConnection = await BluetoothConnection.toAddress(macAddress).timeout(
//         const Duration(seconds: 15),
//         onTimeout: () => throw Exception('Connection timed out'),
//       );
//
//       _setStatus('Connected');
//       _isConnecting = false;
//       print('Bluetooth connected to $macAddress');
//
//       // Show success popup
//       _showSuccessPopup();
//
//       _obdSubscription?.cancel();
//       _obdCommandTimer?.cancel();
//
//       await _initializeOBD();
//       _listenForOBDData();
//     } catch (e) {
//       print('Bluetooth connection error: $e');
//       _showErrorPopup('Failed to connect to OBD device: ${e.toString()}');
//       _handleConnectionError('Failed to connect to OBD device: $e');
//     }
//   }
//
//   void _showSuccessPopup() {
//     if (_context != null) {
//       showDialog(
//         context: _context!,
//         barrierDismissible: false,
//         builder: (BuildContext context) {
//           return StatefulBuilder(
//             builder: (context, setState) {
//               return AlertDialog(
//                 title: Row(
//                   children: [
//                     Icon(Icons.check_circle, color: Colors.green, size: 24),
//                     SizedBox(width: 8),
//                     Text('OBD Connected Successfully', style: TextStyle(fontSize: 16)),
//                   ],
//                 ),
//                 content: Container(
//                   width: double.maxFinite,
//                   height: 400,
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text('Live OBD Responses:',
//                           style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
//                       SizedBox(height: 8),
//                       Expanded(
//                         flex: 2,
//                         child: Container(
//                           padding: EdgeInsets.all(8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.grey),
//                             borderRadius: BorderRadius.circular(4),
//                             color: Colors.black87,
//                           ),
//                           child: StreamBuilder<List<String>>(
//                             stream: Stream.periodic(Duration(milliseconds: 100), (_) => _liveResponses),
//                             builder: (context, snapshot) {
//                               return ListView.builder(
//                                 reverse: true,
//                                 itemCount: _liveResponses.length,
//                                 itemBuilder: (context, index) {
//                                   final reverseIndex = _liveResponses.length - 1 - index;
//                                   return Padding(
//                                     padding: EdgeInsets.symmetric(vertical: 1),
//                                     child: Text(
//                                       _liveResponses[reverseIndex],
//                                       style: TextStyle(
//                                         fontFamily: 'monospace',
//                                         fontSize: 11,
//                                         color: Colors.greenAccent,
//                                       ),
//                                     ),
//                                   );
//                                 },
//                               );
//                             },
//                           ),
//                         ),
//                       ),
//                       SizedBox(height: 12),
//                       Text('Parsed Data:',
//                           style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
//                       SizedBox(height: 8),
//                       Expanded(
//                         flex: 1,
//                         child: Container(
//                           padding: EdgeInsets.all(8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.grey),
//                             borderRadius: BorderRadius.circular(4),
//                             color: Colors.blue.shade50,
//                           ),
//                           child: StreamBuilder<Map<String, dynamic>>(
//                             stream: Stream.periodic(Duration(milliseconds: 500), (_) => _getCurrentValues()),
//                             builder: (context, snapshot) {
//                               final values = snapshot.data ?? {};
//                               return Column(
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   _buildDataRow('Speed', '${values['speed']?.toStringAsFixed(1) ?? '0.0'} km/h'),
//                                   _buildDataRow('RPM', '${values['rpm'] ?? 0} rpm'),
//                                   _buildDataRow('Throttle', '${values['throttle'] ?? 0}%'),
//                                 ],
//                               );
//                             },
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 actions: [
//                   TextButton(
//                     onPressed: () => Navigator.of(context).pop(),
//                     child: Text('Close'),
//                   ),
//                 ],
//               );
//             },
//           );
//         },
//       );
//     }
//   }
//
//   Widget _buildDataRow(String label, String value) {
//     return Padding(
//       padding: EdgeInsets.symmetric(vertical: 2),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
//           Text(value, style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
//         ],
//       ),
//     );
//   }
//
//   Map<String, dynamic> _getCurrentValues() {
//     return {
//       'speed': _currentSpeed,
//       'rpm': _currentRpm,
//       'throttle': _currentThrottle,
//     };
//   }
//
//   double _currentSpeed = 0.0;
//   int _currentRpm = 0;
//   int _currentThrottle = 0;
//
//   void _showErrorPopup(String error) {
//     if (_context != null) {
//       showDialog(
//         context: _context!,
//         builder: (BuildContext context) {
//           return AlertDialog(
//             title: Row(
//               children: [
//                 Icon(Icons.error, color: Colors.red, size: 24),
//                 SizedBox(width: 8),
//                 Text('Connection Error', style: TextStyle(fontSize: 16)),
//               ],
//             ),
//             content: Text(error),
//             actions: [
//               TextButton(
//                 onPressed: () => Navigator.of(context).pop(),
//                 child: Text('OK'),
//               ),
//             ],
//           );
//         },
//       );
//     }
//   }
//
//   Future<void> _initializeOBD() async {
//     try {
//       final initCommands = [
//         'ATZ\r',      // Reset
//         'ATE0\r',     // Echo off
//         'ATL0\r',     // Line feeds off
//         'ATS0\r',     // Spaces off
//         'ATH1\r',     // Headers on
//         'ATSP0\r',    // Set protocol auto
//         'ATAT2\r',    // Adaptive timing auto
//         '0100\r',     // Test connectivity
//       ];
//
//       for (var cmd in initCommands) {
//         print('Sending init command: ${cmd.trim()}');
//         _addLiveResponse('TX: ${cmd.trim()}');
//         _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
//         await _bluetoothConnection?.output.allSent;
//         await Future.delayed(const Duration(milliseconds: 800));
//       }
//
//       print('OBD initialized successfully');
//       await Future.delayed(const Duration(milliseconds: 1000));
//     } catch (e) {
//       print('OBD initialization error: $e');
//       _showErrorPopup('Failed to initialize OBD: ${e.toString()}');
//       _handleConnectionError('Failed to initialize OBD: $e');
//     }
//   }
//
//   void _addLiveResponse(String response) {
//     _liveResponses.add('${DateTime.now().millisecondsSinceEpoch % 100000}: $response');
//     if (_liveResponses.length > 50) {
//       _liveResponses.removeAt(0);
//     }
//     onLiveResponsesChanged?.call(_liveResponses);
//   }
//
//   void _listenForOBDData() {
//     _obdSubscription?.cancel();
//     _obdCommandTimer?.cancel();
//     _obdBuffer = '';
//     _currentObdCommandIndex = 0;
//     _isAwaitingResponse = false;
//     _consecutiveErrors = 0;
//     _liveResponses.clear();
//
//     _obdSubscription = _bluetoothConnection?.input?.listen(
//           (data) {
//         try {
//           final chunk = String.fromCharCodes(data);
//           _obdBuffer += chunk;
//           _lastDataReceived = DateTime.now();
//
//           // Add to live responses
//           if (chunk.trim().isNotEmpty) {
//             _addLiveResponse('RX: ${chunk.replaceAll('\r', '\\r').replaceAll('\n', '\\n')}');
//           }
//
//           _processBufferedResponses();
//         } catch (e) {
//           print('Error processing OBD data: $e');
//           _consecutiveErrors++;
//           _checkConnectionHealth();
//         }
//       },
//       onError: (e) {
//         print('Bluetooth stream error: $e');
//         _showErrorPopup('Bluetooth stream error: ${e.toString()}');
//         _handleConnectionError('Bluetooth stream error: $e');
//       },
//       onDone: () {
//         print('Bluetooth connection closed');
//         _showErrorPopup('Bluetooth connection was closed unexpectedly');
//         _handleConnectionError('Connection closed');
//       },
//       cancelOnError: false,
//     );
//
//     _startContinuousCommands();
//   }
//
//   void _processBufferedResponses() {
//     while (_obdBuffer.contains('\r') || _obdBuffer.contains('>')) {
//       String response;
//       int endIndex;
//
//       int crIndex = _obdBuffer.indexOf('\r');
//       int promptIndex = _obdBuffer.indexOf('>');
//
//       if (crIndex != -1 && (promptIndex == -1 || crIndex < promptIndex)) {
//         endIndex = crIndex;
//       } else if (promptIndex != -1) {
//         endIndex = promptIndex;
//       } else {
//         break;
//       }
//
//       response = _obdBuffer.substring(0, endIndex).trim();
//       _obdBuffer = _obdBuffer.substring(endIndex + 1);
//
//       if (response.isNotEmpty &&
//           !response.startsWith('AT') &&
//           !response.contains('ELM327') &&
//           !response.contains('SEARCHING')) {
//         _addLiveResponse('PARSED: $response');
//         _processObdResponse(response);
//         _isAwaitingResponse = false;
//         _consecutiveErrors = 0;
//       }
//     }
//   }
//
//   void _startContinuousCommands() {
//     _obdCommandTimer?.cancel();
//     _obdCommandTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
//       if (_bluetoothConnection?.isConnected != true) {
//         timer.cancel();
//         return;
//       }
//
//       if (_isAwaitingResponse && _lastCommandSent != null) {
//         final timeSinceLastCommand = DateTime.now().difference(_lastCommandSent!);
//         if (timeSinceLastCommand.inMilliseconds > 1500) {
//           print('Command timeout detected, sending next command');
//           _isAwaitingResponse = false;
//           _consecutiveErrors++;
//         }
//       }
//
//       if (!_isAwaitingResponse) {
//         _sendNextObdCommand();
//       }
//
//       _checkConnectionHealth();
//     });
//   }
//
//   void _sendNextObdCommand() {
//     if (_bluetoothConnection?.isConnected != true) {
//       print('Bluetooth not connected, stopping OBD requests');
//       return;
//     }
//
//     try {
//       final currentCommandSet = _obdCommandSets[_currentCommandSetIndex];
//       final baseCmd = currentCommandSet[_currentObdCommandIndex];
//       final cmd = baseCmd.endsWith('\r') ? baseCmd : baseCmd + '\r';
//
//       print('Sending OBD command: ${cmd.trim()}');
//       _addLiveResponse('TX: ${cmd.trim()}');
//
//       _bluetoothConnection?.output.add(Uint8List.fromList(cmd.codeUnits));
//       _bluetoothConnection?.output.allSent;
//       _lastCommandSent = DateTime.now();
//       _isAwaitingResponse = true;
//       _currentObdCommandIndex = (_currentObdCommandIndex + 1) % currentCommandSet.length;
//
//       // Reset consecutive errors on successful send
//       if (_consecutiveErrors > 0) {
//         _consecutiveErrors = 0;
//       }
//     } catch (e) {
//       print('Error sending OBD command: $e');
//       _consecutiveErrors++;
//       _checkConnectionHealth();
//     }
//   }
//
//   void _checkConnectionHealth() {
//     if (_consecutiveErrors >= _maxConsecutiveErrors) {
//       print('Too many consecutive errors, trying next command set...');
//       _tryNextCommandSet();
//       return;
//     }
//
//     if (_lastDataReceived != null) {
//       final timeSinceLastData = DateTime.now().difference(_lastDataReceived!);
//       if (timeSinceLastData.inSeconds > 8) {
//         print('Data timeout detected, trying next command set...');
//         _tryNextCommandSet();
//         return;
//       }
//     }
//
//     // Check if we're not getting speed/rpm data
//     if (_lastDataReceived != null) {
//       final timeSinceConnection = DateTime.now().difference(_lastDataReceived!);
//       if (timeSinceConnection.inSeconds > 10 && _currentSpeed == 0.0 && _currentRpm == 0) {
//         print('No valid data received, trying next command set...');
//         _tryNextCommandSet();
//       }
//     }
//   }
//
//   void _tryNextCommandSet() {
//     _commandSetRetryCount++;
//     if (_commandSetRetryCount >= _maxCommandSetRetries) {
//       _currentCommandSetIndex = (_currentCommandSetIndex + 1) % _obdCommandSets.length;
//       _commandSetRetryCount = 0;
//       print('Switching to command set ${_currentCommandSetIndex}');
//       _addLiveResponse('INFO: Switching to command set ${_currentCommandSetIndex}');
//     }
//
//     _consecutiveErrors = 0;
//     _currentObdCommandIndex = 0;
//     _isAwaitingResponse = false;
//
//     if (_currentCommandSetIndex >= _obdCommandSets.length - 1 && _commandSetRetryCount >= _maxCommandSetRetries) {
//       _showErrorPopup('Unable to communicate with OBD device. All command formats failed.');
//       _handleConnectionError('All OBD command formats failed');
//     }
//   }
//
//   void _processObdResponse(String response) {
//     response = response.replaceAll(RegExp(r'[\r\n\s>]+'), ' ').trim();
//
//     if (response.isEmpty ||
//         response == '>' ||
//         response.contains('SEARCHING') ||
//         response.contains('UNABLE TO CONNECT') ||
//         response.contains('NO DATA') ||
//         response.contains('ELM327') ||
//         response.contains('OK') ||
//         response.length < 6) {
//       return;
//     }
//
//     print('Processing OBD response: "$response"');
//
//     try {
//       // Try multiple parsing methods
//       _parseObdResponseMethod1(response) ||
//           _parseObdResponseMethod2(response) ||
//           _parseObdResponseMethod3(response);
//     } catch (e) {
//       print('Error parsing OBD response "$response": $e');
//       _consecutiveErrors++;
//     }
//   }
//
//   bool _parseObdResponseMethod1(String response) {
//     try {
//       String cleanResponse = response.replaceAll(' ', '').toUpperCase();
//       if (cleanResponse.startsWith('41')) {
//         String pid = cleanResponse.substring(2, 4);
//         String data = cleanResponse.substring(4);
//         return _processObdPid(pid, data);
//       }
//     } catch (e) {
//       print('Method 1 parsing error: $e');
//     }
//     return false;
//   }
//
//   bool _parseObdResponseMethod2(String response) {
//     try {
//       List<String> parts = response.split(' ');
//       if (parts.length >= 3 && parts[0] == '41') {
//         String pid = parts[1];
//         String data = parts.sublist(2).join('');
//         return _processObdPid(pid, data);
//       }
//     } catch (e) {
//       print('Method 2 parsing error: $e');
//     }
//     return false;
//   }
//
//   bool _parseObdResponseMethod3(String response) {
//     try {
//       RegExp regex = RegExp(r'41\s*([0-9A-F]{2})\s*([0-9A-F\s]+)', caseSensitive: false);
//       Match? match = regex.firstMatch(response);
//       if (match != null) {
//         String pid = match.group(1)!;
//         String data = match.group(2)!.replaceAll(' ', '');
//         return _processObdPid(pid, data);
//       }
//     } catch (e) {
//       print('Method 3 parsing error: $e');
//     }
//     return false;
//   }
//
//   bool _processObdPid(String pid, String data) {
//     switch (pid.toUpperCase()) {
//       case '0D': // Speed
//         if (data.length >= 2) {
//           int speedValue = int.parse(data.substring(0, 2), radix: 16);
//           double newSpeed = speedValue.toDouble();
//           _currentSpeed = newSpeed;
//           onSpeedChanged?.call(newSpeed);
//           _lastUpdateTimes['speed'] = DateTime.now();
//           print('Updated Speed: ${newSpeed.toStringAsFixed(1)} km/h');
//           return true;
//         }
//         break;
//
//       case '0C': // RPM
//         if (data.length >= 4) {
//           int rpmHigh = int.parse(data.substring(0, 2), radix: 16);
//           int rpmLow = int.parse(data.substring(2, 4), radix: 16);
//           int newRpm = ((rpmHigh * 256 + rpmLow) / 4).round();
//           _currentRpm = newRpm;
//           onRpmChanged?.call(newRpm);
//           _lastUpdateTimes['rpm'] = DateTime.now();
//           print('Updated RPM: $newRpm rpm');
//           return true;
//         }
//         break;
//
//       case '11': // Throttle Position
//         if (data.length >= 2) {
//           int throttleValue = int.parse(data.substring(0, 2), radix: 16);
//           int newThrottle = ((throttleValue * 100) / 255).round();
//           _currentThrottle = newThrottle;
//           onThrottleChanged?.call(newThrottle);
//           _lastUpdateTimes['throttle'] = DateTime.now();
//           print('Updated Throttle: $newThrottle%');
//           return true;
//         }
//         break;
//
//     // Additional OBD PIDs for comprehensive support
//       case '05': // Engine Coolant Temperature
//         if (data.length >= 2) {
//           int temp = int.parse(data.substring(0, 2), radix: 16) - 40;
//           print('Engine Coolant Temperature: ${temp}°C');
//           return true;
//         }
//         break;
//
//       case '0A': // Fuel Rail Pressure
//         if (data.length >= 2) {
//           int pressure = int.parse(data.substring(0, 2), radix: 16) * 3;
//           print('Fuel Rail Pressure: ${pressure} kPa');
//           return true;
//         }
//         break;
//
//       case '0B': // Intake Manifold Pressure
//         if (data.length >= 2) {
//           int pressure = int.parse(data.substring(0, 2), radix: 16);
//           print('Intake Manifold Pressure: ${pressure} kPa');
//           return true;
//         }
//         break;
//     }
//     return false;
//   }
//
//   Future<void> disconnectOBD() async {
//     try {
//       _obdSubscription?.cancel();
//       _obdCommandTimer?.cancel();
//       if (_bluetoothConnection?.isConnected == true) {
//         await _bluetoothConnection?.close();
//       }
//       _bluetoothConnection?.dispose();
//       _bluetoothConnection = null;
//       _setStatus('Disconnected');
//       _resetOBDData();
//       _liveResponses.clear();
//       print('OBD disconnected successfully');
//     } catch (e) {
//       print('Error disconnecting OBD: $e');
//       _setError('Error disconnecting OBD: $e');
//     }
//   }
//
//   void _handleConnectionError(String error) {
//     _setStatus('Failed');
//     _setError(error);
//     _obdSubscription?.cancel();
//     _obdCommandTimer?.cancel();
//     _bluetoothConnection?.dispose();
//     _bluetoothConnection = null;
//     _resetOBDData();
//     _liveResponses.clear();
//
//     // Don't auto-reconnect to avoid infinite loops
//     print('Connection error handled: $error');
//   }
//
//   void _resetOBDData() {
//     _currentSpeed = 0.0;
//     _currentRpm = 0;
//     _currentThrottle = 0;
//     onSpeedChanged?.call(0.0);
//     onRpmChanged?.call(0);
//     onThrottleChanged?.call(0);
//   }
//
//   void _setStatus(String status) {
//     _bluetoothStatus = status;
//     onStatusChanged?.call(status);
//   }
//
//   void _setError(String error) {
//     onError?.call(error);
//   }
//
//   void _clearError() {
//     onError?.call('');
//   }
//
//   Map<String, DateTime> get lastUpdateTimes => _lastUpdateTimes;
//
//   void dispose() {
//     _obdSubscription?.cancel();
//     _obdCommandTimer?.cancel();
//     _bluetoothConnection?.dispose();
//   }
// }