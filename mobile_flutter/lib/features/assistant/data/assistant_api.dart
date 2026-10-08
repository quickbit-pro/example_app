import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../domain/assistant_departure.dart';
import '../domain/assistant_spending.dart';

final assistantApiProvider = Provider<AssistantApi>(
  (ref) => AssistantApi(ref.watch(dioProvider)),
);

class AssistantUsage {
  const AssistantUsage({
    required this.enabled,
    required this.dailyLimit,
    required this.used,
    required this.remaining,
    required this.resetsAt,
    required this.maxMessageCharacters,
  });

  factory AssistantUsage.fromJson(Map<String, dynamic> json) => AssistantUsage(
        enabled: json['enabled'] as bool,
        dailyLimit: json['dailyLimit'] as int,
        used: json['used'] as int,
        remaining: json['remaining'] as int,
        resetsAt: DateTime.parse(json['resetsAt'] as String),
        maxMessageCharacters: json['maxMessageCharacters'] as int,
      );

  final bool enabled;
  final int dailyLimit;
  final int used;
  final int remaining;
  final DateTime resetsAt;
  final int maxMessageCharacters;
}

class AssistantTurn {
  const AssistantTurn({required this.role, required this.content});

  final String role;
  final String content;
}

class AssistantAction {
  const AssistantAction({
    required this.label,
    required this.url,
    required this.kind,
  });

  final String label;
  final String url;
  final String kind;
}

class AssistantSource {
  const AssistantSource({required this.title, required this.url});

  final String title;
  final String url;
}

/// Recommendation links must match the separately validated source collection;
/// structured prose never grants navigation or tool access.
class AssistantStructuredAnswer {
  const AssistantStructuredAnswer({
    required this.title,
    required this.summary,
    required this.options,
    this.nextStep,
  });

  final String title;
  final String summary;
  final List<AssistantAnswerOption> options;
  final String? nextStep;

  /// An invalid structure falls back to the compatible plain-text reply. Do
  /// not clip facts independently: that can change the meaning of a quote.
  static AssistantStructuredAnswer? tryParse(Object? value,
      {List<AssistantSource> sources = const []}) {
    if (value is! Map ||
        !_hasOnlyKeys(
            value, const {'title', 'summary', 'options', 'nextStep'})) {
      return null;
    }
    final title = _answerText(value['title'], 80);
    final summary = _answerText(value['summary'], 240);
    final rawOptions = value['options'];
    final rawNextStep = value['nextStep'];
    final nextStep = _answerText(rawNextStep, 200);
    if (title == null ||
        summary == null ||
        rawOptions is! List ||
        rawOptions.length > 3 ||
        (rawNextStep != null && nextStep == null)) {
      return null;
    }
    var total = title.length + summary.length + (nextStep?.length ?? 0);
    final options = <AssistantAnswerOption>[];
    for (final raw in rawOptions) {
      if (raw is! Map ||
          !_hasOnlyKeys(
              raw, const {'title', 'highlights', 'details', 'source'})) {
        return null;
      }
      final optionTitle = _answerText(raw['title'], 80);
      final rawHighlights = raw['highlights'];
      final rawDetails = raw['details'];
      final details = _answerText(rawDetails, 600);
      if (optionTitle == null ||
          rawHighlights is! List ||
          rawHighlights.isEmpty ||
          rawHighlights.length > 2 ||
          (rawDetails != null && details == null)) {
        return null;
      }
      final highlights = <String>[];
      for (final rawHighlight in rawHighlights) {
        final highlight = _answerText(rawHighlight, 160);
        if (highlight == null) return null;
        highlights.add(highlight);
        total += highlight.length;
      }
      total += optionTitle.length + (details?.length ?? 0);
      if (total > 2400) return null;
      AssistantSource? source;
      final rawSource = raw['source'];
      if (rawSource is Map && rawSource['url'] is String) {
        final url = rawSource['url'] as String;
        if (safeAssistantLink(url) != null) {
          for (final candidate in sources) {
            if (candidate.url == url) {
              source = candidate;
              break;
            }
          }
        }
      }
      options.add(AssistantAnswerOption(
        title: optionTitle,
        highlights: List.unmodifiable(highlights),
        details: details,
        source: source,
      ));
    }
    if (total > 2400) return null;
    return AssistantStructuredAnswer(
      title: title,
      summary: summary,
      options: List.unmodifiable(options),
      nextStep: nextStep,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'summary': summary,
        'options': [for (final option in options) option.toJson()],
        if (nextStep != null) 'nextStep': nextStep,
      };
}

class AssistantAnswerOption {
  const AssistantAnswerOption({
    required this.title,
    required this.highlights,
    this.details,
    this.source,
  });

