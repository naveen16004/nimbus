import 'package:flutter/material.dart';
import 'package:nimbus/routes/app_navigation_shell.dart';
import 'package:nimbus/routes/app_routes.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final String routeName = AppRoutes.normalize(settings.name);

    return MaterialPageRoute<void>(
      settings: RouteSettings(name: routeName, arguments: settings.arguments),
      builder: (_) => AppNavigationShell(initialRoute: routeName),
    );
  }
}
