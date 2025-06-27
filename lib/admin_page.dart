import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:intl/intl.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({Key? key}) : super(key: key);

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<dynamic> users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('https://adas-backend.onrender.com/api/get_users'),
      );
      final data = jsonDecode(response.body);

      if (data['success']) {
        setState(() {
          users = data['users'];
          print(users);
          _isLoading = false;
        });
      } else {
        _showErrorSnackBar('Failed to fetch users: ${data['error']}');
      }
    } catch (e) {
      _showErrorSnackBar('Error fetching users: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addUser(Map<String, String> userData) async {
    try {
      final response = await http.post(
        Uri.parse('https://adas-backend.onrender.com/api/add_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        _fetchUsers();
        _showSuccessSnackBar('User added successfully');
      } else {
        _showErrorSnackBar('Failed to add user: ${data['error']}');
      }
    } catch (e) {
      _showErrorSnackBar('Error adding user: $e');
    }
  }

  Future<void> _updateUser(Map<String, dynamic> userData) async {
    try {
      final response = await http.put(
        Uri.parse('https://adas-backend.onrender.com/api/update_user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      );
      final data = jsonDecode(response.body);
      if (data['success']) {
        _fetchUsers();
        _showSuccessSnackBar('User updated successfully');
      } else {
        _showErrorSnackBar('Failed to update user: ${data['error']}');
      }
    } catch (e) {
      _showErrorSnackBar('Error updating user: $e');
    }
  }
  void _showAddUserDialog() {
    final controllers = {
      'username': TextEditingController(),
      'password': TextEditingController(),
      'role': TextEditingController(text: 'user'),
      'full_name': TextEditingController(),
      'email': TextEditingController(),
      'car_name': TextEditingController(),
      'car_number': TextEditingController(),
      'obd_name': TextEditingController(),
      'bluetooth_mac': TextEditingController(),
    };

    showDialog(
      context: context,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final screenHeight = MediaQuery.of(context).size.height;
            final availableHeight = screenHeight - keyboardHeight - 100; // 100 for padding and safe area

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: BoxConstraints(
                  maxHeight: availableHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header - Fixed
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.person_add, color: Colors.blue.shade600),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Add New User',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    // Form fields - Flexible and scrollable
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SingleChildScrollView(
                          child: Column(
                            children: controllers.entries.map((e) =>
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextFormField(
                                    controller: e.value,
                                    obscureText: e.key == 'password',
                                    decoration: InputDecoration(
                                      labelText: e.key.replaceAll('_', ' ').toUpperCase(),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                  ),
                                ),
                            ).toList(),
                          ),
                        ),
                      ),
                    ),

                    // Buttons - Fixed at bottom
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              _addUser({for (var e in controllers.entries) e.key: e.value.text});
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Add User'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final controllers = {
      'username': TextEditingController(text: user['username']),
      'full_name': TextEditingController(text: user['full_name']),
      'email': TextEditingController(text: user['email']),
      'car_name': TextEditingController(text: user['car_name'] ?? ''),
      'car_number': TextEditingController(text: user['car_number'] ?? ''),
      'obd_name': TextEditingController(text: user['obd_name'] ?? ''),
      'bluetooth_mac': TextEditingController(text: user['bluetooth_mac'] ?? ''),
    };

    showDialog(
      context: context,
      builder: (context) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
            final screenHeight = MediaQuery.of(context).size.height;
            final availableHeight = screenHeight - keyboardHeight - 100; // 100 for padding and safe area

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                constraints: BoxConstraints(
                  maxHeight: availableHeight,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header - Fixed
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.edit, color: Colors.orange.shade600),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Edit User',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    // Form fields - Flexible and scrollable
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SingleChildScrollView(
                          child: Column(
                            children: controllers.entries.map((e) =>
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: TextFormField(
                                    controller: e.value,
                                    decoration: InputDecoration(
                                      labelText: e.key.replaceAll('_', ' ').toUpperCase(),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                    ),
                                  ),
                                ),
                            ).toList(),
                          ),
                        ),
                      ),
                    ),

                    // Buttons - Fixed at bottom
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () {
                              _updateUser({
                                'id': user['_id'],
                                ...{for (var e in controllers.entries) e.key: e.value.text},
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Update'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
  Color _getScoreColor(dynamic score) {
    final scoreValue = double.tryParse(score.toString()) ?? 0.0;
    if (scoreValue >= 80) return Colors.green;
    if (scoreValue >= 60) return Colors.orange;
    return Colors.red;
  }

  IconData _getScoreIcon(dynamic score) {
    final scoreValue = double.tryParse(score.toString()) ?? 0.0;
    if (scoreValue >= 80) return Icons.trending_up;
    if (scoreValue >= 60) return Icons.trending_flat;
    return Icons.trending_down;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey.shade200,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading users...'),
          ],
        ),
      )
          : users.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add your first user to get started',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.people,
                      color: Colors.blue.shade600,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Users',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${users.length}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Users',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: _showAddUserDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add User'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: Text(
                          user['full_name']?.substring(0, 1).toUpperCase() ?? 'U',
                          style: TextStyle(
                            color: Colors.blue.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        user['full_name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '@${user['username']}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getScoreColor(user['score']).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _getScoreIcon(user['score']),
                                      size: 14,
                                      color: _getScoreColor(user['score']),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Score: ${user['score']}',
                                      style: TextStyle(
                                        color: _getScoreColor(user['score']),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (user['car_name'] != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.directions_car,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          user['car_name'],
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditUserDialog(user),
                            tooltip: 'Edit User',
                          ),
                          IconButton(
                            icon: const Icon(Icons.analytics_outlined),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserDetailsPage(
                                    userId: user['_id'],
                                    userName: user['full_name'] ?? user['username'],
                                  ),
                                ),
                              );
                            },
                            tooltip: 'View Details',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }
}

class UserDetailsPage extends StatefulWidget {
  final String userId;
  final String userName;

  const UserDetailsPage({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  _UserDetailsPageState createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? userData;
  DateTime? selectedDate;
  bool _isLoading = true;
  late TabController _tabController;
  Timer? _refreshTimer; // Add this line
  MapController mapController = MapController();
  bool _isLegendVisible = true; // New state variable for legend visibility

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchUserDetails(showLoading: true);
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (mounted) {
        _fetchUserDetails(showLoading: false); // Don't show loading for auto-refresh
      }
    });
  }
  Map<String, double> _calculateSpeedStats(List<dynamic> locations) {
    double maxSpeed = 0.0;
    double totalSpeed = 0.0;
    int speedCount = 0;

    for (var location in locations) {
      final path = location['traveled_path'] as List<dynamic>? ?? [];
      for (var point in path) {
        final speed = (point['speed'] as num?)?.toDouble() ?? 0.0;
        if (speed > maxSpeed) maxSpeed = speed;
        if (speed > 0) {
          totalSpeed += speed;
          speedCount++;
        }
      }
    }

    final averageSpeed = speedCount > 0 ? totalSpeed / speedCount : 0.0;
    return {
      'maxSpeed': maxSpeed.roundToDouble(), // Round to nearest integer
      'averageSpeed': averageSpeed.roundToDouble(), // Round to nearest integer
    };
  }
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  // Replace your existing _fetchUserDetails method with this complete version:

  Future<void> _fetchUserDetails({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final queryParams = selectedDate != null
          ? '?user_id=${widget.userId}&date=${DateFormat('yyyy-MM-dd').format(selectedDate!)}'
          : '?user_id=${widget.userId}';
      final response = await http.get(
        Uri.parse('https://adas-backend.onrender.com/api/get_user_details$queryParams'),
      );
      final data = jsonDecode(response.body);
      print(data);
      if (data['success']) {
        setState(() {
          userData = data['user'];
          if (showLoading) _isLoading = false;
        });
      } else {
        if (showLoading) {
          print('Failed to fetch user details: ${data['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to fetch user details: ${data['error']}'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (showLoading) {
        print('Failed to fetch user details: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching user details: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } finally {
      if (showLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _fetchUserDetails();
    }
  }

  Widget _buildPerformanceTab() {
    if (userData == null) return const SizedBox();

    final eventLogs = userData!['event_logs'] as List<dynamic>? ?? [];
    final totalEvents = eventLogs.length;
    final locations = userData!['locations'] as List<dynamic>? ?? [];

    final suddenAcceleration = eventLogs.where((e) => e['event_type'] == 'sudden_acceleration').length;
    final suddenBraking = eventLogs.where((e) => e['event_type'] == 'sudden_braking').length;
    final collisionWarnings = eventLogs.where((e) => e['event_type'] == 'collision_warning').length;
    double totalDistance = 0.0;
    for (var location in locations) {
      totalDistance += (location['total_distance'] as num?)?.toDouble() ?? 0.0;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Performance Score Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Driver Performance Score',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${userData!['score'] ?? 0}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'out of 100',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Event Statistics
          const Text(
            'Event Statistics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Total Events',
                  totalEvents.toString(),
                  Icons.warning_amber,
                  Colors.grey,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Hard Acceleration',
                  suddenAcceleration.toString(),
                  Icons.speed,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Hard Braking',
                  suddenBraking.toString(),
                  Icons.do_not_disturb_on,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Collision Warnings',
                  collisionWarnings.toString(),
                  Icons.warning,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Distance Traveled',
                  '${totalDistance.toStringAsFixed(1)} km',
                  Icons.directions,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: SizedBox.shrink()), // Empty space for layout balance
            ],
          ),
        ],
      ),

    );

  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab() {
    if (userData == null) return const SizedBox();

    final eventLogs = userData!['event_logs'] as List<dynamic>? ?? [];
    eventLogs.sort((a, b) {
      final aTime = DateTime.tryParse(a['timestamp'] ?? '') ?? DateTime(1970);
      final bTime = DateTime.tryParse(b['timestamp'] ?? '') ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return eventLogs.isEmpty
        ? Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_available,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'No events found',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(height: 8),
            Text(
              'for ${DateFormat('MMM dd, yyyy').format(selectedDate!)}',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ],
      ),
    )
        : ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: eventLogs.length,
      itemBuilder: (context, index) {
        final event = eventLogs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _getEventColor(event['event_type']).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getEventIcon(event['event_type']),
                color: _getEventColor(event['event_type']),
              ),
            ),
            title: Text(
              _getEventTitle(event['event_type']),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(event['event_description'] ?? 'No description'),
                const SizedBox(height: 4),
                Text(
                  'Time: ${event['timestamp']}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (event['latitude'] != 0.0 && event['longitude'] != 0.0)
                  Text(
                    'Location: ${event['latitude'].toStringAsFixed(4)}, ${event['longitude'].toStringAsFixed(4)}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  Widget _buildMapTab() {
    if (userData == null) return const SizedBox();

    final locations = userData!['locations'] as List<dynamic>? ?? [];
    final eventLogs = userData!['event_logs'] as List<dynamic>? ?? [];
    final speedStats = _calculateSpeedStats(locations);

    if (locations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.map_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No travel data found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
            if (selectedDate != null) ...[
              const SizedBox(height: 8),
              Text(
                'for ${DateFormat('MMM dd, yyyy').format(selectedDate!)}',
                style: TextStyle(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: locations.isNotEmpty
                ? latlng.LatLng(
              (locations[0]['start_location']['latitude'] as num).toDouble(),
              (locations[0]['start_location']['longitude'] as num).toDouble(),
            )
                : const latlng.LatLng(0.0, 0.0),
            initialZoom: 14.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
            ),
            PolylineLayer(
              polylines: locations.expand<Polyline>((location) {
                final path = location['traveled_path'] as List<dynamic>;
                List<Polyline> segments = [];

                for (int i = 0; i < path.length - 1; i++) {
                  final p1 = path[i];
                  final p2 = path[i + 1];

                  final lat1 = (p1['latitude'] as num).toDouble();
                  final lon1 = (p1['longitude'] as num).toDouble();
                  final speed = (p1['speed'] as num?)?.toDouble() ?? 0.0;

                  Color segmentColor = _getSpeedColor(speed);

                  final matchedEvent = eventLogs.firstWhere(
                        (event) {
                      double eLat = (event['latitude'] as num).toDouble();
                      double eLon = (event['longitude'] as num).toDouble();
                      return (eLat - lat1).abs() < 0.0001 &&
                          (eLon - lon1).abs() < 0.0001 &&
                          event['event_type'] != 'safe_driving';
                    },
                    orElse: () => null,
                  );

                  if (matchedEvent != null) {
                    segmentColor = _getEventColor(matchedEvent['event_type']);
                  }

                  segments.add(
                    Polyline(
                      points: [
                        latlng.LatLng(lat1, lon1),
                        latlng.LatLng(
                          (p2['latitude'] as num).toDouble(),
                          (p2['longitude'] as num).toDouble(),
                        ),
                      ],
                      strokeWidth: 4.0,
                      color: segmentColor,
                    ),
                  );
                }

                return segments;
              }).toList(),
            ),
            MarkerLayer(
              markers: [
                if (locations.isNotEmpty)
                  Marker(
                    point: latlng.LatLng(
                      (locations[0]['start_location']['latitude'] as num).toDouble(),
                      (locations[0]['start_location']['longitude'] as num).toDouble(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: Colors.green,
                        size: 30,
                      ),
                    ),
                  ),
                if (locations.isNotEmpty)
                  Marker(
                    point: latlng.LatLng(
                      (locations[0]['end_location']['latitude'] as num).toDouble(),
                      (locations[0]['end_location']['longitude'] as num).toDouble(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.stop_circle,
                        color: Colors.red,
                        size: 30,
                      ),
                    ),
                  ),
                ...eventLogs.where((event) =>
                event['latitude'] != 0.0 &&
                    event['longitude'] != 0.0 &&
                    event['event_type'] != 'safe_driving' &&
                    _getEventIcon(event['event_type']) != Icons.info).map<Marker>((event) {
                  return Marker(
                    point: latlng.LatLng(
                      (event['latitude'] as num).toDouble(),
                      (event['longitude'] as num).toDouble(),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _getEventColor(event['event_type']),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _getEventIcon(event['event_type']),
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
        // Legend with toggle button
        Positioned(
          bottom: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton(
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                onPressed: () {
                  setState(() {
                    _isLegendVisible = !_isLegendVisible;
                  });
                },
                child: Icon(_isLegendVisible ? Icons.visibility_off : Icons.visibility),
              ),
              const SizedBox(height: 8),
              if (_isLegendVisible)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Event & Speed Legend',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildLegendItem(Icons.trending_up, Colors.orange, 'Hard Acceleration'),
                      _buildLegendItem(Icons.speed, Colors.orange, 'Speeding'),
                      _buildLegendItem(Icons.pause_circle_filled, Colors.red, 'Hard Braking'),
                      _buildLegendItem(Icons.warning, Colors.purple, 'Collision Warning'),
                      _buildLegendItem(Icons.speed_outlined, Colors.amber, 'Speed Limit'),
                      _buildLegendItem(Icons.directions, Colors.yellow.shade600, 'Speed > 50 km/h'),
                      _buildLegendItem(Icons.directions, Colors.orange.shade600, 'Speed > 80 km/h'),
                      _buildLegendItem(Icons.directions, Colors.red.shade600, 'Speed > 100 km/h'),
                      const SizedBox(height: 6),
                      Divider(height: 1, color: Colors.grey.shade300),
                      const SizedBox(height: 6),
                      _buildLegendItem(Icons.play_circle_fill, Colors.green, 'Start Point'),
                      _buildLegendItem(Icons.stop_circle, Colors.red, 'End Point'),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Speed statistics
        Positioned(
          bottom: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9), // Semi-transparent white
              borderRadius: BorderRadius.circular(16), // Rounded corners
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Top: ${speedStats['maxSpeed']!.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'Avg: ${speedStats['averageSpeed']!.toStringAsFixed(0)} km/h',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 12,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Color _getEventColor(String eventType) {
    switch (eventType) {
      case 'sudden_acceleration':
      case 'speeding':
        return Colors.orange;
      case 'sudden_braking':
      case 'hard_braking':
        return Colors.red;
      case 'collision_warning':
        return Colors.purple;
      case 'speed_limit_violation':
        return Colors.amber;
      case 'safe_driving':
        return Colors.blue.shade300; // Subtle color for safe driving (but won't be used in legend)
      default:
        return Colors.blue.shade300;
    }
  }

  IconData _getEventIcon(String eventType) {
    switch (eventType) {
      case 'sudden_acceleration':
        return Icons.trending_up;
      case 'speeding':
        return Icons.speed;
      case 'sudden_braking':
      case 'hard_braking':
        return Icons.pause_circle_filled;
      case 'collision_warning':
        return Icons.warning;
      case 'speed_limit_violation':
        return Icons.speed_outlined;
      case 'safe_driving':
        return Icons.check_circle; // Won't be used since we filter out safe driving
      default:
        return Icons.info;
    }
  }
  Color _getSpeedColor(double speed) {
    if (speed > 100) return Colors.red.shade600; // Above 100 km/h
    if (speed > 80) return Colors.orange.shade600; // Above 80 km/h
    if (speed > 50) return Colors.yellow.shade600; // Above 50 km/h
    return Colors.blue.shade300; // Default (below or equal to 50 km/h)
  }

  String _getEventTitle(String eventType) {
    switch (eventType) {
      case 'sudden_acceleration':
        return 'Hard Acceleration';
      case 'speeding':
        return 'Speeding';
      case 'sudden_braking':
      case 'hard_braking':
        return 'Hard Braking';
      case 'collision_warning':
        return 'Collision Warning';
      case 'speed_limit_violation':
        return 'Speed Limit Exceeded';
      case 'safe_driving':
        return 'Safe Driving'; // Won't be displayed in legend
      default:
        return eventType.replaceAll('_', ' ').toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(

        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              widget.userName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              'Driver Details',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => _selectDate(context),
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(
                selectedDate != null
                    ? DateFormat('MMM dd').format(selectedDate!)
                    : 'All Time',
                style: const TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue.shade600,
                side: BorderSide(color: Colors.blue.shade200),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.blue.shade600,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.blue.shade600,
              indicatorWeight: 3,
              tabs: const [
                Tab(
                  icon: Icon(Icons.analytics, size: 20),
                  text: 'Performance',
                ),
                Tab(
                  icon: Icon(Icons.event_note, size: 20),
                  text: 'Events',
                ),
                Tab(
                  icon: Icon(Icons.map, size: 20),
                  text: 'Route',
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading user details...'),
          ],
        ),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _buildPerformanceTab(),
          _buildEventsTab(),
          _buildMapTab(),
        ],
      ),
    );
  }
}