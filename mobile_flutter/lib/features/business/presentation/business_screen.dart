import '../../../core/compliance/equals_compliance_screen.dart';
import '../../banking/application/banking_providers.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mobile_flutter/brands/example/example.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../core/models/equals_money.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/widgets/additional_information_dialog.dart';
import '../../../shared/widgets/searchable_multi_select_dropdown.dart';
import '../../platform/application/platform_providers.dart';
import '../application/business_providers.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class BusinessScreen extends ConsumerStatefulWidget {
  const BusinessScreen({super.key});

  @override
  ConsumerState<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends ConsumerState<BusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _registeredNameController = TextEditingController();
  final _tradingNameController = TextEditingController();
  final _registrationController = TextEditingController();
  final _incorporationDateController = TextEditingController();
  final _incorporationRegionController = TextEditingController();
  final _businessOverviewController = TextEditingController();
  final _phoneController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _websiteController = TextEditingController();
  final _promotionController = TextEditingController();
  final _registeredStreetController = TextEditingController();
  final _registeredBuildingNumberController = TextEditingController();
  final _registeredBuildingNameController = TextEditingController();
  final _registeredPostcodeController = TextEditingController();
  final _registeredCityController = TextEditingController();
  final _registeredRegionController = TextEditingController();
  final _tradingStreetController = TextEditingController();
  final _tradingBuildingNumberController = TextEditingController();
  final _tradingBuildingNameController = TextEditingController();
  final _tradingPostcodeController = TextEditingController();
  final _tradingCityController = TextEditingController();
  final _tradingRegionController = TextEditingController();
  final _applicantFirstNameController = TextEditingController();
  final _applicantLastNameController = TextEditingController();
  final _applicantEmailController = TextEditingController();
  final _applicantDobController = TextEditingController();
  final _applicantPhoneController = TextEditingController();
  final _applicantTaxIdController = TextEditingController();
  final _applicantJobTitleController = TextEditingController();
  final _applicantOwnershipController = TextEditingController();
  final _applicantStreetController = TextEditingController();
  final _applicantBuildingNumberController = TextEditingController();
  final _applicantBuildingNameController = TextEditingController();
  final _applicantPostcodeController = TextEditingController();
  final _applicantCityController = TextEditingController();
  final _applicantRegionController = TextEditingController();

  String _market = 'UK';
  String _industryMain = '';
  String _industrySub = '';
  String _businessType = 'PRIVATE_COMPANY';
  String _employeeCount = 'ONE_TO_TEN';
  String _countryOfIncorporation = 'GB';
  String _registeredCountry = 'GB';
  String _tradingCountry = 'GB';
  String _applicantCountry = 'GB';
  bool _hasTradingAddress = false;
  bool _applicantIsDirector = true;
  bool _applicantIsUbo = false;
  final List<String> _requestedFeatures = ['PAYMENTS'];
  int _currentSection = 0;
  List<String> _paymentPurposes = ['PAYING_SUPPLIERS'];
  List<String> _accountFundingSource = ['RECEIVING_FUNDS_FROM_OWN_ACCOUNTS'];
  String _estimatedPaymentCount = '5-20';
  String _estimatedPaymentVolume = '10001-50000';
  List<String> _inboundCurrencies = ['GBP'];
  List<String> _outboundCurrencies = ['GBP'];
  List<String> _receivingCountries = ['GB'];
  List<String> _sendingCountries = ['GB'];
  List<String> _applicantNationalities = ['GB'];
  PlatformFile? _proofOfFormation;
  PlatformFile? _proofOfOwnership;
  PlatformFile? _applicantIdentityDocument;
  PlatformFile? _applicantAddressDocument;
  final List<_AdditionalPersonForm> _additionalPeople = [];

  @override
  void dispose() {
    for (final controller in [
      _registeredNameController,
      _tradingNameController,
      _registrationController,
      _incorporationDateController,
      _incorporationRegionController,
      _businessOverviewController,
      _phoneController,
      _taxIdController,
      _websiteController,
      _promotionController,
      _registeredStreetController,
      _registeredBuildingNumberController,
      _registeredBuildingNameController,
      _registeredPostcodeController,
      _registeredCityController,
      _registeredRegionController,
      _tradingStreetController,
      _tradingBuildingNumberController,
      _tradingBuildingNameController,
      _tradingPostcodeController,
      _tradingCityController,
      _tradingRegionController,
      _applicantFirstNameController,
      _applicantLastNameController,
      _applicantEmailController,
      _applicantDobController,
      _applicantPhoneController,
      _applicantTaxIdController,
      _applicantJobTitleController,
      _applicantOwnershipController,
      _applicantStreetController,
      _applicantBuildingNumberController,
      _applicantBuildingNameController,
      _applicantPostcodeController,
      _applicantCityController,
      _applicantRegionController,
    ]) {
      controller.dispose();
    }
    for (final person in _additionalPeople) {
      person.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final state = ref.watch(businessFormControllerProvider);
    final onboardingStatus = ref.watch(businessOnboardingStatusProvider);
    final onboardingOptions = ref.watch(businessOnboardingOptionsProvider);
    final industries = onboardingOptions.valueOrNull?.industries ?? const [];
    final selectedIndustry = industries
        .where((industry) => industry.key == _industryMain)
        .firstOrNull;
    final subIndustries =
        selectedIndustry?.subIndustries ?? const <BusinessOnboardingOption>[];
    String industryLabel(String key) =>
        industries
            .where((industry) => industry.key == key)
            .map((industry) => industry.label)
            .firstOrNull ??
        _label(key);
    String subIndustryLabel(String key) =>
        subIndustries
            .where((industry) => industry.key == key)
            .map((industry) => industry.label)
            .firstOrNull ??
        _label(key);
    final submitted = onboardingStatus.valueOrNull != null &&
        _businessApplicationSubmitted(onboardingStatus.valueOrNull!);

    final hasApplication = onboardingStatus.valueOrNull != null &&
        _businessApplicationExists(onboardingStatus.valueOrNull!);

    ref.listen(businessFormControllerProvider, (previous, next) {
      // The notifier's first build also resolves from loading; only react to
      // a submission that the user actually started.
      if (previous?.isLoading != true || previous?.hasValue != true) return;
      next.whenOrNull(
        data: (_) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Business application saved'))),
        ),
        error: (error, stackTrace) =>
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        ),
      );
    });

    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    return Scaffold(
      appBar: AppBar(
        centerTitle: isExample && !desktop,
        title: Text(context.tr('Business onboarding')),
        actions: desktop && !hasApplication
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Center(
                    child: Text(
                      context
                          .tr('Section {p0} of 5', {'p0': _currentSection + 1}),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: ExampleInk.tertiary(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            desktop
                ? math.max(
                    40, (MediaQuery.sizeOf(context).width - 76 - 760) / 2)
                : (isExample ? 23 : 16),
            desktop ? 28 : (isExample ? 6 : 16),
            desktop
                ? math.max(
                    40, (MediaQuery.sizeOf(context).width - 76 - 760) / 2)
                : (isExample ? 23 : 16),
            isExample ? 110 : 16,
          ),
          children: [
            onboardingStatus.when(
              data: (status) => _BusinessProviderStatus(
                status: status,
                onUpload: (document) =>
                    _uploadRequestedBusinessDocument(document),
                onOpenAction: _openBusinessActionUrl,
              ),
              // Example keeps the top of the form still while the status
              // query settles; a Material bar there is a jump, not news.
              loading: () => isExample
                  ? const SizedBox.shrink()
                  : const LinearProgressIndicator(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
            if (onboardingStatus.valueOrNull != null &&
                _businessApplicationResumable(onboardingStatus.valueOrNull!))
              FilledButton(
                  onPressed: _complianceBusy ? null : _completeCompliance,
                  child: const Text('Resume due diligence and submission')),
            if (submitted) ...[
              const SizedBox(height: 16),
              const _BusinessSubmittedNotice(),
            ],
            if (!hasApplication) ...[
              _BusinessProgress(currentSection: _currentSection),
              const SizedBox(height: 16),
              if (_currentSection == 0)
                _Section(
                  title: context.tr('Business details'),
                  children: [
                    _Field(
                      controller: _registeredNameController,
                      label: context.tr('Registered company name'),
                    ),
                    if (isExample)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Dropdown(
                              label: context.tr('Business type'),
                              value: _businessType,
                              options: equalsBusinessTypeOptions,
                              onChanged: (value) =>
                                  setState(() => _businessType = value),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Dropdown(
                              label: context.tr('Employees'),
                              value: _employeeCount,
                              options: equalsEmployeeCountOptions,
                              onChanged: (value) =>
                                  setState(() => _employeeCount = value),
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _Dropdown(
                        label: context.tr('Market'),
                        value: _market,
                        options: const ['UK', 'EU'],
                        onChanged: (value) => setState(() => _market = value),
                      ),
                      _Dropdown(
                        label: context.tr('Business type'),
                        value: _businessType,
                        options: equalsBusinessTypeOptions,
                        onChanged: (value) =>
                            setState(() => _businessType = value),
                      ),
                      _Dropdown(
                        label: context.tr('Employee count'),
                        value: _employeeCount,
                        options: equalsEmployeeCountOptions,
                        onChanged: (value) =>
                            setState(() => _employeeCount = value),
                      ),
                    ],
                    _Field(
                      controller: _registrationController,
                      label: context.tr('Registration number'),
                    ),
                    SearchableSingleSelectDropdown(
                      label: context.tr('Country of incorporation'),
                      value: _countryOfIncorporation,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) => setState(() {
                        _countryOfIncorporation = value;
                        if (!_requiresIncorporationRegion(value)) {
                          _incorporationRegionController.clear();
                        }
                      }),
                    ),
                    SearchableSingleSelectDropdown(
                      label: context.tr('Industry'),
                      value: _industryMain,
                      options: industries.map((item) => item.key).toList(),
                      labelBuilder: industryLabel,
                      enabled: !onboardingOptions.isLoading,
                      onChanged: (value) => setState(() {
                        _industryMain = value;
                        _industrySub = '';
                      }),
                    ),
                    if (isExample) ...[
                      const SizedBox(height: AppSpacing.xs),
                      // Eyebrow rather than a divider plus a lavender
                      // heading: lavender is a dark-ground ink and fails on
                      // paper, and the label token is resolved per theme.
                      Text(
                        context.tr('ADDITIONAL BUSINESS INFORMATION'),
                        style: ExampleTextStyles.label(context),
                      ),
                      _Dropdown(
                        label: context.tr('Market'),
                        value: _market,
                        options: const ['UK', 'EU'],
                        onChanged: (value) => setState(() => _market = value),
                      ),
                    ],
                    _Field(
                      controller: _tradingNameController,
                      label: context.tr('Trading name'),
                    ),
                    _DateField(
                      controller: _incorporationDateController,
                      label: context.tr('Incorporation date'),
                      lastDate: DateTime.now(),
                    ),
                    if (_requiresIncorporationRegion(
                      _countryOfIncorporation,
                    ))
                      _Field(
                        controller: _incorporationRegionController,
                        label: context.tr('Region of incorporation'),
                      ),
                    _Field(
                      controller: _businessOverviewController,
                      label: context.tr('Business overview'),
                      maxLines: 3,
                      maxLength: 1000,
                      validator: _businessOverviewValidator,
                    ),
                    if (_industryMain.isNotEmpty)
                      SearchableSingleSelectDropdown(
                        label: context.tr('Sub-industry'),
                        value: _industrySub,
                        options: subIndustries.map((item) => item.key).toList(),
                        labelBuilder: subIndustryLabel,
                        onChanged: (value) =>
                            setState(() => _industrySub = value),
                      ),
                    if (onboardingOptions.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.tr(
                                    'Industry options could not be loaded.'),
                              ),
                            ),
                            TextButton(
                              onPressed: () => ref.invalidate(
                                businessOnboardingOptionsProvider,
                              ),
                              child: Text(context.tr('Retry')),
                            ),
                          ],
                        ),
                      ),
                    _Field(
                      controller: _phoneController,
                      label: context.tr('Business phone'),
                      hint: '+386 40 000 003',
                      keyboardType: TextInputType.phone,
                      validator: _phoneValidator,
                    ),
                    _Field(
                      controller: _taxIdController,
                      label: context.tr('Tax ID'),
                      required: false,
                    ),
                    _Field(
                      controller: _websiteController,
                      label: context.tr('Website'),
                      hint: 'https://example.com',
                      keyboardType: TextInputType.url,
                      validator: _websiteValidator,
                    ),
                    _Field(
                      controller: _promotionController,
                      label: context.tr('Business promotion description'),
                      required: false,
                      maxLines: 2,
                    ),
                  ],
                ),
              if (_currentSection == 1)
                _Section(
                  title: context.tr('Registered address'),
                  children: [
                    _Field(
                      controller: _registeredStreetController,
                      label: context.tr('Street name'),
                    ),
                    _Field(
                      controller: _registeredBuildingNumberController,
                      label: context.tr('Building number'),
                      maxLength: 16,
                    ),
                    _Field(
                      controller: _registeredBuildingNameController,
                      label: context.tr('Building name'),
                      required: false,
                    ),
                    _Field(
                      controller: _registeredPostcodeController,
                      label: context.tr('Postcode'),
                    ),
                    _Field(
                      controller: _registeredCityController,
                      label: context.tr('City'),
                    ),
                    _Field(
                      controller: _registeredRegionController,
                      label: context.tr('Region'),
                      required: false,
                    ),
                    SearchableSingleSelectDropdown(
                      label: context.tr('Country'),
                      value: _registeredCountry,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) =>
                          setState(() => _registeredCountry = value),
                    ),
                    _materialSwitchForExample(
                        context,
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title:
                              Text(context.tr('Trading address is different')),
                          subtitle: Text(
                            context.tr(
                                'Enable this only when the company trades from another address.'),
                          ),
                          value: _hasTradingAddress,
                          onChanged: (value) =>
                              setState(() => _hasTradingAddress = value),
                        )),
                    if (_hasTradingAddress) ...[
                      _Field(
                        controller: _tradingStreetController,
                        label: context.tr('Trading street name'),
                      ),
                      _Field(
                        controller: _tradingBuildingNumberController,
                        label: context.tr('Trading building number'),
                        maxLength: 16,
                      ),
                      _Field(
                        controller: _tradingBuildingNameController,
                        label: context.tr('Trading building name'),
                        required: false,
                      ),
                      _Field(
                        controller: _tradingPostcodeController,
                        label: context.tr('Trading postcode'),
                      ),
                      _Field(
                        controller: _tradingCityController,
                        label: context.tr('Trading city'),
                      ),
                      _Field(
                        controller: _tradingRegionController,
                        label: context.tr('Trading region'),
                        required: false,
                      ),
                      SearchableSingleSelectDropdown(
                        label: context.tr('Trading country'),
                        value: _tradingCountry,
                        options: equalsCountryCodes,
                        labelBuilder: _countryLabel,
                        onChanged: (value) =>
                            setState(() => _tradingCountry = value),
                      ),
                    ],
                  ],
                ),
              if (_currentSection == 2)
                _Section(
                  title: context.tr('Associated person'),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(context.tr('Primary applicant')),
                      subtitle: Text(
                        context.tr(
                            'The person completing and managing this application.'),
                      ),
                      trailing: const Icon(Icons.check_circle_outline),
                    ),
                    _Field(
                      controller: _applicantFirstNameController,
                      label: context.tr('First name'),
                    ),
                    _Field(
                      controller: _applicantLastNameController,
                      label: context.tr('Last name'),
                    ),
                    _Field(
                      controller: _applicantEmailController,
                      label: context.tr('Email'),
                      keyboardType: TextInputType.emailAddress,
                      validator: _emailValidator,
                    ),
                    _DateField(
                      controller: _applicantDobController,
                      label: context.tr('Date of birth'),
                      lastDate: _adultCutoff(),
                    ),
                    _Field(
                      controller: _applicantPhoneController,
                      label: context.tr('Phone number'),
                      hint: '+386 40 000 003',
                      keyboardType: TextInputType.phone,
                      validator: _phoneValidator,
                    ),
                    _Field(
                      controller: _applicantTaxIdController,
                      label: context.tr('Tax ID'),
                      required: false,
                    ),
                    _Field(
                      controller: _applicantJobTitleController,
                      label: context.tr('Job title'),
                    ),
                    _materialSwitchForExample(
                        context,
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                              context.tr('This applicant is also a director')),
                          value: _applicantIsDirector,
                          onChanged: (value) =>
                              setState(() => _applicantIsDirector = value),
                        )),
                    _materialSwitchForExample(
                        context,
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            context.tr(
                                'This applicant is also a beneficial owner'),
                          ),
                          value: _applicantIsUbo,
                          onChanged: (value) => setState(() {
                            _applicantIsUbo = value;
                            if (!value) _applicantOwnershipController.clear();
                          }),
                        )),
                    if (_applicantIsUbo)
                      _Field(
                        controller: _applicantOwnershipController,
                        label: context.tr('Ownership percentage'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: _ownershipValidator,
                      ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Nationalities'),
                      values: _applicantNationalities,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) =>
                          setState(() => _applicantNationalities = value),
                    ),
                    _Field(
                      controller: _applicantStreetController,
                      label: context.tr('Residential street'),
                    ),
                    _Field(
                      controller: _applicantBuildingNumberController,
                      label: context.tr('Residential building number'),
                      maxLength: 16,
                    ),
                    _Field(
                      controller: _applicantBuildingNameController,
                      label: context.tr('Residential building name'),
                      required: false,
                    ),
                    _Field(
                      controller: _applicantPostcodeController,
                      label: context.tr('Residential postcode'),
                    ),
                    _Field(
                      controller: _applicantCityController,
                      label: context.tr('Residential city'),
                    ),
                    _Field(
                      controller: _applicantRegionController,
                      label: context.tr('Residential region'),
                      required: false,
                    ),
                    SearchableSingleSelectDropdown(
                      label: context.tr('Residential country'),
                      value: _applicantCountry,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) =>
                          setState(() => _applicantCountry = value),
                    ),
                    const Divider(height: 32),
                    Text(
                      context.tr('Additional associated people'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      context.tr(
                          'Add every separate director and ultimate beneficial owner required for this company.'),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _addAssociatedPerson('DIRECTOR'),
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: Text(context.tr('Add director')),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _addAssociatedPerson(
                            'ULTIMATE_BENEFICIAL_OWNER',
                          ),
                          icon: const Icon(Icons.group_add_outlined),
                          label: Text(context.tr('Add beneficial owner')),
                        ),
                      ],
                    ),
                    for (var index = 0;
                        index < _additionalPeople.length;
                        index++)
                      _buildAdditionalPersonCard(
                        _additionalPeople[index],
                        index,
                      ),
                  ],
                ),
              if (_currentSection == 3)
                _Section(
                  title: context.tr('Fiat account services'),
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(
                          context.tr('Payments and multi-currency accounts')),
                      subtitle: Text(
                        context.tr(
                            'Includes balances, transfers, and currency exchange. Business crypto cards are not offered.'),
                      ),
                      trailing: const Icon(Icons.check_circle_outline),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Payment purposes'),
                      values: _paymentPurposes,
                      options: equalsBusinessPaymentPurposeOptions,
                      labelBuilder: _label,
                      onChanged: (value) =>
                          setState(() => _paymentPurposes = value),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Account funding source'),
                      values: _accountFundingSource,
                      options: equalsBusinessFundingSourceOptions,
                      labelBuilder: _label,
                      onChanged: (value) =>
                          setState(() => _accountFundingSource = value),
                    ),
                    _Dropdown(
                      label: context.tr('Estimated payment volume'),
                      value: _estimatedPaymentVolume,
                      options: equalsAnnualVolumeOptions,
                      onChanged: (value) =>
                          setState(() => _estimatedPaymentVolume = value),
                    ),
                    _Dropdown(
                      label: context.tr('Estimated payment count'),
                      value: _estimatedPaymentCount,
                      options: equalsBusinessPaymentCountOptions,
                      onChanged: (value) =>
                          setState(() => _estimatedPaymentCount = value),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Inbound currencies'),
                      values: _inboundCurrencies,
                      options: equalsSupportedCurrencyCodes,
                      labelBuilder: _label,
                      onChanged: (value) =>
                          setState(() => _inboundCurrencies = value),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Outbound currencies'),
                      values: _outboundCurrencies,
                      options: equalsSupportedCurrencyCodes,
                      labelBuilder: _label,
                      onChanged: (value) =>
                          setState(() => _outboundCurrencies = value),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Receiving countries'),
                      values: _receivingCountries,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) =>
                          setState(() => _receivingCountries = value),
                    ),
                    SearchableMultiSelectDropdown(
                      label: context.tr('Sending countries'),
                      values: _sendingCountries,
                      options: equalsCountryCodes,
                      labelBuilder: _countryLabel,
                      onChanged: (value) =>
                          setState(() => _sendingCountries = value),
                    ),
                  ],
                ),
              if (_currentSection == 4) _documentsSection(isExample),
              if (!isExample) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_currentSection > 0)
                      TextButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () => setState(() => _currentSection--),
                        icon: const Icon(Icons.arrow_back),
                        label: Text(context.tr('Back')),
                      ),
                    const Spacer(),
                    if (_currentSection < 4)
                      FilledButton.icon(
                        onPressed: state.isLoading ? null : _continueSection,
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(context.tr('Continue')),
                      )
                    else
                      FilledButton.icon(
                        onPressed: state.isLoading ? null : _submit,
                        icon: state.isLoading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: AppProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.verified_user_outlined),
                        label: Text(context.tr('Submit application')),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: isExample && !hasApplication
          ? _buildExampleBusinessActions(state.isLoading)
          : null,
    );
  }

  /// The verification documents. Example collects them as one run of rows on
  /// a single surface (and one titled run per extra person); the Material
  /// path keeps the flat list of tiles it had.
  Widget _documentsSection(bool isExample) {
    final applicantTiles = [
      _FileTile(
        title: context.tr('Proof of formation'),
        file: _proofOfFormation,
        onPick: (file) => setState(() => _proofOfFormation = file),
      ),
      _FileTile(
        title: context.tr('Proof of ownership structure'),
        file: _proofOfOwnership,
        onPick: (file) => setState(() => _proofOfOwnership = file),
      ),
      _FileTile(
        title: context.tr('Applicant identity document'),
        file: _applicantIdentityDocument,
        onPick: (file) => setState(() => _applicantIdentityDocument = file),
      ),
      _FileTile(
        title: context.tr('Applicant address document'),
        file: _applicantAddressDocument,
        onPick: (file) => setState(() => _applicantAddressDocument = file),
      ),
    ];
    List<Widget> personTiles(int index) => [
          _FileTile(
            title: context.tr('Identity document'),
            file: _additionalPeople[index].identityDocument,
            onPick: (file) => setState(
              () => _additionalPeople[index].identityDocument = file,
            ),
          ),
          _FileTile(
            title: context.tr('Address document'),
            file: _additionalPeople[index].addressDocument,
            onPick: (file) => setState(
              () => _additionalPeople[index].addressDocument = file,
            ),
          ),
        ];

    if (isExample) {
      return _Section(
        title: context.tr('Verification documents'),
        children: [
          Text(
            context.tr(
                'PDF, JPG or PNG. Required before the application can be submitted.'),
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: ExampleInk.secondary(context)),
          ),
          ExampleListGroup(children: applicantTiles),
          for (var index = 0; index < _additionalPeople.length; index++)
            ExampleListGroup(
              title: '${_additionalPeople[index].roleLabel} '
                  '${_roleNumber(index)}',
              children: personTiles(index),
            ),
        ],
      );
    }
    return _Section(
      title: context.tr('Documents'),
      children: [
        ...applicantTiles,
        for (var index = 0; index < _additionalPeople.length; index++) ...[
          const Divider(height: 28),
          Text(
            '${_additionalPeople[index].roleLabel} ${_roleNumber(index)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ...personTiles(index),
        ],
      ],
    );
  }

  Widget _buildExampleBusinessActions(bool loading) => SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.fromLTRB(23, 12, 23, 10),
              // The one decisive action of the whole KYB flow, so it takes
              // the glass material. Ground is `surface`, not `atmosphere`:
              // this bar lives in the Scaffold's bottomNavigationBar slot, so
              // the body is inset above it and there is genuinely nothing
              // scrolling underneath to blur — a BackdropFilter here would
              // sample the bar's own ground and read as a smudge.
              child: Row(
                children: [
                  if (_currentSection > 0) ...[
                    // A minimum width, not a fixed one: the button's own
                    // height is a floor too, so at text scale 1.3 the bar
                    // grows instead of clipping its labels.
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 114),
                      child: ExampleGlassButton(
                        label: context.tr('Back'),
                        tone: ExampleGlassButtonTone.neutral,
                        expand: false,
                        onPressed: loading
                            ? null
                            : () => setState(() => _currentSection--),
                      ),
                    ),
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    // Loading holds the silhouette, the width and the label's
                    // position and swaps the text for a centred ring. The
                    // previous spinner collapsed "Submit application" to an
                    // 18 px dot, which read as the button having been
                    // replaced rather than as the same button working — and
                    // said nothing at all to a screen reader.
                    child: ExampleGlassButton(
                      label: _currentSection < 4
                          ? context.tr('Continue')
                          : context.tr('Submit application'),
                      loading: loading && _currentSection == 4,
                      onPressed: loading
                          ? null
                          : _currentSection < 4
                              ? _continueSection
                              : _submit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _uploadRequestedBusinessDocument(
    _RequestedBusinessDocument document,
  ) async {
    if (!document.expectsFiles) {
      await _answerRequestedBusinessInformation(document);
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    final paths = result?.files
            .map((file) => file.path)
            .whereType<String>()
            .take(10)
            .toList(growable: false) ??
        const <String>[];
    if (paths.isEmpty) return;

    try {
      await ref.read(mobilePlatformApiProvider).uploadEqualsMoneyDocument(
            type: document.type,
            paths: paths,
            associatedPersonId: document.associatedPersonId,
          );
      ref.invalidate(businessOnboardingStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.tr('{p0} uploaded', {'p0': document.label}))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    }
  }

  Future<void> _openBusinessActionUrl(String fallbackUrl) async {
    var actionUrl = fallbackUrl;
    try {
      final freshStatus =
          await ref.refresh(businessOnboardingStatusProvider.future);
      actionUrl = _findText(freshStatus, const [
            'actionUrl',
            'ActionUrl',
            'verificationUrl',
            'VerificationUrl',
            'nextUrl',
            'NextUrl',
          ]) ??
          fallbackUrl;
    } catch (_) {
      // Use the displayed provider URL if status refresh is unavailable.
    }

    final uri = Uri.tryParse(actionUrl);
    if (uri == null || !uri.isScheme('https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.tr('Secure check link is unavailable.'))),
        );
      }
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Could not open the secure check.'))),
      );
    }
  }

  Future<void> _answerRequestedBusinessInformation(
    _RequestedBusinessDocument document,
  ) async {
    final answer = await showAdditionalInformationDialog(
      context,
      title: _businessRequestLabel(document),
    );
    if (answer == null || !mounted) return;

    try {
      await ref.read(mobilePlatformApiProvider).submitEqualsMoneyInformation(
            type: document.type,
            response: answer,
            associatedPersonId: document.associatedPersonId,
          );
      ref.invalidate(businessOnboardingStatusProvider);
      ref.invalidate(kycDetailedStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.tr('{p0} submitted', {'p0': document.label}))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    }
  }

  void _addAssociatedPerson(String associationType) {
    setState(() {
      _additionalPeople.add(
        _AdditionalPersonForm(
          associationType: associationType,
          country: _applicantCountry,
        ),
      );
    });
  }

  void _removeAssociatedPerson(int index) {
    final person = _additionalPeople.removeAt(index);
    person.dispose();
    setState(() {});
  }

  int _roleNumber(int index) {
    final role = _additionalPeople[index].associationType;
    return _additionalPeople
        .take(index + 1)
        .where((person) => person.associationType == role)
        .length;
  }

  Widget _buildAdditionalPersonCard(
    _AdditionalPersonForm person,
    int index,
  ) {
    final isExample = context.isExampleTheme;
    final isUbo = person.associationType == 'ULTIMATE_BENEFICIAL_OWNER';
    final heading = '${person.roleLabel} ${_roleNumber(index)}';
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                heading,
                style: isExample
                    ? Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: ExampleInk.primary(context),
                          fontWeight: FontWeight.w600,
                        )
                    : Theme.of(context).textTheme.titleSmall,
              ),
            ),
            // IconButton's own 48 pt box already clears the target floor;
            // the tooltip is what a screen reader speaks.
            IconButton(
              tooltip: person.expanded
                  ? context.tr('Collapse')
                  : context.tr('Expand'),
              onPressed: () =>
                  setState(() => person.expanded = !person.expanded),
              icon: Icon(
                person.expanded ? Icons.expand_less : Icons.expand_more,
                color: isExample ? ExampleInk.secondary(context) : null,
              ),
            ),
            IconButton(
              tooltip: context
                  .tr('Remove {p0}', {'p0': person.roleLabel.toLowerCase()}),
              onPressed: () => _removeAssociatedPerson(index),
              icon: Icon(
                Icons.delete_outline,
                color: isExample
                    ? ExampleInk.accent(context, ExampleColors.danger)
                    : null,
              ),
            ),
          ],
        ),
        if (person.expanded) ...[
          _Field(controller: person.firstName, label: context.tr('First name')),
          const SizedBox(height: 12),
          _Field(controller: person.lastName, label: context.tr('Last name')),
          const SizedBox(height: 12),
          _Field(
            controller: person.email,
            label: context.tr('Email'),
            keyboardType: TextInputType.emailAddress,
            validator: _emailValidator,
          ),
          const SizedBox(height: 12),
          _DateField(
            controller: person.dateOfBirth,
            label: context.tr('Date of birth'),
            lastDate: _adultCutoff(),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.phone,
            label: context.tr('Phone number'),
            hint: '+386 40 000 003',
            keyboardType: TextInputType.phone,
            validator: _phoneValidator,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.taxId,
            label: context.tr('Tax ID'),
            required: false,
          ),
          if (isUbo) ...[
            const SizedBox(height: 12),
            _Field(
              controller: person.ownership,
              label: context.tr('Ownership percentage'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _ownershipValidator,
            ),
          ],
          const SizedBox(height: 12),
          SearchableMultiSelectDropdown(
            label: context.tr('Nationalities'),
            values: person.nationalities,
            options: equalsCountryCodes,
            labelBuilder: _countryLabel,
            onChanged: (value) => setState(() => person.nationalities = value),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.street,
            label: context.tr('Residential street'),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.buildingNumber,
            label: context.tr('Residential building number'),
            maxLength: 16,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.buildingName,
            label: context.tr('Residential building name'),
            required: false,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: person.postcode,
            label: context.tr('Residential postcode'),
          ),
          const SizedBox(height: 12),
          _Field(
              controller: person.city, label: context.tr('Residential city')),
          const SizedBox(height: 12),
          _Field(
            controller: person.region,
            label: context.tr('Residential region'),
            required: false,
          ),
          const SizedBox(height: 12),
          SearchableSingleSelectDropdown(
            label: context.tr('Residential country'),
            value: person.country,
            options: equalsCountryCodes,
            labelBuilder: _countryLabel,
            onChanged: (value) => setState(() => person.country = value),
          ),
        ],
      ],
    );
    if (isExample) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: ExampleGlassPanel(
          radius: AppRadii.lg,
          borderAlpha: .30,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: body,
        ),
      );
    }
    return Card.outlined(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: body,
      ),
    );
  }

  Future<void> _continueSection() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final missingMultiSelect = switch (_currentSection) {
      2 => _applicantNationalities.isEmpty ||
          _additionalPeople.any((person) => person.nationalities.isEmpty),
      3 => _paymentPurposes.isEmpty ||
          _accountFundingSource.isEmpty ||
          _inboundCurrencies.isEmpty ||
          _outboundCurrencies.isEmpty ||
          _receivingCountries.isEmpty ||
          _sendingCountries.isEmpty,
      _ => false,
    };
    if (missingMultiSelect) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Complete the required selections'))),
      );
      return;
    }
    if (_currentSection == 2) {
      for (var index = 0; index < _additionalPeople.length; index++) {
        final message = _additionalPeople[index].validationMessage;
        if (message != null) {
          setState(() => _additionalPeople[index].expanded = true);
          _showValidationMessage(
            '${_additionalPeople[index].roleLabel} ${_roleNumber(index)}: $message',
          );
          return;
        }
      }
    }
    final hasDirector = _applicantIsDirector ||
        _additionalPeople.any(
          (person) => person.associationType == 'DIRECTOR',
        );
    if (_currentSection == 2) {
      try {
        final rules = await ref
            .read(mobileBankingApiProvider)
            .businessCompliance('requirements', {
          'businessType': _businessType,
          'country': _countryOfIncorporation,
          'industryMain': _industryMain,
          'industrySub': _industrySub,
          'region': _incorporationRegionController.text.trim(),
          'paymentCountries': {..._receivingCountries, ..._sendingCountries}.toList(),
        });
        if (!mounted) return;
        final eligibilityErrors = rules['eligibilityErrors'] as List? ?? [];
        if (eligibilityErrors.isNotEmpty) { _showValidationMessage(eligibilityErrors.join('\n')); return; }
        if (rules['requiresSoleTraderOwner'] == true &&
            (!_applicantIsUbo ||
                double.tryParse(_applicantOwnershipController.text.trim()) !=
                    100)) {
          _showValidationMessage(
              'The sole trader must be the applicant and 100% beneficial owner.');
          return;
        }
        if (rules['requiresDirector'] == true && !hasDirector) {
          _showValidationMessage('Add a director for this legal form.');
          return;
        }
      } catch (error) {
        if (mounted) _showValidationMessage(complianceError(error));
        return;
      }
    }
    if (_currentSection == 2 && _totalUboOwnership() > 100) {
      _showValidationMessage(
        'Total ownership across all beneficial owners cannot exceed 100%.',
      );
      return;
    }

    setState(() => _currentSection++);
  }

  void _showValidationMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  double _totalUboOwnership() {
    double total = _applicantIsUbo
        ? double.tryParse(_applicantOwnershipController.text.trim()) ?? 0.0
        : 0.0;
    for (final person in _additionalPeople) {
      if (person.associationType == 'ULTIMATE_BENEFICIAL_OWNER') {
        total += double.tryParse(person.ownership.text.trim()) ?? 0.0;
      }
    }
    return total;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_paymentPurposes.isEmpty ||
        _accountFundingSource.isEmpty ||
        _inboundCurrencies.isEmpty ||
        _outboundCurrencies.isEmpty ||
        _receivingCountries.isEmpty ||
        _sendingCountries.isEmpty ||
        _applicantNationalities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('Complete required multi-select fields'))),
      );
      return;
    }

    final proofOfFormation = _businessDocumentUpload(_proofOfFormation);
    final proofOfOwnership = _businessDocumentUpload(_proofOfOwnership);
    final applicantIdentity =
        _businessDocumentUpload(_applicantIdentityDocument);
    final applicantAddress = _businessDocumentUpload(_applicantAddressDocument);
    if (proofOfFormation == null ||
        proofOfOwnership == null ||
        applicantIdentity == null ||
        applicantAddress == null ||
        _additionalPeople.any(
          (person) =>
              _businessDocumentUpload(person.identityDocument) == null ||
              _businessDocumentUpload(person.addressDocument) == null,
        )) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Required documents are missing'))),
      );
      return;
    }

    final ownership =
        double.tryParse(_applicantOwnershipController.text.trim());
    Map<String, Object?> personPayload(
      String associationType, {
      String? jobTitle,
      double? ownershipPercentage,
    }) =>
        _compactMap({
          'firstName': _applicantFirstNameController.text.trim(),
          'lastName': _applicantLastNameController.text.trim(),
          'dateOfBirth': _applicantDobController.text.trim(),
          'nationalities': _applicantNationalities,
          'emailAddress': _applicantEmailController.text.trim(),
          'phoneNumber': _applicantPhoneController.text.trim(),
          'taxId': _applicantTaxIdController.text.trim(),
          'associationType': associationType,
          'jobTitle': jobTitle,
          'ownershipPercentage': ownershipPercentage,
          'addresses': [
            _compactMap({
              'addressType': 'RESIDENTIAL',
              'streetName': _applicantStreetController.text.trim(),
              'buildingNumber': _applicantBuildingNumberController.text.trim(),
              'buildingName': _applicantBuildingNameController.text.trim(),
              'postcode': _applicantPostcodeController.text.trim(),
              'city': _applicantCityController.text.trim(),
              'region': _applicantRegionController.text.trim(),
              'countryCode': _applicantCountry,
            }),
          ],
        });
    final associatedPeople = <Map<String, Object?>>[
      personPayload(
        'APPLICANT',
        jobTitle: _applicantJobTitleController.text.trim(),
      ),
      if (_applicantIsDirector) personPayload('DIRECTOR'),
      if (_applicantIsUbo)
        personPayload(
          'ULTIMATE_BENEFICIAL_OWNER',
          ownershipPercentage: ownership,
        ),
      for (final person in _additionalPeople) person.toApiPayload(),
    ];

    final featureInformation = <String, Object?>{
      'requestedFeatures': _requestedFeatures,
      'paymentsInformation': _compactMap({
        'purposes': _paymentPurposes,
        'accountFundingSource': _accountFundingSource,
        'estimatedPaymentCount': _estimatedPaymentCount,
        'estimatedPaymentVolume': _estimatedPaymentVolume,
        'inboundCurrencies': _inboundCurrencies,
        'outboundCurrencies': _outboundCurrencies,
        'receivingCountries': _receivingCountries,
        'sendingCountries': _sendingCountries,
      }),
    };

    final application = _compactMap({
      'market': _market,
      'type': _businessType,
      'countryOfIncorporation': _countryOfIncorporation,
      'regionOfIncorporation': _incorporationRegionController.text.trim(),
      'registeredName': _registeredNameController.text.trim(),
      'registrationNumber': _registrationController.text.trim(),
      'tradingNames': [_tradingNameController.text.trim()],
      'businessOverview': _businessOverviewController.text.trim(),
      'industry': _compactMap({
        'main': _industryMain,
        'sub': _industrySub,
      }),
      'employeeCount': _employeeCount,
      'incorporationDate': _incorporationDateController.text.trim(),
      'phoneNumber': _phoneController.text.trim(),
      'taxId': _taxIdController.text.trim(),
      'website': _normalizeWebsite(_websiteController.text),
      'businessPromotionDescription': _promotionController.text.trim(),
      'featureInformation': featureInformation,
      'addresses': [
        _compactMap({
          'addressType': 'REGISTERED',
          'streetName': _registeredStreetController.text.trim(),
          'buildingNumber': _registeredBuildingNumberController.text.trim(),
          'buildingName': _registeredBuildingNameController.text.trim(),
          'postcode': _registeredPostcodeController.text.trim(),
          'city': _registeredCityController.text.trim(),
          'region': _registeredRegionController.text.trim(),
          'countryCode': _registeredCountry,
        }),
        if (_hasTradingAddress)
          _compactMap({
            'addressType': 'TRADING',
            'streetName': _tradingStreetController.text.trim(),
            'buildingNumber': _tradingBuildingNumberController.text.trim(),
            'buildingName': _tradingBuildingNameController.text.trim(),
            'postcode': _tradingPostcodeController.text.trim(),
            'city': _tradingCityController.text.trim(),
            'region': _tradingRegionController.text.trim(),
            'countryCode': _tradingCountry,
          }),
      ],
    });

    await ref
        .read(businessFormControllerProvider.notifier)
        .submitDirectEqualsBusiness(
      associatedPeople: associatedPeople,
      application: application,
      proofOfFormation: proofOfFormation,
      proofOfOwnership: proofOfOwnership,
      identityDocuments: [
        applicantIdentity,
        if (_applicantIsDirector) null,
        if (_applicantIsUbo) null,
        for (final person in _additionalPeople)
          _businessDocumentUpload(person.identityDocument),
      ],
      addressDocuments: [
        applicantAddress,
        if (_applicantIsDirector) null,
        if (_applicantIsUbo) null,
        for (final person in _additionalPeople)
          _businessDocumentUpload(person.addressDocument),
      ],
    );
    if (!mounted) return;
    final result = ref.read(businessFormControllerProvider);
    if (result.hasError) {
      _showValidationMessage(complianceError(result.error!));
      return;
    }
    await _completeCompliance();
  }

  bool _complianceBusy = false;
  Future<void> _completeCompliance() async {
    if (_complianceBusy) return;
    setState(() => _complianceBusy = true);
    final api = ref.read(mobileBankingApiProvider);
    try {
      final completed =
          await Navigator.of(context).push<bool>(MaterialPageRoute(
              builder: (_) => EqualsComplianceScreen(
                    saveApplication: (application) async { await api.submitDirectEqualsBusinessApplication(application); },
                    uploadPerson: (personId, purpose, file) async {
                      await api.uploadBusinessOnboardingDocument(purpose: purpose, path: file.path, bytes: file.bytes, fileName: file.name, associatedPersonId: personId);
                    },
                    load: api.getBusinessCompliance,
                    call: api.businessCompliance,
                    upload: (purpose, file) async {
                      final result = await api.uploadBusinessOnboardingDocument(
                          purpose: purpose,
                          path: file.path,
                          bytes: file.bytes,
                          fileName: file.name);
                      return (result['complianceDocumentId'] as num?)
                              ?.toInt() ??
                          0;
                    },
                  )));
      if (completed == true) {
        await api.submitDirectEqualsBusinessApplicationForReview();
        ref.invalidate(businessOnboardingStatusProvider);
        if (mounted) {
          _showValidationMessage('Application submitted to Equals Money for review.');
        }
      }
    } catch (error) {
      if (mounted) _showValidationMessage(complianceError(error));
    } finally {
      if (mounted) setState(() => _complianceBusy = false);
    }
  }

  BusinessDocumentUpload? _businessDocumentUpload(PlatformFile? file) {
    if (file == null || (file.path == null && file.bytes == null)) return null;
    return BusinessDocumentUpload(
      name: file.name,
      path: file.path,
      bytes: file.bytes,
    );
  }
}

