import 'package:flutter/material.dart';
import 'package:nimbus/routes/app_routes.dart';
import 'package:nimbus/screens/albums/albums.dart';
import 'package:nimbus/screens/home/home.dart';
import 'package:nimbus/screens/settings/settings.dart';
import 'package:nimbus/widgets/bottom_nav.dart';

class AppNavigationShell extends StatefulWidget {
  const AppNavigationShell({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    HomeScreen(),
    AlbumsScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = AppRoutes.indexOf(widget.initialRoute);
  }

  void _onDestinationSelected(int index) {
    if (index == _selectedIndex) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: Text(AppRoutes.titleForIndex(_selectedIndex))),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: AppBottomNavBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }
}
