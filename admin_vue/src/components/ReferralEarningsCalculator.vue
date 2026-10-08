<script setup lang="ts">
// Live example beside the reward split (blueprint p16): illustrative inputs, the platform's settlement
// calculator does the maths. Never production authority; a pending result stays pending.
import { ref, watch } from 'vue';
import { describeAdminError } from '@/lib/adminApi';
import { money, type ReferralProgram } from '@/lib/referrals';
import { draftRequest, referralBuildApi, type Simulation } from '@/lib/referralBuild';
const props = defineProps<{ program: ReferralProgram; valid: boolean; available: boolean }>();
const sample = ref({ credited: '1000', fee: '20', cost: '', remaining: '', cardFee: '0', qualifies: false, promo: false, team: false, level: '' });
const simulation = ref<Simulation | null>(null); const busy = ref(false); const error = ref('');
async function calculate() {
  if (!props.valid || !props.program.Id || busy.value) return;
  busy.value = true; error.value = '';
  try {
    const input = sample.value;
    simulation.value = await referralBuildApi.simulate(props.program.Id, {
      Draft: draftRequest(props.program, props.program.MarginPolicy ?? null), LevelCode: input.level || props.program.Levels[0]?.Code,
      CreditedAmount: input.credited, SettledFee: input.fee === '' ? null : input.fee, ProviderCost: input.cost === '' ? null : input.cost,
      EligibleVolumeRemaining: input.remaining === '' ? null : input.remaining, PaidCardFee: input.cardFee,
      CompletesQualification: input.qualifies, Team: !!props.program.MarginPolicy?.Team && input.team,
      PromoCodeUsed: !!props.program.PromoCodePolicyEnabled && input.promo,
    });
  } catch (e) { error.value = describeAdminError(e); }
  finally { busy.value = false; }
}
watch(sample, () => { simulation.value = null; }, { deep: true });
watch(() => JSON.stringify(draftRequest(props.program, props.program.MarginPolicy ?? null)), () => { simulation.value = null; });
const rows = (s: Simulation): [string, number | null][] => [['Inviter recurring', s.InviterReward], ['Customer recurring', s.CustomerRecurringReward], ['Subpartner recurring', s.SubpartnerReward], ['Company retains', s.CompanyRetained], ['One-time inviter bonus', s.QualificationReward], ['One-time customer bonus', s.WelcomeReward]];
</script>

<template>
<div class="space-y-4 rounded-xl border border-slate-200 bg-slate-50 p-4">
  <div><h3 class="font-semibold">Live example</h3><p class="text-sm text-slate-500">Illustrative {{ program.PayoutCurrency }} inputs. Leave the fee or cost empty when unknown; the result stays pending instead of guessing.</p></div>
  <p v-if="!available" class="text-sm text-slate-500">The calculator needs versioned publishing, which this platform does not provide.</p>
  <template v-else>
    <label class="block text-sm">Inviter level<select v-model="sample.level" class="field-control mt-1 w-full"><option value="">First level</option><option v-for="level in program.Levels" :key="level.Code" :value="level.Code">{{ level.Name }}</option></select></label>
    <div class="grid gap-3 sm:grid-cols-2">
      <label class="text-sm">Eligible credited top-up<input v-model="sample.credited" type="number" min="0" step="0.01" class="field-control mt-1 w-full" /></label>
      <label class="text-sm">Eligible volume remaining<input v-model="sample.remaining" type="number" min="0" step="0.01" placeholder="Program cap" class="field-control mt-1 w-full" /></label>
      <label class="text-sm">Settled fee<input v-model="sample.fee" type="number" min="0" step="0.01" class="field-control mt-1 w-full" /></label>
      <label class="text-sm">Provider cost<input v-model="sample.cost" type="number" min="0" step="0.01" placeholder="Unknown" class="field-control mt-1 w-full" /></label>
    </div>
    <label class="flex gap-2 text-sm"><input v-model="sample.qualifies" type="checkbox" /> This event completes qualification</label>
    <label v-if="program.PromoCodePolicyEnabled" class="flex gap-2 text-sm"><input v-model="sample.promo" type="checkbox" /> Customer redeemed a promo code (no welcome reward)</label>
    <label v-if="sample.qualifies" class="block text-sm">Paid card fee<input v-model="sample.cardFee" type="number" min="0" step="0.01" class="field-control mt-1 w-full" /></label>
    <label v-if="program.MarginPolicy?.Team" class="flex gap-2 text-sm"><input v-model="sample.team" type="checkbox" /> Simulate the team route</label>
    <button type="button" class="secondary-button" :disabled="busy || !valid || !program.Id" @click="calculate">{{ busy ? 'Calculating…' : 'Calculate example' }}</button>
    <p v-if="!valid" class="text-xs text-slate-500">Fix the validation issues first; the calculator only runs a valid draft.</p>
    <p v-if="error" role="alert" class="text-sm text-red-700">{{ error }}</p>
    <div v-if="simulation" class="space-y-2" aria-live="polite">
      <p class="font-medium">{{ simulation.Status === 'PENDING_CALCULATION' ? 'Waiting for settlement inputs' : 'Calculated example' }}</p>
      <p class="text-xs text-slate-500">{{ simulation.Basis }} · {{ simulation.CalculationVersion }} · eligible {{ money(simulation.EligibleAmount, simulation.Currency) }}</p>
      <dl class="space-y-2 text-sm"><div v-for="row in rows(simulation)" :key="row[0]" class="flex justify-between gap-3"><dt>{{ row[0] }}</dt><dd class="font-mono">{{ row[1] == null ? 'Pending' : money(row[1], simulation.Currency) }}</dd></div></dl>
      <p v-for="warning in simulation.Warnings" :key="warning" class="text-xs text-slate-600">{{ warning }}</p>
    </div>
  </template>
</div>
</template>
