import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nimbus/authenication/firebase_options.dart';
import 'package:nimbus/authenication/pages/auth_page.dart';
import 'package:nimbus/routes/app_router.dart';
import 'package:nimbus/theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Hive.initFlutter();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  runApp(const NimbusApp());
}

class NimbusApp extends StatelessWidget {
  const NimbusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nimbus',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AuthPage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
