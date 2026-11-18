import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../data/monthly_statements_api.dart';

class MonthlyStatementButton extends StatelessWidget {
  const MonthlyStatementButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
      tooltip: context.tr('Monthly statement with invoices'),
      icon: const Icon(Icons.inventory_2_outlined),
      onPressed: () => showDialog<void>(
          context: context, builder: (_) => const MonthlyStatementsDialog()));
}

class MonthlyStatementsDialog extends ConsumerStatefulWidget {
  const MonthlyStatementsDialog({super.key});
  @override
  ConsumerState<MonthlyStatementsDialog> createState() =>
      _MonthlyStatementsDialogState();
}

class _MonthlyStatementsDialogState
    extends ConsumerState<MonthlyStatementsDialog> {
  late int year, month;
  late final int generation;
  Timer? timer;
  List<MonthlyStatement> jobs = [];
  bool loading = true, creating = false, refreshing = false;
  String? error, requestId;
  bool get current =>
      mounted && ref.read(authSessionGenerationProvider) == generation;
  @override
  void initState() {
    super.initState();
    final previous = DateTime.utc(
        DateTime.now().toUtc().year, DateTime.now().toUtc().month, 0);
    year = previous.year;
    month = previous.month;
    generation = ref.read(authSessionGenerationProvider);
    unawaited(refresh());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (jobs.any((j) => j.pending)) unawaited(refresh());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (refreshing || !current) return;
    refreshing = true;
    try {
      final result = await ref.read(monthlyStatementsApiProvider).list();
      if (current) setState(() => jobs = result);
    } catch (_) {
      if (current) {
        setState(() => error = context.tr('Could not load exports. Try refreshing.'));
      }
    } finally {
      refreshing = false;
      if (current) setState(() => loading = false);
    }
  }

  Future<void> create() async {
    if (creating) return;
    setState(() {
      creating = true;
      error = null;
      requestId ??= MonthlyStatementsApi.requestId();
    });
    try {
      final job = await ref
          .read(monthlyStatementsApiProvider)
          .create(requestId!, year, month);
      if (current) {
        setState(() {
          jobs = [job, ...jobs.where((j) => j.id != job.id)];
          requestId = null;
        });
      }
    } catch (e) {
      if (current) {
        setState(() {
          final data = e is DioException ? e.response?.data : null;
          error = data is Map && data['title'] is String
              ? data['title'] as String
              : context.tr('Could not confirm the export. Retry to check the same request.');
          if (e is DioException &&
              [400, 403, 409, 429].contains(e.response?.statusCode)) {
            requestId = null;
          }
        });
      }
      await refresh();
    } finally {
      if (current) setState(() => creating = false);
    }
  }

  Uri downloadUri(MonthlyStatement job) {
    final path = job.downloadPath;
    if (path == null || !path.startsWith('/api/v1/statement-download?token=')) {
      throw const FormatException('Invalid download link');
    }
    return Uri.parse(ref.read(appConfigProvider).apiBaseUrl).resolve(path);
  }

  Future<void> download(MonthlyStatement job, {bool copy = false}) async {
    try {
      if (copy) {
        await Clipboard.setData(
            ClipboardData(text: downloadUri(job).toString()));
      } else if (!await launchUrl(downloadUri(job),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank')) {
        throw StateError('download');
      }
    } catch (_) {
      if (current) {
        setState(() => error =
            context.tr('Could not open the download. Refresh the list for a new link.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionGenerationProvider, (_, next) {
      if (next != generation && mounted) Navigator.of(context).pop();
    });
    final now = DateTime.now().toUtc();
    final locked = creating || requestId != null;
    return AlertDialog(
        title: Text(context.tr('Monthly statement')),
        content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(context.tr(
                      'Download a PDF and CSV statement with your invoices in one ZIP. All accounts and cards, for the selected calendar month (UTC).')),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(
                        child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: year,
                            decoration:
                                InputDecoration(labelText: context.tr('Year')),
                            items: [
                              for (var y = now.year; y >= 2000; y--)
                                DropdownMenuItem(value: y, child: Text('$y'))
                            ],
                            onChanged: locked
                                ? null
                                : (value) => setState(() {
                                      year = value!;
                                      if (year == now.year &&
                                          month > now.month) {
                                        month = now.month;
                                      }
                                    }))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            key: ValueKey('$year-$month'),
                            initialValue: month,
                            decoration:
                                InputDecoration(labelText: context.tr('Month')),
                            items: [
                              for (var m = 1;
                                  m <= (year == now.year ? now.month : 12);
                                  m++)
                                DropdownMenuItem(
                                    value: m,
                                    child: Text(context.tr(const [
                                      'January',
                                      'February',
                                      'March',
                                      'April',
                                      'May',
                                      'June',
                                      'July',
                                      'August',
                                      'September',
                                      'October',
                                      'November',
                                      'December'
                                    ][m - 1])))
                            ],
                            onChanged: locked
                                ? null
                                : (value) => setState(() => month = value!))),
                  ]),
                  if (year == now.year && month == now.month)
                    Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(context.tr(
                            'The current month includes transactions available when the export is prepared.'))),
                  const SizedBox(height: 14),
                  Text(context.tr(
                      'Invoices are numbered to match statement rows, for example 0012_Merchant_01.pdf. Original uploads stay unchanged.')),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                      onPressed: creating ||
                              (jobs.any((j) => j.pending) && requestId == null)
                          ? null
                          : create,
                      icon: const Icon(Icons.archive_outlined),
                      label: Text(creating
                          ? context.tr('Requesting export…')
                          : requestId != null
                              ? context.tr('Retry export request')
                              : context.tr('Create monthly ZIP'))),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(context.tr(error!),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(
                        child: Text(context.tr('Recent exports'),
                            style: TextStyle(fontWeight: FontWeight.bold))),
                    IconButton(
                        tooltip: context.tr('Refresh exports'),
                        onPressed: refresh,
                        icon: const Icon(Icons.refresh))
                  ]),
                  if (loading) const LinearProgressIndicator(),
                  if (!loading && jobs.isEmpty)
                    Text(context.tr('Your monthly exports will appear here.')),
                  for (final job in jobs)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(job.label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              if (job.pending) ...[
                                const SizedBox(height: 6),
                                const LinearProgressIndicator(),
                                const SizedBox(height: 6),
                                Text(job.status == 'queued'
                                    ? context.tr('Queued for preparation')
                                    : context.tr(
                                        'Preparing statement and invoices…')),
                                Text(context.tr(
                                    'You can close this popup and return later.'))
                              ] else if (job.status == 'ready') ...[
                                Text(context.tr(
                                    '{p0} transactions · {p1} invoices', {
                                  'p0': job.transactionCount,
                                  'p1': job.attachmentCount
                                })),
                                Wrap(spacing: 8, children: [
                                  TextButton.icon(
                                      onPressed: () => download(job),
                                      icon: const Icon(Icons.download),
                                      label: Text(context.tr('Download ZIP'))),
                                  TextButton(
                                      onPressed: () =>
                                          download(job, copy: true),
                                      child: Text(
                                          context.tr('Copy download link')))
                                ]),
                                Text(
                                    context.tr(
                                        'Download links are valid for 15 minutes. Refresh for a new link.'),
                                    style: TextStyle(fontSize: 12))
                              ] else
                                Text(job.error.isEmpty
                                    ? context.tr(
                                        'Export failed. Create a new export to retry.')
                                    : context.tr(job.error)),
                              const Divider(),
                            ])),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('Close')))
        ]);
  }
}
