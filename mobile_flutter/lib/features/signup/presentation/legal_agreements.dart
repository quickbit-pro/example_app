import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../rewards/domain/rewards_models.dart';

/// The agreements a customer accepts at registration. Mirrors the web
/// registration page so both channels record the same consent set.
enum LegalAgreementKey {
  eSignAndCommunication,
  privacyAndTerms,
  additionalAcknowledgements,
  equalsTerms,
  informationAccuracy,
  noUnauthorizedSolicitation,
}

const _defaultAdditionalAcknowledgementsUrl =
    'https://docs.hoppa.global/Additional_acknowledgements_when_onboarding.pdf';

class LegalDocumentLink {
  const LegalDocumentLink(this.label, this.url);

  final String label;
  final String? url;
}

class LegalAgreementSpec {
  const LegalAgreementSpec({
    required this.key,
    required this.title,
    required this.lead,
    this.links = const [],
    this.trail = '',
    this.translationBrand,
  });

  final LegalAgreementKey key;
  final String title;

  /// Sentence shown under the title; [links] are appended, joined by "and".
  final String lead;
  final List<LegalDocumentLink> links;
  final String trail;
  final String? translationBrand;

  /// Display translations never change the consent evidence or URLs.
  String localizedCopy(BuildContext context, String copy) {
    final brand = translationBrand;
    if (brand == null || brand.isEmpty) return context.tr(copy);
    return context.tr(copy.replaceAll(brand, '{p0}'), {'p0': brand});
  }

  String get payloadKey => switch (key) {
        LegalAgreementKey.eSignAndCommunication => 'eSignAndCommunication',
        LegalAgreementKey.privacyAndTerms => 'privacyAndTerms',
        LegalAgreementKey.additionalAcknowledgements =>
          'additionalAcknowledgements',
        LegalAgreementKey.equalsTerms => 'equalsTerms',
        LegalAgreementKey.informationAccuracy => 'informationAccuracy',
        LegalAgreementKey.noUnauthorizedSolicitation =>
          'noUnauthorizedSolicitation',
      };
}

/// Builds the agreement list for this installation. The fiat account terms
/// only appear when fiat banking applies and a document is configured, the
/// same rule the web registration uses.
List<LegalAgreementSpec> legalAgreementSpecs(
  MobileTenantConfig? config, {
  required bool business,
  String appName = 'App',
}) {
  final brand = config?.brandName.trim().isNotEmpty == true
      ? config!.brandName.trim()
      : appName;
  const generalTerms = _sharedGeneralTermsUrl;
  const generalTermsUs = _sharedGeneralTermsUsUrl;
  final equalsUrl = config?.equalsGeneralTermsUrl?.trim();
  final requiresEqualsTerms =
      (business || config?.equalsMoneyEnabled != false) &&
          equalsUrl != null &&
          equalsUrl.isNotEmpty;
  return [
    LegalAgreementSpec(
      key: LegalAgreementKey.eSignAndCommunication,
      title: config?.eCommunicationNoticeUrl != null
          ? 'I accept the E-Sign Agreement and GLBA Disclosure'
          : 'I accept the E-Sign Agreement',
      lead: 'Review the ',
      links: [
        const LegalDocumentLink('E-Sign Agreement', _sharedESignUrl),
        if (config?.eCommunicationNoticeUrl != null)
          LegalDocumentLink('GLBA Disclosure', config!.eCommunicationNoticeUrl),
      ],
      trail: ' before proceeding.',
    ),
    LegalAgreementSpec(
      key: LegalAgreementKey.privacyAndTerms,
      title: 'I accept the Privacy Policy and Terms of Service',
      lead: 'Review the ',
      links: [
        const LegalDocumentLink('Privacy Policy', _sharedPrivacyUrl),
        LegalDocumentLink('$brand General Terms (Non-US)', generalTerms),
        LegalDocumentLink('$brand General Terms (US)', generalTermsUs),
      ],
      trail: '.',
    ),
    const LegalAgreementSpec(
      key: LegalAgreementKey.additionalAcknowledgements,
      title: 'I accept the Additional Acknowledgements when Onboarding',
      lead: 'Review the ',
      links: [
        LegalDocumentLink(
          'Additional Acknowledgements when Onboarding',
          _defaultAdditionalAcknowledgementsUrl,
        ),
      ],
      trail: ' before proceeding.',
    ),
    if (requiresEqualsTerms)
      LegalAgreementSpec(
        key: LegalAgreementKey.equalsTerms,
        title: 'I accept the fiat account terms and conditions',
        lead: 'Review the ',
        links: [
          LegalDocumentLink('Equals Money Terms and Conditions', equalsUrl)
        ],
        trail: ' before proceeding with multi-currency account services.',
      ),
    LegalAgreementSpec(
      key: LegalAgreementKey.informationAccuracy,
      translationBrand: brand,
      title: 'I certify the accuracy of my information',
      lead:
          'I certify that the information I have provided is true and accurate and I will abide by all rules related to my $brand spend card.',
    ),
    LegalAgreementSpec(
      key: LegalAgreementKey.noUnauthorizedSolicitation,
      translationBrand: brand,
      title: 'I acknowledge the $brand card usage terms',
      lead:
          'I acknowledge that using the $brand Spend Card does not constitute unauthorized solicitation.',
    ),
  ];
}

