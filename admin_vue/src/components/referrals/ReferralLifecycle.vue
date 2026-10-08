<script setup lang="ts">
import { ref, watch } from "vue";
import UserPicker from "@/components/UserPicker.vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  programPath,
  displayDate,
  humanLabel,
} from "@/lib/referralOperations";
import { rewardRateLabel, type ReferralMember, type UserOption } from "@/lib/referrals";
const props = defineProps<{
  programId: string;
  members: ReferralMember[];
  users: UserOption[];
}>();
const userId = ref<number | null>(null),
  busy = ref(false),
  error = ref(""),
  page = ref(1);
type Level = {
  Name: string;
  Code: string;
  TopupCalculationType: string;
  TopupRate: number;
};
type Lifecycle = {
  AsOf: string;
  ObservedAt: string | null;
  CurrentLevel: Level | null;
  Assigned: boolean;
  Progress: {
    QualifiedReferrals: number;
    TopupVolume: number;
    TopupVolumeCurrency: string;
    RemainingQualifiedReferrals: number | null;
    RemainingTopupVolume: number | null;
    LookbackMonths: number;
  };
  Forecast: {
    EffectiveAt: string;
    DaysUntil: number;
    Level: Level | null;
    Assigned: boolean;
    Reason: string;
  } | null;
  ProtectedRelationshipCount: number;
};
const state = ref<Lifecycle | null>(null),
  history = ref<{
    Items: {
      Id: string;
      Kind: string;
      EffectiveAt: string;
      ObservedAt: string;
      EffectiveTimeBasis: string;
      PreviousLevel: Level | null;
      CurrentLevel: Level | null;
      DeliveryStatus: string;
    }[];
    HasMore: boolean;
  } | null>(null);
let requestGeneration = 0;
async function load() {
  const generation = ++requestGeneration;
  if (!userId.value) {
    busy.value = false;
    history.value = null;
    return;
  }
  busy.value = true;
  error.value = "";
  try {
    const [nextState, nextHistory] = await Promise.all([
      referralGet<Lifecycle>(
        `${programPath(props.programId)}/members/${userId.value}/level-lifecycle`,
      ),
      referralGet<{
        Items: NonNullable<typeof history.value>["Items"];
        HasMore: boolean;
      }>(
        `${programPath(props.programId)}/members/${userId.value}/level-history`,
        { page: page.value, pageSize: 25 },
      ),
    ]);
    if (generation === requestGeneration) {
      state.value = nextState;
      history.value = nextHistory;
    }
  } catch (e) {
    if (generation === requestGeneration) error.value = describeAdminError(e);
  } finally {
    if (generation === requestGeneration) busy.value = false;
  }
}
watch(
  () => props.programId,
  () => {
    state.value = null;
    history.value = null;
    userId.value = null;
  },
);
watch(userId, () => {
  page.value = 1;
  state.value = null;
  load();
});
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Member levels and forecasts</h2>
    <p class="text-sm text-slate-500">
      Current and future invitation offers. Existing protected relationships
      keep their accepted rates.
    </p>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-sm grid gap-1"
        >Find a member<UserPicker v-model="userId" /></label
      ><label v-if="members.length" class="text-sm grid gap-1"
        >Program partners<select v-model.number="userId" class="field-control">
          <option :value="null">Choose partner</option>
          <option
            v-for="member in members"
            :key="member.UserId"
            :value="member.UserId"
          >
            {{ member.Name }} · {{ member.Email }}
          </option>
        </select></label
      >
    </div>
    <p v-if="busy" role="status">Loading level…</p>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <p v-if="!userId" class="text-sm text-slate-500">
      Search any inviter, or choose a registered partner.
    </p>
    <template v-if="state"
      ><div class="grid sm:grid-cols-3 gap-3">
        <div class="metric-card">
          <p class="text-sm text-slate-500">Current level</p>
          <p class="font-semibold mt-1">
            {{ state.CurrentLevel?.Name || "No level" }}
          </p>
          <p class="text-sm">
            {{ state.Assigned ? "Manual assignment" : "Activity-based" }}
          </p>
        </div>
        <div class="metric-card">
          <p class="text-sm text-slate-500">
            Qualified referrals / top-up volume
          </p>
          <p class="font-semibold mt-1">
            {{ state.Progress.QualifiedReferrals }} /
            {{ state.Progress.TopupVolume }}
            {{ state.Progress.TopupVolumeCurrency }}
          </p>
        </div>
        <div class="metric-card">
          <p class="text-sm text-slate-500">To next level</p>
          <p class="text-sm mt-1">
            {{ state.Progress.RemainingQualifiedReferrals ?? "—" }} more
            qualified friends · {{ state.Progress.RemainingTopupVolume ?? "—" }}
            {{ state.Progress.TopupVolumeCurrency }} volume
          </p>
        </div>
      </div>
      <div
        v-if="state.Forecast"
        class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm"
      >
        <strong>With no new qualifying activity or policy changes:</strong> the
        invitation offer changes to
        {{ state.Forecast.Level?.Name || "no level" }}
        <span v-if="state.Forecast.Level"
          >({{
            rewardRateLabel(
              state.Forecast.Level.TopupCalculationType,
              state.Forecast.Level.TopupRate,
              state.Progress.TopupVolumeCurrency,
            )
          }})</span
        >
        on {{ displayDate(state.Forecast.EffectiveAt) }} ({{
          state.Forecast.DaysUntil
        }}
        days).
        <p class="mt-1">
          {{ humanLabel(state.Forecast.Reason) }} ·
          {{ state.ProtectedRelationshipCount }} protected relationships retain
          their accepted offers.
        </p>
      </div>
      <p v-else class="text-sm text-slate-500">
        No future level change is currently projected.
      </p>
      <p class="text-xs text-slate-500">
        As of {{ displayDate(state.AsOf) }} · Last stored observation
        {{ displayDate(state.ObservedAt) }}
      </p>
      <h3 class="font-semibold">Level history</h3>
      <div class="overflow-x-auto">
        <table class="data-table min-w-[620px]">
          <thead>
            <tr>
              <th>Change</th>
              <th>Previous → current</th>
              <th>Effective</th>
              <th>Observed / delivery</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="event in history?.Items" :key="event.Id">
              <td>{{ humanLabel(event.Kind) }}</td>
              <td>
                {{ event.PreviousLevel?.Name || "—" }} →
                {{ event.CurrentLevel?.Name || "—" }}
              </td>
              <td>
                {{ displayDate(event.EffectiveAt) }}
                <div class="text-xs">
                  {{ humanLabel(event.EffectiveTimeBasis) }}
                </div>
              </td>
              <td>
                {{ displayDate(event.ObservedAt) }} · {{ event.DeliveryStatus }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!history?.Items.length" class="text-sm text-slate-500">
        No recorded changes yet.
      </p>
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
        ><button
          class="secondary-button"
          :disabled="!history?.HasMore || busy"
          @click="
            page++;
            load();
          "
        >
          Next
        </button>
      </div></template
    >
  </section>
</template>
