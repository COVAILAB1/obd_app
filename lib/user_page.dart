import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'real_time_object_detection.dart';

class UserPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const UserPage({Key? key, required this.cameras}) : super(key: key);

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  Map<String, dynamic>? _userDetails;
  String _userId = "";
  String _errorMessage = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)!.settings.arguments;
      if (args is Map<String, dynamic> && args.containsKey('userId')) {
        _userId = args['userId'].toString();
        print('User ID from arguments: $_userId');
      } else {
        _showErrorPopup('Invalid user ID provided');
        _setDefaultUserDetails();
      }
      _fetchUserDetails();
    });
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
                _isLoading = false;
                print('Updated _userDetails: $_userDetails');
              });
            }
          } else {
            if (mounted) {
              _showErrorPopup('Failed to fetch user details: ${data['error']}');
              _setDefaultUserDetails();
            }
          }
        } catch (e) {
          if (mounted) {
            _showErrorPopup('Invalid response format: $e');
            _setDefaultUserDetails();
          }
        }
      } else {
        if (mounted) {
          _showErrorPopup('Server error: ${response.statusCode}');
          _setDefaultUserDetails();
        }
      }
    } catch (e) {
      print('Fetch user details error: $e');
      if (mounted) {
        _showErrorPopup('Failed to connect to server: $e');
        _setDefaultUserDetails();
      }
    }
  }

  void _setDefaultUserDetails() {
    setState(() {
      _userDetails = {
        'full_name': 'Unknown User',
        'score': '0',
        'car_name': 'Unknown',
        'car_number': 'Unknown',
        'obd_name': 'Unknown',
        'bluetooth_mac': 'Unknown'
      };
      _isLoading = false;
    });
  }

  void _showErrorPopup(String message) {
    if (mounted) {
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
            content: Text(message),
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

  String _formatMacAddress(String? mac) {
    if (mac == null || mac == 'Unknown' || mac.isEmpty) return 'N/A';
    if (mac.length < 10) return mac;
    return '${mac.substring(0, 6)}...${mac.substring(mac.length - 4)}';
  }

  Widget _buildProfileRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('User Profile'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[300],
                  child: Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              SizedBox(height: 16),
              Center(
                child: Text(
                  _userDetails?['full_name'] ?? 'Unknown User',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              SizedBox(height: 24),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildProfileRow('Score', _userDetails?['score'].toString() ?? 'N/A', Icons.star),
                      _buildProfileRow('Car Name', _userDetails?['car_name'] ?? 'N/A', Icons.directions_car),
                      _buildProfileRow('Car Number', _userDetails?['car_number'] ?? 'N/A', Icons.numbers),
                      _buildProfileRow('OBD Device', _userDetails?['obd_name'] ?? 'N/A', Icons.device_hub),
                      _buildProfileRow('Bluetooth MAC', _formatMacAddress(_userDetails?['bluetooth_mac']), Icons.bluetooth),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 32),
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.drive_eta),
                  label: Text('Start Drive'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RealTimeObjectDetection(cameras: widget.cameras),
                        settings: RouteSettings(arguments: {'userId': _userId}),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}