import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../app/routes.dart';
import '../../../brands/example/example_colors.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/l10n/app_localizations.dart';
import '../data/assistant_api.dart';
import '../data/assistant_preferences_api.dart';
import '../domain/assistant_preferences.dart';
import '../data/assistant_history_storage.dart';
import '../data/assistant_speech_recognizer.dart';
import '../domain/assistant_dictation_controller.dart';
import '../domain/assistant_departure.dart';
import '../domain/assistant_conversation.dart';
import '../domain/assistant_knowledge.dart';
import 'sparkle_icon.dart';
import 'assistant_voice_button.dart';
import 'assistant_departure_picker.dart';
import 'assistant_history_sheet.dart';
import 'assistant_answer.dart';
import 'assistant_quick_entry.dart';
import 'assistant_spending_panel.dart';

final assistantLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

class _Message {
  const _Message({
    required this.text,
    required this.fromUser,
    this.topic,
    this.reply,
    this.includeInHistory = true,
  });

  final String text;
  final bool fromUser;
  final bool includeInHistory;
  final AssistantTopic? topic;
  final AssistantReply? reply;
}

class _PendingQuestion {
  const _PendingQuestion(
      this.text, this.history, this.departure, this.tripDetails);
  final String text;
  final List<AssistantTurn> history;
  final AssistantDeparture? departure;
  final AssistantTripDetails tripDetails;
}

/// Completed conversations are saved locally for this account. Quotas, topic
/// restrictions and search run on the server; New chat never resets allowance.
class AskAiScreen extends ConsumerStatefulWidget {
  const AskAiScreen({super.key});

  @override
  ConsumerState<AskAiScreen> createState() => _AskAiScreenState();
}