class _AdditionalPersonForm {
  _AdditionalPersonForm({
    required this.associationType,
    required this.country,
  });

  final String associationType;
  String country;
  List<String> nationalities = [];
  PlatformFile? identityDocument;
  PlatformFile? addressDocument;
  bool expanded = true;

  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final email = TextEditingController();
  final dateOfBirth = TextEditingController();
  final phone = TextEditingController();
  final taxId = TextEditingController();
  final ownership = TextEditingController();
  final street = TextEditingController();
  final buildingNumber = TextEditingController();
  final buildingName = TextEditingController();
  final postcode = TextEditingController();
  final city = TextEditingController();
  final region = TextEditingController();

  String get roleLabel =>
      associationType == 'DIRECTOR' ? 'Director' : 'Ultimate beneficial owner';

  String? get validationMessage {
    if (firstName.text.trim().isEmpty || lastName.text.trim().isEmpty) {
      return 'first and last name are required.';
    }
    if (_emailValidator(email.text) != null) {
      return 'enter a valid email address.';
    }
    final dob = DateTime.tryParse(dateOfBirth.text.trim());
    if (dob == null || dob.isAfter(_adultCutoff())) {
      return 'the person must be at least 18 years old.';
    }
    if (_phoneValidator(phone.text) != null) {
      return 'enter a valid international phone number.';
    }
    if (nationalities.isEmpty) return 'select at least one nationality.';
    if (street.text.trim().isEmpty ||
        buildingNumber.text.trim().isEmpty ||
        postcode.text.trim().isEmpty ||
        city.text.trim().isEmpty ||
        country.trim().isEmpty) {
      return 'complete all required residential address fields.';
    }
    if (buildingNumber.text.trim().length > 16) {
      return 'building number must be 16 characters or fewer.';
    }
    if (associationType == 'ULTIMATE_BENEFICIAL_OWNER' &&
        _ownershipValidator(ownership.text) != null) {
      return 'ownership must be between 0 and 100%.';
    }
    return null;
  }

