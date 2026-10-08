import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/widgets/app_states.dart';
import '../../wallets/presentation/crypto_wallet_actions.dart';
import '../../platform/application/platform_providers.dart';
import '../application/peer_providers.dart';
import '../data/peer_transfers_api.dart';
import 'peer_composer.dart';
import 'peer_confirmation.dart';
import 'peer_widgets.dart';

/// Send & request hub: instant transfers between members, pending requests,
/// saved contacts and recent activity. Phones open the composer as a sheet;
/// desktop keeps it in a left column next to the lists.
class PeerHubScreen extends ConsumerStatefulWidget {
  const PeerHubScreen({this.initialMode = PeerComposerMode.send, super.key});

  final PeerComposerMode initialMode;

  @override
  ConsumerState<PeerHubScreen> createState() => _PeerHubScreenState();
}

class _PeerHubScreenState extends ConsumerState<PeerHubScreen> {
  late PeerComposerMode _mode = widget.initialMode;
  final _busyRequests = <String>{};

  Future<void> _refresh() async {
    invalidatePeerData(ref);
    await Future.wait<void>([
      ref
          .read(peerRequestsProvider.future)
          .then<void>((_) {})
          .catchError((_) {}),
      ref
          .read(peerContactsProvider.future)
          .then<void>((_) {})
          .catchError((_) {}),
      ref.read(peerRecentProvider.future).then<void>((_) {}).catchError((_) {}),
    ]);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pay(PeerPaymentRequest request) async {
    final confirmation = await confirmPeerAction(
      context,
      ref,
      reason:
          'Confirm paying ${peerMoney(request.currency, request.amount)} to ${request.otherUser.fullName}',
    );
    if (confirmation == null || !mounted) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await ref.read(peerTransfersApiProvider).respond(
            requestId: request.id,
            accept: true,
            confirmation: confirmation,
          );
      invalidatePeerData(ref);
      if (!mounted) return;
      _toast(
          'Paid ${peerMoney(request.currency, request.amount)} to ${request.otherUser.fullName}.');
    } catch (error) {
      if (!mounted) return;
      _toast(peerErrorText(error));
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _decline(PeerPaymentRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ExamplePalette.of(context).navigation,
        title: Text(context.tr('Decline request?')),
        content: Text(
          context.tr('{p0} asked for {p1}. They will be told you declined.', {
            'p0': request.otherUser.fullName,
            'p1': peerMoney(request.currency, request.amount)
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Decline')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await ref
          .read(peerTransfersApiProvider)
          .respond(requestId: request.id, accept: false);
      invalidatePeerData(ref);
      if (mounted) _toast('Request declined.');
    } catch (error) {
      if (mounted) _toast(peerErrorText(error));
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _cancel(PeerPaymentRequest request) async {
    setState(() => _busyRequests.add(request.id));
    try {
      await ref.read(peerTransfersApiProvider).cancelRequest(request.id);
      invalidatePeerData(ref);
      if (mounted) _toast('Request cancelled.');
    } catch (error) {
      if (mounted) _toast(peerErrorText(error));
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _removeContact(PeerContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: ExamplePalette.of(context).navigation,
        title: Text(context.tr('Remove {p0}?', {'p0': contact.displayName})),
        content:
            Text(context.tr('You can add them again from a transfer later.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Keep')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Remove')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(peerTransfersApiProvider).removeContact(contact.id);
      ref.invalidate(peerContactsProvider);
    } catch (error) {
      if (mounted) _toast(peerErrorText(error));
    }
  }

  void _openComposer(PeerComposerMode mode, {PeerUser? recipient}) {
    setState(() => _mode = mode);
    showPeerComposerSheet(
      context,
      mode: mode,
      recipient: recipient,
      onModeChanged: (value) {
        if (mounted) setState(() => _mode = value);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(peerTransfersEnabledProvider).valueOrNull ?? true;
    final tenant = ref.watch(mobileTenantConfigProvider).valueOrNull;
    final fiatEnabled = tenant?.equalsMoneyEnabled ?? true;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= ExampleBreakpoints.desktop;

    final lists = <Widget>[
      _RequestsSection(
        busy: _busyRequests,
        onPay: _pay,
        onDecline: _decline,
        onCancel: _cancel,
      ),
      const SizedBox(height: 18),
      _ContactsSection(
        onPick: (contact) => desktop
            ? _openComposer(PeerComposerMode.send, recipient: contact.user)
            : _openComposer(PeerComposerMode.send, recipient: contact.user),
        onAdd: () => _openComposer(PeerComposerMode.send),
        onRemove: _removeContact,
      ),
      const SizedBox(height: 18),
      const _RecentSection(),
    ];

    final otherWays = _OtherWays(fiatEnabled: fiatEnabled, mode: _mode);

    Widget body;
    if (desktop) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 470,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!enabled)
                          const _DisabledNotice()
                        else
                          PeerComposer(
                            mode: _mode,
                            onModeChanged: (mode) =>
                                setState(() => _mode = mode),
                          ),
                        const SizedBox(height: 16),
                        otherWays,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: lists,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            if (!enabled)
              const _DisabledNotice()
            else
              _Hero(
                onSend: () => _openComposer(PeerComposerMode.send),
                onRequest: () => _openComposer(PeerComposerMode.request),
              ),
            const SizedBox(height: 14),
            otherWays,
            const SizedBox(height: 18),
            ...lists,
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Send & request')),
        actions: [
          IconButton(
            tooltip: context.tr('Refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.onSend, required this.onRequest});

  final VoidCallback onSend;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        emphasis: true,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Instant transfers between members'),
              style: TextStyle(
                color: ExamplePalette.of(context).ink,
                fontSize: 17 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w800,
                letterSpacing: -.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr(
                  'Send USD, USDC or USDT to anyone on {p0} with their nickname, email or phone number. 10 free transfers a day.',
                  {
                    'p0': AppDesignTheme.nameOf(context).isEmpty
                        ? 'Example'
                        : AppDesignTheme.nameOf(context)
                  }),
              style: TextStyle(
                  color: ExamplePalette.of(context).textSecondary,
                  fontSize: 12.5 * context.brandDesign.typographyScale,
                  height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.north_east_rounded, size: 18),
                    label: Text(context.tr('Send')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRequest,
                    icon: const Icon(Icons.south_west_rounded, size: 18),
                    label: Text(context.tr('Request')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _DisabledNotice extends StatelessWidget {
  const _DisabledNotice();

  @override
  Widget build(BuildContext context) => ExampleDashedPanel(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  color: ExamplePalette.of(context).textSecondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr(
                      'Member-to-member transfers are not switched on for this programme yet.'),
                  style: TextStyle(
                      color: ExamplePalette.of(context).textSecondary,
                      fontSize: 13 * context.brandDesign.typographyScale,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Bank transfers and on-chain withdrawals stay where they were; this row
/// just points there so "Send" on Home has one front door.
class _OtherWays extends ConsumerWidget {
  const _OtherWays({required this.fiatEnabled, required this.mode});

  final bool fiatEnabled;
  final PeerComposerMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
        children: [
          if (fiatEnabled)
            Expanded(
              child: _WayTile(
                icon: Icons.account_balance_outlined,
                title: context.tr('Bank transfer'),
                caption: context.tr('IBAN & SWIFT'),
                onTap: () => context.go(AppRoutes.pay),
              ),
            ),
          if (fiatEnabled) const SizedBox(width: 10),
          Expanded(
            child: _WayTile(
              icon: Icons.currency_bitcoin_rounded,
              title: context.tr('Crypto wallet'),
              caption: context.tr('On-chain'),
              onTap: () => mode == PeerComposerMode.request
                  ? openCryptoDeposit(context, ref)
                  : openCryptoSend(context, ref),
            ),
          ),
        ],
      );
}

class _WayTile extends StatelessWidget {
  const _WayTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            ExampleIconTile(icon: icon, color: ExamplePalette.of(context).accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ExamplePalette.of(context).ink,
                      fontSize: 12.5 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ExamplePalette.of(context).textTertiary,
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RequestsSection extends ConsumerWidget {
  const _RequestsSection({
    required this.busy,
    required this.onPay,
    required this.onDecline,
    required this.onCancel,
  });

  final Set<String> busy;
  final ValueChanged<PeerPaymentRequest> onPay;
  final ValueChanged<PeerPaymentRequest> onDecline;
  final ValueChanged<PeerPaymentRequest> onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(peerRequestsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(
          title: context.tr('Requests'),
          action: _openCount(requests.valueOrNull?.pendingCount ?? 0),
        ),
        const SizedBox(height: 10),
        requests.when(
          data: (data) {
            if (data.pendingCount == 0 && data.history.isEmpty) {
              return ExampleDashedPanel(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.tr(
                        'No requests yet. Ask a member for money and it shows up here until they pay or decline.'),
                    style: TextStyle(
                        color: ExamplePalette.of(context).textTertiary,
                        fontSize: 12.5 * context.brandDesign.typographyScale,
                        height: 1.4),
                  ),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final request in data.received) ...[
                  PeerRequestTile(
                    request: request,
                    busy: busy.contains(request.id),
                    onPay: () => onPay(request),
                    onDecline: () => onDecline(request),
                    onTap: () => showPeerRequestDetails(context, request),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final request in data.sent) ...[
                  PeerRequestTile(
                    request: request,
                    busy: busy.contains(request.id),
                    onCancel: () => onCancel(request),
                    onTap: () => showPeerRequestDetails(context, request),
                  ),
                  const SizedBox(height: 8),
                ],
                if (data.history.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.tr('EARLIER'),
                    style: TextStyle(
                      color: ExamplePalette.of(context).textTertiary,
                      fontSize: 10.5 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final request in data.history.take(6)) ...[
                    PeerRequestTile(
                      request: request,
                      onTap: () => showPeerRequestDetails(context, request),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            );
          },
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(peerRequestsProvider),
          ),
          loading: () => LoadingState(label: context.tr('Loading requests')),
        ),
      ],
    );
  }
}

String? _openCount(int count) => count > 0 ? '$count open' : null;

class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({
    required this.onPick,
    required this.onAdd,
    required this.onRemove,
  });

  final ValueChanged<PeerContact> onPick;
  final VoidCallback onAdd;
  final ValueChanged<PeerContact> onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(peerContactsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Contacts')),
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: contacts.when(
            data: (items) => ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _ContactBubble(
                  label: context.tr('New'),
                  avatar: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ExamplePalette.of(context).borderEmphasis,
                          width: 1.5),
                      color: ExamplePalette.of(context).surfaceSubtle,
                    ),
                    child: Icon(Icons.add_rounded,
                        color: ExamplePalette.of(context).accent),
                  ),
                  onTap: onAdd,
                ),
                for (final contact in items)
                  _ContactBubble(
                    label: contact.displayName.split(' ').first,
                    avatar: PeerAvatar(user: contact.user, size: 48),
                    onTap: () => onPick(contact),
                    onLongPress: () => onRemove(contact),
                  ),
              ],
            ),
            error: (_, __) => const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _ContactBubble extends StatelessWidget {
  const _ContactBubble({
    required this.label,
    required this.avatar,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final Widget avatar;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 68,
          child: Column(
            children: [
              avatar,
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: ExamplePalette.of(context).textSecondary,
                    fontSize: 11.5),
              ),
            ],
          ),
        ),
      );
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(peerRecentProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Recent')),
        const SizedBox(height: 6),
        recent.when(
          data: (items) => items.isEmpty
              ? ExampleDashedPanel(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.tr(
                          'Transfers between you and other members will appear here.'),
                      style: TextStyle(
                          color: ExamplePalette.of(context).textTertiary,
                          fontSize: 12.5 * context.brandDesign.typographyScale,
                          height: 1.4),
                    ),
                  ),
                )
              : ExampleGlassPanel(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(
                    children: [
                      for (final transfer in items)
                        PeerTransferTile(
                          transfer: transfer,
                          onTap: () =>
                              showPeerTransferDetails(context, transfer),
                        ),
                    ],
                  ),
                ),
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(peerRecentProvider),
          ),
          loading: () => LoadingState(label: context.tr('Loading activity')),
        ),
      ],
    );
  }
}
