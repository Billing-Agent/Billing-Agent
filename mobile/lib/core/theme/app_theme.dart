import 'package:flutter/material.dart';

@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color pending;
  final Color pendingContainer;
  final Color onPendingContainer;
  final Color information;
  final Color informationContainer;
  final Color onInformationContainer;
  final Color neutral;
  final Color neutralContainer;
  final Color onNeutralContainer;
  final Color border;
  final Color surfaceSubtle;

  const AppSemanticColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.pending,
    required this.pendingContainer,
    required this.onPendingContainer,
    required this.information,
    required this.informationContainer,
    required this.onInformationContainer,
    required this.neutral,
    required this.neutralContainer,
    required this.onNeutralContainer,
    required this.border,
    required this.surfaceSubtle,
  });

  static const light = AppSemanticColors(
    success: Color(0xFF15803D),
    successContainer: Color(0xFFEAF7EE),
    onSuccessContainer: Color(0xFF14532D),
    pending: Color(0xFFB45309),
    pendingContainer: Color(0xFFFFF4E5),
    onPendingContainer: Color(0xFF7C2D12),
    information: Color(0xFF0369A1),
    informationContainer: Color(0xFFE7F3FA),
    onInformationContainer: Color(0xFF0C4A6E),
    neutral: Color(0xFF64748B),
    neutralContainer: Color(0xFFF1F5F9),
    onNeutralContainer: Color(0xFF334155),
    border: Color(0xFFD9E2EC),
    surfaceSubtle: Color(0xFFF6F8FB),
  );

  static const dark = AppSemanticColors(
    success: Color(0xFF4ADE80),
    successContainer: Color(0xFF123D27),
    onSuccessContainer: Color(0xFFBBF7D0),
    pending: Color(0xFFFBBF24),
    pendingContainer: Color(0xFF4A3212),
    onPendingContainer: Color(0xFFFDE68A),
    information: Color(0xFF38BDF8),
    informationContainer: Color(0xFF12354A),
    onInformationContainer: Color(0xFFBAE6FD),
    neutral: Color(0xFF94A3B8),
    neutralContainer: Color(0xFF273449),
    onNeutralContainer: Color(0xFFE2E8F0),
    border: Color(0xFF334155),
    surfaceSubtle: Color(0xFF172033),
  );

  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? pending,
    Color? pendingContainer,
    Color? onPendingContainer,
    Color? information,
    Color? informationContainer,
    Color? onInformationContainer,
    Color? neutral,
    Color? neutralContainer,
    Color? onNeutralContainer,
    Color? border,
    Color? surfaceSubtle,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      pending: pending ?? this.pending,
      pendingContainer: pendingContainer ?? this.pendingContainer,
      onPendingContainer: onPendingContainer ?? this.onPendingContainer,
      information: information ?? this.information,
      informationContainer: informationContainer ?? this.informationContainer,
      onInformationContainer:
          onInformationContainer ?? this.onInformationContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
      onNeutralContainer: onNeutralContainer ?? this.onNeutralContainer,
      border: border ?? this.border,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    );
  }

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      pendingContainer:
          Color.lerp(pendingContainer, other.pendingContainer, t)!,
      onPendingContainer:
          Color.lerp(onPendingContainer, other.onPendingContainer, t)!,
      information: Color.lerp(information, other.information, t)!,
      informationContainer:
          Color.lerp(informationContainer, other.informationContainer, t)!,
      onInformationContainer: Color.lerp(
        onInformationContainer,
        other.onInformationContainer,
        t,
      )!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      neutralContainer:
          Color.lerp(neutralContainer, other.neutralContainer, t)!,
      onNeutralContainer:
          Color.lerp(onNeutralContainer, other.onNeutralContainer, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
    );
  }
}

