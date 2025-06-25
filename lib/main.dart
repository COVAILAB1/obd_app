import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'login_page.dart';
import 'admin_page.dart';
import 'sub_admin_page.dart';
import 'user_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({Key? key, required this.cameras}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Assist',
      initialRoute: '/login',
      debugShowCheckedModeBanner: false,
      routes: {
        '/login': (context) => LoginPage(cameras: cameras),
        '/admin': (context) => const AdminPage(),
        '/sub_admin': (context) => const SubAdminPage(),
        '/user': (context) => UserPage(cameras: cameras),
      },
    );
  }
}