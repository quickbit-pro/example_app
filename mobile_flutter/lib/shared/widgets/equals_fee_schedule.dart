import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/dio_provider.dart';
import '../../features/platform/application/platform_providers.dart';

final equalsFeeScheduleProvider = FutureProvider.autoDispose<Map>((ref) async {
  final response =
      await ref.watch(dioProvider).get('/api/v1/mobile/onboarding/fees');
  final body = response.data;
  if (body is! Map) throw const FormatException('Invalid fee schedule');
  return body;
});

Future<void> showEqualsFeeSchedule(BuildContext context) => showDialog<void>(
    context: context, builder: (_) => const EqualsFeeScheduleDialog());

class EqualsFeeScheduleButton extends ConsumerWidget {
  const EqualsFeeScheduleButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled !=
        true) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Equals Money fees and billing'),
      onPressed: () => showEqualsFeeSchedule(context),
    );
  }
}

class EqualsFeeScheduleDialog extends ConsumerWidget {
  const EqualsFeeScheduleDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 600;
    final padding = compact ? 20.0 : 32.0;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SizedBox(
        width: 820,
        height: math.min(820, size.height - (compact ? 24 : 56)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(padding, padding, 12, 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(16)),
                child: Icon(Icons.receipt_long_outlined, color: colors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fees & billing',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Equals Money',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ]),
              ),
              IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ]),
          ),
          Divider(
              height: 1, color: colors.outlineVariant.withValues(alpha: .5)),
          Expanded(
            child: ref.watch(equalsFeeScheduleProvider).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _FeeScheduleMessage(
                    message:
                        'Your fee schedule could not be loaded. Please try again.',
                    action: TextButton.icon(
                        onPressed: () =>
                            ref.invalidate(equalsFeeScheduleProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry')),
                  ),
                  data: (body) {
                    final data = body['data'];
                    if (body['success'] != true || data is! Map) {
                      return _FeeScheduleMessage(
                          message: body['errorCode'] == 'NO_TIER_ASSIGNED'
                              ? 'Choose a plan to see your fee schedule.'
                              : 'No fee schedule is configured for your current plan. Contact support.');
                    }
                    final sections = (data['sections'] as List? ?? [])
                        .whereType<Map>()
                        .toList();
                    return SingleChildScrollView(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              _FeeScheduleTag('${data['tierLabel']} schedule',
                                  highlighted: true),
                              _FeeScheduleTag(
                                  data['region'] == 'uk' ? 'UK' : 'Europe'),
                              _FeeScheduleTag(data['accountType'] == 'personal'
                                  ? 'Personal account'
                                  : 'Business account'),
                            ]),
                            const SizedBox(height: 16),
                            Text('Your current plan’s fees, all in one place.',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Text(
                                'You’ll see the charges for each payment or exchange before you confirm.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.5)),
                            const SizedBox(height: 28),
                            for (var i = 0; i < sections.length; i++) ...[
                              _FeeSection(section: sections[i]),
                              if (i < sections.length - 1)
                                const SizedBox(height: 20),
                            ],
                          ]),
                    );
                  },
                ),
          ),
        ]),
      ),
    );
  }
}

class _FeeScheduleMessage extends StatelessWidget {
  const _FeeScheduleMessage({required this.message, this.action});
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.receipt_long_outlined, size: 36),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ]),
      ));
}

class _FeeScheduleTag extends StatelessWidget {
  const _FeeScheduleTag(this.label, {this.highlighted = false});
  final String label;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: .12)
            : theme.colorScheme.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(label,
          style: theme.textTheme.labelMedium?.copyWith(
              color: highlighted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _FeeSection extends StatelessWidget {
  const _FeeSection({required this.section});
  final Map section;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rows = (section['rows'] as List? ?? []).whereType<Map>().toList();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          border:
              Border.all(color: colors.outlineVariant.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: colors.onSurface.withValues(alpha: .04),
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${section['title']}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if ('${section['description'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${section['description']}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant)),
            ],
          ]),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: colors.outlineVariant.withValues(alpha: .4)),
          _FeeRow(row: rows[i]),
        ],
      ]),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.row});
  final Map row;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final frequency = '${row['frequency'] ?? ''}';
    final description = '${row['description'] ?? ''}'
        .replaceAll(
            RegExp(r"Can be set as 'Free Internal Transfers' In Retool\.?",
                caseSensitive: false),
            '')
        .replaceAll(
            RegExp(
                r'Sometimes know to the Partner as an account residency fee, or to the Client as a monthly account fee\.?',
                caseSensitive: false),
            '')
        .trim();
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, constraints) {
          final title = Text('${row['item']}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600));
          final price = Text('${row['value']}',
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700, color: colors.primary));
          if (constraints.maxWidth < 350) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 6), price]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: title),
            const SizedBox(width: 20),
            Flexible(
                flex: 2,
                child: Align(alignment: Alignment.topRight, child: price))
          ]);
        }),
        if (frequency.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(frequency,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant)),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.5)),
        ],
      ]),
    );
  }
}
