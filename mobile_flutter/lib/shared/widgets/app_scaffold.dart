import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    this.title,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.extendBody = false,
    this.safeArea = true,
    super.key,
  });

  final Widget body;
  final String? title;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool extendBody;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = safeArea ? SafeArea(child: body) : body;

    return Scaffold(
      extendBody: extendBody,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              actions: actions,
            ),
      body: content,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

class AppScreenBody extends StatelessWidget {
  const AppScreenBody({
    required this.children,
    this.padding = AppSpacing.screenPadding,
    this.controller,
    super.key,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      padding: padding,
      children: children,
    );
  }
}