class _AskAiScreenState extends ConsumerState<AskAiScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  late final AssistantDictationController _voice;
  AssistantUsage? _usage;
  AssistantTripDetails _tripDetails = const AssistantTripDetails();
  int _quickEntryEpoch = 0;
  AssistantDeparture? _departure;
  AssistantPreferences _preferences = const AssistantPreferences();
  bool _departureEdited = false;
  CancelToken? _preferencesCancel;
  int _accountEpoch = 0;
  String? _conversationId;
  String? _conversationTitle;
  DialogRoute<SavedAssistantConversation>? _historyRoute;
  NavigatorState? _historyNavigator;
  _PendingQuestion? _pending;
  CancelToken? _chatCancel;
  CancelToken? _usageCancel;
  Timer? _resetTimer;
  Timer? _retryTimer;
  int _epoch = 0;
  bool _thinking = false;
  bool _loadingUsage = true;
  bool _coolingDown = false;
  bool _sensitiveInputRejected = false;
  String? _error;
  String? _usageError;

  bool get _localHelp => _usage?.enabled == false;
  bool get _exhausted => !_localHelp && _usage?.remaining == 0;
  bool get _canAsk =>
      _usage != null &&
      !_loadingUsage &&
      !_thinking &&
      !_voice.isActive &&
      !_exhausted &&
      !_coolingDown &&
      _pending == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _voice = AssistantDictationController(
      recognizer: ref.read(assistantSpeechRecognizerProvider)(),
      onDraft: (text) {
        if (!mounted) return;
        _controller.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length));
      },
    )..addListener(_voiceChanged);
    unawaited(_loadUsage());
    unawaited(_loadPreferences());
  }

  void _voiceChanged() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (_voice.isActive &&
        (lifecycle == AppLifecycleState.hidden ||
            lifecycle == AppLifecycleState.paused ||
            lifecycle == AppLifecycleState.detached)) {
      unawaited(_voice.cancel());
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Native permission sheets briefly make the app inactive. Keep the first
    // mic tap alive during that prompt; actual backgrounding always cancels.
    final permissionPrompt =
        state == AppLifecycleState.inactive && _voice.isStarting;
    if (state != AppLifecycleState.resumed && !permissionPrompt) {
      unawaited(_voice.cancel());
    }
    if (state == AppLifecycleState.resumed && !_thinking) {
      unawaited(_loadUsage());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closeHistory();
    _epoch++;
    _chatCancel?.cancel();
    _usageCancel?.cancel();
    _resetTimer?.cancel();
    _retryTimer?.cancel();
    _preferencesCancel?.cancel();
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setUsage(AssistantUsage usage) {
    _usage = usage;
    _resetTimer?.cancel();
    final delay = usage.resetsAt.difference(DateTime.now());
    if (usage.enabled && delay > Duration.zero) {
      _resetTimer = Timer(delay + const Duration(seconds: 1), () {
        if (mounted && !_thinking) unawaited(_loadUsage());
      });
    }
  }

  Future<void> _loadUsage() async {
    final epoch = _epoch;
    _usageCancel?.cancel();
    final token = _usageCancel = CancelToken();
    setState(() {
      _loadingUsage = true;
      _usageError = null;
    });
    try {
      final usage =
          await ref.read(assistantApiProvider).usage(cancelToken: token);
      if (!mounted || epoch != _epoch || token.isCancelled) return;
      setState(() => _setUsage(usage));
    } catch (_) {
      if (!mounted || epoch != _epoch || token.isCancelled) return;
      setState(() {
        _usageError = 'Could not check your daily allowance. Please try again.';
      });
    } finally {
      if (mounted && epoch == _epoch && !token.isCancelled) {
        setState(() => _loadingUsage = false);
      }
    }
  }

  Future<void> _loadPreferences() async {
    final accountEpoch = _accountEpoch;
    _preferencesCancel?.cancel();
    final token = _preferencesCancel = CancelToken();
    try {
      final preferences = await ref
          .read(assistantPreferencesApiProvider)
          .load(cancelToken: token);
      if (!mounted || accountEpoch != _accountEpoch || token.isCancelled) {
        return;
      }
      setState(() {
        _preferences = preferences;
        // Never replace a manual choice, restored chat or an active trip.
        if (!_departureEdited && _messages.isEmpty && _pending == null) {
          _departure ??= preferences.departure;
        }
      });
    } catch (_) {
      // Personalisation is optional. Generic starters remain usable offline;
      // raw onboarding responses/errors never enter a chat or local history.
    }
  }

  void _setTripDetails(AssistantTripDetails details) {
    if (!_canAsk) return;
    final draft = applyAssistantTripDetails(
        _controller.text, _tripDetails.requestText, details.requestText);
    if (draft.length > _messageLimit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context
              .tr('Shorten your question before adding trip details.'))));
      return;
    }
    setState(() => _tripDetails = details);
    _controller.value = TextEditingValue(
        text: draft, selection: TextSelection.collapsed(offset: draft.length));
  }

  void _draftStarter(String text) {
    if (!_canAsk) return;
    final draft = applyAssistantTripDetails(text, '', _tripDetails.requestText);
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
  }

  void _newConversation({bool resetDeparture = false}) {
    if (resetDeparture) _closeHistory();
    unawaited(_voice.cancel());
    _epoch++;
    _chatCancel?.cancel();
    _usageCancel?.cancel();
    _resetTimer?.cancel();
    _retryTimer?.cancel();
    _controller.clear();
    setState(() {
      _tripDetails = const AssistantTripDetails();
      _quickEntryEpoch++;
      if (resetDeparture) {
        _departure = null;
        _departureEdited = false;
        _preferences = const AssistantPreferences();
        _preferencesCancel?.cancel();
        _accountEpoch++;
      }
      _conversationId = null;
      _conversationTitle = null;
      _messages.clear();
      _pending = null;
      _usage = null;
      _thinking = false;
      _coolingDown = false;
      _error = null;
      _sensitiveInputRejected = false;
      _usageError = null;
    });
    unawaited(_loadUsage());
    if (resetDeparture) unawaited(_loadPreferences());
  }

  Future<void> _ask(String question) async {
    final text = question.trim();
    if (!_canAsk || text.isEmpty || text.length > _messageLimit) return;
    unawaited(_voice.cancel());
    final tripDetails = _tripDetails;
    _controller.clear();
    _tripDetails = const AssistantTripDetails();
    _quickEntryEpoch++;
    if (_localHelp) {
      final topic = assistantTopics
              .where((topic) => context.tr(topic.prompt) == text)
              .firstOrNull ??
          matchAssistantTopic(text);
      final email = ref.read(appConfigProvider).branding.supportEmail;
      setState(() {
        _messages
            .add(_Message(text: text, fromUser: true, includeInHistory: false));
        _messages.add(_Message(
          text: topic == null
              ? context.tr(
                  'I do not have an answer for that yet. Try one of the suggested questions, or email {p0} and the team will help.',
                  {'p0': email})
              : context.tr(topic.answer),
          fromUser: false,
          topic: topic,
          includeInHistory: false,
        ));
      });
      _scrollToEnd();
      return;
    }
    final history = _messages
        .where((message) => message.includeInHistory)
        .map((message) => AssistantTurn(
            role: message.fromUser ? 'user' : 'assistant',
            content: message.text))
        .toList(growable: false);
    setState(() {
      _messages.add(_Message(text: text, fromUser: true));
      _pending = _PendingQuestion(text, history, _departure, tripDetails);
    });
    await _sendPending();
  }

  int get _messageLimit =>
      (_usage?.maxMessageCharacters ?? 1500).clamp(1, 1500);

  Future<void> _sendPending() async {
    final pending = _pending;
    if (pending == null || _thinking || _coolingDown || _exhausted) return;
    final epoch = _epoch;
    final token = _chatCancel = CancelToken();
    setState(() {
      _thinking = true;
      _error = null;
      _sensitiveInputRejected = false;
    });
    _scrollToEnd();
    try {
      final reply = await ref.read(assistantApiProvider).chat(
            message: pending.text,
            history: pending.history,
            departure: pending.departure,
            locale: AppLocalizations.of(context).locale.toLanguageTag(),
            cancelToken: token,
          );
      if (!mounted || epoch != _epoch || token.isCancelled) return;
      setState(() {
        _setUsage(reply.usage);
        _pending = null;
        _messages
            .add(_Message(text: reply.reply, fromUser: false, reply: reply));
      });
      unawaited(_saveConversation());
    } catch (error) {
      if (!mounted || epoch != _epoch || token.isCancelled) return;
      setState(() => _error = _friendlyError(error));
      // Attempts can consume allowance even when the provider times out. Read
      // the authoritative count; never estimate or automatically repeat a POST.
      await _loadUsage();
    } finally {
      if (mounted && epoch == _epoch && !token.isCancelled) {
        setState(() => _thinking = false);
        _scrollToEnd();
        if (_usage?.enabled == true &&
            !_usage!.resetsAt.isAfter(DateTime.now())) {
          unawaited(_loadUsage());
        }
      }
    }
  }

  bool Function() _historyGuard(String? owner) {
    // The container outlives this screen. A completed answer can finish saving
    // after Back, but a logout or account switch invalidates that write.
    final container = ProviderScope.containerOf(context, listen: false);
    final generation = container.read(authSessionGenerationProvider);
    return () {
      try {
        return generation == container.read(authSessionGenerationProvider) &&
            owner == container.read(assistantHistoryOwnerProvider);
      } catch (_) {
        return false;
      }
    };
  }

  Future<void> _saveConversation() async {
    final owner = ref.read(assistantHistoryOwnerProvider);
    if (owner == null) return;
    final completed =
        _messages.where((message) => message.includeInHistory).toList();
    if (completed.isEmpty || completed.last.fromUser) return;
    final id = _conversationId ??= createAssistantConversationId();
    final title =
        _conversationTitle ??= assistantConversationTitle(completed.first.text);
    final conversation = SavedAssistantConversation(
      id: id,
      title: title,
      updatedAt: DateTime.now().toUtc(),
      departure: _departure,
      turns: [
        for (final message in completed)
          SavedAssistantTurn(
              role: message.fromUser ? 'user' : 'assistant',
              text: message.text,
              reply: message.reply),
      ],
    );
    final isCurrent = _historyGuard(owner);
    final saved = await ref
        .read(assistantHistoryStorageProvider)
        .save(owner, conversation, isCurrent: isCurrent);
    if (!saved && mounted && isCurrent() && _conversationId == id) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              context.tr('Could not save this conversation on this device.'))));
    }
  }

  void _closeHistory() {
    final route = _historyRoute;
    final navigator = _historyNavigator;
    _historyRoute = null;
    if (route != null) {
      scheduleMicrotask(() {
        if (navigator?.mounted == true && route.isActive) {
          navigator!.removeRoute(route);
        }
      });
    }
  }

  Future<void> _showHistory() async {
    if (_historyRoute != null) return;
    unawaited(_voice.cancel());
    if (_thinking) {
      // Browsing history freezes its completed-turn snapshot. An old request
      // must not save a newer version while the user is selecting that chat.
      _epoch++;
      _chatCancel?.cancel();
      _usageCancel?.cancel();
      setState(() {
        final pending = _pending;
        if (pending != null) {
          _messages.removeLast();
          _tripDetails = pending.tripDetails;
          _controller.text = pending.text;
          _controller.selection =
              TextSelection.collapsed(offset: pending.text.length);
        }
        _pending = null;
        _thinking = false;
        _error = null;
        _sensitiveInputRejected = false;
      });
      unawaited(_loadUsage());
    }
    final owner = ref.read(assistantHistoryOwnerProvider);
    final isCurrent = _historyGuard(owner);
    final storage = ref.read(assistantHistoryStorageProvider);
    final navigator = _historyNavigator = Navigator.of(context);
    final route = _historyRoute = DialogRoute<SavedAssistantConversation>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 560,
          height: MediaQuery.sizeOf(context).height * .75,
          child: AssistantHistorySheet(
            storage: storage,
            owner: owner,
            isCurrent: isCurrent,
            onDeleting: (id) {
              if (mounted && isCurrent() && id == _conversationId) {
                _newConversation();
              }
            },
          ),
        ),
      ),
    );
    final selected = await navigator.push(route);
    if (!mounted || _historyRoute != route || !isCurrent()) return;
    _historyRoute = null;
    if (selected == null) return;
    // Restoring is entirely local. Only the fresh allowance GET runs here.
    _newConversation();
    setState(() {
      _conversationId = selected.id;
      _conversationTitle = selected.title;
      _departure = selected.departure;
      _departureEdited = true;
      _messages.addAll(selected.turns.map((turn) => _Message(
          text: turn.text, fromUser: turn.role == 'user', reply: turn.reply)));
    });
    _scrollToEnd();
  }

  void _back() {
    unawaited(_voice.cancel());
    _chatCancel?.cancel();
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() == true) {
      router!.pop();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      router?.go(AppRoutes.home);
    }
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final code = data is Map ? data['code'] : null;
      if (status == 400 && code == 'assistant.sensitive_input') {
        _sensitiveInputRejected = true;
        return 'Remove card numbers, bank account details, passwords or security codes before sending. Start a new conversation if they appeared in an earlier message.';
      }
      if (status == 429) {
        final retry =
            int.tryParse(error.response?.headers.value('retry-after') ?? '') ??
                30;
        _coolingDown = true;
        _retryTimer?.cancel();
        _retryTimer = Timer(Duration(seconds: retry.clamp(1, 86400)), () {
          if (mounted) setState(() => _coolingDown = false);
        });
        return switch (code) {
          'assistant.daily_limit' =>
            'Daily allowance used. Come back after the reset.',
          'assistant.global_limit' =>
            'The concierge has reached its daily service limit. Please try again tomorrow.',
          'assistant.busy' =>
            'Another concierge request is still running. Please try again in a minute.',
          _ => 'Please wait a minute before sending another question.',
        };
      }
      if (status == 503) {
        return 'The travel concierge is temporarily unavailable. Please try again later.';
      }
      if (status == 401 || status == 403) {
        return 'Please sign in again to use the travel concierge.';
      }
    }
    return 'Your answer could not be loaded. Try again or edit your question.';
  }

  void _editPending() {
    final pending = _pending;
    if (pending == null || _thinking) return;
    setState(() {
      _messages.removeLast();
      _pending = null;
      _error = null;
      _sensitiveInputRejected = false;
      _tripDetails = pending.tripDetails;
      _controller.text = pending.text;
      _controller.selection =
          TextSelection.collapsed(offset: pending.text.length);
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openExternal(String url) async {
    final uri = safeAssistantLink(url);
    if (uri == null) return;
    try {
      if (await ref.read(assistantLinkLauncherProvider)(uri)) return;
    } catch (_) {
      // Launch failures belong to the button action, not the chat response.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.tr('Could not open this link. Please try again.')),
    ));
  }

  Future<void> _showAiInfo() async {
    unawaited(_voice.cancel());
    FocusManager.instance.primaryFocus?.unfocus();
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(context.tr('Ask AI information')),
              scrollable: true,
              content: SizedBox(
                  width: 420,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_usage != null && !_localHelp) ...[
                          _Allowance(usage: _usage!, exhausted: _exhausted),
                          const SizedBox(height: 20),
                        ],
                        Text(context.tr('Privacy'),
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(context.tr(
                            'Do not share card numbers, passwords or security codes.')),
                        const SizedBox(height: 20),
                        Text(context.tr('Voice input'),
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(context.tr(
                            'Voice uses your device or browser speech service. Review the text before sending.')),
                      ])),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(context.tr('Close')))
              ],
            ));
  }

  List<Widget> _footerDetails(BuildContext context) => [
        if (_usage != null && !_localHelp)
          Semantics(
              liveRegion: true,
              excludeSemantics: true,
              label: context.tr('{p0} of {p1} requests left today',
                  {'p0': _usage!.remaining, 'p1': _usage!.dailyLimit}),
              child: Text(
                  context.tr('{p0}/{p1}',
                      {'p0': _usage!.remaining, 'p1': _usage!.dailyLimit}),
                  style: TextStyle(
                      fontSize: 11 * context.brandDesign.typographyScale,
                      color: _exhausted
                          ? ExamplePalette.of(context).accent
                          : ExamplePalette.of(context).textSecondary))),
        IconButton(
            tooltip: context.tr('Ask AI information'),
            onPressed: _showAiInfo,
            icon: const Icon(Icons.info_outline_rounded, size: 18),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40)),
      ];

  Future<void> _showSpending() async {
    unawaited(_voice.cancel());
    await showDialog<void>(
        context: context, builder: (_) => const AssistantSpendingPanel());
    if (mounted) unawaited(_loadUsage());
  }

  Future<void> _showHelp() async {
    final accountEpoch = _accountEpoch;
    final route = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Help')),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final topic in assistantTopics)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(context.tr(topic.prompt)),
                  childrenPadding: const EdgeInsets.only(bottom: 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr(topic.answer),
                        style: const TextStyle(height: 1.5)),
                    if (topic.route != null)
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(topic.route),
                        child: Text(context.tr(topic.routeLabel!)),
                      ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Close')),
          ),
        ],
      ),
    );
    if (!mounted || accountEpoch != _accountEpoch || route == null) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionGenerationProvider,
        (_, __) => _newConversation(resetDeparture: true));
    final accountEpoch = _accountEpoch;
    final brandName = ref.watch(appConfigProvider).branding.appName;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final body = Column(
      children: [
        if (_usage?.enabled == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: AssistantDeparturePicker(
              key: ValueKey('assistant-departure-$accountEpoch'),
              departure: _departure,
              enabled: _canAsk,
              onChanged: (departure) {
                if (!mounted ||
                    accountEpoch != _accountEpoch ||
                    _thinking ||
                    _pending != null) {
                  return;
                }
                setState(() {
                  _departure = departure;
                  _departureEdited = true;
                });
              },
            ),
          ),
        if (_messages.isNotEmpty && _usage?.enabled == true)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _canAsk ? _showSpending : null,
              icon: const Icon(Icons.insights_outlined, size: 18),
              label: Text(context.tr('My account activity')),
            ),
          ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(16, 8, 16, desktop ? 24 : 12),
            children: [
              if (_loadingUsage && _usage == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_usageError != null)
                _Notice(
                  text: context.tr(_usageError!),
                  onRetry: _loadingUsage ? null : _loadUsage,
                ),
              if (_messages.isEmpty && _usage != null)
                _Intro(
                    brandName: brandName,
                    localHelp: _localHelp,
                    onHelp: _showHelp,
                    onSpending: _canAsk ? _showSpending : null,
                    departure: _departure,
                    preferences: _preferences,
                    onPick:
                        _canAsk ? (_localHelp ? _ask : _draftStarter) : null),
              for (final message in _messages)
                _Bubble(
                  brandName: brandName,
                  message: message,
                  onOpen: (route) => context.go(route),
                  onExternal: _openExternal,
                ),
              if (_thinking) const _Thinking(),
              if (_error != null && !_thinking) ...[
                _Notice(text: context.tr(_error!)),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!_localHelp && !_exhausted && !_sensitiveInputRejected)
                      FilledButton.tonalIcon(
                        onPressed:
                            _coolingDown || _loadingUsage ? null : _sendPending,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(context.tr('Try again')),
                      ),
                    TextButton(
                      onPressed: _editPending,
                      child: Text(context.tr('Edit question')),
                    ),
                  ],
                ),
                if (!_sensitiveInputRejected)
                  Text(
                    context.tr(
                        'Each attempt uses one request from your daily allowance.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
        Padding(
          key: const ValueKey('assistant-compact-toolbar'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _usage?.enabled == true
              ? AssistantQuickEntry(
                  key: ValueKey('assistant-quick-entry-$_quickEntryEpoch'),
                  value: _tripDetails,
                  enabled: _canAsk,
                  onChanged: _setTripDetails,
                  trailing: _footerDetails(context))
              : Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: _footerDetails(context))),
        ),
        if (_exhausted)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                  context
                      .tr('Daily allowance used. Come back after the reset.'),
                  style: TextStyle(
                      color: ExamplePalette.of(context).accent,
                      fontSize: 12 * context.brandDesign.typographyScale))),
        if (_voice.hint != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Semantics(
                  liveRegion: true,
                  child: Text(context.tr(_voice.hint!),
                      style: TextStyle(
                          color: ExamplePalette.of(context).textSecondary,
                          fontSize: 11 * context.brandDesign.typographyScale,
                          height: 1.3)))),
        _Composer(
          voice: _voice,
          onVoiceStart: () {
            FocusManager.instance.primaryFocus?.unfocus();
            unawaited(_voice.start(
                draft: _controller.text, maxCharacters: _messageLimit));
          },
          controller: _controller,
          enabled: _canAsk,
          localHelp: _localHelp,
          maxLength: _messageLimit,
          onSend: () => _ask(_controller.text),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('Back'),
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(context.tr('Ask AI'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              tooltip: context.tr('Help'),
              onPressed: _showHelp,
              icon: const Icon(Icons.help_outline_rounded),
            ),
          IconButton(
            tooltip: context.tr('Conversation history'),
            onPressed: _showHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          Tooltip(
            message: context.tr('New conversation'),
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: _newConversation,
              child: Text(context.tr('New chat')),
            ),
          ),
        ],
      ),
      body: desktop
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: body,
              ),
            )
          : body,
    );
  }
}

