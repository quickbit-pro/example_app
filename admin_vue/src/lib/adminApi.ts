import axios from 'axios';

import { apiClient } from '@/lib/apiClient';
import type { AdminRow, OverviewData } from '@/lib/adminResources';

export interface AdminLoadResult<T> {
  data: T;
  error?: string;
  source: 'api' | 'local';
}

export const emptyOverview: OverviewData = {
  activity: [],
  charts: {
    cardStatusBreakdown: [],
    cardsIssued: { labels: [], values: [] },
    kycReviews: { labels: [], approved: [], rejected: [], manualReview: [] },
    kycStatusBreakdown: [],
    signups: { labels: [], values: [] },
    webhookEventTypes: [],
    webhooks: { labels: [], succeeded: [], failed: [] },
    windowDays: 30,
  },
  metrics: [
    { label: 'Local users', tone: 'neutral', trend: 'Loading…', value: '0' },
    { label: 'KYC pending review', tone: 'neutral', trend: 'Loading…', value: '0' },
    { label: 'Cards (active / total)', tone: 'neutral', trend: 'Loading…', value: '0 / 0' },
    { label: 'Webhook failures', tone: 'neutral', trend: 'Loading…', value: '0' },
  ],
  onboarding: {
    applicants: [],
    cohortLabel: 'Users registered in the selected period',
    completed: 0,
    completionRate: 0,
    funnel: [
      { count: 0, key: 'registered', label: 'Registered', percent: 0 },
      { count: 0, key: 'started', label: 'Started onboarding', percent: 0 },
      { count: 0, key: 'submitted', label: 'Submitted details', percent: 0 },
      { count: 0, key: 'verified', label: 'Identity verified', percent: 0 },
      { count: 0, key: 'completed', label: 'Onboarding complete', percent: 0 },
    ],
    inProgress: 0,
    medianCompletionHours: null,
    needsAttention: 0,
    registered: 0,
    started: 0,
    statusBreakdown: [],
    stepBreakdown: [],
  },
  queues: [],
  riskSignals: [],
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function firstText(value: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const candidate = value[key];
    if (
      (typeof candidate === 'string' || typeof candidate === 'number') &&
      String(candidate).trim()
    ) {
      return String(candidate).trim();
    }
  }

  return '';
}

export function describeAdminError(error: unknown) {
  if (!axios.isAxiosError(error)) {
    return error instanceof Error ? error.message : 'Backend request failed.';
  }

  const data = error.response?.data;
  if (typeof data === 'string' && data.trim()) {
    return data.trim();
  }

  if (!isRecord(data)) {
    return error.message || 'Backend request failed.';
  }

  const parts = [
    firstText(data, ['title', 'error', 'message']),
    firstText(data, ['detail', 'Detail']),
    firstText(data, ['code', 'Code']),
    firstText(data, ['type', 'Type']),
    firstText(data, ['status', 'Status']),
    firstText(data, ['traceId', 'TraceId']),
    firstText(data, ['requestId', 'RequestId']),
  ].filter(Boolean);

  const validationErrors = isRecord(data.errors)
    ? Object.entries(data.errors)
        .flatMap(([field, value]) =>
          Array.isArray(value)
            ? value.map((item) => `${field}: ${String(item)}`)
            : [`${field}: ${String(value)}`],
        )
        .join(' ')
    : '';

  if (validationErrors) {
    parts.push(validationErrors);
  }

  return parts.length ? parts.join(' ') : error.message || 'Backend request failed.';
}

function normalizeRowValue(value: unknown): string | number | boolean | null {
  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean' ||
    value === null
  ) {
    return value;
  }

  if (value instanceof Date) {
    return value.toISOString();
  }

  return null;
}

function normalizeKey(key: string) {
  return key.length === 0 ? key : `${key[0].toLowerCase()}${key.slice(1)}`;
}

function firstPresent(
  row: Record<string, string | number | boolean | null>,
  keys: string[],
) {
  for (const key of keys) {
    const value = row[key];

    if (value !== null && value !== undefined && String(value).trim() !== '') {
      return value;
    }
  }

  return null;
}