  Map<String, Object?> toApiPayload() {
    final ownershipPercentage = associationType == 'ULTIMATE_BENEFICIAL_OWNER'
        ? double.tryParse(ownership.text.trim())
        : null;
    return _compactMap({
      'firstName': firstName.text.trim(),
      'lastName': lastName.text.trim(),
      'dateOfBirth': dateOfBirth.text.trim(),
      'nationalities': nationalities,
      'emailAddress': email.text.trim(),
      'phoneNumber': phone.text.trim(),
      'taxId': taxId.text.trim(),
      'associationType': associationType,
      'ownershipPercentage': ownershipPercentage,
      'addresses': [
        _compactMap({
          'addressType': 'RESIDENTIAL',
          'streetName': street.text.trim(),
          'buildingNumber': buildingNumber.text.trim(),
          'buildingName': buildingName.text.trim(),
          'postcode': postcode.text.trim(),
          'city': city.text.trim(),
          'region': region.text.trim(),
          'countryCode': country,
        }),
      ],
    });
  }

  void dispose() {
    for (final controller in [
      firstName,
      lastName,
      email,
      dateOfBirth,
      phone,
      taxId,
      ownership,
      street,
      buildingNumber,
      buildingName,
      postcode,
      city,
      region,
    ]) {
      controller.dispose();
    }
  }
}

