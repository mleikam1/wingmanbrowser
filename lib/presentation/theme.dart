import 'package:flutter/material.dart';
import 'design_system/wingman_tokens.dart';
import 'components/wingman_route.dart';
export 'design_system/wingman_tokens.dart';

abstract final class WingmanTheme {
  static ThemeData make(Brightness brightness) {
    final t = brightness == Brightness.dark
        ? WingmanTokens.dark
        : WingmanTokens.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: t.action,
          brightness: brightness,
        ).copyWith(
          primary: t.action,
          onPrimary: t.onAction,
          primaryContainer: t.raised,
          onPrimaryContainer: t.text,
          secondary: t.action,
          onSecondary: t.onAction,
          secondaryContainer: t.raised,
          onSecondaryContainer: t.text,
          tertiary: t.action,
          onTertiary: t.onAction,
          surface: t.surface,
          onSurface: t.text,
          onSurfaceVariant: t.secondaryText,
          surfaceContainerLowest: t.canvas,
          surfaceContainerLow: t.canvas,
          surfaceContainer: t.surface,
          surfaceContainerHigh: t.raised,
          surfaceContainerHighest: t.raised,
          outline: t.controlOutline,
          outlineVariant: t.divider,
          error: t.danger,
          errorContainer: t.dangerSurface,
          onErrorContainer: t.danger,
        );
    TextStyle type(
      double size,
      double line, {
      FontWeight weight = FontWeight.w400,
      Color? color,
    }) => TextStyle(
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Noto Sans Symbols'],
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      color: color ?? t.text,
    );
    final text = TextTheme(
      displaySmall: type(36, 42, weight: FontWeight.w700),
      headlineLarge: type(32, 40, weight: FontWeight.w700),
      headlineMedium: type(28, 34, weight: FontWeight.w700),
      headlineSmall: type(24, 32, weight: FontWeight.w700),
      titleLarge: type(20, 28, weight: FontWeight.w700),
      titleMedium: type(16, 24, weight: FontWeight.w500),
      titleSmall: type(14, 20, weight: FontWeight.w700),
      bodyLarge: type(16, 24),
      bodyMedium: type(16, 24),
      bodySmall: type(12, 16, color: t.secondaryText),
      labelLarge: type(14, 20, weight: FontWeight.w500),
      labelMedium: type(12, 16, weight: FontWeight.w500),
      labelSmall: type(12, 16, weight: FontWeight.w500),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      shape: WidgetStatePropertyAll(shape),
      animationDuration: WingmanTokens.press,
    );
    return ThemeData(
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: WingmanPageTransitions(),
          TargetPlatform.iOS: WingmanPageTransitions(),
          TargetPlatform.macOS: WingmanPageTransitions(),
          TargetPlatform.linux: WingmanPageTransitions(),
          TargetPlatform.windows: WingmanPageTransitions(),
          TargetPlatform.fuchsia: WingmanPageTransitions(),
        },
      ),
      fontFamily: 'Roboto',
      fontFamilyFallback: const ['Noto Sans Symbols'],
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      extensions: [t],
      scaffoldBackgroundColor: t.canvas,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: t.canvas,
        foregroundColor: t.text,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: type(18, 26, weight: FontWeight.w700),
        centerTitle: false,
        toolbarHeight: 64,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        hoverColor: t.raised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        labelStyle: type(14, 20, color: t.secondaryText),
        hintStyle: type(16, 24, color: t.secondaryText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.controlOutline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.controlOutline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.action, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: button),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: button.copyWith(
          side: WidgetStatePropertyAll(BorderSide(color: t.controlOutline)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: button.copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        ),
      ),
      cardTheme: CardThemeData(
        color: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: t.divider),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.raised,
        side: BorderSide(color: t.controlOutline),
        labelStyle: text.labelLarge,
        padding: const EdgeInsets.all(8),
      ),
      dividerTheme: DividerThemeData(color: t.divider, thickness: 1, space: 24),
      listTileTheme: ListTileThemeData(
        minTileHeight: 64,
        iconColor: t.secondaryText,
        textColor: t.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        selectedTileColor: t.raised,
        selectedColor: t.action,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surface,
        indicatorColor: t.raised,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: t.canvas,
        indicatorColor: t.raised,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.text,
        contentTextStyle: type(14, 20, color: t.canvas),
        actionTextColor: brightness == Brightness.dark
            ? WingmanTokens.light.action
            : WingmanTokens.dark.action,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
