import { apiClient } from '@/lib/apiClient';

export interface CurrencyAmount {
  amount: number;
  currency: string;
}

export interface AttentionItem {
  ageHours: number;
  customerId: string;
  customerName: string;
  customerType: 'business' | 'individual';
  priority: number;
  reason: string;
  tone: 'danger' | 'warning';
}

/** A count now and in the equally long period before. */
export interface Metric {
  current: number;
  previous: number;
}

/** A USD amount (stablecoins at 1:1) and its row count, now and in the previous period. */
export interface AmountMetric {
  amount: number;
  count: number;
  previousAmount: number;
  previousCount: number;
}

export interface AmountCount {
  amount: number;
  count: number;
}

export interface FeeTypeRow {
  amount: number;
  count: number;
  label: string;
  type: string;
}

export interface DailyKpi {
  approvals: number;
  date: string;
  declinedAmount: number;
  declines: number;
  deposits: number;
  fees: number;
  signups: number;
  spend: number;
  withdrawals: number;
}

export interface SegmentRow {
  approved: number;
  customers: number;
  fees: number;
  funded: number;
  key: string;
  spend: number;
  transacting: number;
}

export interface Cohort {
  size: number;
  weekStart: string;
  weeks: { active: number; offset: number; rate: number | null }[];
}

/** GET /api/v1/admin/overview — KPIs from the classified transaction ledger, test accounts excluded. */
export interface OverviewData {
  attention: AttentionItem[];
  balances: CurrencyAmount[];
  cards: {
    activeCardholders: Metric;
    averageTicket: number | null;
    cash: AmountCount;
    checks: number;
    declineRate: number | null;
    declines: AmountCount;
    previousDeclineRate: number | null;
    spend: AmountMetric;
  };
  cohorts: Cohort[];
  declines: {
    byCard: { count: number; lastFour: string }[];
    byMerchant: { amount: number; attempts: number; declined: number; name: string; rate: number | null }[];
    byReason: { count: number; reason: string }[];
  };
  freshness: {
    errorCustomers: number;
    staleCustomers: number;
    state: 'current' | 'stale' | 'warning';
  };
  from: string;
  funnel: { key: string; label: string; value: number }[];
  /** When the server computed these figures; `updatedAt` is the oldest customer refresh behind them. */
  generatedAt: string;
  kpis: {
    activationRate: number | null;
    activeCards: number;
    approvals: Metric;
    approvedCustomers: number;
    cardsIssued: Metric;
    customers: number;
    engagedCustomers: number;
    fundedCustomers: number;
    newCustomers: Metric;
    transactingCustomers: Metric;
    verifiedRate: number;
  };
  money: {
    conversions: number;
    deposits: AmountMetric;
    fundsHeld: number;
    netDeposits: number;
    transfers: AmountCount;
    unconvertedCurrencies: string[];
    withdrawals: AmountMetric;
  };
  previousFrom: string;
  rangeDays: number;
  reportingCurrency: string;
  revenue: {
    byType: FeeTypeRow[];
    fees: AmountMetric;
    onDeclinedPayments: AmountCount;
    perActiveCardholder: number | null;
    perTransactingCustomer: number | null;
  };
  segments: { appVersion: SegmentRow[]; country: SegmentRow[]; platform: SegmentRow[]; source: SegmentRow[] };
  series: DailyKpi[];
  stages: { count: number; stage: string }[];
  support: { awaiting: number; oldestWaitingHours: number | null };
  testCustomers: number;
  /** IANA zone that decides where a reporting day starts. */
  timeZone: string;
  to: string;
  topMerchants: { amount: number; count: number; name: string }[];
  updatedAt: string | null;
  verificationAging: {
    over24Hours: number;
    pending: number;
    rejected: number;
  };
}

export interface CustomerRow {
  accountStatus: string;
  activeCards: number;
  attentionReason: string | null;
  attentionTone: string | null;
  balances: CurrencyAmount[];
  customerId: string;
  customerType: 'business' | 'individual';
  email: string;
  lastActivityAt: string | null;
  lastSyncedAt: string | null;
  name: string;
  onboardingStatus: string;
  onboardingStep: string;
  phone: string | null;
  totalCards: number;
  verificationStatus: string;
  /** Internal and test accounts are left out of the Overview KPIs. */
  isTestAccount: boolean;
  /** Where the customer is in the journey, see lib/customerStages.ts. */
  stage: string;
}

