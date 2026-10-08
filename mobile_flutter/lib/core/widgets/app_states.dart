import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../../brands/example/example_colors.dart';
import '../../brands/example/example_ui.dart';
import '../../shared/widgets/app_progress_indicator.dart';
import '../branding/app_design.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: EdgeInsets.all(isExample ? 24 : 0),
          decoration: isExample
              ? BoxDecoration(
                  // Per brightness: the dark branch is the Twilight value this
                  // card has always painted. Every screen's empty and error
                  // state renders here, so a fixed dark card meant a near-black
                  // panel on paper on all of them.
                  color: ExamplePalette.of(context).surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: context.brandDesign.color(
                        Theme.of(context).brightness, 'borderSubtle',
                        fallback: ExamplePalette.of(context).brightness ==
                                Brightness.light
                            ? ExamplePalette.of(context).borderSubtle
                            : ExampleColors.lavender.withValues(alpha: .12)),
                  ),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: isExample
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.brandDesign
                            .color(Theme.of(context).brightness, 'accent',
                                fallback: ExampleColors.iris)
                            .withValues(alpha: .12),
                      )
                    : null,
                child: Icon(
                  icon,
                  size: isExample ? 28 : 48,
                  color: isExample
                      ? context.brandDesign.color(
                          Theme.of(context).brightness, 'accent',
                          fallback: ExampleColors.iris)
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.tr(title),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr(message!),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({
    required this.error,
    this.onRetry,
    this.title = 'Something went wrong',
    super.key,
  });

  final Object error;
  final VoidCallback? onRetry;
  final String title;

  /// Provider-side gateway errors (502/503/504) are common for a minute or
  /// two right after registration while the account is being provisioned.
  bool get _providerWarmingUp =>
      error is DioException &&
      const {502, 503, 504}
          .contains((error as DioException).response?.statusCode);

  @override
  Widget build(BuildContext context) {
    final retry = onRetry == null
        ? null
        : FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(context.tr('Try again')),
          );
    if (_providerWarmingUp) {
      return EmptyState(
        icon: Icons.hourglass_top_rounded,
        title: context.tr('Your account is being set up'),
        message: context.tr(
            'This usually takes a minute right after registration. Please wait a moment and try again.'),
        action: retry,
      );
    }
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: title,
      message: friendlyErrorMessage(error),
      action: retry,
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({this.label = 'Loading', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isExample)
              const ExampleLoader(size: 42)
            else
              const AppProgressIndicator(),
            const SizedBox(height: 12),
            Text(context.tr(label)),
          ],
        ),
      ),
    );
  }
}

String friendlyErrorMessage(Object error) {
  if (error is FormatException) return error.message;
  if (error is DioException) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'We could not reach the service. Check your connection and try again.';
    }
    final status = error.response?.statusCode;
    if (status == 401) {
      return 'Your session has expired. Sign in again to continue.';
    }
    if (status == 403) return 'You do not have access to this action yet.';
    if (status == 404) return 'We could not find that information.';
    if (status == 409) {
      // Conflicts usually carry a specific instruction (e.g. "sign in or
      // connect your account"); fall back to the generic text otherwise.
      return _safeResponseMessage(error.response?.data) ??
          'This request conflicts with the current account state. Refresh and try again.';
    }
    if (status == 422) {
      return _safeResponseMessage(error.response?.data) ??
          'Check the entered information and try again.';
    }
    if (status == 429) {
      return 'Too many requests. Please wait a moment and try again.';
    }
    if (status != null && status >= 500) {
      return 'The service is temporarily unavailable. Try again shortly.';
    }
    return _safeResponseMessage(error.response?.data) ??
        'We could not complete that request. Please try again.';
  }

  final raw = error.toString().trim();
  if (raw.isEmpty) {
    return 'Please check your connection and try again.';
  }

  final lower = raw.toLowerCase();
  if (lower.contains('socketexception') ||
      lower.contains('connection') ||
      lower.contains('timeout')) {
    return 'We could not reach the service. Check your connection and try again.';
  }
  if (lower.contains('401') || lower.contains('unauthorized')) {
    return 'Your session has expired. Sign in again to continue.';
  }
  if (lower.contains('403') || lower.contains('forbidden')) {
    return 'You do not have access to this action yet.';
  }
  if (lower.contains('404') || lower.contains('not found')) {
    return 'We could not find that information.';
  }
  if (lower.contains('500') || lower.contains('502') || lower.contains('503')) {
    return 'The service is temporarily unavailable. Try again shortly.';
  }

  final cleaned = raw
      .replaceFirst(RegExp(r'^(Exception|DioException)\s*:\s*'), '')
      .replaceAll(RegExp(r'https?://\S+'), 'the service');
  if (!cleaned.contains('{') &&
      !cleaned.contains('[') &&
      cleaned.length <= 140) {
    return cleaned;
  }

  return 'We could not complete that request. Please try again.';
}

String? _safeResponseMessage(Object? data) {
  if (data is! Map) return null;
  for (final key in const ['message', 'Message', 'title', 'Title']) {
    final value = data[key]?.toString().trim();
    if (value != null &&
        value.isNotEmpty &&
        value.length <= 220 &&
        !value.contains('{') &&
        !value.contains('[')) {
      return value;
    }
  }
  return null;
}

String friendlyStatus(String value) {
  final normalized = value.trim().replaceAll('_', ' ').replaceAll('-', ' ');
  if (normalized.isEmpty) {
    return 'Not started';
  }

  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
    if (part.length <= 5 && part == part.toUpperCase()) {
      return part;
    }

    return part[0].toUpperCase() + part.substring(1).toLowerCase();
  }).join(' ');
}

String fallbackText(String value, String fallback) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}
