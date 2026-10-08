<script setup lang="ts">
import Button from 'primevue/button';
import Card from 'primevue/card';
import Column from 'primevue/column';
import DataTable from 'primevue/datatable';
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import AppShell from '@/components/AppShell.vue';
import { apiClient } from '@/lib/apiClient';
import {
  describeAdminError,
  extractAdminRecordList,
  loadAdminRows,
  lookupAdminUser,
} from '@/lib/adminApi';
import type { AdminRow, AdminRowValue } from '@/lib/adminResources';

const route = useRoute();
const router = useRouter();
const user = ref<AdminRow | null>(null);
const loading = ref(false);
const errorMessage = ref('');
const noticeMessage = ref('');
const sections = ref<UserSection[]>([]);

const lookup = computed(() => String(route.params.lookup ?? '').trim());

interface UserSection {
  description: string;
  error: string;
  icon: string;
  key: string;
  loading: boolean;
  rows: AdminRow[];
  title: string;
  type: 'list' | 'summary';
}

interface SectionRowsResult {
  data: AdminRow[];
  error?: string;
}

interface ResourceColumn {
  emphasis?: boolean;
  fields: string[];
  key: string;
  label: string;
  mono?: boolean;
}

const addressContainerKeys = [
  'addresses',
  'Addresses',
  'depositAddresses',
  'DepositAddresses',
  'cryptoAddresses',
  'CryptoAddresses',
  'walletAddresses',
  'WalletAddresses',
  'addressList',
  'AddressList',
];

const addressValueKeys = [
  'address',
  'Address',
  'depositAddress',
  'DepositAddress',
  'walletAddress',
  'WalletAddress',
  'cryptoAddress',
  'CryptoAddress',
  'publicAddress',
  'PublicAddress',
  'blockchainAddress',
  'BlockchainAddress',
];

const addressIdKeys = [
  'addressId',
  'AddressId',
  'depositAddressId',
  'DepositAddressId',
  'walletAddressId',
  'WalletAddressId',
];

const assetKeys = [
  'asset',
  'Asset',
  'assetCode',
  'AssetCode',
  'currency',
  'Currency',
  'currencyCode',
  'CurrencyCode',
  'token',
  'Token',
  'tokenSymbol',
  'TokenSymbol',
];

const networkKeys = [
  'network',
  'Network',
  'chain',
  'Chain',
  'blockchain',
  'Blockchain',
  'blockchainNetwork',
  'BlockchainNetwork',
  'protocol',
  'Protocol',
];

const walletIdKeys = ['id', 'Id', 'walletId', 'WalletId'];

const technicalEntries = computed(() => {
  if (!user.value) {
    return [];
  }

  return Object.entries(user.value)
    .filter(([field, value]) => isPresent(value) && isIdentifierField(field))
    .map(([field, value]) => ({
      field,
      label: fieldLabel(field),
      technical: isIdentifierField(field),
      value: formatValue(value),
    }));
});

const heroFacts = computed(() => {
  if (!user.value) {
    return [];
  }

  const kyc = sections.value.find((section) => section.key === 'kyc')?.rows[0];
  const assets = sections.value.find((section) => section.key === 'assets')?.rows ?? [];
  const cards = sections.value.find((section) => section.key === 'cards')?.rows ?? [];
  const transactions = sections.value.find((section) => section.key === 'transactions')?.rows ?? [];
  const activeCards = cards.filter((card) => ['active', 'activated'].includes(String(firstValue(card, ['status', 'state']) ?? '').toLowerCase())).length;

  return [
    { field: 'status', label: 'Account', value: user.value.status },
    { field: 'kycStatus', label: 'KYC', value: firstValue(kyc ?? {}, ['status', 'kycStatus', 'verificationStatus']) ?? user.value.kycStatus },
    { field: 'balances', label: 'Available funds', value: formatBalanceRows(assets) },
    { field: 'cards', label: 'Active cards', value: `${activeCards} of ${cards.length}` },
    { field: 'activity', label: 'Latest activity', value: firstValue(transactions[0] ?? {}, ['createdAt', 'date', 'transactionDate', 'timestamp']) },
  ].filter((fact) => isPresent(fact.value)).map((fact) => ({ ...fact, value: formatValue(fact.value) }));
});

