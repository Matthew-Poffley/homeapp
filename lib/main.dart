import 'package:flutter/material.dart';

import 'screens/plug_list_screen.dart';
import 'screens/plug_tile.dart';

void main() {
  runApp(const HomeControllerApp());
}

class HomeControllerApp extends StatelessWidget {
  const HomeControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Home Controller',
      theme: _buildTheme(),
      home: const PlugListScreen(),
    );
  }

  ThemeData _buildTheme() {
    const background = Color(0xFF0A0A0A);
    const surface = Color(0xFF161616);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: neonGreen,
      brightness: Brightness.dark,
    ).copyWith(primary: neonGreen, secondary: neonGreen, surface: surface);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF141414)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? neonGreen : Colors.grey.shade600,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? neonGreen.withValues(alpha: 0.4)
              : Colors.grey.shade800,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? neonGreen.withValues(alpha: 0.18)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? neonGreen : Colors.white70,
          ),
          side: WidgetStateProperty.all(BorderSide(color: neonGreen.withValues(alpha: 0.5))),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: neonGreen, foregroundColor: Colors.black),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: neonGreen,
        foregroundColor: Colors.black,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: neonGreen),
        ),
      ),
    );
  }
}
