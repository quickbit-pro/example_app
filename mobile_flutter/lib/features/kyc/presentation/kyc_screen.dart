import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../application/kyc_providers.dart';
import '../data/kyc_api.dart';
import 'kyc_resubmission_panel.dart';
import '../../platform/application/platform_providers.dart';
import '../../profile/presentation/kyc_status_overview_screen.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../../../shared/widgets/searchable_multi_select_dropdown.dart';

class KycScreen extends ConsumerStatefulWidget {
  const KycScreen({super.key});

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  static const _salaryOptions = [
    '0-10000',
    '10001-30000',
    '30001-50000',
    '50001-75000',
    '75001-100000',
    '100001-150000',
    '150001-250000',
    '250001+',
  ];
  static const _volumeOptions = [
    '0-1000',
    '1001-5000',
    '5001-15000',
    '15001-50000',
    '50001-100000',
    '100001+',
  ];

  /// Form measure on Example: a column of inputs stops being readable past
  /// about 520 px, so the desktop layout centres it instead of stretching.
  static const double _formMeasure = 520;

  final _formKey = GlobalKey<FormState>();
  final _purposeController = TextEditingController();
  final _documentIssueDateController = TextEditingController();
  String? _occupation;
  String? _salary = _salaryOptions[3];
  String? _volume = _volumeOptions[1];
  bool _wasResubmission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(kycDetailedStatusProvider);
    });
  }

  @override
  void dispose() {
    _purposeController.dispose();
    _documentIssueDateController.dispose();
    super.dispose();
  }

  Future<void> _showHostedVerificationDialog({required bool blocked}) async {
    final link = ref.read(hostedKycLinkProvider);
    if (link == null || !mounted) return;
    Future<void> open() async {
      await launchUrl(
        link,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    }

    if (context.isExampleTheme) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _KycHandoffDialog(
          blocked: blocked,
          onOpen: open,
          onCheckStatus: () {
            Navigator.of(dialogContext).pop();
            context.go('/kyc/status');
          },
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(blocked
            ? context.tr('Open verification')
            : context.tr('Verification opened')),
        content: Text(
          blocked
              ? context.tr(
                  'Your browser blocked the verification tab. Use the button below to open it.')
              : context.tr(
                  'Identity verification opened in a new tab. Complete it there, then come back and check your status.'),
        ),
        actions: [
          TextButton(
            onPressed: open,
            child: Text(blocked
                ? context.tr('Open verification')
                : context.tr('Open again')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go('/kyc/status');
            },
            child: Text(context.tr('Check status')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detailedStatus = ref.watch(kycDetailedStatusProvider);
    final resetStatus = detailedStatus.valueOrNull;
    if (resetStatus == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Identity verification'))),
        body: detailedStatus.hasError
            ? ErrorState(
                error: detailedStatus.error!,
                onRetry: () => ref.invalidate(kycDetailedStatusProvider))
            : LoadingState(label: context.tr('Loading KYC status')),
      );
    }
    if (resetStatus.hasInterlaceAction) {
      _wasResubmission = true;
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Identity verification'))),
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.all(16),
                children: [KycResubmissionPanel(status: resetStatus)])),
      );
    }
    // Returning from hosted verification can recreate this screen, so use the
    // persisted identity approval as well as this widget's resubmission state.
    if (_wasResubmission || resetStatus.isHoppaApproved) {
      return const HoppaKycStatusScreen();
    }
    final state = ref.watch(kycControllerProvider);
    final occupations = ref.watch(occupationCodesProvider);
    final isExample = context.isExampleTheme;

    ref.listen(kycControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (outcome) {
          if (outcome == KycLaunchOutcome.openedInNewTab ||
              outcome == KycLaunchOutcome.popupBlocked) {
            if ((previous?.isLoading ?? false)) {
              _showHostedVerificationDialog(
                blocked: outcome == KycLaunchOutcome.popupBlocked,
              );
            }
            return;
          }
          if ((previous?.isLoading ?? false) && (previous?.hasValue ?? false)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.tr('Verification submitted'))),
            );
            context.go('/kyc/status');
          }
        },
        error: (error, stackTrace) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
        },
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Identity verification'))),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: isExample
              ? _exampleBody(context, state: state, occupations: occupations)
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      context.tr('Verify your identity'),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr(
                          'Answer a few questions before starting secure identity checks.'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    _occupationField(occupations),
                    const SizedBox(height: 12),
                    _salaryField(),
                    const SizedBox(height: 12),
                    _purposeField(),
                    const SizedBox(height: 12),
                    _volumeField(),
                    const SizedBox(height: 12),
                    _issueDateField(),
                    const SizedBox(height: 24),
                    _submitButton(state, example: false),
                  ],
                ),
        ),
      ),
    );
  }

  /// The Example verification screen in both themes: the journey as a vertical
  /// progress with a hairline connector, the launch state as one pill and one
  /// glyph, and the questionnaire under a section title.
  ///
  /// A utility screen, so there is no arrival moment. The only motion is the
  /// 200 ms status swap and the soft sheen that crosses the step panel on the
  /// shell's cadence.
  Widget _exampleBody(
    BuildContext context, {
    required AsyncValue<KycLaunchOutcome?> state,
    required AsyncValue<List<OccupationCode>> occupations,
  }) {
    final theme = Theme.of(context);
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final status = _KycStatus.from(state);
    final gutter = desktop ? 40.0 : AppSpacing.md;

    Widget content = ListView(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.md,
        gutter,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _formMeasure),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('Verify your identity'),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.tr(
                      'Answer a few questions before starting secure identity checks.'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ExampleInk.secondary(context),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _KycProgressPanel(status: status),
                const SizedBox(height: AppSpacing.md),
                // What the secure window will ask for, stated before it
                // opens. The single loudest complaint about hosted KYC is
                // that a customer is handed to a third party without being
                // told what they are about to be asked to photograph.
                _KycDocumentChecklist(status: status),
                if (state.hasError) ...[
                  const SizedBox(height: AppSpacing.md),
                  _KycFailureNotice(error: state.error!),
                ],
                const SizedBox(height: AppSpacing.lg),
                ExampleSectionTitle(title: context.tr('About you')),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  context.tr(
                      'Five questions. Every one of them is asked because a regulator requires it, and each says what it is used for.'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    // Secondary ink: 7.3:1 or better on the page in both
                    // themes, so this is a sentence at body grade rather
                    // than a caption the customer has to squint at.
                    color: ExampleInk.secondary(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _occupationField(occupations),
                const SizedBox(height: AppSpacing.md),
                _salaryField(),
                const SizedBox(height: AppSpacing.md),
                _purposeField(),
                const SizedBox(height: AppSpacing.md),
                _volumeField(),
                const SizedBox(height: AppSpacing.md),
                _issueDateField(),
                const SizedBox(height: AppSpacing.lg),
                _submitButton(state, example: true),
                const SizedBox(height: AppSpacing.md),
                // Reassurance sits *after* the CTA on purpose: it is the
                // last thing read before a passport is handed over, and it
                // is a footnote rather than a card because reassurance that
                // shouts stops being reassurance.
                const _KycAssurancePanel(),
              ],
            ),
          ),
        ),
      ],
    );

    // The shell already provides the alive layer; a screen opened outside it
    // gets its own so the step panel still has a clock.
    if (!ExampleSheenScope.existsAbove(context)) {
      content = ExampleSheenScope(child: content);
    }
    return content;
  }

  Widget _occupationField(AsyncValue<List<OccupationCode>> occupations) {
    return occupations.when(
      data: (items) {
        if (items.isEmpty) {
          return _OptionsError(
            message:
                context.tr('Occupation options are temporarily unavailable.'),
            onRetry: () => ref.invalidate(occupationCodesProvider),
          );
        }

        final labels = {
          for (final occupation in items)
            occupation.value: context.tr(occupation.title),
        };
        return _field(
          label: context.tr('Occupation'),
          why: 'The regulator that licenses your account requires it.',
          child: SearchableSingleSelectDropdown(
            label: context.tr('Occupation'),
            showLabel: false,
            value: _occupation,
            options: labels.keys.toList(),
            labelBuilder: (value) => labels[value] ?? value,
            onChanged: (value) => setState(() => _occupation = value),
          ),
        );
      },
      error: (error, stackTrace) => _OptionsError(
        message: friendlyErrorMessage(error),
        onRetry: () => ref.invalidate(occupationCodesProvider),
      ),
      loading: () => _LoadingField(label: context.tr('Occupation')),
    );
  }

  Widget _salaryField() => _field(
        label: context.tr('Annual salary'),
        why: 'A range is enough. We never ask for an exact figure.',
        child: DropdownButtonFormField<String>(
          initialValue: _salary,
          // Example lets the selected range flex and pushes the caret to the
          // field's own right edge. Measured: at 2x type on a 375 window the
          // unexpanded row runs 8 px past the control, because a money range
          // is the longest string this form ever puts in a closed dropdown.
          // Other brands keep today's hugging layout, and today's bug.
          isExpanded: context.isExampleTheme,
          decoration: _decoration(
            'Annual salary',
            exampleHint: 'Select a range',
          ),
          items: [
            for (final option in _salaryOptions)
              DropdownMenuItem(
                value: option,
                child: Text(
                  _moneyRangeLabel(option),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          validator: (value) =>
              value == null ? 'Annual salary is required' : null,
          onChanged: (value) => setState(() => _salary = value),
        ),
      );

  Widget _purposeField() => _field(
        label: context.tr('Account purpose'),
        why: 'Tells us what normal activity looks like on your account.',
        child: _RequiredTextField(
          controller: _purposeController,
          label: context.tr('Account purpose'),
          hint: 'Everyday banking',
        ),
      );

  Widget _volumeField() => _field(
        label: context.tr('Expected monthly volume'),
        why: 'Sets your starting limits. An estimate is fine.',
        child: DropdownButtonFormField<String>(
          initialValue: _volume,
          // Same measured overflow as the salary field, same fix.
          isExpanded: context.isExampleTheme,
          decoration: _decoration(
            'Expected monthly volume',
            exampleHint: 'Select a range',
          ),
          items: [
            for (final option in _volumeOptions)
              DropdownMenuItem(
                value: option,
                child: Text(
                  _moneyRangeLabel(option),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          validator: (value) =>
              value == null ? 'Expected monthly volume is required' : null,
          onChanged: (value) => setState(() => _volume = value),
        ),
      );

  Widget _issueDateField() => _field(
        label: context.tr('Document issue date'),
        why: 'Must match the ID you photograph in the next step.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _documentIssueDateController,
              readOnly: true,
              decoration: _decoration(
                'Document issue date',
                hint: 'YYYY-MM-DD',
                suffixIcon: const Icon(Icons.calendar_month_outlined),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.tr('Document issue date is required');
                }

                return null;
              },
              onTap: _pickDocumentIssueDate,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                "If no issue date is shown, subtract 5 or 10 years from the expiry date, depending on your document's validity period.",
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.isExampleTheme
                    ? ExampleInk.secondary(context)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );

  /// Submit the original questionnaire after validating every field.
  void _startKyc() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    ref.read(kycControllerProvider.notifier).startKyc({
      'Occupation': _occupation,
      'AnnualSalary': _salary,
      'AccountPurpose': _purposeController.text.trim(),
      'ExpectedMonthlyVolume': _volume,
      'DocumentIssueDate': _documentIssueDateController.text.trim(),
    });
  }

  Widget _submitButton(
    AsyncValue<KycLaunchOutcome?> state, {
    required bool example,
  }) {
    if (example) {
      // The one decisive action on the screen, so it gets the glass
      // material. Ground is `surface`: this CTA scrolls with the form on a
      // painted page rather than sitting pinned over the atmosphere, and a
      // backdrop blur that samples a flat panel is a blur that dissolves.
      // No arrival sheen — verification is a utility register, and a CTA
      // that sparkles at someone about to photograph a passport is the
      // wrong tone entirely.
      return ExampleGlassButton(
        label: context.tr('Start verification'),
        icon: Icons.lock_outline_rounded,
        loading: state.isLoading,
        loadingSemanticsLabel: 'Starting verification',
        onPressed: state.isLoading ? null : _startKyc,
      );
    }
    return FilledButton(
      onPressed: state.isLoading ? null : _startKyc,
      child: state.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: AppProgressIndicator(strokeWidth: 2),
            )
          : Text(context.tr('Start verification')),
    );
  }

  /// Wraps one question in the Example field composition; every other brand
  /// gets the stock Material field back, unchanged.
  Widget _field({
    required String label,
    required String why,
    required Widget child,
  }) =>
      context.isExampleTheme
          ? _KycField(label: label, why: why, child: child)
          : child;

  /// Decoration for one question. Example drops the floating label — the
  /// question is already stated above the control at full size, and a label
  /// that shrinks to 12 px the instant the field has a value is the wrong
  /// behaviour for a form where every question needs justifying. Every other
  /// brand keeps today's decoration exactly.
  InputDecoration _decoration(
    String label, {
    String? hint,
    String? exampleHint,
    Widget? suffixIcon,
  }) =>
      context.isExampleTheme
          ? InputDecoration(
              hintText: exampleHint ?? hint,
              suffixIcon: suffixIcon,
            )
          : InputDecoration(
              labelText: label,
              hintText: hint,
              suffixIcon: suffixIcon,
            );

  Future<void> _pickDocumentIssueDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(1950),
      lastDate: now,
    );
    if (selected == null) {
      return;
    }

    _documentIssueDateController.text =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
  }
}

