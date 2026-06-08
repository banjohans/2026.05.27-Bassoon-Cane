import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_controller.dart';
import 'state/theme_controller.dart';
import 'ui/shell.dart';

// Logo-derived palette (the original "Classic Burgundy" tokens).
const Color kBrandBurgundy = Color(0xFF5C1A1B); // primary
const Color kBrandBurgundyDark = Color(0xFF3A0F12);
const Color kBrandBurgundyDeep = Color(0xFF22070A); // deepest ink
const Color kBrandGold = Color(0xFFC9A24A); // brass accent
const Color kBrandGoldLight = Color(0xFFE8C977);
const Color kBrandGoldPale = Color(0xFFF4E5B8); // tint surfaces
const Color kBrandCane = Color(0xFFC19A6B); // warm cane wood
const Color kBrandParchment = Color(0xFFFAF3E7); // app surface
const Color kBrandParchmentDeep = Color(0xFFF1E6D3);
const Color kSurfaceTint = Color(0xFFF7EDD7); // subtle warm panel
const Color kSurfaceLine = Color(0xFFE6D9BD); // hairline border
const Color kInk = Color(0xFF22070A);
const Color kInkMuted = Color(0xFF5A4338);

// Harmonised status colours (jewel-toned, complement the burgundy/gold family).
const Color kStatusSuccess = Color(0xFF1F5D3A);
const Color kStatusSuccessAccent = Color(0xFF2E7D4A);
const Color kStatusSuccessSoft = Color(0xFFE0EBDF);
const Color kStatusWarning = Color(0xFFB8731F);
const Color kStatusWarningAccent = Color(0xFFDDA646);
const Color kStatusWarningSoft = Color(0xFFF6E4C4);
const Color kStatusDanger = Color(0xFF8B2A2A);
const Color kStatusDangerAccent = Color(0xFFC04848);
const Color kStatusDangerSoft = Color(0xFFF1D7D7);
const Color kStatusNeutral = Color(0xFF6B5A4E);

