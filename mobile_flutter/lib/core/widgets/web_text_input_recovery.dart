import 'dart:async';
import 'package:flutter/material.dart';
import '../web/web_text_input_probe.dart';

/// Reconnects a desktop Chromium editor only when Flutter still owns focus but
/// the browser has lost its native text input. Does not reset values or reload.
class WebTextInputRecovery extends StatefulWidget {
  const WebTextInputRecovery({required this.child, this.probe, super.key});
  final Widget child;
  final WebTextInputProbe? probe;
  @override
  State<WebTextInputRecovery> createState() => _WebTextInputRecoveryState();
}

class _WebTextInputRecoveryState extends State<WebTextInputRecovery> {
  late final WebTextInputProbe _probe;
  void Function()? _stopListening;
  bool _checkPending = false;
  bool _reconnecting = false;
  int _pointerEpoch = 0;
  int _repairGeneration = 0;
  Offset? _pendingPointer;
  FocusNode? _lastAttempt;
  DateTime? _retryAfter;
  Timer? _connectionCheck;
  @override
  void initState() {
    super.initState();
    _probe = widget.probe ?? createWebTextInputProbe();
    if (_probe.supported) {
      _stopListening = _probe.listen(_scheduleCheck);
      // Chrome can lose its editor without delivering a window-focus event.
      // Healthy/idle fields do not schedule a frame or change their connection.
      _connectionCheck = Timer.periodic(const Duration(seconds: 1), (_) {
        final editable = FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>();
        if (editable != null &&
            !editable.widget.readOnly &&
            _probe.documentFocused &&
            !_probe.editingElementFocused) {
          _scheduleCheck();
        }
      });
    }
  }

  void _scheduleCheck([Offset? pointerPosition]) {
    if (!_probe.supported || _reconnecting || !mounted) return;
    if (pointerPosition != null) _pendingPointer = pointerPosition;
    if (_checkPending) return;
    _checkPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPending = false;
      final pointer = _pendingPointer;
      _pendingPointer = null;
      _recoverIfDisconnected(pointer);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _recoverIfDisconnected(Offset? pointerPosition) {
    if (!mounted || !_probe.documentFocused || _probe.editingElementFocused) {
      return;
    }
    final focus = FocusManager.instance.primaryFocus;
    final editable =
        focus?.context?.findAncestorStateOfType<EditableTextState>();
    if (focus == null ||
        editable == null ||
        !editable.mounted ||
        !focus.hasFocus ||
        !focus.canRequestFocus ||
        editable.widget.readOnly ||
        ModalRoute.of(editable.context)?.isCurrent != true) {
      return;
    }
    if (pointerPosition != null) {
      BuildContext fieldContext = editable.context;
      editable.context.visitAncestorElements((element) {
        if (element.widget is TextField) {
          fieldContext = element;
          return false;
        }
        return true;
      });
      final box = fieldContext.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          !(box.localToGlobal(Offset.zero) & box.size)
              .contains(pointerPosition)) {
        return;
      }
    }
    final controller = editable.widget.controller;
    final value = controller.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    if (pointerPosition == null &&
        _lastAttempt == focus &&
        _retryAfter?.isAfter(DateTime.now()) == true) {
      return;
    }
    _lastAttempt = focus;
    _retryAfter = DateTime.now().add(const Duration(seconds: 5));
    _reconnecting = true;
    final generation = ++_repairGeneration;
    final pointerEpoch = _pointerEpoch;
    // Let the blur reach both Flutter's client and its HTML semantics node
    // before reopening. Reopening in the same frame can retain a stale editor.
    focus.unfocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
    final afterBlur = FocusManager.instance.primaryFocus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _repairGeneration) return;
      if (_pointerEpoch != pointerEpoch ||
          !editable.mounted ||
          !focus.canRequestFocus ||
          !_probe.documentFocused ||
          ModalRoute.of(editable.context)?.isCurrent != true ||
          (FocusManager.instance.primaryFocus != afterBlur &&
              FocusManager.instance.primaryFocus != focus)) {
        _reconnecting = false;
        return;
      }
      focus.requestFocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      void preserveSelection() {
        if (value.selection.isValid &&
            controller.text == value.text &&
            controller.selection != value.selection) {
          controller.selection = value.selection;
        }
      }

      preserveSelection();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _repairGeneration) return;
        _reconnecting = false;
        if (!mounted ||
            !editable.mounted ||
            !focus.hasFocus ||
            !_probe.documentFocused) {
          return;
        }
        editable.requestKeyboard();
        preserveSelection();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _connectionCheck?.cancel();
    _stopListening?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _probe.supported
      ? Listener(
          onPointerDown: (_) {
            _pointerEpoch++;
            if (_reconnecting) {
              _repairGeneration++;
              _reconnecting = false;
            }
          },
          onPointerUp: (event) => _scheduleCheck(event.position),
          child: widget.child)
      : widget.child;
}