class _BusinessSubmittedNotice extends StatelessWidget {
  const _BusinessSubmittedNotice();

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleEmptyState(
        icon: Icons.fact_check_outlined,
        title: context.tr('Application submitted'),
        body: context.tr(
            'Your application is being reviewed. Complete any provider actions or requested documents shown above.'),
      );
    }
    return EmptyState(
      title: context.tr('Application submitted'),
      message: context.tr(
          'Your application is being reviewed. Complete any provider actions or requested documents shown above.'),
      icon: Icons.fact_check_outlined,
    );
  }
}

class _BusinessProviderStatus extends StatelessWidget {
  const _BusinessProviderStatus({
    required this.status,
    required this.onUpload,
    required this.onOpenAction,
  });

  final Map<String, dynamic> status;
  final ValueChanged<_RequestedBusinessDocument> onUpload;
  final ValueChanged<String> onOpenAction;

  @override
  Widget build(BuildContext context) {
    final providerStatus = _findText(status, const [
      'status',
      'Status',
      'applicationStatus',
      'ApplicationStatus',
    ]);
    final requiredAction = _findText(status, const [
      'requiredAction',
      'RequiredAction',
      'nextAction',
      'NextAction',
    ]);
    final actionUrl = _findText(status, const [
      'actionUrl',
      'ActionUrl',
      'verificationUrl',
      'VerificationUrl',
      'nextUrl',
      'NextUrl',
    ]);
    final documents = _requestedBusinessDocuments(status);
    if ((providerStatus == null || providerStatus.isEmpty) &&
        requiredAction == null &&
        documents.isEmpty) {
      return const SizedBox.shrink();
    }

    if (context.isExampleTheme) {
      return _examplePanel(
        context,
        providerStatus: providerStatus,
        requiredAction: requiredAction,
        actionUrl: actionUrl,
        documents: documents,
      );
    }

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('EqualsMoney application'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (providerStatus != null)
              Text(context.tr(
                  'Status: {p0}', {'p0': providerStatus.replaceAll('_', ' ')})),
            if (requiredAction != null) ...[
              const SizedBox(height: 8),
              Text(context.tr('Action required: {p0}',
                  {'p0': requiredAction.replaceAll('_', ' ')})),
            ],
            for (final document in documents)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  document.expectsFiles
                      ? Icons.upload_file
                      : Icons.edit_note_outlined,
                ),
                title: Text(_businessRequestLabel(document)),
                subtitle: document.expectsFiles
                    ? Text([
                        if (document.associatedPersonId != null)
                          'Associated person request',
                        if (document.additionalInformation != null)
                          document.additionalInformation!,
                      ].join('\n'))
                    : null,
                trailing: OutlinedButton(
                  onPressed: () => onUpload(document),
                  child: Text(document.expectsFiles
                      ? context.tr('Upload')
                      : context.tr('Answer')),
                ),
              ),
            if (actionUrl != null &&
                Uri.tryParse(actionUrl)?.isScheme('https') == true)
              FilledButton.icon(
                onPressed: () => onOpenAction(actionUrl),
                icon: const Icon(Icons.open_in_new),
                label: Text(context.tr('Continue secure check')),
              ),
          ],
        ),
      ),
    );
  }

  /// Example reads the provider's answer as a panel: eyebrow, one status
  /// pill, then the outstanding requests as rows rather than list tiles.
  Widget _examplePanel(
    BuildContext context, {
    required String? providerStatus,
    required String? requiredAction,
    required String? actionUrl,
    required List<_RequestedBusinessDocument> documents,
  }) {
    final theme = Theme.of(context);
    final hasStatus = providerStatus != null && providerStatus.isNotEmpty;
    final pillColor = requiredAction != null
        ? ExampleColors.warning
        : _statusIsCleared(providerStatus)
            ? ExampleColors.success
            : ExampleColors.iris;
    return ExampleGlassPanel(
      radius: AppRadii.lg,
      borderAlpha: .30,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('EQUALSMONEY APPLICATION'),
                  style: ExampleTextStyles.label(context),
                ),
              ),
              if (hasStatus) ...[
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: ExamplePill(
                    label: _humanise(providerStatus),
                    color: pillColor,
                    dot: true,
                  ),
                ),
              ],
            ],
          ),
          if (requiredAction != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('Action required: {p0}',
                  {'p0': _humanise(requiredAction).toLowerCase()}),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ExampleInk.secondary(context),
              ),
            ),
          ],
          for (var index = 0; index < documents.length; index++)
            ExampleRow(
              title: _businessRequestLabel(documents[index]),
              subtitle: _requestSubtitle(documents[index]),
              divider: index < documents.length - 1,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              onTap: () => onUpload(documents[index]),
              semanticsLabel: documents[index].expectsFiles
                  ? context.tr('Upload {p0}',
                      {'p0': _businessRequestLabel(documents[index])})
                  : context.tr('Answer {p0}',
                      {'p0': _businessRequestLabel(documents[index])}),
              trailing: Text(
                documents[index].expectsFiles
                    ? context.tr('Upload')
                    : context.tr('Answer'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.accent(context, ExampleColors.iris),
                ),
              ),
            ),
          if (actionUrl != null &&
              Uri.tryParse(actionUrl)?.isScheme('https') == true) ...[
            const SizedBox(height: AppSpacing.sm),
            // The provider's escalation, in the house glass instead of the
            // Material slab it shipped with — this panel is Example-only, so
            // a FilledButton here was the second primary material on a screen
            // whose CTA bar is already glass.
            //
            // The tone is the judgement call. While the application is still
            // being filled in, the bottom bar owns Continue / Submit and this
            // is a detour, so it takes `neutral`: same object, same 54 pt
            // silhouette, same press and focus ring, deliberately not louder
            // than the action that finishes the form. Once the application is
            // submitted the bar is gone (see the `bottomNavigationBar` gate),
            // this becomes the only action left on the screen, and it takes
            // `primary`. Either way the screen has exactly one primary.
            //
            // `surface` ground: ExampleGlassPanel is already the frosted layer
            // here, and a second bounded blur would sample its own output.
            ExampleGlassButton(
              label: context.tr('Continue secure check'),
              icon: Icons.open_in_new,
              tone: _businessApplicationSubmitted(status)
                  ? ExampleGlassButtonTone.primary
                  : ExampleGlassButtonTone.neutral,
              semanticsLabel:
                  context.tr('Continue secure check with the provider'),
              onPressed: () => onOpenAction(actionUrl),
            ),
          ],
        ],
      ),
    );
  }

  String? _requestSubtitle(_RequestedBusinessDocument document) {
    if (!document.expectsFiles) return null;
    final parts = [
      if (document.associatedPersonId != null) 'Associated person request',
      if (document.additionalInformation != null)
        document.additionalInformation!,
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }

  static String _humanise(String? value) =>
      (value ?? '').replaceAll('_', ' ').trim();

  static bool _statusIsCleared(String? value) {
    final normalised = (value ?? '').toUpperCase();
    return normalised.contains('APPROVED') ||
        normalised.contains('ACTIVE') ||
        normalised.contains('COMPLETE');
  }
}

