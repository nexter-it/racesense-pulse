import 'package:flutter/material.dart';
/// Palette Racesense Live portata in Flutter
const kBgColor = Color(0xFF040404);
const kFgColor = Color(0xFFE9FFE0);
const kBrandColor = Color(0xFFC0FF03);
const kBrandWeakColor = Color(0xFFA8E403);
const kLineColor = Color.fromRGBO(192, 255, 3, 0.25);
const kMutedColor = Color(0xFF9AA39A);
const kErrorColor = Color(0xFFFF6B6B);
const kLiveColor = Color(0xFFFF4D4F);
const kPulseColor = Color(0xFF8E85FF);
const kCoachColor = Color(0xFFFFC24B);

ThemeData buildPulseTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  const fontFallback = [
    'SF Pro Text',
    'SF Pro Display',
    'San Francisco',
    'Segoe UI',
    'Roboto',
    'Oxygen',
    'Ubuntu',
    'Cantarell',
    'Fira Sans',
    'Droid Sans',
    'Helvetica Neue',
    'Arial',
    'sans-serif',
  ];

  return base.copyWith(
    scaffoldBackgroundColor: kBgColor,
    primaryColor: kBrandColor,
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: kBrandColor,
      secondary: kPulseColor,
      error: kErrorColor,
      surface: const Color(0xFF111111),
      background: kBgColor,
      onBackground: kFgColor,
      onPrimary: Colors.black,
      onSurface: kFgColor,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: kFgColor,
      displayColor: kFgColor,
      fontFamily: 'SF Pro Text',
      fontFamilyFallback: fontFallback,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: kFgColor,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: const Color.fromRGBO(255, 255, 255, 0.06),
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: const BorderSide(color: kLineColor),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color.fromRGBO(255, 255, 255, 0.06),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLineColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kLineColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBrandColor, width: 1.6),
      ),
      labelStyle: const TextStyle(color: kMutedColor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.black,
        backgroundColor: kBrandColor,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kFgColor,
        side: const BorderSide(color: kLineColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: const Color.fromRGBO(255, 255, 255, 0.06),
      selectedColor: const Color.fromRGBO(192, 255, 3, 0.15),
      labelStyle: const TextStyle(color: kFgColor),
      secondaryLabelStyle: const TextStyle(color: kFgColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: const BorderSide(color: kLineColor),
      ),
    ),
  );
}
