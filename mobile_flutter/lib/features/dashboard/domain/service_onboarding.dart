enum OnboardingService {
  cryptoCards('Crypto Cards'),
  banking('Banking'),
  exchange('Exchange');

  const OnboardingService(this.label);
  final String label;
}

enum OnboardingStage {
  start('Start'),
  inProgress('In progress'),
  rejected('Rejected'),
  needUpdate('Need update'),
  complete('Complete'),
  unavailable('Check status');

  const OnboardingStage(this.label);
  final String label;
}

class ServiceOnboardingItem {
  const ServiceOnboardingItem({
    required this.name,
    required this.status,
    required this.needsAction,
    this.service,
    this.blockedBy,
    this.completedAt,
    this.owner,
  });

  final String name;
  final String status;
  final bool needsAction;
  final OnboardingService? service;
  final OnboardingService? blockedBy;
  final DateTime? completedAt;
  final String? owner;

  OnboardingService get kind =>
      service ??
      (name.toLowerCase().contains('banking')
          ? OnboardingService.banking
          : name.toLowerCase().contains('exchange')
              ? OnboardingService.exchange
              : OnboardingService.cryptoCards);
  OnboardingStage get stage => onboardingStage(status);

  ServiceOnboardingItem forOwner(String? value) => ServiceOnboardingItem(
      name: name,
      status: status,
      needsAction: needsAction,
      service: kind,
      blockedBy: blockedBy,
      completedAt: completedAt,
      owner: value);
}

String normalizedOnboardingStatus(Object? value) =>
    value?.toString().trim().toLowerCase().replaceAll(RegExp(r'[-\s]+'), '_') ??
    '';

OnboardingStage onboardingStage(Object? value, {bool submitted = false}) {
  final status = normalizedOnboardingStatus(value);
  if (const {
    'approved',
    'accepted',
    'active',
    'ready',
    'complete',
    'completed',
    'verified'
  }.contains(status)) {
    return OnboardingStage.complete;
  }
  if (const {'rejected', 'failed', 'declined', 'denied'}.contains(status)) {
    return OnboardingStage.rejected;
  }
  if (const {
    'need_update',
    'needs_update',
    'resubmission_required',
    'action_required',
    'invite_required',
    'payment_required',
    'information_required',
    'documents_required',
    'additional_documents_required',
    'application_needs_attention',
    'accept_your_banking_invite',
    'onboarding_payment_required'
  }.contains(status)) {
    return OnboardingStage.needUpdate;
  }
  if (const {'unavailable', 'disabled_in_staging', 'check_status', 'unknown'}
      .contains(status)) {
    return OnboardingStage.unavailable;
  }
  if (const {'start', 'not_started', 'not_selected', 'setup_incomplete'}
      .contains(status)) {
    return OnboardingStage.start;
  }
  if (status.isEmpty) {
    return submitted ? OnboardingStage.inProgress : OnboardingStage.start;
  }
  return OnboardingStage.inProgress;
}

/// Includes completed services: presentation remembers acknowledgement and the
/// completion window separately, without losing their place in the sequence.
List<ServiceOnboardingItem> remainingServiceOnboarding({
  bool cardsEnabled = true,
  required bool bankingEnabled,
  required bool exchangeEnabled,
  required Map<String, dynamic> preferences,
  required Map<String, dynamic> progress,
}) {
  final submitted = progress['submissionRequested'] == true;
  final selections = <OnboardingService, String>{
    if (cardsEnabled && preferences['cryptoCard'] == true)
      OnboardingService.cryptoCards: 'interlace',
    if (bankingEnabled &&
        preferences['enabled'] == true &&
        preferences['banking'] == true)
      OnboardingService.banking: 'equalsMoney',
    if (exchangeEnabled &&
        preferences['enabled'] == true &&
        preferences['exchange'] == true)
      OnboardingService.exchange: 'boomFi',
  };
  OnboardingService? previousIncomplete;
  return selections.entries.map((entry) {
    final stage = onboardingStage(progress[entry.value], submitted: submitted);
    final completed = DateTime.tryParse(
        progress['${entry.value}CompletedAt']?.toString() ?? '');
    final item = ServiceOnboardingItem(
        name: entry.key.label,
        status: stage.label,
        needsAction: {
          OnboardingStage.start,
          OnboardingStage.needUpdate,
          OnboardingStage.rejected
        }.contains(stage),
        service: entry.key,
        completedAt: completed,
        blockedBy: stage == OnboardingStage.start ? previousIncomplete : null);
    if (stage != OnboardingStage.complete) previousIncomplete ??= entry.key;
    return item;
  }).toList(growable: false);
}
