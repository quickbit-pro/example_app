import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_share.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  group('resolveReferralShareLink', () {
    const malformedConnectedAccountLink =
        'https://example.comhttps://my.example.com/#/signup?ref=S4MBAL7';

    test('connected-account links with two origins use the current app on web',
        () {
      for (final origin in [
        'https://my.example.com',
        'https://example-dev.roks.dev',
        'https://hoppa.roks.dev',
      ]) {
        expect(
          resolveReferralShareLink(
            referralCode: 'S4MBAL7',
            referralPath: malformedConnectedAccountLink,
            currentWebUri: Uri.parse('$origin/#/rewards'),
          ),
          '$origin/#/signup?ref=S4MBAL7',
        );
      }
    });

    test('native repairs a doubled origin using the configured app and code',
        () {
      expect(
        resolveReferralShareLink(
          referralCode: 'S4MBAL7',
          referralPath: malformedConnectedAccountLink,
          webAppUrl: 'https://my.example.com',
        ),
        'https://my.example.com/#/signup?ref=S4MBAL7',
      );
    });

    test('a doubled origin without an app address is never shared', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'S4MBAL7',
          referralPath: malformedConnectedAccountLink,
        ),
        isNull,
      );
    });

    test('a valid absolute link can carry another URL in its query', () {
      const path =
          'https://my.example.com/#/signup?ref=S4MBAL7&next=https://example.com';
      expect(
        resolveReferralShareLink(
          referralCode: 'S4MBAL7',
          referralPath: path,
          currentWebUri: Uri.parse('https://example-dev.roks.dev/#/rewards'),
        ),
        path,
      );
    });

    test('an absolute referral path from the platform is used verbatim', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          referralPath: ' https://hoppa.roks.dev/#/signup?ref=UUDPDZX ',
          currentWebUri: Uri.parse('https://elsewhere.test/#/rewards'),
          webAppUrl: 'https://mobile.test',
        ),
        'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
      );
    });

    test('a relative dashboard route on web becomes the app sign-up route', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          referralPath: '/registration?referralCode=UUDPDZX',
          currentWebUri:
              Uri.parse('https://hoppa.roks.dev/?theme=dark#/rewards'),
        ),
        'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
      );
    });

    test('web keeps the directory the app is served from', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'ABC',
          currentWebUri: Uri.parse('https://cards.test/app/index.html#/home'),
        ),
        'https://cards.test/app/#/signup?ref=ABC',
      );
    });

    test('native builds use the configured web app address', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          referralPath: '/registration?referralCode=UUDPDZX',
          webAppUrl: 'https://hoppa.roks.dev',
        ),
        'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
      );
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          webAppUrl: 'https://hoppa.roks.dev/#/login',
        ),
        'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
      );
    });

    test('the code is query-encoded', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'A B&C',
          webAppUrl: 'https://hoppa.roks.dev/',
        ),
        'https://hoppa.roks.dev/#/signup?ref=A+B%26C',
      );
    });

    test('no usable address means no link', () {
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          referralPath: '/registration?referralCode=UUDPDZX',
        ),
        isNull,
      );
      expect(
        resolveReferralShareLink(referralCode: 'UUDPDZX', webAppUrl: ''),
        isNull,
      );
      expect(
        resolveReferralShareLink(
          referralCode: 'UUDPDZX',
          webAppUrl: 'hoppa.roks.dev',
        ),
        isNull,
        reason: 'a bare host is not a link a friend can open',
      );
      expect(
        resolveReferralShareLink(
          referralCode: '  ',
          webAppUrl: 'https://hoppa.roks.dev',
        ),
        isNull,
      );
    });
  });

  group('buildReferralShareText', () {
    const offer = ReferralOffer(
      welcomeAmount: 3,
      welcomeCurrency: 'USD',
      qualificationRate: 1,
      topupRate: 0.25,
    );

    test('names the app, the welcome reward, the link and the code', () {
      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: ' UUDPDZX ',
        link: 'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
        offer: offer,
      );

      expect(
        text,
        'Join me on Hoppa and get \$3 on your USD balance after your first '
        'top-up. Sign up with my link: https://hoppa.roks.dev/#/signup?ref=UUDPDZX '
        '— or enter code UUDPDZX when you register.',
      );
    });

    test('states the minimum top-up when the offer has one', () {
      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: 'UUDPDZX',
        link: 'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
        offer: const ReferralOffer(
          welcomeAmount: 5.5,
          welcomeCurrency: 'EUR',
          minimumTopup: 20,
        ),
      );

      expect(
        text,
        startsWith('Join me on Hoppa and get €5.50 on your EUR balance after '
            'your first top-up of €20 or more.'),
      );
    });

    test('promises the welcome at sign-up when no top-up is required', () {
      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: 'UUDPDZX',
        offer: const ReferralOffer(welcomeAmount: 3, requiresTopup: false),
      );

      expect(
        text,
        'Join me on Hoppa and get \$3 on your USD balance when you sign up. '
        'Enter code UUDPDZX when you register.',
      );
    });

    test('drops the reward sentence when the offer has no welcome amount', () {
      for (final noWelcome in [
        null,
        const ReferralOffer(welcomeAmount: 0, qualificationRate: 1),
      ]) {
        final text = buildReferralShareText(
          appName: 'Hoppa',
          referralCode: 'UUDPDZX',
          link: 'https://hoppa.roks.dev/#/signup?ref=UUDPDZX',
          offer: noWelcome,
        );

        expect(
          text,
          'Join me on Hoppa. Sign up with my link: '
          'https://hoppa.roks.dev/#/signup?ref=UUDPDZX — or enter code UUDPDZX '
          'when you register.',
        );
      }
    });

    test('falls back to the code alone when there is no link', () {
      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: 'UUDPDZX',
        link: ' ',
        offer: offer,
      );

      expect(
        text,
        'Join me on Hoppa and get \$3 on your USD balance after your first '
        'top-up. Enter code UUDPDZX when you register.',
      );
      expect(text, isNot(contains('http')));
    });

    test('never masks the reward under Private Mode', () {
      Money.maskAmounts = true;
      addTearDown(() => Money.maskAmounts = false);

      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: 'UUDPDZX',
        offer: offer,
      );

      expect(text, contains('\$3'));
      expect(text, isNot(contains('••••')));
    });

    test('uses the app catalogue for the copy', () {
      const l10n = AppLocalizations(Locale('de'), {
        'Join me on {p0}.': 'Mach mit bei {p0}.',
        'Enter code {p0} when you register.':
            'Gib bei der Registrierung den Code {p0} ein.',
      });

      final text = buildReferralShareText(
        appName: 'Hoppa',
        referralCode: 'UUDPDZX',
        translate: l10n.translate,
      );

      expect(
        text,
        'Mach mit bei Hoppa. Gib bei der Registrierung den Code UUDPDZX ein.',
      );
    });

    test('every sentence of the invitation is in every catalogue', () {
      const sentences = [
        'Join me on {p0}.',
        'Join me on {p0} and get {p1} on your {p2} balance after your first top-up.',
        'Join me on {p0} and get {p1} on your {p2} balance after your first top-up of {p3} or more.',
        'Join me on {p0} and get {p1} on your {p2} balance when you sign up.',
        'Sign up with my link: {p0} — or enter code {p1} when you register.',
        'Enter code {p0} when you register.',
        "You're invited to {p0}",
      ];
      for (final language in appLanguages) {
        final catalogue = jsonDecode(
          File('assets/l10n/${language.code}.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        for (final sentence in sentences) {
          expect(catalogue, contains(sentence),
              reason: '${language.code}: $sentence');
        }
      }
    });
  });
}
