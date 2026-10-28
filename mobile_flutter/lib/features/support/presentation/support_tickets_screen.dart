import 'dart:math';
import '../../signup/data/visitor_id_store.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_states.dart';
import '../data/support_tickets_api.dart';

const _supportNotice = 'Submit a ticket and our support team will reply here. '
    'Replies are not immediate. You can leave this page and check back later.';
String _date(DateTime value) =>
    DateFormat('d MMM y, HH:mm').format(value.toLocal());

class SupportTicketsScreen extends ConsumerStatefulWidget {
  const SupportTicketsScreen({super.key});
  @override
  ConsumerState<SupportTicketsScreen> createState() =>
      _SupportTicketsScreenState();
}

class _SupportTicketsScreenState extends ConsumerState<SupportTicketsScreen> {
  int _offset = 0;
  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(supportTicketListProvider(_offset));
    return Scaffold(
      appBar: _appBar(context, 'Support tickets', onRefresh: () {
        ref.invalidate(supportTicketListProvider);
      }),
      body: _Page(children: [
        const _Notice(_supportNotice),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => context.push('/support/new'),
          icon: const Icon(Icons.add_rounded),
          label: Text(context.tr('New support ticket')),
        ),
        const SizedBox(height: 24),
        tickets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorNotice(error, () {
            ref.invalidate(supportTicketListProvider(_offset));
          }),
          data: (page) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (page.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(children: [
                    const Icon(Icons.confirmation_number_outlined, size: 40),
                    const SizedBox(height: 16),
                    Text(context.tr('No support tickets yet')),
                    const SizedBox(height: 8),
                    Text(
                        context
                            .tr('Need a hand? Create a ticket to get started.'),
                        textAlign: TextAlign.center),
                  ]),
                ),
              for (final ticket in page.items)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(ticket.subject,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(context.tr('{p0}\n{p1} · Updated {p2}', {
                        'p0': ticket.statusLabel,
                        'p1': ticket.reference,
                        'p2': _date(ticket.updatedAt)
                      })),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/support/${ticket.id}'),
                  ),
                ),
              if (page.totalCount > 30 || _offset > 0)
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                          onPressed: _offset == 0
                              ? null
                              : () => setState(() => _offset -= 30),
                          child: Text(context.tr('Previous'))),
                      Text(context.tr('Page {p0}', {'p0': _offset ~/ 30 + 1})),
                      TextButton(
                          onPressed: _offset + 30 >= page.totalCount
                              ? null
                              : () => setState(() => _offset += 30),
                          child: Text(context.tr('Next'))),
                    ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class NewSupportTicketScreen extends ConsumerStatefulWidget {
  const NewSupportTicketScreen({this.complaint = false, super.key});
  final bool complaint;
  @override
  ConsumerState<NewSupportTicketScreen> createState() =>
      _NewSupportTicketScreenState();
}

class _NewSupportTicketScreenState
    extends ConsumerState<NewSupportTicketScreen> {
  final _requestId = VisitorIdStore.newVisitorId(Random.secure());
  final _form = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  Object? _error;
  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(supportTicketsApiProvider);
      final detail = widget.complaint
          ? await api.createComplaint(
              _requestId, _subject.text.trim(), _body.text.trim())
          : await api.create(_subject.text.trim(), _body.text.trim());
      if (!mounted) return;
      ref.invalidate(supportTicketListProvider);
      context.replace('/support/${detail.ticket.id}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr(widget.complaint
              ? 'Complaint recorded. You can track forwarding here.'
              : 'Ticket submitted. Our team will reply here.'))));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: _appBar(context,
            widget.complaint ? 'Make a complaint' : 'New support ticket'),
        body: _Page(children: [
          _Notice(widget.complaint
              ? 'Your complaint and contact details will be passed to Equals Money with your account reference. Equals will assess the complaint and contact you. You can follow its forwarding status here.'
              : _supportNotice),
          const SizedBox(height: 24),
          Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _subject,
                      enabled: !_busy,
                      maxLength: widget.complaint ? 140 : 160,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          labelText: context.tr('Subject'),
                          hintText: context.tr('What do you need help with?'),
                          border: const OutlineInputBorder()),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Enter a subject.'
                              : null,
                    ),
                    const SizedBox(height: 20),
                    _MessageField(
                        controller: _body,
                        enabled: !_busy,
                        label: context.tr(widget.complaint
                            ? 'Tell us what happened and how you were affected'
                            : 'Describe your issue')),
                    const SizedBox(height: 8),
                    Text(
                        context.tr(
                            'Include any useful details. Never include your password, PIN or security codes.'),
                        style: const TextStyle(fontSize: 12)),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(friendlyErrorMessage(_error!),
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy
                            ? context.tr('Submitting…')
                            : context.tr(widget.complaint
                                ? 'Submit complaint'
                                : 'Submit ticket'))),
                  ])),
        ]),
      );
}

