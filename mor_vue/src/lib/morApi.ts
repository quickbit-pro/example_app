import { apiClient } from "./apiClient";
import axios from "axios";

export interface MorContext {
  company: { id: number | string; name: string };
  capabilities?: MorCapabilities;
  merchant: boolean;
  whitelabel: boolean;
}
export interface MorCapabilities {
  cardOrdering: boolean;
  cardCancellation: boolean;
  quantumFunding: boolean;
}
export interface Kyb {
  status: string;
  profileId?: string;
  interlaceAccountId?: string;
  rejectionReason?: string;
  companyCardholderId?: string;
  companyCardholderStatus?: string;
  companyCardholderError?: string;
  submittedAt?: string;
  reviewedAt?: string;
  lastPolledAt?: string;
}
export interface Wallet {
  id?: number;
  tokenSymbol?: string;
  token?: string;
  network?: string;
  balance: number;
  usdValue?: number;
  walletAddress?: string;
  status?: string;
  onlyDeposit?: boolean;
}
export interface Balances {
  totalUsdValue: number;
  totalAvailableUSDT: number;
  totalAvailableUSDC: number;
  quantumWallets: Wallet[];
  cryptoAssets: Wallet[];
}
export interface Overview {
  company: {
    id: number | string;
    name: string;
    legalName?: string;
    status?: string;
    interlaceAccountId?: string;
  };
  parentWhitelabel?: { id: number | string; name: string };
  kyb?: Kyb | null;
  counts: {
    users: number;
    cards: number;
    assignedCards: number;
    unassignedCards: number;
  };
  balances: Balances;
}
export interface MorUser {
  userId: number;
  email: string;
  firstName?: string;
  lastName?: string;
  phone?: string | null;
  name?: string;
  invitationEmailSent?: boolean;
}
export interface MorCard {
  id: number;
  status: string;
  productName?: string;
  currency: string;
  availableBalance: number;
  pendingBalance: number;
  maskedCardNumber?: string;
  cardNumberLastFour?: string;
  assignedUserId?: number;
  assignedUserName?: string;
  assignedUserEmail?: string;
  isLocked: boolean;
  isVirtual: boolean;
  createdAt: string;
  pendingLoadRequest?: {
    amount: number;
    currency: string;
    requestedByName: string;
    note?: string;
    status: string;
  };
}
export interface CardProduct {
  cardTypeId: number;
  name: string;
  description?: string;
  currencyCode: string;
  tierName: string;
  issuanceFee: number;
  monthlySubscriptionFee: number;
  yearlySubscriptionFee: number;
  isVirtual: boolean;
  maxCards?: number;
}
export interface Analytics {
  totalCards: number;
  activeCards: number;
  cancelledCards: number;
  assignedCards: number;
  unassignedCards: number;
  cardsUsedInPeriod: number;
  transactionCount: number;
  totalAvailableBalance: number;
  totalPendingBalance: number;
  totalSpendUsd: number;
  averageTransactionUsd: number;
  dailyUsage: {
    date: string;
    transactionCount: number;
    uniqueCards: number;
    spendUsd: number;
  }[];
}
export interface Transactions {
  data: {
    id: number;
    userName: string;
    userEmail?: string;
    transactionType: string;
    amount: string;
    currency: string;
    status: string;
    description?: string;
    merchantName?: string;
    transactionDate: string;
  }[];
  pagination: {
    page: number;
    pageSize: number;
    total: number;
    totalPages: number;
  };
  stats: { totalTransactions: number; countByStatus: Record<string, number> };
  transactionTypes: string[];
  users: { userId: number; name: string; email?: string }[];
}
export interface MerchantTier {
  tierId: number;
  name: string;
  monthlyFee: number;
  yearlyFee: number;
  virtualCardProductCount: number;
}
export interface MorCompany {
  companyId: number;
  name: string;
  tierName?: string;
  kybStatus?: string;
  createdAt: string;
}
export interface WalletResponse {
  balances: Balances;
  wallets: {
    wallets: Wallet[];
    refreshSuccessful?: boolean;
    errorMessage?: string;
    walletOutflowsEnabled?: boolean;
    disabledCryptoAddresses?: string[];
  };
}

const base = "/api/v1/mor/admin";
export async function morGet<T>(path: string, params?: object): Promise<T> {
  return (await apiClient.get<T>(`${base}/${path}`, { params })).data;
}
export async function morPost<T>(path: string, body?: object): Promise<T> {
  return (await apiClient.post<T>(`${base}/${path}`, body ?? {})).data;
}
export function morError(error: unknown): string {
  if (axios.isAxiosError(error)) {
    const data = error.response?.data;
    const detail = data?.detail;
    if (typeof detail === "string") {
      try {
        const parsed = JSON.parse(detail);
        return parsed.message ?? parsed.Message ?? detail;
      } catch {
        return detail;
      }
    }
    return data?.message ?? data?.title ?? error.message;
  }
  return error instanceof Error
    ? error.message
    : "Unable to complete the request.";
}
export function money(value: number | string | undefined, currency = "USD") {
  if (value === undefined || value === null || !Number.isFinite(Number(value)))
    return "—";
  return `${Number(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${currency}`;
}
export function date(value?: string) {
  return value ? new Date(value).toLocaleString() : "—";
}
export function cardsReady(kyb?: Kyb | null) {
  return (
    kyb?.status?.toUpperCase() === "PASSED" &&
    !!kyb.companyCardholderId &&
    ["ACTIVE", "APPROVED", "PASSED"].includes(
      kyb.companyCardholderStatus?.trim().toUpperCase() ?? "",
    )
  );
}

export function morUserName(user: MorUser) {
  return (
    user.name ||
    [user.firstName, user.lastName].filter(Boolean).join(" ") ||
    user.email
  );
}