export interface CustomerListResponse {
  attentionCount: number;
  items: CustomerRow[];
  /** Counts per stage under every other filter, for the stage chips. */
  stageCounts?: { count: number; stage: string }[];
  totalCount: number;
}

export interface InsightItem {
  area: 'customers' | 'money' | 'cards' | 'revenue' | 'operations';
  detail: string;
  link: string | null;
  title: string;
  tone: 'good' | 'bad' | 'neutral';
}

/** GET /api/v1/admin/insights — briefing written by the configured model, or by fixed rules as a fallback. */
export interface InsightsResponse {
  generatedAt: string;
  headline: string;
  items: InsightItem[];
  model: string | null;
  notice: string | null;
  rangeDays: number;
  source: 'ai' | 'rules';
}

export interface ReminderPreview {
  appUrlConfigured: boolean;
  cooldownDays: number;
  recipients: number;
  sampleNames: string[];
  skipped: { emailNotConfirmed: number; locked: number; overLimit: number; recentlyReminded: number; testAccounts: number };
  stage: string;
  subject: string;
  templateEnabled: boolean;
  templateKey: string;
  templateName: string;
}

export interface ReportingSettings {
  suggestedTimeZones: string[];
  timeZone: string;
}

export interface AccountRow {
  accountReference: string | null;
  balance: number | null;
  currency: string | null;
  maskedNumber: string | null;
  name: string;
  reference: string;
  resourceType: string | null;
  status: string;
  transactionReference: string | null;
}

export interface CardRow {
  activatedAt: string | null;
  balance: number | null;
  budgetReference: string | null;
  currency: string | null;
  /** Only some providers report an expiry; the UI shows it when present. */
  expiresAt?: string | null;
  issuedAt: string | null;
  lastFour: string;
  reference: string;
  status: string;
  type: string;
}

/** One classified ledger row. `direction` is relative to the customer; `internal` moves their own money. */
export interface TransactionRow {
  accountReference: string | null;
  amount: number;
  budgetReference: string | null;
  cardReference: string | null;
  currency: string;
  description: string;
  direction: 'in' | 'out' | 'internal' | 'none';
  feeType: string | null;
  /** False for related provider legs; these are listed but never summed. */
  isPrimary: boolean;
  /** A second provider view of a movement another row already reports. */
  isDuplicate: boolean;
  kind: string;
  merchant: string | null;
  occurredAt: string;
  rawStatus: string;
  reference: string;
  status: 'completed' | 'pending' | 'failed' | 'other';
}

export interface CustomerDetail {
  accounts: AccountRow[];
  balances: CurrencyAmount[];
  cards: CardRow[];
  customer: CustomerRow;
  onboarding: {
    completedAt: string | null;
    currentStep: string;
    startedAt: string | null;
    status: string;
    updatedAt: string | null;
  };
  recentTransactions: TransactionRow[];
  referenceDetails: {
    localCustomerId: string;
    providerCustomerId: string | null;
  };
  support: {
    attentionReason: string | null;
    dataMessage: string | null;
    dataState: 'current' | 'needs_retry';
    lastSyncedAt: string | null;
  };
  verification: {
    countryCode?: string;
    level?: string;
    reviewedAt?: string | null;
    status?: string;
    submittedAt?: string | null;
    type?: 'kyb' | 'kyc';
  };
}

export interface VerificationResponse {
  items: {
    customerId: string;
    customerName: string;
    customerType: string;
    email: string;
    level: string | null;
    reviewedAt: string | null;
    status: string;
    submittedAt: string | null;
    verificationType: string;
  }[];
  over24Hours: number;
  pendingCount: number;
  totalCount: number;
}