function appendNestedDisplayFields(
  target: Record<string, unknown>,
  sourceKey: string,
  value: Record<string, unknown>,
) {
  const normalizedSourceKey = normalizeKey(sourceKey);

  for (const [childKey, childValue] of Object.entries(value)) {
    if (isRecord(childValue) || Array.isArray(childValue)) {
      continue;
    }

    const normalizedChildKey = normalizeKey(childKey);
    const prefixedKey = `${normalizedSourceKey}${
      normalizedChildKey.charAt(0).toUpperCase() + normalizedChildKey.slice(1)
    }`;

    target[normalizedChildKey] ??= childValue;
    target[prefixedKey] ??= childValue;
  }
}

function normalizeRow(row: Record<string, unknown>) {
  const flattened: Record<string, unknown> = { ...row };

  for (const [key, value] of Object.entries(row)) {
    if (isRecord(value)) {
      appendNestedDisplayFields(flattened, key, value);
    }
  }

  return withDisplayAliases(
    Object.fromEntries(
      Object.entries(flattened).map(([key, value]) => [
        key,
        normalizeRowValue(value),
      ]),
    ),
  );
}

function withDisplayAliases(
  row: Record<string, string | number | boolean | null>,
): AdminRow {
  const normalized = { ...row };

  for (const [key, value] of Object.entries(row)) {
    normalized[normalizeKey(key)] ??= value;
  }

  const firstName = firstPresent(normalized, ['firstName', 'givenName']);
  const lastName = firstPresent(normalized, ['lastName', 'familyName', 'surname']);
  const fullName = [firstName, lastName]
    .filter((part) => part !== null && String(part).trim() !== '')
    .join(' ');

  normalized.id ??= firstPresent(normalized, [
    'userId',
    'hoppaUserId',
    'localUserId',
    'caseId',
    'accountId',
    'cardId',
    'walletId',
    'addressId',
    'transactionId',
    'paymentId',
    'caseId',
    'eventId',
    'reference',
  ]);
  normalized.fullName ??= fullName || firstPresent(normalized, ['name', 'displayName']);
  normalized.firstName ??= firstName;
  normalized.lastName ??= lastName;
  normalized.owner ??= firstPresent(normalized, [
    'fullName',
    'displayName',
    'holderName',
    'customerName',
    'customerFullName',
    'businessName',
    'companyName',
    'email',
  ]);
  normalized.address ??= firstPresent(normalized, [
    'address',
    'depositAddress',
    'walletAddress',
    'cryptoAddress',
    'destinationAddress',
    'publicAddress',
    'iban',
    'accountNumber',
  ]);
  normalized.depositAddress ??= firstPresent(normalized, [
    'depositAddress',
    'walletAddress',
    'cryptoAddress',
    'publicAddress',
    'address',
  ]);
  normalized.walletAddress ??= firstPresent(normalized, [
    'walletAddress',
    'depositAddress',
    'cryptoAddress',
    'publicAddress',
    'address',
  ]);
  normalized.status ??= firstPresent(normalized, ['state', 'kycStatus', 'verificationStatus']);

  return normalized;
}

const adminListKeys = [
  'items',
  'Items',
  'data',
  'Data',
  'results',
  'Results',
  'list',
  'List',
  'users',
  'Users',
  'cases',
  'accounts',
  'Accounts',
  'cards',
  'Cards',
  'transactions',
  'Transactions',
  'transfers',
  'tiers',
  'events',
  'reports',
  'applications',
  'providers',
  'budgets',
  'balances',
  'payees',
  'mandates',
  'requests',
  'payouts',
  'withdrawals',
  'stats',
  'wallets',
  'Wallets',
  'assets',
  'Assets',
  'addresses',
  'Addresses',
  'cryptoAddresses',
  'CryptoAddresses',
];

export function extractAdminRecordList(data: unknown): Record<string, unknown>[] | null {
  const findList = (value: unknown): unknown[] | null => {
    if (Array.isArray(value)) {
      return value;
    }

    if (!isRecord(value)) {
      return null;
    }

    for (const key of adminListKeys) {
      if (Array.isArray(value[key])) {
        return value[key];
      }
    }

    for (const key of ['data', 'Data', 'result', 'Result']) {
      const list = findList(value[key]);

      if (list) {
        return list;
      }
    }

    return null;
  };

  const list = Array.isArray(data)
    ? data
    : isRecord(data)
      ? findList(data)
      : null;

  if (!list) {
    return null;
  }

  return list.filter(isRecord);
}

export function normalizeAdminRows(data: unknown): AdminRow[] | null {
  const list = extractAdminRecordList(data);

  return list ? list.map(normalizeRow) : null;
}

