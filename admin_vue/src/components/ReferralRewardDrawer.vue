<script setup lang="ts">
// Reward explanation drawer (blueprint p28): basis, rate, cap, currency, original event, beneficiary,
// terms version, delivery reference and state. Values the row does not carry are shown as not recorded,
// never as zero.
import { computed, onBeforeUnmount, onMounted } from 'vue';
import StatusPill from '@/components/StatusPill.vue';
import { money, rewardEventLabel, statusLabel, statusTone, type AdminReward, type ReferralCredit } from '@/lib/referrals';
import { beneficiaryRoleLabel, capNote, deliveryLabel, rewardBasisLabel, rewardDeliveryState, rewardRateText } from '@/lib/referralReview';
const props = defineProps<{ row: AdminReward; credit: ReferralCredit | null; creditsLoaded: boolean }>();
const emit = defineEmits<{ close: [] }>();
const reward = computed(() => props.row.Reward);
const explanation = computed(() => reward.value.Explanation ?? null);
const amount = (value: number | null | undefined, currency: string) => value === null || value === undefined || !Number.isFinite(value) ? 'Not recorded' : money(value, currency);
const date = (value: string | null | undefined) => value ? new Date(value).toLocaleString() : '—';
const shortId = (value: string | null | undefined) => value ? `${value.slice(0, 8)}…` : null;
function onKey(event: KeyboardEvent) { if (event.key === 'Escape') emit('close'); }
onMounted(() => document.addEventListener('keydown', onKey)); onBeforeUnmount(() => document.removeEventListener('keydown', onKey));
</script>