export interface MoneyResponse {
  activity: {
    currency: string;
    inflow: number;
    internal: number;
    outflow: number;
    transactionCount: number;
  }[];
  balances: CurrencyAmount[];
  customers: { id: string; name: string }[];
  filterOptions: { currencies: string[]; kinds: string[]; statuses: string[] };
  kinds: { amounts: CurrencyAmount[]; count: number; kind: string }[];
  limit: number;
  offset: number;
  rangeDays: number;
  recentTransactions: (TransactionRow & {
    customerId: string;
    customerName: string;
  })[];
  totalCount: number;
}

export interface CardPortfolioResponse {
  activeCount: number;
  customers: { id: string; name: string }[];
  filterOptions: { currencies: string[]; statuses: string[] };
  items: (CardRow & {
    customerId: string;
    customerName: string;
  })[];
  limit: number;
  offset: number;
  totalCount: number;
}

export interface MobileDesign {
  accentColor: string;
  appName: string;
  fontFamily: string;
  legalEntity: string;
  logoAsset: string;
  loginBackgroundColor: string;
  primaryColor: string;
  schemaVersion: number;
  supportEmail: string;
  supportPhone: string;
  themeMode: 'dark' | 'light' | 'system';
  updatedAt: string | null;
}

export interface EmailPlaceholder {
  description: string;
  name: string;
  required: boolean;
  sample: string;
}

export interface EmailTemplate {
  description: string;
  htmlBody: string;
  isCustomized: boolean;
  isEnabled: boolean;
  key: string;
  name: string;
  placeholders: EmailPlaceholder[];
  subject: string;
  textBody: string;
  updatedAt: string | null;
}

export interface EmailDeliveryStatus {
  configured: boolean;
  fromEmail: string;
  fromName: string;
  provider: string;
  replyToEmail: string | null;
}

export interface EmailTemplateListResponse {
  delivery: EmailDeliveryStatus;
  templates: EmailTemplate[];
}

export interface EmailTemplateDraft {
  htmlBody: string;
  isEnabled: boolean;
  subject: string;
  textBody: string;
}

export interface EmailPreview {
  htmlBody: string;
  subject: string;
  textBody: string;
}

export interface EmailMessageRow {
  attemptCount: number;
  createdAt: string;
  errorMessage: string | null;
  id: string;
  sentAt: string | null;
  status: string;
  subject: string;
  templateKey: string;
  toEmail: string;
}

export interface EmailMessageListResponse {
  items: EmailMessageRow[];
  totalCount: number;
}

export interface SupportSignInMethod {
  emailAtProvider: string | null;
  isPrimary: boolean;
  lastAuthenticatedAt: string | null;
  provider: string;
}

export interface SupportAccountLock {
  canUnlockNow: boolean;
  lockReason: string | null;
  lockedAt: string;
  unlockAvailableAt: string | null;
}

export interface SupportAccount {
  createdAt: string;
  displayName: string;
  email: string;
  emailVerifiedAt: string | null;
  lastLoginAt: string | null;
  locale: string | null;
  lock: SupportAccountLock | null;
  passwordChangedAt: string | null;
  phone: string | null;
  signInMethods: SupportSignInMethod[];
  status: string;
  timeZone: string | null;
  twoFactorEnabled: boolean;
  twoFactorEnabledAt: string | null;
}

export interface SupportSession {
  createdAt: string;
  deviceName: string | null;
  expiresAt: string;
  id: string;
  ipAddress: string | null;
  lastUsedAt: string | null;
  revocationReason: string | null;
  revokedAt: string | null;
  userAgent: string | null;
}

export interface SupportDevice {
  appVersion: string | null;
  id: string;
  isEnabled: boolean;
  lastSeenAt: string | null;
  locale: string | null;
  platform: string;
}

export interface SupportTicketSummary {
  createdAt: string;
  id: string;
  lastMessageAt: string | null;
  lastMessageFromAdmin: boolean;
  messageCount: number;
  status: string;
  subject: string;
  updatedAt: string;
}

export interface SupportNotification {
  attemptCount: number;
  createdAt: string;
  errorMessage: string | null;
  eventType: string | null;
  id: string;
  kind: 'email' | 'push';
  readAt: string | null;
  sentAt: string | null;
  status: string;
  templateKey: string | null;
  title: string;
}