// Shared programme documents: styling or tenant configuration must not change
// the PDFs displayed or recorded in customer consent.
const _sharedESignUrl = 'https://docs.hoppa.global/01%20E-sign%20Consent.pdf';
const _sharedPrivacyUrl =
    'https://docs.hoppa.global/Hoppacard%20Privacy%20Policy.pdf';
const _sharedGeneralTermsUrl =
    'https://docs.hoppa.global/4-4%5BB2C%5D_HOPPACARD_NAME_SPEND_CARD_TERMS_%28Non-US%20Consumer%29.pdf';
const _sharedGeneralTermsUsUrl =
    'https://docs.hoppa.global/4-3%5BB2C%5D_HOPPACARD_CREDIT_CARD_ACCOUNT_OPENING_DISCLOSURES_%E2%80%93_NO_SET.pdf';

/// Agreements confirmed when ordering a card: the same four the web cards
/// page requires. Programme PDFs are shared across white-label installations.
List<LegalAgreementSpec> cardOrderAgreementSpecs(
  MobileTenantConfig? config, {
  String appName = 'App',
}) {
  final brand = config?.brandName.trim().isNotEmpty == true
      ? config!.brandName.trim()
      : appName;
  const eSign = _sharedESignUrl;
  final glba = config?.eCommunicationNoticeUrl ?? eSign;
  const privacy = _sharedPrivacyUrl;
  const generalTerms = _sharedGeneralTermsUrl;
  const generalTermsUs = _sharedGeneralTermsUsUrl;
  return [
    LegalAgreementSpec(
      key: LegalAgreementKey.eSignAndCommunication,
      title: 'I accept the E-Sign Agreement and GLBA Disclosure',
      lead: 'Review the ',
      links: [
        const LegalDocumentLink('E-Sign Agreement', eSign),
        LegalDocumentLink('GLBA Disclosure', glba),
      ],
      trail: ' before proceeding.',
    ),
    LegalAgreementSpec(
      key: LegalAgreementKey.privacyAndTerms,
      title: 'I accept the Privacy Policy and Terms of Service',
      lead: 'Review the ',
      links: [
        const LegalDocumentLink('Privacy Policy', privacy),
        LegalDocumentLink('$brand General Terms (Non-US)', generalTerms),
        LegalDocumentLink('$brand General Terms (US)', generalTermsUs),
      ],
      trail: ' before proceeding.',
    ),
    LegalAgreementSpec(
      key: LegalAgreementKey.informationAccuracy,
      translationBrand: brand,
      title: 'I certify the accuracy of my information',
      lead:
          'I certify that the information I have provided is true and accurate and I will abide by all rules and requirements related to my $brand card.',
    ),
    LegalAgreementSpec(
      key: LegalAgreementKey.noUnauthorizedSolicitation,
      translationBrand: brand,
      title: 'I acknowledge the $brand card usage terms',
      lead:
          'I acknowledge that using the $brand card does not constitute unauthorized solicitation.',
    ),
  ];
}

/// Current reference library for both personal/business registration and card
/// ordering. Reuse consent definitions so Settings cannot drift from the flows.
List<LegalDocumentLink> legalDocumentLibrary(
  MobileTenantConfig? config, {
  required String appName,
}) {
  final labelsByUrl = <String, Set<String>>{};
  final links = [
    for (final spec in [
      ...legalAgreementSpecs(config, business: true, appName: appName),
      ...cardOrderAgreementSpecs(config, appName: appName),
    ])
      ...spec.links,
    LegalDocumentLink('Company terms of service', config?.termsUrl),
    LegalDocumentLink('Company privacy policy', config?.privacyUrl),
  ];
  for (final link in links) {
    final url = link.url?.trim();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      continue;
    }
    labelsByUrl.putIfAbsent(uri.toString(), () => <String>{}).add(link.label);
  }
  return List.unmodifiable([
    for (final entry in labelsByUrl.entries)
      LegalDocumentLink(entry.value.join(' / '), entry.key),
  ]);
}

