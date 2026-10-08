import {
  existsSync,
  readdirSync,
  readFileSync,
  statSync,
} from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../..', import.meta.url));
const hoppaOpenApiPath =
  process.env.HOPPA_OPENAPI_PATH ??
  '/Users/rok/Downloads/cryptocard-platform-api_staging.json';
const failures = [];
const notes = [];

const skipDirectories = new Set([
  '.dart_tool',
  '.git',
  'bin',
  'build',
  'dist',
  'node_modules',
  'obj',
]);

function readProjectFile(file) {
  return readFileSync(join(root, file), 'utf8');
}

function listFiles(relativeDirectory, extensions = null) {
  const directory = join(root, relativeDirectory);
  const results = [];

  if (!existsSync(directory)) {
    failures.push(`Missing directory ${relativeDirectory}`);
    return results;
  }

  function walk(currentDirectory, currentRelativeDirectory) {
    for (const entry of readdirSync(currentDirectory)) {
      if (skipDirectories.has(entry)) {
        continue;
      }

      const absolutePath = join(currentDirectory, entry);
      const relativePath = currentRelativeDirectory
        ? `${currentRelativeDirectory}/${entry}`
        : entry;
      const stat = statSync(absolutePath);

      if (stat.isDirectory()) {
        walk(absolutePath, relativePath);
        continue;
      }

      if (!extensions || extensions.some((extension) => relativePath.endsWith(extension))) {
        results.push(`${relativeDirectory}/${relativePath}`);
      }
    }
  }

  walk(directory, '');
  return results;
}

function expectSnippets(file, snippets) {
  let content = '';

  try {
    content = readProjectFile(file);
  } catch (error) {
    failures.push(`Missing ${file}: ${error.message}`);
    return '';
  }

  for (const snippet of snippets) {
    if (!content.includes(snippet)) {
      failures.push(`${file} does not include ${snippet}`);
    }
  }

  return content;
}

function expectRegex(file, pattern, description) {
  const content = expectSnippets(file, []);
  if (content && !pattern.test(content)) {
    failures.push(`${file} does not match ${description}`);
  }
}

function expectNoPattern(files, pattern, description) {
  for (const file of files) {
    const content = readProjectFile(file);
    if (pattern.test(content)) {
      failures.push(`${file} must not include ${description}`);
    }
  }
}

function loadHoppaOpenApi() {
  if (!existsSync(hoppaOpenApiPath)) {
    notes.push(`Hoppa OpenAPI file not found at ${hoppaOpenApiPath}; used embedded coverage matrix only.`);
    return null;
  }

  const document = JSON.parse(readFileSync(hoppaOpenApiPath, 'utf8'));
  if (!document.paths || typeof document.paths !== 'object') {
    failures.push(`${hoppaOpenApiPath} does not contain an OpenAPI paths object`);
    return null;
  }

  return document;
}

function expectHoppaOperations(openApi, groups) {
  if (!openApi) {
    return;
  }

  for (const group of groups) {
    for (const operation of group.operations) {
      const methods = openApi.paths[operation.path];
      if (!methods) {
        failures.push(`Hoppa OpenAPI is missing ${group.area}: ${operation.method} ${operation.path}`);
        continue;
      }

      if (!methods[operation.method.toLowerCase()]) {
        failures.push(`Hoppa OpenAPI is missing method for ${group.area}: ${operation.method} ${operation.path}`);
      }
    }
  }
}

function operationKey(operation) {
  return `${operation.method.toUpperCase()} ${operation.path}`;
}

function expectOperationsIncluded(actualOperations, expectedOperations, description) {
  const actual = new Set(actualOperations.map(operationKey));

  for (const operation of expectedOperations) {
    const key = operationKey(operation);
    if (!actual.has(key)) {
      failures.push(`${description} is missing ${key}`);
    }
  }
}

function extractVueSourceOperations(file) {
  const content = readProjectFile(file);
  const operations = [];
  const operationPattern = /\{\s*method:\s*'([A-Z]+)',\s*path:\s*'([^']+)'\s*\}/g;
  let match = operationPattern.exec(content);

  while (match) {
    operations.push({ method: match[1], path: match[2] });
    match = operationPattern.exec(content);
  }

  return operations;
}

function extractAdminResourceKeys(file) {
  const content = readProjectFile(file);
  const match = content.match(/export type AdminResourceKey =([\s\S]*?);/);

  if (!match) {
    failures.push(`${file} is missing AdminResourceKey`);
    return new Set();
  }

  return new Set(
    Array.from(match[1].matchAll(/\|\s*'([^']+)'/g)).map((entry) => entry[1]),
  );
}

function extractAdminRouteBlocks(file) {
  const content = readProjectFile(file);
  const routePattern = /\{\s*path:\s*'([^']+)'([\s\S]*?)\n    \},/g;
  const routes = [];
  let match = routePattern.exec(content);

  while (match) {
    routes.push({ path: match[1], block: match[0] });
    match = routePattern.exec(content);
  }

  return routes;
}