class AppTheme {
  static const Color primaryBlue = Color(0xFF0F4C81);
  static const Color secondaryTeal = Color(0xFF0E7490);
  static const Color backgroundLight = Color(0xFFF6F8FB);
  static const Color backgroundDark = Color(0xFF0B1220);
  static const Color errorRed = Color(0xFFB91C1C);
  static const Color successGreen = Color(0xFF15803D);
  static const Color textLight = Color(0xFF0F172A);
  static const Color textDark = Color(0xFFF8FAFC);

  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightTextSecondary = Color(0xFF475569);
  static const Color _darkSurface = Color(0xFF111827);
  static const Color _darkTextSecondary = Color(0xFFCBD5E1);

  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: primaryBlue,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE8F1F8),
    onPrimaryContainer: Color(0xFF0B365C),
    secondary: secondaryTeal,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFDDF3F6),
    onSecondaryContainer: Color(0xFF0D4C5C),
    surface: _lightSurface,
    onSurface: textLight,
    onSurfaceVariant: _lightTextSecondary,
    error: errorRed,
    onError: Colors.white,
    errorContainer: Color(0xFFFDECEC),
    onErrorContainer: Color(0xFF7F1D1D),
    outline: Color(0xFF64748B),
    outlineVariant: Color(0xFFD9E2EC),
    shadow: Color(0x1A0F172A),
    scrim: Color(0x990B1220),
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: Color(0xFF83B9E4),
    onPrimary: Color(0xFF052A47),
    primaryContainer: Color(0xFF173E5D),
    onPrimaryContainer: Color(0xFFD6EAF8),
    secondary: Color(0xFF67D1DC),
    onSecondary: Color(0xFF00363D),
    secondaryContainer: Color(0xFF164E58),
    onSecondaryContainer: Color(0xFFCFFAFE),
    surface: _darkSurface,
    onSurface: textDark,
    onSurfaceVariant: _darkTextSecondary,
    error: Color(0xFFFCA5A5),
    onError: Color(0xFF450A0A),
    errorContainer: Color(0xFF5B1A1A),
    onErrorContainer: Color(0xFFFECACA),
    outline: Color(0xFF94A3B8),
    outlineVariant: Color(0xFF334155),
    shadow: Color(0x66000000),
    scrim: Color(0xCC020617),
  );

  static ThemeData get lightTheme => _buildTheme(
        colorScheme: _lightColorScheme,
        semanticColors: AppSemanticColors.light,
        scaffoldBackground: backgroundLight,
        secondaryText: _lightTextSecondary,
      );

  static ThemeData get darkTheme => _buildTheme(
        colorScheme: _darkColorScheme,
        semanticColors: AppSemanticColors.dark,
        scaffoldBackground: backgroundDark,
        secondaryText: _darkTextSecondary,
      );

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required AppSemanticColors semanticColors,
    required Color scaffoldBackground,
    required Color secondaryText,
  }) {
    final textTheme = _textTheme(colorScheme.onSurface, secondaryText);
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: semanticColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      primaryColor: colorScheme.primary,
      scaffoldBackgroundColor: scaffoldBackground,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardTheme(
        color: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: semanticColors.border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          disabledBackgroundColor: colorScheme.onSurface.withOpacity(0.12),
          disabledForegroundColor: colorScheme.onSurface.withOpacity(0.46),
          elevation: 0,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          side: BorderSide(color: colorScheme.outlineVariant),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
        hintStyle: textTheme.bodyMedium?.copyWith(color: secondaryText),
        helperStyle: textTheme.bodySmall?.copyWith(color: secondaryText),
        errorStyle: textTheme.bodySmall?.copyWith(color: colorScheme.error),
        prefixIconColor: secondaryText,
        suffixIconColor: secondaryText,
        border: fieldBorder,
        enabledBorder: fieldBorder,
        disabledBorder: fieldBorder.copyWith(
          borderSide: BorderSide(
            color: semanticColors.border.withOpacity(0.6),
          ),
        ),
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colorScheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colorScheme.primary : secondaryText,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? colorScheme.primary : secondaryText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      dividerTheme: DividerThemeData(
        color: semanticColors.border,
        thickness: 1,
        space: 24,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: colorScheme.primaryContainer,
        circularTrackColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.surface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondaryText,
        textColor: colorScheme.onSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  static TextTheme _textTheme(Color primaryText, Color secondaryText) {
    return TextTheme(
      displaySmall: TextStyle(
        color: primaryText,
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineLarge: TextStyle(
        color: primaryText,
        fontSize: 28,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineMedium: TextStyle(
        color: primaryText,
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      headlineSmall: TextStyle(
        color: primaryText,
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        color: primaryText,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: primaryText,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: TextStyle(
        color: primaryText,
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: primaryText,
        fontSize: 16,
        height: 1.5,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: primaryText,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: secondaryText,
        fontSize: 12,
        height: 1.4,
        fontWeight: FontWeight.w400,
      ),
      labelLarge: TextStyle(
        color: primaryText,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      labelMedium: TextStyle(
        color: primaryText,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: TextStyle(
        color: secondaryText,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