String _moneyRangeLabel(String value) {
  final parts = value.split('-');
  if (parts.length == 2) {
    return 'EUR ${parts[0]} to ${parts[1]}';
  }
  if (value.endsWith('+')) {
    return 'EUR ${value.substring(0, value.length - 1)}+';
  }

  return value;
}

/// Where the customer is in the journey, and what the launch attempt is
/// currently saying about it. Pending, active and in review are the registers
/// this screen can reach; the verified register belongs to the status screen
/// after the partner answers. The semantic hue lands on the pill and the
/// glyph only, never on the panel behind them.
enum _KycTone { pending, active, review, attention }

class _KycStatus {
  const _KycStatus({
    required this.tone,
    required this.step,
    required this.label,
    required this.line,
    required this.icon,
  });

  factory _KycStatus.from(AsyncValue<KycLaunchOutcome?> state) {
    if (state.isLoading) {
      return const _KycStatus(
        tone: _KycTone.pending,
        step: 0,
        label: 'Starting',
        line: 'Opening the secure verification window.',
        icon: Icons.autorenew_rounded,
      );
    }
    if (state.hasError) {
      return const _KycStatus(
        tone: _KycTone.attention,
        step: 0,
        label: 'Not started',
        line: 'Verification could not be started. Try again.',
        icon: Icons.error_outline_rounded,
      );
    }
    return switch (state.valueOrNull) {
      KycLaunchOutcome.openedInNewTab => const _KycStatus(
          tone: _KycTone.active,
          step: 1,
          label: 'In progress',
          line: 'Finish in the secure tab, then check your status.',
          icon: Icons.open_in_new_rounded,
        ),
      KycLaunchOutcome.popupBlocked => const _KycStatus(
          tone: _KycTone.attention,
          step: 1,
          label: 'Action needed',
          line: 'Your browser blocked the tab. Open it to continue.',
          icon: Icons.warning_amber_rounded,
        ),
      KycLaunchOutcome.submitted => const _KycStatus(
          tone: _KycTone.review,
          step: 2,
          label: 'In review',
          line: 'Your documents are with our verification partner.',
          icon: Icons.hourglass_bottom_rounded,
        ),
      null => const _KycStatus(
          tone: _KycTone.pending,
          step: 0,
          label: 'Not started',
          line: 'Three steps, about two minutes.',
          icon: Icons.shield_outlined,
        ),
    };
  }

