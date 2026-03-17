import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ion.dart';
import 'package:nimbus/theme/colors.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

void signUserout(){
    FirebaseAuth.instance.signOut();
  }
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoBackup = true;
  bool _wifiOnly = true;
  bool _useDynamicGrid = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Iconify(Ion.arrow_back, color: Colors.white, size: 20),
        ),
        title: Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
                        
              actions: [IconButton(onPressed: widget.signUserout,icon:Icon(Icons.logout ))],backgroundColor: const Color.fromARGB(255, 3, 3, 3),         
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: <Widget>[
                const Iconify(Ion.person_circle_outline, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Nimbus User',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Local media and privacy-first sync',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsGroup(
            title: 'Appearance',
            children: <Widget>[
              SwitchListTile(
                value: _useDynamicGrid,
                onChanged: (bool value) {
                  setState(() {
                    _useDynamicGrid = value;
                  });
                },
                title: const Text('Remember grid preference'),
                subtitle: const Text('Keep last grid size across launches'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            title: 'Backup',
            children: <Widget>[
              SwitchListTile(
                value: _autoBackup,
                onChanged: (bool value) {
                  setState(() {
                    _autoBackup = value;
                  });
                },
                title: const Text('Auto backup'),
              ),
              SwitchListTile(
                value: _wifiOnly,
                onChanged: (bool value) {
                  setState(() {
                    _wifiOnly = value;
                  });
                },
                title: const Text('Upload on Wi-Fi only'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            title: 'Storage',
            children: const <Widget>[
              ListTile(
                title: Text('Manage local cache'),
                trailing: Iconify(Ion.chevron_right, size: 16),
              ),
              ListTile(
                title: Text('App album storage'),
                trailing: Iconify(Ion.chevron_right, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsGroup(
            title: 'About',
            children: const <Widget>[
              ListTile(title: Text('Version 1.0.0+1')),
              ListTile(
                title: Text('Privacy policy'),
                trailing: Iconify(Ion.chevron_right, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
