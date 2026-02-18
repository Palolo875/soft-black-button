import 'package:flutter/material.dart';

class HorizonTokens {
  static const Color seed = Color(0xFFABC9D3);
  static const double radius = 22.0;

  static const double space2 = 2;
  static const double space4 = 4;
  static const double space6 = 6;
  static const double space8 = 8;
  static const double space10 = 10;
  static const double space12 = 12;
  static const double space14 = 14;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 2;
  static const double elevation3 = 3;
  static const double elevation4 = 4;

  static const Color bgLight = Color(0xFFF6F7F8);
  static const Color surfaceLight = Colors.white;

  static const Color bgDark = Color(0xFF0C1217);
  static const Color surfaceDark = Color(0xFF141C22);
}

class HorizonTheme {
  static TextTheme _textTheme(ColorScheme scheme) {
    return TextTheme(
      titleLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900, fontSize: 22, height: 1.15),
      titleMedium: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 18, height: 1.15),
      titleSmall: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 16, height: 1.15),
      bodyLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 16, height: 1.25),
      bodyMedium: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14, height: 1.25),
      bodySmall: TextStyle(color: scheme.onSurface.withOpacity(0.75), fontWeight: FontWeight.w600, fontSize: 12, height: 1.25),
      labelLarge: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 13, height: 1.1, letterSpacing: -0.2),
      labelMedium: TextStyle(color: scheme.onSurface.withOpacity(0.85), fontWeight: FontWeight.w800, fontSize: 12, height: 1.1, letterSpacing: -0.2),
      labelSmall: TextStyle(color: scheme.onSurface.withOpacity(0.75), fontWeight: FontWeight.w800, fontSize: 11, height: 1.1, letterSpacing: -0.2),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: HorizonTokens.seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(scheme),
      scaffoldBackgroundColor: HorizonTokens.bgLight,
      chipTheme: ChipThemeData(
        backgroundColor: HorizonTokens.surfaceLight.withOpacity(0.70),
        selectedColor: HorizonTokens.surfaceLight.withOpacity(0.92),
        disabledColor: HorizonTokens.surfaceLight.withOpacity(0.45),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface.withOpacity(0.75), size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.35), width: 1),
        ),
      ),
      cardTheme: CardTheme(
        color: HorizonTokens.surfaceLight.withOpacity(0.92),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HorizonTokens.surfaceLight.withOpacity(0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide(color: HorizonTokens.seed.withOpacity(0.35), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1.5,
        backgroundColor: HorizonTokens.surfaceLight.withOpacity(0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: HorizonTokens.seed,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(scheme),
      scaffoldBackgroundColor: HorizonTokens.bgDark,
      chipTheme: ChipThemeData(
        backgroundColor: HorizonTokens.surfaceDark.withOpacity(0.65),
        selectedColor: HorizonTokens.surfaceDark.withOpacity(0.92),
        disabledColor: HorizonTokens.surfaceDark.withOpacity(0.45),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSurface),
        iconTheme: IconThemeData(color: scheme.onSurface.withOpacity(0.80), size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.35), width: 1),
        ),
      ),
      cardTheme: CardTheme(
        color: HorizonTokens.surfaceDark.withOpacity(0.92),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HorizonTokens.surfaceDark.withOpacity(0.92),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HorizonTokens.radius),
          borderSide: BorderSide(color: HorizonTokens.seed.withOpacity(0.45), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 1.5,
        backgroundColor: HorizonTokens.surfaceDark.withOpacity(0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
