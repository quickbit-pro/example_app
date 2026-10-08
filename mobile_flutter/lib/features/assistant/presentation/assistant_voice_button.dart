import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../domain/assistant_dictation_controller.dart';

class AssistantVoiceButton extends StatelessWidget {
  const AssistantVoiceButton({
    required this.controller,
    required this.enabled,
    required this.onStart,
    super.key,
  });

  final AssistantDictationController controller;
  final bool enabled;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => IconButton(
          key: const ValueKey('assistant-voice-button'),
          tooltip: context.tr(controller.isActive
              ? 'Stop voice input'
              : 'Dictate your request'),
          onPressed: controller.isStopping
              ? null
              : controller.isActive
                  ? () => unawaited(controller.stop())
                  : enabled
                      ? onStart
                      : null,
          color: controller.isListening
              ? Theme.of(context).colorScheme.error
              : null,
          icon: controller.isStarting || controller.isStopping
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(controller.isListening
                  ? Icons.stop_circle_outlined
                  : Icons.mic_none_outlined),
        ),
      );
}
