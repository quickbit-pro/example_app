import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/referral_community.dart';

final referralCommunityProvider = FutureProvider.autoDispose
    .family<ReferralCommunity?, String?>((ref, programId) async {
  try {
    return await ref
        .watch(mobilePlatformApiProvider)
        .getReferralCommunity(programId: programId);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) return null;
    rethrow;
  }
});

class ReferralCommunityEntry extends ConsumerWidget {
  const ReferralCommunityEntry({required this.programId, super.key});
  final String? programId;
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(referralCommunityProvider(programId)).when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (community) => community?.enabled != true
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Card(
                        child: ListTile(
                            leading: const Icon(Icons.hub_outlined),
                            title: Text(context.tr('Example Community')),
                            subtitle: Text(context.tr(
                                'Your community and earnings across three generations')),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => ReferralCommunityScreen(
                                        programId: programId))))),
                  ),
          );
}

class ReferralCommunityScreen extends ConsumerStatefulWidget {
  const ReferralCommunityScreen({required this.programId, super.key});
  final String? programId;
  @override
  ConsumerState<ReferralCommunityScreen> createState() =>
      _ReferralCommunityScreenState();
}

class _ReferralCommunityScreenState
    extends ConsumerState<ReferralCommunityScreen> {
  final List<ReferralCommunityEarning> _earnings = [];
  int _page = 1;
  bool _loading = false;
  bool _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _earnings.clear();
        _more = true;
      }
    });
    try {
      final rows = await ref
          .read(mobilePlatformApiProvider)
          .getReferralCommunityEarnings(
              programId: widget.programId, page: _page);
      if (!mounted) return;
      setState(() {
        _earnings.addAll(
            rows.where((row) => !_earnings.any((old) => old.id == row.id)));
        _more = rows.length == 25;
        _page++;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Community earnings are temporarily unavailable.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double value, String currency) =>
      '${value.toStringAsFixed(2)} $currency';
  String _rate(double percent) =>
      '${percent.toStringAsFixed(2)}% of settled margin (approximately ${(percent / 100 * 2).toStringAsFixed(2)}% of gross top-up at 2% margin)';
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Example Community'))),
        body: ref.watch(referralCommunityProvider(widget.programId)).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(
                          referralCommunityProvider(widget.programId)),
                      child: Text(context.tr('Retry')))),
              data: (community) {
                if (community == null || community.plan.isEmpty) {
                  return Center(
                      child: Text(
                          context.tr('Community membership is unavailable.')));
                }
                return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(
                          referralCommunityProvider(widget.programId));
                      await _load(reset: true);
                    },
                    child:
                        ListView(padding: const EdgeInsets.all(20), children: [
                      Text(
                          community.plan == 'LEADER'
                              ? context.tr('Community Leader')
                              : context.tr('Community Partner'),
                          style: Theme.of(context).textTheme.headlineSmall),
                      Text(community.status,
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 16),
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(context.tr('Your protected plan'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(context.tr(
                                        'L1: your existing direct rewards and protected rate')),
                                    Text('L2: ${_rate(community.l2Percent)}'),
                                    Text('L3: ${_rate(community.l3Percent)}'),
                                    const SizedBox(height: 12),
                                    Text(context.tr(
                                        'L2 and L3 earn recurring rewards only, from eligible external top-ups in each friend’s original earning window. There are no additional fixed bonuses.')),
                                    Text(context.tr(
                                        'The total recurring budget is 65% of settled margin. L3 is reduced first, then L2; the direct inviter’s protected reward stays unchanged.')),
                                    Text(context.tr(
                                        'People between you and a friend are never skipped. Enabling Community does not reward earlier top-ups.')),
                                  ]))),
                      for (final generation in community.generations)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('L${generation.depth}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      Text(
                                          '${generation.descendants} ${context.tr('friends')} · ${generation.qualified} ${context.tr('qualified')} · ${generation.earning} ${context.tr('earning')}'),
                                      Text(
                                          '${context.tr('Accrued')}: ${_money(generation.accrued, community.currency)}'),
                                      Text(
                                          '${context.tr('Paid')}: ${_money(generation.cashPaid, community.currency)} · ${context.tr('Outstanding')}: ${_money(generation.outstanding, community.currency)}'),
                                    ]))),
                      const SizedBox(height: 16),
                      Text(context.tr('Community earnings'),
                          style: Theme.of(context).textTheme.titleLarge),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      if (_earnings.isEmpty && !_loading && _error == null)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child:
                                Text(context.tr('No community earnings yet.'))),
                      for (final earning in _earnings)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'L${earning.depth} · ${earning.friendAlias}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      Text(
                                          '${_money(earning.amount, community.currency)} · ${earning.status}'),
                                      Text(
                                          '${context.tr('Applied share')}: ${_rate(earning.appliedRate)}'),
                                      if (earning.reductionReason != null)
                                        Text(context.tr(
                                            'This reward was reduced to fit the recurring margin budget.')),
                                      Text(
                                          '${context.tr('Paid')}: ${_money(earning.cashPaid, community.currency)} · ${context.tr('Outstanding')}: ${_money(earning.outstanding, community.currency)}'),
                                    ]))),
                      if (_loading)
                        const Center(child: CircularProgressIndicator()),
                      if (_error != null || (_more && !_loading))
                        TextButton(
                            onPressed: () => _load(),
                            child: Text(context
                                .tr(_error != null ? 'Retry' : 'Load more'))),
                    ]));
              },
            ),
      );
}
