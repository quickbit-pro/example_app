import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/widgets/app_states.dart';
import '../data/peer_transfers_api.dart';

/// Two decimals for every member-transfer currency: "$12.50", "12.50 USDC".
String peerMoney(String currency, double amount) {
  final code = currency.toUpperCase();
  final fixed = amount.abs().toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final fraction = dot < 0 ? '' : fixed.substring(dot);
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  final sign = amount < 0 ? '-' : '';
  return code == 'USD'
      ? '$sign\$$grouped$fraction'
      : '$sign$grouped$fraction $code';
}

/// Server explanations ("Please wait 12 seconds…", "Insufficient balance")
/// beat the generic copy when the API sent one.
String peerErrorText(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      for (final key in const ['detail', 'message', 'title']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty && value.length < 300) {
          return value.trim();
        }
      }
    }
  }
  return friendlyErrorMessage(error);
}

String peerRelativeTime(DateTime time, {DateTime? now, BuildContext? context}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  if (difference.inSeconds < 60) return context?.tr('Just now') ?? 'Just now';
  if (difference.inMinutes < 60) {
    return context?.tr('{p0}m ago', {'p0': difference.inMinutes}) ??
        '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return context?.tr('{p0}h ago', {'p0': difference.inHours}) ??
        '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return context?.tr('{p0}d ago', {'p0': difference.inDays}) ??
        '${difference.inDays}d ago';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${time.day} ${context?.tr(months[time.month - 1]) ?? months[time.month - 1]}';
}

String peerExpiresIn(DateTime expiresAt,
    {DateTime? now, BuildContext? context}) {
  final remaining = expiresAt.difference(now ?? DateTime.now());
  if (remaining.isNegative) return context?.tr('Expired') ?? 'Expired';
  if (remaining.inDays >= 1) {
    return context?.tr('Expires in {p0}d', {'p0': remaining.inDays}) ??
        'Expires in ${remaining.inDays}d';
  }
  if (remaining.inHours >= 1) {
    return context?.tr('Expires in {p0}h', {'p0': remaining.inHours}) ??
        'Expires in ${remaining.inHours}h';
  }
  return context?.tr('Expires soon') ?? 'Expires soon';
}

class PeerAvatar extends StatelessWidget {
  const PeerAvatar({required this.user, this.size = 40, super.key});

  final PeerUser user;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: user.avatarColor,
          boxShadow: [
            BoxShadow(
              color: user.avatarColor.withValues(alpha: .35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          user.initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * .36,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      );
}

Color peerStatusColor(BuildContext context, String status) => switch (status) {
      'completed' || 'accepted' => ExamplePalette.of(context).success,
      'pending' || 'processing' => ExamplePalette.of(context).warning,
      'declined' ||
      'failed' ||
      'needs_attention' =>
        ExamplePalette.of(context).danger,
      _ => ExamplePalette.of(context).textTertiary,
    };

String peerStatusLabel(String status) => switch (status) {
      'completed' => 'Completed',
      'accepted' => 'Paid',
      'pending' => 'Pending',
      'processing' => 'Processing',
      'declined' => 'Declined',
      'expired' => 'Expired',
      'cancelled' => 'Cancelled',
      'refunded' => 'Refunded',
      'failed' => 'Failed',
      'needs_attention' => 'Under review',
      _ => status,
    };

/// One completed / attempted transfer in the activity list.
class PeerTransferTile extends StatelessWidget {
  const PeerTransferTile({required this.transfer, this.onTap, super.key});

  final PeerTransfer transfer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor = !transfer.completed
        ? ExamplePalette.of(context).textTertiary
        : transfer.sent
            ? ExamplePalette.of(context).ink
            : ExamplePalette.of(context).success;
    final prefix = transfer.sent ? '-' : '+';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            PeerAvatar(user: transfer.otherUser),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transfer.otherUser.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ExamplePalette.of(context).ink,
                      fontSize: 14 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    transfer.note?.isNotEmpty == true
                        ? transfer.note!
                        : transfer.completed
                            ? (transfer.sent
                                ? context.tr('Sent')
                                : context.tr('Received'))
                            : peerStatusLabel(transfer.status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ExamplePalette.of(context).textTertiary,
                      fontSize: 12 * context.brandDesign.typographyScale,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$prefix${peerMoney(transfer.currency, transfer.amount)}',
                  style: TextStyle(
                    color: amountColor,
                    fontSize: 14 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  peerRelativeTime(transfer.createdAt, context: context),
                  style: TextStyle(
                    color: ExamplePalette.of(context).textTertiary,
                    fontSize: 11.5 * context.brandDesign.typographyScale,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending or settled request card. Received requests carry Pay / Decline;
/// requests the customer sent carry Cancel while still open.
class PeerRequestTile extends StatelessWidget {
  const PeerRequestTile({
    required this.request,
    this.onPay,
    this.onDecline,
    this.onCancel,
    this.onTap,
    this.busy = false,
    super.key,
  });

  final PeerPaymentRequest request;
  final VoidCallback? onPay;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final name = request.otherUser.fullName;
    final amount = peerMoney(request.currency, request.amount);
    final title = request.sent
        ? context.tr('You asked {p0}', {'p0': name})
        : context.tr('{p0} asks you', {'p0': name});
    return ExampleGlassPanel(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PeerAvatar(user: request.otherUser, size: 38),
              const SizedBox(width: 12),
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
                        fontSize: 13.5 * context.brandDesign.typographyScale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      request.note?.isNotEmpty == true
                          ? request.note!
                          : request.pending
                              ? peerExpiresIn(request.expiresAt,
                                  context: context)
                              : peerRelativeTime(request.createdAt,
                                  context: context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ExamplePalette.of(context).textTertiary,
                        fontSize: 12 * context.brandDesign.typographyScale,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: TextStyle(
                      color: ExamplePalette.of(context).ink,
                      fontSize: 15 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExamplePill(
                    label: request.pending
                        ? (request.sent
                            ? context.tr('Waiting')
                            : context.tr('Pending'))
                        : peerStatusLabel(request.status),
                    color: peerStatusColor(context, request.status),
                    dot: request.pending,
                  ),
                ],
              ),
            ],
          ),
          if (request.pending &&
              (onPay != null || onDecline != null || onCancel != null)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onPay != null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onPay,
                      icon: const Icon(Icons.fingerprint_rounded, size: 18),
                      label: Text(context.tr('Pay {p0}', {'p0': amount})),
                    ),
                  ),
                if (onPay != null && onDecline != null)
                  const SizedBox(width: 8),
                if (onDecline != null)
                  OutlinedButton(
                    onPressed: busy ? null : onDecline,
                    child: Text(context.tr('Decline')),
                  ),
                if (onCancel != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: Text(context.tr('Cancel request')),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PeerDetailRow extends StatelessWidget {
  const PeerDetailRow(
      {required this.label,
      required this.value,
      this.emphasis = false,
      super.key});

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: ExamplePalette.of(context).textSecondary,
                fontSize: 12.5 * context.brandDesign.typographyScale,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: ExamplePalette.of(context).ink,
                  fontSize: emphasis ? 15 : 13,
                  fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
}

Future<void> showPeerTransferDetails(
    BuildContext context, PeerTransfer transfer) {
  return _detailSheet(
    context,
    title: transfer.sent
        ? context.tr('Sent to {p0}', {'p0': transfer.otherUser.fullName})
        : context.tr('Received from {p0}', {'p0': transfer.otherUser.fullName}),
    user: transfer.otherUser,
    rows: [
      PeerDetailRow(
        label: context.tr('Amount'),
        value: peerMoney(transfer.currency, transfer.amount),
        emphasis: true,
      ),
      if (transfer.sent && transfer.fee > 0)
        PeerDetailRow(
            label: context.tr('Fee'),
            value: peerMoney(transfer.currency, transfer.fee)),
      PeerDetailRow(
          label: context.tr('Status'), value: peerStatusLabel(transfer.status)),
      if (transfer.note?.isNotEmpty == true)
        PeerDetailRow(label: context.tr('Note'), value: transfer.note!),
      PeerDetailRow(
          label: context.tr('Date'), value: _fullDate(transfer.createdAt)),
      if (transfer.errorMessage?.isNotEmpty == true)
        PeerDetailRow(
            label: context.tr('Details'), value: transfer.errorMessage!),
      PeerDetailRow(label: context.tr('Reference'), value: transfer.id),
    ],
  );
}

Future<void> showPeerRequestDetails(
    BuildContext context, PeerPaymentRequest request) {
  return _detailSheet(
    context,
    title: request.sent
        ? context.tr('Request to {p0}', {'p0': request.otherUser.fullName})
        : context.tr('Request from {p0}', {'p0': request.otherUser.fullName}),
    user: request.otherUser,
    rows: [
      PeerDetailRow(
        label: context.tr('Amount'),
        value: peerMoney(request.currency, request.amount),
        emphasis: true,
      ),
      PeerDetailRow(
          label: context.tr('Status'), value: peerStatusLabel(request.status)),
      if (request.note?.isNotEmpty == true)
        PeerDetailRow(label: context.tr('Note'), value: request.note!),
      PeerDetailRow(
          label: context.tr('Created'), value: _fullDate(request.createdAt)),
      PeerDetailRow(
        label: request.pending ? context.tr('Expires') : context.tr('Closed'),
        value: _fullDate(request.pending
            ? request.expiresAt
            : (request.respondedAt ?? request.expiresAt)),
      ),
      PeerDetailRow(label: context.tr('Reference'), value: request.id),
    ],
  );
}

Future<void> _detailSheet(
  BuildContext context, {
  required String title,
  required PeerUser user,
  required List<Widget> rows,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: ExamplePalette.of(context).navigation,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PeerAvatar(user: user, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: ExamplePalette.of(context).ink,
                            fontSize: 15 * context.brandDesign.typographyScale,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (user.contactHint.isNotEmpty)
                          Text(
                            user.contactHint,
                            style: TextStyle(
                              color: ExamplePalette.of(context).textTertiary,
                              fontSize:
                                  12 * context.brandDesign.typographyScale,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...rows,
            ],
          ),
        ),
      ),
    );

String _fullDate(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
