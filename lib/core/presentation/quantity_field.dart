import 'package:flutter/material.dart';

/// A quantity input whose first focus replaces its initial value by typing.
///
/// Focusing never clears the value. After the first focus, ordinary taps and
/// cursor movement are left untouched. Change [resetToken] after saving a new
/// item to make the next draft select its default again.
class QuantityField extends StatefulWidget {
  const QuantityField({
    required this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(labelText: 'Quantity'),
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.resetToken,
    this.textInputAction,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool autofocus;
  final Object? resetToken;
  final TextInputAction? textInputAction;

  @override
  State<QuantityField> createState() => _QuantityFieldState();
}

class _QuantityFieldState extends State<QuantityField> {
  late FocusNode _focus;
  bool _ownsFocus = false;
  bool _selectOnNextFocus = true;
  int _selectionGeneration = 0;

  @override
  void initState() {
    super.initState();
    _attachFocus();
  }

  void _attachFocus() {
    _ownsFocus = widget.focusNode == null;
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_handleFocus);
  }

  void _detachFocus() {
    _focus.removeListener(_handleFocus);
    if (_ownsFocus) _focus.dispose();
  }

  @override
  void didUpdateWidget(QuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFocus();
      _attachFocus();
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.resetToken != widget.resetToken) {
      _selectOnNextFocus = true;
      _selectionGeneration++;
    }
    if (_focus.hasFocus) _handleFocus();
  }

  void _handleFocus() {
    if (!_focus.hasFocus || !_selectOnNextFocus || !widget.enabled) return;
    _selectOnNextFocus = false;
    final generation = ++_selectionGeneration;
    final controller = widget.controller;
    final text = controller.text;
    // Tap-to-position runs after focus acquisition. Apply selection after that
    // gesture so mouse, touch and keyboard focus all have the same behavior.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _selectionGeneration ||
          !_focus.hasFocus ||
          controller != widget.controller ||
          controller.text != text) {
        return;
      }
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
    });
  }

  @override
  void dispose() {
    _selectionGeneration++;
    _detachFocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    focusNode: _focus,
    decoration: widget.decoration,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    // Desktop defaults otherwise select everything on every focus.
    selectAllOnFocus: false,
    textInputAction: widget.textInputAction,
    onChanged: widget.onChanged,
    onFieldSubmitted: widget.onFieldSubmitted,
    validator: widget.validator,
    enabled: widget.enabled,
    autofocus: widget.autofocus,
  );
}