class BassoonCaneApp extends StatelessWidget {
  const BassoonCaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppController()..initialize()),
        ChangeNotifierProvider(create: (_) => ThemeController()..load()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, themeController, _) {
          return MaterialApp(
            title: 'ReedLab for Bassoon',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(themeController.variant),
            home: const ShellPage(),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme palettes
// ---------------------------------------------------------------------------

class _ThemePalette {
  const _ThemePalette({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.tertiary,
    required this.surface,
    required this.onSurface,
    required this.surfaceLow,
    required this.surfaceMid,
    required this.surfaceHigh,
    required this.outline,
    required this.bodyGradient,
    required this.headerGradient,
    required this.headerForeground,
    required this.headerMuted,
    required this.cardColor,
  });

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color tertiary;
  final Color surface;
  final Color onSurface;
  final Color surfaceLow;
  final Color surfaceMid;
  final Color surfaceHigh;
  final Color outline;
  final List<Color> bodyGradient;
  final List<Color> headerGradient;
  final Color headerForeground;
  final Color headerMuted;
  final Color cardColor;
}

_ThemePalette _paletteFor(AppThemeVariant variant) {
  switch (variant) {
    case AppThemeVariant.classic:
      return const _ThemePalette(
        brightness: Brightness.light,
        primary: kBrandBurgundy,
        onPrimary: kBrandGoldLight,
        primaryContainer: kBrandBurgundyDark,
        onPrimaryContainer: kBrandGoldLight,
        secondary: kBrandGold,
        onSecondary: kBrandBurgundyDeep,
        tertiary: kBrandCane,
        surface: Colors.white,
        onSurface: kInk,
        surfaceLow: kBrandParchment,
        surfaceMid: kSurfaceTint,
        surfaceHigh: kBrandParchmentDeep,
        outline: kSurfaceLine,
        bodyGradient: [kBrandParchment, kBrandParchmentDeep, kSurfaceTint],
        headerGradient: [kBrandBurgundyDeep, kBrandBurgundyDark, kBrandBurgundy],
        headerForeground: kBrandGoldLight,
        headerMuted: kBrandParchment,
        cardColor: Colors.white,
      );
    case AppThemeVariant.dark:
      return const _ThemePalette(
        brightness: Brightness.dark,
        primary: Color(0xFFD9B26A), // gold leaf for primary actions
        onPrimary: Color(0xFF1A0F12),
        primaryContainer: Color(0xFF3A1F23),
        onPrimaryContainer: Color(0xFFE8C977),
        secondary: Color(0xFF9C4A4C), // muted oxblood accent
        onSecondary: Color(0xFFF5E6CC),
        tertiary: Color(0xFFB07A56),
        surface: Color(0xFF1B1418),
        onSurface: Color(0xFFEFE3D2),
        surfaceLow: Color(0xFF151013),
        surfaceMid: Color(0xFF221A1E),
        surfaceHigh: Color(0xFF2C2227),
        outline: Color(0xFF3B2E33),
        bodyGradient: [Color(0xFF0E0A0C), Color(0xFF1B1418), Color(0xFF221A1E)],
        headerGradient: [Color(0xFF0E0A0C), Color(0xFF2A171B), Color(0xFF3A1F23)],
        headerForeground: Color(0xFFE8C977),
        headerMuted: Color(0xFFD9C6A8),
        cardColor: Color(0xFF231A1E),
      );
    case AppThemeVariant.enchantedForest:
      return const _ThemePalette(
        brightness: Brightness.light,
        primary: Color(0xFF2F4A30), // moss
        onPrimary: Color(0xFFF1E5B8),
        primaryContainer: Color(0xFF1F3322),
        onPrimaryContainer: Color(0xFFE9D798),
        secondary: Color(0xFFB8842B), // amber glow
        onSecondary: Color(0xFF1F3322),
        tertiary: Color(0xFF7A5A36), // bark
        surface: Color(0xFFFBF7EA),
        onSurface: Color(0xFF1B2A1D),
        surfaceLow: Color(0xFFEFEAD6),
        surfaceMid: Color(0xFFE3DDC4),
        surfaceHigh: Color(0xFFD7D0B2),
        outline: Color(0xFFC1B894),
        bodyGradient: [Color(0xFFEFEAD6), Color(0xFFDCE3CB), Color(0xFFE9DFBE)],
        headerGradient: [Color(0xFF13231A), Color(0xFF1F3322), Color(0xFF2F4A30)],
        headerForeground: Color(0xFFEED8A0),
        headerMuted: Color(0xFFE9E3C7),
        cardColor: Color(0xFFFBF7EA),
      );
    case AppThemeVariant.rococo:
      return const _ThemePalette(
        brightness: Brightness.light,
        primary: Color(0xFF8E3A66), // dusty rose
        onPrimary: Color(0xFFFFF1F2),
        primaryContainer: Color(0xFF6B2A4C),
        onPrimaryContainer: Color(0xFFFCE0E7),
        secondary: Color(0xFFB89858), // gilt
        onSecondary: Color(0xFF3A1F2E),
        tertiary: Color(0xFF6A7FA8), // powder blue
        surface: Color(0xFFFFF7F4),
        onSurface: Color(0xFF3A1F2E),
        surfaceLow: Color(0xFFFBEAEC),
        surfaceMid: Color(0xFFF4DDE2),
        surfaceHigh: Color(0xFFEFD0D8),
        outline: Color(0xFFE3C5CE),
        bodyGradient: [Color(0xFFFCEFEF), Color(0xFFF4DDE2), Color(0xFFEAE2F0)],
        headerGradient: [Color(0xFF6B2A4C), Color(0xFF8E3A66), Color(0xFFB89858)],
        headerForeground: Color(0xFFFFE9C8),
        headerMuted: Color(0xFFFBE4D6),
        cardColor: Color(0xFFFFFAFB),
      );
  }
}

ThemeData _buildTheme(AppThemeVariant variant) {
  final p = _paletteFor(variant);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: p.brightness,
  ).copyWith(
    primary: p.primary,
    onPrimary: p.onPrimary,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: p.secondary,
    onSecondary: p.onSecondary,
    secondaryContainer: p.surfaceHigh,
    onSecondaryContainer: p.onSurface,
    tertiary: p.tertiary,
    onTertiary: p.onPrimary,
    surface: p.surface,
    onSurface: p.onSurface,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surfaceLow,
    surfaceContainer: p.surfaceMid,
    surfaceContainerHigh: p.surfaceHigh,
    surfaceContainerHighest: p.surfaceHigh,
    outline: p.outline,
    outlineVariant: p.outline,
    error: kStatusDanger,
    onError: Colors.white,
  );

  final mutedInk = Color.alphaBlend(p.onSurface.withValues(alpha: 0.55), p.surface);

  final baseText = p.brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;

  final brandExtension = BrandTheme(
    bodyGradient: p.bodyGradient,
    surfaceCard: p.cardColor,
    outline: p.outline,
    accent: p.secondary,
    onAccent: p.onSecondary,
    headerGradient: p.headerGradient,
    headerForeground: p.headerForeground,
    headerMuted: p.headerMuted,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: p.surfaceLow,
    textTheme: baseText,
    extensions: [brandExtension],
    appBarTheme: AppBarTheme(
      backgroundColor: p.primaryContainer,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.onPrimary,
      iconTheme: IconThemeData(color: p.onPrimary),
      titleTextStyle: TextStyle(
        color: p.onPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: const OutlineInputBorder(),
      isDense: true,
      filled: true,
      fillColor: p.surfaceMid,
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.primary, width: 1.6),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: p.outline, width: 1),
      ),
      hintStyle: TextStyle(color: p.onSurface.withValues(alpha: 0.7)),
      floatingLabelStyle: TextStyle(color: p.primary, fontWeight: FontWeight.w600),
      labelStyle: TextStyle(color: p.primary),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(color: p.onSurface),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(p.surfaceHigh),
        side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceMid,
        hintStyle: TextStyle(color: p.onSurface.withValues(alpha: 0.7)),
      ),
    ),
    cardTheme: CardThemeData(
      color: p.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.secondary.withValues(alpha: 0.35)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.primary,
        side: BorderSide(color: p.primary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.primary),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.primary,
      foregroundColor: p.onPrimary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.secondary.withValues(alpha: 0.30),
      labelStyle: TextStyle(color: p.onSurface, fontWeight: FontWeight.w600),
      side: BorderSide(color: p.secondary.withValues(alpha: 0.5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: DividerThemeData(
      color: p.outline,
      thickness: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.secondary,
      linearTrackColor: p.secondary.withValues(alpha: 0.20),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.primaryContainer,
      contentTextStyle: TextStyle(color: p.onPrimary),
      actionTextColor: p.onPrimary,
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.cardColor,
      indicatorColor: p.secondary.withValues(alpha: 0.30),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: p.primary);
        }
        return IconThemeData(color: mutedInk);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: p.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          );
        }
        return TextStyle(color: mutedInk, fontSize: 12);
      }),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.primary,
      inactiveTrackColor: p.outline,
      thumbColor: p.secondary,
      overlayColor: p.secondary.withValues(alpha: 0.20),
      valueIndicatorColor: p.primary,
      valueIndicatorTextStyle: TextStyle(color: p.onPrimary, fontWeight: FontWeight.w700),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onPrimary;
          return p.primary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.primary;
          return p.cardColor;
        }),
        side: WidgetStateProperty.all(BorderSide(color: p.primary, width: 1)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(p.primary),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.cardColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titleTextStyle: TextStyle(
        color: p.primary,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
      contentTextStyle: TextStyle(color: p.onSurface, fontSize: 14),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.primary,
      textColor: p.onSurface,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.secondary;
        return mutedInk;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return p.primary;
        return p.outline;
      }),
    ),
  );
}
