import 'package:flutter/material.dart';

import 'content_scroll_view.dart';

Future<bool> confirmInputDiscard(BuildContext context) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final discard = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('작성한 내용을 폐기할까요?'),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 작성'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('내용 폐기'),
          ),
        ],
      ),
    ),
  );
  if (discard != true && context.mounted) previousFocus?.requestFocus();
  return discard == true;
}

/// Input routes are dismissible only while the shared dialog reports empty.
/// Wait for the exit animation before callers dispose their form controllers.
Future<T?> showInputDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = _InputDialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

class _InputDialogRoute<T> extends DialogRoute<T> {
  _InputDialogRoute({required super.context, required super.builder});
  bool Function()? allowImplicitDismiss;
  bool Function()? hasUnsavedChanges;
  bool saving = false;
  bool confirming = false;

  Future<void> cancel(BuildContext context, T? result) async {
    if (saving || confirming || !isCurrent) return;
    if (hasUnsavedChanges?.call() == true) {
      confirming = true;
      final discard = await confirmInputDiscard(context);
      confirming = false;
      if (discard != true) return;
    }
    if (isCurrent && !saving) navigator?.pop(result);
  }

  @override
  Widget buildModalBarrier() => AnimatedModalBarrier(
    color: animation!.drive(
      ColorTween(begin: Colors.transparent, end: barrierColor),
    ),
    dismissible: true,
    semanticsLabel: barrierLabel,
    onDismiss: () {
      // Read current values at the click, including edits before the next frame.
      if (isCurrent && allowImplicitDismiss?.call() == true) navigator?.pop();
    },
  );
}

/// Shared multi-field form shell. Features own content/default interpretation.
/// Cancellation confirms changed input; successful saves may pop directly.
class InputDialog extends StatelessWidget {
  static Future<void> cancel<T>(BuildContext context, [T? result]) async {
    final route = ModalRoute.of(context);
    if (route is _InputDialogRoute<T>) await route.cancel(context, result);
  }

  const InputDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    required this.hasContent,
    required this.changes,
    this.hasUnsavedChanges,
    this.saving = false,
    this.editing = false,
  });
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final bool Function() hasContent;
  final Listenable changes;
  final bool Function()? hasUnsavedChanges;
  final bool saving;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is _InputDialogRoute) {
      route.saving = saving;
      route.hasUnsavedChanges = hasUnsavedChanges ?? hasContent;
      route.allowImplicitDismiss = () => !saving && !editing && !hasContent();
    }
    return AnimatedBuilder(
      animation: changes,
      builder: (context, _) => PopScope(
        canPop: !saving && !editing && !hasContent(),
        child: Dialog(
          insetPadding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            key: const Key('input-dialog-surface'),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.titleLarge!,
                    child: title,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(child: ContentScrollView(child: content)),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