class _RequestedBusinessDocument {
  const _RequestedBusinessDocument({
    required this.type,
    required this.label,
    this.expectedResponseType = 'file',
    this.additionalInformation,
    this.associatedPersonId,
  });

  final String type;
  final String label;
  final String expectedResponseType;
  final String? additionalInformation;
  final String? associatedPersonId;

  bool get expectsFiles => expectedResponseType.trim().toLowerCase() == 'file';
}

String _businessRequestLabel(_RequestedBusinessDocument document) {
  return document.type.trim().toUpperCase() == 'RESIDENTIAL_ADDRESS'
      ? 'Enter your residential address'
      : document.label;
}

bool _businessApplicationExists(Map<String, dynamic> status) {
  final value = (_findText(status, const ['status', 'Status', 'applicationStatus', 'ApplicationStatus']) ?? '').trim().toLowerCase();
  return value.isNotEmpty && !const {'not_started', 'not started', 'none'}.contains(value);
}

bool _businessApplicationResumable(Map<String, dynamic> status) {
  final value = (_findText(status, const [
            'status',
            'Status',
            'applicationStatus',
            'ApplicationStatus'
          ]) ??
          '')
      .toLowerCase();
  return const {'draft', 'created', 'rejected'}.contains(value);
}

bool _businessApplicationSubmitted(Map<String, dynamic> status) {
  final value = (_findText(status, const [
            'status',
            'Status',
            'applicationStatus',
            'ApplicationStatus',
          ]) ??
          '')
      .trim()
      .toLowerCase();
  return const {
    'submitted',
    'in_review',
    'under_review',
    'pending',
    'approved',
    'completed',
    'active'
  }.contains(value);
}

