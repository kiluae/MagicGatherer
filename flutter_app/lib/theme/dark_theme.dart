import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Palette ──────────────────────────────────────────────────────────────────
const Color kBgBase      = Color(0xFF121212);
const Color kBgPane      = Color(0xFF1E1E2E);
const Color kBgCard      = Color(0xFF2A2A3C);
const Color kAccent      = Color(0xFF7C3AED); // violet
const Color kAccentLight = Color(0xFFA78BFA);
const Color kSuccess     = Color(0xFF22C55E);
const Color kWarning     = Color(0xFFF59E0B);
const Color kError       = Color(0xFFEF4444);
const Color kBorder      = Color(0xFF3A3A4C);
const Color kText        = Color(0xFFE0E0E0);
const Color kTextMuted   = Color(0xFF9CA3AF);

ThemeData buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: kText,
    displayColor: kText,
  );

  return base.copyWith(
    scaffoldBackgroundColor: kBgBase,
    colorScheme: const ColorScheme.dark(
      primary:   kAccent,
      secondary: kAccentLight,
      surface:   kBgPane,
      error:     kError,
      onPrimary: Colors.white,
      onSurface: kText,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: kBgPane,
      foregroundColor: kText,
      elevation: 0,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w600, color: kText,
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: kBgPane,
      selectedIconTheme: IconThemeData(color: kAccentLight),
      unselectedIconTheme: IconThemeData(color: kTextMuted),
      selectedLabelTextStyle: TextStyle(color: kAccentLight, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: kTextMuted),
      indicatorColor: Color(0x337C3AED),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kBgCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: kAccent, width: 2),
      ),
      hintStyle: const TextStyle(color: kTextMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: kAccentLight,
        side: const BorderSide(color: kAccent),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kAccent;
        return kBgCard;
      }),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: kBorder, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kAccent;
        return kTextMuted;
      }),
    ),
    dividerTheme: const DividerThemeData(color: kBorder, thickness: 1),
    cardTheme: CardThemeData(
      color: kBgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: kBorder),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),
  );
}
