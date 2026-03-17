import 'package:flutter/material.dart';
import 'package:nimbus/routes/app_routes.dart';
import 'package:nimbus/routes/navigation_shell.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppNavigationShell(initialRoute: AppRoutes.home);
  }
}
