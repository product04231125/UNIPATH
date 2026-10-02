import 'package:flutter/material.dart';

/// Semantic sizes shared by the Web and Windows workspace.
abstract final class AppTypography {
  static const double caption = 13;
  static const double body = 14;
  static const double section = 18;
  static const double page = 26;

  static const TextStyle bodyStyle = TextStyle(fontSize: body, height: 1.5);
  static const TextStyle captionStyle = TextStyle(
    fontSize: caption,
    height: 1.5,
  );
  static const TextStyle sectionStyle = TextStyle(
    fontSize: section,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle pageStyle = TextStyle(
    fontSize: page,
    height: 1.3,
    fontWeight: FontWeight.w700,
  );

  static TextTheme apply(TextTheme base) => base.copyWith(
    displayLarge: pageStyle,
    displayMedium: pageStyle,
    displaySmall: pageStyle,
    headlineLarge: pageStyle,
    headlineMedium: pageStyle,
    headlineSmall: pageStyle,
    titleLarge: sectionStyle,
    titleMedium: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    titleSmall: bodyStyle.copyWith(fontWeight: FontWeight.w700),
    bodyLarge: bodyStyle,
    bodyMedium: bodyStyle,
    bodySmall: captionStyle,
    labelLarge: bodyStyle.copyWith(fontWeight: FontWeight.w600),
    labelMedium: captionStyle.copyWith(fontWeight: FontWeight.w600),
    labelSmall: captionStyle,
  );
}
