import 'package:flutter/material.dart';

/// CommunityHub — "Divine Tech" Color System
/// Primary: Deep Navy (trust, faith) | Secondary: Sacred Gold (divinity)
/// Accent: Sky Blue (tech, clarity) | Dark base for modern appeal

abstract class AppColors {
  // ── Brand ─────────────────────────────────────────────────
  static const Color primary = Color(0xFF1A237E);        // Deep Navy
  static const Color primaryLight = Color(0xFF3949AB);   // Indigo
  static const Color primaryDark = Color(0xFF0D0D5C);    // Midnight Navy

  static const Color secondary = Color(0xFFF9A825);      // Sacred Gold
  static const Color secondaryLight = Color(0xFFFFCA28); // Bright Gold
  static const Color secondaryDark = Color(0xFFF57F17);  // Deep Amber

  static const Color accent = Color(0xFF4FC3F7);         // Sky Blue
  static const Color accentDark = Color(0xFF0288D1);     // Ocean Blue

  // ── Semantic ──────────────────────────────────────────────
  static const Color success = Color(0xFF66BB6A);        // Green
  static const Color error = Color(0xFFEF5350);          // Red
  static const Color warning = Color(0xFFFFA726);        // Amber
  static const Color info = Color(0xFF29B6F6);           // Light Blue

  // ── Dark Mode Surfaces ────────────────────────────────────
  static const Color darkBackground = Color(0xFF0D1117);  // Near Black
  static const Color darkSurface = Color(0xFF161B22);     // Dark Card
  static const Color darkSurface2 = Color(0xFF21262D);    // Elevated Card
  static const Color darkBorder = Color(0xFF30363D);      // Subtle border
  static const Color darkDivider = Color(0xFF21262D);

  // ── Light Mode Surfaces ───────────────────────────────────
  static const Color lightBackground = Color(0xFFF8F9FA); // Off White
  static const Color lightSurface = Color(0xFFFFFFFF);    // Pure White
  static const Color lightSurface2 = Color(0xFFF0F2F5);  // Card background
  static const Color lightBorder = Color(0xFFE4E6EB);
  static const Color lightDivider = Color(0xFFE4E6EB);

  // ── Text ──────────────────────────────────────────────────
  static const Color textDarkPrimary = Color(0xFFF0F6FC);    // Near white
  static const Color textDarkSecondary = Color(0xFF8B949E);  // Muted
  static const Color textDarkTertiary = Color(0xFF484F58);   // Very muted
  static const Color textMuted = Color(0xFF8B949E);          // Alias for textDarkSecondary

  static const Color textLightPrimary = Color(0xFF0D1117);   // Near black
  static const Color textLightSecondary = Color(0xFF57606A); // Gray
  static const Color textLightTertiary = Color(0xFF8C959F);  // Light gray

  // ── Special UI ────────────────────────────────────────────
  static const Color storyRing = Color(0xFFF9A825);         // Gold story ring
  static const Color liveIndicator = Color(0xFFEF5350);     // Red live dot
  static const Color verifiedBadge = Color(0xFF4FC3F7);     // Blue checkmark
  static const Color faithTag = Color(0xFF7B1FA2);          // Purple for faith
  static const Color techTag = Color(0xFF00897B);           // Teal for tech
  static const Color churchTag = Color(0xFF1A237E);         // Navy for church

  // ── Short aliases ─────────────────────────────────────────
  static const Color backgroundDark = darkBackground;
  static const Color surfaceDark = darkSurface;
  static const Color divider = darkDivider;
  static const Color border = darkBorder;
  static const Color textPrimary = textDarkPrimary;
  static const Color textSecondary = textDarkSecondary;
  static const Color gold = secondary; // Sacred Gold alias

  // ── Gradient Presets ──────────────────────────────────────
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFF9A825), Color(0xFFFF8F00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient storyGradient = LinearGradient(
    colors: [Color(0xFFF9A825), Color(0xFFEF5350), Color(0xFF7B1FA2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkOverlay = LinearGradient(
    colors: [Colors.transparent, Color(0xCC0D1117)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF0D0D5C), Color(0xFF1A237E), Color(0xFF3949AB)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
