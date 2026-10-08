import 'dart:async';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart'
    as banking;
import 'package:mobile_flutter/features/dashboard/data/dashboard_providers.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';

void main() {
  test('Home refresh fetches new transactions and the portfolio together',
      () async {
    var dashboardCalls = 0;
    var portfolioCalls = 0;
    var historyCalls = 0;
    final container = ProviderContainer(overrides: [
      banking.activityTransactionsProvider.overrideWith((ref) async {
        historyCalls++;
        return historyCalls == 1
            ? []
            : [
                LedgerTransaction.fromJson({
                  'id': 'new-deposit',
                  'type': 'deposit',
                  'currency': 'EUR',
                  'amount': 2,
                  'status': 'completed',
                })
              ];
      }),
      banking.dashboardProvider.overrideWith((ref) async {
        dashboardCalls++;
        return DashboardSnapshot(
          profile: UserProfile.fromJson(const {'name': 'Customer'}),
          accounts: const [],
          cards: const [],
          onboarding: const [],
          transactions: dashboardCalls == 1
              ? []
              : [
                  LedgerTransaction.fromJson({
                    'id': 'new-deposit',
                    'type': 'deposit',
                    'currency': 'EUR',
                    'amount': 2,
                    'status': 'completed',
                  })
                ],
        );
      }),
      portfolioEstimateProvider.overrideWith((ref) async {
        portfolioCalls++;
        return PortfolioEstimate.fromJson(
            {'currency': 'USD', 'total': portfolioCalls == 1 ? 100 : 102.32});
      }),
      banking.accountsProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => const []),
      userAssetsProvider.overrideWith((ref) async => const []),
      userWalletsProvider.overrideWith((ref) async => const []),
      mobileTenantConfigProvider
          .overrideWith((ref) async => _tenantConfig(exchangeEnabled: false)),
    ]);
    addTearDown(container.dispose);
    expect((await container.read(hoppaDashboardProvider.future)).activities,
        isEmpty);
    expect(await container.read(banking.activityTransactionsProvider.future),
        isEmpty);
    final refresh = container.read(refreshHoppaDashboardProvider);
    final firstRefresh = refresh();
    expect(identical(refresh(), firstRefresh), isTrue,
        reason: 'Navigation and pull-to-refresh share an in-flight request.');
    await firstRefresh;
    final updated = await container.read(hoppaDashboardProvider.future);
    expect(updated.activities.single.id, 'new-deposit');
    expect(updated.portfolioEstimate!.total, 102.32);
    expect(dashboardCalls, 2);
    expect(portfolioCalls, 2);
    expect(
        (await container.read(banking.activityTransactionsProvider.future))
            .single
            .id,
        'new-deposit');
    expect(historyCalls, 2);
  });

  test('Home starts every independent source before the profile answers',
      () async {
    final started = <String>[];
    final bankingSnapshot = Completer<DashboardSnapshot>();
    final container = ProviderContainer(overrides: [
      banking.dashboardProvider.overrideWith((ref) {
        started.add('dashboard');
        return bankingSnapshot.future;
      }),
      banking.accountsProvider.overrideWith((ref) async {
        started.add('accounts');
        return const [];
      }),
      mobileTenantConfigProvider.overrideWith((ref) async {
        started.add('config');
        return _tenantConfig(exchangeEnabled: false);
      }),
      budgetsProvider.overrideWith((ref) async {
        started.add('budgets');
        return const [];
      }),
      portfolioEstimateProvider.overrideWith((ref) async {
        started.add('portfolio');
        return PortfolioEstimate.fromJson({'currency': 'USD', 'total': 1});
      }),
      userAssetsProvider.overrideWith((ref) async => const []),
      userWalletsProvider.overrideWith((ref) async => const []),
    ]);
    addTearDown(container.dispose);

    final pending = container.read(hoppaDashboardProvider.future);

    expect(
      started,
      unorderedEquals(
          ['dashboard', 'accounts', 'config', 'budgets', 'portfolio']),
      reason: 'Sources that need no other response must not wait for one.',
    );

    bankingSnapshot.complete(DashboardSnapshot(
      profile: UserProfile.fromJson(const {'name': 'Customer'}),
      accounts: const [],
      cards: const [],
      transactions: const [],
      onboarding: const [],
    ));
    expect((await pending).portfolioEstimate!.total, 1);
  });

  test('recent activity preserves API identity and only displays actual dates',
      () async {
    final dated = LedgerTransaction.fromJson({
      'id': 'card-row',
      'cardId': 'card-owned',
      'accountId': 'account-owned',
      'amount': -12.34,
      'currency': 'EUR',
      'type': 'card_payment',
      'bookedAt': '2026-09-06T09:15:00Z',
    });
    final undated = LedgerTransaction.fromJson({
      'id': 'undated-row',
      'budgetId': 'budget-owned',
      'amount': 4,
      'currency': 'USD',
      'type': 'deposit',
    });
    final container = ProviderContainer(overrides: [
      banking.dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
            profile: UserProfile.fromJson(const {'name': 'Customer'}),
            accounts: const [],
            cards: const [],
            transactions: [dated, undated],
            onboarding: const [],
          )),
      banking.accountsProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => const []),
      userAssetsProvider.overrideWith((ref) async => const []),
      userWalletsProvider.overrideWith((ref) async => const []),
      mobileTenantConfigProvider.overrideWith(
        (ref) async => _tenantConfig(exchangeEnabled: false),
      ),
    ]);
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);
    final datedPreview =
        snapshot.activities.singleWhere((row) => row.id == dated.id);
    expect(datedPreview.transaction, same(dated));
    expect(datedPreview.timeLabel,
        DateFormat('d MMM yyyy · HH:mm').format(dated.bookedAt.toLocal()));
    final undatedPreview =
        snapshot.activities.singleWhere((row) => row.id == undated.id);
    expect(undatedPreview.transaction, same(undated));
    expect(undatedPreview.bookedAt, isNull);
    expect(undatedPreview.timeLabel, 'Date unavailable');
  });

  test('shows KYC dashboard when platform resources are unavailable', () async {
    final container = ProviderContainer(
      overrides: [
        banking.dashboardProvider.overrideWith((ref) async {
          return DashboardSnapshot(
            profile: UserProfile.fromJson(const {
              'name': 'Fresh User',
              'kycStatus': 'not_started',
            }),
            accounts: const [],
            cards: const [],
            transactions: const [],
            onboarding: const [],
          );
        }),
        banking.accountsProvider.overrideWith((ref) async => const []),
        budgetsProvider.overrideWith((ref) async => const []),
        mobileTenantConfigProvider.overrideWith(
          (ref) async => _tenantConfig(exchangeEnabled: false),
        ),
        userAssetsProvider.overrideWith((ref) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/api/v1/mobile/assets'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/api/v1/mobile/assets'),
              statusCode: 401,
            ),
          );
        }),
        userWalletsProvider.overrideWith((ref) async {
          throw DioException(
            requestOptions: RequestOptions(path: '/api/v1/mobile/wallets'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/api/v1/mobile/wallets'),
              statusCode: 500,
            ),
          );
        }),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);

    expect(snapshot.customerName, 'Fresh User');
    expect(snapshot.requiresKyc, isTrue);
    expect(snapshot.accounts, isEmpty);
    expect(snapshot.holdings, isEmpty);
  });

  test('keeps EqualsMoney, Interlace and BoomFi balances distinct', () async {
    final container = ProviderContainer(
      overrides: [
        banking.dashboardProvider.overrideWith((ref) async {
          return DashboardSnapshot(
            profile: UserProfile.fromJson(const {
              'name': 'Connected User',
              'kycStatus': 'approved',
              'onboardingStatus': 'active',
            }),
            accounts: const [],
            cards: const [],
            transactions: const [],
            onboarding: const [],
          );
        }),
        banking.accountsProvider.overrideWith(
          (ref) async => const [
            AccountBalance(
              id: 'equals-1',
              name: 'Main account',
              iban: 'GB00TEST00000001',
              balance: Money(currency: 'GBP', minorUnits: 0),
              available: Money(currency: 'GBP', minorUnits: 0),
              provider: 'EqualsMoney',
              status: 'active',
            ),
          ],
        ),
        userAssetsProvider.overrideWith(
          (ref) async => const [
            PlatformResource(
              id: 'interlace-1',
              title: 'USDC',
              subtitle: '',
              metadata: {
                'currency': 'USDC',
                'amount': 50,
                'provider': 'Interlace',
              },
            ),
          ],
        ),
        userWalletsProvider.overrideWith((ref) async => const []),
        equalsBankingInfoProvider.overrideWith((ref) async => const []),
        budgetsProvider.overrideWith(
          (ref) async => const [
            PlatformResource(
              id: 'equals-budget-1',
              title: 'Account balance',
              subtitle: '',
              metadata: {
                'currency': 'GBP',
                'balance': 100,
                'provider': 'EqualsMoney',
              },
            ),
            PlatformResource(
              id: 'equals-budget-2',
              title: 'Account balance',
              subtitle: '',
              metadata: {
                'currency': 'GBP',
                'balance': 280,
                'provider': 'EqualsMoney',
              },
            ),
          ],
        ),
        mobileTenantConfigProvider.overrideWith(
          (ref) async => _tenantConfig(exchangeEnabled: true),
        ),
        exchangeOverviewProvider.overrideWith(
          (ref) async => const BoomFiExchangeOverview(
            accountId: 7,
            accountName: 'Exchange',
            accountEnabled: true,
            accountState: 'active',
            balances: [
              BoomFiExchangeBalance(
                accountId: 7,
                currency: 'USD',
                amount: 27.08,
                pendingAmount: 0,
                chainId: 0,
                chainName: '',
                tokenAddress: '',
              ),
            ],
            settlementAccounts: [],
            subAccounts: [],
            fiatFundingCurrencies: [],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);

    expect(
      snapshot.accounts.map((account) => account.provider).toSet(),
      {'EqualsMoney', 'Interlace', 'BoomFi'},
    );
    expect(
      snapshot.accounts
          .singleWhere((account) => account.provider == 'EqualsMoney')
          .balance,
      380,
    );
  });

  test('business dashboard exposes Equals Money only and keeps exchange',
      () async {
    final container = ProviderContainer(
      overrides: [
        banking.dashboardProvider.overrideWith((ref) async {
          return DashboardSnapshot(
            profile: UserProfile.fromJson(const {
              'name': 'Business Owner',
              'accountType': 'business',
              'kycStatus': 'approved',
              'onboardingStatus': 'active',
            }),
            accounts: const [],
            cards: const [],
            transactions: const [],
            onboarding: const [],
          );
        }),
        banking.accountsProvider.overrideWith(
          (ref) async => const [
            AccountBalance(
              id: 'interlace-1',
              name: 'Crypto card',
              iban: '',
              balance: Money(currency: 'USD', minorUnits: 1000),
              available: Money(currency: 'USD', minorUnits: 1000),
              provider: 'Interlace',
              status: 'active',
            ),
          ],
        ),
        userAssetsProvider.overrideWith(
          (ref) => throw StateError('business must not load crypto assets'),
        ),
        userWalletsProvider.overrideWith(
          (ref) => throw StateError('business must not load crypto wallets'),
        ),
        equalsBankingInfoProvider.overrideWith((ref) async => const []),
        budgetsProvider.overrideWith(
          (ref) async => const [
            PlatformResource(
              id: 'budget-1',
              title: 'Operating budget',
              subtitle: '',
              metadata: {
                'currency': 'GBP',
                'balance': 250,
                'provider': 'EqualsMoney',
              },
            ),
          ],
        ),
        mobileTenantConfigProvider.overrideWith(
          (ref) async => _tenantConfig(exchangeEnabled: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);

    expect(snapshot.isBusinessAccount, isTrue);
    expect(snapshot.accounts.map((item) => item.provider).toSet(),
        {'EqualsMoney'});
    expect(snapshot.holdings, isEmpty);
    expect(snapshot.cards, isEmpty);
    expect(snapshot.exchangeEnabled, isTrue);
    expect(snapshot.outflowsEnabled, isTrue);
  });

  test('keeps EUR and RON amounts distinct with their real shared budget',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'synthetic-display-row',
          title: 'Operating account',
          subtitle: '',
          metadata: {
            'budgetId': 'real-budget',
            'provider': 'EqualsMoney',
            'balances': [
              {'currency': 'EUR', 'availableBalance': 42.75},
              {'currency': 'RON', 'availableBalance': 210.50},
            ],
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'receiving-row',
          title: 'Receiving account',
          subtitle: '',
          metadata: {
            'budgetId': 'real-budget',
            'iban': 'BE68 5390 0754 1234',
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);
    final eur = snapshot.accounts.singleWhere((item) => item.currency == 'EUR');
    final ron = snapshot.accounts.singleWhere((item) => item.currency == 'RON');

    expect(snapshot.accounts, hasLength(2));
    expect(eur.id, isNot(ron.id));
    expect(eur.balance, 42.75);
    expect(eur.available, 42.75);
    expect(ron.balance, 210.50);
    expect(ron.available, 210.50);
    for (final account in [eur, ron]) {
      expect(account.budgetId, 'real-budget');
      expect(account.iban, 'BE68539007541234');
      expect(account.maskedIban, 'BE***1234');
    }
  });

  test('matches a receiving account by budget rather than list position',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'account-row',
          title: 'Euro account',
          subtitle: '',
          metadata: {
            'budgetId': 'euro-budget',
            'currency': 'EUR',
            'balance': 15,
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'first-receiving-row',
          title: 'Other account',
          subtitle: '',
          metadata: {
            'budgetId': 'other-budget',
            'iban': 'BE68539007541111',
          },
        ),
        PlatformResource(
          id: 'second-receiving-row',
          title: 'Euro receiving account',
          subtitle: '',
          metadata: {
            'budgetId': 'euro-budget',
            'iban': 'BE68539007542222',
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final account =
        (await container.read(hoppaDashboardProvider.future)).accounts.single;

    expect(account.budgetId, 'euro-budget');
    expect(account.iban, 'BE68539007542222');
    expect(account.maskedIban, 'BE***2222');
    expect(account.balance, 15);
  });

  test('shows a matched domestic account number without treating it as an IBAN',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'display-row',
          title: 'Sterling account',
          subtitle: '',
          metadata: {
            'budgetId': 'sterling-budget',
            'currency': 'GBP',
            'balance': 85.25,
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'receiving-row',
          title: 'Domestic receiving account',
          subtitle: '',
          metadata: {
            'budgetId': 'sterling-budget',
            'currency': 'GBP',
            'accountNumber': '12345678',
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final account =
        (await container.read(hoppaDashboardProvider.future)).accounts.single;

    expect(account.budgetId, 'sterling-budget');
    expect(account.balance, 85.25);
    expect(account.accountNumber, '12345678');
    expect(account.iban, isEmpty);
    expect(account.maskedIban, isEmpty);
    expect(account.maskedIdentifier, '***5678');
  });

  test('binds each currency to its own settlement IBAN in a shared budget',
      () async {
    const settlementDetails = {
      'currencyDetails': [
        {
          'currencyCode': 'EUR',
          'international': {'accountIdentifier': 'BE68539007542222'},
        },
        {
          'currencyCode': 'RON',
          'international': {'accountIdentifier': 'RO49AAAA1B31007593843333'},
        },
      ],
    };
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'display-row',
          title: 'Multicurrency account',
          subtitle: '',
          metadata: {
            'budgetId': 'shared-budget',
            'balances': [
              {'currency': 'EUR', 'balance': 15},
              {'currency': 'RON', 'balance': 72.50},
            ],
            'settlementDetails': settlementDetails,
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'settlement-row',
          title: 'Receiving accounts',
          subtitle: '',
          metadata: {
            'budgetId': 'shared-budget',
            'settlementDetails': settlementDetails,
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);
    final eur = snapshot.accounts.singleWhere((item) => item.currency == 'EUR');
    final ron = snapshot.accounts.singleWhere((item) => item.currency == 'RON');

    expect(eur.budgetId, 'shared-budget');
    expect(ron.budgetId, 'shared-budget');
    expect(eur.balance, 15);
    expect(ron.balance, 72.50);
    expect(eur.iban, 'BE68539007542222');
    expect(ron.iban, 'RO49AAAA1B31007593843333');
    expect(eur.maskedIban, 'BE***2222');
    expect(ron.maskedIban, 'RO***3333');
  });

  test('does not attach an unlinked receiving account to a currency total',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'real-budget',
          title: 'Euro account',
          subtitle: '',
          metadata: {
            'budgetId': 'real-budget',
            'currency': 'EUR',
            'balance': 15,
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'receiving-row',
          title: 'Euro account',
          subtitle: '',
          metadata: {
            'currency': 'EUR',
            'iban': 'BE68539007541111',
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final account =
        (await container.read(hoppaDashboardProvider.future)).accounts.single;

    expect(account.budgetId, 'real-budget');
    expect(account.balance, 15);
    expect(account.iban, isEmpty);
    expect(account.maskedIban, isEmpty);
  });

  for (final includesIdentifiedBudget in [false, true]) {
    test(
        includesIdentifiedBudget
            ? 'keeps a mixed identified and unidentified currency total unscoped'
            : 'does not route using a synthesized platform resource ID',
        () async {
      final container = _equalsDashboardContainer(
        budgets: [
          PlatformResource.fromJson(const {
            'title': 'Euro account',
            'currency': 'EUR',
            'balance': 15,
          }),
          if (includesIdentifiedBudget)
            const PlatformResource(
              id: 'display-row',
              title: 'Other Euro account',
              subtitle: '',
              metadata: {
                'budgetId': 'real-budget',
                'currency': 'EUR',
                'balance': 27.50,
              },
            ),
        ],
        bankingInfo: const [
          PlatformResource(
            id: 'receiving-row',
            title: 'Receiving account',
            subtitle: '',
            metadata: {
              'budgetId': 'real-budget',
              'iban': 'BE68539007541111',
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      final account =
          (await container.read(hoppaDashboardProvider.future)).accounts.single;

      expect(account.currency, 'EUR');
      expect(account.balance, includesIdentifiedBudget ? 42.50 : 15);
      expect(account.budgetId, isEmpty);
      expect(account.iban, isEmpty);
    });
  }

  test('retains aggregate balances without a misleading account identity',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'first-row',
          title: 'First account',
          subtitle: '',
          metadata: {
            'budgetId': 'first-budget',
            'currency': 'EUR',
            'balance': 15,
          },
        ),
        PlatformResource(
          id: 'second-row',
          title: 'Second account',
          subtitle: '',
          metadata: {
            'budgetId': 'second-budget',
            'currency': 'EUR',
            'balance': 27.50,
          },
        ),
      ],
      bankingInfo: const [
        PlatformResource(
          id: 'receiving-row',
          title: 'First receiving account',
          subtitle: '',
          metadata: {
            'budgetId': 'first-budget',
            'iban': 'BE68539007541111',
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final account =
        (await container.read(hoppaDashboardProvider.future)).accounts.single;

    expect(account.currency, 'EUR');
    expect(account.balance, 42.50);
    expect(account.available, 42.50);
    expect(account.budgetId, isEmpty);
    expect(account.iban, isEmpty);
    expect(account.maskedIban, isEmpty);
  });

  for (final idKey in ['budgetId', 'BudgetId', 'id', 'Id', 'accountId']) {
    test('uses metadata $idKey instead of a synthetic Home resource ID',
        () async {
      final container = _equalsDashboardContainer(
        budgets: [
          PlatformResource(
            id: 'EqualsMoney:EUR',
            title: idKey == 'accountId' ? 'Account balance' : 'Euro account',
            subtitle: '',
            metadata: {
              idKey: 'api-budget-id',
              'currency': 'EUR',
              'balance': 15
            },
          ),
        ],
      );
      addTearDown(container.dispose);

      final account =
          (await container.read(hoppaDashboardProvider.future)).accounts.single;

      expect(account.budgetId, 'api-budget-id');
      expect(account.balance, 15);
    });
  }

  test('does not collapse named budgets into their shared owner account ID',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'travel-display-row',
          title: 'Travel',
          subtitle: '',
          metadata: {
            'accountId': 'shared-owner',
            'currency': 'EUR',
            'balance': 15,
          },
        ),
        PlatformResource(
          id: 'operations-display-row',
          title: 'Operations',
          subtitle: '',
          metadata: {
            'accountId': 'shared-owner',
            'currency': 'EUR',
            'balance': 27.50,
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final account =
        (await container.read(hoppaDashboardProvider.future)).accounts.single;

    expect(account.balance, 42.50);
    expect(account.budgetId, isEmpty);
    expect(account.accountNumber, isEmpty);
    expect(account.iban, isEmpty);
  });

  test('banking-info failure keeps real Home balances and account routing',
      () async {
    final container = _equalsDashboardContainer(
      budgets: const [
        PlatformResource(
          id: 'display-row',
          title: 'Euro account',
          subtitle: '',
          metadata: {
            'budgetId': 'api-budget-id',
            'currency': 'EUR',
            'balance': 75.25,
          },
        ),
      ],
      bankingInfoError: DioException(
        requestOptions: RequestOptions(path: '/api/v1/mobile/banking-info'),
      ),
    );
    addTearDown(container.dispose);

    final snapshot = await container.read(hoppaDashboardProvider.future);

    expect(snapshot.customerName, 'Connected User');
    expect(snapshot.accounts, hasLength(1));
    final account = snapshot.accounts.single;
    expect(account.currency, 'EUR');
    expect(account.balance, 75.25);
    expect(account.budgetId, 'api-budget-id');
    expect(account.iban, isEmpty);
  });
}

ProviderContainer _equalsDashboardContainer({
  required List<PlatformResource> budgets,
  List<PlatformResource> bankingInfo = const [],
  DioException? bankingInfoError,
}) {
  return ProviderContainer(
    overrides: [
      banking.dashboardProvider.overrideWith(
        (ref) async => DashboardSnapshot(
          profile: UserProfile.fromJson(const {
            'name': 'Connected User',
            'kycStatus': 'approved',
            'onboardingStatus': 'active',
          }),
          accounts: const [],
          cards: const [],
          transactions: const [],
          onboarding: const [],
        ),
      ),
      banking.accountsProvider.overrideWith((ref) async => const []),
      userAssetsProvider.overrideWith((ref) async => const []),
      userWalletsProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => budgets),
      equalsBankingInfoProvider.overrideWith((ref) async {
        if (bankingInfoError != null) throw bankingInfoError;
        return bankingInfo;
      }),
      mobileTenantConfigProvider.overrideWith(
        (ref) async => _tenantConfig(exchangeEnabled: false),
      ),
      portfolioEstimateProvider.overrideWith((ref) async {
        throw DioException(
          requestOptions: RequestOptions(path: '/portfolio-estimate'),
        );
      }),
      marketRatesProvider.overrideWith((ref) async {
        throw DioException(
            requestOptions: RequestOptions(path: '/market-rates'));
      }),
    ],
  );
}

MobileTenantConfig _tenantConfig({required bool exchangeEnabled}) {
  return MobileTenantConfig(
    companyName: 'Test',
    brandName: 'Test',
    referralsEnabled: true,
    referralRegistrationMode: 'optional',
    vouchersEnabled: true,
    existingAccountClaimEnabled: true,
    boomFiExchangeEnabled: exchangeEnabled,
    walletOutflowsEnabled: true,
    equalsMoneyEnabled: true,
  );
}
