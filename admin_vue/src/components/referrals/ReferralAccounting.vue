<script setup lang="ts">
import { ref, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  referralSend,
  referralDownload,
  displayDate,
  localDateTime,
  utc,
} from "@/lib/referralOperations";
const props = defineProps<{ programId: string; currency: string }>();
const month = ref(new Date().toISOString().slice(0, 7)),
  currency = ref(props.currency),
  asOf = ref(""),
  kind = ref("ledger"),
  status = ref(""),
  from = ref(""),
  to = ref(""),
  busy = ref(false),
  error = ref(""),
  message = ref("");
type Report = {
  Month: string;
  Currency: string;
  PeriodStart: string;
  PeriodEndExclusive: string;
  AsOf: string;
  IsComplete: boolean;
  IsRestated: boolean;
  OpeningEarnedBalance: number | null;
  Accrued: number;
  EntitlementAdjustments: number;
  ActualCashPaid: number;
  Offsets: number;
  ClosingEarnedBalance: number | null;
  OpeningReservedExposure: number | null;
  ReservationMovement: number;
  ClosingReservedExposure: number | null;
  UnearnedReservedExposure: number | null;
  ClosingEarnedLiability: number | null;
  ClosingRecoveryReceivable: number | null;
  Warnings: string[];
  Programs: {
    ProgramId: string;
    ProgramName: string;
    OpeningReconciled: boolean;
    Accrued: number;
    ActualCashPaid: number;
    ClosingEarnedBalance: number | null;
    ClosingReservedExposure: number | null;
    LateRecordedMovements: number;
  }[];
};
const report = ref<Report | null>(null);
const opening = ref({
    at: localDateTime(),
    earned: "",
    reserved: "",
    evidence: "",
  }),
  balances = ref<{ user: string; balance: string }[]>([]),
  confirmed = ref(false);