function expectAdminVueRoutesGuarded() {
  const routerFile = 'admin_vue/src/router/index.ts';
  const resourcesFile = 'admin_vue/src/lib/adminResources.ts';
  const routes = extractAdminRouteBlocks(routerFile);
  const resourceKeys = extractAdminResourceKeys(resourcesFile);
  const guardedPaths = new Set();
  const routedResourceKeys = new Set();
  const routeByPath = new Map(routes.map((route) => [route.path, route.block]));
  const navTargets = Array.from(
    readProjectFile(resourcesFile).matchAll(/to:\s*'([^']+)'/g),
  ).map((match) => match[1]);

  if (routes.length === 0) {
    failures.push(`${routerFile} does not expose parseable route definitions`);
  }

  for (const route of routes) {
    const isLoginRoute = route.path === '/login';
    const isCatchAllRoute = route.path.includes(':pathMatch');
    const isRedirectOnly = /\bredirect:\s*'[^']+'/.test(route.block);

    if (isLoginRoute || isCatchAllRoute || isRedirectOnly) {
      continue;
    }

    const hasAdminMeta =
      /meta:\s*adminMeta/.test(route.block) ||
      /meta:\s*\{\s*\.\.\.adminMeta/.test(route.block);

    if (!hasAdminMeta) {
      failures.push(`${routerFile} route ${route.path} is missing adminMeta protection`);
    }

    guardedPaths.add(route.path);

    const resourceKey = route.block.match(/resourceKey:\s*'([^']+)'/)?.[1];
    if (resourceKey) {
      if (!resourceKeys.has(resourceKey)) {
        failures.push(`${routerFile} route ${route.path} references unknown resourceKey ${resourceKey}`);
      }

      routedResourceKeys.add(resourceKey);
    }
  }

  for (const key of resourceKeys) {
    if (!routedResourceKeys.has(key) && key !== 'support') {
      failures.push(`${routerFile} does not route AdminResourceKey ${key}`);
    }
  }

  for (const target of navTargets) {
    const targetRoute = routeByPath.get(target);
    const isGuardedTarget = guardedPaths.has(target);
    const redirectsToGuardedRoute =
      targetRoute &&
      /redirect:\s*'([^']+)'/.test(targetRoute) &&
      guardedPaths.has(targetRoute.match(/redirect:\s*'([^']+)'/)?.[1] ?? '');

    if (!isGuardedTarget && !redirectsToGuardedRoute) {
      failures.push(`${resourcesFile} nav target ${target} does not resolve to a guarded admin route`);
    }
  }
}

function expectVueSourceOperationsMatchOpenApi(openApi, file) {
  if (!openApi) {
    return;
  }

  for (const operation of extractVueSourceOperations(file)) {
    const methods = openApi.paths[operation.path];
    if (!methods) {
      failures.push(`${file} source operation is not in Hoppa OpenAPI: ${operation.method} ${operation.path}`);
      continue;
    }

    if (!methods[operation.method.toLowerCase()]) {
      failures.push(`${file} source operation uses unsupported method: ${operation.method} ${operation.path}`);
    }
  }
}

const hoppaCoverageGroups = [
  {
    area: 'auth and user profile',
    operations: [
      { method: 'POST', path: '/Users/Authenticate' },
      { method: 'POST', path: '/Users/RefreshToken' },
      { method: 'GET', path: '/Users/Me' },
      { method: 'GET', path: '/api/v2/users' },
      { method: 'GET', path: '/api/v2/users/{userId}' },
      { method: 'PUT', path: '/api/v2/users/{userId}' },
    ],
  },
  {
    area: 'onboarding and KYB',
    operations: [
      { method: 'POST', path: '/api/v2/banking/equalsmoney-onboarding' },
      { method: 'GET', path: '/api/v2/banking/users/{userId}/equals-banking-info' },
      { method: 'GET', path: '/api/v2/banking/providers' },
      { method: 'GET', path: '/api/v2/business/onboarding/options' },
      { method: 'GET', path: '/api/v2/business/onboarding/application' },
      { method: 'POST', path: '/api/v2/business/onboarding/application' },
      { method: 'POST', path: '/api/v2/business/onboarding/application/submit' },
      { method: 'POST', path: '/api/v2/business/onboarding/application/documents' },
      { method: 'GET', path: '/api/v2/business/onboarding/associated-people' },
      { method: 'POST', path: '/api/v2/business/onboarding/associated-people' },
      { method: 'POST', path: '/api/v2/business/onboarding/associated-people/{associatedPersonId}/documents' },
    ],
  },
  {
    area: 'KYC and SumSub',
    operations: [
      { method: 'POST', path: '/api/v2/users/{userId}/kyc/verify' },
      { method: 'PUT', path: '/api/v2/users/{userId}/kyc/sumsub-token' },
      { method: 'POST', path: '/api/v2/users/{userId}/kyc/sumsub-access-token' },
      { method: 'GET', path: '/api/v2/users/{userId}/kyc/detailed-status' },
      { method: 'POST', path: '/api/v2/users/{userId}/sumsub/kyc-url' },
    ],
  },
  {
    area: 'accounts, balances, budgets, payees, and banking transfers',
    operations: [
      { method: 'GET', path: '/api/v2/banking/accounts' },
      { method: 'GET', path: '/api/v2/banking/balance' },
      { method: 'GET', path: '/api/v2/banking/transactions' },
      { method: 'GET', path: '/api/v2/banking/users/{userId}/budgets' },
      { method: 'POST', path: '/api/v2/banking/users/{userId}/budgets' },
      { method: 'GET', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}' },
      { method: 'PUT', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}' },
      { method: 'POST', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}/transfer' },
      { method: 'POST', path: '/api/v2/banking/budgets/{budgetId}/transfer' },
      { method: 'GET', path: '/api/v2/banking/payees' },
      { method: 'POST', path: '/api/v2/banking/payees' },
      { method: 'GET', path: '/api/v2/banking/payees/required-fields' },
      { method: 'DELETE', path: '/api/v2/banking/payees/{payeeId}' },
      { method: 'POST', path: '/api/v2/banking/transfers' },
      { method: 'POST', path: '/api/v2/banking/transfers/internal' },
      { method: 'POST', path: '/api/v2/banking/quotes' },
      { method: 'POST', path: '/api/v2/banking/orders/quote' },
      { method: 'POST', path: '/api/v2/banking/orders/trade' },
    ],
  },
  {
    area: 'tiers and card lifecycle',
    operations: [
      { method: 'GET', path: '/api/v2/tiers' },
      { method: 'GET', path: '/api/v2/tiers/card-tier/{cardTierId}' },
      { method: 'GET', path: '/api/v2/cards/quantum-topup/estimate' },
      { method: 'GET', path: '/api/v2/cards' },
      { method: 'POST', path: '/api/v2/cards' },
      { method: 'GET', path: '/api/v2/cards/cardHolders' },
      { method: 'GET', path: '/api/v2/cards/{cardId}' },
      { method: 'POST', path: '/api/v2/cards/{cardId}/activate' },
      { method: 'POST', path: '/api/v2/cards/{cardId}/freeze' },
      { method: 'POST', path: '/api/v2/cards/{cardId}/enable' },
      { method: 'GET', path: '/api/v2/cards/{cardId}/transactions' },
      { method: 'PUT', path: '/api/v2/cards/{cardId}/limits' },
      { method: 'PUT', path: '/api/v2/cards/{cardId}/pin' },
      { method: 'POST', path: '/api/v2/cards/topup' },
      { method: 'POST', path: '/api/v2/cards/unload-card' },
      { method: 'GET', path: '/api/v2/cards/{cardId}/widget' },
    ],
  },
  {
    area: 'payments, wallets, assets, transactions, export, and sync',
    operations: [
      { method: 'POST', path: '/api/v2/payments/create' },
      { method: 'GET', path: '/api/v2/payments/mandates' },
      { method: 'POST', path: '/api/v2/payments/mandates' },
      { method: 'GET', path: '/api/v2/payments/mandates/{mandateId}' },
      { method: 'PUT', path: '/api/v2/payments/mandates/{mandateId}/revoke' },
      { method: 'GET', path: '/api/v2/payments/requests' },
      { method: 'POST', path: '/api/v2/payments/requests' },
      { method: 'GET', path: '/api/v2/payments/requests/{requestId}' },
      { method: 'PUT', path: '/api/v2/payments/requests/{requestId}/cancel' },
      { method: 'POST', path: '/api/v2/payments/payouts' },
      { method: 'POST', path: '/api/v2/payments/withdrawals/fee' },
      { method: 'POST', path: '/api/v2/payments/withdrawals' },
      { method: 'GET', path: '/api/v2/payments/assets/co-brand' },
      { method: 'GET', path: '/api/v2/users/{userId}/wallets' },
      { method: 'GET', path: '/api/v2/users/{userId}/assets' },
      { method: 'GET', path: '/api/v2/users/{userId}/crypto-addresses' },
      { method: 'GET', path: '/api/v2/transfers/withdrawals/available-balance' },
      { method: 'GET', path: '/api/v2/transfers/withdrawals/fee-and-quota' },
      { method: 'GET', path: '/api/v2/transfers/withdrawals/validate' },
      { method: 'POST', path: '/api/v2/transfers/wallet-topup' },
      { method: 'POST', path: '/api/v2/transfers/crypto-to-quantum-transfer' },
      { method: 'POST', path: '/api/v2/transfers/quantum-usd-to-crypto-exchange' },
      { method: 'POST', path: '/api/v2/transfers/withdrawals/crypto' },
      { method: 'POST', path: '/api/v2/transfers/withdrawals/crypto/confirm' },
      { method: 'GET', path: '/api/v2/transfers/crypto-transactions' },
      { method: 'GET', path: '/api/v2/transfers/crypto-refunds' },
      { method: 'POST', path: '/api/v2/transfers/crypto-refunds' },
      { method: 'POST', path: '/api/v2/transfers/crypto-refunds/gas-fee' },
      { method: 'GET', path: '/api/v2/transactions' },
      { method: 'GET', path: '/api/v2/transactions/{id}' },
      { method: 'POST', path: '/api/v2/transactions/sync' },
      { method: 'GET', path: '/api/v2/transactions/export' },
      { method: 'GET', path: '/api/v2/transactions/stats' },
      { method: 'POST', path: '/api/v2/transactions/top-up' },
      { method: 'GET', path: '/api/v2/whitelabel/transactions' },
      { method: 'POST', path: '/api/v2/whitelabel/transactions/sync' },
      { method: 'GET', path: '/api/v2/whitelabel/transactions/export' },
    ],
  },
  {
    area: 'audit, webhooks, support, and admin settings',
    operations: [
      { method: 'POST', path: '/api/v2/admin/support/messages/report-transaction' },
      { method: 'POST', path: '/webhooks/outbound/user.registered' },
      { method: 'POST', path: '/webhooks/outbound/user.kyc.updated' },
      { method: 'POST', path: '/webhooks/outbound/payment.completed' },
      { method: 'POST', path: '/webhooks/outbound/card.state_updated' },
      { method: 'POST', path: '/webhooks/outbound/wallet.withdrawal' },
    ],
  },
];

