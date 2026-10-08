import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/referral_lifecycle.dart';
import '../domain/rewards_models.dart';

/// Same observation, forecast assumptions and history on phone and desktop.
/// No client-side countdown invents a demotion when observations are missing.
class ReferralLevelLifecycleCard extends ConsumerWidget {
  const ReferralLevelLifecycleCard({required this.currency, super.key});
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(referralLevelLifecycleProvider);
    return Card(
      key: const Key('referral_level_lifecycle'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('Level information could not be loaded.')),
            TextButton(
                onPressed: () => ref.invalidate(referralLevelLifecycleProvider),
                child: Text(context.tr('Retry'))),
          ]),
          data: (data) => data == null
              ? Text(context.tr('Level history and forecasts are unavailable.'))
              : ReferralLevelLifecycleView(data: data, currency: currency),
        ),
      ),
    );
  }
}

class ReferralLevelLifecycleView extends ConsumerWidget {
  const ReferralLevelLifecycleView(
      {required this.data, required this.currency, super.key});
  final ReferralLevelLifecycle data;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dates = MaterialLocalizations.of(context);
    final forecast = data.forecast;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.tr('Your invitation level'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(data.currentLevel?.name ?? context.tr('No current level'),
          key: const Key('referral_lifecycle_current'),
          style: Theme.of(context).textTheme.headlineSmall),
      if (data.assigned) Text(context.tr('Assigned level')),
      for (final condition in data.progress.nextConditions) ...[
        const SizedBox(height: 12),
        Text(condition.kind == ReferralConditionKind.qualifiedReferrals
            ? context.tr('Qualified friends: {p0} of {p1}', {
                'p0': condition.current.toInt(),
                'p1': condition.target.toInt()
              })
            : context.tr('Eligible volume: {p0} of {p1}', {
                'p0': Money.formatAmount(currency, condition.current),
                'p1': Money.formatAmount(currency, condition.target)
              })),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: condition.fraction),
      ],
      const SizedBox(height: 12),
      if (forecast != null) ...[
        Text(
            context.tr('Projected level on {p0}: {p1}', {
              'p0': dates.formatMediumDate(forecast.effectiveAt.toLocal()),
              'p1': forecast.level?.name ?? context.tr('No current level')
            }),
            key: const Key('referral_lifecycle_forecast')),
        if (forecast.level != null)
          Text(context.tr('Top-up rate: {p0}',
              {'p0': _rateLabel(context, forecast.level!, currency)})),
        if (data.forecastAssumption == 'NO_FUTURE_ACTIVITY_OR_POLICY_CHANGES')
          Text(context
              .tr('Projection assumes no new activity or programme changes.')),
      ] else
        Text(context.tr('No upcoming level change is currently projected.')),
      if (data.existingOffersProtected &&
          data.protectedRelationshipCount > 0) ...[
        const SizedBox(height: 8),
        Text(context.tr(
            'Existing accepted offers stay unchanged. This level applies to new invitations.')),
      ],
      const SizedBox(height: 8),
      Text(
          context.tr('Calculated on {p0}',
              {'p0': dates.formatMediumDate(data.asOf.toLocal())}),
          style: Theme.of(context).textTheme.bodySmall),
      Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
              icon: const Icon(Icons.history),
              label: Text(context.tr('Level history')),
              onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      _LevelHistoryDialog(programId: data.programId)))),
    ]);
  }
}

String _rateLabel(BuildContext context, ReferralLevel level, String currency) {
  final percent = formatReferralPercent(level.topupRate);
  return switch (level.topupCalculationType) {
    'FIXED' => Money.formatAmount(currency, level.topupRate),
    'PERCENT_OF_MARGIN' =>
      context.tr('{p0} of settled margin', {'p0': percent}),
    'PERCENT_OF_WL_FEE' =>
      context.tr('{p0} of the settled fee after cost', {'p0': percent}),
    'PERCENT_OF_TOPUP' =>
      context.tr('{p0} of eligible top-ups', {'p0': percent}),
    _ => context.tr('Rate details unavailable'),
  };
}

class _LevelHistoryDialog extends ConsumerStatefulWidget {
  const _LevelHistoryDialog({required this.programId});
  final String programId;
  @override
  ConsumerState<_LevelHistoryDialog> createState() =>
      _LevelHistoryDialogState();
}

class _LevelHistoryDialogState extends ConsumerState<_LevelHistoryDialog> {
  final _items = <ReferralLevelChange>[];
  bool _loading = false;
  bool _unavailable = false;
  bool _failed = false;
  bool _hasMore = true;
  int _nextPage = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await ref
          .read(mobilePlatformApiProvider)
          .getReferralLevelHistory(
              programId: widget.programId, page: _nextPage);
      if (!mounted) return;
      setState(() {
        final known = _items.map((item) => item.id).toSet();
        _items.addAll(page.items.where((item) => known.add(item.id)));
        _nextPage = page.page + 1;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _unavailable = error is DioException &&
            (error.response?.statusCode == 404 ||
                error.response?.statusCode == 501);
        _failed = !_unavailable;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Level history')),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  for (final item in _items)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context
                                  .tr('Level changed from {p0} to {p1}', {
                                'p0': item.previousLevel?.name ??
                                    context.tr('No current level'),
                                'p1': item.currentLevel?.name ??
                                    context.tr('No current level')
                              })),
                              Text(MaterialLocalizations.of(context)
                                  .formatMediumDate(
                                      item.effectiveAt.toLocal())),
                            ])),
                  if (_unavailable)
                    Text(context
                        .tr('Level history and forecasts are unavailable.')),
                  if (_failed)
                    Text(context.tr('Level information could not be loaded.')),
                  if (!_loading && !_failed && !_unavailable && _items.isEmpty)
                    Text(context.tr('No recorded level changes yet.')),
                  if (_loading) const LinearProgressIndicator(),
                  if (!_loading && !_unavailable && (_hasMore || _failed))
                    TextButton(
                        onPressed: _load,
                        child:
                            Text(context.tr(_failed ? 'Retry' : 'Load more'))),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close')))
        ],
      );
}