  /// Semantic register of the status. Carried by the pill and the glyph.
  final _KycTone tone;

  /// Index of the step the customer is on, 0 to 2.
  final int step;

  /// Pill label. Kept short so the header holds at 375 px and text scale 1.3.
  final String label;

  /// One line under the eyebrow saying what happens next.
  final String line;

  final IconData icon;

  /// Brand token for [tone]; `ExamplePill` and `ExampleIconTile` deepen it for
  /// paper themselves, so the same token is right in both themes.
  Color get color => switch (tone) {
        _KycTone.pending => ExampleColors.iris,
        _KycTone.active => ExampleColors.iris,
        _KycTone.review => ExampleColors.teal,
        _KycTone.attention => ExampleColors.warning,
      };
}

/// The verification journey. Three fixed steps; the current one is the only
/// thing on the panel wearing iris.
const List<(String, String)> _kycSteps = [
  ('Your details', 'Occupation, income and account purpose'),
  ('Identity documents', 'Photo ID and a selfie, in a secure window'),
  ('Review', 'Our verification partner confirms your documents'),
];

/// Status and progress in one panel: the eyebrow, the live status line, the
/// status pill, then the vertical step bar under a hairline.
///
/// The panel is the screen's single sheen host — a progress bar is one of the
/// allowed ones — and it never sweeps on arrival, so the screen stays a
/// utility screen.
class _KycProgressPanel extends StatelessWidget {
  const _KycProgressPanel({required this.status});