<template>
<Teleport to="body">
  <div class="fixed inset-0 z-40 bg-slate-950/30" aria-hidden="true" @click="emit('close')" />
  <aside class="fixed inset-y-0 right-0 z-50 flex w-full max-w-lg flex-col overflow-y-auto border-l border-slate-200 bg-white shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="reward-drawer-title">
    <header class="flex items-start justify-between gap-3 border-b border-slate-200 p-5">
      <div><p class="text-xs uppercase tracking-wide text-slate-500">Reward explanation</p><h2 id="reward-drawer-title" class="mt-1 text-lg font-bold">{{ rewardEventLabel(reward.EventType) }} · {{ money(reward.Amount, reward.Currency) }}</h2>
        <div class="mt-2 flex flex-wrap items-center gap-2"><StatusPill :label="reward.Status" :tone="statusTone(reward.Status)" /><span class="text-xs text-slate-500">{{ rewardDeliveryState(reward) }}</span></div></div>
      <button type="button" class="secondary-button" @click="emit('close')">Close</button>
    </header>
    <div class="space-y-6 p-5 text-sm">
      <section><h3 class="font-semibold">Beneficiary</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Role</dt><dd>{{ beneficiaryRoleLabel(reward.BeneficiaryRole) }}</dd>
          <dt class="text-slate-500">Account</dt><dd>{{ row.BeneficiaryEmail }} <span class="text-slate-500">#{{ row.BeneficiaryUserId }}</span></dd>
          <dt class="text-slate-500">Pseudonym</dt><dd>{{ reward.FriendAlias || 'Not recorded' }}<span class="block text-xs text-slate-500">What the inviter sees instead of the referred customer's identity.</span></dd>
          <dt class="text-slate-500">Level</dt><dd class="font-mono text-xs">{{ reward.LevelCode || '—' }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Original event</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Event</dt><dd>{{ rewardEventLabel(reward.EventType) }} <span class="font-mono text-xs text-slate-500">{{ reward.EventType }}</span></dd>
          <dt class="text-slate-500">Occurred</dt><dd>{{ date(reward.OccurredAt) }}</dd>
          <dt class="text-slate-500">Subject</dt><dd>{{ row.SubjectEmail }} <span class="text-slate-500">#{{ row.SubjectUserId }}</span></dd>
          <dt class="text-slate-500">Eligible credited top-up</dt><dd>{{ reward.BasisAmount > 0 ? money(reward.BasisAmount, reward.BasisCurrency) : 'Not a top-up event' }}</dd>
          <dt class="text-slate-500">Reward ID</dt><dd class="font-mono text-xs">{{ reward.Id }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Calculation</h3>
        <p v-if="!explanation" class="mt-2 rounded-lg bg-slate-50 p-3 text-slate-600">This reward predates calculation evidence on the platform. Basis, rate and cap were not recorded; the current program terms are not assumed.</p>
        <dl v-else class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Basis</dt><dd>{{ rewardBasisLabel(explanation.Basis) }} <span class="font-mono text-xs text-slate-500">{{ explanation.Basis }}</span></dd>
          <dt class="text-slate-500">Rate</dt><dd>{{ rewardRateText(explanation.Basis, explanation.Rate, reward.Currency) }}</dd>
          <dt class="text-slate-500">Eligible amount</dt><dd>{{ amount(explanation.EligibleAmount, reward.BasisCurrency) }}</dd>
          <dt class="text-slate-500">Cap</dt><dd>{{ capNote(explanation, reward) }}</dd>
          <dt class="text-slate-500">Rounding</dt><dd>{{ explanation.Rounding || 'Not recorded' }}</dd>
          <dt class="text-slate-500">Currency</dt><dd>{{ reward.Currency }}<span v-if="reward.BasisCurrency && reward.BasisCurrency !== reward.Currency" class="text-slate-500"> · basis in {{ reward.BasisCurrency }}</span></dd>
          <dt class="text-slate-500">Rounded amount</dt><dd class="font-semibold">{{ money(reward.Amount, reward.Currency) }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Terms</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Terms version</dt><dd>{{ explanation?.TermsVersion != null ? `v${explanation.TermsVersion}` : 'Not recorded' }}</dd>
          <dt class="text-slate-500">Offer version</dt><dd class="font-mono text-xs">{{ explanation?.OfferVersionId || 'Legacy offer (no version snapshot)' }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Delivery</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Mode</dt><dd>{{ deliveryLabel(reward.DeliveryMode, reward.Currency) }}</dd>
          <dt class="text-slate-500">State</dt><dd>{{ statusLabel(reward.Status) }} · {{ statusLabel(reward.Stage) }}<span class="block text-xs text-slate-500">{{ explanation?.DeliveryExplanation || rewardDeliveryState(reward) }}</span></dd>
          <dt class="text-slate-500">Paid at</dt><dd>{{ reward.PaidAt ? date(reward.PaidAt) : 'Not confirmed yet' }}</dd>
          <dt class="text-slate-500">Delivery reference</dt><dd class="font-mono text-xs">{{ reward.CreditId ? `credit ${reward.CreditId}` : reward.VoucherId ? `voucher ${reward.VoucherId}` : 'Not assigned yet' }}</dd>
        </dl>
        <div v-if="reward.CreditId" class="mt-3 rounded-lg border border-slate-200 p-3">
          <p class="text-xs uppercase tracking-wide text-slate-500">Wallet credit</p>
          <template v-if="credit">
            <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
              <dt class="text-slate-500">Credit state</dt><dd><StatusPill :label="credit.Status" :tone="statusTone(credit.Status)" /><span v-if="credit.Status === 'CONFIRMING' || credit.Status === 'TRANSFERRING'" class="ml-2 text-xs text-slate-500">provider outcome not confirmed yet</span></dd>
              <dt class="text-slate-500">Provider reference</dt><dd class="font-mono text-xs">{{ credit.ProviderReference || 'None yet' }}</dd>
              <dt class="text-slate-500">Provider confirmed</dt><dd>{{ credit.ProviderConfirmedAt ? date(credit.ProviderConfirmedAt) : 'Not confirmed' }}</dd>
              <dt class="text-slate-500">Attempts</dt><dd>{{ credit.Attempts }}<span v-if="credit.NextAttemptAt && credit.Status !== 'PAID'" class="text-slate-500"> · next {{ date(credit.NextAttemptAt) }}</span></dd>
              <dt v-if="credit.LastError" class="text-slate-500">Last error</dt><dd v-if="credit.LastError" class="text-red-700">{{ credit.LastError }}</dd>
              <dt class="text-slate-500">Batch</dt><dd>{{ credit.RewardIds.length }} reward{{ credit.RewardIds.length === 1 ? '' : 's' }} · {{ money(credit.Amount, credit.Currency) }} to {{ credit.Destination }}</dd>
            </dl>
          </template>
          <p v-else class="mt-2 text-xs text-slate-500">{{ creditsLoaded ? 'This credit is not in the currently loaded credit page. Open the Credits tab and filter by status to find it.' : 'Credit details are unavailable right now.' }}</p>
        </div>
        <p class="mt-3 text-xs text-slate-500">Fee and provider cost for this event are kept on the platform's settlement record and are not part of this response{{ shortId(explanation?.OfferVersionId) ? `; the offer version ${shortId(explanation?.OfferVersionId)} snapshots the terms that applied` : '' }}.</p>
      </section>
    </div>
  </aside>
</Teleport>
</template>
