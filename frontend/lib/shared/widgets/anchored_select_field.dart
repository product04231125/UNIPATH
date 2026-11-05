import 'dart:math' as math;

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

    /// Title-bar density: no floating label, tight padding for a 48px strip.
    this.compact = false,
  });
  final T value;
  final String label;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final bool searchable;
  final String searchLabel;
  final bool externalLabel;
  final bool compact;

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
  Widget build(BuildContext context) {
    final menu = _menu(context);
    if (widget.externalLabel && !widget.compact) {
      return FieldLabel(label: widget.label, child: menu);
    }
    return menu;
  }

  ({double below, double above, double fieldHeight}) _space(
    BuildContext context,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) {
      return (below: 320, above: 0, fieldHeight: 48);
    }
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    return (
      below: screen.height - padding.bottom - origin.dy - box.size.height - 12,
      above: origin.dy - padding.top - 12,
      fieldHeight: box.size.height,
    );
  }

  Widget _menu(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final space = widget.searchable ? _space(context) : null;
      final menuHeight = space == null
          ? 320.0
          : math
                .min(320, math.max(space.below, space.above))
                .clamp(160, 320)
                .toDouble();
      final openAbove =
          space != null &&
          space.below < menuHeight &&
          space.above >= space.below;
      return MenuAnchor(
        childFocusNode: _focus,
        crossAxisUnconstrained: false,
        alignmentOffset: openAbove
            ? Offset(0, -(menuHeight + space!.fieldHeight + 4))
            : const Offset(0, 4),
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
          maximumSize: WidgetStatePropertyAll(
            Size(constraints.maxWidth, menuHeight),
          ),
        ),
        menuChildren: [
          if (widget.searchable)
            SizedBox(
              height: menuHeight - 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel(
                    label: widget.searchLabel,
                    child: TextField(
                      key: const ValueKey('select-search-input'),
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filtered.isEmpty
                        ? const Text('검색에 맞는 항목이 없습니다.')
                      : ListView(
                          primary: false,
                          children: [
                              for (final option in _filtered)
                                _optionButton(context, option),
                            ],
                          ),
                  ),
                ],
              ),
            )
          else
            for (final option in widget.options) _optionButton(context, option),
        ],
        builder: (context, controller, _) => Semantics(
          label: widget.label,
          child: InkWell(
            focusNode: _focus,
            borderRadius: BorderRadius.circular(widget.compact ? 12 : 20),
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: InputDecorator(
              isEmpty: false,
              decoration: InputDecoration(
                labelText: widget.externalLabel || widget.compact
                    ? null
                    : widget.label,
                floatingLabelBehavior: widget.compact
                    ? FloatingLabelBehavior.never
                    : null,
                isDense: widget.compact,
                contentPadding: widget.compact
                    ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.options
                          .firstWhere((option) => option.value == widget.value)
                          .label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.expand_more, size: widget.compact ? 18 : 24),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  List<SelectOption<T>> get _filtered => [
    for (final option in widget.options)
      if (!widget.searchable || option.label.toLowerCase().contains(_query))
        option,
  ];

  Widget _optionButton(BuildContext context, SelectOption<T> option) =>
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
          MenuController.maybeOf(context)?.close();
          _focus.requestFocus();
        },
        leadingIcon: Icon(
          option.value == widget.value ? Icons.check : null,
          size: 18,
        ),
        child: Text(option.label),
      );
}