  final String title;
  final List<String> highlights;
  final String? details;
  final AssistantSource? source;

  Map<String, dynamic> toJson() => {
        'title': title,
        'highlights': highlights,
        if (details != null) 'details': details,
        if (source != null)
          'source': {'title': source!.title, 'url': source!.url},
      };
}

bool _hasOnlyKeys(Map value, Set<String> allowed) =>
    value.keys.every((key) => key is String && allowed.contains(key));

String? _answerText(Object? value, int maxCodeUnits) {
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty ||
      text.length > maxCodeUnits ||
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]')
          .hasMatch(text) ||
      RegExp(r'(?:[a-z][a-z0-9+.-]*://|www\.|\]\s*\(|<\s*a\b)',
              caseSensitive: false)
          .hasMatch(text)) {
    return null;
  }
  return text;
}

class AssistantReply {
  const AssistantReply({
    required this.reply,
    required this.actions,
    required this.sources,
    required this.webSearchUsed,
    required this.usage,
    required this.refused,
    this.answer,
    this.verification,
  });

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final actions = <AssistantAction>[];
    final sources = <AssistantSource>[];
    for (final item in json['actions'] as List? ?? const []) {
      if (item is! Map) continue;
      final label = item['label'];
      final url = item['url'];
      final kind = item['kind'];
      if (label is! String ||
          label.trim().isEmpty ||
          url is! String ||
          safeAssistantLink(url) == null ||
          !const {'flights', 'hotels', 'maps'}.contains(kind)) {
        continue;
      }
      actions
          .add(AssistantAction(label: label, url: url, kind: kind as String));
    }
    for (final item in json['sources'] as List? ?? const []) {
      if (item is! Map) continue;
      final title = item['title'];
      final url = item['url'];
      if (title is! String ||
          title.trim().isEmpty ||
          url is! String ||
          safeAssistantLink(url) == null) {
        continue;
      }
      sources.add(AssistantSource(title: title, url: url));
    }
    return AssistantReply(
      reply: json['reply'] as String,
      actions: List.unmodifiable(actions),
      sources: List.unmodifiable(sources),
      webSearchUsed: json['webSearchUsed'] == true,
      usage: AssistantUsage.fromJson(json['usage'] as Map<String, dynamic>),
      refused: json['refused'] == true,
      answer:
          AssistantStructuredAnswer.tryParse(json['answer'], sources: sources),
      verification:
          const {'web_sources', 'planning'}.contains(json['verification'])
              ? json['verification'] as String
              : null,
    );
  }

  final String reply;
  final List<AssistantAction> actions;
  final List<AssistantSource> sources;
  final bool webSearchUsed;
  final AssistantUsage usage;
  final bool refused;
  final AssistantStructuredAnswer? answer;
  final String? verification;
}

class AssistantApi {
  const AssistantApi(this._dio);

  final Dio _dio;
  static const _path = '/api/v1/mobile/assistant';

  Future<AssistantUsage> usage({CancelToken? cancelToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_path/usage',
      cancelToken: cancelToken,
      options: Options(extra: {
        'sensitiveRequest': true,
        // Opt out of the shared interceptor's automatic transient GET retry.
        'transientReadRetried': true,
      }),
    );
    return AssistantUsage.fromJson(response.data!);
  }

