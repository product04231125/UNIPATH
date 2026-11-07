import 'package:flutter/material.dart';

/// Shown under fields that use [FilteringTextInputFormatter.digitsOnly].
const digitsOnlyInputHint = '숫자만 입력할 수 있습니다.';

/// Red helper style for digits-only input guidance.
TextStyle digitsOnlyHelperStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!.copyWith(
      color: Theme.of(context).colorScheme.error,
    );

/// Merges the digits-only red helper into an [InputDecoration].
InputDecoration digitsOnlyDecoration(
  BuildContext context, {
  InputDecoration? base,
}) {
  final decoration = base ?? const InputDecoration();
  return decoration.copyWith(
    helperText: digitsOnlyInputHint,
    helperStyle: digitsOnlyHelperStyle(context),
    helperMaxLines: 2,
  );
}
