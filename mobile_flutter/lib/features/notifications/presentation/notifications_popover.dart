import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../application/notification_inbox_providers.dart';
import '../domain/app_notification.dart';
import 'notification_inbox_screen.dart';

/// Desktop: the bell opens this anchored panel under the app bar instead of
/// navigating away. Tapping an item marks it read and follows its route.
Future<void> showNotificationsPopover(BuildContext context) {
  return showDialog<void>(
    context: context,
    // The scrim is a different job in each theme. On Twilight the panel is
    // lighter than the page, so black .25 pushes the page down and away —
    // the historical value, unchanged. On paper the panel is *white on
    // white*, so a heavy dim would read as a full modal for what is a
    // glance surface; night at .14 is just enough separation to say the
    // page behind is inert, and it keeps Example's violet cast instead of
    // greying the daylight out.
    barrierColor: ExampleTheme.isLight(context)
        ? context.brandDesign
            .color(Theme.of(context).brightness, 'ink',
                fallback: ExampleColors.night)
            .withValues(alpha: .14)
        : Colors.black.withValues(alpha: .25),
    builder: (_) => const Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(top: 64, right: AppSpacing.md),
        child: _NotificationsPanel(),
      ),
    ),
  );
}

/// The popover itself: the one frosted panel in the notifications surface,
/// floating over the shell's atmosphere in both themes.
///
/// It sizes itself to the window, so the same panel fits a 1440 desktop and
/// a 375 phone without clipping: 400 px at most, and always 32 px narrower
/// than the viewport. There is no sheen scope inside a dialog route, so the
/// loading blocks carry the static soft highlight rather than a ticker.
class _NotificationsPanel extends ConsumerWidget {
  const _NotificationsPanel();

  /// Widest the panel ever gets; below that it follows the window.
  static const double _maxWidth = 400;

  /// Rows shown before the panel defers to the full inbox.
  static const int _maxRows = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationInboxProvider);
    final action = ref.watch(notificationInboxActionProvider);
    final items = inbox.valueOrNull ?? const <AppNotification>[];
    final unread = items.where((item) => !item.isRead).length;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(_maxWidth, size.width - 2 * AppSpacing.md);
    final maxHeight = math.min(620.0, math.max(240.0, size.height - 120));
    final borderRadius = BorderRadius.circular(AppRadii.lg);

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: ExampleShadows.liftOf(context),
          ),
          child: ExampleGlassPanel(
            material: ExampleGlassMaterial.frosted,
            radius: AppRadii.lg,
            padding: EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A header rule and a footer rule, so the panel reads as one
                // three-part object rather than a list that happens to have
                // things stuck above and below it.
                _PopoverHeader(
                  unread: unread,
                  onReadAll: action.isLoading || unread == 0
                      ? null
                      : () => ref
                          .read(notificationInboxActionProvider.notifier)
                          .readAll(),
                ),
                const _PopoverRule(),
                Flexible(
                  child: inbox.when(
                    data: (list) => list.isEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  AppSpacing.xs,
                                  AppSpacing.md,
                                  AppSpacing.md,
                                ),
                                child: ExampleEmptyState(
                                  compact: true,
                                  icon: Icons.notifications_none_rounded,
                                  // The same sentence the full inbox uses.
                                  // Two surfaces describing one state in two
                                  // different voices is how an app starts
                                  // feeling assembled rather than designed.
                                  title: context.tr('You are all caught up'),
                                  body: context.tr(
                                      'Nothing needs your attention right now.'),
                                ),
                              ),
                            ],
                          )
                        : _PopoverList(
                            items: list.length > _maxRows
                                ? list.sublist(0, _maxRows)
                                : list,
                            onOpen: (item) => _open(context, ref, item),
                          ),
                    error: (error, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md,
                            AppSpacing.xs,
                            AppSpacing.md,
                            AppSpacing.md,
                          ),
                          child: ExampleErrorState(
                            compact: true,
                            title: context.tr('Notifications did not load'),
                            error: error,
                          ),
                        ),
                      ],
                    ),
                    loading: () => const _PopoverSkeleton(),
                  ),
                ),
                const _PopoverRule(),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor:
                          ExampleInk.accent(context, ExampleColors.iris),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(AppRadii.lg),
                        ),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.go(AppRoutes.notifications);
                    },
                    // Says how much is being left behind when the panel is
                    // truncating. "View all" over a list that is already
                    // complete is a link to the same eight rows.
                    child: Text(
                      items.length > _maxRows
                          ? context.tr('View all {p0} notifications',
                              {'p0': items.length})
                          : context.tr('View all notifications'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification item,
  ) async {
    if (!item.isRead) {
      await ref
          .read(notificationInboxActionProvider.notifier)
          .setRead(item.id, read: true);
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    context.go(safeNotificationRoute(item.route));
  }
}

/// Title, the unread count as a numeric badge, and the two icon actions.
/// Everything but the title is a fixed width, and the title is the only
/// flexible child, so the header holds its shape down to 375 px.
class _PopoverHeader extends StatelessWidget {
  const _PopoverHeader({required this.unread, required this.onReadAll});

  final int unread;
  final VoidCallback? onReadAll;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      context.tr('Notifications'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                  ),
                  if (unread > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Semantics(
                      label: context.tr('{p0} unread', {'p0': unread}),
                      child: ExcludeSemantics(
                        child: ExamplePill(
                          label: '$unread',
                          color: ExampleColors.iris,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: context.tr('Mark all as read'),
              onPressed: onReadAll,
              icon: const Icon(Icons.done_all_rounded, size: 18),
              color: ExampleInk.primary(context),
            ),
            IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 18),
              color: ExampleInk.primary(context),
            ),
          ],
        ),
      );
}

/// The rule under the header and over the footer. One pixel, the panel's own
/// hairline in both themes.
class _PopoverRule extends StatelessWidget {
  const _PopoverRule();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: ColoredBox(color: ExampleBorders.hairlineSideOf(context).color),
      );
}

/// The rows themselves: the same [ExampleNotificationTile] the full inbox
/// uses, compact, on hairlines rather than in a group — a card inside this
/// panel would be a card inside a card.
class _PopoverList extends StatelessWidget {
  const _PopoverList({required this.items, required this.onOpen});

  final List<AppNotification> items;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) => ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        itemCount: items.length,
        itemBuilder: (context, index) => ExampleNotificationTile(
          notification: items[index],
          compact: true,
          divider: index != items.length - 1,
          onTap: () => onOpen(items[index]),
        ),
      );
}

/// Three shape-matched rows under one soft highlight while the inbox loads.
class _PopoverSkeleton extends StatelessWidget {
  const _PopoverSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Semantics(
          label: context.tr('Loading notifications'),
          child: ExcludeSemantics(
            child: ExampleSheen(
              intensity: ExampleSheenIntensity.soft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExampleSkeleton.row(
                    height: 52,
                    sheen: false,
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  ),
                  ExampleSkeleton.row(
                    height: 52,
                    sheen: false,
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  ),
                  ExampleSkeleton.row(
                    height: 52,
                    sheen: false,
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