bool allLegalAgreementsAccepted(
  List<LegalAgreementSpec> specs,
  Set<LegalAgreementKey> accepted,
) =>
    specs.every((spec) => accepted.contains(spec.key));

/// Consent record sent with the signup request; the same shape the web
/// registration stores so back-office reporting reads both alike.
Map<String, dynamic> legalAgreementsPayload(
  List<LegalAgreementSpec> specs,
  Set<LegalAgreementKey> accepted,
  MobileTenantConfig? config,
) {
  final present = specs.map((spec) => spec.key).toSet();
  bool value(LegalAgreementKey key) =>
      !present.contains(key) || accepted.contains(key);
  String? documentUrl(LegalAgreementKey key, int index) {
    for (final spec in specs) {
      if (spec.key == key && spec.links.length > index) {
        return spec.links[index].url;
      }
    }
    return null;
  }

  return {
    'acceptedAt': DateTime.now().toUtc().toIso8601String(),
    for (final key in LegalAgreementKey.values)
      _specFor(key).payloadKey: value(key),
    'documents': {
      'privacyUrl': documentUrl(LegalAgreementKey.privacyAndTerms, 0),
      'termsUrl': documentUrl(LegalAgreementKey.privacyAndTerms, 1),
      'eSignUrl': documentUrl(LegalAgreementKey.eSignAndCommunication, 0),
      'eCommunicationNoticeUrl':
          documentUrl(LegalAgreementKey.eSignAndCommunication, 1),
      'generalTermsUrl': documentUrl(LegalAgreementKey.privacyAndTerms, 1),
      'generalTermsUsUrl': documentUrl(LegalAgreementKey.privacyAndTerms, 2),
      'additionalAcknowledgementsUrl':
          documentUrl(LegalAgreementKey.additionalAcknowledgements, 0),
      'equalsGeneralTermsUrl': documentUrl(LegalAgreementKey.equalsTerms, 0),
    },
    'channel': 'mobile',
  };
}

LegalAgreementSpec _specFor(LegalAgreementKey key) => LegalAgreementSpec(
      key: key,
      title: '',
      lead: '',
    );

/// Checkbox list for the agreements. Links open in the system browser.
class LegalAgreementsSection extends StatelessWidget {
  const LegalAgreementsSection({
    required this.specs,
    required this.accepted,
    required this.onChanged,
    super.key,
  });

