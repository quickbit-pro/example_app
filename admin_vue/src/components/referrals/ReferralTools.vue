<script setup lang="ts">
import { ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import type { ReferralProgram } from "@/lib/referrals";
import { referralGet, programPath } from "@/lib/referralOperations";
import { describeAdminError } from "@/lib/adminApi";
import ReferralSignupAttempts from "./ReferralSignupAttempts.vue";
import ReferralAudit from "./ReferralAudit.vue";
import ReferralAccounting from "./ReferralAccounting.vue";
import ReferralAlerts from "./ReferralAlerts.vue";
import ReferralScenario from "./ReferralScenario.vue";
import ReferralBoosts from "./ReferralBoosts.vue";
import ReferralBulk from "./ReferralBulk.vue";
import ReferralGeography from "./ReferralGeography.vue";
const props = defineProps<{ program: ReferralProgram }>();
const readiness = ref<{
  Ready: boolean;
  Reason: string | null;
  Remedy: string | null;
} | null>(null);
const readinessError = ref("");
watch(
  () => props.program.Id,
  async (id) => {
    readiness.value = null;
    readinessError.value = "";
    try {
      readiness.value = await referralGet(
        `${programPath(id!)}/attribution-readiness`,
      );
    } catch (error) {
      readinessError.value = describeAdminError(error);
    }
  },
  { immediate: true },
);
const route = useRoute(),
  router = useRouter();
const items = [
  ["rules", "Attribution rules"],
  ["attempts", "Signup attempts"],
  ["audit", "Audit"],
  ["accounting", "Exports & accounting"],
  ["alerts", "Alerts"],
  ["simulator", "Walkthrough"],
  ["boosts", "Boosts"],
  ["bulk", "Bulk operations"],
  ["geo", "Countries & terms"],
] as const;
const selected = ref(
  items.some(([id]) => id === route.query.tool)
    ? String(route.query.tool)
    : "rules",
);
watch(
  () => route.query.tool,
  (v) => {
    if (items.some(([id]) => id === v)) selected.value = String(v);
  },
);
watch(selected, (v) => {
  void router.replace({ query: { ...route.query, tool: v } });
});
</script>
<template>
  <div class="space-y-4">
    <nav class="flex flex-wrap gap-2" aria-label="Referral tools">
      <button
        v-for="[id, label] in items"
        :key="id"
        :class="selected === id ? 'primary-button' : 'secondary-button'"
        :aria-current="selected === id ? 'page' : undefined"
        @click="selected = id"
      >
        {{ label }}
      </button>
    </nav>
    <section v-if="selected === 'rules'" class="panel p-5 space-y-4">
      <h2 class="panel-heading">Attribution rules</h2>
      <div v-if="readiness" class="rounded-lg bg-slate-50 p-3 text-sm">
        <strong>{{
          readiness.Ready
            ? "Program ready for signup attribution commands"
            : "Program requires attention before signup attribution commands"
        }}</strong>
        <p v-if="readiness.Reason">
          {{ readiness.Reason }} · {{ readiness.Remedy }}
        </p>
        <p class="text-xs text-slate-500 mt-1">
          This checks program policy readiness. Actual signup delivery also
          depends on deployment configuration.
        </p>
      </div>
      <p v-if="readinessError" class="text-sm text-amber-800">
        Program readiness could not be checked. {{ readinessError }}
      </p>
      <dl class="space-y-4 text-sm">
        <div>
          <dt class="font-semibold">Code or invitation link at signup</dt>
          <dd class="text-slate-600 mt-1">
            A personal code, campaign link or verified email invitation
            identifies the inviter. Personal-code lookup takes precedence over a
            matching campaign code. Required acceptance is checked by the
            server.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">One lifetime inviter per company</dt>
          <dd class="text-slate-600 mt-1">
            The first successfully committed relationship wins. A duplicate
            request cannot reserve twice or replace an existing inviter. An
            earlier pending request does not override a committed relationship.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">
            Signup and referral confirmation are separate
          </dt>
          <dd class="text-slate-600 mt-1">
            An account can exist while its referral is pending or refused. Only
            authoritative engine commitment confirms the accepted offer and
            reservation. A preview quote is not a guaranteed reward promise.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Clicks do not create relationships</dt>
          <dd class="text-slate-600 mt-1">
            Clicks and unique visitor counts measure campaign traffic. There is
            no click-to-signup attribution window, first/last-click override or
            cross-device identity matching.
          </dd>
        </div>
        <div>
          <dt class="font-semibold">Accepted terms are preserved</dt>
          <dd class="text-slate-600 mt-1">
            A committed protected relationship retains its accepted offer. Quote
            expiry or a later program edit cannot silently change it.
            Tier/discount inheritance does not create multiple commission
            generations.
          </dd>
        </div>
      </dl>
      <p class="text-xs text-slate-500">
        Issued codes are not signups. Diagnose pending or rejected attribution
        separately from account creation and click statistics.
      </p>
    </section>
    <ReferralSignupAttempts v-else-if="selected === 'attempts'" />
    <ReferralAudit v-else-if="selected === 'audit'" :program-id="program.Id!" />
    <ReferralAccounting
      v-else-if="selected === 'accounting'"
      :program-id="program.Id!"
      :currency="program.PayoutCurrency"
    />
    <ReferralAlerts v-else-if="selected === 'alerts'" />
    <ReferralScenario v-else-if="selected === 'simulator'" :program="program" />
    <ReferralBoosts
      v-else-if="selected === 'boosts'"
      :program-id="program.Id!"
      :revision="program.Revision"
      :currency="program.PayoutCurrency"
    />
    <ReferralBulk
      v-else-if="selected === 'bulk'"
      :program-id="program.Id!"
      :revision="program.Revision"
    />
    <ReferralGeography
      v-else-if="selected === 'geo'"
      :program-id="program.Id!"
    />
  </div>
</template>
