import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart' show friendlyErrorMessage;
import '../../../shared/theme/app_colors.dart' show FinanceStatusTone;
import '../../platform/application/platform_providers.dart';
import '../domain/referral_share.dart';
import '../domain/rewards_models.dart';
import 'referral_actions.dart';
import 'referral_analytics.dart';
import 'referral_sections.dart' show ReferralStageChip;
import 'referral_widgets.dart';

// ---------------------------------------------------------------------------
// Campaign links (blueprint p27 "Links and campaigns should be simple", p17
// campaign performance): the member's tracking links on the web workspace,
// and the short list of them the phone's share block carries. A link is a
// name, a code, a channel, a language and a lifecycle; it never carries a
// rate. Pausing stops new attribution and leaves existing relationships
// untouched. Nothing here shares anything on the member's behalf.
// ---------------------------------------------------------------------------

/// The chip tone for a link's status.
FinanceStatusTone campaignLinkStatusTone(ReferralCampaignLinkStatus status) {
  switch (status) {
    case ReferralCampaignLinkStatus.active:
      return FinanceStatusTone.success;
    case ReferralCampaignLinkStatus.paused:
    case ReferralCampaignLinkStatus.draft:
      return FinanceStatusTone.warning;
    case ReferralCampaignLinkStatus.archived:
      return FinanceStatusTone.danger;
    case ReferralCampaignLinkStatus.expired:
    case ReferralCampaignLinkStatus.unknown:
      return FinanceStatusTone.neutral;
  }
}

IconData campaignChannelIcon(ReferralCampaignChannel? channel) {
  switch (channel) {
    case ReferralCampaignChannel.social:
      return Icons.tag_rounded;
    case ReferralCampaignChannel.community:
      return Icons.forum_outlined;
    case ReferralCampaignChannel.email:
      return Icons.mail_outline_rounded;
    case ReferralCampaignChannel.website:
      return Icons.language_rounded;
    case ReferralCampaignChannel.event:
      return Icons.event_outlined;
    case ReferralCampaignChannel.other:
    case null:
      return Icons.link_rounded;
  }
}

/// The channel as copy: the allowlist's label, or the raw value for one the
/// app does not know.
String campaignChannelLabel(BuildContext context, ReferralCampaignLink link) {
  final channel = link.channelValue;
  if (channel != null) return context.tr(channel.label);
  return link.channel.isEmpty ? '—' : link.channel;
}

/// The offer as one sentence, for the creator's preview: the tenant's own
/// words when the admin wrote them, otherwise the programme's figures.
String referralCampaignOfferPreview(
    BuildContext context, ReferralSummary summary) {
  if (summary.hasProgramDescription) {
    return summary.programDescription!.trim();
  }
  final offer = summary.offer;
  final lines = <String>[];
  if (offer != null && offer.hasWelcome) {
    lines.add(context.tr('{p0} for them.', {
      'p0': formatReferralAmount(offer.welcomeCurrency, offer.welcomeAmount),
    }));
  }
  final referrer = offer == null ? null : describeReferrerReward(offer);
  if (referrer != null) {
    lines.add(context.tr('{p0} for you.', {'p0': referrer}));
  }
  return lines.isEmpty
      ? context.tr('Invite friends and earn rewards.')
      : lines.join(' ');
}

/// The caption a member can paste beside a campaign link: the platform's
/// sentence when it sent one, the app's invitation text otherwise.
String referralCampaignCaption(
  BuildContext context, {
  required String appName,
  required ReferralSummary summary,
  required ReferralCampaignLink link,
}) {
  final suggested = link.suggestedCaption?.trim() ?? '';
  if (suggested.isNotEmpty) return suggested;
  return buildReferralShareText(
    appName: appName,
    referralCode: link.code,
    link: link.shareUrl,
    offer: summary.offer,
    translate: AppLocalizations.of(context).translate,
  );
}

// ------------------------------------------------------------------- tab

