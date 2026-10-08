import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/identity/user_nickname.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/formatters/amount_input.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../application/peer_providers.dart';
import '../data/peer_transfers_api.dart';
import 'peer_confirmation.dart';
import 'peer_widgets.dart';

enum PeerComposerMode { send, request }

enum _Step { recipient, amount, review, done }

const peerCurrencies = ['USD', 'USDC', 'USDT'];

/// Opens the composer as a tall sheet on phones; the desktop hub embeds
/// [PeerComposer] directly in its left column.
Future<void> showPeerComposerSheet(
  BuildContext context, {
  PeerComposerMode mode = PeerComposerMode.send,
  PeerUser? recipient,
  ValueChanged<PeerComposerMode>? onModeChanged,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ExamplePalette.of(context).navigation,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => FractionallySizedBox(
        heightFactor: .93,
        child: PeerComposer(
            mode: mode,
            initialRecipient: recipient,
            asSheet: true,
            onModeChanged: onModeChanged),
      ),
    );

/// Revolut-style three-step flow: who → how much → review, then the device
/// confirmation before money moves. The same widget asks for money in
/// [PeerComposerMode.request].
class PeerComposer extends ConsumerStatefulWidget {
  const PeerComposer({
    this.mode = PeerComposerMode.send,
    this.initialRecipient,
    this.asSheet = false,
    this.allowModeSwitch = true,
    this.onModeChanged,
    super.key,
  });

  final PeerComposerMode mode;
  final PeerUser? initialRecipient;
  final bool asSheet;
  final bool allowModeSwitch;
  final ValueChanged<PeerComposerMode>? onModeChanged;

  @override
  ConsumerState<PeerComposer> createState() => _PeerComposerState();
}

class _PeerComposerState extends ConsumerState<PeerComposer> {
  late PeerComposerMode _mode = widget.mode;
  late _Step _step =
      widget.initialRecipient == null ? _Step.recipient : _Step.amount;
  late PeerUser? _recipient = widget.initialRecipient;
  final _searchController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String _currency = 'USD';
  bool _busy = false;
  bool _searching = false;
  String? _searchError;
  PeerFeeInfo? _fee;
  Timer? _feeDebounce;
  Object? _result;
  bool _saveContact = false;

  bool get _isSend => _mode == PeerComposerMode.send;

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    if (_isSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshFee());
    }
  }

  @override
  void dispose() {
    _feeDebounce?.cancel();
    _searchController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _step = _Step.recipient;
      _recipient = null;
      _result = null;
      _fee = null;
      _searchError = null;
      _saveContact = false;
      _searchController.clear();
      _amountController.clear();
      _noteController.clear();
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ─── Recipient ──────────────────────────────────────────────────────────

  Future<void> _lookup() async {
    final query = _searchController.text.trim();
    if (_searching) return;
    final problem = recipientLookupProblem(query);
    if (problem != null) {
      setState(() => _searchError = context.tr(problem));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final api = ref.read(peerTransfersApiProvider);
      final user = await api.lookupQuery(query);
      if (!mounted) return;
      setState(() {
        _recipient = user;
        _saveContact = !user.isContact;
        _step = _Step.amount;
      });
    } catch (error) {
      if (!mounted) return;
      final message = peerErrorText(error);
      setState(() => _searchError =
          message == 'One or more validation errors occurred.'
              ? context.tr(query.contains('@')
                  ? 'Enter a valid email address.'
                  : 'Enter a valid nickname, email address or phone number.')
              : message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pickContact(PeerContact contact) {
    setState(() {
      _recipient = contact.user.copyWith(isContact: true);
      _saveContact = false;
      _step = _Step.amount;
    });
  }

  // ─── Amount ─────────────────────────────────────────────────────────────

  void _onAmountChanged() {
    setState(() {});
    _feeDebounce?.cancel();
    if (!_isSend) return;
    _feeDebounce = Timer(const Duration(milliseconds: 400), _refreshFee);
  }

  Future<void> _refreshFee() async {
    if (!_isSend) return;
    try {
      final fee = await ref.read(peerTransfersApiProvider).feeInfo(
            amount: _amount > 0 ? _amount : null,
            currency: _currency,
          );
      if (mounted) setState(() => _fee = fee);
    } catch (_) {
      // The quota hint is advisory; the send itself re-checks on the server.
    }
  }

  String? get _amountProblem {
    final amount = _amount;
    if (_amountController.text.trim().isEmpty) return null;
    if (amount <= 0) return 'Enter an amount greater than zero.';
    if (amount < 0.01) return 'The minimum is 0.01.';
    if (amount > 1000000) return 'The maximum is 1,000,000.';
    final available = _available;
    if (_isSend && available != null) {
      final total = amount + (_fee?.feeApplies == true ? _fee!.feeAmount : 0);
      if (total > available + 1e-9) {
        return 'That is more than you have available.';
      }
    }
    return null;
  }

  double? get _available {
    final balances = ref.watch(peerAvailableBalancesProvider).valueOrNull;
    return balances?[_currency];
  }

  // ─── Submit ─────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final recipient = _recipient;
    if (recipient == null || _amount <= 0 || _busy) return;
    final api = ref.read(peerTransfersApiProvider);
    final amountLabel = peerMoney(_currency, _amount);
    PeerConfirmation? confirmation;
    if (_isSend) {
      confirmation = await confirmPeerAction(
        context,
        ref,
        reason: 'Confirm sending $amountLabel to ${recipient.fullName}',
      );
      if (confirmation == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final Object result;
      if (_isSend) {
        result = await api.send(
          recipientUserId: recipient.userId,
          amount: _amount,
          currency: _currency,
          note: _noteController.text,
          confirmation: confirmation!,
        );
      } else {
        result = await api.requestMoney(
          fromUserId: recipient.userId,
          amount: _amount,
          currency: _currency,
          note: _noteController.text,
        );
      }
      if (_saveContact) {
        try {
          await api.addContact(recipient.userId);
        } catch (_) {
          // Saving a favourite is a convenience; the transfer already went through.
        }
      }
      invalidatePeerData(ref);
      if (!mounted) return;
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } catch (error) {
      if (!mounted) return;
      _toast(peerErrorText(error));
      unawaited(_refreshFee());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      _Step.recipient => _buildRecipient(),
      _Step.amount => _buildAmount(),
      _Step.review => _buildReview(),
      _Step.done => _buildDone(),
    };
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 14),
        body,
      ],
    );
    if (widget.asSheet) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(child: content),
      );
    }
    return ExampleGlassPanel(
      padding: const EdgeInsets.all(18),
      child: content,
    );
  }

  Widget _buildHeader() {
    final canGoBack =
        _step == _Step.amount && widget.initialRecipient == null ||
            _step == _Step.review;
    return Row(
      children: [
        if (canGoBack)
          IconButton(
            tooltip: context.tr('Back'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy
                ? null
                : () => setState(() {
                      _step = _step == _Step.review
                          ? _Step.amount
                          : _Step.recipient;
                    }),
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
        Expanded(
          child: widget.allowModeSwitch && _step != _Step.done
              ? ExampleSegmentedControl<PeerComposerMode>(
                  segments: [
                    (value: PeerComposerMode.send, label: context.tr('Send')),
                    (
                      value: PeerComposerMode.request,
                      label: context.tr('Request')
                    ),
                  ],
                  selected: _mode,
                  onChanged: _busy
                      ? (_) {}
                      : (value) {
                          setState(() {
                            _mode = value;
                            _fee = null;
                            if (value == PeerComposerMode.send) _refreshFee();
                          });
                          widget.onModeChanged?.call(value);
                        },
                )
              : Text(
                  _isSend
                      ? context.tr('Send money')
                      : context.tr('Request money'),
                  style: TextStyle(
                    color: ExamplePalette.of(context).ink,
                    fontSize: 16 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        if (widget.asSheet)
          IconButton(
            tooltip: context.tr('Close'),
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
      ],
    );
  }

  Widget _buildRecipient() {
    final contacts = ref.watch(peerContactsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isSend
              ? context.tr('Who are you sending to?')
              : context.tr('Who should pay you?'),
          style: TextStyle(
            color: ExamplePalette.of(context).ink,
            fontSize: 15 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('Find any member by nickname, email or phone number.'),
          style: TextStyle(
              color: ExamplePalette.of(context).textTertiary, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchController,
          autofocus: widget.asSheet,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _lookup(),
          onChanged: (_) => setState(() => _searchError = null),
          decoration: InputDecoration(
            labelText: context.tr('Nickname, email or phone number'),
            hintText: context.tr('@nickname, name@example.com or +386 40 …'),
            errorText: _searchError,
            errorMaxLines: 3,
            prefixIcon: const Icon(Icons.person_search_rounded),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    tooltip: context.tr('Find member'),
                    onPressed:
                        _searchController.text.trim().isEmpty ? null : _lookup,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        contacts.when(
          data: (items) => items.isEmpty
              ? Text(
                  context.tr(_isSend
                      ? 'People you send to can be saved as contacts for next time.'
                      : 'People you request money from can be saved as contacts for next time.'),
                  style: TextStyle(
                      color: ExamplePalette.of(context).textTertiary,
                      fontSize: 12),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Contacts'),
                      style: TextStyle(
                        color: ExamplePalette.of(context).textSecondary,
                        fontSize: 11.5 * context.brandDesign.typographyScale,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final contact in items)
                          ActionChip(
                            avatar: PeerAvatar(user: contact.user, size: 24),
                            label: Text(contact.displayName),
                            onPressed: () => _pickContact(contact),
                          ),
                      ],
                    ),
                  ],
                ),
          error: (_, __) => const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAmount() {
    final recipient = _recipient!;
    final available = _available;
    final problem = _amountProblem;
    final fee = _fee;
    final valid =
        _amount > 0 && problem == null && !(fee?.isRateLimited ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecipientBanner(
          user: recipient,
          caption: _isSend
              ? context.tr('Sending to')
              : context.tr('Requesting from'),
          onChange: widget.initialRecipient == null
              ? () => setState(() => _step = _Step.recipient)
              : null,
        ),
        const SizedBox(height: 16),
        ExampleSegmentedControl<String>(
          segments: [
            for (final code in peerCurrencies) (value: code, label: code),
          ],
          selected: _currency,
          onChanged: (value) {
            setState(() => _currency = value);
            _refreshFee();
          },
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _amountController,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          ],
          onChanged: (_) => _onAmountChanged(),
          style: TextStyle(
            color: ExamplePalette.of(context).ink,
            fontSize: 40 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: TextStyle(color: ExamplePalette.of(context).textTertiary),
            prefixText: _currency == 'USD' ? '\$' : null,
            suffixText: _currency == 'USD' ? null : ' $_currency',
            prefixStyle: TextStyle(
              color: ExamplePalette.of(context).ink,
              fontSize: 40 * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w800,
            ),
            suffixStyle: TextStyle(
              color: ExamplePalette.of(context).textSecondary,
              fontSize: 18 * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w700,
            ),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            errorText: problem,
            errorStyle: const TextStyle(fontSize: 12),
          ),
        ),
        if (_isSend)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                available == null
                    ? context.tr('Available balance unavailable')
                    : context.tr('Available {p0}',
                        {'p0': peerMoney(_currency, available)}),
                style: TextStyle(
                    color: ExamplePalette.of(context).textTertiary,
                    fontSize: 12.5),
              ),
              if (available != null && available > 0) ...[
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    _amountController.text =
                        maxAmountInput(available, decimals: 2);
                    _onAmountChanged();
                  },
                  child: Text(context.tr('Max')),
                ),
              ],
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _noteController,
          maxLength: 250,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.tr('Note (optional)'),
            hintText: _isSendNoteHint,
            counterText: '',
            prefixIcon: const Icon(Icons.notes_rounded),
          ),
        ),
        if (_isSend) ...[
          const SizedBox(height: 12),
          _FeeHint(fee: fee, currency: _currency),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: valid ? () => setState(() => _step = _Step.review) : null,
          child: Text(context.tr('Continue')),
        ),
      ],
    );
  }

  static const _isSendNoteHint = 'What is it for?';

  Widget _buildReview() {
    final recipient = _recipient!;
    final fee = _isSend && _fee?.feeApplies == true ? _fee!.feeAmount : 0.0;
    final total = _amount + fee;
    final note = _noteController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: PeerAvatar(user: recipient, size: 64)),
        const SizedBox(height: 12),
        Text(
          _isSend
              ? context.tr('Send {p0}', {'p0': peerMoney(_currency, _amount)})
              : context
                  .tr('Request {p0}', {'p0': peerMoney(_currency, _amount)}),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ExamplePalette.of(context).ink,
            fontSize: 24 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        Text(
          _isSend
              ? context.tr('to {p0}', {'p0': recipient.fullName})
              : context.tr('from {p0}', {'p0': recipient.fullName}),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: ExamplePalette.of(context).textSecondary, fontSize: 13.5),
        ),
        const SizedBox(height: 18),
        ExampleGlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              PeerDetailRow(
                  label: context.tr('Amount'),
                  value: peerMoney(_currency, _amount)),
              if (_isSend)
                PeerDetailRow(
                  label: context.tr('Fee'),
                  value: fee > 0 ? peerMoney(_currency, fee) : 'Free',
                ),
              if (_isSend)
                PeerDetailRow(
                  label: context.tr('Total from your balance'),
                  value: peerMoney(_currency, total),
                  emphasis: true,
                ),
              if (note.isNotEmpty)
                PeerDetailRow(label: context.tr('Note'), value: note),
              if (!_isSend)
                PeerDetailRow(label: context.tr('Expires'), value: 'In 7 days'),
            ],
          ),
        ),
        if (!recipient.isContact) ...[
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _saveContact,
            onChanged: (value) => setState(() => _saveContact = value),
            title: Text(
              context.tr('Save as contact'),
              style: TextStyle(
                  color: ExamplePalette.of(context).ink, fontSize: 13.5),
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: AppProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isSend ? Icons.fingerprint_rounded : Icons.send_rounded,
                  size: 20),
          label: Text(_isSend
              ? context.tr('Confirm and send')
              : context.tr('Send request')),
        ),
        if (_isSend) ...[
          const SizedBox(height: 8),
          Text(
            context.tr(
                'You will confirm with your fingerprint, face or password before the money moves.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: ExamplePalette.of(context).textTertiary,
                fontSize: 11.5 * context.brandDesign.typographyScale,
                height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _buildDone() {
    final recipient = _recipient!;
    final result = _result;
    final title = result is PeerTransfer
        ? context
            .tr('{p0} sent', {'p0': peerMoney(result.currency, result.amount)})
        : context.tr('Request sent');
    final subtitle = result is PeerTransfer
        ? context.tr('{p0} has the money now.', {'p0': recipient.fullName})
        : context.tr('{p0} will be asked to pay {p1}.',
            {'p0': recipient.fullName, 'p1': peerMoney(_currency, _amount)});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ExamplePalette.of(context).success.withValues(alpha: .16),
            border:
                Border.all(color: ExamplePalette.of(context).success, width: 2),
          ),
          child: Icon(Icons.check_rounded,
              color: ExamplePalette.of(context).success, size: 38),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: ExamplePalette.of(context).ink,
            fontSize: 22 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: ExamplePalette.of(context).textSecondary,
              fontSize: 13.5 * context.brandDesign.typographyScale,
              height: 1.4),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () {
            if (widget.asSheet) {
              Navigator.of(context).maybePop();
            } else {
              _reset();
            }
          },
          child: Text(context.tr('Done')),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _reset,
          child: Text(_isSend
              ? context.tr('Send to someone else')
              : context.tr('Request from someone else')),
        ),
      ],
    );
  }
}

