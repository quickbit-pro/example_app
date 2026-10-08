import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../data/assistant_history_storage.dart';
import '../domain/assistant_conversation.dart';

/// Local history for a single captured account. The caller closes this route
/// when the account changes; every asynchronous action also checks ownership.
class AssistantHistorySheet extends StatefulWidget {
  const AssistantHistorySheet({
    required this.storage,
    required this.owner,
    required this.isCurrent,
    required this.onDeleting,
    super.key,
  });

  final AssistantHistoryStorage storage;
  final String? owner;
  final bool Function() isCurrent;
  final ValueChanged<String> onDeleting;

  @override
  State<AssistantHistorySheet> createState() => _AssistantHistorySheetState();
}

class _AssistantHistorySheetState extends State<AssistantHistorySheet> {
  List<SavedAssistantConversation> _conversations = const [];
  bool _loading = true;
  String? _deleting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final owner = widget.owner;
    final conversations = owner == null
        ? <SavedAssistantConversation>[]
        : await widget.storage.load(owner);
    if (!mounted || !widget.isCurrent()) return;
    setState(() {
      _conversations = conversations;
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    if (_deleting != null || !widget.isCurrent() || widget.owner == null) {
      return;
    }
    // Cancel any active request for this conversation before awaiting storage,
    // so a late response cannot recreate an item the user just deleted.
    widget.onDeleting(id);
    setState(() {
      _deleting = id;
      _error = null;
    });
    final removed = await widget.storage
        .delete(widget.owner!, id, isCurrent: widget.isCurrent);
    if (!mounted || !widget.isCurrent()) return;
    setState(() {
      _deleting = null;
      if (removed) {
        _conversations = _conversations.where((item) => item.id != id).toList();
      } else {
        _error = 'Could not delete this conversation. Please try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Text(context.tr('Conversation history'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                context.tr(
                    'Saved on this device for 7 days. Up to 20 conversations.'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (_error != null)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(context.tr(_error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _conversations.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(context.tr(widget.owner == null
                                ? 'Sign in to view saved conversations.'
                                : 'No saved conversations yet.')),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: _conversations.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final conversation = _conversations[index];
                            final date = MaterialLocalizations.of(context)
                                .formatShortDate(
                                    conversation.updatedAt.toLocal());
                            return ListTile(
                              key: ValueKey(
                                  'assistant-history-${conversation.id}'),
                              contentPadding:
                                  const EdgeInsets.only(left: 20, right: 8),
                              title: Text(conversation.title,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(date),
                              onTap: _deleting != null
                                  ? null
                                  : () {
                                      if (widget.isCurrent()) {
                                        Navigator.of(context).pop(conversation);
                                      }
                                    },
                              trailing: _deleting == conversation.id
                                  ? const SizedBox.square(
                                      dimension: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : IconButton(
                                      tooltip:
                                          context.tr('Delete conversation'),
                                      onPressed: _deleting == null
                                          ? () => _delete(conversation.id)
                                          : null,
                                      icon: const Icon(
                                          Icons.delete_outline_rounded),
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
}
