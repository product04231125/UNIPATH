import 'package:flutter/material.dart';

import 'content_scroll_view.dart';
import 'task_focus_group.dart';

/// Result of the leave/discard confirmation for unsaved input.
enum InputDiscardAction {
  /// Keep editing; do not leave.
  cancel,

  /// Persist a client draft (caller/`onTempSave`) then leave.
  tempSave,

  /// Discard unsaved input and leave.
  discard,
}

/// Asks whether to keep editing, temp-save, or discard unsaved input.
///
/// When [onTempSave] is provided and the user chooses temp-save, it is awaited
/// first. A failed or false result keeps the dialog outcome as [InputDiscardAction.cancel].
Future<InputDiscardAction> confirmInputDiscard(
  BuildContext context, {
  Future<bool> Function()? onTempSave,
}) async {
  final previousFocus = FocusManager.instance.primaryFocus;
  final choice = await showDialog<InputDiscardAction>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('작성한 내용을 폐기할까요?'),
        actions: [
          TextButton(
            key: const Key('input-discard-cancel'),
            autofocus: true,
            onPressed: () => Navigator.pop(context, InputDiscardAction.cancel),
            child: const Text('취소'),
          ),
          TextButton(
            key: const Key('input-discard-temp-save'),
            onPressed: () => Navigator.pop(context, InputDiscardAction.tempSave),
            child: const Text('임시저장'),
          ),
          FilledButton(
            key: const Key('input-discard-delete'),
            onPressed: () => Navigator.pop(context, InputDiscardAction.discard),
            child: const Text('삭제'),
          ),
        ],
      ),
    ),
  );
  final action = choice ?? InputDiscardAction.cancel;
  if (action == InputDiscardAction.tempSave) {
    if (onTempSave == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 화면에서는 아직 임시저장할 수 없습니다.')),
        );
      }
      if (context.mounted) previousFocus?.requestFocus();
      return InputDiscardAction.cancel;
    }
    final saved = await onTempSave();
    if (!saved) {
      if (context.mounted) previousFocus?.requestFocus();
      return InputDiscardAction.cancel;
    }
  }
  if (action == InputDiscardAction.cancel && context.mounted) {
    previousFocus?.requestFocus();
  }
  return action;
}

/// True when the user chose to leave after discard or a successful temp-save.
Future<bool> confirmInputDiscardAllowsLeave(
  BuildContext context, {
  Future<bool> Function()? onTempSave,
}) async {
  final action = await confirmInputDiscard(context, onTempSave: onTempSave);
  return action == InputDiscardAction.tempSave ||
      action == InputDiscardAction.discard;
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
  Future<bool> Function()? onTempSave;
  bool saving = false;
  bool confirming = false;

  Future<void> cancel(BuildContext context, T? result) async {
    if (saving || confirming || !isCurrent) return;
    if (hasUnsavedChanges?.call() == true) {
      confirming = true;
      final action = await confirmInputDiscard(
        context,
        onTempSave: onTempSave,
      );
      confirming = false;
      if (action == InputDiscardAction.cancel) return;
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
    this.onTempSave,
    this.saving = false,
    this.editing = false,
  });
  final Widget title;
  final Widget content;
  final List<Widget> actions;
  final bool Function() hasContent;
  final Listenable changes;
  final bool Function()? hasUnsavedChanges;
  final Future<bool> Function()? onTempSave;
  final bool saving;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route is _InputDialogRoute) {
      route.saving = saving;
      route.hasUnsavedChanges = hasUnsavedChanges ?? hasContent;
      route.onTempSave = onTempSave;
      route.allowImplicitDismiss = () => !saving && !editing && !hasContent();
    }
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return AnimatedBuilder(
      animation: changes,
      builder: (context, _) => PopScope(
        canPop: !saving && !editing && !hasContent(),
        child: TaskFocusGroup(
          child: Dialog(
            insetPadding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + viewInsets.bottom,
            ),
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
      ),
    );
  }
}
