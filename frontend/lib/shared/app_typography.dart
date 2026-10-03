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
    displayLarge: base.displayLarge?.merge(pageStyle),
    displayMedium: base.displayMedium?.merge(pageStyle),
    displaySmall: base.displaySmall?.merge(pageStyle),
    headlineLarge: base.headlineLarge?.merge(pageStyle),
    headlineMedium: base.headlineMedium?.merge(pageStyle),
    headlineSmall: base.headlineSmall?.merge(pageStyle),
    titleLarge: base.titleLarge?.merge(sectionStyle),
    titleMedium: base.titleMedium?.merge(
      bodyStyle.copyWith(fontWeight: FontWeight.w700),
    ),
    titleSmall: base.titleSmall?.merge(
      bodyStyle.copyWith(fontWeight: FontWeight.w700),
    ),
    bodyLarge: base.bodyLarge?.merge(bodyStyle),
    bodyMedium: base.bodyMedium?.merge(bodyStyle),
    bodySmall: base.bodySmall?.merge(captionStyle),
    labelLarge: base.labelLarge?.merge(
      bodyStyle.copyWith(fontWeight: FontWeight.w600),
    ),
    labelMedium: base.labelMedium?.merge(
      captionStyle.copyWith(fontWeight: FontWeight.w600),
    ),
    labelSmall: base.labelSmall?.merge(captionStyle),
  );
}