List<_RequestedBusinessDocument> _requestedBusinessDocuments(Object? value) {
  final documents = <_RequestedBusinessDocument>[];

  void visit(Object? item, [int depth = 0, bool insideRequested = false]) {
    if (depth > 8) return;
    if (item is List) {
      for (final child in item) {
        visit(child, depth + 1, insideRequested);
      }
      return;
    }
    if (item is! Map) return;
    final map = item.map((key, child) => MapEntry(key.toString(), child));
    final type = (map['type'] ??
            map['Type'] ??
            map['purpose'] ??
            map['Purpose'] ??
            map['documentType'] ??
            map['DocumentType'])
        ?.toString()
        .trim();
    final appearsRequested = insideRequested ||
        map.keys.any((key) =>
            key.toLowerCase().contains('additionaldocumentsrequested') ||
            key.toLowerCase().contains('requesteddocuments'));
    if (type != null &&
        type.isNotEmpty &&
        (appearsRequested ||
            map.containsKey('associatedPersonId') ||
            map.containsKey('applicationId'))) {
      final label = (map['text'] ??
                  map['Text'] ??
                  map['label'] ??
                  map['Label'] ??
                  map['name'] ??
                  map['Name'])
              ?.toString()
              .trim() ??
          type.replaceAll('_', ' ');
      final personId = (map['associatedPersonId'] ?? map['AssociatedPersonId'])
          ?.toString()
          .trim();
      final expectedResponseType =
          (map['expectedResponseType'] ?? map['ExpectedResponseType'])
                  ?.toString()
                  .trim() ??
              'file';
      final additionalInformation =
          (map['additionalInformation'] ?? map['AdditionalInformation'])
              ?.toString()
              .trim();
      documents.add(_RequestedBusinessDocument(
        type: type,
        label: label,
        expectedResponseType: expectedResponseType,
        additionalInformation:
            additionalInformation == null || additionalInformation.isEmpty
                ? null
                : additionalInformation,
        associatedPersonId:
            personId == null || personId.isEmpty ? null : personId,
      ));
    }
    for (final entry in map.entries) {
      final key = entry.key.toLowerCase();
      visit(
        entry.value,
        depth + 1,
        appearsRequested ||
            key.contains('additionaldocumentsrequested') ||
            key.contains('requesteddocuments'),
      );
    }
  }

  visit(value);
  final unique = <String, _RequestedBusinessDocument>{};
  for (final document in documents) {
    unique['${document.type}:${document.associatedPersonId ?? ''}'] = document;
  }
  return unique.values.toList();
}

