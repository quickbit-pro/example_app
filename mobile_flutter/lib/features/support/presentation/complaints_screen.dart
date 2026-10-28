import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../platform/application/platform_providers.dart';
import '../../signup/presentation/legal_agreements.dart';

class ComplaintsScreen extends ConsumerStatefulWidget {
  const ComplaintsScreen({super.key});
  @override
  ConsumerState<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends ConsumerState<ComplaintsScreen> {
  String? _error;
  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mobileTenantConfigProvider).valueOrNull;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Complaints')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Let us know what went wrong',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text(
                'Equals Money provides the banking accounts and payment services identified as Equals Money in this app. You can raise a complaint with us or contact Equals Money directly. The choice is yours.'),
            const SizedBox(height: 28),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.chat_bubble_outline, size: 30),
                          const SizedBox(height: 16),
                          Text('Raise a complaint with us',
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 12),
                          const Text(
                              'We will pass your complaint to Equals Money, who will assess it and contact you. We do not decide whether your complaint is justified. If you are unsure which provider is involved, you can still raise it here.'),
                          const SizedBox(height: 20),
                          FilledButton(
                              onPressed: () =>
                                  context.push('/support/new?complaint=true'),
                              child: const Text('Make a complaint')),
                          TextButton(
                              onPressed: () => context.push('/support'),
                              child: const Text(
                                  'View my complaints and support tickets')),
                        ]))),
            const SizedBox(height: 16),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Contact Equals Money directly',
                              style: theme.textTheme.titleLarge),
                          const SizedBox(height: 12),
                          const Text(
                              'Their complaints page explains how to complain, how complaints are handled, and your escalation options.'),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                              onPressed: () async {
                                setState(() => _error = null);
                                try {
                                  if (await launchUrl(
                                      Uri.parse(equalsComplaintsUrl(config
                                          ?.equalsRegulatoryRegionDefault)),
                                      mode: LaunchMode.externalApplication)) {
                                    return;
                                  }
                                } catch (_) {}
                                if (mounted) {
                                  setState(() => _error =
                                      'The complaints page could not be opened. Please try again.');
                                }
                              },
                              icon: const Icon(Icons.open_in_new),
                              label: const Text(
                                  'Equals Money complaints procedure')),
                          if (_error != null)
                            Text(_error!,
                                style:
                                    TextStyle(color: theme.colorScheme.error)),
                        ]))),
          ]),
        )),
      ),
    );
  }
}