  final _KycStatus status;

  @override
  Widget build(BuildContext context) {
    return ExampleGlassPanel(
      radius: AppRadii.lg,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KycStatusHeader(status: status),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 1,
            child: ColoredBox(
              color: ExampleBorders.hairlineSideOf(context).color,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // The step bar is the host, not the whole panel: the sheen's clip
          // would otherwise cut the panel's daylight ambient shadow, and the
          // band belongs on the progress, not on the status line.
          ExampleSheen(
            borderRadius: BorderRadius.circular(AppRadii.xs),
            intensity: ExampleSheenIntensity.soft,
            sweepOnArrival: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < _kycSteps.length; index++)
                  _KycStepRow(
                    index: index,
                    title: _kycSteps[index].$1,
                    detail: _kycSteps[index].$2,
                    done: index < status.step,
                    current: index == status.step,
                    last: index == _kycSteps.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KycStatusHeader extends StatelessWidget {
  const _KycStatusHeader({required this.status});

  final _KycStatus status;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          ExampleStateSwitch(
            child: ExampleIconTile(
              key: ValueKey(status.icon.codePoint),
              icon: status.icon,
              color: status.color,
              size: 34,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('VERIFICATION'),
                    style: ExampleTextStyles.label(context)),
                const SizedBox(height: 2),
                Semantics(
                  liveRegion: true,
                  child: ExampleStateSwitch(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.tr(status.line),
                      key: ValueKey(status.line),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ExampleStateSwitch(
            child: ExamplePill(
              key: ValueKey(status.label),
              label: context.tr(status.label),
              color: status.color,
              dot: true,
            ),
          ),
        ],
      );
}

/// One step of the vertical progress: a 20 pt marker, a one-pixel connector
/// down to the next marker, and the step's own text.
///
/// The connector is drawn by the row above it and stretches to whatever
/// height the text needs, so the bar stays joined at text scale 1.3.
class _KycStepRow extends StatelessWidget {
  const _KycStepRow({
    required this.index,
    required this.title,
    required this.detail,
    required this.done,
    required this.current,
    required this.last,
  });

  /// Zero-based position in [_kycSteps]. A step that is neither done nor
  /// current shows this number, so the three states are told apart by shape
  /// — tick, ring-and-dot, numeral — and not only by hue.
  final int index;

  final String title;
  final String detail;
  final bool done;
  final bool current;
  final bool last;

  /// Width of the marker column. The marker is 20; the connector runs down
  /// its centre.
  static const double _marker = 20;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final settled = ExampleInk.accent(context, ExampleColors.success);
    final hairline = ExampleBorders.hairlineSideOf(context).color;
    return Semantics(
      label: 'Step ${index + 1} of ${_kycSteps.length}. $title. '
          '${done ? 'Done' : current ? 'You are here' : 'Not started'}. '
          '$detail',
      child: ExcludeSemantics(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _marker,
                child: Column(
                  children: [
                    _KycStepMarker(
                      index: index,
                      done: done,
                      current: current,
                      accent: accent,
                      settled: settled,
                      hairline: hairline,
                    ),
                    if (!last)
                      Expanded(
                        child: Container(
                          width: 1,
                          color: done ? settled : hairline,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: last ? 0 : AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.3,
                          fontWeight:
                              current ? FontWeight.w700 : FontWeight.w600,
                          color: ExampleInk.primary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Done is a settled tick, current is an iris ring, next is a hairline ring.
/// Only one marker on the panel is iris at a time.
class _KycStepMarker extends StatelessWidget {
  const _KycStepMarker({
    required this.index,
    required this.done,
    required this.current,
    required this.accent,
    required this.settled,
    required this.hairline,
  });

  final int index;
  final bool done;
  final bool current;
  final Color accent;
  final Color settled;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: _KycStepRow._marker,
        height: _KycStepRow._marker,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ExampleInk.tint(context, ExampleColors.success, alpha: .16),
        ),
        child: Icon(Icons.check_rounded, size: 12, color: settled),
      );
    }
    if (current) {
      return Container(
        width: _KycStepRow._marker,
        height: _KycStepRow._marker,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ExampleInk.tint(context, ExampleColors.iris, alpha: .12),
          border: Border.all(color: accent, width: 2),
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
          ),
        ),
      );
    }
    // Not started. An empty hairline ring is ambiguous — it reads as a
    // disabled control rather than as step three — so the numeral goes in.
    // Tertiary ink measures 5.15:1 on Twilight and 4.58:1 on paper, body
    // grade rather than the 3:1 an icon would have been held to.
    return Container(
      width: _KycStepRow._marker,
      height: _KycStepRow._marker,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: hairline),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontSize: 10.5,
          height: 1,
          fontWeight: FontWeight.w600,
          // Secondary rather than tertiary ink: at 10.5 px this numeral is
          // body-grade text, and tertiary on the daylight panel lands at
          // about 4.5:1 — exactly on the floor, with no margin for the
          // gradient's darker stop. Secondary measures 7.79:1 / 7.30:1
          // across the daylight panel and 7.41:1 / 7.76:1 across the
          // Twilight one, and the ring plus the size still keep it the
          // quietest marker of the three.
          color: ExampleInk.secondary(context),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _LoadingField extends StatelessWidget {
  const _LoadingField({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      // The question stays readable while its options load, and the
      // placeholder reserves the 56 pt the filled control will occupy, so
      // nothing below it jumps when the list arrives. A spinner would
      // animate a utility screen and still say nothing about what is
      // loading.
      return _KycField(
        label: label,
        why: 'Loading the list.',
        child: ExampleSkeleton(
          height: 56,
          radius: AppRadii.sm,
          semanticsLabel: context.tr('Loading options'),
        ),
      );
    }
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: AppProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(context.tr('Loading options')),
        ],
      ),
    );
  }
}

class _OptionsError extends StatelessWidget {
  const _OptionsError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleGlassPanel(
        radius: AppRadii.sm,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExampleIconTile(
              icon: Icons.error_outline_rounded,
              color: ExampleColors.danger,
              size: 30,
              radius: 9,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Could not load occupations'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor:
                          ExampleInk.accent(context, ExampleColors.iris),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                    ),
                    onPressed: onRetry,
                    child: Text(context.tr('Retry')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Could not load occupations'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.tr('Retry')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredTextField extends StatelessWidget {
  const _RequiredTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      // Example states the question above the control, so the floating label
      // here would be the same words twice.
      decoration: context.isExampleTheme
          ? InputDecoration(hintText: hint)
          : InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return context.tr('{p0} is required', {'p0': label});
        }

        return null;
      },
    );
  }
}

/// One question in the verification form, Example only.
///
/// The label sits above the control at full size instead of floating inside
/// it. In a KYC form that is not a style preference. A Material floating
/// label shrinks to about 12 px the moment the field has a value, so the
/// question a customer is answering becomes the smallest text on the screen
/// exactly while they decide whether to answer it — and this is the one form
/// in the product where people stop and decide. Lifting the label also buys
/// the line that does the real work here, [why], which says what the answer
/// is for, in the place a help icon would otherwise hide it.
///
/// Screen readers hear the question and its reason once, as the field's own
/// name, rather than three times over from three sibling nodes.
class _KycField extends StatelessWidget {
  const _KycField({
    required this.label,
    required this.why,
    required this.child,
  });

  final String label;

  /// What the answer is used for. One sentence, never a policy paragraph.
  final String why;

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: ExampleInk.primary(context),
              ),
            ),
          ),
          const SizedBox(height: 2),
          ExcludeSemantics(
            child: Text(
              why,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                // Secondary, not tertiary. This is a sentence, and the page
                // ground under it is the shell atmosphere, where daylight
                // tertiary measures 4.28:1 on the bright half — under the
                // body floor. Secondary holds 6.70:1 on that same peak and
                // 7.49:1 on flat paper. Size and weight, not colour, keep it
                // quieter than the question above it.
                color: ExampleInk.secondary(context),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(label: '$label. $why', child: child),
        ],
      );
}

/// What the secure window will ask for, and where each document has got to.
///
/// Hosted identity verification hands a customer to a third party with no
/// warning about what they are about to be asked to photograph; this states
/// it first. The list is deliberately two items long — a checklist that
/// cannot be finished in one sitting is a reason to abandon the flow.
class _KycDocumentChecklist extends StatelessWidget {
  const _KycDocumentChecklist({required this.status});

