// lib/core/theme.dart
import 'package:fluent_ui/fluent_ui.dart';

class AppTheme {
  // Google Pixel 10 signature styling palette
  static const Color pixelBlue = Color(0xFF1A73E8);
  static const Color pixelGreen = Color(0xFF34A853);
  static const Color pixelAmber = Color(0xFFFBBC04);
  static const Color pixelRed = Color(0xFFEA4335);

  static FluentThemeData lightTheme = FluentThemeData(
    brightness: Brightness.light,
    accentColor: Colors.blue,
    scaffoldBackgroundColor: const Color(0xF0F3F3F3),
    micaBackgroundColor: const Color(0xE0F3F3F3),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardColor: const Color(0xD8FFFFFF),
  );

  static FluentThemeData darkTheme = FluentThemeData(
    brightness: Brightness.dark,
    accentColor: Colors.blue,
    scaffoldBackgroundColor: const Color(0xF0202020),
    micaBackgroundColor: const Color(0xE01C1C1C),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    cardColor: const Color(0xCC2B2B2B),
  );
}
