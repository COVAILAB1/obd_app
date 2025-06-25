import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class SubAdminPage extends StatefulWidget {
  const SubAdminPage({Key? key}) : super(key: key);

  @override
  _SubAdminPageState createState() => _SubAdminPageState();
}

class _SubAdminPageState extends State<SubAdminPage> {
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

  Future<void> _showEventLogs(int userId) async {
    final response = await http.get(
      Uri.parse('https://adas-backend.onrender.com/api/get_events?user_id=USER_ID'), // Replace with your local IP
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
      appBar: AppBar(title: const Text('Sub-Admin Dashboard')),
      body: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          return ListTile(
            title: Text('${user['full_name']} (${user['username']})'),
            subtitle: Text('Score: ${user['score']} | Car: ${user['car_name'] ?? 'N/A'}'),
            trailing: IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => _showEventLogs(user['id']),
            ),
          );
        },
      ),
    );
  }
}