/// The Links tab of the workspace: the member's links with their figures,
/// the way to create one, and each link's actions.
class ReferralCampaignLinksTab extends ConsumerStatefulWidget {
  const ReferralCampaignLinksTab({required this.summary, super.key});

  final ReferralSummary summary;

  @override
  ConsumerState<ReferralCampaignLinksTab> createState() =>
      _ReferralCampaignLinksTabState();
}

class _ReferralCampaignLinksTabState
    extends ConsumerState<ReferralCampaignLinksTab> {
  ReferralAnalyticsRange _range = ReferralAnalyticsRange.thirtyDays;

  /// Ids of links with a status change in flight.
  final _busy = <String>{};

  Future<void> _create(List<ReferralCampaignLink> links) async {
    final created = await showReferralCampaignLinkCreator(
      context,
      summary: widget.summary,
      links: links,
    );
    if (created != null) ref.invalidate(referralCampaignLinksProvider);
  }

  Future<void> _setStatus(
    ReferralCampaignLink link,
    ReferralCampaignLinkStatus status,
  ) async {
    final confirmed = await _confirmStatusChange(context, link, status);
    if (!confirmed || !mounted) return;
    setState(() => _busy.add(link.id));
    try {
      await ref
          .read(mobilePlatformApiProvider)
          .updateReferralCampaignLink(link.id, status: status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(switch (status) {
          ReferralCampaignLinkStatus.paused =>
            context.tr('Link paused. New sign-ups no longer count through it.'),
          ReferralCampaignLinkStatus.archived => context.tr('Link archived.'),
          _ => context.tr('Link resumed.'),
        }),
      ));
      ref.invalidate(referralCampaignLinksProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(link.id));
    }
  }

  Future<void> _copy(String text, String confirmation) async {
    await copyToClipboard(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final linksValue = ref.watch(referralCampaignLinksProvider);
    final analyticsValue = ref.watch(referralAnalyticsProvider(_range));
    final analytics = analyticsValue.asData?.value;
    final analyticsServed = analyticsValue.when(
      data: (data) => data != null,
      error: (_, __) => true,
      loading: () => true,
    );
    final earnings = {
      for (final row in analytics?.campaigns ?? const <ReferralCampaignRow>[])
        row.linkId: row,
    };
    final currency = analytics?.currency ?? widget.summary.rewards.currency;
    final appName = ref.watch(appConfigProvider).branding.appName;
    final links = linksValue.asData?.value;
    final Widget body;
    if (linksValue.isLoading && links == null) {
      body = const ReferralListSkeleton();
    } else if (linksValue.hasError && links == null) {
      body = ExampleErrorState(
        key: const Key('referral_links_error'),
        compact: true,
        error: linksValue.error,
        onRetry: () => ref.invalidate(referralCampaignLinksProvider),
      );
    } else if (links == null) {
      body = ExampleEmptyState(
        key: const Key('referral_links_unavailable'),
        compact: true,
        icon: Icons.link_off_rounded,
        title: context.tr('Campaign links are not available yet'),
        body: context.tr(
            'This section appears once your company enables campaign links.'),
      );
    } else if (links.isEmpty) {
      body = ExampleEmptyState(
        key: const Key('referral_links_empty'),
        compact: true,
        icon: Icons.link_rounded,
        title: context.tr('No campaign links yet'),
        body: context.tr(
            'Create a link for each place you share, and see what each one brings in.'),
        actionLabel: context.tr('Create link'),
        onAction: () => _create(links),
      );
    } else {
      final rows = sortReferralCampaignLinks(links);
      body = ExampleListGroup(
        key: const Key('referral_links_list'),
        dividers: true,
        dividerInset: 0,
        children: [
          for (final link in rows)
            _LinkRow(
              key: ValueKey('referral_link_${link.id}'),
              link: link,
              earned: earnings[link.id],
              currency: currency,
              busy: _busy.contains(link.id),
              showEarnings: analyticsServed,
              onPerformance: () =>
                  showReferralCampaignLinkPerformance(context, link),
              onCopy: () =>
                  _copy(link.shareText, context.tr('Campaign link copied')),
              onQr: link.shareUrl == null
                  ? null
                  : () => showReferralQrDialog(context, link.shareUrl!),
              onCopyCaption: () => _copy(
                referralCampaignCaption(
                  context,
                  appName: appName,
                  summary: widget.summary,
                  link: link,
                ),
                context.tr('Caption copied'),
              ),
              onPause: link.canPause()
                  ? () => _setStatus(link, ReferralCampaignLinkStatus.paused)
                  : null,
              onResume: link.canResume()
                  ? () => _setStatus(link, ReferralCampaignLinkStatus.active)
                  : null,
              onArchive: link.canArchive()
                  ? () =>
                      _setStatus(link, ReferralCampaignLinkStatus.archived)
                  : null,
            ),
        ],
      );
    }
    final canCreate = links != null && widget.summary.canInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: AppSpacing.sm,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.tr('Links'),
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    context.tr(
                        'One link per place you share. Each link tracks its own sign-ups; pausing one stops new sign-ups through it and changes nothing for friends already attributed.'),
                    style: referralBodyStyle(context),
                  ),
                ],
              ),
            ),
            if (canCreate)
              ExampleGlassButton(
                key: const Key('referral_links_create'),
                label: context.tr('Create link'),
                icon: Icons.add_link_rounded,
                sheen: false,
                expand: false,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                onPressed: () => _create(links),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (links != null && links.isNotEmpty && analyticsServed) ...[
          ReferralPeriodSelector(
            selected: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('Earnings are shown for the selected period; sign-ups and qualified friends are counted since the link was created.'),
            key: const Key('referral_links_period_note'),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (linksValue.hasError && links != null) ...[
          ExampleErrorState(
            compact: true,
            error: linksValue.error,
            onRetry: () => ref.invalidate(referralCampaignLinksProvider),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        body,
      ],
    );
  }
}

Future<bool> _confirmStatusChange(
  BuildContext context,
  ReferralCampaignLink link,
  ReferralCampaignLinkStatus status,
) async {
  if (status == ReferralCampaignLinkStatus.active) return true;
  final archive = status == ReferralCampaignLinkStatus.archived;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('referral_link_confirm'),
      title: Text(archive
          ? dialogContext.tr('Archive {p0}?', {'p0': link.name})
          : dialogContext.tr('Pause {p0}?', {'p0': link.name})),
      content: Text(archive
          ? dialogContext.tr(
              'The link stops counting new sign-ups for good and cannot be reactivated. Friends already attributed keep their earning window.')
          : dialogContext.tr(
              'New sign-ups through this link stop counting until you resume it. Friends already attributed keep their earning window.')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.tr('Cancel')),
        ),
        FilledButton(
          key: const Key('referral_link_confirm_yes'),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(archive
              ? dialogContext.tr('Archive link')
              : dialogContext.tr('Pause link')),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// One link: what it is, where it stands, what it brought in, and a menu of
/// its actions. Figures spread into columns on a wide row and stack under
/// the name below 720 px.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.link,
    required this.earned,
    required this.currency,
    required this.busy,
    required this.showEarnings,
    required this.onPerformance,
    required this.onCopy,
    required this.onCopyCaption,
    this.onQr,
    this.onPause,
    this.onResume,
    this.onArchive,
    super.key,
  });

  final ReferralCampaignLink link;
  final ReferralCampaignRow? earned;
  final String currency;
  final bool busy;
  final bool showEarnings;
  final VoidCallback onPerformance;
  final VoidCallback onCopy;
  final VoidCallback onCopyCaption;
  final VoidCallback? onQr;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final status = link.effectiveStatus();
    final statusLabel = context.tr(status.label);
    final channel = campaignChannelLabel(context, link);
    final earnedText = Money.formatAmount(currency, earned?.rewardsAccrued ?? 0);
    // Click figures (addendum A) only once the platform counts them; an
    // older platform's links show no zeros they cannot stand behind.
    final figures = [
      if (link.clicksTracked) ...[
        (
          key: 'clicks',
          label: context.tr('Clicks'),
          value: '${link.clickCount}',
        ),
        (
          key: 'unique_clicks',
          label: context.tr('Unique clicks'),
          value: '${link.uniqueClickCount}',
        ),
      ],
      (
        key: 'signups',
        label: context.tr('Sign-ups'),
        value: '${link.signupCount}',
      ),
      if (link.clicksTracked)
        (
          key: 'rate',
          label: context.tr('Click→sign-up rate'),
          value: formatReferralRate(link.clickToSignupRate) ?? '—',
        ),
      (
        key: 'qualified',
        label: context.tr('Qualified'),
        value: '${link.qualifiedCount}',
      ),
      if (showEarnings)
        (key: 'earned', label: context.tr('Earned'), value: earnedText),
    ];
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          link.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: ExampleInk.primary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              link.code,
              key: Key('referral_link_code_${link.id}'),
              style: ExampleTextStyles.mono(context, size: 12.5)
                  .copyWith(color: ExampleInk.secondary(context)),
            ),
            Text('· $channel', style: referralBodyStyle(context)),
            ReferralStageChip(
              key: Key('referral_link_status_${link.id}'),
              label: statusLabel,
              tone: campaignLinkStatusTone(status),
            ),
          ],
        ),
      ],
    );
    Widget figure(({String key, String label, String value}) item,
        {bool end = true}) {
      return Column(
        crossAxisAlignment:
            end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11.5,
              color: ExampleInk.secondary(context),
            ),
          ),
          Text(
            item.value,
            key: Key('referral_link_${item.key}_${link.id}'),
            style: referralFigureStyle(context, size: 15),
          ),
        ],
      );
    }

    final menu = PopupMenuButton<VoidCallback>(
      key: Key('referral_link_menu_${link.id}'),
      tooltip: context.tr('Link actions'),
      enabled: !busy,
      onSelected: (action) => action(),
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.more_horiz_rounded, color: ExampleInk.secondary(context)),
      itemBuilder: (context) => [
        PopupMenuItem(value: onCopy, child: Text(context.tr('Copy link'))),
        if (onQr != null)
          PopupMenuItem(value: onQr, child: Text(context.tr('Show QR code'))),
        PopupMenuItem(
            value: onCopyCaption, child: Text(context.tr('Copy caption'))),
        PopupMenuItem(
            value: onPerformance, child: Text(context.tr('Performance'))),
        if (onPause != null)
          PopupMenuItem(value: onPause, child: Text(context.tr('Pause link'))),
        if (onResume != null)
          PopupMenuItem(
              value: onResume, child: Text(context.tr('Resume link'))),
        if (onArchive != null)
          PopupMenuItem(
              value: onArchive, child: Text(context.tr('Archive link'))),
      ],
    );
    final semantics =
        '${link.name}, ${link.code}, $channel, $statusLabel, ${figures.map((f) => '${f.label} ${f.value}').join(', ')}';
    return ExamplePressable(
      onTap: onPerformance,
      pressedScale: 1,
      semanticsLabel: semantics,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Six figures need the room three did; below it they wrap
            // under the name instead of squeezing it out.
            final stackBelow = figures.length > 3 ? 980.0 : 720.0;
            if (constraints.maxWidth < stackBelow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      menu,
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final item in figures) figure(item, end: false),
                    ],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: identity),
                for (final item in figures) ...[
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(width: 92, child: figure(item)),
                ],
                const SizedBox(width: AppSpacing.sm),
                menu,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- creator