export interface SupportPeerTransfer {
  amount: number;
  completedAt: string | null;
  counterpartyName: string | null;
  createdAt: string;
  currency: string;
  direction: 'received' | 'sent';
  errorCode: string | null;
  errorMessage: string | null;
  externalReferenceId: string | null;
  id: string;
  note: string | null;
  status: string;
}

export interface SupportVerificationRecord {
  businessName: string | null;
  countryCode: string | null;
  expiresAt: string | null;
  id: string;
  level: string | null;
  provider: string | null;
  providerReference: string | null;
  reviewedAt: string | null;
  startedAt: string | null;
  status: string;
  submittedAt: string | null;
  type: 'kyb' | 'kyc';
}

export interface SupportOnboardingApplication {
  completedAt: string | null;
  createdAt: string;
  currentStep: string | null;
  id: string;
  kind: string;
  status: string;
  submittedAt: string | null;
  updatedAt: string | null;
  workflowVersion: number | null;
}

export interface SupportAuditEntry {
  action: string;
  entityId: string | null;
  entityType: string | null;
  id: string;
  ipAddress: string | null;
  occurredAt: string;
  userAgent: string | null;
}

export interface SupportApiFailure {
  appMethod: string | null;
  appPath: string | null;
  appStatusCode: number | null;
  failureCode: string | null;
  failureMessage: string | null;
  hoppaDurationMs: number | null;
  hoppaEndpoint: string | null;
  hoppaMethod: string | null;
  hoppaStatusCode: number | null;
  id: string;
  occurredAt: string;
  traceId: string | null;
}

/** GET /api/v1/admin/customers/{id}/support — everything a support agent needs beside the customer detail. */
export interface CustomerSupportData {
  account: SupportAccount;
  activity30d: {
    completedTransactionCount: number;
    inflow: CurrencyAmount[];
    lastActivityAt: string | null;
    lastTransactionAt: string | null;
    outflow: CurrencyAmount[];
  };
  apiCalls: {
    failedLast24h: number;
    failedLast7d: number;
    recentFailures: SupportApiFailure[];
  };
  auditTrail: SupportAuditEntry[];
  devices: SupportDevice[];
  generatedAt: string;
  notifications: SupportNotification[];
  onboardingApplications: SupportOnboardingApplication[];
  peerTransfers: SupportPeerTransfer[];
  sessions: { activeCount: number; items: SupportSession[] };
  tickets: { awaitingSupportCount: number; items: SupportTicketSummary[]; totalCount: number };
  verificationHistory: SupportVerificationRecord[];
}

/** 409 body of POST /api/v1/admin/accounts/{id}/unlock while the cooling-off period is still running. */
export interface UnlockConflict {
  message: string;
  unlockAvailableAt: string | null;
}