class _Allowance extends StatelessWidget {
  const _Allowance({required this.usage, required this.exhausted});
  final AssistantUsage usage;
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final localReset = usage.resetsAt.toLocal();
    final formats = MaterialLocalizations.of(context);
    final reset = '${formats.formatShortDate(localReset)}, '
        '${formats.formatTimeOfDay(TimeOfDay.fromDateTime(localReset))}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                  context.tr('{p0} of {p1} requests left today',
                      {'p0': usage.remaining, 'p1': usage.dailyLimit}),
                  style: TextStyle(
                    color: exhausted ? palette.accent : palette.textSecondary,
                    fontSize: 11.5 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(context.tr('Resets {p0}', {'p0': reset}),
                    style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11 * context.brandDesign.typographyScale)),
              ],
            ),
            if (exhausted)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context
                      .tr('Daily allowance used. Come back after the reset.'),
                  style: TextStyle(
                      color: palette.accent,
                      fontSize: 12 * context.brandDesign.typographyScale),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _suggestionIcons = [
  Icons.flight_takeoff_rounded,
  Icons.hotel_rounded,
  Icons.wb_sunny_outlined,
  Icons.restaurant_rounded,
];

class _Intro extends StatelessWidget {
  const _Intro(
      {required this.brandName,
      required this.localHelp,
      required this.onHelp,
      required this.onSpending,
      required this.onPick,
      required this.departure,
      required this.preferences});
  final String brandName;
  final bool localHelp;
  final AssistantDeparture? departure;
  final AssistantPreferences preferences;
  final ValueChanged<String>? onPick;
  final VoidCallback onHelp;
  final VoidCallback? onSpending;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final starters = assistantStarters(
      departure: departure,
      preferences: preferences,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Center(child: SparkleIcon(selected: true, size: 64)),
        const SizedBox(height: 14),
        Text(
          context.tr(localHelp ? 'App help' : 'Your travel concierge'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.ink,
            fontSize: 23 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w800,
            letterSpacing: -.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
              localHelp
                  ? 'Travel concierge is not enabled here. Browse answers from {p0} help content.'
                  : 'Pick an idea, make it yours and send. Your dates and trip budget are always up to you.',
              {'p0': brandName}),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13 * context.brandDesign.typographyScale,
              height: 1.5),
        ),
        const SizedBox(height: 22),
        if (!localHelp &&
            (departure != null || preferences.monthlyVolume != null)) ...[
          Text(
            [
              if (departure != null) departure!.displayLabel,
              if (preferences.monthlyVolume != null)
                context.tr(assistantTravelStyleLabel(preferences.style)),
            ].join(' · '),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w600,
              fontSize: 12 * context.brandDesign.typographyScale,
            ),
          ),
          if (preferences.monthlyVolume != null) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                  'Ideas use your onboarding range as a starting point, not a trip budget.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 11.5 * context.brandDesign.typographyScale),
            ),
          ],
          const SizedBox(height: 12),
        ],
        _Suggestion(
          icon: Icons.help_outline_rounded,
          title: context.tr('Help'),
          description:
              context.tr('Cards, transfers, fees and account security'),
          onTap: onHelp,
          bottomSpacing: 0,
        ),
        if (!localHelp) ...[
          for (var index = 0; index < starters.length; index++)
            _Suggestion(
              icon: _suggestionIcons[index],
              title: context.tr(starters[index].title),
              description: context.tr(starters[index].prompt),
              onTap: onPick == null
                  ? null
                  : () => onPick!(context.tr(starters[index].prompt)),
            ),
          _Suggestion(
            icon: Icons.insights_outlined,
            title: context.tr('My account activity'),
            description: context.tr(
                'Understand money in, money out, fees and transfers. Ask about your activity.'),
            onTap: onSpending,
          ),
          const SizedBox(height: 10),
          Text(
            context.tr(
                'Trips, flights, hotels, dining, activities, airport help and app navigation.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: palette.textTertiary,
                fontSize: 11.5 * context.brandDesign.typographyScale,
                height: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            context.tr(
                'Prices and availability are confirmed on the booking site.'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: palette.textTertiary,
                fontSize: 11.5 * context.brandDesign.typographyScale,
                height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion(
      {required this.icon,
      required this.title,
      this.description,
      this.onTap,
      this.bottomSpacing = 8});
  final IconData icon;
  final String title;
  final String? description;
  final VoidCallback? onTap;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: ExampleGlassPanel(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 22, color: palette.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: palette.ink,
                          fontSize: 13 * context.brandDesign.typographyScale,
                          fontWeight: FontWeight.w700)),
                  if (description != null) ...[
                    const SizedBox(height: 3),
                    Text(description!,
                        style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 12 * context.brandDesign.typographyScale,
                            height: 1.35)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(
      {required this.brandName,
      required this.message,
      required this.onOpen,
      required this.onExternal});
  final String brandName;
  final _Message message;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onExternal;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final fromUser = message.fromUser;
    final topic = message.topic;
    final route = topic?.route;
    final reply = message.reply;
    final actions = reply?.actions
            .where((action) => safeAssistantLink(action.url) != null)
            .toList() ??
        [];
    final sources = reply?.sources
            .where((source) => safeAssistantLink(source.url) != null)
            .toList() ??
        [];
    final verificationNote = switch (reply?.verification) {
      'web_sources' =>
        'Found on the web. Confirm final prices and availability with the provider.',
      'planning' =>
        'Planning suggestions only. Current prices and availability have not been verified.',
      _ => sources.isNotEmpty || actions.isNotEmpty
          ? 'Prices and availability are confirmed on the booking site.'
          : null,
    };
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: fromUser ? .9 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: fromUser ? palette.fill : palette.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(fromUser ? 18 : 6),
              bottomRight: Radius.circular(fromUser ? 6 : 18),
            ),
            border: fromUser ? null : Border.all(color: palette.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!fromUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const SparkleIcon(
                          selected: true, size: 14, animate: false),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              context.tr(
                                  reply == null ? 'App help' : '{p0} concierge',
                                  {'p0': brandName}),
                              style: TextStyle(
                                  color: palette.accent,
                                  fontSize:
                                      11 * context.brandDesign.typographyScale,
                                  fontWeight: FontWeight.w700))),
                    ],
                  ),
                ),
              // Model prose is plain text. Only validated recommendation
              // sources and the source/action collections open destinations.
              if (reply != null)
                AssistantAnswer(
                    text: message.text,
                    answer: reply.answer,
                    onOpenSource: onExternal)
              else
                SelectableText(message.text,
                    style: TextStyle(
                        color: fromUser
                            ? context.brandDesign.color(
                                Theme.of(context).brightness, 'onFill',
                                fallback: Colors.white)
                            : palette.ink,
                        fontSize: 13.5 * context.brandDesign.typographyScale,
                        height: 1.5)),
              if (route != null) ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: () => onOpen(route),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(context.tr(topic?.routeLabel ?? 'Open')),
                ),
              ],
              if (sources.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(context.tr('Sources'),
                    style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11 * context.brandDesign.typographyScale,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final source in sources)
                  _ExternalLink(
                      label: source.title,
                      url: source.url,
                      icon: Icons.open_in_new_rounded,
                      onOpen: onExternal),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final action in actions)
                  _ExternalLink(
                      label: action.label,
                      url: action.url,
                      icon: switch (action.kind) {
                        'flights' => Icons.flight_takeoff_rounded,
                        'hotels' => Icons.hotel_outlined,
                        _ => Icons.map_outlined,
                      },
                      onOpen: onExternal),
              ],
              if (verificationNote != null) ...[
                const SizedBox(height: 8),
                Text(context.tr(verificationNote),
                    style: TextStyle(
                        color: palette.textTertiary,
                        fontSize: 11 * context.brandDesign.typographyScale,
                        height: 1.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalLink extends StatelessWidget {
  const _ExternalLink(
      {required this.label,
      required this.url,
      required this.icon,
      required this.onOpen});
  final String label;
  final String url;
  final IconData icon;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final uri = safeAssistantLink(url)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9)),
        onPressed: () => onOpen(url),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(uri.host,
                      softWrap: true,
                      style: TextStyle(
                          fontSize: 10 * context.brandDesign.typographyScale,
                          color: ExamplePalette.of(context).textSecondary)),
                ])),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.onRetry});
  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Semantics(
            liveRegion: true,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text,
                  style: TextStyle(
                      color: ExamplePalette.of(context).textSecondary,
                      height: 1.5)),
              if (onRetry != null)
                TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(context.tr('Try again'))),
            ])),
      );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(children: [
            const SparkleIcon(selected: true, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(context.tr('Planning your answer…'),
                    semanticsLabel: context.tr('Answer loading'),
                    style: TextStyle(
                        color: ExamplePalette.of(context).textTertiary,
                        fontSize: 12.5 * context.brandDesign.typographyScale))),
          ]),
        ),
      );
}