const fullFlowBackendExpectations = [
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileKycController.cs',
    snippets: [
      '[HttpGet("detailed-status")]',
      '[HttpPost("verify")]',
      '[HttpPost("url")]',
      '/kyc/detailed-status',
      '/kyc/verify',
      '/sumsub/kyc-url',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileBusinessOnboardingController.cs',
    snippets: [
      '[HttpGet("options")]',
      '[HttpGet("application")]',
      '[HttpPost("application")]',
      '[HttpPost("application/submit")]',
      '[HttpPost("application/documents")]',
      '[HttpGet("associated-people")]',
      '[HttpPost("associated-people")]',
      '[HttpPost("associated-people/{associatedPersonId}/documents")]',
      '/api/v2/business/onboarding',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileBankingController.cs',
    snippets: [
      '[HttpPost("equalsmoney-onboarding")]',
      '[HttpGet("equals-banking-info")]',
      '[HttpGet("providers")]',
      '[HttpGet("balance")]',
      '[HttpGet("budgets/{budgetId}")]',
      '[HttpPatch("budgets/{budgetId}")]',
      '[HttpPost("budgets/{budgetId}/transfer")]',
      '[HttpGet("payees/required-fields")]',
      '[HttpPost("transfers/internal")]',
      '[HttpPost("quotes")]',
      '[HttpPost("orders/quote")]',
      '[HttpPost("orders/trade")]',
      'banking/equalsmoney-onboarding',
      'equals-banking-info',
      'banking/providers',
      'budgets/{Segment(budgetId)}/transfer',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileTiersController.cs',
    snippets: ['[HttpGet("card-tier/{cardTierId}")]', '/api/v2/tiers/card-tier/'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileCardsController.cs',
    snippets: [
      '[HttpPost("{cardId}/enable")]',
      '[HttpPost("topup")]',
      '[HttpPost("unload")]',
      '[HttpGet("{cardId}/widget")]',
      '[HttpGet("{cardId}/transactions")]',
      'CardLifecycleAction(cardId, "enable"',
      'cards/topup',
      'cards/unload-card',
      'cards/{Segment(cardId)}/widget',
      'cards/{Segment(cardId)}/transactions',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobilePaymentsController.cs',
    snippets: [
      '[HttpPost("create")]',
      '[HttpGet("mandates")]',
      '[HttpPost("mandates")]',
      '[HttpGet("mandates/{mandateId}")]',
      '[HttpPut("mandates/{mandateId}/revoke")]',
      '[HttpGet("requests")]',
      '[HttpPost("requests")]',
      '[HttpGet("requests/{requestId}")]',
      '[HttpPut("requests/{requestId}/cancel")]',
      '[HttpPost("payouts")]',
      '[HttpPost("withdrawals")]',
      '[HttpPost("withdrawals/fee")]',
      'payments/create',
      'payments/mandates',
      'payments/requests',
      'payments/payouts',
      'payments/withdrawals',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileTransactionsController.cs',
    snippets: [
      '[HttpGet("export")]',
      '[HttpGet("stats")]',
      '[HttpPost("sync")]',
      '/api/v2/transactions/export',
      '/api/v2/transactions/stats',
      '/api/v2/transactions/sync',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileBankingController.cs',
    snippets: [
      '[HttpGet("wallets")]',
      '[HttpGet("assets")]',
      '[HttpGet("crypto-addresses")]',
      '[HttpGet("transfers/withdrawals/available-balance")]',
      '[HttpPost("transfers/wallet-topup")]',
      '[HttpPost("transfers/crypto-to-quantum-transfer")]',
      '[HttpPost("transfers/quantum-usd-to-crypto-exchange")]',
      '[HttpPost("transfers/withdrawals/crypto")]',
      'wallets',
      'assets',
      'crypto-addresses',
    ],
  },
];

const fullFlowFlutterExpectations = [
  {
    file: 'mobile_flutter/lib/features/platform/data/mobile_platform_api.dart',
    snippets: [
      '/api/v1/mobile/kyc/status',
      '/api/v1/mobile/kyc/verify',
      '/api/v1/mobile/kyc/url',
      'ProofOfAddress',
      'RequestedFeatures',
      '/api/v1/mobile/banking/equals-banking-info',
      '/api/v1/mobile/banking/providers',
      '/api/v1/mobile/banking/budgets',
      '/api/v1/mobile/banking/budgets/$fromBudgetId/transfer',
      'updateBudget',
      '/api/v1/mobile/tiers',
      '/api/v1/mobile/tiers/current',
      'selectTier',
      'card-tier',
      '/api/v1/mobile/cards/$cardId',
      '/api/v1/mobile/cards/$cardId/enable',
      '/api/v1/mobile/cards/$cardId/activate',
      '/api/v1/mobile/cards/$cardId/cancel',
      '/api/v1/mobile/cards/$cardId/load',
      '/api/v1/mobile/cards/$cardId/unload',
      '/api/v1/mobile/cards/$cardId/widget/secret-data',
      '/api/v1/mobile/cards/$cardId/transactions',
      '/api/v1/mobile/payments',
      '/api/v1/mobile/payments/mandates',
      '/api/v1/mobile/payments/mandates/$mandateId/revoke',
      '/api/v1/mobile/payments/requests',
      '/api/v1/mobile/payments/requests/$requestId/cancel',
      '/api/v1/mobile/payments/payouts',
      '/api/v1/mobile/payments/withdrawals',
      '/api/v1/mobile/payments/withdrawals/fee',
      '/api/v1/mobile/wallets',
      '/api/v1/mobile/assets',
      '/api/v1/mobile/crypto-addresses',
      '/api/v1/mobile/banking/accounts',
      '/api/v1/mobile/transfers/wallet-topup',
      '/api/v1/mobile/transfers/crypto-to-quantum-transfer',
      '/api/v1/mobile/transfers/quantum-usd-to-crypto-exchange',
      '/api/v1/mobile/transfers/withdrawals/crypto',
      '/api/v1/mobile/transactions/export',
      '/api/v1/mobile/transactions/stats',
      '/api/v1/mobile/transactions/sync',
    ],
  },
  {
    file: 'mobile_flutter/lib/features/banking/data/mobile_banking_api.dart',
    snippets: [
      '/api/v1/mobile/cards',
      '/api/v1/mobile/cards/$cardId/load',
      '/api/v1/mobile/cards/$cardId/${freeze ? \'freeze\' : \'unfreeze\'}',
      '/api/v1/mobile/banking/payees',
      '/api/v1/mobile/banking/transfers',
      '/api/v1/mobile/payments',
      '/api/v1/mobile/business-onboarding/profile',
      'topUpCard',
      'loadCard',
    ],
  },
  {
    file: 'mobile_flutter/lib/features/platform/application/platform_providers.dart',
    snippets: [
      'cryptoAddressesProvider',
      'transactionStatsProvider',
      'ref.invalidate(cryptoAddressesProvider)',
      'ref.invalidate(transactionStatsProvider)',
    ],
  },
];

const fullFlowVueExpectations = [
  {
    file: 'admin_vue/src/lib/adminResources.ts',
    snippets: [
      "'providers'",
      "'budgets'",
      "'cardTiers'",
      "'balances'",
      "'payees'",
      "'bankingTransfers'",
      "'mandates'",
      "'paymentRequests'",
      "'payouts'",
      "'withdrawals'",
      "'transactionStats'",
      "endpoint: '/api/v1/admin/hoppa/banking/providers'",
      "endpoint: '/api/v1/admin/hoppa/banking/budgets'",
      "endpoint: '/api/v1/admin/hoppa/tiers/card-tiers'",
      "endpoint: '/api/v1/admin/hoppa/cards'",
      "endpoint: '/api/v1/admin/hoppa/banking/balances'",
      "endpoint: '/api/v1/admin/hoppa/banking/payees'",
      "endpoint: '/api/v1/admin/hoppa/banking/transfers'",
      "endpoint: '/api/v1/admin/hoppa/payments/mandates'",
      "endpoint: '/api/v1/admin/hoppa/payments/requests'",
      "endpoint: '/api/v1/admin/hoppa/payments/payouts'",
      "endpoint: '/api/v1/admin/hoppa/withdrawals'",
      "endpoint: '/api/v1/admin/hoppa/transactions/stats'",
      "exportEndpoint: '/api/v1/admin/hoppa/transactions/export'",
    ],
  },
];

const requiredVueSourceOperations = [
  { method: 'POST', path: '/api/v2/banking/equalsmoney-onboarding' },
  { method: 'GET', path: '/api/v2/banking/users/{userId}/equals-banking-info' },
  { method: 'GET', path: '/api/v2/banking/providers' },
  { method: 'GET', path: '/api/v2/banking/users/{userId}/budgets' },
  { method: 'POST', path: '/api/v2/banking/users/{userId}/budgets' },
  { method: 'GET', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}' },
  { method: 'PUT', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}' },
  { method: 'POST', path: '/api/v2/banking/users/{userId}/budgets/{budgetId}/transfer' },
  { method: 'POST', path: '/api/v2/banking/budgets/{budgetId}/transfer' },
  { method: 'GET', path: '/api/v2/tiers' },
  { method: 'GET', path: '/api/v2/tiers/card-tier/{cardTierId}' },
  { method: 'GET', path: '/api/v2/cards' },
  { method: 'POST', path: '/api/v2/cards' },
  { method: 'GET', path: '/api/v2/cards/cardHolders' },
  { method: 'GET', path: '/api/v2/cards/{cardId}' },
  { method: 'POST', path: '/api/v2/cards/{cardId}/activate' },
  { method: 'POST', path: '/api/v2/cards/{cardId}/freeze' },
  { method: 'POST', path: '/api/v2/cards/{cardId}/enable' },
  { method: 'GET', path: '/api/v2/cards/{cardId}/transactions' },
  { method: 'POST', path: '/api/v2/cards/topup' },
  { method: 'POST', path: '/api/v2/cards/unload-card' },
  { method: 'GET', path: '/api/v2/cards/{cardId}/widget' },
  { method: 'GET', path: '/api/v2/banking/balance' },
  { method: 'GET', path: '/api/v2/users/{userId}/wallets' },
  { method: 'GET', path: '/api/v2/users/{userId}/assets' },
  { method: 'GET', path: '/api/v2/users/{userId}/crypto-addresses' },
  { method: 'POST', path: '/api/v2/payments/create' },
  { method: 'GET', path: '/api/v2/payments/mandates' },
  { method: 'POST', path: '/api/v2/payments/mandates' },
  { method: 'GET', path: '/api/v2/payments/mandates/{mandateId}' },
  { method: 'PUT', path: '/api/v2/payments/mandates/{mandateId}/revoke' },
  { method: 'GET', path: '/api/v2/payments/requests' },
  { method: 'POST', path: '/api/v2/payments/requests' },
  { method: 'GET', path: '/api/v2/payments/requests/{requestId}' },
  { method: 'PUT', path: '/api/v2/payments/requests/{requestId}/cancel' },
  { method: 'POST', path: '/api/v2/payments/payouts' },
  { method: 'POST', path: '/api/v2/payments/withdrawals/fee' },
  { method: 'POST', path: '/api/v2/payments/withdrawals' },
  { method: 'GET', path: '/api/v2/transfers/withdrawals/available-balance' },
  { method: 'GET', path: '/api/v2/transfers/withdrawals/fee-and-quota' },
  { method: 'GET', path: '/api/v2/transfers/withdrawals/validate' },
  { method: 'POST', path: '/api/v2/transfers/wallet-topup' },
  { method: 'POST', path: '/api/v2/transfers/crypto-to-quantum-transfer' },
  { method: 'POST', path: '/api/v2/transfers/quantum-usd-to-crypto-exchange' },
  { method: 'POST', path: '/api/v2/transfers/withdrawals/crypto' },
  { method: 'POST', path: '/api/v2/transfers/withdrawals/crypto/confirm' },
  { method: 'GET', path: '/api/v2/transfers/crypto-transactions' },
  { method: 'GET', path: '/api/v2/transfers/crypto-refunds' },
  { method: 'POST', path: '/api/v2/transfers/crypto-refunds' },
  { method: 'POST', path: '/api/v2/transfers/crypto-refunds/gas-fee' },
  { method: 'GET', path: '/api/v2/transactions' },
  { method: 'GET', path: '/api/v2/transactions/{id}' },
  { method: 'GET', path: '/api/v2/transactions/export' },
  { method: 'GET', path: '/api/v2/transactions/stats' },
  { method: 'POST', path: '/api/v2/transactions/sync' },
];

const scaffoldExpectations = [
  {
    file: 'mobile_flutter/lib/features/kyc/data/kyc_api.dart',
    snippets: ['/api/v1/mobile/kyc/sumsub-token', 'createSumsubToken'],
  },
  {
    file: 'mobile_flutter/lib/features/kyc/data/sumsub_kyc_adapter.dart',
    snippets: ['SumsubKycAdapter', 'ArgumentError.value', 'SNSMobileSDK', '.init(accessToken', 'sdk.launch()'],
  },
  {
    file: 'mobile_flutter/lib/app.dart',
    snippets: ['MaterialApp.router', 'ShellRoute', 'buildAppTheme'],
  },
  {
    file: 'mobile_flutter/pubspec.yaml',
    snippets: ['flutter_riverpod', 'go_router', 'dio'],
  },
  {
    file: 'admin_vue/src/router/index.ts',
    snippets: ['requiresAdmin', 'beforeEach', 'useAuthStore'],
  },
  {
    file: 'admin_vue/src/lib/apiClient.ts',
    snippets: ['VITE_BACKEND_API_BASE_URL', 'axios.create', 'baseURL'],
  },
  {
    file: 'admin_vue/package.json',
    snippets: ['primevue', 'tailwindcss', 'pinia', 'vue-router'],
  },
  {
    file: 'docs/validation.md',
    snippets: [
      'Validation Plan',
      'Feature Coverage Matrix',
      'POST /api/v1/mobile/kyc/sumsub-token',
      'backend-only Hoppa rule',
      'admin/user route separation',
      'Hoppa OpenAPI source of truth',
      'UI/UX Review Checklist',
      'Clear overview',
      'Intuitive onboarding',
      'Simple money movement',
      'Card controls',
      'EqualsMoney/Interlace status clarity',
      'Admin dashboard density/readability',
    ],
  },
];

const backendExpectations = [
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AuthController.cs',
    snippets: [
      '[Route("api/v1/auth")]',
      '[AllowAnonymous]',
      '[HttpPost("login")]',
      '[HttpPost("refresh")]',
      '[Authorize(Policy = AuthorizationPolicyNames.AuthenticatedUser)]',
      '[HttpPost("logout")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileOnboardingController.cs',
    snippets: [
      '[Authorize(Policy = AuthorizationPolicyNames.User)]',
      '[Route("api/v1/mobile/onboarding")]',
      '[HttpGet("status")]',
      '[HttpPost("start")]',
      '[HttpPatch("steps")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileBusinessOnboardingController.cs',
    snippets: [
      '[Authorize(Policy = AuthorizationPolicyNames.User)]',
      '[Route("api/v1/mobile/business-onboarding")]',
      '[HttpGet("status")]',
      '[HttpPost("start")]',
      '[HttpPatch("profile")]',
      '[HttpPost("beneficial-owners")]',
      '[HttpPost("documents")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileKycController.cs',
    snippets: [
      '[Authorize(Policy = AuthorizationPolicyNames.User)]',
      '[Route("api/v1/mobile/kyc")]',
      '[HttpGet("status")]',
      '[HttpPost("sumsub-token")]',
      'ICreateSumSubAccessTokenUseCase',
      'TryGetCurrentUserId',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileBankingController.cs',
    snippets: [
      '[Authorize(Policy = AuthorizationPolicyNames.User)]',
      '[Route("api/v1/mobile/banking")]',
      '[HttpGet("accounts")]',
      '[HttpGet("accounts/{accountId}/balances")]',
      '[HttpGet("budgets")]',
      '[HttpPost("budgets")]',
      '[HttpGet("payees")]',
      '[HttpPost("payees")]',
      '[HttpGet("transfers")]',
      '[HttpPost("transfers")]',
      'UpstreamPath = $"/api/v2/{userRelativePath}"',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileCardsController.cs',
    snippets: [
      '[Route("api/v1/mobile/cards")]',
      '[HttpGet]',
      '[HttpPost]',
      '[HttpPost("{cardId}/activate")]',
      '[HttpPost("{cardId}/freeze")]',
      '[HttpPost("{cardId}/unfreeze")]',
      '[HttpPost("{cardId}/cancel")]',
      '[HttpPost("{cardId}/replace")]',
      '[HttpPatch("{cardId}/limits")]',
      '[HttpPatch("{cardId}/pin")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobilePaymentsController.cs',
    snippets: [
      '[Route("api/v1/mobile/payments")]',
      '[HttpGet]',
      '[HttpPost]',
      '[HttpGet("{paymentId}")]',
      '[HttpPost("{paymentId}/cancel")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileTransactionsController.cs',
    snippets: ['[Route("api/v1/mobile/transactions")]', '[HttpGet]', '[HttpGet("{transactionId}")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/MobileTiersController.cs',
    snippets: ['[Route("api/v1/mobile/tiers")]', '[HttpGet]', '[HttpGet("current")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminUsersController.cs',
    snippets: [
      '[Authorize(Policy = AuthorizationPolicyNames.Admin)]',
      '[Route("api/v1/admin/users")]',
      '[HttpGet]',
      '[HttpGet("{userId}")]',
      '[HttpPost("{userId}/decisions")]',
      '[HttpPatch("{userId}/status")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminKycController.cs',
    snippets: ['[Route("api/v1/admin/kyc")]', '[HttpGet("cases")]', '[HttpPost("cases/{caseId}/decisions")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminKybController.cs',
    snippets: ['[Route("api/v1/admin/kyb")]', '[HttpGet("cases")]', '[HttpPost("cases/{caseId}/decisions")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminBankingController.cs',
    snippets: [
      '[Route("api/v1/admin/banking")]',
      '[HttpGet("accounts")]',
      '[HttpGet("accounts/{accountId}/balances")]',
      '[HttpGet("payees")]',
      '[HttpGet("transfers")]',
    ],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminCardsController.cs',
    snippets: ['[Route("api/v1/admin/cards")]', '[HttpGet]', '[HttpPatch("{cardId}/status")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminPaymentsController.cs',
    snippets: ['[Route("api/v1/admin/payments")]', '[HttpGet]', '[HttpPatch("{paymentId}/status")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminTransactionsController.cs',
    snippets: ['[Route("api/v1/admin/transactions")]', '[HttpGet]', '[HttpPost("{transactionId}/adjustments")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminTiersController.cs',
    snippets: ['[Route("api/v1/admin/tiers")]', '[HttpGet]', '[HttpPatch("{tierCode}")]', '[HttpPost("users/{userId}")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminAuditController.cs',
    snippets: ['[Route("api/v1/admin/audit")]', '[HttpGet("events")]', '[HttpGet("events/{eventId}")]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/AdminBrandingController.cs',
    snippets: ['[Route("api/v1/admin/branding")]', '[HttpGet]', '[HttpPut]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/BrandingController.cs',
    snippets: ['[Route("api/v1/branding")]', '[AllowAnonymous]', '[HttpGet]', '[Authorize(Policy = AuthorizationPolicyNames.Admin)]', '[HttpPut]'],
  },
  {
    file: 'backend/src/NeoBanking.Api/Controllers/WebhooksController.cs',
    snippets: ['[AllowAnonymous]', '[Route("api/v1/webhooks")]', '[HttpPost("hoppa")]', '[HttpPost("sumsub")]'],
  },
  {
    file: 'backend/src/NeoBanking.Application/UseCases/Hoppa/ProxyHoppaRequestUseCase.cs',
    snippets: ['IProxyHoppaRequestUseCase', 'IHoppaClient', 'ValidatePath', 'must not contain a scheme'],
  },
  {
    file: 'backend/src/NeoBanking.Infrastructure/Hoppa/HoppaClient.cs',
    snippets: ['HttpClient', 'BuildRequestUri', 'x-api-key', 'QueryHelpers.AddQueryString', 'ValidateConfiguration'],
  },
  {
    file: 'backend/src/NeoBanking.Infrastructure/Hoppa/HoppaKycClient.cs',
    snippets: ['HttpClient', '/api/v2/users/', '/kyc/sumsub-access-token', 'x-api-key', 'SumSubAccessTokenResponseDto'],
  },
];

const flutterExpectations = [
  {
    file: 'mobile_flutter/lib/features/banking/data/mobile_banking_api.dart',
    snippets: [
      '/api/v1/mobile/me',
      '/api/v1/mobile/banking/accounts',
      '/api/v1/mobile/cards',
      '/api/v1/mobile/transactions',
      '/api/v1/mobile/banking/payees',
      '/api/v1/mobile/onboarding/status',
      '/api/v1/mobile/cards/$cardId/load',
      '/api/v1/mobile/banking/transfers',
      '/api/v1/mobile/payments',
      '/api/v1/mobile/business-onboarding/profile',
      '_withFallback',
    ],
  },
  {
    file: 'mobile_flutter/lib/features/platform/data/mobile_platform_api.dart',
    snippets: [
      '/api/v1/mobile/auth/signup',
      '/api/v1/mobile/kyc/status',
      '/api/v1/mobile/kyc/verify',
      '/api/v1/mobile/kyc/url',
      'equalsmoney',
      '/api/v1/mobile/banking/providers',
      '/api/v1/mobile/banking/budgets',
      '/api/v1/mobile/tiers',
      '/api/v1/mobile/tiers/current',
      '/api/v1/mobile/cards/$cardId/enable',
      '/api/v1/mobile/cards/$cardId/activate',
      '/api/v1/mobile/cards/$cardId/pin',
      '/api/v1/mobile/cards/$cardId/widget',
      '/api/v1/mobile/cards/$cardId/unload',
      '/api/v1/mobile/banking/accounts',
      '/api/v1/mobile/banking/quotes',
      '/api/v1/mobile/payments/mandates',
      '/api/v1/mobile/payments/requests',
      '/api/v1/mobile/payments/payouts',
      '/api/v1/mobile/payments/withdrawals',
      '/api/v1/mobile/wallets',
      '/api/v1/mobile/assets',
      '/api/v1/mobile/crypto-addresses',
      '/api/v1/mobile/transactions/export',
      '/api/v1/mobile/transactions/stats',
      '/api/v1/mobile/transactions/sync',
    ],
  },
  {
    file: 'mobile_flutter/lib/features/platform/application/platform_providers.dart',
    snippets: [
      'kycDetailedStatusProvider',
      'budgetsProvider',
      'tiersProvider',
      'bankingBalancesProvider',
      'mandatesProvider',
      'paymentRequestsProvider',
      'walletsProvider',
      'assetsProvider',
      'transactionStatsProvider',
    ],
  },
  {
    file: 'mobile_flutter/lib/core/api/dio_provider.dart',
    snippets: ['baseUrl: config.apiBaseUrl', 'Dio(', 'BaseOptions'],
  },
  {
    file: 'mobile_flutter/lib/features/kyc/application/kyc_providers.dart',
    snippets: ['kycApiProvider', 'sumsubKycAdapterProvider', 'startVerification(', 'onTokenExpiration'],
  },
  {
    file: 'mobile_flutter/test/features/kyc/data/kyc_api_test.dart',
    snippets: ['parses token field from backend response', 'rejects empty token response'],
  },
];

const vueExpectations = [
  {
    file: 'admin_vue/src/lib/apiClient.ts',
    snippets: [
      "allowedApiPrefixes = ['/api/v1/admin', '/api/v1/auth']",
      'apiClient.interceptors.request.use',
      'Admin UI may only call backend-owned admin/auth APIs',
    ],
  },
  {
    file: 'admin_vue/src/lib/adminApi.ts',
    snippets: ['loadAdminRows', 'loadAdminOverview', 'runAdminAction', 'exportAdminRows', 'buildCsv'],
  },
  {
    file: 'admin_vue/src/lib/adminResources.ts',
    snippets: [
      "'users'",
      "'onboarding'",
      "'kycKyb'",
      "'providers'",
      "'budgets'",
      "'tiers'",
      "'cardTiers'",
      "'cards'",
      "'accounts'",
      "'balances'",
      "'payees'",
      "'bankingTransfers'",
      "'payments'",
      "'mandates'",
      "'paymentRequests'",
      "'payouts'",
      "'withdrawals'",
      "'transactions'",
      "'transactionStats'",
      "'audit'",
      "'support'",
      "endpoint: '/api/v1/admin/hoppa/users'",
      "endpoint: '/api/v1/admin/hoppa/business-onboarding/applications'",
      "endpoint: '/api/v1/admin/hoppa/kyc-kyb/cases'",
      "endpoint: '/api/v1/admin/hoppa/banking/accounts'",
      "endpoint: '/api/v1/admin/hoppa/banking/balances'",
      "endpoint: '/api/v1/admin/hoppa/banking/payees'",
      "endpoint: '/api/v1/admin/hoppa/banking/transfers'",
      "endpoint: '/api/v1/admin/hoppa/payments'",
      "exportEndpoint: '/api/v1/admin/hoppa/transactions/export'",
      "endpoint: '/api/v1/admin/audit-log'",
      "endpoint: '/api/v1/admin/hoppa/support/reported-transactions'",
    ],
  },
  {
    file: 'admin_vue/src/views/AdminSettings.vue',
    snippets: [
      "apiClient.get<Record<string, unknown>>('/api/v1/admin/branding')",
      "apiClient.get<Record<string, unknown>>('/api/v1/admin/settings')",
      "apiClient.put('/api/v1/admin/branding'",
      "apiClient.put('/api/v1/admin/settings'",
      'adminMfaRequired',
      'kybRequiredForBusiness',
    ],
  },
  {
    file: 'admin_vue/src/views/AdminSupport.vue',
    snippets: [
      'adminResources.support',
      "'/api/v1/admin/hoppa/support/messages/report-transaction'",
      'Report Transaction',
    ],
  },
  {
    file: 'admin_vue/src/stores/auth.ts',
    snippets: ["roles.includes('admin')", 'isAuthenticated'],
  },
];

for (const expectation of [
  ...scaffoldExpectations,
  ...backendExpectations,
  ...flutterExpectations,
  ...vueExpectations,
  ...fullFlowBackendExpectations,
  ...fullFlowFlutterExpectations,
  ...fullFlowVueExpectations,
]) {
  expectSnippets(expectation.file, expectation.snippets);
}

const openApi = loadHoppaOpenApi();
expectHoppaOperations(openApi, hoppaCoverageGroups);
expectVueSourceOperationsMatchOpenApi(openApi, 'admin_vue/src/lib/adminResources.ts');
expectOperationsIncluded(
  extractVueSourceOperations('admin_vue/src/lib/adminResources.ts'),
  requiredVueSourceOperations,
  'admin_vue/src/lib/adminResources.ts sourceOperations full-flow coverage',
);
expectAdminVueRoutesGuarded();

expectRegex(
  'mobile_flutter/lib/features/kyc/data/kyc_api.dart',
  /_dio\.post<Map<String,\s*dynamic>>\(\s*['"]\/api\/v1\/mobile\/kyc\/sumsub-token['"]/m,
  'Flutter KYC client using POST /api/v1/mobile/kyc/sumsub-token',
);

const controllerFiles = listFiles('backend/src/NeoBanking.Api/Controllers', ['.cs']);
for (const file of controllerFiles) {
  const content = readProjectFile(file);
  const hasAdminRoute = content.includes('[Route("api/v1/admin/');
  const hasMobileRoute = content.includes('[Route("api/v1/mobile/');

  if (hasAdminRoute && !content.includes('[Authorize(Policy = AuthorizationPolicyNames.Admin)]')) {
    failures.push(`${file} has an admin route without the admin authorization policy`);
  }

  if (hasAdminRoute && content.includes('[Authorize(Policy = AuthorizationPolicyNames.User)]')) {
    failures.push(`${file} mixes an admin route with the user authorization policy`);
  }

  if (hasMobileRoute && !content.includes('[Authorize(Policy = AuthorizationPolicyNames.User)]')) {
    failures.push(`${file} has a mobile user route without the user authorization policy`);
  }

  if (hasMobileRoute && content.includes('[Authorize(Policy = AuthorizationPolicyNames.Admin)]')) {
    failures.push(`${file} mixes a mobile user route with the admin authorization policy`);
  }

  if (hasAdminRoute && hasMobileRoute) {
    failures.push(`${file} mixes admin and mobile route prefixes`);
  }
}

expectNoPattern(
  controllerFiles,
  /\b(?:IHoppaClient|IHoppaKycClient|HoppaClient|HoppaKycClient|HoppaOptions|HttpClient|x-api-key)\b/,
  'direct Hoppa client/header usage in API controllers; controllers must use proxy use cases',
);

const adminSourceFiles = listFiles('admin_vue/src', ['.ts', '.vue']);
const mobileSourceFiles = [
  ...listFiles('mobile_flutter/lib', ['.dart']),
  ...listFiles('mobile_flutter/test', ['.dart']),
];
const frontendSourceFiles = [...adminSourceFiles, ...mobileSourceFiles];

expectNoPattern(frontendSourceFiles, /staging\.(?:hoppa|hoppacard)|(?:hoppa|hoppacard)\.staging/i, 'Hoppa staging hostnames');
expectNoPattern(frontendSourceFiles, /https?:\/\/[^'"\s]*(?:hoppa|hoppacard)/i, 'direct Hoppa HTTP URLs');
expectNoPattern(frontendSourceFiles, /\b(?:api|global|staging)\.(?:hoppa|hoppacard)\b/i, 'direct Hoppa global hostnames');
expectNoPattern(
  frontendSourceFiles,
  /\b(?:x-api-key|hoppa[_-]?api[_-]?key|hoppacard[_-]?api[_-]?key|api[_-]?key[^'"\n;]*(?:hoppa|hoppacard)|(?:hoppa|hoppacard)[^'"\n;]*api[_-]?key)\b/i,
  'Hoppa API key material',
);
expectNoPattern(frontendSourceFiles, /https?:\/\/[^'"\s]*sumsub/i, 'direct SumSub HTTP URLs');
expectNoPattern(frontendSourceFiles, /\b(?:api|global|staging)\.sumsub\b/i, 'direct SumSub global hostnames');
expectNoPattern(adminSourceFiles, /\/api\/v1\/mobile\//, 'mobile API routes in admin Vue');
expectNoPattern(mobileSourceFiles, /\/api\/v1\/admin\//, 'admin API routes in Flutter mobile');

const backendSumsubRoute = readProjectFile('backend/src/NeoBanking.Api/Controllers/MobileKycController.cs');
const mobileSumsubClient = readProjectFile('mobile_flutter/lib/features/kyc/data/kyc_api.dart');
if (
  !backendSumsubRoute.includes('[Route("api/v1/mobile/kyc")]') ||
  !backendSumsubRoute.includes('[HttpPost("sumsub-token")]') ||
  !mobileSumsubClient.includes("'/api/v1/mobile/kyc/sumsub-token'")
) {
  failures.push('SumSub token route must be present in backend and consumed through the mobile backend API client');
}

if (failures.length > 0) {
  console.error(failures.join('\n'));
  process.exit(1);
}

console.log(
  [
    `Validated ${scaffoldExpectations.length} scaffold files.`,
    `Validated ${backendExpectations.length} backend feature files.`,
    `Validated ${flutterExpectations.length} Flutter feature files.`,
    `Validated ${vueExpectations.length} Vue feature files.`,
    `Validated ${fullFlowBackendExpectations.length} backend full-flow route/source groups.`,
    `Validated ${fullFlowFlutterExpectations.length} Flutter full-flow API groups.`,
    `Validated ${fullFlowVueExpectations.length} Vue full-flow resource groups.`,
    `Validated ${hoppaCoverageGroups.reduce((total, group) => total + group.operations.length, 0)} Hoppa OpenAPI source operations.`,
    `Validated ${extractVueSourceOperations('admin_vue/src/lib/adminResources.ts').length} Vue source operations against Hoppa OpenAPI.`,
    `Validated ${requiredVueSourceOperations.length} required Vue source operations for full-flow coverage.`,
    'Validated admin Vue route guard and nav/resource coverage.',
    'Validated UI/UX review checklist documentation for modern neo-banking standards.',
    'Validated backend-only Hoppa staging URL/API key guards, SumSub route, vendor URL, and admin/user route guards.',
    ...notes,
  ].join('\n'),
);