export async function loadAdminRows(
  endpoint: string,
  _sampleRows: AdminRow[],
): Promise<AdminLoadResult<AdminRow[]>> {
  try {
    const { data } = await apiClient.get<unknown>(endpoint);
    const rows = normalizeAdminRows(data);

    return {
      data: rows ?? [],
      error: rows
        ? undefined
        : 'Backend response did not include a list of records.',
      source: 'api',
    };
  } catch (error) {
    return {
      data: [],
      error: describeAdminError(error),
      source: 'local',
    };
  }
}

export interface AdminPage {
  rows: AdminRow[];
  totalCount: number;
}

function extractTotalCount(data: unknown): number | null {
  if (!isRecord(data)) return null;
  for (const key of ['totalCount', 'TotalCount', 'total', 'Total', 'count', 'Count']) {
    const candidate = data[key];
    if (typeof candidate === 'number' && Number.isFinite(candidate)) {
      return candidate;
    }
  }
  return null;
}

export async function loadAdminPage(
  endpoint: string,
): Promise<AdminLoadResult<AdminPage>> {
  try {
    const { data } = await apiClient.get<unknown>(endpoint);
    const rows = normalizeAdminRows(data) ?? [];
    const total = extractTotalCount(data);
    return {
      data: { rows, totalCount: total ?? rows.length },
      source: 'api',
    };
  } catch (error) {
    return {
      data: { rows: [], totalCount: 0 },
      error: describeAdminError(error),
      source: 'local',
    };
  }
}

export async function lookupAdminUser(lookup: string): Promise<AdminRow> {
  const { data } = await apiClient.get<unknown>(
    `/api/v1/admin/users/lookup/${encodeURIComponent(lookup)}`,
  );

  if (!isRecord(data)) {
    throw new Error('Backend user lookup response did not include a user record.');
  }

  return normalizeRow(data);
}

export async function loadAdminOverview(
  days?: number,
): Promise<AdminLoadResult<OverviewData>> {
  try {
    const path = typeof days === 'number'
      ? `/api/v1/admin/dashboard/overview?days=${days}`
      : '/api/v1/admin/dashboard/overview';
    const { data } = await apiClient.get<OverviewData>(path);

    if (!data || !Array.isArray(data.metrics)) {
      return {
        data: emptyOverview,
        error: 'Backend overview response did not include metrics.',
        source: 'local',
      };
    }

    return {
      data: {
        ...emptyOverview,
        ...data,
        onboarding: data.onboarding ?? emptyOverview.onboarding,
      },
      source: 'api',
    };
  } catch (error) {
    return {
      data: emptyOverview,
      error: describeAdminError(error),
      source: 'local',
    };
  }
}

export async function runAdminAction(
  method: 'delete' | 'get' | 'post' | 'put',
  endpoint: string,
  payload: Record<string, unknown>,
) {
  if (method === 'get') {
    const { data } = await apiClient.get<unknown>(endpoint);
    return data;
  }

  if (method === 'delete') {
    const { data } = await apiClient.delete<unknown>(endpoint, { data: payload });
    return data;
  }

  if (method === 'put') {
    const { data } = await apiClient.put<unknown>(endpoint, payload);
    return data;
  }

  const { data } = await apiClient.post<unknown>(endpoint, payload);
  return data;
}

export function buildCsv(rows: AdminRow[]): string {
  if (rows.length === 0) {
    return '';
  }

  const headers = Object.keys(rows[0]);
  const escapeCell = (value: unknown) => {
    const cell = value === null || value === undefined ? '' : String(value);
    return `"${cell.replace(/"/g, '""')}"`;
  };

  return [
    headers.map(escapeCell).join(','),
    ...rows.map((row) => headers.map((header) => escapeCell(row[header])).join(',')),
  ].join('\n');
}

export function downloadTextFile(filename: string, text: string, type: string) {
  const blob = new Blob([text], { type });
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  window.URL.revokeObjectURL(url);
}

export async function exportAdminRows(
  endpoint: string,
  fallbackRows: AdminRow[],
  filename: string,
): Promise<'api' | 'local'> {
  try {
    const { data } = await apiClient.get<Blob>(endpoint, {
      responseType: 'blob',
    });

    const url = window.URL.createObjectURL(data);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    window.URL.revokeObjectURL(url);
    return 'api';
  } catch {
    downloadTextFile(
      filename.replace(/\.csv$/, '-local-fallback.csv'),
      buildCsv(fallbackRows),
      'text/csv;charset=utf-8',
    );
    return 'local';
  }
}
