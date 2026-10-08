import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../application/notification_inbox_providers.dart';
import '../domain/app_notification.dart';

class NotificationInboxScreen extends ConsumerWidget {
  const NotificationInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final action = ref.watch(notificationInboxActionProvider);
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final unread = inbox.valueOrNull?.where((item) => !item.isRead).length ?? 0;

    return Scaffold(
      appBar: AppBar(
        centerTitle: isExample && !desktop,
        leading: isExample && !desktop
            ? IconButton(
                tooltip: context.tr('Back'),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              )
            : null,
        title: Text(context.tr('Notifications')),
        actions: [
          TextButton(
            style: isExample
                ? TextButton.styleFrom(
                    foregroundColor: ExampleInk.primary(context),
                    minimumSize: const Size(0, 44),
                  )
                : null,
            onPressed: action.isLoading || unread == 0
                ? null
                : () => ref
                    .read(notificationInboxActionProvider.notifier)
                    .readAll(),
            child: Text(context.tr('Read all')),
          ),
          if (!isExample || !desktop) const SizedBox(width: 4),
        ],
      ),
      body: inbox.when(
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(notificationInboxProvider.future),
          child: items.isEmpty
              ? (isExample
                  ? const _ExampleInboxEmpty()
                  : ListView(
                      children: [
                        const SizedBox(height: 160),
                        EmptyState(
                          icon: Icons.notifications_none_rounded,
                          title: context.tr('No notifications'),
                          message: context
                              .tr('Account and card updates will appear here.'),
                        ),
                      ],
                    ))
              : isExample
                  ? _ExampleInbox(
                      items: items,
                      desktop: desktop,
                      unread: unread,
                      onOpen: (item) => _openNotification(context, ref, item),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (context, index) => _NotificationTile(
                        notification: items[index],
                        onTap: () => _openNotification(
                          context,
                          ref,
                          items[index],
                        ),
                      ),
                    ),
        ),
        error: (error, stackTrace) => isExample
            ? ExampleErrorState(
                title: context.tr('Notifications did not load'),
                error: error,
                onRetry: () => ref.invalidate(notificationInboxProvider),
              )
            : ErrorState(
                error: error,
                onRetry: () => ref.invalidate(notificationInboxProvider),
              ),
        loading: () => isExample
            ? _ExampleInboxSkeleton(desktop: desktop)
            : LoadingState(label: context.tr('Loading notifications')),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    if (!notification.isRead) {
      await ref
          .read(notificationInboxActionProvider.notifier)
          .setRead(notification.id, read: true);
    }
    if (!context.mounted) return;
    context.go(safeNotificationRoute(notification.route));
  }
}

/// Reading measure of the inbox column: wide enough for a two-line message,
/// narrow enough that a title never runs the width of a desktop window.
const double _inboxMeasure = 720;

/// Day sections of the inbox, in both themes: one [ExampleListGroup] per day,
/// rows on hairlines, unread carried by a 6 px iris dot instead of a lit
/// tile.
///
/// A utility screen. No arrival moment, no stagger, no per-row animation;
/// the only motion is the 200 ms state swap when a row is read and the
/// counter above the list changes.
class _ExampleInbox extends StatelessWidget {
  const _ExampleInbox({
    required this.items,
    required this.desktop,
    required this.unread,
    required this.onOpen,
  });

