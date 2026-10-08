export type AdminResourceKey = 'users';

export type AdminCellType =
  | 'currency'
  | 'date'
  | 'datetime'
  | 'number'
  | 'status'
  | 'text';

export type AdminRowValue = boolean | number | string | null | undefined;
export type AdminRow = Record<string, AdminRowValue>;

export interface AdminColumn {
  field: string;
  header: string;
  type?: AdminCellType;
}

export interface SourceOperation {
  method: 'DELETE' | 'GET' | 'POST' | 'PUT';
  path: string;
}

export interface AdminResourceDefinition {
  columns: AdminColumn[];
  description: string;
  endpoint: string;
  exportEndpoint?: string;
  filters?: {
    field: string;
    label: string;
    options: string[];
  }[];
  key: AdminResourceKey;
  primaryField: string;
  sampleRows: AdminRow[];
  sourceOperations: SourceOperation[];
  supportsList?: boolean;
  title: string;
  userScoped?: boolean;
}

export interface AdminNavItem {
  description?: string;
  icon: string;
  isPrimary?: boolean;
  label: string;
  section: AdminNavSection;
  to: string;
}

export type AdminNavSection =
  | 'Customer Operations'
  | 'Risk & Compliance'
  | 'Money Movement'
  | 'Observability';

export interface AdminNavGroup {
  description: string;
  icon: string;
  items: AdminNavItem[];
  label: AdminNavSection;
}

export interface DailySeries {
  labels: string[];
  values: number[];
}

export interface KycReviewSeries {
  labels: string[];
  approved: number[];
  rejected: number[];
  manualReview: number[];
}

export interface WebhookSeries {
  labels: string[];
  succeeded: number[];
  failed: number[];
}

export interface CategoryCount {
  count: number;
  eventType?: string;
  status?: string;
}

export interface OverviewCharts {
  cardStatusBreakdown: CategoryCount[];
  cardsIssued: DailySeries;
  kycReviews: KycReviewSeries;
  kycStatusBreakdown: CategoryCount[];
  signups: DailySeries;
  webhookEventTypes: CategoryCount[];
  webhooks: WebhookSeries;
  windowDays: number;
}

export interface OnboardingFunnelStage {
  count: number;
  key: string;
  label: string;
  percent: number;
}

export interface OnboardingBreakdown {
  count: number;
  status?: string;
  step?: string;
}

export interface OnboardingApplicant {
  ageHours: number;
  attentionReason: string;
  currentStep: string;
  email: string;
  id: string | null;
  kind: string;
  kycStatus: string;
  lastActivityAt: string;
  name: string;
  needsAttention: boolean;
  registeredAt: string;
  status: string;
  userId: string;
}

export interface OnboardingOverview {
  applicants: OnboardingApplicant[];
  cohortLabel: string;
  completed: number;
  completionRate: number;
  funnel: OnboardingFunnelStage[];
  inProgress: number;
  medianCompletionHours: number | null;
  needsAttention: number;
  registered: number;
  started: number;
  statusBreakdown: OnboardingBreakdown[];
  stepBreakdown: OnboardingBreakdown[];
}

export interface OverviewData {
  activity: AdminRow[];
  charts?: OverviewCharts;
  metrics: {
    label: string;
    tone: 'danger' | 'neutral' | 'success' | 'warning';
    trend: string;
    value: string;
  }[];
  onboarding: OnboardingOverview;
  queues: AdminRow[];
  riskSignals: AdminRow[];
}

export const adminNavItems: AdminNavItem[] = [
  {
    description: 'Onboarding progress, drop-off, and customers needing help',
    icon: 'pi pi-chart-line',
    isPrimary: true,
    label: 'Dashboard',
    section: 'Customer Operations',
    to: '/',
  },
  {
    description: 'Customer list with complete selected-user details',
    icon: 'pi pi-users',
    isPrimary: true,
    label: 'Users',
    section: 'Customer Operations',
    to: '/users',
  },
  {
    description: 'KYC verification cases and admin decisions',
    icon: 'pi pi-id-card',
    isPrimary: true,
    label: 'KYC Cases',
    section: 'Risk & Compliance',
    to: '/kyc',
  },
  {
    description: 'Issued cards with status, lifecycle, and decisions',
    icon: 'pi pi-credit-card',
    isPrimary: true,
    label: 'Cards',
    section: 'Money Movement',
    to: '/cards',
  },
  {
    description: 'Account transactions across the platform',
    icon: 'pi pi-receipt',
    isPrimary: true,
    label: 'Transactions',
    section: 'Money Movement',
    to: '/transactions',
  },
  {
    description: 'Read-only audit log of admin actions',
    icon: 'pi pi-history',
    label: 'Audit Log',
    section: 'Observability',
    to: '/audit',
  },
  {
    description: 'Full app-to-Hoppa request and response traces',
    icon: 'pi pi-sitemap',
    label: 'Hoppa API Logs',
    section: 'Observability',
    to: '/hoppa-logs',
  },
];

export const adminNavGroups: AdminNavGroup[] = [
  {
    description: 'Onboarding performance and customer follow-up',
    icon: 'pi pi-users',
    items: adminNavItems.filter((item) => item.section === 'Customer Operations'),
    label: 'Customer Operations',
  },
  {
    description: 'KYC, KYB, and verification workload',
    icon: 'pi pi-shield',
    items: adminNavItems.filter((item) => item.section === 'Risk & Compliance'),
    label: 'Risk & Compliance',
  },
  {
    description: 'Cards, payments, transfers, and transactions',
    icon: 'pi pi-wallet',
    items: adminNavItems.filter((item) => item.section === 'Money Movement'),
    label: 'Money Movement',
  },
  {
    description: 'Audit, traces, and operational signals',
    icon: 'pi pi-eye',
    items: adminNavItems.filter((item) => item.section === 'Observability'),
    label: 'Observability',
  },
];

export const adminResources: Record<AdminResourceKey, AdminResourceDefinition> = {
  users: {
    columns: [
      { field: 'displayName', header: 'Name' },
      { field: 'email', header: 'Email' },
      { field: 'hoppaUserId', header: 'Hoppa ID' },
      { field: 'localUserId', header: 'Local ID' },
      { field: 'status', header: 'Status', type: 'status' },
      { field: 'kycStatus', header: 'KYC', type: 'status' },
      { field: 'tier', header: 'Tier' },
      { field: 'lastLoginAt', header: 'Last Login', type: 'datetime' },
    ],
    description: 'Customer table for search, account state, and detail review.',
    endpoint: '/api/v1/admin/users/summaries',
    filters: [{ field: 'status', label: 'Status', options: [] }],
    key: 'users',
    primaryField: 'displayName',
    sampleRows: [],
    sourceOperations: [
      { method: 'GET', path: '/api/v1/admin/users/summaries' },
      { method: 'GET', path: '/api/v1/admin/users/search' },
      { method: 'GET', path: '/api/v1/admin/users/lookup/{lookup}' },
      { method: 'GET', path: '/api/v2/users/{userId}' },
    ],
    title: 'Users',
  },
};