/// The guided form that creates a link, then the created link with Copy,
/// QR and Copy caption. Resolves with the link, or null when dismissed.
Future<ReferralCampaignLink?> showReferralCampaignLinkCreator(
  BuildContext context, {
  required ReferralSummary summary,
  required List<ReferralCampaignLink> links,
}) {
  return showDialog<ReferralCampaignLink>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CampaignLinkCreator(
      summary: summary,
      programmes: referralCampaignProgrammes(summary, links),
    ),
  );
}

class _CampaignLinkCreator extends ConsumerStatefulWidget {
  const _CampaignLinkCreator({
    required this.summary,
    required this.programmes,
  });

  final ReferralSummary summary;
  final List<ReferralCampaignProgramme> programmes;

  @override
  ConsumerState<_CampaignLinkCreator> createState() =>
      _CampaignLinkCreatorState();
}

class _CampaignLinkCreatorState extends ConsumerState<_CampaignLinkCreator> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  ReferralCampaignChannel _channel = ReferralCampaignChannel.social;
  ReferralCampaignDestination _destination =
      ReferralCampaignDestination.signup;
  String? _programId;
  String? _locale;
  DateTime? _expiresAt;
  bool _submitting = false;
  String? _failure;
  ReferralCampaignLink? _created;

  @override
  void initState() {
    super.initState();
    _programId = widget.programmes.isEmpty ? null : widget.programmes.first.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _locale ??= _defaultLocale(context);
  }

  static String _defaultLocale(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return appLanguages.any((language) => language.code == code) ? code : 'en';
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() =>
        _expiresAt = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_formKey.currentState?.validate() != true) return;
    final expiryError = referralCampaignExpiryError(_expiresAt);
    if (expiryError != null) {
      setState(() => _failure = context.tr(expiryError));
      return;
    }
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      final created =
          await ref.read(mobilePlatformApiProvider).createReferralCampaignLink(
                ReferralCampaignLinkDraft(
                  name: _name.text,
                  channel: _channel,
                  programId: _programId,
                  code: _code.text,
                  locale: _locale,
                  destination: _destination,
                  expiresAt: _expiresAt,
                ),
              );
      if (!mounted) return;
      setState(() => _created = created);
    } catch (error) {
      if (!mounted) return;
      setState(() => _failure = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _copy(String text, String confirmation) async {
    await copyToClipboard(text);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(confirmation)));
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    if (created != null) return _success(context, created);
    const inputStyle = TextStyle(fontSize: 16);
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      key: const Key('referral_link_creator'),
      title: Text(context.tr('Create a campaign link')),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExampleGlassPanel(
                  key: const Key('referral_link_offer_preview'),
                  radius: AppRadii.md,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('WHAT FRIENDS SEE'),
                          style: ExampleTextStyles.label(context)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        referralCampaignOfferPreview(context, widget.summary),
                        style: referralBodyStyle(context),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        context.tr(
                            'The link carries the offer in force when it is created. It never changes a rate.'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (widget.programmes.length > 1) ...[
                  DropdownButtonFormField<String>(
                    key: const Key('referral_link_programme'),
                    initialValue: _programId,
                    decoration:
                        InputDecoration(labelText: context.tr('Programme')),
                    items: [
                      for (final programme in widget.programmes)
                        DropdownMenuItem(
                          value: programme.id,
                          child: Text(programme.name.isEmpty
                              ? programme.id
                              : programme.name),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _programId = value),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                TextFormField(
                  key: const Key('referral_link_name'),
                  controller: _name,
                  enabled: !_submitting,
                  style: inputStyle,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Campaign name'),
                    helperText: context.tr(
                        'For you only, e.g. "Autumn newsletter". Friends never see it.'),
                    counterText: '',
                  ),
                  validator: (value) {
                    final error = referralCampaignNameError(value);
                    return error == null ? null : context.tr(error);
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<ReferralCampaignChannel>(
                  key: const Key('referral_link_channel'),
                  initialValue: _channel,
                  decoration: InputDecoration(labelText: context.tr('Channel')),
                  items: [
                    for (final channel in ReferralCampaignChannel.values)
                      DropdownMenuItem(
                        value: channel,
                        child: Text(context.tr(channel.label)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) setState(() => _channel = value);
                        },
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: const Key('referral_link_locale'),
                  initialValue: _locale,
                  decoration: InputDecoration(labelText: context.tr('Language')),
                  items: [
                    for (final language in appLanguages)
                      DropdownMenuItem(
                        value: language.code,
                        child: Text(language.name),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _locale = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Addendum A: where the friend lands once signed up. The
                // platform validates the word; the app only offers its list.
                DropdownButtonFormField<ReferralCampaignDestination>(
                  key: const Key('referral_link_destination'),
                  initialValue: _destination,
                  decoration: InputDecoration(
                    labelText: context.tr('Destination'),
                    helperText:
                        context.tr('Where friends land after they sign up.'),
                  ),
                  items: [
                    for (final destination
                        in ReferralCampaignDestination.values)
                      DropdownMenuItem(
                        value: destination,
                        child: Text(context.tr(destination.label)),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _destination = value);
                          }
                        },
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  key: const Key('referral_link_code'),
                  controller: _code,
                  enabled: !_submitting,
                  style: inputStyle,
                  maxLength: 24,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: context.tr('Custom code (optional)'),
                    helperText: context.tr(
                        'Leave blank and one is made from the name. 6–24 letters, digits, hyphens or underscores.'),
                    counterText: '',
                  ),
                  validator: (value) {
                    final error = referralCampaignCodeError(value);
                    return error == null ? null : context.tr(error);
                  },
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiresAt == null
                            ? context.tr('No expiry')
                            : context.tr('Expires {p0}', {
                                'p0': localizations
                                    .formatMediumDate(_expiresAt!),
                              }),
                        key: const Key('referral_link_expiry'),
                        style: referralBodyStyle(context),
                      ),
                    ),
                    TextButton(
                      key: const Key('referral_link_pick_expiry'),
                      onPressed: _submitting ? null : _pickExpiry,
                      child: Text(_expiresAt == null
                          ? context.tr('Set expiry')
                          : context.tr('Change')),
                    ),
                    if (_expiresAt != null)
                      IconButton(
                        tooltip: context.tr('Remove expiry'),
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _expiresAt = null),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
                if (_failure != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _failure!,
                    key: const Key('referral_link_creator_error'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: ExampleInk.accent(context, ExampleColors.warning),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton.icon(
          key: const Key('referral_link_submit'),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_link_rounded),
          label: Text(context.tr('Create link')),
        ),
      ],
    );
  }

  Widget _success(BuildContext context, ReferralCampaignLink link) {
    final appName = ref.read(appConfigProvider).branding.appName;
    final caption = referralCampaignCaption(
      context,
      appName: appName,
      summary: widget.summary,
      link: link,
    );
    final address = link.shareText;
    return AlertDialog(
      key: const Key('referral_link_created'),
      title: Text(context.tr('Your link is ready')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                link.name,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: ExampleInk.primary(context),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                address,
                key: const Key('referral_link_created_address'),
                style: ExampleTextStyles.mono(
                  context,
                  size: 14,
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                context.tr('Code {p0}', {'p0': link.code}),
                key: const Key('referral_link_created_code'),
                style: ExampleTextStyles.mono(context, size: 12.5)
                    .copyWith(color: ExampleInk.secondary(context)),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ExampleGlassButton(
                    key: const Key('referral_link_created_copy'),
                    label: context.tr('Copy link'),
                    icon: Icons.copy_rounded,
                    sheen: false,
                    expand: false,
                    height: 44,
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    onPressed: () =>
                        _copy(address, context.tr('Campaign link copied')),
                  ),
                  if (link.shareUrl != null)
                    ExampleGlassButton(
                      key: const Key('referral_link_created_qr'),
                      label: context.tr('QR code'),
                      icon: Icons.qr_code_2_rounded,
                      tone: ExampleGlassButtonTone.neutral,
                      sheen: false,
                      expand: false,
                      height: 44,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md),
                      onPressed: () =>
                          showReferralQrDialog(context, link.shareUrl!),
                    ),
                  ExampleGlassButton(
                    key: const Key('referral_link_created_caption'),
                    label: context.tr('Copy caption'),
                    icon: Icons.notes_rounded,
                    tone: ExampleGlassButtonTone.neutral,
                    sheen: false,
                    expand: false,
                    height: 44,
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    onPressed: () =>
                        _copy(caption, context.tr('Caption copied')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(context.tr('SUGGESTED CAPTION'),
                  style: ExampleTextStyles.label(context)),
              const SizedBox(height: AppSpacing.xxs),
              SelectableText(
                caption,
                key: const Key('referral_link_created_caption_text'),
                style: referralBodyStyle(context),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('referral_link_created_done'),
          onPressed: () => Navigator.pop(context, link),
          child: Text(context.tr('Done')),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- performance

/// Opens one link's figures in a side panel: the period selector the
/// Overview uses, then sign-ups, verified, qualified, earning, and the
/// rewards accrued and paid through it.
Future<void> showReferralCampaignLinkPerformance(
  BuildContext context,
  ReferralCampaignLink link,
) {
  final duration = ExampleMotion.of(context, ExampleMotion.sheet);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr('Close'),
    barrierColor: Colors.black.withValues(alpha: .38),
    transitionDuration: duration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final width = MediaQuery.sizeOf(dialogContext).width;
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          key: const Key('referral_link_performance'),
          width: width < 520 ? width : 440,
          height: double.infinity,
          child: Material(
            color: ExampleSurface.navigationOf(dialogContext),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xs,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            link.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -.3,
                              color: ExampleInk.primary(dialogContext),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: dialogContext.tr('Close'),
                          onPressed: () => Navigator.pop(dialogContext),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: ReferralCampaignLinkPerformancePanel(link: link),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: ExampleMotion.sheetCurve,
        reverseCurve: ExampleMotion.exit,
      )),
      child: child,
    ),
  );
}

/// The body of the performance panel; a widget of its own so it can be
/// mounted anywhere and tested without the dialog.
class ReferralCampaignLinkPerformancePanel extends ConsumerStatefulWidget {
  const ReferralCampaignLinkPerformancePanel({required this.link, super.key});

  final ReferralCampaignLink link;

  @override
  ConsumerState<ReferralCampaignLinkPerformancePanel> createState() =>
      _ReferralCampaignLinkPerformancePanelState();
}

class _ReferralCampaignLinkPerformancePanelState
    extends ConsumerState<ReferralCampaignLinkPerformancePanel> {
  ReferralAnalyticsRange _range = ReferralAnalyticsRange.thirtyDays;

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final key = (linkId: link.id, range: _range);
    final value = ref.watch(referralCampaignLinkPerformanceProvider(key));
    final status = link.effectiveStatus();
    final Widget figures = value.when(
      data: (data) => _figures(context, data),
      error: (error, _) => ExampleErrorState(
        key: const Key('referral_link_performance_error'),
        compact: true,
        error: error,
        onRetry: () =>
            ref.invalidate(referralCampaignLinkPerformanceProvider(key)),
      ),
      loading: () => const ReferralListSkeleton(rows: 3),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              link.code,
              style: ExampleTextStyles.mono(context, size: 13)
                  .copyWith(color: ExampleInk.secondary(context)),
            ),
            Text('· ${campaignChannelLabel(context, link)}',
                style: referralBodyStyle(context)),
            ReferralStageChip(
              label: context.tr(status.label),
              tone: campaignLinkStatusTone(status),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ReferralPeriodSelector(
          selected: _range,
          onChanged: (range) => setState(() => _range = range),
        ),
        const SizedBox(height: AppSpacing.md),
        figures,
        const SizedBox(height: AppSpacing.md),
        Text(
          context.tr(
              'Figures count friends who signed up through this link. Rewards are yours for those friends and follow the ledger; a pending reward is never shown as paid.'),
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: ExampleInk.secondary(context),
          ),
        ),
        if (value.asData?.value.clicksTracked == true) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
                'Clicks count visitors who opened the sign-up page through this link, once per visitor per day.'),
            key: const Key('referral_link_performance_clicks_note'),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _figures(BuildContext context, ReferralCampaignLinkPerformance data) {
    final caption = referralRangeCaption(context, _range);
    final tiles = [
      if (data.clicksTracked) ...[
        (key: 'clicks', label: context.tr('Clicks'), value: '${data.clicks}'),
        (
          key: 'unique_clicks',
          label: context.tr('Unique clicks'),
          value: '${data.uniqueClicks}',
        ),
        (
          key: 'rate',
          label: context.tr('Click→sign-up rate'),
          value: formatReferralRate(data.clickToSignupRate) ?? '—',
        ),
      ],
      (key: 'signups', label: context.tr('Sign-ups'), value: '${data.signups}'),
      (key: 'verified', label: context.tr('Verified'), value: '${data.verified}'),
      (
        key: 'qualified',
        label: context.tr('Qualified'),
        value: '${data.qualified}',
      ),
      (key: 'earning', label: context.tr('Earning'), value: '${data.earning}'),
      (
        key: 'accrued',
        label: context.tr('Rewards accrued'),
        value: Money.formatAmount(data.currency, data.rewardsAccrued),
      ),
      (
        key: 'paid',
        label: context.tr('Rewards paid'),
        value: Money.formatAmount(data.currency, data.rewardsPaid),
      ),
    ];
    if (data.isEmpty) {
      return ExampleEmptyState(
        key: const Key('referral_link_performance_empty'),
        compact: true,
        icon: Icons.insights_outlined,
        title: context.tr('Nothing through this link yet'),
        body: context.tr('Figures appear here as friends sign up with it.'),
      );
    }
    return Column(
      key: const Key('referral_link_performance_figures'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(caption, style: referralBodyStyle(context)),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.9,
          children: [
            for (final tile in tiles)
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: ExampleSurface.of(context, 1),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: ExampleBorders.subtleOf(context),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      tile.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        tile.value,
                        key: Key('referral_link_performance_${tile.key}'),
                        style: referralFigureStyle(context, size: 22),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- phone

/// The phone's secondary list under the share actions: the member's active
/// campaign links, each with a copy action. Mounts nothing while the links
/// are loading, when the backend does not serve them, or when none is
/// active — the phone stays as it was.
class ReferralCampaignLinksPhoneList extends ConsumerWidget {
  const ReferralCampaignLinksPhoneList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(referralCampaignLinksProvider).asData?.value;
    if (links == null) return const SizedBox.shrink();
    final active = activeReferralCampaignLinks(links);
    if (active.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: ExampleListGroup(
        key: const Key('referral_campaign_links_phone'),
        title: context.tr('Your campaign links'),
        children: [
          for (final link in active)
            ExampleRow(
              key: Key('referral_campaign_link_phone_${link.id}'),
              title: link.name,
              subtitle: '${link.code} · ${campaignChannelLabel(context, link)}',
              leading: ExampleIconTile(
                icon: campaignChannelIcon(link.channelValue),
                color: ExampleColors.iris,
              ),
              trailing: Icon(
                Icons.copy_rounded,
                size: 18,
                color: ExampleInk.secondary(context),
              ),
              semanticsLabel: context.tr('Copy link {p0}', {'p0': link.name}),
              onTap: () async {
                await copyToClipboard(link.shareText);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('Campaign link copied'))),
                );
              },
            ),
        ],
      ),
    );
  }
}
