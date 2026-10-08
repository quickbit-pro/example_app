import 'package:flutter/widgets.dart';

/// Native platforms report their insets through the view; nothing to add.
class WebSafeArea {
  static EdgeInsets insets() => EdgeInsets.zero;
}