  Future<AssistantSpendingResult> analyseSpending({
    required String period,
    required String message,
    String? locale,
    List<String> previousQuestions = const [],
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '$_path/chat',
      data: {
        'message': message,
        'spendingPeriod': period,
        if (previousQuestions.isNotEmpty)
          'spendingQuestions': previousQuestions,
        if (locale != null) 'locale': locale,
      },
      cancelToken: cancelToken,
      options: Options(
          extra: {'sensitiveRequest': true},
          receiveTimeout: const Duration(seconds: 100)),
    );
    final json = response.data!;
    return AssistantSpendingResult(
        AssistantReply.fromJson(json),
        json['spending'] == null
            ? null
            : AssistantSpendingSummary.fromJson(
                Map<String, dynamic>.from(json['spending'] as Map)));
  }

  Future<AssistantReply> chat({
    required String message,
    required List<AssistantTurn> history,
    String? locale,
    AssistantDeparture? departure,
    CancelToken? cancelToken,
  }) async {
    final conversation = history
        .where((turn) => turn.role == 'user' || turn.role == 'assistant')
        .toList();
    final recent = conversation.skip(
      conversation.length > 6 ? conversation.length - 6 : 0,
    );
    final response = await _dio.post<Map<String, dynamic>>(
      '$_path/chat',
      data: {
        'message': message,
        'history': [
          for (final turn in recent)
            {
              'role': turn.role,
              'content': truncateAssistantText(turn.content, 3000),
            },
        ],
        if (locale != null && locale.trim().isNotEmpty) 'locale': locale,
        if (departure != null) 'departure': departure.toJson(),
      },
      cancelToken: cancelToken,
      options: Options(
        extra: {'sensitiveRequest': true},
        receiveTimeout: const Duration(seconds: 100),
      ),
    );
    return AssistantReply.fromJson(response.data!);
  }
}

/// Matches the server's UTF-16 character budget without splitting a surrogate.
String truncateAssistantText(String text, int maxCodeUnits) {
  if (maxCodeUnits <= 0) return '';
  if (text.length <= maxCodeUnits) return text;
  var end = maxCodeUnits;
  final previous = text.codeUnitAt(end - 1);
  final next = text.codeUnitAt(end);
  if (previous >= 0xD800 &&
      previous <= 0xDBFF &&
      next >= 0xDC00 &&
      next <= 0xDFFF) {
    end--;
  }
  return text.substring(0, end);
}

/// Allows external HTTPS links with conventional public DNS names.
///
/// This is a navigation guard, not a DNS resolution or redirect guarantee.
/// Recheck at launch time, including links from hand-created reply models.
Uri? safeAssistantLink(String value) {
  if (value.isEmpty || RegExp(r'[\s\x00-\x1f\x7f\\]').hasMatch(value)) {
    return null;
  }
  // Uri normalizes empty credentials away, so inspect the raw authority too.
  if (RegExp(r'^https://[^/?#]*@', caseSensitive: false).hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.authority.contains('@') ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.length > 253) return null;
  final labels = host.split('.');
  if (labels.length < 2 ||
      !RegExp(r'^[a-z]{2,63}$').hasMatch(labels.last) ||
      labels.any((label) =>
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(label))) {
    // Also rejects IPv4, IPv6, integer/hex IPs and single-label local hosts.
    return null;
  }
  const reserved = {
    'localhost',
    'local',
    'localdomain',
    'internal',
    'intranet',
    'lan',
    'home',
    'corp',
    'private',
    'arpa',
    'test',
    'invalid',
    'example',
    'onion',
    'alt',
    'example.com',
    'example.net',
    'example.org',
  };
  if (reserved.any((suffix) => host == suffix || host.endsWith('.$suffix'))) {
    return null;
  }
  return uri;
}

/// Kept separate from chat replies so financial summaries cannot enter saved or provider history.
class AssistantSpendingResult {
  const AssistantSpendingResult(this.reply, this.summary);
  final AssistantReply reply;
  final AssistantSpendingSummary? summary;
}
