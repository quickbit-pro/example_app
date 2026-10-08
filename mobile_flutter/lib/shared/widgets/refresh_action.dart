import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/widgets/app_states.dart';

/// Explicit refresh with one request at a time and visible failure feedback.
class RefreshAction extends StatefulWidget {
  const RefreshAction({required this.onRefresh, super.key});
  final Future<void> Function() onRefresh;
  @override
  State<RefreshAction> createState() => _RefreshActionState();
}

class _RefreshActionState extends State<RefreshAction> {
  bool _busy = false;
  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.tr(friendlyErrorMessage(error)))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: context.tr('Refresh'),
        onPressed: _busy ? null : _refresh,
        icon: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded),
      );
}