  final _KycStatus status;

  static const List<(IconData, String, String)> _documents = [
    (
      Icons.badge_outlined,
      'Photo ID',
      'Passport, national ID card or driving licence',
    ),
    (
      Icons.face_retouching_natural_outlined,
      'Selfie',
      'A short liveness check in the same window',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final state = _KycDocState.from(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('What you will need')),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < _documents.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.xs),
          _KycDocumentTile(
            icon: _documents[index].$1,
            title: _documents[index].$2,
            detail: _documents[index].$3,
            state: state,
          ),
        ],
      ],
    );
  }
}

/// Where one document has got to.
///
/// The state a hosted flow can actually report, named honestly. There is no
/// per-document rejection here because the launcher does not return one; the
/// [attention] register is where that copy will land the day the partner's
/// status is available, and it is already written as *what to fix* rather
/// than as "invalid".
enum _KycDocState {
  /// Not asked for yet. Drawn as an outline, so an empty slot looks empty.
  waiting,

  /// The secure window is open and waiting for this document.
  active,

  /// Handed to the verification partner.
  received,

  /// Something is in the way and the customer can clear it.
  attention;

  static _KycDocState from(_KycStatus status) {
    if (status.step >= 2) return _KycDocState.received;
    if (status.tone == _KycTone.attention && status.step >= 1) {
      return _KycDocState.attention;
    }
    if (status.step >= 1) return _KycDocState.active;
    return _KycDocState.waiting;
  }
}