  final List<LegalAgreementSpec> specs;
  final Set<LegalAgreementKey> accepted;
  final void Function(LegalAgreementKey key, bool accepted) onChanged;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    // EXAMPLE reads its sizes from the theme so the block matches the fields
    // above it; the white-label path keeps the literals it shipped with.
    final titleStyle = isExample
        ? (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
            color: ExampleInk.primary(context),
            fontWeight: FontWeight.w600,
            height: 1.3,
          )
        : TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: theme.colorScheme.onSurface,
          );
    final bodyStyle = isExample
        ? (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
            color: ExampleInk.secondary(context),
            height: 1.45,
          )
        : TextStyle(
            fontSize: 12,
            height: 1.45,
            color: theme.colorScheme.onSurfaceVariant,
          );
    // Lavender carries a link on night at 7.2:1 and 1.7:1 on paper, so
    // daylight hands the role to the accent ink (6.2:1 on white).
    final linkInk = isExample
        ? ExampleTheme.pick(
            context,
            dark: context.brandDesign.color(
                Theme.of(context).brightness, 'accent',
                fallback: ExampleColors.lavender),
            light: ExamplePalette.of(context).accent,
          )
        : theme.colorScheme.primary;
    final linkStyle = bodyStyle.copyWith(
      color: linkInk,
      decoration: TextDecoration.underline,
      decorationColor: linkInk,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Legal agreements'),
          style: isExample
              ? theme.textTheme.labelMedium
                  ?.copyWith(color: ExampleInk.secondary(context))
              : TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .6,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
        ),
        SizedBox(height: isExample ? AppSpacing.xs : 8),
        for (var index = 0; index < specs.length; index++) ...[
          _AgreementRow(
            spec: specs[index],
            checked: accepted.contains(specs[index].key),
            isExample: isExample,
            titleStyle: titleStyle,
            bodyStyle: bodyStyle,
            linkStyle: linkStyle,
            onChanged: (value) => onChanged(specs[index].key, value),
          ),
          if (index != specs.length - 1)
            SizedBox(height: isExample ? AppSpacing.xs : 6),
        ],
      ],
    );
  }
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.spec,
    required this.checked,
    required this.isExample,
    required this.titleStyle,
    required this.bodyStyle,
    required this.linkStyle,
    required this.onChanged,
  });

  final LegalAgreementSpec spec;
  final bool checked;
  final bool isExample;
  final TextStyle titleStyle;
  final TextStyle bodyStyle;
  final TextStyle linkStyle;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final description = Text.rich(
      TextSpan(
        style: bodyStyle,
        children: [
          TextSpan(text: spec.localizedCopy(context, spec.lead)),
          for (var index = 0; index < spec.links.length; index++) ...[
            if (index > 0)
              TextSpan(
                text:
                    index == spec.links.length - 1 ? context.tr(' and ') : ', ',
              ),
            TextSpan(
              text: spec.links[index].label,
              style: spec.links[index].url == null ? bodyStyle : linkStyle,
              recognizer: spec.links[index].url == null
                  ? null
                  : (TapGestureRecognizer()
                    ..onTap = () => _open(context, spec.links[index].url!)),
            ),
          ],
          if (spec.trail.isNotEmpty) TextSpan(text: context.tr(spec.trail)),
        ],
      ),
    );
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // On EXAMPLE the panel itself is the target, so the box is drawn
        // rather than being a second, 24 pt control inside a 60 pt one.
        if (isExample)
          _ExampleAgreementBox(checked: checked)
        else
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: checked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (value) => onChanged(value ?? false),
            ),
          ),
        SizedBox(width: isExample ? AppSpacing.sm : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spec.localizedCopy(context, spec.title), style: titleStyle),
              const SizedBox(height: 3),
              description,
            ],
          ),
        ),
      ],
    );
    if (!isExample) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(!checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: content,
        ),
      );
    }
    // `borderAlpha` is a Twilight-only knob (the daylight branch of
    // ExampleGlassPanel paints an opaque hairline instead), so on paper the
    // checked and unchecked edges of these panels rasterised to the identical
    // 1.18:1 line: no state on the plane, and no 3:1 boundary on a tap target
    // either. `emphasis` would fix the edge but also swaps the fill and adds
    // a bloom, which moves Twilight pixels. Daylight therefore draws the box
    // itself — the same pattern the tier tiles use — while Twilight keeps the
    // glass panel byte for byte.
    final light = ExampleTheme.isLight(context);
    final radius = BorderRadius.circular(AppRadii.sm);
    return Semantics(
      container: true,
      checked: checked,
      label: spec.title,
      child: light
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(!checked),
                borderRadius: radius,
                child: Ink(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: checked
                        ? ExamplePalette.of(context).fill.withValues(alpha: .06)
                        : ExamplePalette.of(context).surface,
                    borderRadius: radius,
                    border: Border.fromBorderSide(
                      checked
                          ? BorderSide(
                              color: ExamplePalette.of(context).fill,
                              width: 1.5,
                            )
                          : ExampleBorders.controlSideOf(context),
                    ),
                  ),
                  child: content,
                ),
              ),
            )
          : ExampleGlassPanel(
              radius: AppRadii.sm,
              padding: const EdgeInsets.all(AppSpacing.sm),
              borderAlpha: checked ? .34 : .16,
              onTap: () => onChanged(!checked),
              child: content,
            ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final ok = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Could not open the document.'))),
      );
    }
  }
}

/// The tick in front of an agreement on EXAMPLE. Painted, not interactive:
/// the panel around it owns the gesture, which keeps one 44 pt target per
/// agreement instead of a small control nested inside a large one.
class _ExampleAgreementBox extends StatelessWidget {
  const _ExampleAgreementBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final fill = ExampleInk.accent(context, ExampleColors.violet);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: ExampleMotion.of(context, ExampleMotion.state),
        curve: ExampleMotion.arrive,
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: checked ? fill : Colors.transparent,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
          border: Border.all(
            // Unchecked, the box is the whole affordance: on paper the .55
            // violet edge reads at 2.3:1, so daylight takes the solid fill.
            color: checked
                ? fill
                : ExampleTheme.pick(
                    context,
                    dark: ExamplePalette.of(context).borderEmphasis,
                    light: ExamplePalette.of(context).fill,
                  ),
          ),
        ),
        child: checked
            ? Icon(
                Icons.check_rounded,
                size: 15,
                color: ExamplePalette.of(context).onFill,
              )
            : null,
      ),
    );
  }
}