class _RecipientBanner extends StatelessWidget {
  const _RecipientBanner(
      {required this.user, required this.caption, this.onChange});

  final PeerUser user;
  final String caption;
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          PeerAvatar(user: user, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  caption,
                  style: TextStyle(
                      color: ExamplePalette.of(context).textTertiary,
                      fontSize: 11.5),
                ),
                Text(
                  user.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ExamplePalette.of(context).ink,
                    fontSize: 15 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (user.contactHint.isNotEmpty)
                  Text(
                    user.contactHint,
                    style: TextStyle(
                        color: ExamplePalette.of(context).textTertiary,
                        fontSize: 12),
                  ),
              ],
            ),
          ),
          if (onChange != null)
            TextButton(onPressed: onChange, child: Text(context.tr('Change'))),
        ],
      );
}

class _FeeHint extends StatelessWidget {
  const _FeeHint({required this.fee, required this.currency});

  final PeerFeeInfo? fee;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final info = fee;
    if (info == null) {
      return Text(
        context.tr('Members get 10 free transfers a day.'),
        style: TextStyle(
            color: ExamplePalette.of(context).textTertiary, fontSize: 12),
      );
    }
    final IconData icon;
    final Color color;
    final String text;
    if (info.isRateLimited) {
      icon = Icons.timer_outlined;
      color = ExamplePalette.of(context).warning;
      text =
          'Wait ${info.rateLimitSecondsRemaining}s before your next transfer.';
    } else if (info.sendsRemainingToday <= 0) {
      icon = Icons.block_outlined;
      color = ExamplePalette.of(context).danger;
      text = 'You have reached today\'s transfer limit.';
    } else if (info.feeApplies) {
      icon = Icons.info_outline_rounded;
      color = ExamplePalette.of(context).warning;
      text =
          'Fee ${peerMoney(currency, info.feeAmount)} (${info.feePercent.toStringAsFixed(0)}%) · free transfers used up for today.';
    } else {
      icon = Icons.check_circle_outline_rounded;
      color = ExamplePalette.of(context).success;
      text =
          'Free · ${info.freeTransfersRemaining} of ${info.freeTransfersPerDay} free transfers left today.';
    }
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
                color: color,
                fontSize: 12 * context.brandDesign.typographyScale,
                height: 1.35),
          ),
        ),
      ],
    );
  }
}