const userReference = computed(() => {
  if (!user.value) {
    return lookup.value;
  }

  return String(
    firstValue(user.value, ['hoppaUserId', 'userId', 'id', 'localUserId']) ??
      lookup.value,
  );
});

const hasUserContext = computed(() => Boolean(user.value || userReference.value));

// Local account security: duress / security locks lifted by an admin after
// the cooling-off period. Only meaningful when the row carries the local UUID.
interface AccountLock {
  id: string;
  lockedAt: string;
  lockReason?: string | null;
  unlockAvailableAt: string;
}
const accountLock = ref<AccountLock | null>(null);
const accountLockBusy = ref(false);
const accountLockMessage = ref('');
const localUserId = computed(() => {
  const candidate = String(
    firstValue(user.value ?? {}, ['localUserId', 'localId', 'uuid', 'id']) ?? '',
  );
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(candidate)
    ? candidate
    : '';
});
const unlockAvailable = computed(() =>
  accountLock.value ? Date.parse(accountLock.value.unlockAvailableAt) <= Date.now() : false,
);

async function loadAccountLock() {
  accountLock.value = null;
  if (!localUserId.value) {
    return;
  }
  try {
    const response = await apiClient.get<AccountLock | null>(
      `/api/v1/admin/accounts/${localUserId.value}/lock`,
    );
    accountLock.value = response.status === 204 ? null : response.data;
  } catch {
    accountLock.value = null;
  }
}

async function unlockAccount() {
  if (!localUserId.value) {
    return;
  }
  accountLockBusy.value = true;
  accountLockMessage.value = '';
  try {
    await apiClient.post(`/api/v1/admin/accounts/${localUserId.value}/unlock`);
    accountLockMessage.value = 'Account unlocked. The customer can sign in again.';
    await loadAccountLock();
  } catch (error) {
    accountLockMessage.value = describeAdminError(error);
  } finally {
    accountLockBusy.value = false;
  }
}

function isPresent(value: AdminRowValue) {
  return value !== null && value !== undefined && String(value).trim() !== '';
}

function isIdentifierField(field: string) {
  return (
    field === 'id' ||
    field === 'uuid' ||
    field === 'localUuid' ||
    field === 'reference' ||
    /(^|_)(id|uuid)$/i.test(field) ||
    /Id$/.test(field) ||
    /Reference$/.test(field)
  );
}

function firstValue(row: AdminRow, fields: string[]) {
  for (const field of fields) {
    const value = row[field];

    if (isPresent(value)) {
      return value;
    }
  }

  return null;
}

