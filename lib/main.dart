import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'login_page.dart';
import 'admin_page.dart';
import 'sub_admin_page.dart';
import 'user_page.dart';
import 'package:no_screenshot/no_screenshot.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final _noScreenshot = NoScreenshot.instance;

  const MyApp({Key? key, required this.cameras}) : super(key: key);

  void disableScreenshot() async {
    bool result = await _noScreenshot.screenshotOff();
    debugPrint('Disable Screenshot: $result');
  }

  void enableScreenshot() async {
    bool result = await _noScreenshot.screenshotOn();
    debugPrint('Enable Screenshot: $result');
  }

  @override
  Widget build(BuildContext context) {
    // Enable screenshots when app starts
    enableScreenshot();

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