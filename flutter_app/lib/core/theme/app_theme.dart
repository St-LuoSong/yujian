import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Material 3 theme for 豫见智旅 v0.3.
///
/// v0.2 flattened everything (no elevation, no splash, one 2dp radius) which
/// made the product read as a wireframe. v0.3 restores soft depth and real
/// touch feedback, but keeps the deliberate choices: no gold, no gradient
/// sweep, one dark brand surface and one warm price accent.
abstract final class AppTheme {
  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.celadon,
      brightness: Brightness.light,
    ).copyWith(
      surface: AppColors.ground,
      primary: AppColors.celadon,
      onPrimary: AppColors.onInk,
      secondary: AppColors.amber,
      error: AppColors.kilnRed,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.ground,
      // Default M3 ripple: the APK needs a visible press response. v0.2 turned
      // it off, which is a large part of why the interface felt inert.
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          color: AppColors.ink,
          fontSize: AppTypography.body,
          height: AppTypography.lineHeight,
        ),
        bodySmall: TextStyle(
          color: AppColors.crackle,
          fontSize: AppTypography.secondary,
          height: AppTypography.lineHeight,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: AppTypography.cardTitle,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppSpacing.radiusCard),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.celadonPale,
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.celadonDeep
                : AppColors.crackle,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) => TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.celadonDeep
                : AppColors.crackle,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.celadonDeep,
          foregroundColor: AppColors.onInk,
          disabledBackgroundColor: AppColors.surfaceSunken,
          disabledForegroundColor: AppColors.crackle,
          elevation: 0,
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppSpacing.radiusControl),
            ),
          ),
          textStyle: const TextStyle(
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.celadonDeep,
          backgroundColor: AppColors.surface,
          minimumSize: const Size(0, AppSpacing.buttonHeight),
          side: const BorderSide(color: AppColors.celadonPale),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(AppSpacing.radiusControl),
            ),
          ),
          textStyle: const TextStyle(
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.celadonDeep,
          minimumSize: const Size(0, AppSpacing.minTouchTarget),
          textStyle: const TextStyle(
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.celadonDeep,
          minimumSize: const Size(
            AppSpacing.minTouchTarget,
            AppSpacing.minTouchTarget,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(
          color: AppColors.crackle,
          fontSize: AppTypography.body,
        ),
        border: _fieldBorder(AppColors.hairline),
        enabledBorder: _fieldBorder(AppColors.hairline),
        focusedBorder: _fieldBorder(AppColors.celadon, width: 1.5),
        errorBorder: _fieldBorder(AppColors.kilnRed),
        focusedErrorBorder: _fieldBorder(AppColors.kilnRed, width: 1.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.celadonDeep,
        side: const BorderSide(color: AppColors.hairline),
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          fontSize: AppTypography.secondary,
          color: AppColors.inkSoft,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: AppTypography.secondary,
          color: AppColors.onInk,
          fontWeight: FontWeight.w700,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        showCheckmark: false,
        surfaceTintColor: Colors.transparent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? AppColors.onInk
                : AppColors.crackle,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => states.contains(WidgetState.selected)
                ? AppColors.celadonDeep
                : AppColors.surface,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.hairline),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(AppSpacing.radiusControl),
              ),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: AppTypography.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.celadon,
        inactiveTrackColor: AppColors.celadonPale,
        thumbColor: AppColors.surface,
        overlayColor: Color(0x1A2F6F68),
        trackHeight: 4,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: AppSpacing.hairline,
        space: AppSpacing.hairline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(
          color: AppColors.onInk,
          fontSize: AppTypography.secondary,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppSpacing.radiusControl),
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusCard),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(AppSpacing.radiusCard),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.celadon,
        textColor: AppColors.ink,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.celadon,
        linearTrackColor: AppColors.celadonPale,
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );
}
