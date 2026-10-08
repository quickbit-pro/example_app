import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/web/web_safe_area_padding.dart';

void main() {
  Widget host(EdgeInsets insets, {EdgeInsets viewInsets = EdgeInsets.zero}) =>
      MediaQuery(
        data:
            MediaQueryData(size: const Size(393, 852), viewInsets: viewInsets),
        child: WebSafeAreaPadding(
          insets: () => insets,
          child: Builder(
            builder: (context) => SafeArea(
              child: Container(key: const ValueKey('content')),
            ),
          ),
        ),
      );

  Rect contentRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('content')));

  testWidgets('page insets become the padding SafeArea keeps clear',
      (tester) async {
    await tester.pumpWidget(
      host(const EdgeInsets.only(top: 59, bottom: 34)),
    );
    final rect = contentRect(tester);
    final surface = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.top, 59);
    expect(rect.bottom, surface.height - 34);
  });

  testWidgets('the keyboard takes over the bottom inset', (tester) async {
    await tester.pumpWidget(
      host(
        const EdgeInsets.only(bottom: 34),
        viewInsets: const EdgeInsets.only(bottom: 300),
      ),
    );
    final context = tester.element(find.byKey(const ValueKey('content')));
    expect(MediaQuery.paddingOf(context).bottom, 0);
    expect(MediaQuery.viewPaddingOf(context).bottom, 34);
  });

  testWidgets('no insets leaves the tree untouched', (tester) async {
    await tester.pumpWidget(host(EdgeInsets.zero));
    final surface = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(contentRect(tester), Offset.zero & surface);
  });
}