export const operationsApi = {
  async overview(range: number) {
    return (await apiClient.get<OverviewData>('/api/v1/admin/overview', { params: { range } })).data;
  },
  async customers(params: Record<string, unknown>) {
    return (await apiClient.get<CustomerListResponse>('/api/v1/admin/customers', { params })).data;
  },
  async customer(customerId: string) {
    return (await apiClient.get<CustomerDetail>(`/api/v1/admin/customers/${customerId}`)).data;
  },
  /** Re-syncs card holders (oldest snapshot first, `limit` per call) or one customer; loop while `remaining` > 0. */
  async refreshCards(params: { customerId?: string; limit?: number } = {}) {
    return (await apiClient.post<{ refreshed: number; failed: number; remaining: number; total?: number; refreshedAt: string }>('/api/v1/admin/card-portfolio/refresh', null, { params })).data;
  },
  async insights(range: number, refresh = false) {
    return refresh
      ? (await apiClient.post<InsightsResponse>('/api/v1/admin/insights/refresh', null, { params: { range } })).data
      : (await apiClient.get<InsightsResponse>('/api/v1/admin/insights', { params: { range } })).data;
  },
  async reportingSettings() {
    return (await apiClient.get<ReportingSettings>('/api/v1/admin/reporting-settings')).data;
  },
  async saveReportingSettings(timeZone: string) {
    return (await apiClient.put<ReportingSettings>('/api/v1/admin/reporting-settings', { timeZone })).data;
  },
  async previewReminder(stage: string) {
    return (await apiClient.post<ReminderPreview>('/api/v1/admin/customer-reminders/preview', { stage, expectedRecipients: 0 })).data;
  },
  async sendReminder(stage: string, expectedRecipients: number) {
    return (await apiClient.post<{ queued: number; stage: string; templateKey: string }>('/api/v1/admin/customer-reminders/send', { stage, expectedRecipients })).data;
  },
  async setTestAccount(customerId: string, isTestAccount: boolean) {
    return (await apiClient.put<{ customerId: string; isTestAccount: boolean }>(`/api/v1/admin/customers/${customerId}/test-account`, { isTestAccount })).data;
  },
  async refreshCustomer(customerId: string) {
    return (await apiClient.post(`/api/v1/admin/customers/${customerId}/refresh`)).data;
  },
  async customerSupport(customerId: string) {
    return (await apiClient.get<CustomerSupportData>(`/api/v1/admin/customers/${customerId}/support`)).data;
  },
  async unlockAccount(customerId: string) {
    return (await apiClient.post<{ message?: string }>(`/api/v1/admin/accounts/${customerId}/unlock`)).data;
  },
  async verifications(params: Record<string, unknown>) {
    return (await apiClient.get<VerificationResponse>('/api/v1/admin/verifications', { params })).data;
  },
  async money(params: Record<string, unknown>) {
    return (await apiClient.get<MoneyResponse>('/api/v1/admin/money', { params })).data;
  },
  async cards(params: Record<string, unknown>) {
    return (await apiClient.get<CardPortfolioResponse>('/api/v1/admin/card-portfolio', { params })).data;
  },
  async mobileDesign() {
    return (await apiClient.get<MobileDesign>('/api/v1/admin/mobile-design')).data;
  },
  async saveMobileDesign(design: Omit<MobileDesign, 'schemaVersion' | 'updatedAt'>) {
    return (await apiClient.put<MobileDesign>('/api/v1/admin/mobile-design', design)).data;
  },
  async exportMobileDesign() {
    return (
      await apiClient.get<Blob>('/api/v1/admin/mobile-design/export', {
        responseType: 'blob',
      })
    ).data;
  },
  async emailTemplates() {
    return (await apiClient.get<EmailTemplateListResponse>('/api/v1/admin/email-templates')).data;
  },
  async saveEmailTemplate(key: string, draft: EmailTemplateDraft) {
    return (await apiClient.put<EmailTemplate>(`/api/v1/admin/email-templates/${encodeURIComponent(key)}`, draft)).data;
  },
  async resetEmailTemplate(key: string) {
    return (await apiClient.post<EmailTemplate>(`/api/v1/admin/email-templates/${encodeURIComponent(key)}/reset`)).data;
  },
  async previewEmailTemplate(key: string, draft: Pick<EmailTemplateDraft, 'htmlBody' | 'subject' | 'textBody'>) {
    return (await apiClient.post<EmailPreview>(`/api/v1/admin/email-templates/${encodeURIComponent(key)}/preview`, draft)).data;
  },
  async sendTestEmail(key: string, toEmail: string, draft: Pick<EmailTemplateDraft, 'htmlBody' | 'subject' | 'textBody'>) {
    return (
      await apiClient.post<EmailMessageRow>(`/api/v1/admin/email-templates/${encodeURIComponent(key)}/test`, {
        toEmail,
        ...draft,
      })
    ).data;
  },
  async emailMessages(params: { status?: string; take?: number; templateKey?: string }) {
    return (await apiClient.get<EmailMessageListResponse>('/api/v1/admin/email-messages', { params })).data;
  },
  async decideVerification(providerCustomerId: string, decision: 'approved' | 'rejected', reason: string) {
    return (
      await apiClient.post(`/api/v1/admin/kyc/cases/${encodeURIComponent(providerCustomerId)}/decisions`, {
        decision,
        reason,
      })
    ).data;
  },
};