class SupportTicketScreen extends ConsumerStatefulWidget {
  const SupportTicketScreen({required this.ticketId, super.key});
  final String ticketId;
  @override
  ConsumerState<SupportTicketScreen> createState() =>
      _SupportTicketScreenState();
}

class _SupportTicketScreenState extends ConsumerState<SupportTicketScreen> {
  final _form = GlobalKey<FormState>();
  final _reply = TextEditingController();
  bool _busy = false;
  Object? _error;
  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SupportTicketScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticketId != widget.ticketId) {
      _reply.clear();
      _error = null;
    }
  }

  Future<void> _submit(SupportTicket ticket) async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(supportTicketsApiProvider)
          .reply(ticket.id, _reply.text.trim(), ticket.revision);
      if (!mounted) return;
      _reply.clear();
      ref.invalidate(supportTicketProvider(ticket.id));
      ref.invalidate(supportTicketListProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context
              .tr('Reply submitted. Our support team will review it.'))));
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(supportTicketProvider(widget.ticketId));
    return Scaffold(
      appBar: _appBar(context, 'Support ticket',
          onRefresh: _busy
              ? null
              : () => ref.invalidate(supportTicketProvider(widget.ticketId))),
      body: detail.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Page(children: [
          _ErrorNotice(error,
              () => ref.invalidate(supportTicketProvider(widget.ticketId)))
        ]),
        data: (detail) => _Page(children: [
          Text(detail.ticket.reference,
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(detail.ticket.subject,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text(detail.ticket.statusLabel))),
          const SizedBox(height: 16),
          _Notice(detail.ticket.status == 'resolved'
              ? 'This ticket is resolved. If you still need help, submit a reply to reopen it.'
              : 'Replies are not immediate. We’ll notify you in the app when support replies. You can also check back here.'),
          if (detail.complaintForwarding != null) ...[
            const SizedBox(height: 16),
            _Notice(switch (detail.complaintForwarding!['status']) {
              'sent' =>
                'Your complaint has been passed to Equals Money, who will contact you.',
              'staging_preview' =>
                'Staging test: your complaint is recorded, but it has not been sent to Equals Money.',
              'failed' ||
              'held' =>
                'Forwarding needs attention. Your complaint is saved and our team needs to follow up. You can also contact Equals Money directly from Help & legal → Complaints.',
              _ =>
                'Your complaint is saved and queued to be forwarded to Equals Money.',
            }),
          ],
          const SizedBox(height: 24),
          for (final message in detail.messages)
            Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            message.isAdmin
                                ? context.tr('Support team')
                                : context.tr('You'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(_date(message.createdAt),
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                        SelectableText(message.body),
                      ]),
                )),
          const SizedBox(height: 12),
          Form(
              key: _form,
              child: _MessageField(
                  controller: _reply,
                  enabled: !_busy,
                  label: context.tr('Your reply'))),
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(friendlyErrorMessage(_error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _busy ? null : () => _submit(detail.ticket),
              child: Text(_busy
                  ? context.tr('Submitting…')
                  : detail.ticket.status == 'resolved'
                      ? context.tr('Submit reply & reopen')
                      : context.tr('Submit reply'))),
        ]),
      ),
    );
  }
}

AppBar _appBar(BuildContext context, String title, {VoidCallback? onRefresh}) =>
    AppBar(
      title: Text(title),
      leading: IconButton(
          tooltip: context.tr('Back'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(title == 'Support tickets' ? '/profile' : '/support');
            }
          }),
      actions: [
        if (onRefresh != null)
          IconButton(
              tooltip: context.tr('Refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded))
      ],
    );

class _Page extends StatelessWidget {
  const _Page({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [...children, const SizedBox(height: 40)],
            )),
      );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16)),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

class _MessageField extends StatelessWidget {
  const _MessageField(
      {required this.controller, required this.enabled, required this.label});
  final TextEditingController controller;
  final bool enabled;
  final String label;
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        minLines: 5,
        maxLines: 12,
        maxLength: 8000,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: true,
            border: const OutlineInputBorder()),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter a message.' : null,
      );
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice(this.error, this.retry);
  final Object error;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(friendlyErrorMessage(error), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: retry, child: Text(context.tr('Try again'))),
      ]);
}
