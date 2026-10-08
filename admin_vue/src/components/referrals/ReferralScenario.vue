<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import { draftRequest } from "@/lib/referralBuild";
import type { ReferralProgram } from "@/lib/referrals";
import {
  displayDate,
  humanLabel,
  localDateTime,
  utc,
  referralSend,
  referralGet,
  programPath,
  type Condition,
} from "@/lib/referralOperations";
const props = defineProps<{ program: ReferralProgram }>();
const level = ref(props.program.Levels[0]?.Code || ""),
  attributed = ref(localDateTime()),
  asOf = ref(localDateTime()),
  volume = ref(0),
  rewarded = ref(0),
  country = ref("");
const events = ref<
  {
    key: string;
    type: string;
    at: string;
    amount: number;
    funding: string;
    fee: string;
    cost: string;
    promo: boolean;
  }[]
>([]);
const busy = ref(false),
  error = ref(""),
  boostId = ref(""),
  boostRewarded = ref(0),
  qualifiedFriends = ref(0),
  boosts = ref<{ Id: string; Name: string; Status: string }[]>([]);
watch(
  () => props.program.Id,
  async (id) => {
    boostId.value = "";
    try {
      boosts.value = await referralGet(`${programPath(id!)}/boosts`);
    } catch {
      boosts.value = [];
    }
  },
  { immediate: true },
);
type Qualification = {
  Stage: string;
  CanQualify: boolean;
  QualifiedAt: string | null;
  WindowEndsAt: string | null;
  Conditions: Condition[];
  MissingConditions: string[];
};
type Result = {
  Qualification: Qualification;
  Steps: {
    EventKey: string;
    EventType: string;
    At: string;
    Decision: string;
    BoostReward: number;
    Qualification: Qualification;
    Calculation: {
      Currency: string;
      InviterReward: number | null;
      CustomerRecurringReward: number | null;
      QualificationReward: number;
      WelcomeReward: number;
      Status: string;
    } | null;
  }[];
  Warnings: string[];
  EligibleVolumeUsed: number;
  RecurringRewardUsed: number;
};
const result = ref<Result | null>(null);
const fingerprint = computed(() =>
  JSON.stringify([
    props.program,
    level.value,
    attributed.value,
    asOf.value,
    volume.value,
    rewarded.value,
    country.value,
    boostId.value,
    boostRewarded.value,
    qualifiedFriends.value,
    events.value,
  ]),
);
watch(fingerprint, () => {
  result.value = null;
});
function add(type: string) {
  events.value.push({
    key: crypto.randomUUID(),
    type,
    at: asOf.value,
    amount: type === "CARD_TOPUP" ? 100 : type === "CARD_ISSUED" ? 10 : 0,
    funding: "EXTERNAL_CRYPTO",
    fee: "",
    cost: "",
    promo: false,
  });
}
async function simulate() {
  busy.value = true;
  error.value = "";
  try {
    result.value = await referralSend<Result>(
      "POST",
      `${programPath(props.program.Id!)}/qualification-scenarios`,
      {
        Draft: draftRequest(props.program, props.program.MarginPolicy ?? null),
        LevelCode: level.value,
        AttributedAt: utc(attributed.value),
        AsOf: utc(asOf.value),
        AlreadyUsedVolume: volume.value,
        AlreadyRewarded: rewarded.value,
        BoostId: boostId.value || null,
        AlreadyBoostRewarded: boostRewarded.value,
        AlreadyQualifiedFriends: qualifiedFriends.value,
        VerifiedCountry: country.value.trim().toUpperCase() || null,
        Events: events.value.map((e) => ({
          Key: e.key,
          Type: e.type,
          At: utc(e.at),
          Amount: e.amount,
          Currency: props.program.PayoutCurrency,
          FundingSource: e.funding,
          SettledFee: e.fee === "" ? null : e.fee,
          ProviderCost: e.cost === "" ? null : e.cost,
          PromoCodeUsed: !!props.program.PromoCodePolicyEnabled && e.promo,
        })),
      },
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Qualification walkthrough</h2>
    <p class="text-sm text-slate-500">
      Try the current offer draft with a fictional friend. The server evaluates
      the timeline; no customer, reward or credit is created. Changes clear the
      previous result. The current published country policy applies. This
      walkthrough covers KYC, card issuance and top-ups; provider reversals are
      handled in the ledger flow.
    </p>
    <form @submit.prevent="simulate" class="space-y-4">
      <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <label class="text-sm grid gap-1"
          >Inviter level<select v-model="level" class="field-control">
            <option v-for="l in program.Levels" :key="l.Code" :value="l.Code">
              {{ l.Name }}
            </option>
          </select></label
        ><label class="text-sm grid gap-1"
          >Attribution<input
            v-model="attributed"
            type="datetime-local"
            class="field-control"
            required /></label
        ><label class="text-sm grid gap-1"
          >Evaluate as of<input
            v-model="asOf"
            type="datetime-local"
            class="field-control"
            required /></label
        ><label class="text-sm grid gap-1"
          >Eligible volume already used<input
            v-model.number="volume"
            type="number"
            min="0"
            step="any"
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Recurring rewards already accrued<input
            v-model.number="rewarded"
            type="number"
            min="0"
            step="any"
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Verified residence country (optional)<input
            v-model="country"
            maxlength="2"
            class="field-control"
            placeholder="ISO country, e.g. DE"
        /></label>
      </div>
      <details class="border rounded-xl p-3">
        <summary class="cursor-pointer font-semibold text-sm">
          Boost scenario (optional)
        </summary>
        <div class="grid sm:grid-cols-3 gap-3 mt-3">
          <label class="text-sm grid gap-1"
            >Boost<select v-model="boostId" class="field-control">
              <option value="">No boost</option>
              <option v-for="boost in boosts" :key="boost.Id" :value="boost.Id">
                {{ boost.Name }} · {{ boost.Status }}
              </option>
            </select></label
          ><label class="text-sm grid gap-1"
            >Boost rewards already accrued<input
              v-model.number="boostRewarded"
              type="number"
              min="0"
              step="any"
              class="field-control" /></label
          ><label class="text-sm grid gap-1"
            >Previously qualified friends<input
              v-model.number="qualifiedFriends"
              type="number"
              min="0"
              class="field-control"
          /></label>
        </div>
      </details>
      <div class="flex flex-wrap gap-2">
        <button
          v-for="type in ['KYC_APPROVED', 'CARD_ISSUED', 'CARD_TOPUP']"
          :key="type"
          type="button"
          class="secondary-button"
          @click="add(type)"
        >
          Add {{ humanLabel(type) }}
        </button>
      </div>
      <fieldset
        v-for="(event, index) in events"
        :key="event.key"
        class="border rounded-xl p-3 space-y-3"
      >
        <legend class="px-2 font-semibold text-sm">
          {{ index + 1 }}. {{ humanLabel(event.type) }}
        </legend>
        <label v-if="program.PromoCodePolicyEnabled && event.type !== 'KYC_APPROVED'" class="flex gap-2 text-sm">
          <input v-model="event.promo" type="checkbox" /> Promo code redeemed with this event
        </label>
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <label class="text-sm grid gap-1"
            >Occurred at<input
              v-model="event.at"
              type="datetime-local"
              class="field-control"
              required /></label
          ><label
            v-if="event.type !== 'KYC_APPROVED'"
            class="text-sm grid gap-1"
            >Amount ({{ program.PayoutCurrency }})<input
              v-model.number="event.amount"
              type="number"
              min="0"
              step="any"
              class="field-control" /></label
          ><template v-if="event.type === 'CARD_TOPUP'"
            ><label class="text-sm grid gap-1"
              >Funding<select v-model="event.funding" class="field-control">
                <option>EXTERNAL_CRYPTO</option>
                <option>REFERRAL_REWARD</option>
                <option>INTERNAL_TRANSFER</option>
              </select></label
            ><label class="text-sm grid gap-1"
              >Settled fee<input
                v-model="event.fee"
                type="number"
                min="0"
                step="any"
                class="field-control"
                placeholder="Unknown" /></label
            ><label class="text-sm grid gap-1"
              >Provider cost<input
                v-model="event.cost"
                type="number"
                min="0"
                step="any"
                class="field-control"
                placeholder="Unknown" /></label
          ></template>
        </div>
        <button
          type="button"
          class="text-sm text-red-700"
          @click="events.splice(index, 1)"
        >
          Remove event
        </button>
      </fieldset>
      <p v-if="!events.length" class="text-sm text-slate-500">
        Add events to test missing steps and qualification.
      </p>
      <button class="primary-button" :disabled="busy || !level">
        {{ busy ? "Evaluating…" : "Run walkthrough" }}
      </button>
    </form>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <div v-if="result" class="space-y-3" role="status">
      <p class="font-semibold">
        {{ humanLabel(result.Qualification.Stage) }} ·
        {{
          result.Qualification.CanQualify
            ? "All required conditions met"
            : "Qualification incomplete"
        }}
      </p>
      <p class="text-sm">
        Qualified {{ displayDate(result.Qualification.QualifiedAt) }} · Window
        ends {{ displayDate(result.Qualification.WindowEndsAt) }}
      </p>
      <ul class="text-sm space-y-1">
        <li
          v-for="condition in result.Qualification.Conditions"
          :key="condition.Code"
        >
          {{ condition.Label }}:
          {{
            !condition.Required ? "optional" : condition.Met ? "met" : "missing"
          }}
        </li>
      </ul>
      <div
        v-for="step in result.Steps"
        :key="step.EventKey"
        class="bg-slate-50 rounded-lg p-3 text-sm"
      >
        <strong>{{ humanLabel(step.EventType) }}</strong> ·
        {{ displayDate(step.At) }} — {{ humanLabel(step.Decision) }}
        <p v-if="step.BoostReward">
          Boost reward: {{ step.BoostReward }} {{ program.PayoutCurrency }}
        </p>
        <p v-if="step.Calculation">
          {{ humanLabel(step.Calculation.Status) }} · Inviter
          {{ step.Calculation.InviterReward ?? "pending" }}
          {{ step.Calculation.Currency }} · Customer recurring
          {{ step.Calculation.CustomerRecurringReward ?? "pending" }} ·
          Qualification {{ step.Calculation.QualificationReward }} · Welcome
          {{ step.Calculation.WelcomeReward }}
        </p>
      </div>
      <p
        v-for="warning in result.Warnings"
        :key="warning"
        class="text-sm text-amber-800"
      >
        {{ warning }}
      </p>
    </div>
  </section>
</template>
