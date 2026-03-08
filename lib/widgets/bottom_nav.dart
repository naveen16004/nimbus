import 'package:flutter/material.dart';
import 'package:iconify_flutter/iconify_flutter.dart';
import 'package:iconify_flutter/icons/ion.dart';
import 'package:nimbus/theme/colors.dart';

class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6121212),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: NavigationBar(
            height: 68,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: const <NavigationDestination>[
              NavigationDestination(
                icon: Iconify(
                  Ion.home_outline,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                selectedIcon: Iconify(
                  Ion.home,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Iconify(
                  Ion.images_outline,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                selectedIcon: Iconify(
                  Ion.images,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
                label: 'Albums',
              ),
              NavigationDestination(
                icon: Iconify(
                  Ion.settings_outline,
                  color: AppColors.textSecondary,
                  size: 22,
                ),
                selectedIcon: Iconify(
                  Ion.settings,
                  color: AppColors.textPrimary,
                  size: 22,
                ),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
