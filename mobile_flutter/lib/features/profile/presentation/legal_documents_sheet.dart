import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../brands/example/example.dart';
import '../../../core/api/dio_provider.dart';
import '../../platform/application/platform_providers.dart';
import '../../signup/presentation/legal_agreements.dart';
import 'security_sheets.dart';

Future<void> showLegalDocumentsSheet(BuildContext context) async {
  await showExampleSheet<void>(context,
      builder: (_) => const _LegalDocumentsContent());
}

class _LegalDocumentsContent extends ConsumerStatefulWidget {
  const _LegalDocumentsContent();

  @override
  ConsumerState<_LegalDocumentsContent> createState() =>
      _LegalDocumentsContentState();
}

class _LegalDocumentsContentState
    extends ConsumerState<_LegalDocumentsContent> {
  String? _error;

  Future<void> _open(LegalDocumentLink document) async {
    setState(() => _error = null);
    try {
      // Start from the tap, without dismissing the library or awaiting a
      // capability check: web/PWA browsers require the active user gesture.
      if (await launchUrl(Uri.parse(document.url!),
          mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // A failed browser or native handoff leaves all documents available.
    }
    if (mounted) {
      setState(
          () => _error = 'Could not open ${document.label}. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(mobileTenantConfigProvider);
    final appName = ref.watch(appConfigProvider).branding.appName;
    final documents =
        legalDocumentLibrary(tenant.valueOrNull, appName: appName);
    final example = context.isExampleTheme;
    final rows = [
      for (final document in documents)
        if (example)
          ExampleRow(
            leading: const ExampleIconTile(
                icon: Icons.description_outlined, color: ExampleColors.iris),
            title: document.label,
            subtitle: context.tr('Opens outside the app'),
            trailing: Icon(Icons.open_in_new_rounded,
                size: 18, color: ExampleInk.tertiary(context)),
            semanticsLabel: context
                .tr('{p0}, opens outside the app', {'p0': document.label}),
            onTap: () => _open(document),
          )
        else
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(document.label),
            subtitle: Text(context.tr('Opens outside the app')),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => _open(document),
          ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(title: context.tr('Legal documents')),
        const SizedBox(height: AppSpacing.sm),
        Text(context.tr(
            'Review the documents available during registration and card ordering.')),
        const SizedBox(height: AppSpacing.md),
        if (_error != null) ...[
          Semantics(
              liveRegion: true,
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (example) ExampleListGroup(children: rows) else ...rows,
        if (tenant.isLoading) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(context.tr('Loading additional company documents…')),
        ] else if (tenant.hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(context.tr('Additional company documents could not be loaded.')),
          TextButton(
              onPressed: () => ref.invalidate(mobileTenantConfigProvider),
              child: Text(context.tr('Retry'))),
        ],
      ],
    );
  }
}