  final List<AppNotification> items;
  final bool desktop;
  final int unread;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final recent = <AppNotification>[];
    final previous = <AppNotification>[];
    final earlier = <AppNotification>[];
    for (final item in items) {
      final day = DateUtils.dateOnly(item.createdAt.toLocal());
      if (day == today) {
        recent.add(item);
      } else if (day == yesterday) {
        previous.add(item);
      } else {
        earlier.add(item);
      }
    }
    final sections = <MapEntry<String, List<AppNotification>>>[
      if (recent.isNotEmpty) MapEntry('Today', recent),
      if (previous.isNotEmpty) MapEntry('Yesterday', previous),
      if (earlier.isNotEmpty) MapEntry('Earlier', earlier),
    ];

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        desktop ? 40 : AppSpacing.md,
        desktop ? AppSpacing.lg : AppSpacing.sm,
        desktop ? 40 : AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _inboxMeasure),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InboxHeader(unread: unread),
                const SizedBox(height: AppSpacing.md),
                for (var index = 0; index < sections.length; index++) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.lg),
                  ExampleListGroup(
                    title: sections[index].key,
                    children: [
                      for (final item in sections[index].value)
                        ExampleNotificationTile(
                          notification: item,
                          onTap: () => onOpen(item),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Read-state summary above the notification list.
class _InboxHeader extends StatelessWidget {
  const _InboxHeader({required this.unread});

  final int unread;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExampleStateSwitch(
            alignment: Alignment.centerLeft,
            child: unread > 0
                ? ExamplePill(
                    key: ValueKey('unread-$unread'),
                    label: unread == 1
                        ? context.tr('1 unread')
                        : context.tr('{p0} unread', {'p0': unread}),
                    color: ExampleColors.iris,
                    dot: true,
                    fontSize: 11,
                  )
                : ExamplePill(
                    key: const ValueKey('read'),
                    label: context.tr('All caught up'),
                    color: ExampleColors.success,
                    fontSize: 11,
                  ),
          ),
        ],
      );
}

/// Shape-matched placeholder for the inbox: one group of rows under one soft
/// sheen, rather than five blocks each on their own clock.
class _ExampleInboxSkeleton extends StatelessWidget {
  const _ExampleInboxSkeleton({required this.desktop});

  final bool desktop;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(
          desktop ? 40 : AppSpacing.md,
          desktop ? AppSpacing.lg : AppSpacing.sm,
          desktop ? 40 : AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _inboxMeasure),
              child: Semantics(
                label: context.tr('Loading notifications'),
                child: ExcludeSemantics(
                  // The sheen clips what it wraps, so the daylight ambient
                  // under the group is drawn outside it. On Twilight
                  // `ambientOf` is empty and this box paints nothing.
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: ExampleShadows.ambientOf(context),
                    ),
                    child: ExampleSheen(
                      intensity: ExampleSheenIntensity.soft,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      child: const ExampleListGroup(
                        children: [
                          ExampleSkeleton.row(sheen: false),
                          ExampleSkeleton.row(sheen: false),
                          ExampleSkeleton.row(sheen: false),
                          ExampleSkeleton.row(sheen: false),
                          ExampleSkeleton.row(sheen: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

/// One inbox row. Shared by the full-page inbox and the desktop popover:
/// [compact] tightens the paddings and the tile for the popover, [divider]
/// draws the hairline when the row is not inside a [ExampleListGroup].
///
/// Unread is a 6 px iris dot and an iris tile, never a lit background — a
/// list of unread rows should read as a list, not as a wall of highlights.
/// Read and unread swap through [ExampleStateSwitch] inside fixed-size slots,
/// so marking a row read moves no layout.
class ExampleNotificationTile extends StatelessWidget {
  const ExampleNotificationTile({
    required this.notification,
    required this.onTap,
    this.compact = false,
    this.divider = false,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  final bool compact;

  /// Hairline under the row. Leave it false inside a [ExampleListGroup],
  /// which draws its own separators.
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    final destination = notificationDestinationLabel(notification.route);
    final body = notification.body.trim();
    final time = notificationTime(notification.createdAt);
    return ExampleRow(
      minHeight: compact ? 52 : 60,
      padding: compact
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            )
          : ExampleRow.defaultPadding,
      leading: ExampleStateSwitch(
        // Unread wears the iris tile and the *filled* glyph; read is the
        // outlined glyph, bare, in the secondary ink. Three form differences
        // — fill, container, weight of mark — so the two states are still
        // plainly two in greyscale, at 200 % zoom, and for the roughly one
        // reader in twelve who cannot use the iris to tell them apart. Both
        // resolve per theme, and the swap happens inside the row's fixed
        // 40 pt leading slot, so nothing moves.
        child: unread
            ? ExampleIconTile(
                key: const ValueKey(true),
                icon: _destinationIcon(destination, unread: true),
                color: ExampleColors.iris,
                size: compact ? 30 : 34,
                radius: compact ? 9 : 10,
              )
            : Icon(
                _destinationIcon(destination, unread: false),
                key: const ValueKey(false),
                size: 20,
                color: ExampleInk.secondary(context),
              ),
      ),
      title: notification.title,
      titleMaxLines: null,
      subtitle: body.isEmpty ? destination : body,
      subtitleMaxLines: null,
      trailing: _NotificationMeta(time: time, unread: unread),
      divider: divider,
      onTap: onTap,
      semanticsLabel: [
        unread ? 'Unread notification' : 'Notification',
        notification.title,
        if (body.isNotEmpty) body,
        time,
        'Opens $destination',
      ].join('. '),
    );
  }
}

/// Trailing slot of an inbox row: the timestamp in the tertiary ink over a
/// fixed 6 px marker slot.
class _NotificationMeta extends StatelessWidget {
  const _NotificationMeta({required this.time, required this.unread});

  final String time;
  final bool unread;

  /// The unread marker. Six pixels of iris is the whole signal.
  static const double _dot = 6;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              time,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                height: 1.3,
                color: ExampleInk.tertiary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            SizedBox(
              width: _dot,
              height: _dot,
              child: ExampleStateSwitch(
                child: unread
                    ? DecoratedBox(
                        key: const ValueKey(true),
                        decoration: BoxDecoration(
                          color: ExampleInk.accent(context, ExampleColors.iris),
                          shape: BoxShape.circle,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey(false)),
              ),
            ),
          ],
        ),
      );
}

/// Glyph for where a notification leads. The icon carries the destination so
/// the row's text column can spend its width on the message — and it carries
/// read state too: [unread] takes the filled cut of the same mark, read
/// takes the outline. Same symbol, two weights, no second colour.
IconData _destinationIcon(String destination, {required bool unread}) =>
    switch (destination) {
      'Wallets' => unread
          ? Icons.account_balance_wallet_rounded
          : Icons.account_balance_wallet_outlined,
      'Activity' =>
        unread ? Icons.receipt_long_rounded : Icons.receipt_long_outlined,
      'Cards' =>
        unread ? Icons.credit_card_rounded : Icons.credit_card_outlined,
      'Accounts' =>
        unread ? Icons.account_balance_rounded : Icons.account_balance_outlined,
      'Verification' =>
        unread ? Icons.verified_user_rounded : Icons.verified_user_outlined,
      'Business' =>
        unread ? Icons.business_center_rounded : Icons.business_center_outlined,
      'Rewards' =>
        unread ? Icons.card_giftcard_rounded : Icons.card_giftcard_outlined,
      _ =>
        unread ? Icons.notifications_rounded : Icons.notifications_none_rounded,
    };

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NeoSurfaceCard(
      color: notification.isRead
          ? colors.surface
          : colors.primary.withValues(alpha: 0.10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            notification.isRead
                ? Icons.notifications_none_rounded
                : Icons.notifications_active_rounded,
            color:
                notification.isRead ? colors.onSurfaceVariant : colors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (notification.body.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  notificationTime(notification.createdAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

String notificationTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inDays > 0) return '${difference.inDays}d ago';
  if (difference.inHours > 0) return '${difference.inHours}h ago';
  if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
  return 'Just now';
}

String safeNotificationRoute(String value) {
  final route = value.trim();
  if (!route.startsWith('/') || route.startsWith('//')) return '/home';
  const prefixes = [
    '/home',
    '/activity',
    '/accounts',
    '/cards',
    '/kyc',
    '/business',
    '/onboarding/banking',
    '/wallets',
    '/transactions',
    '/rewards',
    '/send',
    '/support',
  ];
  return prefixes.any(
    (prefix) => route == prefix || route.startsWith('$prefix/'),
  )
      ? route
      : '/home';
}

/// Human label for where a notification leads, instead of the raw route.
String notificationDestinationLabel(String route) {
  final safe = safeNotificationRoute(route);
  if (safe.startsWith('/wallets')) return 'Wallets';
  if (safe.startsWith('/activity') || safe.startsWith('/transactions')) {
    return 'Activity';
  }
  if (safe.startsWith('/cards')) return 'Cards';
  if (safe.startsWith('/accounts')) return 'Accounts';
  if (safe.startsWith('/kyc') || safe.startsWith('/onboarding')) {
    return 'Verification';
  }
  if (safe.startsWith('/business')) return 'Business';
  if (safe.startsWith('/rewards')) return 'Rewards';
  if (safe.startsWith('/support')) return 'Support tickets';
  if (safe.startsWith('/send')) return 'Send & request';
  return 'Home';
}

/// The inbox with nothing in it.
///
/// This is not an edge case. An account in good standing generates a handful
/// of notifications a month, so an empty inbox is what most customers see
/// most of the times they open this screen — which makes it the screen's
/// primary composition, not its fallback. Every wallet in the category ships
/// a grey bell and the word "None", which turns the most-viewed state into
/// the least-designed one.
///
/// So the empty state answers the question the emptiness raises: it is not
/// broken, and here is what will land here when it does. Three lines, in the
/// footnote register, on a hairline rather than in cards — the space around
/// the composition is doing the work, and a card grid here would be three
/// pieces of furniture standing in for nothing at all.
class _ExampleInboxEmpty extends StatelessWidget {
  const _ExampleInboxEmpty();

  /// Only destinations this inbox can actually route to; a promise of
  /// notifications the product does not send is worse than no promise.
  static const List<(IconData, String, String)> _arrivals = [
    (
      Icons.account_balance_wallet_outlined,
      'Money',
      'Payments in and out of your accounts',
    ),
    (
      Icons.credit_card_outlined,
      'Cards',
      'Freezes, limits and delivery updates',
    ),
    (
      Icons.verified_user_outlined,
      'Verification',
      'Anything your application still needs',
    ),
  ];

  /// Measure of the composition. Wide enough for a two-line description,
  /// narrow enough that the block stays a block on a 1440 window instead of
  /// becoming three very long rules.
  static const double _measure = 360;

  @override
  Widget build(BuildContext context) => ListView(
        // Inside a RefreshIndicator: an empty inbox still has to be
        // pullable, or the one gesture that could fix a stale list is dead
        // exactly where a customer is most likely to doubt the screen.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xxl,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _measure),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExampleEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: context.tr('You are all caught up'),
                    body: context.tr('Nothing needs your attention right now.'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: ExampleBorders.hairlineSideOf(context).color,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    context.tr('WHAT ARRIVES HERE'),
                    style: ExampleTextStyles.label(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (var index = 0; index < _arrivals.length; index++) ...[
                    if (index > 0) const SizedBox(height: AppSpacing.sm),
                    _ArrivalLine(
                      icon: _arrivals[index].$1,
                      title: _arrivals[index].$2,
                      detail: _arrivals[index].$3,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
}

/// One thing that will arrive in the inbox. Deliberately not a [ExampleRow]:
/// nothing here is tappable, and borrowing the row rhythm would promise a
/// destination that does not exist yet.
class _ArrivalLine extends StatelessWidget {
  const _ArrivalLine({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 16,
              // Secondary ink over the page and the shell atmosphere:
              // 6.70:1 at the brightest daylight peak and 7.3:1 or better on
              // Twilight, against a 3:1 floor for a glyph.
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
