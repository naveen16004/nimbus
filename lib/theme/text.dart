import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nimbus/theme/colors.dart';

class AppTextTheme {
  AppTextTheme._();

  static TextTheme build() {
    final TextTheme base = ThemeData.dark().textTheme;
    final TextTheme inter = GoogleFonts.interTextTheme(base);

    return inter.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
  }
}
