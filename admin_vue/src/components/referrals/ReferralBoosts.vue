<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  referralSend,
  programPath,
  displayDate,
  localDateTime,
  utc,
} from "@/lib/referralOperations";
const props = defineProps<{
  programId: string;
  revision: number;
  currency: string;
}>();
type Boost = {
  Id: string;
  Name: string;
  Kind: string;
  Status: string;
  StartsAt: string;
  EndsAt: string;
  Multiplier: number | null;
  QualifiedFriendCount: number | null;
  MilestoneAmount: number | null;
  MaximumIncrementalReward: number | null;
  MaximumAwards: number;
  FundedBudget: number;
  ReservedBudget: number;
  AllocatedAwards: number;
  Currency: string;
};
const rows = ref<Boost[]>([]),
  busy = ref(false),
  error = ref(""),
  message = ref(""),
  activation = ref<Boost | null>(null),
  pauseTarget = ref<Boost | null>(null),
  capability = ref<boolean | null>(null);
const form = ref({
  Name: "",
  Kind: "MULTIPLIER",
  StartsAt: localDateTime(),
  EndsAt: localDateTime(new Date(Date.now() + 86400000)),
  Multiplier: 2,
  QualifiedFriendCount: 5,
  MilestoneAmount: 0,
  MaximumIncrementalReward: 0,
  MaximumAwards: 1,
  FundedBudget: 0,
});
const minimumFunding = computed(
  () =>
    form.value.MaximumAwards *
    (form.value.Kind === "MULTIPLIER"
      ? form.value.MaximumIncrementalReward
      : form.value.MilestoneAmount),
);
async function load() {
  busy.value = true;
  error.value = "";
  try {
    rows.value = await referralGet<Boost[]>(
      `${programPath(props.programId)}/boosts`,
    );
    const c = await referralGet<{ Enabled: boolean }>(
      `${programPath(props.programId)}/boosts/capabilities`,
    );
    capability.value = c.Enabled;
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function create() {
  busy.value = true;
  error.value = "";
  try {
    await referralSend("POST", `${programPath(props.programId)}/boosts`, {
      ...form.value,
      StartsAt: utc(form.value.StartsAt),
      EndsAt: utc(form.value.EndsAt),
      Multiplier:
        form.value.Kind === "MULTIPLIER" ? form.value.Multiplier : null,
      QualifiedFriendCount:
        form.value.Kind === "MILESTONE"
          ? form.value.QualifiedFriendCount
          : null,
      MilestoneAmount:
        form.value.Kind === "MILESTONE" ? form.value.MilestoneAmount : null,
      MaximumIncrementalReward:
        form.value.Kind === "MULTIPLIER"
          ? form.value.MaximumIncrementalReward
          : null,
      Currency: props.currency,
      ExpectedProgramRevision: props.revision,
    });
    message.value = "Boost draft created. Activation is a separate action.";
    await load();
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function activate() {
  if (!activation.value) return;
  busy.value = true;
  error.value = "";
  try {
    await referralSend(
      "POST",
      `${programPath(props.programId)}/boosts/${activation.value.Id}/activate`,
      { ExpectedProgramRevision: props.revision },
    );
    message.value = "Boost activated for eligible new accepted cohorts.";
    activation.value = null;
    await load();
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function pause() {
  if (!pauseTarget.value) return;
  busy.value = true;
  error.value = "";
  try {
    await referralSend(
      "POST",
      `${programPath(props.programId)}/boosts/${pauseTarget.value.Id}/pause`,
      { ExpectedProgramRevision: props.revision },
    );
    pauseTarget.value = null;
    message.value =
      "New participation stopped. Captured rewards and reserved funding are preserved.";
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
    activation.value = null;
    pauseTarget.value = null;
    load();
  },
  { immediate: true },
);
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Time-boxed boosts</h2>
    <p class="text-sm text-slate-500">
      Economic boosts are separate from campaign tracking links. Boosts do not
      stack, apply to new accepted cohorts, and remain bounded by settled margin
      and funded reward limits.
    </p>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
    <p v-if="capability !== true" class="text-sm bg-amber-50 p-3 rounded-lg">
      Boost activation is disabled in this environment. Drafts can still be
      prepared.
    </p>
    <form @submit.prevent="create" class="space-y-3">
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <label class="text-sm grid gap-1"
          >Name<input
            v-model="form.Name"
            required
            maxlength="120"
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Type<select v-model="form.Kind" class="field-control">
            <option value="MULTIPLIER">Rate multiplier</option>
            <option value="MILESTONE">Qualified-friend milestone</option>
          </select></label
        ><label class="text-sm grid gap-1"
          >Starts<input
            v-model="form.StartsAt"
            type="datetime-local"
            required
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Ends (exclusive)<input
            v-model="form.EndsAt"
            type="datetime-local"
            required
            class="field-control" /></label
        ><template v-if="form.Kind === 'MULTIPLIER'"
          ><label class="text-sm grid gap-1"
            >Rate multiplier<input
              v-model.number="form.Multiplier"
              type="number"
              min="1"
              max="10"
              step="any"
              required
              class="field-control" /></label
          ><label class="text-sm grid gap-1"
            >Maximum cumulative extra per relationship<input
              v-model.number="form.MaximumIncrementalReward"
              type="number"
              min="0.01"
              step="any"
              required
              class="field-control" /></label></template
        ><template v-else
          ><label class="text-sm grid gap-1"
            >Qualified friends required<input
              v-model.number="form.QualifiedFriendCount"
              type="number"
              min="1"
              max="10000"
              required
              class="field-control" /></label
          ><label class="text-sm grid gap-1"
            >Milestone reward ({{ currency }})<input
              v-model.number="form.MilestoneAmount"
              type="number"
              min="0.01"
              step="any"
              required
              class="field-control" /></label></template
        ><label class="text-sm grid gap-1"
          >Maximum funded recipients<input
            v-model.number="form.MaximumAwards"
            type="number"
            min="1"
            required
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Funded budget ({{ currency }})<input
            v-model.number="form.FundedBudget"
            type="number"
            :min="minimumFunding"
            step="any"
            required
            class="field-control"
        /></label>
      </div>
      <p class="text-sm text-slate-500">
        At least {{ minimumFunding }} {{ currency }} is required to fund these
        award limits. Times are displayed in your timezone and submitted in UTC.
      </p>
      <button class="primary-button" :disabled="busy">
        Create boost draft
      </button>
    </form>
    <div class="overflow-x-auto">
      <table class="data-table min-w-[650px]">
        <thead>
          <tr>
            <th>Boost</th>
            <th>Schedule</th>
            <th>Budget / allocated</th>
            <th>Status</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="boost in rows" :key="boost.Id">
            <td>
              {{ boost.Name }}
              <div class="text-xs">
                {{
                  boost.Kind === "MULTIPLIER"
                    ? `${boost.Multiplier}× rate`
                    : `${boost.QualifiedFriendCount} friends · ${boost.MilestoneAmount} ${boost.Currency}`
                }}
              </div>
            </td>
            <td>
              {{ displayDate(boost.StartsAt) }} →
              {{ displayDate(boost.EndsAt) }}
            </td>
            <td>
              {{ boost.FundedBudget }} {{ boost.Currency }} ·
              {{ boost.AllocatedAwards }} / {{ boost.MaximumAwards }} awards
            </td>
            <td>{{ boost.Status }}</td>
            <td>
              <button
                v-if="boost.Status === 'DRAFT'"
                class="secondary-button"
                :disabled="busy || capability !== true"
                @click="activation = boost"
              >
                Review activation
              </button>
              <button
                v-if="boost.Status === 'ACTIVE'"
                class="secondary-button"
                :disabled="busy"
                @click="pauseTarget = boost"
              >
                Stop new participation
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="!rows.length && !busy" class="text-sm text-slate-500">
      No boosts have been created.
    </p>
    <div v-if="activation" class="border rounded-xl p-4 space-y-3">
      <h3 class="font-semibold">Activate {{ activation.Name }}</h3>
      <p class="text-sm">
        This activates the immutable reward policy for eligible new cohorts
        during {{ displayDate(activation.StartsAt) }}–{{
          displayDate(activation.EndsAt)
        }}. Funded budget: {{ activation.FundedBudget }}
        {{ activation.Currency }}. Existing accepted terms remain unchanged.
      </p>
      <button
        class="primary-button"
        :disabled="busy || capability !== true"
        @click="activate"
      >
        Confirm activation</button
      ><button class="secondary-button ml-2" @click="activation = null">
        Cancel
      </button>
    </div>
    <div v-if="pauseTarget" class="border rounded-xl p-4 space-y-3">
      <h3 class="font-semibold">
        Stop new participation in {{ pauseTarget.Name }}?
      </h3>
      <p class="text-sm">
        Existing accepted participants keep captured rewards and reserved
        funding. New signup quotes cannot join this boost; unused funding
        expires at its original end.
      </p>
      <button class="primary-button" :disabled="busy" @click="pause">
        Confirm stop</button
      ><button class="secondary-button ml-2" @click="pauseTarget = null">
        Cancel
      </button>
    </div>
  </section>
</template>
