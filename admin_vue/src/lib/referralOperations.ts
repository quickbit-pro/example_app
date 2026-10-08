import { apiClient } from "./apiClient";
/** Normalize DTO property casing while preserving dictionary keys such as locale IDs and audited field paths. */
export function normalizeOperation<T>(value: unknown, dictionary = false): T {
  if (Array.isArray(value))
    return value.map((item) => normalizeOperation(item)) as T;
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => {
        const property = key.charAt(0).toUpperCase() + key.slice(1);
        const preserveChildren = [
          "TermsByLocale",
          "Changes",
          "BeneficiaryBalances",
        ].includes(property);
        return [
          dictionary ? key : property,
          normalizeOperation(item, preserveChildren),
        ];
      }),
    ) as T;
  }
  return value as T;
}
export const referralRoot = "/api/v1/admin/referrals";
export const programPath = (id: string) =>
  `/programs/${encodeURIComponent(id)}`;
export async function referralGet<T>(
  path: string,
  params: object = {},
): Promise<T> {
  return normalizeOperation<T>(
    (await apiClient.get(referralRoot + path, { params })).data,
  );
}
export async function referralSend<T>(
  method: "POST" | "PUT" | "PATCH",
  path: string,
  data: unknown,
): Promise<T> {
  return normalizeOperation<T>(
    (await apiClient.request({ method, url: referralRoot + path, data })).data,
  );
}
export async function referralDownload(
  path: string,
  params: object,
  filename: string,
) {
  const response = await apiClient.get(referralRoot + path, {
    params,
    responseType: "blob",
  });
  const url = URL.createObjectURL(response.data);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
export function displayDate(value?: string | null): string {
  return value ? new Date(value).toLocaleString() : "—";
}
export function humanLabel(value: string): string {
  return value
    .replace(/_/g, " ")
    .toLowerCase()
    .replace(/^./, (c) => c.toUpperCase());
}
export function localDateTime(value = new Date()): string {
  return new Date(value.getTime() - value.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);
}
export function utc(value: string): string {
  if (!value || !Number.isFinite(Date.parse(value)))
    throw new Error("Enter a valid date and time.");
  return new Date(value).toISOString();
}
export interface SupportIdentity {
  Id: number;
  Name: string;
  Email: string;
}
export interface RelationshipRow {
  Id: string;
  Cursor: number;
  ProgramId: string;
  ProgramName: string;
  Inviter: SupportIdentity;
  Friend: SupportIdentity;
  Status: string;
  Stage: string;
  AttributionSource: string;
  AttributedAt: string;
  QualifiedAt: string | null;
  EarningWindowEndsAt: string | null;
  MissingConditions: string[];
  ProtectedOffer: boolean;
  OfferVersionId: string | null;
}
export interface RelationshipPage {
  Items: RelationshipRow[];
  NextCursor: number | null;
}
export interface Condition {
  Code: string;
  Label: string;
  Required: boolean;
  Met: boolean;
  MetAt: string | null;
  Evidence: string | null;
}
export interface RelationshipDetail {
  Relationship: RelationshipRow;
  Conditions: Condition[];
  Events: {
    EventType: string;
    SourceEventKey: string;
    OccurredAt: string;
    Amount: number;
    Currency: string;
    FundingSource: string | null;
    Status: string;
    ExcludedReason: string | null;
  }[];
  TermsVersionAccepted: number | null;
  AcceptedAt: string | null;
  CampaignLinkId: string | null;
  EligibleVolumeTotal: number;
  ReservedExposure: number;
  AsOf: string;
}
export const relationshipApi = {
  list: (query: object) =>
    referralGet<RelationshipPage>("/relationships", query),
  detail: (id: string) =>
    referralGet<RelationshipDetail>(`/relationships/${encodeURIComponent(id)}`),
  support: async (id: string, query: object) =>
    normalizeOperation<RelationshipPage>(
      (
        await apiClient.get(
          `/api/v1/admin/customers/${encodeURIComponent(id)}/referrals`,
          { params: query },
        )
      ).data,
    ),
};
export interface RiskPolicy {
  SignupSignalsEnabled: boolean;
  ProgramId: string;
  Revision: number;
  PayoutHoldDays: number;
  DailyAttributionLimit: number | null;
  AutomaticClawbackEnabled: boolean;
  DayBoundary: string;
  SupportedDeliveryModes: string[];
  SignalAvailability: { Signal: string; Status: string; Detail: string }[];
}
export interface RiskReview {
  Id: string;
  ProgramId: string;
  RelationshipId: string;
  InviterUserId: number;
  FriendUserId: number;
  Status: string;
  Revision: number;
  CreatedAt: string;
  UpdatedAt: string;
  Signals: {
    Id: string;
    Reason: string;
    Source: string;
    OccurredAt: string;
    AcknowledgedAt: string | null;
  }[];
}
export interface BulkRow {
  Row: number;
  Action: string;
  UserId: number | null;
  Status: string;
  ErrorCode: string | null;
  Message: string | null;
}
export interface BulkPreview {
  Id: string;
  ProgramId: string;
  ProgramRevision: number;
  PayloadHash: string;
  ExpiresAt: string;
  Status: string;
  ExecutedAt: string | null;
  Rows: BulkRow[];
}
/** Only explicitly selected, valid rows may be submitted from a partially invalid file. */
export function selectedBulkRows(
  rows: BulkRow[],
  selected: number[],
): number[] {
  return rows
    .filter((r) => r.Status === "VALID" && selected.includes(r.Row))
    .map((r) => r.Row);
}
export function csvTemplate(action: string): string {
  return action === "LEVEL_ASSIGNMENT"
    ? "action,user_id,level_id,expires_at,notes\nLEVEL_ASSIGNMENT,,,,\n"
    : action === "INVITE_BENEFIT"
      ? "action,user_id,referred_tier_id,discount_code_id,inherit_benefits\nINVITE_BENEFIT,,,,false\n"
      : action.startsWith("EXPIRE_")
        ? `action,user_id,notes\n${action},,\n`
        : "action,user_id,active,approve,expires_at,notes\nMEMBERSHIP,,true,false,,\n";
}
