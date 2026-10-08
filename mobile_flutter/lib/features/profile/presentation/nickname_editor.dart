import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/identity/user_nickname.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';

Future<void> showNicknameEditor(BuildContext context, String? nickname) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NicknameEditor(nickname: nickname),
    );

class NicknameEditor extends ConsumerStatefulWidget {
  const NicknameEditor({super.key, this.nickname});

  final String? nickname;

  @override
  ConsumerState<NicknameEditor> createState() => _NicknameEditorState();
}

class _NicknameEditorState extends ConsumerState<NicknameEditor> {
  late final _controller = TextEditingController(text: widget.nickname ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final raw = _controller.text.trim();
    final nickname = normalizeNickname(raw);
    if (raw.isNotEmpty && !isValidNickname(nickname)) {
      setState(() => _error = context.tr(nicknameRules));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(mobilePlatformApiProvider)
          .updateProfile(nickname: nickname);
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(context.tr('Nickname')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(
                    'People can find you by your unique nickname to split a bill, send money or request money.')),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  enabled: !_saving,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  onChanged: (_) => setState(() => _error = null),
                  decoration: InputDecoration(
                    labelText: context.tr('Nickname'),
                    prefixText: '@',
                    helperText: context.tr(nicknameRules),
                    helperMaxLines: 3,
                    errorText: _error,
                    errorMaxLines: 4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(context.tr(
                    'Nicknames are not case-sensitive. Leave blank to remove yours.')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(context.tr(_saving ? 'Saving…' : 'Save')),
            ),
          ],
        ),
      );
}
