import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/auth_token_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../data/assistant_api.dart';
import 'assistant_answer.dart';

/// Private, ephemeral account conversation. Never written to travel history.
class AssistantSpendingPanel extends ConsumerStatefulWidget {
  const AssistantSpendingPanel({super.key});
  @override
  ConsumerState<AssistantSpendingPanel> createState() =>
      _AssistantSpendingPanelState();
}

class _ActivityTurn {
  const _ActivityTurn(this.question, this.result);
  final String question;
  final AssistantSpendingResult result;
}

class _AssistantSpendingPanelState extends ConsumerState<AssistantSpendingPanel>
    with WidgetsBindingObserver {
  final _question = TextEditingController(
      text:
          'Summarise all my account activity: money in, money out, transfers and fees.');
  final _scroll = ScrollController();
  final _overviewScroll = ScrollController();
  final _turns = <_ActivityTurn>[];
  String _period = 'this_month';
  String? _error;
  CancelToken? _cancel;
  bool _busy = false;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _clear() {
    _epoch++;
    _cancel?.cancel();
    _turns.clear();
    _question.clear();
    _error = null;
    _busy = false;
  }

  @override
  void dispose() {
    _clear();
    _question.dispose();
    _scroll.dispose();
    _overviewScroll.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      setState(_clear);
    }
  }

  void _scrollToReply() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut);
        }
      });

  Future<void> _analyse() async {
    final question = _question.text.trim();
    if (_busy || question.isEmpty || question.length > 1500) return;
    final epoch = ++_epoch;
    final generation = ref.read(authSessionGenerationProvider);
    final cancel = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(assistantApiProvider).analyseSpending(
          period: _period,
          message: question,
          previousQuestions: _turns.reversed
              .where((t) => !t.result.reply.refused)
              .take(6)
              .toList()
              .reversed
              .map((t) => t.question)
              .toList(),
          locale: AppLocalizations.of(context).locale.toLanguageTag(),
          cancelToken: cancel);
      if (!mounted ||
          epoch != _epoch ||
          cancel.isCancelled ||
          generation != ref.read(authSessionGenerationProvider)) {
        return;
      }
      setState(() {
        _turns.add(_ActivityTurn(question, result));
        if (_turns.length > 20) _turns.removeAt(0);
        _question.clear();
      });
      _scrollToReply();
    } catch (error) {
      if (!mounted || epoch != _epoch || cancel.isCancelled) return;
      final status = error is DioException ? error.response?.statusCode : null;
      setState(() => _error = status == 429
          ? 'Your Ask AI limit has been reached. Try again later.'
          : status == 400
              ? 'Check your question and remove any card numbers, passwords or security codes.'
              : 'We could not verify complete account activity. Try a shorter period or view Activity.');
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  String _amount(num value) {
    var text = value.toStringAsFixed(8);
    while (text.endsWith('0') && text.length - text.indexOf('.') > 3) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionGenerationProvider, (_, __) {
      setState(_clear);
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
    final size = MediaQuery.sizeOf(context);
    final desktop = size.width >= 1050 &&
        size.height >= 640 &&
        MediaQuery.textScalerOf(context).scale(16) <= 22.4;
    if (desktop) return _desktop(context, size);
    final theme = Theme.of(context);
    return Dialog.fullscreen(
        child: Scaffold(
      appBar: AppBar(
          title: Text(context.tr('My account activity')),
          leading: IconButton(
              tooltip: context.tr('Close'),
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop())),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(children: [
                Expanded(
                    child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(20),
                        children: [
                      Text(context.tr('Your account, explained'),
                          style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                          context.tr(
                              'Ask about deposits, transfers, withdrawals, card payments, exchanges, fees and pending activity.'),
                          style: const TextStyle(height: 1.5)),
                      const SizedBox(height: 12),
                      _periodSelector(context),
                      const SizedBox(height: 8),
                      _privacy(context),
                      ..._suggestions(context),
                      ..._summary(context),
                      ..._conversation(context),
                    ])),
                _mobileComposer(context),
              ]))),
    ));
  }

  Widget _desktop(BuildContext context, Size size) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Dialog(
      key: const ValueKey('activity-desktop-dialog'),
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
          width: 1360,
          height: (size.height - 48).clamp(0, 900),
          child: Column(children: [
            Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
                child: Row(children: [
                  Icon(Icons.insights_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(context.tr('My account activity'),
                          style: theme.textTheme.titleLarge)),
                  IconButton(
                      tooltip: context.tr('Close'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop()),
                ])),
            const Divider(height: 1),
            Expanded(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  SizedBox(
                      width: 320,
                      child: Material(
                          color: colors.surfaceContainerLow,
                          child: Scrollbar(
                              controller: _overviewScroll,
                              thumbVisibility: true,
                              child: ListView(
                                  key: const ValueKey(
                                      'activity-desktop-overview'),
                                  controller: _overviewScroll,
                                  padding: const EdgeInsets.all(24),
                                  children: [
                                    Text(context.tr('Account overview'),
                                        style: theme.textTheme.titleMedium),
                                    const SizedBox(height: 8),
                                    Text(
                                        context.tr(
                                            'Choose a period to explore your activity.'),
                                        style: theme.textTheme.bodyMedium),
                                    const SizedBox(height: 24),
                                    _periodSelector(context),
                                    const SizedBox(height: 12),
                                    _privacy(context),
                                    ..._summary(context),
                                    if (_turns.isEmpty)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 24),
                                          child: Text(
                                              context.tr(
                                                  'Your recorded totals will appear here after you analyse your activity.'),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant,
                                                      height: 1.5))),
                                  ])))),
                  const VerticalDivider(width: 1),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        Padding(
                            padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
                            child: Row(children: [
                              Expanded(
                                  child: Text(
                                      context.tr('Your account, explained'),
                                      style: theme.textTheme.titleLarge)),
                              if (_busy)
                                const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                            ])),
                        Expanded(
                            child: Scrollbar(
                                controller: _scroll,
                                thumbVisibility: true,
                                child: ListView(
                                    key: const ValueKey(
                                        'activity-desktop-conversation'),
                                    controller: _scroll,
                                    padding: const EdgeInsets.fromLTRB(
                                        28, 8, 28, 24),
                                    children: [
                                      if (_turns.isEmpty) ...[
                                        Text(
                                            context.tr(
                                                'Ask about deposits, transfers, withdrawals, card payments, exchanges, fees and pending activity.'),
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                    height: 1.6,
                                                    color: colors
                                                        .onSurfaceVariant)),
                                        const SizedBox(height: 28),
                                        ..._desktopQuestions(context),
                                      ],
                                      ..._conversation(context),
                                    ]))),
                        const Divider(height: 1),
                        _desktopComposer(context),
                      ])),
                ])),
          ])),
    );
  }

  List<Widget> _desktopQuestions(BuildContext context) {
    const prompts = [
      (Icons.swap_vert, 'Money in and out', 'How much came in and went out?'),
      (
        Icons.payments_outlined,
        'Largest transfers',
        'Which transfers were the largest?'
      ),
      (
        Icons.receipt_long_outlined,
        'Fees and charges',
        'What fees were recorded?'
      ),
      (
        Icons.pending_actions_outlined,
        'Pending or failed',
        'Which transactions are pending or failed?'
      ),
    ];
    return [
      for (final prompt in prompts)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton(
                onPressed:
                    _busy ? null : () => _question.text = context.tr(prompt.$3),
                style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.all(18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: Row(children: [
                  Icon(prompt.$1, size: 22),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(context.tr(prompt.$2),
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(context.tr(prompt.$3),
                            style: Theme.of(context).textTheme.bodyMedium),
                      ])),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward, size: 18),
                ])))
    ];
  }

  Widget _desktopComposer(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 18),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _question,
                enabled: !_busy,
                maxLength: 1500,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: context.tr(_turns.isEmpty
                        ? 'What would you like to understand?'
                        : 'Ask a follow-up question'))),
            const SizedBox(height: 4),
            Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                      context.tr(
                          _turns.isEmpty
                              ? 'Uses one of your 50 daily Ask AI requests.'
                              : '{p0} requests left today',
                          _turns.isEmpty
                              ? {}
                              : {
                                  'p0': _turns.last.result.reply.usage.remaining
                                }),
                      style: Theme.of(context).textTheme.bodySmall),
                  FilledButton.icon(
                      onPressed: _busy ? null : _analyse,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      label: Text(context.tr(_busy
                          ? 'Analysing…'
                          : _turns.isEmpty
                              ? 'Share activity & analyse'
                              : 'Ask about my activity'))),
                ]),
          ]));

  Widget _periodSelector(BuildContext context) =>
      DropdownButtonFormField<String>(
          key: ValueKey(_period),
          initialValue: _period,
          decoration: InputDecoration(labelText: context.tr('Period (UTC)')),
          isExpanded: true,
          items: [
            for (final item in const {
              'this_month': 'This month',
              'last_month': 'Last month',
              'last_90_days': 'Last 90 days'
            }.entries)
              DropdownMenuItem(
                  value: item.key, child: Text(context.tr(item.value)))
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _clear();
                    _period = value!;
                  }));

  Widget _privacy(BuildContext context) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('Your data and privacy')),
          children: [
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(context.tr(
                    'With your permission, AI via OpenRouter receives dated activity amounts, currencies, types, statuses, categories and totals for this period. Names, account/card numbers, payment references and raw descriptions are removed. Only your signed-in account is used. This conversation is cleared when closed or backgrounded.')))
          ]);

  List<Widget> _suggestions(BuildContext context) {
    final theme = Theme.of(context);
    return [
      if (_turns.isEmpty) ...[
        const SizedBox(height: 12),
        Text(context.tr('Try a question'), style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final prompt in const [
            'How much came in and went out?',
            'Which transfers were the largest?',
            'What fees were recorded?',
            'Which transactions are pending or failed?'
          ])
            ActionChip(
                label: Text(context.tr(prompt)),
                onPressed: _busy
                    ? null
                    : () {
                        _question.text = context.tr(prompt);
                      })
        ]),
      ],
    ];
  }

  List<Widget> _summary(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _turns.isEmpty ? null : _turns.last.result.summary;
    return [
      if (summary != null) ...[
        const SizedBox(height: 16),
        Text(context.tr('Recorded account activity'),
            style: theme.textTheme.titleMedium),
        Text('${summary.from} – ${summary.to} · UTC'),
        for (final currency in summary.activity)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${currency.currency} · ${currency.count} ${context.tr('records')}',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                            '${context.tr('Money in')}: ${currency.currency} ${_amount(currency.incoming)}'),
                        Text(
                            '${context.tr('Money out')}: ${currency.currency} ${_amount(currency.outgoing)}'),
                        Text(
                            '${context.tr('Net flow')}: ${currency.currency} ${_amount(currency.net)}'),
                        if (currency.pending > 0 || currency.failed > 0)
                          Text(
                              '${context.tr('Pending')}: ${currency.pending} · ${context.tr('Failed')}: ${currency.failed}'),
                        if (currency.internal > 0 || currency.related > 0)
                          Text(
                              '${context.tr('Internal movements')}: ${currency.internal} · ${context.tr('Related records')}: ${currency.related}'),
                      ]))),
        Text(
            context.tr(
                'Cash flow counts completed external movements. Internal transfers, related ledger records and pending/failed amounts are kept separate. Currencies are never combined.'),
            style: theme.textTheme.bodySmall),
      ],
    ];
  }

  List<Widget> _conversation(BuildContext context) {
    final theme = Theme.of(context);
    return [
      for (final turn in _turns) ...[
        const SizedBox(height: 20),
        Align(
            alignment: Alignment.centerRight,
            child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(turn.question,
                    style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer)))),
        const SizedBox(height: 12),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: AssistantAnswer(
                    text: turn.result.reply.reply,
                    answer: turn.result.reply.answer))),
      ],
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(context.tr(_error!))),
    ];
  }

  Widget _mobileComposer(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
        top: false,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                      controller: _question,
                      enabled: !_busy,
                      maxLength: 1500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                          labelText: context.tr(_turns.isEmpty
                              ? 'What would you like to understand?'
                              : 'Ask a follow-up question'))),
                  FilledButton.icon(
                      onPressed: _busy ? null : _analyse,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.insights_outlined),
                      label: Text(context.tr(_busy
                          ? 'Analysing…'
                          : _turns.isEmpty
                              ? 'Share activity & analyse'
                              : 'Ask about my activity'))),
                  const SizedBox(height: 6),
                  Text(
                      context.tr(
                          _turns.isEmpty
                              ? 'Uses one of your 50 daily Ask AI requests.'
                              : '{p0} requests left today',
                          _turns.isEmpty
                              ? {}
                              : {
                                  'p0': _turns.last.result.reply.usage.remaining
                                }),
                      style: theme.textTheme.bodySmall),
                ])));
  }
}
