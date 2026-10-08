<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  referralSend,
  programPath,
  displayDate,
  humanLabel,
  type RiskPolicy,
  type RiskReview,
} from "@/lib/referralOperations";
const props = defineProps<{ programId: string; deliveryMode: string }>();
const policy = ref<RiskPolicy | null>(null),
  rows = ref<RiskReview[]>([]),
  total = ref(0),
  page = ref(1),
  status = ref("FLAGGED"),
  busy = ref(false),
  error = ref(""),
  message = ref(""),
  reason = ref(""),
  decisionReason = ref(""),
  chosen = ref<RiskReview | null>(null),
  key = ref("");
const supported = computed(
  () =>
    policy.value?.SupportedDeliveryModes.includes(props.deliveryMode) ?? false,
);
async function load() {
  busy.value = true;
  error.value = "";
  try {
    const [p, reviews] = await Promise.all([
      referralGet<RiskPolicy>(`${programPath(props.programId)}/risk-policy`),
      referralGet<{ Items: RiskReview[]; Total: number }>("/reviews", {
        programId: props.programId,
        status: status.value,
        page: page.value,
        pageSize: 25,
      }),
    ]);
    policy.value = p;
    rows.value = reviews.Items;
    total.value = reviews.Total;
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function save() {
  if (!policy.value) return;
  busy.value = true;
  error.value = "";
  try {
    policy.value = await referralSend<RiskPolicy>(
      "PUT",
      `${programPath(props.programId)}/risk-policy`,
      {
        ExpectedRevision: policy.value.Revision,
        PayoutHoldDays: policy.value.PayoutHoldDays,
        DailyAttributionLimit:
          policy.value.DailyAttributionLimit == null ||
          String(policy.value.DailyAttributionLimit) === ""
            ? null
            : policy.value.DailyAttributionLimit,
        AutomaticClawbackEnabled: policy.value.AutomaticClawbackEnabled,
        SignupSignalsEnabled: policy.value.SignupSignalsEnabled ?? false,
        Reason: reason.value,
      },
    );
    message.value =
      "Risk policy saved. Existing accepted-policy rules are preserved.";
    reason.value = "";
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
function select(row: RiskReview) {
  chosen.value = row;
  decisionReason.value = "";
  key.value = crypto.randomUUID();
}
async function decide(decision: string) {
  if (!chosen.value) return;
  busy.value = true;
  error.value = "";
  try {
    await referralSend("POST", `/reviews/${chosen.value.Id}/decisions`, {
      Decision: decision,
      Reason: decisionReason.value,
      ExpectedRevision: chosen.value.Revision,
      IdempotencyKey: key.value,
    });
    chosen.value = null;
    message.value = `Review ${decision === "APPROVE" ? "approved" : "rejected"}. Other payment gates still apply.`;
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
    page.value = 1;
    chosen.value = null;
    load();
  },
  { immediate: true },
);
</script>
<template>
  <div class="space-y-4">
    <section class="panel p-5 space-y-4">
      <h2 class="panel-heading">Payout holds and risk policy</h2>
      <p class="text-sm text-slate-500">
        A risk review, time hold and reversal are separate payment gates.
        Approval clears the reviewed risk condition only.
      </p>
      <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
      <p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
      <p v-if="busy && !policy" role="status">Loading policy…</p>
      <form v-if="policy" class="space-y-3" @submit.prevent="save">
        <p v-if="!supported" class="text-sm text-amber-800">
          Risk controls are not available for {{ deliveryMode }} delivery.
          Supported: {{ policy.SupportedDeliveryModes.join(", ") || "none" }}.
        </p>
        <label class="flex gap-2 text-sm">
          <input
            v-model="policy.SignupSignalsEnabled"
            type="checkbox"
            :disabled="!supported"
          />
          Review matching signup IP/device signals
        </label>
        <p class="text-xs text-slate-500">
          Signal review requires configured company evidence hashing. Matches
          flag a relationship for review; they do not establish fraud.
        </p>
        <div class="grid sm:grid-cols-2 gap-3">
          <label class="text-sm grid gap-1"
            >Hold after qualification (days)<input
              v-model.number="policy.PayoutHoldDays"
              type="number"
              min="0"
              max="90"
              required
              class="field-control"
              :disabled="!supported" /></label
          ><label class="text-sm grid gap-1"
            >Attributions per inviter per day<input
              v-model.number="policy.DailyAttributionLimit"
              type="number"
              min="1"
              class="field-control"
              placeholder="Unlimited"
              :disabled="!supported"
          /></label>
        </div>
        <p class="text-sm text-slate-500">
          The hold ends at qualification plus this many days. Later recurring
          top-ups do not receive a new cooling period. Daily limit uses
          {{ policy.DayBoundary }}.
        </p>
        <label class="flex gap-2 text-sm"
          ><input
            v-model="policy.AutomaticClawbackEnabled"
            type="checkbox"
            :disabled="!supported"
          />
          Apply eligible reversal recovery against future rewards</label
        ><label class="text-sm grid gap-1"
          >Reason for this change<input
            v-model="reason"
            required
            maxlength="1000"
            class="field-control" /></label
        ><button
          class="primary-button"
          :disabled="busy || !supported || !reason.trim()"
        >
          Save policy
        </button>
        <p class="text-xs text-slate-500">
          Revision {{ policy.Revision }}. If another admin changes it, reload
          and review before trying again.
        </p>
      </form>
      <ul v-if="policy" class="grid gap-2 sm:grid-cols-2">
        <li
          v-for="signal in policy.SignalAvailability"
          :key="signal.Signal"
          class="bg-slate-50 p-3 rounded-lg text-sm"
        >
          <strong
            >{{ humanLabel(signal.Signal) }} ·
            {{ humanLabel(signal.Status) }}</strong
          >
          <p class="text-slate-500 mt-1">{{ signal.Detail }}</p>
        </li>
      </ul>
    </section>
    <section class="panel p-5 space-y-4">
      <h2 class="panel-heading">Review queue</h2>
      <form
        class="flex gap-3 items-end"
        @submit.prevent="
          page = 1;
          load();
        "
      >
        <label class="text-sm grid gap-1"
          >Status<select v-model="status" class="field-control">
            <option value="">All</option>
            <option v-for="s in ['FLAGGED', 'APPROVED', 'REJECTED']" :key="s">
              {{ s }}
            </option>
          </select></label
        ><button class="secondary-button" :disabled="busy">Refresh</button>
      </form>
      <p v-if="!busy && !rows.length" class="text-sm text-slate-500">
        No reviews match this status.
      </p>
      <div v-if="rows.length" class="overflow-x-auto">
        <table class="data-table min-w-[620px]">
          <thead>
            <tr>
              <th>Inviter / friend</th>
              <th>Reasons</th>
              <th>Created</th>
              <th>Status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.Id">
              <td>#{{ row.InviterUserId }} → #{{ row.FriendUserId }}</td>
              <td>
                {{ row.Signals.map((s) => humanLabel(s.Reason)).join(", ") }}
              </td>
              <td>{{ displayDate(row.CreatedAt) }}</td>
              <td>{{ row.Status }}</td>
              <td>
                <button class="secondary-button" @click="select(row)">
                  Review
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="flex gap-2">
        <button
          class="secondary-button"
          :disabled="page === 1 || busy"
          @click="
            page--;
            load();
          "
        >
          Previous</button
        ><span class="self-center text-sm"
          >Page {{ page }} · {{ total }} reviews</span
        ><button
          class="secondary-button"
          :disabled="page * 25 >= total || busy"
          @click="
            page++;
            load();
          "
        >
          Next
        </button>
      </div>
      <section v-if="chosen" class="border rounded-xl p-4 space-y-3">
        <div class="flex justify-between">
          <h3 class="font-semibold">Review #{{ chosen.Id.slice(0, 8) }}</h3>
          <button class="secondary-button" @click="chosen = null">Close</button>
        </div>
        <p class="text-sm">
          Relationship {{ chosen.RelationshipId }} · {{ chosen.Status }}
        </p>
        <ul class="space-y-2">
          <li
            v-for="signal in chosen.Signals"
            :key="signal.Id"
            class="bg-slate-50 p-3 text-sm"
          >
            <strong>{{ humanLabel(signal.Reason) }}</strong> ·
            {{ signal.Source }} · {{ displayDate(signal.OccurredAt) }}
            <p v-if="signal.AcknowledgedAt">
              Acknowledged {{ displayDate(signal.AcknowledgedAt) }}
            </p>
          </li>
        </ul>
        <template v-if="chosen.Status === 'FLAGGED'"
          ><label class="text-sm grid gap-1"
            >Decision reason<textarea
              v-model="decisionReason"
              class="field-control"
              required
              rows="3"
              maxlength="1000"
            />
          </label>
          <div class="flex gap-2">
            <button
              class="primary-button"
              :disabled="busy || !decisionReason.trim()"
              @click="decide('APPROVE')"
            >
              Approve review</button
            ><button
              class="secondary-button text-red-700"
              :disabled="busy || !decisionReason.trim()"
              @click="decide('REJECT')"
            >
              Reject relationship
            </button>
          </div></template
        >
      </section>
    </section>
  </div>
</template>