const labels: { key: keyof Report; label: string }[] = [
  { key: "OpeningEarnedBalance", label: "Opening net earned balance" },
  { key: "Accrued", label: "Accrued entitlement" },
  { key: "EntitlementAdjustments", label: "Entitlement adjustments" },
  { key: "ActualCashPaid", label: "Actual cash paid" },
  { key: "Offsets", label: "Offsets" },
  { key: "ClosingEarnedBalance", label: "Closing net earned balance" },
  { key: "ClosingEarnedLiability", label: "Closing rewards owed" },
  { key: "ClosingRecoveryReceivable", label: "Closing recovery receivable" },
  { key: "OpeningReservedExposure", label: "Opening reserved exposure" },
  { key: "ReservationMovement", label: "Reservation movement" },
  { key: "ClosingReservedExposure", label: "Closing reserved exposure" },
  { key: "UnearnedReservedExposure", label: "Unearned reserved exposure" },
];
function amount(value: unknown) {
  return value == null
    ? "Unknown"
    : `${Number(value).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 8 })} ${report.value?.Currency || currency.value}`;
}
async function load() {
  busy.value = true;
  error.value = "";
  try {
    report.value = await referralGet<Report>("/accounting/monthly", {
      programId: props.programId,
      month: month.value,
      currency: currency.value,
      asOf: asOf.value ? utc(asOf.value) : undefined,
    });
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function download() {
  busy.value = true;
  error.value = "";
  try {
    await referralDownload(
      `/exports/${kind.value}`,
      {
        programId: props.programId,
        currency: currency.value,
        status: status.value || undefined,
        from: from.value ? utc(from.value) : undefined,
        to: to.value ? utc(to.value) : undefined,
      },
      `referrals-${kind.value}.csv`,
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function saveOpening() {
  busy.value = true;
  error.value = "";
  try {
    const entries = balances.value.map((b) => [b.user, Number(b.balance)]);
    if (new Set(entries.map((e) => e[0])).size !== entries.length)
      throw new Error("Each beneficiary may appear only once.");
    await referralSend("POST", "/accounting/openings", {
      ProgramId: props.programId,
      Currency: currency.value,
      OpeningAt: utc(opening.value.at),
      EarnedBalance: Number(opening.value.earned),
      ReservedExposure: Number(opening.value.reserved),
      Evidence: opening.value.evidence,
      BeneficiaryBalances: entries.length ? Object.fromEntries(entries) : null,
    });
    message.value = "Reconciled opening recorded. It is immutable.";
    confirmed.value = false;
    await load();
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
watch(
  () => props.programId,
  () => {
    report.value = null;
    confirmed.value = false;
  },
);
</script>
<template>
  <div class="space-y-4">
    <section class="panel p-5 space-y-4">
      <h2 class="panel-heading">Exports and monthly accounting</h2>
      <p class="text-sm text-slate-500">
        Actual cash is based on reconciled allocations. Unknown historical
        balances remain unknown until supported by opening evidence.
      </p>
      <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
      <p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
      <form class="flex gap-3 flex-wrap items-end" @submit.prevent="load">
        <label class="text-sm grid gap-1"
          >Month<input
            v-model="month"
            type="month"
            required
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Currency<input
            v-model="currency"
            maxlength="3"
            required
            class="field-control uppercase" /></label
        ><label class="text-sm grid gap-1"
          >Known as of (optional)<input
            v-model="asOf"
            type="datetime-local"
            class="field-control" /></label
        ><button class="primary-button" :disabled="busy">
          {{ busy ? "Working…" : "Load report" }}
        </button>
      </form>
      <template v-if="report"
        ><p class="text-sm">
          {{
            report.IsComplete
              ? "Reconciled report"
              : "Incomplete reconciliation"
          }}
          · {{ report.IsRestated ? "Restated" : "Original cutoff" }} · as of
          {{ displayDate(report.AsOf) }}
        </p>
        <p
          v-for="warning in report.Warnings"
          :key="warning"
          class="text-sm rounded-lg bg-amber-50 p-3 text-amber-900"
        >
          {{ warning }}
        </p>
        <dl class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div v-for="item in labels" :key="item.key" class="metric-card">
            <dt class="text-sm text-slate-500">{{ item.label }}</dt>
            <dd class="font-semibold mt-1">{{ amount(report[item.key]) }}</dd>
          </div>
        </dl>
        <div class="overflow-x-auto">
          <table class="data-table min-w-[650px]">
            <thead>
              <tr>
                <th>Program</th>
                <th>Opening evidence</th>
                <th>Accrued</th>
                <th>Cash paid</th>
                <th>Closing earned / reserved</th>
                <th>Late records</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in report.Programs" :key="p.ProgramId">
                <td>{{ p.ProgramName }}</td>
                <td>{{ p.OpeningReconciled ? "Reconciled" : "Missing" }}</td>
                <td>{{ amount(p.Accrued) }}</td>
                <td>{{ amount(p.ActualCashPaid) }}</td>
                <td>
                  {{ amount(p.ClosingEarnedBalance) }} /
                  {{ amount(p.ClosingReservedExposure) }}
                </td>
                <td>{{ p.LateRecordedMovements }}</td>
              </tr>
            </tbody>
          </table>
        </div></template
      >
    </section>
    <section class="panel p-5 space-y-4">
      <h3 class="panel-heading">CSV export</h3>
      <form class="flex flex-wrap gap-3 items-end" @submit.prevent="download">
        <label class="text-sm grid gap-1"
          >Data<select v-model="kind" class="field-control">
            <option value="ledger">Earnings ledger</option>
            <option value="credits">Credits</option>
            <option value="relationships">Relationships</option>
          </select></label
        ><label class="text-sm grid gap-1"
          >Status (optional)<input
            v-model="status"
            class="field-control"
            placeholder="e.g. PAID" /></label
        ><label class="text-sm grid gap-1"
          >From<input
            v-model="from"
            type="datetime-local"
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >To (exclusive)<input
            v-model="to"
            type="datetime-local"
            class="field-control" /></label
        ><button class="secondary-button" :disabled="busy">Download CSV</button>
      </form>
      <p class="text-xs text-slate-500">
        Uses the selected program and currency. The export includes its server
        cutoff and all matching rows.
      </p>
    </section>
    <details class="panel p-5">
      <summary class="cursor-pointer font-semibold">
        Record a reconciled opening
      </summary>
      <p class="text-sm text-amber-900 mt-3">
        For accounting staff with verified records. An opening is immutable and
        must be supported by evidence. Do not use zero for an unknown balance.
      </p>
      <form @submit.prevent="saveOpening" class="space-y-3 mt-4">
        <div class="grid sm:grid-cols-3 gap-3">
          <label class="text-sm grid gap-1"
            >Opening at<input
              v-model="opening.at"
              type="datetime-local"
              required
              class="field-control" /></label
          ><label class="text-sm grid gap-1"
            >Signed net earned balance<input
              v-model="opening.earned"
              type="number"
              step="any"
              required
              class="field-control" /></label
          ><label class="text-sm grid gap-1"
            >Reserved exposure<input
              v-model="opening.reserved"
              type="number"
              min="0"
              step="any"
              required
              class="field-control"
          /></label>
        </div>
        <label class="text-sm grid gap-1"
          >Evidence reference<textarea
            v-model="opening.evidence"
            required
            rows="3"
            class="field-control"
          />
        </label>
        <p class="text-sm text-slate-500">
          Optional beneficiary balances distinguish gross liability from
          recovery debt; their sum must equal the net earned balance.
        </p>
        <div v-for="(row, i) in balances" :key="i" class="flex flex-wrap gap-2">
          <label class="text-sm"
            >User ID<input
              v-model="row.user"
              type="number"
              min="1"
              required
              class="field-control" /></label
          ><label class="text-sm"
            >Signed balance<input
              v-model="row.balance"
              type="number"
              step="any"
              required
              class="field-control" /></label
          ><button
            type="button"
            class="secondary-button"
            @click="balances.splice(i, 1)"
          >
            Remove
          </button>
        </div>
        <button
          type="button"
          class="secondary-button"
          @click="balances.push({ user: '', balance: '' })"
        >
          Add beneficiary balance</button
        ><label class="flex gap-2 text-sm"
          ><input v-model="confirmed" type="checkbox" required /> I verified the
          opening amounts and understand this record cannot be edited.</label
        ><button
          class="primary-button"
          :disabled="busy || !confirmed || !opening.evidence.trim()"
        >
          Record opening
        </button>
      </form>
    </details>
  </div>
</template>
