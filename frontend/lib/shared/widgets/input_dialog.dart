import 'package:flutter/material.dart';

import 'content_scroll_view.dart';

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
/// Explicit cancel and successful save may pop; implicit dismissal is guarded.
class InputDialog extends StatelessWidget {
  const InputDialog({
    super.key,
    required this.title,
    required this.content,
    required this.actions,
    required this.hasContent,
    required this.changes,
    this.saving = false,
    this.editing = false,
  });
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final bool Function() hasContent;
  final Listenable changes;
  final bool saving;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is _InputDialogRoute) {
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