class _Composer extends StatelessWidget {
  const _Composer(
      {required this.voice,
      required this.onVoiceStart,
      required this.controller,
      required this.enabled,
      required this.localHelp,
      required this.maxLength,
      required this.onSend});
  final AssistantDictationController voice;
  final VoidCallback onVoiceStart;
  final TextEditingController controller;
  final bool enabled;
  final bool localHelp;
  final int maxLength;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: TextField(
              key: const ValueKey('assistant-message'),
              controller: controller,
              enabled: enabled || voice.isActive,
              readOnly: voice.isActive,
              minLines: 1,
              maxLines: 3,
              maxLength: maxLength,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final text = truncateAssistantText(newValue.text, maxLength);
                  if (text == newValue.text) return newValue;
                  return TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length));
                }),
              ],
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      maxLength}) =>
                  controller.text.length >= (maxLength ?? 1500) * .9
                      ? Text('${controller.text.length} / $maxLength',
                          style: Theme.of(context).textTheme.bodySmall)
                      : null,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                suffixIcon: AssistantVoiceButton(
                    controller: voice, enabled: enabled, onStart: onVoiceStart),
                hintText: context.tr(localHelp
                    ? 'Ask about the app…'
                    : 'Where would you like to go?'),
              ),
            )),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: SizedBox.square(
                dimension: 46,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => Tooltip(
                    message: context.tr('Send question'),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          shape: const CircleBorder()),
                      onPressed: enabled &&
                              value.text.trim().isNotEmpty &&
                              value.text.length <= maxLength
                          ? onSend
                          : null,
                      child: const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
}
