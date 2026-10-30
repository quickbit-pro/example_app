import 'dart:async';

import 'package:flutter/material.dart';

/// Keeps the whole active input visible as keyboards reduce available space.
/// Covers native insets and mobile browsers that resize the viewport instead.
class KeyboardFocusVisibility extends StatefulWidget {
  const KeyboardFocusVisibility({required this.child, super.key});

  final Widget child;

  @override
  State<KeyboardFocusVisibility> createState() =>
      _KeyboardFocusVisibilityState();
}

class _KeyboardFocusVisibilityState extends State<KeyboardFocusVisibility>
    with WidgetsBindingObserver {
  double? _availableHeight;
  double? _viewHeight;
  Timer? _settledReveal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final view = View.of(context);
    _availableHeight = view.physicalSize.height - view.viewInsets.bottom;
    _viewHeight = view.physicalSize.height;
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final height = view.physicalSize.height - view.viewInsets.bottom;
    final viewportShrank =
        _viewHeight != null && view.physicalSize.height < _viewHeight!;
    _viewHeight = view.physicalSize.height;
    final previousHeight = _availableHeight;
    _availableHeight = height;
    _settledReveal?.cancel();
    if (previousHeight == null || height >= previousHeight) return;

    if (viewportShrank) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealFocusedField());
    }
    // Dialogs animate their keyboard padding after metrics change. Reveal
    // again when that transition finishes, using its final scroll viewport.
    _settledReveal =
        Timer(const Duration(milliseconds: 250), _revealFocusedField);
  }

  void _revealFocusedField() {
    if (!mounted) return;
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null ||
        !focusedContext.mounted ||
        focusedContext
                .findAncestorStateOfType<_KeyboardFocusVisibilityState>() !=
            this) {
      return;
    }
    // Include borders, labels and validation text, not only the caret line.
    BuildContext target = focusedContext;
    focusedContext.visitAncestorElements((element) {
      if (element.widget is TextField) {
        target = element;
        return false;
      }
      return true;
    });
    if (target == focusedContext) return; // Leave non-text focus alone.
    final fieldContext = focusedContext
        .findAncestorStateOfType<FormFieldState<String>>()
        ?.context;
    Scrollable.ensureVisible(
      fieldContext ?? target,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  void dispose() {
    _settledReveal?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
