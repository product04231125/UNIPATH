import 'package:flutter/material.dart';

import 'field_label.dart';

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
    this.searchable = false,
    this.searchLabel = '검색',
    this.externalLabel = false,
  });
  final T value;
  final String label;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool searchable;
  final String searchLabel;
  final bool externalLabel;

  @override
  State<AnchoredSelectField<T>> createState() => _AnchoredSelectFieldState<T>();
}

class _AnchoredSelectFieldState<T> extends State<AnchoredSelectField<T>> {
  final _focus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.externalLabel
      ? FieldLabel(label: widget.label, child: _menu(context))
      : _menu(context);

  Widget _menu(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => MenuAnchor(
      childFocusNode: _focus,
      crossAxisUnconstrained: false,
      alignmentOffset: const Offset(0, 4),
      onOpen: () {
        if (widget.searchable) setState(() => _query = '');
      },
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
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: const ValueKey('select-search-input'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.searchLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
        if (widget.searchable &&
            !widget.options.any(
              (option) => option.label.toLowerCase().contains(_query),
            ))
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('검색에 맞는 항목이 없습니다.'),
          ),
        for (final option in widget.options.where(
          (option) =>
              !widget.searchable || option.label.toLowerCase().contains(_query),
        ))
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
            decoration: InputDecoration(
              labelText: widget.externalLabel ? null : widget.label,
            ),
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
