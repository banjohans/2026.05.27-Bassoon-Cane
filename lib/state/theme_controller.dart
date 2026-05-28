import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available top-level visual themes for ReedLab.
enum AppThemeVariant {
  classic('Classic Burgundy', 'Warm parchment, brass gilt and oxblood — the default ReedLab look.'),
  dark('Midnight Reed', 'Low-light slate with gold and rosewood accents for late-night sessions.'),
  enchantedForest('Enchanted Forest', 'Deep moss, bark and lichen tones with an amber glow.'),
  rococo('Rococo Salon', 'Pastel rose, powder blue and ivory with gilt highlights.');

  const AppThemeVariant(this.label, this.description);

  final String label;
  final String description;
}

/// A small, focused colour extension used by [ShellPage] and other top-level
/// chrome to react to the currently selected [AppThemeVariant] without having
/// to touch every hard-coded brand colour in the app.
@immutable
class BrandTheme extends ThemeExtension<BrandTheme> {
  const BrandTheme({
    required this.bodyGradient,
    required this.surfaceCard,
    required this.outline,
    required this.accent,
    required this.onAccent,
    required this.headerGradient,
    required this.headerForeground,
    required this.headerMuted,
  });

  final List<Color> bodyGradient;
  final Color surfaceCard;
  final Color outline;
  final Color accent;
  final Color onAccent;
  final List<Color> headerGradient;
  final Color headerForeground;
  final Color headerMuted;

  @override
  BrandTheme copyWith({
    List<Color>? bodyGradient,
    Color? surfaceCard,
    Color? outline,
    Color? accent,
    Color? onAccent,
    List<Color>? headerGradient,
    Color? headerForeground,
    Color? headerMuted,
  }) {
    return BrandTheme(
      bodyGradient: bodyGradient ?? this.bodyGradient,
      surfaceCard: surfaceCard ?? this.surfaceCard,
      outline: outline ?? this.outline,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      headerGradient: headerGradient ?? this.headerGradient,
      headerForeground: headerForeground ?? this.headerForeground,
      headerMuted: headerMuted ?? this.headerMuted,
    );
  }

  @override
  BrandTheme lerp(ThemeExtension<BrandTheme>? other, double t) {
    if (other is! BrandTheme) return this;
    List<Color> lerpList(List<Color> a, List<Color> b) {
      final length = a.length < b.length ? a.length : b.length;
      return List.generate(length, (i) => Color.lerp(a[i], b[i], t) ?? a[i]);
    }

    return BrandTheme(
      bodyGradient: lerpList(bodyGradient, other.bodyGradient),
      surfaceCard: Color.lerp(surfaceCard, other.surfaceCard, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      headerGradient: lerpList(headerGradient, other.headerGradient),
      headerForeground: Color.lerp(headerForeground, other.headerForeground, t)!,
      headerMuted: Color.lerp(headerMuted, other.headerMuted, t)!,
    );
  }
}

class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'reedlab_theme_variant';

  AppThemeVariant _variant = AppThemeVariant.classic;
  AppThemeVariant get variant => _variant;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      if (stored == null) return;
      final match = AppThemeVariant.values
          .where((v) => v.name == stored)
          .cast<AppThemeVariant?>()
          .firstWhere((_) => true, orElse: () => null);
      if (match != null) {
        _variant = match;
        notifyListeners();
      }
    } catch (_) {
      // Best-effort — preferences may not be available on first launch.
    }
  }

  Future<void> setVariant(AppThemeVariant variant) async {
    if (_variant == variant) return;
    _variant = variant;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, variant.name);
    } catch (_) {
      // Ignore persistence failures; in-memory selection still applies.
    }
  }
}