String? _findText(Object? value, List<String> keys, [int depth = 0]) {
  if (depth > 8 || value == null) return null;
  if (value is List) {
    for (final child in value) {
      final result = _findText(child, keys, depth + 1);
      if (result != null) return result;
    }
    return null;
  }
  if (value is! Map) return null;
  for (final key in keys) {
    final text = value[key]?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  for (final child in value.values) {
    final result = _findText(child, keys, depth + 1);
    if (result != null) return result;
  }
  return null;
}

class _BusinessProgress extends StatelessWidget {
  const _BusinessProgress({required this.currentSection});

  final int currentSection;

  static const _labels = [
    'Company',
    'Address',
    'People',
    'Services',
    'Documents',
  ];

  /// The section names Example puts in the page title; the Material path keeps
  /// its own short [_labels].
  static const exampleLabels = [
    'Business details',
    'Registered address',
    'Associated people',
    'Services',
    'Verification documents',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (context.isExampleTheme) {
      final done = ExampleInk.accent(context, ExampleColors.iris);
      final track = ExampleTheme.isLight(context)
          ? ExamplePalette.of(context).surfaceHigh
          : ExamplePalette.of(context).ink.withValues(alpha: .12);
      const radius = BorderRadius.all(Radius.circular(AppRadii.pill));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The section name is the page title, so no section repeats it
          // further down: one name per state of the form.
          Text(
            exampleLabels[currentSection],
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
              color: ExampleInk.primary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: context.tr('Application progress'),
            value: 'Section ${currentSection + 1} of ${_labels.length}',
            child: Row(
              children: [
                for (var index = 0; index < _labels.length; index++) ...[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: index <= currentSection ? done : track,
                        borderRadius: radius,
                      ),
                      child: const SizedBox(height: 3),
                    ),
                  ),
                  if (index != _labels.length - 1)
                    const SizedBox(width: AppSpacing.xxs),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('Section {p0} of {p1}',
                {'p0': currentSection + 1, 'p1': _labels.length}),
            style: theme.textTheme.labelSmall?.copyWith(
              color: ExampleInk.tertiary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Step {p0} of {p1}: {p2}', {
                'p0': currentSection + 1,
                'p1': _labels.length,
                'p2': _labels[currentSection]
              }),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (currentSection + 1) / _labels.length,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr(
                  'Complete one section at a time. Your entries stay available while you review earlier steps before submission.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      // The step header above already names the section; repeating it here
      // was the same word twice on one screen.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children.expand(
            (child) => [child, const SizedBox(height: AppSpacing.sm)],
          ),
        ],
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children.expand((child) => [child, const SizedBox(height: 12)]),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.required = true,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.maxLength,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool required;
  final int maxLines;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ExampleInk.secondary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            maxLength: maxLength,
            decoration: InputDecoration(hintText: hint),
            validator: validator ?? (required ? _required : null),
          ),
        ],
      );
    }
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validator ?? (required ? _required : null),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.lastDate,
  });

  final TextEditingController controller;
  final String label;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        hintText: context.tr('YYYY-MM-DD'),
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      validator: _required,
      onTap: () async {
        final current = DateTime.tryParse(controller.text);
        final selected = await showDatePicker(
          context: context,
          initialDate: current ?? lastDate,
          firstDate: DateTime(1900),
          lastDate: lastDate,
        );
        if (selected != null) {
          controller.text = _isoDate(selected);
        }
      },
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ExampleInk.secondary(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: ExampleInk.primary(context),
            ),
            dropdownColor: ExampleSurface.navigationOf(context),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option,
                  child: Text(
                    _label(option),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            validator: (value) => value == null ? '$label is required' : null,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ],
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              _label(option),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      validator: (value) => value == null ? '$label is required' : null,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.title,
    required this.file,
    required this.onPick,
  });

  final String title;
  final PlatformFile? file;
  final ValueChanged<PlatformFile> onPick;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      final uploaded = file != null;
      // A row inside the documents group rather than a bordered card of its
      // own: four identical cards stacked is the grid the laws reject, and
      // the whole row is a 56 pt target for the picker.
      return ExampleRow(
        title: title,
        subtitle: file?.name ?? 'PDF, JPG or PNG',
        onTap: _pickFile,
        semanticsLabel: uploaded
            ? context.tr('Replace {p0}, {p1}', {'p0': title, 'p1': file!.name})
            : context.tr('Upload {p0}', {'p0': title}),
        leading: ExampleIconTile(
          icon: uploaded ? Icons.check_rounded : Icons.file_upload_outlined,
          color: uploaded ? ExampleColors.success : ExampleColors.iris,
        ),
        trailing: uploaded
            ? ExamplePill(
                label: context.tr('Uploaded'),
                color: ExampleColors.success,
                dot: true,
              )
            : Text(
                context.tr('Upload'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.accent(context, ExampleColors.iris),
                ),
              ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.upload_file),
      title: Text(title),
      subtitle: Text(file?.name ?? 'Required'),
      trailing: TextButton(
        onPressed: _pickFile,
        child: Text(context.tr('Choose')),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked != null && (picked.path != null || picked.bytes != null)) {
      onPick(picked);
    }
  }
}

