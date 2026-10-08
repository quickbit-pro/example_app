import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/application/referral_invitation_providers.dart';
import 'package:mobile_flutter/features/signup/data/referral_invitation_repository.dart';
import 'package:mobile_flutter/features/signup/domain/referral_invitation.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';

void main() {
  testWidgets('valid invitation prefills and locks email and referral code',
      (tester) async {
    final repository = _FakeRepository(
      ReferralInvitationPreview(
        email: 'invitee@example.com',
        referralCode: 'ABC1234',
        inviterDisplayName: 'John',
        expiresAt: _futureDate,
      ),
    );
    await _pump(tester, repository: repository, token: 'opaque-token');

    expect(
      find.byKey(const Key('referral_invitation_banner')),
      findsOneWidget,
    );
    final email = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('signup_email')),
        matching: find.byType(EditableText),
      ),
    );
    expect(email.controller.text, 'invitee@example.com');
    expect(email.readOnly, isTrue);

    final referral = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(
          const Key('signup_referral_code'),
          skipOffstage: false,
        ),
        matching: find.byType(EditableText, skipOffstage: false),
      ),
    );
    expect(referral.controller.text, 'ABC1234');
    expect(referral.readOnly, isTrue);
  });

  testWidgets('invalid and expired invitations show exact messages',
      (tester) async {
    for (final entry in {
      ReferralInvitationFailureType.invalid:
          'This referral invitation is invalid.',
      ReferralInvitationFailureType.expired:
          'This referral invitation has expired or has already been used.',
    }.entries) {
      await _pump(
        tester,
        repository: _FakeRepository(ReferralInvitationFailure(entry.key)),
        token: 'opaque-token',
      );
      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets(
      'network retry repeats preview and normal signup remains available',
      (tester) async {
    final repository = _RetryRepository();
    await _pump(tester, repository: repository, token: 'opaque-token');

    expect(repository.calls, 1);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Create account without invitation'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repository.calls, 2);
    expect(find.text('Choose your account'), findsOneWidget);
  });

  testWidgets('normal signup does not resolve an invitation', (tester) async {
    final repository = _FakeRepository(
      const ReferralInvitationFailure(ReferralInvitationFailureType.invalid),
    );
    await _pump(tester, repository: repository);

    expect(repository.calls, 0);
    expect(find.text('Choose your account'), findsOneWidget);
  });
}

final _futureDate = DateTime.utc(2099, 1, 1);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeRepository repository,
  String? token,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        referralInvitationRepositoryProvider.overrideWithValue(repository),
        mobileTenantConfigProvider.overrideWith(
          (ref) async => const MobileTenantConfig(
            companyName: 'Hoppa',
            brandName: 'Hoppa',
            referralsEnabled: true,
            referralRegistrationMode: 'optional',
            vouchersEnabled: true,
            existingAccountClaimEnabled: true,
            boomFiExchangeEnabled: true,
            walletOutflowsEnabled: true,
            equalsMoneyEnabled: true,
          ),
        ),
      ],
      child: MaterialApp(
        home: SignupScreen(invitationToken: token),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeRepository implements ReferralInvitationRepository {
  _FakeRepository(this.result);

  final Object result;
  int calls = 0;

  @override
  Future<ReferralInvitationPreview> preview(String token) async {
    calls++;
    if (result is ReferralInvitationPreview) {
      return result as ReferralInvitationPreview;
    }
    throw result;
  }
}

class _RetryRepository extends _FakeRepository {
  _RetryRepository()
      : super(
          const ReferralInvitationFailure(
            ReferralInvitationFailureType.network,
          ),
        );

  @override
  Future<ReferralInvitationPreview> preview(String token) async {
    calls++;
    if (calls == 1) {
      throw const ReferralInvitationFailure(
        ReferralInvitationFailureType.network,
      );
    }
    return ReferralInvitationPreview(
      email: 'invitee@example.com',
      referralCode: 'ABC1234',
      inviterDisplayName: 'John',
      expiresAt: _futureDate,
    );
  }
}
