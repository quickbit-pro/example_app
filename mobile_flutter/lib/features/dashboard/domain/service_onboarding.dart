class ServiceOnboardingItem {
  const ServiceOnboardingItem({
    required this.name,
    required this.status,
    required this.needsAction,
  });

  final String name;
  final String status;
  final bool needsAction;
}

/// Registration preferences identify the requested services. Identity approval
/// alone does not complete either provider's separate application.
List<ServiceOnboardingItem> remainingServiceOnboarding({
  required bool bankingEnabled,
  required bool exchangeEnabled,
  required Map<String, dynamic> preferences,
  required Map<String, dynamic> progress,
}) {
  if (preferences['enabled'] != true) return const [];
  final submitted = progress['submissionRequested'] == true;
  return [
    if (bankingEnabled && preferences['banking'] == true)
      _item('Equals Money banking', progress['equalsMoney'], submitted),
    if (exchangeEnabled && preferences['exchange'] == true)
      _item('ZBX exchange', progress['boomFi'], submitted),
  ].whereType<ServiceOnboardingItem>().toList(growable: false);
}

ServiceOnboardingItem? _item(String name, Object? value, bool submitted) {
  final status =
      value?.toString().trim().toLowerCase().replaceAll('-', '_') ?? '';
  if (const {'approved', 'accepted', 'active', 'ready', 'complete', 'completed'}
      .contains(status)) {
    return null;
  }
  final (label, needsAction) = switch (status) {
    'invite_required' => ('Accept your banking invite', true),
    'payment_required' => ('Onboarding payment required', true),
    'rejected' || 'resubmission_required' || 'action_required' => (
        'Application needs attention',
        true
      ),
    'disabled_in_staging' => ('Unavailable in this environment', false),
    'submitted' ||
    'dispatching' ||
    'reconciliation_required' ||
    'in_review' ||
    'under_review' ||
    'processing' =>
      ('Application under review', false),
    _ => submitted
        ? ('Application under review', false)
        : ('Setup incomplete', true),
  };
  return ServiceOnboardingItem(
      name: name, status: label, needsAction: needsAction);
}
