import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brands/example/example.dart';
import 'app_localizations.dart';
import 'locale_preference_provider.dart';

class LanguagePicker extends ConsumerWidget {
  const LanguagePicker({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(localePreferenceProvider);
    final name = selected == null
        ? context.tr('Device language')
        : appLanguages.firstWhere((l) => l.code == selected.languageCode).name;
    if (compact) {
      return TextButton.icon(
        onPressed: () => _show(context, ref),
        icon: const Icon(Icons.language),
        label: Text(name),
      );
    }
    if (context.isExampleTheme) {
      return ExampleRow(
        leading: ExampleIconTile(
            icon: Icons.language, color: Theme.of(context).colorScheme.primary),
        title: context.tr('Language'),
        subtitle: name,
        trailing: ExampleRow.chevron,
        onTap: () => _show(context, ref),
      );
    }
    return Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: const Icon(Icons.language),
          title: Text(context.tr('Language')),
          subtitle: Text(name),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _show(context, ref),
        ));
  }

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    final selected =
        ref.read(localePreferenceProvider)?.languageCode ?? 'system';
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('Language'),
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final language in [
                    AppLanguage('system', context.tr('Device language')),
                    ...appLanguages,
                  ])
                    ListTile(
                      title: Text(language.name),
                      selected: selected == language.code,
                      trailing: selected == language.code
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, language.code),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (code == null || !context.mounted) return;
    try {
      await ref
          .read(localePreferenceProvider.notifier)
          .setLocale(code == 'system' ? null : Locale(code));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('Could not save language. Try again.'))),
      );
    }
  }
}