Map<String, Object?> _compactMap(Map<String, Object?> value) {
  return Map.fromEntries(
    value.entries.where((entry) {
      final item = entry.value;
      if (item == null) {
        return false;
      }
      if (item is String) {
        return item.trim().isNotEmpty;
      }
      if (item is Iterable) {
        return item.isNotEmpty;
      }

      return true;
    }),
  );
}

String _label(String value) {
  const overrides = {
    'PRIVATE_COMPANY': 'Private Company',
    'SOLE_TRADER': 'Sole Trader',
    'PUBLIC_COMPANY_LISTED': 'Public Company (Listed)',
    'PUBLIC_COMPANY_UNLISTED': 'Public Company (Unlisted)',
    'NON_PROFIT': 'Non Profit',
    'SOCIAL_ENTERPRISE': 'Social Enterprise',
    'SEGREGATED_PORTFOLIO_COMPANY': 'Segregated Portfolio Company',
    'ONE_TO_TEN': '1 to 10',
    'ELEVEN_TO_FIFTY': '11 to 50',
    'FIFTY_ONE_TO_TWO_HUNDRED': '51 to 200',
    'TWO_HUNDRED_AND_ONE_TO_FIVE_HUNDRED': '201 to 500',
    'FIVE_HUNDRED_AND_ONE_TO_ONE_THOUSAND': '501 to 1,000',
    'ONE_THOUSAND_AND_ONE_TO_FIVE_THOUSAND': '1,001 to 5,000',
    'FIVE_THOUSAND_AND_ONE_TO_TEN_THOUSAND': '5,001 to 10,000',
    'TEN_THOUSAND_PLUS': '10,000+',
    'FEWER-THAN-5-PAYMENTS': 'Fewer than 5 payments',
  };
  final override = overrides[value];
  if (override != null) return override;
  const acronyms = {
    'ACH',
    'API',
    'ATM',
    'B2B',
    'CBD',
    'CFD',
    'EU',
    'FPS',
    'FX',
    'GBP',
    'IPO',
    'IT',
    'NAICS',
    'OTC',
    'P2P',
    'SEO',
    'SCO',
    'TV',
    'UBO',
    'UK',
    'US',
    'USD',
    'VAT',
  };
  return value.replaceAll('_', ' ').toLowerCase().split(' ').map((part) {
    if (acronyms.contains(part.toUpperCase())) return part.toUpperCase();

    return '${part[0].toUpperCase()}${part.substring(1)}';
  }).join(' ');
}

String _countryLabel(String code) {
  const names = {
    'AT': 'Austria',
    'BE': 'Belgium',
    'BG': 'Bulgaria',
    'CH': 'Switzerland',
    'CY': 'Cyprus',
    'CZ': 'Czechia',
    'DE': 'Germany',
    'DK': 'Denmark',
    'EE': 'Estonia',
    'ES': 'Spain',
    'FI': 'Finland',
    'FR': 'France',
    'GB': 'United Kingdom',
    'GR': 'Greece',
    'HR': 'Croatia',
    'HU': 'Hungary',
    'IE': 'Ireland',
    'IS': 'Iceland',
    'IT': 'Italy',
    'LI': 'Liechtenstein',
    'LT': 'Lithuania',
    'LU': 'Luxembourg',
    'LV': 'Latvia',
    'MT': 'Malta',
    'NL': 'Netherlands',
    'NO': 'Norway',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'SE': 'Sweden',
    'SI': 'Slovenia',
    'SK': 'Slovakia',
    'US': 'United States',
  };
  final name = names[code];
  return name == null ? code : '$name ($code)';
}

bool _requiresIncorporationRegion(String countryCode) =>
    const {'US', 'FR', 'DE'}.contains(countryCode);

DateTime _adultCutoff() {
  final now = DateTime.now();
  return DateTime(now.year - 18, now.month, now.day);
}

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String? _businessOverviewValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Required';
  if (text.length < 10 || text.length > 1000) {
    return 'Use between 10 and 1,000 characters';
  }
  return null;
}

String? _emailValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Required';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text)) {
    return 'Enter a valid email address';
  }
  return null;
}

String? _phoneValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Required';
  final digits = text.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 7 || digits.length > 15) {
    return 'Enter a valid international phone number';
  }
  return null;
}

String? _websiteValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final normalized = RegExp(r'^https?://', caseSensitive: false).hasMatch(text)
      ? text
      : 'https://$text';
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      !uri.host.contains('.')) {
    return 'Enter a valid website, for example https://example.com';
  }
  return null;
}

String _normalizeWebsite(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
    return text;
  }
  return 'https://$text';
}

String? _ownershipValidator(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Required';
  final ownership = double.tryParse(text);
  if (ownership == null || ownership < 0 || ownership > 100) {
    return 'Enter a percentage from 0 to 100';
  }
  return null;
}

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }

  return null;
}

/// Forces the Material switch for Example, and leaves every other brand alone.
///
/// `Switch.adaptive` renders the Cupertino control on iOS and macOS — web
/// included — and the Cupertino switch consults none of `SwitchThemeData`. On
/// pearl daylight that shipped an off state of a white thumb on a near-white
/// track: 1.31:1 thumb-to-track, 1.21:1 track-to-page. Overriding `platform`
/// for the switch's own subtree routes Example to the Material switch — and so
/// to the theme's thumb, track and 3:1 track outline — while a non-Example
/// brand keeps the adaptive control it renders today, byte for byte.
Widget _materialSwitchForExample(BuildContext context, Widget child) =>
    context.isExampleTheme
        ? Theme(
            data: Theme.of(context).copyWith(platform: TargetPlatform.android),
            child: child,
          )
        : child;
