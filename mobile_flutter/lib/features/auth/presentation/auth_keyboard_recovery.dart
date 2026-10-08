import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Reconnect a focused Android web input after its soft keyboard was dismissed.
///
/// Android can hide the keyboard without blurring the field. Flutter web's
/// TextInput.show then does nothing because the engine still considers itself
/// editing. A fresh focus/input connection restores the DOM input on the user's
/// tap. Keep the connection intact while the keyboard is visible, so selection,
/// composition and password-manager input are not interrupted.
void recoverAuthKeyboard(BuildContext context, FocusNode focusNode) {
  if (!kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      !focusNode.hasFocus ||
      View.of(context).viewInsets.bottom > 0) {
    return;
  }
  focusNode.unfocus();
  // Flush the blur before requesting focus again; otherwise Flutter coalesces
  // them into no change and keeps the stale web input connection.
  FocusManager.instance.applyFocusChangesIfNeeded();
  focusNode.requestFocus();
}