function fieldLabel(field: string) {
  return field
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatValue(value: AdminRowValue) {
  if (value === null || value === undefined || value === '') {
    return 'Not provided';
  }

  if (typeof value === 'string') {
    const date = new Date(value);

    if (
      !Number.isNaN(date.getTime()) &&
      /^\d{4}-\d{2}-\d{2}/.test(value)
    ) {
      return new Intl.DateTimeFormat(undefined, {
        dateStyle: 'medium',
        timeStyle: value.includes('T') ? 'short' : undefined,
      }).format(date);
    }
  }

  return String(value);
}

function numericValue(value: AdminRowValue) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function assetCurrency(row: AdminRow) {
  return String(firstValue(row, ['asset', 'assetCode', 'currency', 'currencyCode', 'token', 'tokenSymbol']) ?? '').toUpperCase();
}

// Provider asset listings include chains the product does not offer; the
// backend hides the same set from every stored balance summary.
const HIDDEN_BALANCE_ASSETS = new Set(['BTC', 'ETH']);

function summarizeAssetRows(rows: AdminRow[]) {
  const totals = new Map<string, number>();
  for (const row of rows) {
    const currency = assetCurrency(row);
    if (!currency || HIDDEN_BALANCE_ASSETS.has(currency)) continue;
    const balance = numericValue(firstValue(row, ['availableBalance', 'balance', 'amount', 'value']));
    totals.set(currency, (totals.get(currency) ?? 0) + balance);
  }
  return [...totals.entries()]
    .map(([currency, balance], index) => ({ id: `${currency}-${index}`, asset: currency, balance }))
    .sort((left, right) => Math.abs(Number(right.balance)) - Math.abs(Number(left.balance)));
}

function formatBalanceRows(rows: AdminRow[]) {
  const funded = rows.filter((row) => Math.abs(numericValue(row.balance)) > 0.00000001);
  if (funded.length === 0) return rows.length ? 'No funds' : null;
  return funded.slice(0, 3).map((row) => `${Number(row.balance).toLocaleString(undefined, { maximumFractionDigits: 6 })} ${row.asset}`).join(' · ');
}

function deduplicateRows(rows: AdminRow[], fields: string[]) {
  const seen = new Set<string>();
  return rows.filter((row, index) => {
    const key = String(firstValue(row, fields) ?? index);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function normalizeRowValue(value: unknown): AdminRowValue | null {
  if (
    typeof value === 'string' ||
    typeof value === 'number' ||
    typeof value === 'boolean' ||
    value === null ||
    value === undefined
  ) {
    return value;
  }

  return null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function firstText(row: Record<string, unknown>, keys: string[]) {
  for (const key of keys) {
    const value = row[key];

    if (value !== null && value !== undefined && String(value).trim() !== '') {
      return String(value).trim();
    }
  }

  return '';
}

function flattenRecord(value: unknown) {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return {};
  }

  const flattened: AdminRow = {};

  for (const [key, entry] of Object.entries(value)) {
    if (typeof entry === 'object' && entry !== null && !Array.isArray(entry)) {
      for (const [nestedKey, nestedValue] of Object.entries(entry)) {
        const value = normalizeRowValue(nestedValue);

        if (value !== undefined) {
          flattened[nestedKey] ??= value;
          flattened[`${key}${nestedKey.charAt(0).toUpperCase()}${nestedKey.slice(1)}`] ??= value;
        }
      }
      continue;
    }

    const normalized = normalizeRowValue(entry);

    if (normalized !== undefined) {
      flattened[key] = normalized;
    }
  }

  return flattened;
}

function rowKey(row: AdminRow, fallback: unknown) {
  return String(
    firstValue(row, [
      'id',
      'uuid',
      'accountId',
      'cardId',
      'walletId',
      'addressId',
      'transactionId',
      'reference',
    ]) ?? fallback,
  );
}

function primaryRowText(row: AdminRow) {
  return String(
    firstValue(row, [
      'name',
      'displayName',
      'fullName',
      'nickname',
      'holder',
      'currency',
      'asset',
      'accountNumber',
      'iban',
      'address',
      'depositAddress',
      'walletAddress',
      'transactionId',
      'id',
    ]) ?? 'Record',
  );
}

function rowEntries(row: AdminRow) {
  return Object.entries(row)
    .filter(([, value]) => isPresent(value))
    .sort(([left], [right]) => fieldPriority(left) - fieldPriority(right))
    .slice(0, 8)
    .map(([field, value]) => ({
      field,
      label: fieldLabel(field),
      value: formatValue(value),
    }));
}

function resourceColumns(sectionKey: string): ResourceColumn[] {
  const columns: Record<string, ResourceColumn[]> = {
    accounts: [
      { emphasis: true, fields: ['displayName', 'name', 'nickname', 'owner'], key: 'name', label: 'Account' },
      { fields: ['accountType', 'type'], key: 'type', label: 'Type' },
      { fields: ['status', 'state'], key: 'status', label: 'Status' },
      { fields: ['balance', 'availableBalance', 'amount'], key: 'balance', label: 'Balance' },
      { fields: ['currency', 'currencyCode'], key: 'currency', label: 'Currency' },
    ],
    assets: [
      { emphasis: true, fields: ['asset', 'assetCode', 'currency', 'currencyCode', 'token', 'tokenSymbol'], key: 'asset', label: 'Asset' },
      { fields: ['balance', 'availableBalance', 'amount'], key: 'balance', label: 'Balance' },
      { fields: ['network', 'chain', 'blockchain', 'protocol'], key: 'network', label: 'Network' },
      { fields: ['status', 'state'], key: 'status', label: 'Status' },
    ],
    cards: [
      { emphasis: true, fields: ['cardName', 'nickname', 'displayName', 'name', 'cardNumber'], key: 'card', label: 'Card' },
      { fields: ['cardType', 'type', 'productCode'], key: 'type', label: 'Type' },
      { fields: ['status', 'state'], key: 'status', label: 'Status' },
      { fields: ['cardNumber', 'maskedPan', 'pan'], key: 'number', label: 'Number', mono: true },
      { fields: ['currency', 'currencyCode'], key: 'currency', label: 'Currency' },
    ],
    depositAddresses: [
      { emphasis: true, fields: ['asset', 'assetCode', 'currency', 'currencyCode', 'token', 'tokenSymbol'], key: 'asset', label: 'Asset' },
      { fields: ['network', 'chain', 'blockchain', 'protocol'], key: 'network', label: 'Network' },
      { fields: ['address', 'depositAddress', 'walletAddress', 'cryptoAddress', 'publicAddress', 'blockchainAddress'], key: 'address', label: 'Address', mono: true },
      { fields: ['walletId'], key: 'walletId', label: 'Wallet ID', mono: true },
      { fields: ['status', 'state', 'source'], key: 'status', label: 'Status' },
    ],
    transactions: [
      { fields: ['createdAt', 'date', 'transactionDate', 'timestamp'], key: 'date', label: 'Date' },
      { emphasis: true, fields: ['description', 'merchantName', 'counterparty', 'type'], key: 'description', label: 'Description' },
      { fields: ['type', 'transactionType'], key: 'type', label: 'Type' },
      { fields: ['amount', 'value'], key: 'amount', label: 'Amount' },
      { fields: ['currency', 'currencyCode'], key: 'currency', label: 'Currency' },
      { fields: ['status', 'state'], key: 'status', label: 'Status' },
    ],
    wallets: [
      { emphasis: true, fields: ['nickname', 'name', 'displayName', 'type'], key: 'wallet', label: 'Wallet' },
      { fields: ['walletId', 'id'], key: 'walletId', label: 'Wallet ID', mono: true },
      { fields: ['accountId'], key: 'accountId', label: 'Account ID', mono: true },
      { fields: ['currency', 'currencyCode', 'asset', 'assetCode'], key: 'currency', label: 'Currency' },
      { fields: ['balance', 'availableBalance', 'amount'], key: 'balance', label: 'Balance' },
      { fields: ['master', 'isMaster'], key: 'master', label: 'Master' },
      { fields: ['referenceId', 'reference'], key: 'reference', label: 'Reference', mono: true },
    ],
  };

  return (
    columns[sectionKey] ?? [
      { emphasis: true, fields: ['name', 'displayName', 'description', 'type', 'id'], key: 'record', label: 'Record' },
      { fields: ['status', 'state'], key: 'status', label: 'Status' },
      { fields: ['amount', 'balance', 'currency'], key: 'amount', label: 'Amount' },
      { fields: ['id', 'reference'], key: 'reference', label: 'Reference', mono: true },
    ]
  );
}

function columnValue(row: AdminRow, column: ResourceColumn) {
  return formatValue(firstValue(row, column.fields));
}

function shouldCopyColumn(column: ResourceColumn) {
  return column.mono || column.key === 'address';
}

function fieldPriority(field: string) {
  const normalized = field.toLowerCase();

  if (['status', 'state', 'kycstatus', 'verificationstatus'].includes(normalized)) {
    return 0;
  }

  if (
    [
      'balance',
      'availablebalance',
      'amount',
      'currency',
      'asset',
      'network',
      'chain',
      'address',
      'depositaddress',
      'walletaddress',
      'iban',
      'accountnumber',
    ].includes(normalized)
  ) {
    return 1;
  }

  if (isIdentifierField(field)) {
    return 3;
  }

  return 2;
}

function primaryText(row: AdminRow | null) {
  if (!row) {
    return lookup.value || 'User detail';
  }

  const firstName = String(row.firstName ?? row.first_name ?? '').trim();
  const lastName = String(row.lastName ?? row.last_name ?? '').trim();
  const fullName = [firstName, lastName].filter(Boolean).join(' ');

  return String(
    fullName ||
      row.name ||
      row.displayName ||
      row.fullName ||
      row.email ||
      row.id ||
      lookup.value,
  );
}

function canUseImpliedNetworkAddress(key: string | null) {
  const normalized = key?.trim().toLowerCase();

  if (!normalized) {
    return false;
  }

  const metadataKeys = [
    ...addressValueKeys,
    ...addressIdKeys,
    ...assetKeys,
    ...networkKeys,
    ...walletIdKeys,
    'accountId',
    'AccountId',
    'nickname',
    'Nickname',
    'selected',
    'enabled',
    'active',
    'status',
    'state',
    'type',
  ].map((item) => item.toLowerCase());

  return !metadataKeys.includes(normalized);
}

function walletAddressRow(
  wallet: Record<string, unknown>,
  address: Record<string, unknown>,
  impliedKey: string | null,
) {
  const normalized: Record<string, unknown> = {
    ...address,
    walletId: firstText(wallet, walletIdKeys),
    accountId: firstText(wallet, ['accountId', 'AccountId']),
    walletNickname: firstText(wallet, ['nickname', 'Nickname']),
    currency: firstText(address, assetKeys) || firstText(wallet, assetKeys),
    network: firstText(address, networkKeys) || impliedKey || firstText(wallet, networkKeys),
    source: 'wallet',
  };
  normalized.id =
    normalized.id ||
    firstText(address, addressIdKeys) ||
    [
      normalized.walletId,
      normalized.currency,
      normalized.network,
      firstText(address, addressValueKeys),
    ]
      .filter(Boolean)
      .join(':');

  return flattenRecord(normalized);
}

function appendWalletAddressRows(
  rows: AdminRow[],
  wallet: Record<string, unknown>,
  value: unknown,
  impliedKey: string | null = null,
) {
  if (value === null || value === undefined) {
    return;
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      appendWalletAddressRows(rows, wallet, item, impliedKey);
    }
    return;
  }

  if (isRecord(value)) {
    if (firstText(value, addressValueKeys)) {
      rows.push(walletAddressRow(wallet, value, impliedKey));
      return;
    }

    for (const [key, nestedValue] of Object.entries(value)) {
      appendWalletAddressRows(rows, wallet, nestedValue, key);
    }
    return;
  }

  if (typeof value !== 'string' || !canUseImpliedNetworkAddress(impliedKey)) {
    return;
  }

  const address = value.trim();

  if (!address) {
    return;
  }

  rows.push(walletAddressRow(wallet, { address }, impliedKey));
}

function depositAddressRowsFromWallets(wallets: Record<string, unknown>[]) {
  const rows: AdminRow[] = [];

  for (const wallet of wallets) {
    if (firstText(wallet, addressValueKeys)) {
      rows.push(walletAddressRow(wallet, wallet, null));
    }

    for (const key of addressContainerKeys) {
      appendWalletAddressRows(rows, wallet, wallet[key]);
    }
  }

  return rows;
}

function addressMergeKey(row: AdminRow) {
  return [
    firstValue(row, ['address', 'depositAddress', 'walletAddress', 'cryptoAddress', 'publicAddress']),
    firstValue(row, ['asset', 'assetCode', 'currency', 'currencyCode', 'token', 'tokenSymbol']),
    firstValue(row, ['network', 'chain', 'blockchain', 'protocol']),
    firstValue(row, ['addressId', 'depositAddressId', 'walletAddressId', 'id']),
  ]
    .filter((value) => value !== null && String(value).trim() !== '')
    .map((value) => String(value).trim().toLowerCase())
    .join('|');
}

function mergeRowsByAddress(rows: AdminRow[]) {
  const merged: AdminRow[] = [];
  const seen = new Set<string>();

  for (const row of rows) {
    const key = addressMergeKey(row) || rowKey(row, merged.length);

    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    merged.push(row);
  }

  return merged;
}

async function copyValue(label: string, value: string) {
  errorMessage.value = '';

  try {
    await navigator.clipboard.writeText(value);
    noticeMessage.value = `${label} copied to clipboard.`;
  } catch (error) {
    errorMessage.value = `Could not copy ${label.toLowerCase()}. ${describeAdminError(error)}`;
  }
}

async function loadUser() {
  if (!lookup.value) {
    errorMessage.value = 'User lookup is missing.';
    return;
  }

  loading.value = true;
  errorMessage.value = '';
  noticeMessage.value = '';

  try {
    user.value = await lookupAdminUser(lookup.value);
    await loadAccountLock();
    await loadUserSections();
  } catch (error) {
    user.value = null;
    errorMessage.value = describeAdminError(error);
    await loadUserSections();
  } finally {
    loading.value = false;
  }
}

function makeSections(): UserSection[] {
  return [
    {
      description: 'Identity verification status, provider references, and review state.',
      error: '',
      icon: 'pi pi-verified',
      key: 'kyc',
      loading: false,
      rows: [],
      title: 'KYC Status',
      type: 'summary',
    },
    {
      description: 'Bank accounts and account-level state for this customer.',
      error: '',
      icon: 'pi pi-building-columns',
      key: 'accounts',
      loading: false,
      rows: [],
      title: 'Bank Accounts',
      type: 'list',
    },
    {
      description: 'Combined available balances by currency and asset.',
      error: '',
      icon: 'pi pi-chart-pie',
      key: 'assets',
      loading: false,
      rows: [],
      title: 'Balances',
      type: 'list',
    },
    {
      description: 'Issued cards, cardholder state, limits, and status.',
      error: '',
      icon: 'pi pi-credit-card',
      key: 'cards',
      loading: false,
      rows: [],
      title: 'Cards',
      type: 'list',
    },
    {
      description: 'Recent platform transactions scoped to this customer.',
      error: '',
      icon: 'pi pi-receipt',
      key: 'transactions',
      loading: false,
      rows: [],
      title: 'Transactions',
      type: 'list',
    },
  ];
}

async function loadUserSections() {
  if (!userReference.value) {
    sections.value = makeSections().map((section) => ({
      ...section,
      error: 'No Hoppa or local user reference was returned for this user.',
    }));
    return;
  }

  sections.value = makeSections();
  await Promise.all(sections.value.map(loadSection));
}

async function loadDepositAddressRows(encodedUserId: string): Promise<SectionRowsResult> {
  const addressResult = await loadAdminRows(
    `/api/v1/admin/hoppa/users/crypto-addresses?userId=${encodedUserId}`,
    [],
  );
  let walletAddressRows: AdminRow[] = [];
  let walletAddressError = '';

  try {
    const { data } = await apiClient.get<unknown>(
      `/api/v1/admin/hoppa/users/wallets?userId=${encodedUserId}`,
    );
    const walletRecords = extractAdminRecordList(data) ?? [];
    walletAddressRows = depositAddressRowsFromWallets(walletRecords);
  } catch (error) {
    walletAddressError = describeAdminError(error);
  }

  const rows = mergeRowsByAddress([...addressResult.data, ...walletAddressRows]);
  const errors = [...new Set([addressResult.error, walletAddressError].filter(Boolean))];

  return {
    data: rows,
    error: rows.length === 0 && errors.length ? errors.join(' ') : undefined,
  };
}

async function loadSectionRows(
  sectionKey: string,
  encodedUserId: string,
): Promise<SectionRowsResult> {
  if (sectionKey === 'depositAddresses') {
    return loadDepositAddressRows(encodedUserId);
  }

  const endpoints: Record<string, string> = {
    accounts: `/api/v1/admin/banking/accounts?userId=${encodedUserId}&limit=25`,
    assets: `/api/v1/admin/hoppa/users/assets?userId=${encodedUserId}`,
    cards: `/api/v1/admin/cards?userId=${encodedUserId}&limit=25`,
    transactions: `/api/v1/admin/transactions?userId=${encodedUserId}&limit=25`,
    wallets: `/api/v1/admin/hoppa/users/wallets?userId=${encodedUserId}`,
  };
  const endpoint = endpoints[sectionKey];

  if (!endpoint) {
    return {
      data: [],
      error: `No admin endpoint configured for ${sectionKey}.`,
    };
  }

  return loadAdminRows(endpoint, []);
}

async function loadSection(section: UserSection) {
  section.loading = true;
  section.error = '';

  try {
    const encodedUserId = encodeURIComponent(userReference.value);

    if (section.key === 'kyc') {
      const { data } = await apiClient.get<unknown>(
        `/api/v1/admin/kyc/cases/${encodedUserId}`,
      );
      const row = flattenRecord(data);
      section.rows = Object.keys(row).length > 0 ? [row] : [];
      return;
    }

    const result = await loadSectionRows(section.key, encodedUserId);
    section.rows = section.key === 'assets'
      ? summarizeAssetRows(result.data)
      : section.key === 'accounts'
        ? deduplicateRows(result.data, ['accountId', 'id'])
        : result.data;
    section.error = result.error ?? '';
  } catch (error) {
    section.rows = [];
    section.error = describeAdminError(error);
  } finally {
    section.loading = false;
  }
}

onMounted(loadUser);
watch(lookup, loadUser);
</script>

<template>
  <AppShell>
    <template #header>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <button
            class="mb-2 inline-flex items-center gap-2 text-sm font-semibold text-slate-500 hover:text-slate-950"
            type="button"
            @click="router.push({ name: 'admin-users' })"
          >
            <i class="pi pi-arrow-left text-xs" />
            Users
          </button>
          <h1 class="text-xl font-semibold text-slate-950">
            {{ primaryText(user) }}
          </h1>
          <p class="text-sm text-slate-500">
            Customer verification, balances, cards, and recent activity.
          </p>
        </div>
        <Button
          icon="pi pi-refresh"
          label="Refresh"
          :loading="loading"
          @click="loadUser"
        />
      </div>
    </template>

    <div
      v-if="errorMessage"
      class="mb-4 rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800"
    >
      {{ errorMessage }}
    </div>
    <div
      v-if="noticeMessage"
      class="mb-4 rounded-md border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
    >
      {{ noticeMessage }}
    </div>

    <Card>
      <template #content>
        <div v-if="loading" class="py-12 text-center text-sm text-slate-500">
          Loading user details...
        </div>
        <div v-else-if="hasUserContext" class="space-y-5">
          <div class="flex flex-wrap items-start justify-between gap-4 border-b border-slate-200 pb-4">
            <div class="min-w-0">
              <p class="text-xs font-semibold uppercase text-slate-500">
                {{ user ? 'Customer' : 'Customer lookup' }}
              </p>
              <h2 class="mt-1 break-words text-2xl font-semibold text-slate-950">
                {{ primaryText(user) }}
              </h2>
              <p
                v-if="user?.email"
                class="mt-1 break-words text-sm text-slate-500"
              >
                {{ user.email }}
              </p>
              <p
                v-else-if="!user"
                class="mt-1 break-words font-mono text-xs text-slate-500"
              >
                {{ userReference }}
              </p>
            </div>
          </div>

          <dl
            v-if="heroFacts.length"
            class="grid overflow-hidden rounded-md border border-slate-200 md:grid-cols-4 sm:grid-cols-2"
          >
            <div
              v-for="fact in heroFacts"
              :key="fact.field"
              class="border-b border-r border-slate-200 px-3 py-2 last:border-r-0 md:border-b-0"
            >
              <dt class="text-[0.68rem] font-semibold uppercase text-slate-500">
                {{ fact.label }}
              </dt>
              <dd class="mt-1 break-words text-sm font-semibold text-slate-950">
                {{ fact.value }}
              </dd>
            </div>
          </dl>

          <section
            v-if="accountLock"
            class="rounded-md border border-amber-300 bg-amber-50 px-4 py-3"
          >
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h3 class="text-base font-semibold text-amber-900">
                  Account locked ({{ accountLock.lockReason ?? 'security' }})
                </h3>
                <p class="text-sm text-amber-800">
                  Locked {{ formatValue(accountLock.lockedAt) }}.
                  <template v-if="unlockAvailable">The cooling-off period has passed; you can unlock it now.</template>
                  <template v-else>Can be unlocked from {{ formatValue(accountLock.unlockAvailableAt) }}.</template>
                </p>
                <p v-if="accountLockMessage" class="mt-1 text-sm font-semibold text-amber-900">
                  {{ accountLockMessage }}
                </p>
              </div>
              <Button
                icon="pi pi-unlock"
                label="Unlock account"
                :disabled="!unlockAvailable"
                :loading="accountLockBusy"
                @click="unlockAccount"
              />
            </div>
          </section>

          <section class="space-y-4">
            <div>
              <h3 class="text-base font-semibold text-slate-950">
                Customer overview
              </h3>
              <p class="text-sm text-slate-500">
                Live financial and compliance information from the platform.
              </p>
            </div>

            <div class="space-y-4">
              <section
                v-for="section in sections"
                :key="section.key"
                class="rounded-md border border-slate-200 bg-white"
              >
                <div class="flex flex-wrap items-start justify-between gap-3 border-b border-slate-200 bg-slate-50 px-4 py-3">
                  <div class="flex min-w-0 items-start gap-3">
                    <span class="inline-flex size-9 shrink-0 items-center justify-center rounded-md border border-slate-200 bg-white text-slate-600">
                      <i :class="section.icon" />
                    </span>
                    <div class="min-w-0">
                      <h4 class="text-sm font-semibold text-slate-950">
                        {{ section.title }}
                      </h4>
                      <p class="mt-0.5 text-xs leading-5 text-slate-500">
                        {{ section.description }}
                      </p>
                    </div>
                  </div>
                  <span class="rounded-md border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-600">
                    {{ section.loading ? 'Loading' : `${section.rows.length} records` }}
                  </span>
                </div>

                <div
                  v-if="section.error"
                  class="border-b border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800"
                >
                  {{ section.error }}
                </div>

                <div v-if="section.loading" class="px-4 py-8 text-center text-sm text-slate-500">
                  Loading {{ section.title.toLowerCase() }}...
                </div>

                <div
                  v-else-if="section.rows.length === 0"
                  class="px-4 py-8 text-center text-sm text-slate-500"
                >
                  No {{ section.title.toLowerCase() }} returned for this user.
                </div>

                <div
                  v-else-if="section.type === 'summary'"
                  class="p-4"
                >
                  <div class="overflow-hidden rounded-md border border-slate-200">
                    <table class="min-w-full divide-y divide-slate-200 text-sm">
                      <tbody class="divide-y divide-slate-200">
                        <tr
                          v-for="entry in rowEntries(section.rows[0])"
                          :key="entry.field"
                        >
                          <th class="w-56 bg-slate-50 px-3 py-2 text-left text-xs font-semibold uppercase text-slate-500">
                            {{ entry.label }}
                          </th>
                          <td class="px-3 py-2 text-slate-900">
                            {{ entry.value }}
                          </td>
                        </tr>
                      </tbody>
                    </table>
                  </div>
                </div>

                <DataTable
                  v-else
                  :value="section.rows"
                  data-key="id"
                  size="small"
                  striped-rows
                  scrollable
                  table-style="min-width: 48rem"
                >
                  <Column
                    v-for="column in resourceColumns(section.key)"
                    :key="column.key"
                    :header="column.label"
                  >
                    <template #body="{ data }">
                      <div class="flex min-w-0 items-center gap-2">
                        <span
                          class="min-w-0 max-w-80 truncate text-sm"
                          :class="[
                            column.emphasis ? 'font-semibold text-slate-950' : 'text-slate-700',
                            column.mono ? 'font-mono text-xs' : '',
                          ]"
                          :title="columnValue(data, column)"
                        >
                          {{ columnValue(data, column) }}
                        </span>
                        <Button
                          v-if="shouldCopyColumn(column) && columnValue(data, column) !== 'Not provided'"
                          icon="pi pi-copy"
                          severity="secondary"
                          size="small"
                          text
                          :aria-label="`Copy ${column.label}`"
                          @click="copyValue(column.label, columnValue(data, column))"
                        />
                      </div>
                    </template>
                  </Column>
                </DataTable>
              </section>
            </div>
          </section>

          <details v-if="technicalEntries.length" class="rounded-md border border-slate-200 bg-slate-50">
            <summary class="cursor-pointer px-4 py-3 text-sm font-semibold text-slate-600">
              Technical identifiers
            </summary>
            <div class="border-t border-slate-200 bg-white p-4">
              <dl class="grid gap-3 md:grid-cols-2">
                <div v-for="entry in technicalEntries" :key="entry.field" class="rounded-md border border-slate-200 p-3">
                  <dt class="text-xs font-semibold uppercase text-slate-500">{{ entry.label }}</dt>
                  <dd class="mt-1 break-all font-mono text-xs text-slate-700">{{ entry.value }}</dd>
                </div>
              </dl>
            </div>
          </details>
        </div>
        <div v-else class="py-12 text-center text-sm text-slate-500">
          No user detail was returned.
        </div>
      </template>
    </Card>
  </AppShell>
</template>
