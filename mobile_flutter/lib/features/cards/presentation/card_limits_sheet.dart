import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/card_limits.dart';

/// Formats a limit in the card's currency without trailing cents noise.
String cardLimitLabel(String currency, double value) {
  final text = Money.formatAmount(currency, value);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

/// Lets the customer set daily / weekly / monthly spending limits on a card.
/// Each slider stops at the tier ceiling, and the backend refuses anything
/// above it as well.
Future<void> showCardLimitsSheet(
  BuildContext context,
  WidgetRef ref, {
  required PaymentCard card,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.isExampleTheme
          ? ExampleSurface.of(context, 1)
          : context.brandDesign.color(
              Theme.of(context).brightness, 'navigation',
              fallback: ExampleColors.navigationSurface),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => CardLimitsSheet(card: card),
    );

class CardLimitsSheet extends ConsumerStatefulWidget {
  const CardLimitsSheet({required this.card, super.key});

  final PaymentCard card;

  @override
  ConsumerState<CardLimitsSheet> createState() => _CardLimitsSheetState();
}

class _CardLimitsSheetState extends ConsumerState<CardLimitsSheet> {
  final _controllers = <String, TextEditingController>{};
  bool _busy = false;
  bool _seeded = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controller(CardLimitPeriod period) {
    return _controllers.putIfAbsent(period.key, () {
      final current = period.current;
      return TextEditingController(
        text: current == null ? '' : _plain(current),
      );
    });
  }

  static String _plain(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
  }

  double? _value(String key) {
    final text = _controllers[key]?.text.trim() ?? '';
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  String? _problem(CardLimitsInfo info) {
    final daily = _value('daily');
    final weekly = _value('weekly');
    final monthly = _value('monthly');
    if (daily == null && weekly == null && monthly == null) {
      return context.tr('Enter at least one limit.');
    }
    for (final period in info.periods) {
      final value = _value(period.key);
      if (value == null) continue;
      if (value < 0) {
        return context.tr(
            '{p0} limit cannot be negative.', {'p0': context.tr(period.label)});
      }
      if (period.hasCap && value > period.cap!) {
        return context.tr('{p0} limit cannot exceed {p1} on your tier.', {
          'p0': context.tr(period.label),
          'p1': cardLimitLabel(info.currency, period.cap!)
        });
      }
    }
    if (daily != null && weekly != null && daily > weekly) {
      return context.tr('Daily limit cannot exceed the weekly limit.');
    }
    if (weekly != null && monthly != null && weekly > monthly) {
      return context.tr('Weekly limit cannot exceed the monthly limit.');
    }
    if (daily != null && monthly != null && daily > monthly) {
      return context.tr('Daily limit cannot exceed the monthly limit.');
    }
    return null;
  }

  Future<void> _save(CardLimitsInfo info) async {
    final problem = _problem(info);
    if (problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(mobilePlatformApiProvider).updateCardLimits(
            widget.card.id,
            daily: _value('daily'),
            weekly: _value('weekly'),
            monthly: _value('monthly'),
            currency: info.currency,
          );
      ref.invalidate(cardLimitsProvider(widget.card.id));
      ref.invalidate(cardControlCapabilitiesProvider(widget.card.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Card limits updated.'))),
      );
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorText(error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final limits = ref.watch(cardLimitsProvider(widget.card.id));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Spending limits'),
                    style: TextStyle(
                      color: context.isExampleTheme
                          ? ExampleInk.primary(context)
                          : context.brandDesign.color(
                              Theme.of(context).brightness, 'ink',
                              fallback: ExampleColors.pearl),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Close'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 4),
            limits.when(
              data: (info) {
                if (!_seeded) {
                  _seeded = true;
                  for (final period in info.periods) {
                    _controller(period);
                  }
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      info.hasCaps
                          ? context.tr(
                              'Set how much this card can spend. Your {p0} tier caps each limit; upgrade your tier for more.',
                              {
                                  'p0': info.tierName ?? 'current'
                                })
                          : context.tr(
                              'Set how much this card can spend per day, week and month.'),
                      style: TextStyle(
                        color: context.isExampleTheme
                            ? ExampleInk.secondary(context)
                            : context.brandDesign.color(
                                Theme.of(context).brightness, 'textSecondary',
                                fallback: ExampleColors.textSecondary),
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final period in info.periods) ...[
                      _LimitRow(
                        period: period,
                        currency: info.currency,
                        controller: _controller(period),
                        enabled: !_busy,
                        onChanged: () => setState(() {}),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (info.updatedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          context.tr('Last updated {p0}',
                              {'p0': _date(info.updatedAt!)}),
                          style: TextStyle(
                            color: context.isExampleTheme
                                ? ExampleInk.tertiary(context)
                                : context.brandDesign.color(
                                    Theme.of(context).brightness,
                                    'textTertiary',
                                    fallback: ExampleColors.textTertiary),
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    if (context.isExampleTheme)
                      ExampleGlassButton(
                        label: context.tr('Save limits'),
                        icon: Icons.check_rounded,
                        loading: _busy,
                        onPressed:
                            _busy || !info.canUpdate ? null : () => _save(info),
                      )
                    else
                      FilledButton.icon(
                        onPressed:
                            _busy || !info.canUpdate ? null : () => _save(info),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: AppProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(context.tr('Save limits')),
                      ),
                  ],
                );
              },
              error: (error, _) => ErrorState(
                error: error,
                onRetry: () =>
                    ref.invalidate(cardLimitsProvider(widget.card.id)),
              ),
              loading: () => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: LoadingState(label: context.tr('Loading limits')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

String _errorText(Object error) => friendlyErrorMessage(error);

/// One period: amount field with the ceiling pill, and a slider that cannot
/// pass the ceiling when one is known.
class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.period,
    required this.currency,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final CardLimitPeriod period;
  final String currency;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final value = double.tryParse(controller.text.replaceAll(',', '.'));
    final cap = period.hasCap ? period.cap! : null;
    final overCap = cap != null && value != null && value > cap;
    final sliderMax = cap ?? _fallbackMax(value);
    return ExampleGlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr(period.label),
                  style: TextStyle(
                    color: context.isExampleTheme
                        ? ExampleInk.primary(context)
                        : context.brandDesign.color(
                            Theme.of(context).brightness, 'ink',
                            fallback: ExampleColors.pearl),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (cap != null)
                ExamplePill(
                  label: context.tr(
                      'Tier max {p0}', {'p0': cardLimitLabel(currency, cap)}),
                  color: context.isExampleTheme
                      ? (overCap
                          ? ExamplePalette.of(context).danger
                          : ExamplePalette.of(context).accent)
                      : (overCap
                          ? context.brandDesign.color(
                              Theme.of(context).brightness, 'danger',
                              fallback: ExampleColors.danger)
                          : context.brandDesign.color(
                              Theme.of(context).brightness, 'accent',
                              fallback: ExampleColors.iris)),
                )
              else
                ExamplePill(
                  label: context.tr('No tier cap'),
                  color: context.isExampleTheme
                      ? ExampleInk.tertiary(context)
                      : context.brandDesign.color(
                          Theme.of(context).brightness, 'textTertiary',
                          fallback: ExampleColors.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: context.tr('No limit set'),
              prefixText: currency == 'USD' ? '\$ ' : '$currency ',
              errorText: overCap
                  ? context.tr('Above your tier ceiling of {p0}',
                      {'p0': cardLimitLabel(currency, cap)})
                  : null,
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.tr('Clear'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: enabled
                          ? () {
                              controller.clear();
                              onChanged();
                            }
                          : null,
                    ),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: context.isExampleTheme
                  ? (overCap
                      ? ExamplePalette.of(context).danger
                      : ExamplePalette.of(context).accent)
                  : (overCap
                      ? context.brandDesign.color(
                          Theme.of(context).brightness, 'danger',
                          fallback: ExampleColors.danger)
                      : context.brandDesign.color(
                          Theme.of(context).brightness, 'fill',
                          fallback: ExampleColors.violet)),
              thumbColor: context.isExampleTheme
                  ? ExamplePalette.of(context).accent
                  : context.brandDesign.color(
                      Theme.of(context).brightness, 'accent',
                      fallback: ExampleColors.lavender),
              inactiveTrackColor: context.isExampleTheme
                  ? ExampleSurface.of(context, 3)
                  : context.brandDesign.color(
                      Theme.of(context).brightness, 'surfaceSubtle',
                      fallback: ExampleColors.darkSurfaceSubtle),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: (value ?? 0).clamp(0, sliderMax).toDouble(),
              max: sliderMax,
              divisions: 100,
              label: value == null ? null : cardLimitLabel(currency, value),
              onChanged: enabled
                  ? (next) {
                      final rounded = _snap(next, sliderMax);
                      controller.text = rounded == 0
                          ? ''
                          : _CardLimitsSheetState._plain(rounded);
                      onChanged();
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  /// Without a tier ceiling the slider spans a sensible range around the
  /// current value so it stays usable.
  static double _fallbackMax(double? value) {
    if (value == null || value <= 0) return 5000;
    return (value * 2).clamp(1000, 1000000).toDouble();
  }

  /// Snaps slider steps to round money amounts.
  static double _snap(double value, double max) {
    final step = max >= 10000
        ? 100.0
        : max >= 1000
            ? 10.0
            : 1.0;
    return (value / step).round() * step;
  }
}