/// One document, in one of four designed states.
///
/// Empty and filled are told apart by *material*, not by a tint: waiting is a
/// dashed outline with no fill, everything after it is a solid panel. Radius
/// and padding are pinned to the same numbers in both, so a document tile
/// never moves or resizes as it fills — the checklist settles rather than
/// reflowing under the reader.
class _KycDocumentTile extends StatelessWidget {
  const _KycDocumentTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.state,
  });

  final IconData icon;
  final String title;
  final String detail;
  final _KycDocState state;

  /// Shared silhouette. [ExampleDashedPanel] defaults to exactly these, and
  /// the solid states are pinned to them so nothing shifts on a state change.
  static const double _radius = 16;
  static const EdgeInsets _padding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 12);

  @override
  Widget build(BuildContext context) {
    final line = switch (state) {
      _KycDocState.waiting => detail,
      _KycDocState.active => 'Photograph it in the secure window.',
      _KycDocState.received => 'Sent to our verification partner.',
      _KycDocState.attention =>
        'The secure window is not open. Allow pop-ups for this site, then '
            'start again.',
    };
    final (String? pill, Color pillColor) = switch (state) {
      _KycDocState.waiting => (null, ExampleColors.iris),
      _KycDocState.active => ('Ready', ExampleColors.iris),
      _KycDocState.received => ('Received', ExampleColors.teal),
      _KycDocState.attention => ('Action needed', ExampleColors.warning),
    };

    final body = Semantics(
      label: '$title. ${switch (state) {
        _KycDocState.waiting => 'Not provided yet',
        _KycDocState.active => 'Ready to capture',
        _KycDocState.received => 'Received',
        _KycDocState.attention => 'Action needed',
      }}. $line',
      child: ExcludeSemantics(
        child: Row(
          children: [
            _DocumentGlyph(icon: icon, state: state),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  // The line swaps in place through the 200 ms state fade;
                  // both variants live in the same text slot, so the tile
                  // height is set by the longest of them and the checklist
                  // never reflows as the flow advances.
                  ExampleStateSwitch(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      line,
                      key: ValueKey(line),
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        // Secondary ink, measured against the panel's own
                        // gradient rather than a flat swatch: 7.79:1 at the
                        // daylight top stop and 7.30:1 at the bottom, 7.41:1
                        // and 7.76:1 on Twilight. Body grade everywhere on
                        // the tile, in both themes.
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (pill != null) ...[
              const SizedBox(width: AppSpacing.xs),
              ExampleStateSwitch(
                child: ExamplePill(
                  key: ValueKey(pill),
                  label: pill,
                  color: pillColor,
                  dot: state == _KycDocState.active,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (state == _KycDocState.waiting) {
      return ExampleDashedPanel(
        radius: _radius,
        padding: _padding,
        child: body,
      );
    }
    return ExampleGlassPanel(
      radius: _radius,
      padding: _padding,
      child: body,
    );
  }
}

/// The document's own glyph, in the state's register. Waiting is a bare
/// outline in the resting ink — a slot that has not been filled should not
/// wear a colour — and the three live states take the tinted tile.
class _DocumentGlyph extends StatelessWidget {
  const _DocumentGlyph({required this.icon, required this.state});

  final IconData icon;
  final _KycDocState state;

  @override
  Widget build(BuildContext context) {
    if (state == _KycDocState.waiting) {
      return SizedBox.square(
        dimension: 34,
        child: Icon(
          icon,
          size: 20,
          // Secondary ink on the dashed tile: 7.30:1 at the darkest point
          // of the daylight fill and 7.41:1 at the darkest point of the
          // Twilight one, against a 3:1 floor for a glyph.
          color: ExampleInk.secondary(context),
        ),
      );
    }
    return ExampleStateSwitch(
      child: ExampleIconTile(
        key: ValueKey(state),
        icon: switch (state) {
          _KycDocState.received => Icons.check_rounded,
          _KycDocState.attention => Icons.priority_high_rounded,
          _ => icon,
        },
        color: switch (state) {
          _KycDocState.received => ExampleColors.teal,
          _KycDocState.attention => ExampleColors.warning,
          _ => ExampleColors.iris,
        },
        size: 34,
      ),
    );
  }
}

/// A launch that failed, answered where it failed.
///
/// Keeps the error visible alongside the original snackbar feedback.
class _KycFailureNotice extends StatelessWidget {
  const _KycFailureNotice({required this.error});

  final Object error;

  /// The two things that actually cause this, in the order they are worth
  /// trying. Neither mentions a status code.
  static const List<String> _fixes = [
    'Allow pop-ups for this site, then start again.',
    'On a work network, a VPN or firewall can block the secure window.',
  ];

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: ExampleGlassPanel(
          radius: AppRadii.lg,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExampleIconTile(
                    icon: Icons.error_outline_rounded,
                    color: ExampleColors.danger,
                    size: 34,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Verification did not start'),
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: ExampleInk.primary(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          friendlyErrorMessage(error),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final fix in _fixes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          fix,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

/// The three sentences a customer wants before they photograph a passport.
///
/// Not a card. Every competitor answers this anxiety with either nothing or
/// a wall of legalese behind a "Learn more"; the material answer is a
/// hairline-topped footnote in the resting palette that can be read in four
/// seconds and never asks to be tapped. Reassurance that shouts stops being
/// reassurance.
class _KycAssurancePanel extends StatelessWidget {
  const _KycAssurancePanel();

  static const List<(IconData, String)> _lines = [
    (
      Icons.shield_outlined,
      'Required by law before an account can hold or send money.',
    ),
    (
      Icons.lock_outline_rounded,
      'Sent over an encrypted connection to a regulated verification partner.',
    ),
    (Icons.schedule_rounded, 'Most reviews finish in minutes.'),
  ];

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 1,
            child: ColoredBox(
              color: ExampleBorders.hairlineSideOf(context).color,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < _lines.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    _lines[index].$1,
                    size: 15,
                    // Secondary ink over the page and its atmosphere:
                    // 6.70:1 at the brightest daylight peak, well past the
                    // 3:1 floor for a glyph.
                    color: ExampleInk.secondary(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _lines[index].$2,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
}

/// The hand-off to the hosted verification window, Example only.
///
/// A blocked pop-up is the single failure this flow actually hits, and a
/// stock alert answers it with a title and a paragraph. This answers it with
/// the fix and the button that applies it: the primary action is whichever
/// one moves the customer forward from where they are — open the window when
/// it never opened, check the status when it did.
class _KycHandoffDialog extends StatelessWidget {
  const _KycHandoffDialog({
    required this.blocked,
    required this.onOpen,
    required this.onCheckStatus,
  });

  final bool blocked;
  final Future<void> Function() onOpen;
  final VoidCallback onCheckStatus;

  /// The launcher as a plain callback, so the two CTAs can share one
  /// conditional without the ternary widening to `Function`.
  void _open() => unawaited(onOpen());

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // 24 rather than the Material 40, so the panel is 327 wide at 375
        // and the two stacked CTAs never crowd their labels.
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: ExampleShadows.sheetOf(context),
            ),
            child: ExampleGlassPanel(
              radius: AppRadii.lg,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ExampleIconTile(
                        icon: blocked
                            ? Icons.tab_unselected_rounded
                            : Icons.open_in_new_rounded,
                        color:
                            blocked ? ExampleColors.warning : ExampleColors.teal,
                        size: 38,
                        radius: 12,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      blocked
                          ? context.tr('Your browser blocked the window')
                          : context.tr('Verification is open in a new tab'),
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      blocked
                          ? context.tr(
                              'Nothing has gone wrong with your application. Allow pop-ups for this site, or open the secure window from here.')
                          : context.tr(
                              'Finish the checks there, then come back and check your status. You can close this and return at any time.'),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Primary is whichever action moves this customer on
                    // from where they actually are, not a fixed "OK".
                    ExampleGlassButton(
                      label: blocked
                          ? context.tr('Open verification')
                          : context.tr('Check status'),
                      icon: blocked
                          ? Icons.open_in_new_rounded
                          : Icons.task_alt_rounded,
                      onPressed: blocked ? _open : onCheckStatus,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ExampleGlassButton(
                      label: blocked
                          ? context.tr('Check status')
                          : context.tr('Open again'),
                      tone: ExampleGlassButtonTone.neutral,
                      onPressed: blocked ? onCheckStatus : _open,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
