import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminPage extends StatefulWidget {
  const AdminPage({Key? key}) : super(key: key);

  @override
  _AdminPageState createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<dynamic> users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    final response = await http.get(
      Uri.parse('https://adas-backend.onrender.com/api/get_users'), // Replace with your local IP
    );
    final data = jsonDecode(response.body);
    if (data['success']) {
      setState(() {
        users = data['users'];
      });
    }
  }

  Future<void> _addUser(Map<String, String> userData) async {
    final response = await http.post(
      Uri.parse('https://adas-backend.onrender.com/api/add_user'), // Replace with your local IP
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(userData),
    );
    if (jsonDecode(response.body)['success']) {
      _fetchUsers();
    }
  }

  Future<void> _updateUser(Map<String, dynamic> userData) async {
    final response = await http.put(
      Uri.parse('https://adas-backend.onrender.com/api/update_user'), // Replace with your local IP
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(userData),
    );
    if (jsonDecode(response.body)['success']) {
      _fetchUsers();
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
      builder: (context) => AlertDialog(
        title: const Text('Add User'),
        content: SingleChildScrollView(
          child: Column(
            children: controllers.entries
                .map((e) => TextField(
              controller: e.value,
              decoration: InputDecoration(labelText: e.key),
            ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _addUser({for (var e in controllers.entries) e.key: e.value.text});
              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
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
      builder: (context) => AlertDialog(
        title: const Text('Edit User'),
        content: SingleChildScrollView(
          child: Column(
            children: controllers.entries
                .map((e) => TextField(
              controller: e.value,
              decoration: InputDecoration(labelText: e.key),
            ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _updateUser({
                'id': user['id'],
                ...{for (var e in controllers.entries) e.key: e.value.text},
              });
              Navigator.pop(context);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEventLogs(int userId) async {
    final response = await http.get(
      Uri.parse('http://192.168.1.40/driver/api.php?action=get_events&user_id=$userId'), // Replace with your local IP
    );
    final data = jsonDecode(response.body);
    if (data['success']) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Event Logs'),
          content: SingleChildScrollView(
            child: Column(
              children: data['events']
                  .map<Widget>((event) => ListTile(
                title: Text('${event['event_type']} - ${event['timestamp']}'),
                subtitle: Text(event['event_description']),
              ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Dashboard')),
      body: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return ListTile(
            title: Text('${user['full_name']} (${user['username']})'),
            subtitle: Text('Score: ${user['score']} | Car: ${user['car_name'] ?? 'N/A'}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditUserDialog(user),
                ),
                IconButton(
                  icon: const Icon(Icons.history),
                  onPressed: () => _showEventLogs(user['id']),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddUserDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}