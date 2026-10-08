import 'package:flutter/widgets.dart';

/// Re-record retained display lists after the browser restores a graphics surface.
/// Painting only RenderView reuses clean child repaint boundaries, which can
/// leave an unchanged screen blank after Android discards its backing surface.
void repaintApp(WidgetsBinding binding) {
  void invalidate(RenderObject object) {
    object.visitChildren(invalidate);
    object.markNeedsPaint();
  }

  for (final view in binding.renderViews) {
    invalidate(view);
  }
}
