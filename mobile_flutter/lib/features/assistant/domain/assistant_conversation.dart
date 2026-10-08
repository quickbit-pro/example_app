import 'dart:math';

import '../data/assistant_api.dart';
import 'assistant_departure.dart';

/// A completed conversation saved on this device, separate from live quota.
class SavedAssistantConversation {
  SavedAssistantConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required List<SavedAssistantTurn> turns,
    this.departure,
  }) : turns = List.unmodifiable(turns);

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<SavedAssistantTurn> turns;
  final AssistantDeparture? departure;
}

/// Only complete user / successful API reply pairs belong in saved history.
/// Drafts, pending questions and failed requests never enter this model.
class SavedAssistantTurn {
  const SavedAssistantTurn({
    required this.role,
    required this.text,
    this.reply,
  });

  final String role;
  final String text;

  /// Historical metadata for rendering only. Fetch usage before allowing Send;
  /// never use a restored reply's usage as the current daily allowance.
  final AssistantReply? reply;
}

String createAssistantConversationId() {
  final random = Random.secure();
  return List.generate(
      16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

String assistantConversationTitle(String question) {
  final plain = question
      .replaceAll(RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.isEmpty) return 'New conversation';
  return truncateAssistantText(plain, 72);
}
