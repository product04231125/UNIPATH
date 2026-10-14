import 'package:flutter/material.dart';

class SelectOption<T> {
  const SelectOption(this.value, this.label);
  final T value;
  final String label;
}

/// A keyboard-accessible selection menu anchored to its field, not its value.
class AnchoredSelectField<T> extends StatefulWidget {
  const AnchoredSelectField({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final String label;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  State<AnchoredSelectField<T>> createState() => _AnchoredSelectFieldState<T>();
}

class _AnchoredSelectFieldState<T> extends State<AnchoredSelectField<T>> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      childFocusNode: _focus,
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(0, 4),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surface,
        ),
        elevation: const WidgetStatePropertyAll(4),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 320)),
      ),
      menuChildren: [
        for (final option in widget.options)
          MenuItemButton(
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              foregroundColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.onSurface,
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                final colors = Theme.of(context).colorScheme;
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return colors.onSurface.withValues(alpha: .10);
                }
                return option.value == widget.value
                    ? colors.primaryContainer
                    : null;
              }),
            ),
            onPressed: () {
              widget.onChanged(option.value);
              _focus.requestFocus();
            },
            leadingIcon: Icon(
              option.value == widget.value ? Icons.check : null,
              size: 18,
            ),
            child: Text(option.label),
          ),
      ],
      builder: (context, controller, _) => Semantics(
        label: widget.label,
        child: InkWell(
          focusNode: _focus,
          borderRadius: BorderRadius.circular(20),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: InputDecorator(
            decoration: InputDecoration(labelText: widget.label),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.options
                        .firstWhere((option) => option.value == widget.value)
                        .label,
                  ),
                ),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
