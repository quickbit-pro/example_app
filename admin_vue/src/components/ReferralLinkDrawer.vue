<script setup lang="ts">
// Campaign link drawer (blueprint p17, p27): what the link is, who owns it, where it points, and what it
// brought in. Since addendum A the platform serves per-link performance to admins for any owner
// (GET links/{id}/performance?range): clicks, unique clicks, click→sign-up rate, sign-ups, verified,
// qualified, earning and the owner's rewards accrued and paid through the link, for a chosen period.
// On a platform that predates the route (404) the drawer keeps the link's own lifetime counters.
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import StatusPill from '@/components/StatusPill.vue';
import { describeAdminError } from '@/lib/adminApi';
import { money } from '@/lib/referrals';
import { referralsApi } from '@/lib/referralsApi';
import { PERFORMANCE_RANGES, channelLabel, clickToSignupRate, clicksTracked, effectiveLinkStatus, linkActions, linkStatusTone, ownerLabel, qualificationShare, ratePercent,
  type CampaignLink, type CampaignLinkPerformance, type PerformanceRange } from '@/lib/referralLinks';
const props = defineProps<{ link: CampaignLink; busy: boolean }>();
const emit = defineEmits<{ close: []; pause: []; resume: []; archive: [] }>();
const status = computed(() => effectiveLinkStatus(props.link));
const actions = computed(() => linkActions(props.link));
const share = computed(() => qualificationShare(props.link));
const tracked = computed(() => clicksTracked(props.link));
const lifetimeRate = computed(() => clickToSignupRate(props.link.SignupCount, props.link.UniqueClickCount));
const date = (value: string | null | undefined) => value ? new Date(value).toLocaleString() : '—';

// ---- period performance ----
const range = ref<PerformanceRange>('30d');
const performance = ref<CampaignLinkPerformance | null>(null);
const performanceLoading = ref(false);
const performanceError = ref('');
/** The platform answered 404: no per-link performance route; lifetime counters only. */
const performanceUnavailable = ref(false);
let requestId = 0;
async function loadPerformance() {
  const id = ++requestId;
  performanceLoading.value = true; performanceError.value = '';
  try {
    const result = await referralsApi.linkPerformance(props.link.Id, range.value);
    if (id !== requestId) return;
    performance.value = result; performanceUnavailable.value = false;
  } catch (e) {
    if (id !== requestId) return;
    performance.value = null;
    if ((e as { response?: { status?: number } })?.response?.status === 404) performanceUnavailable.value = true;
    else performanceError.value = describeAdminError(e);
  } finally { if (id === requestId) performanceLoading.value = false; }
}
watch([range, () => props.link.Id], loadPerformance, { immediate: true });
const rows = computed(() => {
  const p = performance.value; if (!p) return [];
  return [
    { label: 'Clicks', value: String(p.Clicks), note: 'Sign-up page opened through this link' },
    { label: 'Unique clicks', value: String(p.UniqueClicks), note: 'Visitors counted once per day' },
    { label: 'Click→sign-up rate', value: ratePercent(p.ClickToSignupRate), note: 'Sign-ups per unique click' },
    { label: 'Sign-ups', value: String(p.Signups) },
    { label: 'Verified', value: String(p.Verified) },
    { label: 'Qualified', value: String(p.Qualified) },
    { label: 'Earning', value: String(p.Earning), note: 'Friends who earned the owner something' },
    { label: 'Rewards accrued', value: money(p.RewardsAccrued, p.Currency), note: "On the owner's ledger for these friends" },
    { label: 'Rewards paid', value: money(p.RewardsPaid, p.Currency) },
  ];
});
function onKey(event: KeyboardEvent) { if (event.key === 'Escape') emit('close'); }
onMounted(() => document.addEventListener('keydown', onKey)); onBeforeUnmount(() => document.removeEventListener('keydown', onKey));
</script>

<template>
<Teleport to="body">
  <div class="fixed inset-0 z-40 bg-slate-950/30" aria-hidden="true" @click="emit('close')" />
  <aside class="fixed inset-y-0 right-0 z-50 flex w-full max-w-lg flex-col overflow-y-auto border-l border-slate-200 bg-white shadow-2xl" role="dialog" aria-modal="true" aria-labelledby="link-drawer-title">
    <header class="flex items-start justify-between gap-3 border-b border-slate-200 p-5">
      <div><p class="text-xs uppercase tracking-wide text-slate-500">Campaign link</p><h2 id="link-drawer-title" class="mt-1 text-lg font-bold">{{ link.Name }}</h2>
        <div class="mt-2 flex flex-wrap items-center gap-2"><StatusPill :label="status" :tone="linkStatusTone(status)" /><span class="font-mono text-xs text-slate-500">{{ link.Code }}</span></div></div>
      <button type="button" class="secondary-button" @click="emit('close')">Close</button>
    </header>
    <div class="space-y-6 p-5 text-sm">
      <section>
        <div class="flex flex-wrap items-end justify-between gap-2">
          <h3 class="font-semibold">Performance</h3>
          <label v-if="!performanceUnavailable" class="referral-field text-xs">Period<select v-model="range" class="field-control" aria-label="Performance period"><option v-for="r in PERFORMANCE_RANGES" :key="r.id" :value="r.id">{{ r.label }}</option></select></label>
        </div>
        <p v-if="performanceError" role="alert" class="mt-2 text-xs text-red-700">Could not load performance. {{ performanceError }} <button type="button" class="underline" @click="loadPerformance">Retry</button></p>
        <p v-else-if="performanceLoading && !performance" class="mt-2 text-xs text-slate-500">Loading performance…</p>
        <dl v-else-if="performance" class="mt-2 grid grid-cols-[11rem_1fr] gap-y-1.5" :class="{ 'opacity-60': performanceLoading }" aria-live="polite">
          <template v-for="row in rows" :key="row.label">
            <dt class="text-slate-500">{{ row.label }}</dt>
            <dd class="font-semibold">{{ row.value }}<span v-if="row.note" class="block text-xs font-normal text-slate-500">{{ row.note }}</span></dd>
          </template>
        </dl>
        <p v-if="performance" class="mt-2 text-xs text-slate-500">Friends who signed up through this link in the period; clicks are visitors who opened the sign-up page with it, once per visitor per day. Rewards are the owner's and follow the ledger — a pending reward is never shown as paid.</p>
        <div class="mt-3 grid grid-cols-3 gap-3">
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Sign-ups, all time</div><div class="mt-1 text-xl font-bold">{{ link.SignupCount }}</div></div>
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Qualified, all time</div><div class="mt-1 text-xl font-bold">{{ link.QualifiedCount }}</div></div>
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Qualification</div><div class="mt-1 text-xl font-bold">{{ share === null ? '—' : `${share}%` }}</div></div>
        </div>
        <div v-if="tracked" class="mt-3 grid grid-cols-3 gap-3">
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Clicks, all time</div><div class="mt-1 text-xl font-bold">{{ link.ClickCount ?? 0 }}</div></div>
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Unique, all time</div><div class="mt-1 text-xl font-bold">{{ link.UniqueClickCount ?? 0 }}</div></div>
          <div class="rounded-lg border border-slate-200 p-3"><div class="text-xs text-slate-500">Click→sign-up</div><div class="mt-1 text-xl font-bold">{{ ratePercent(lifetimeRate) }}</div></div>
        </div>
        <p class="mt-2 text-xs text-slate-500">{{ performanceUnavailable ? 'This platform does not serve per-link performance yet; the counters above are kept by the platform as relationships attribute through the link and qualify.' : 'Lifetime counters are kept by the platform as visitors click, relationships attribute through the link and qualify.' }}</p>
      </section>
      <section><h3 class="font-semibold">Owner and programme</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Owner</dt><dd>{{ ownerLabel(link) }}<span v-if="link.OwnerEmail && link.OwnerName" class="block text-xs text-slate-500">{{ link.OwnerEmail }}</span><span v-if="link.OwnerUserId" class="block text-xs text-slate-500">#{{ link.OwnerUserId }}</span></dd>
          <dt class="text-slate-500">Programme</dt><dd>{{ link.ProgramName || '—' }}<span class="block font-mono text-xs text-slate-500">{{ link.ProgramId }}</span></dd>
          <dt class="text-slate-500">Offer version</dt><dd class="font-mono text-xs">{{ link.OfferVersionId || 'Current offer (no version snapshot)' }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Link</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Channel</dt><dd>{{ channelLabel(link.Channel) }}</dd>
          <dt class="text-slate-500">Language</dt><dd>{{ link.Locale || '—' }}</dd>
          <dt class="text-slate-500">Destination</dt><dd>{{ link.Destination || 'signup' }}<span class="block text-xs text-slate-500">Where the friend lands after sign-up</span></dd>
          <dt class="text-slate-500">Share URL</dt><dd class="break-all font-mono text-xs">{{ link.ShareUrl || '—' }}</dd>
          <dt class="text-slate-500">Caption</dt><dd>{{ link.SuggestedCaption || 'Not generated' }}</dd>
        </dl>
      </section>
      <section><h3 class="font-semibold">Lifecycle</h3>
        <dl class="mt-2 grid grid-cols-[9rem_1fr] gap-y-1.5">
          <dt class="text-slate-500">Created</dt><dd>{{ date(link.CreatedAt) }}</dd>
          <dt class="text-slate-500">Active from</dt><dd>{{ date(link.ActiveFrom) }}</dd>
          <dt class="text-slate-500">Expires</dt><dd>{{ link.ExpiresAt ? date(link.ExpiresAt) : 'No expiry' }}</dd>
          <dt class="text-slate-500">Link ID</dt><dd class="font-mono text-xs">{{ link.Id }}</dd>
        </dl>
        <div class="mt-3 flex flex-wrap gap-2">
          <button v-if="actions.pause" type="button" class="secondary-button" :disabled="busy" @click="emit('pause')">Pause</button>
          <button v-if="actions.resume" type="button" class="secondary-button" :disabled="busy" @click="emit('resume')">Resume</button>
          <button v-if="actions.archive" type="button" class="secondary-button" :disabled="busy" @click="emit('archive')">Archive</button>
        </div>
        <p class="mt-2 text-xs text-slate-500">Pausing stops new attribution through this link and leaves existing relationships untouched. Archiving is permanent.</p>
      </section>
    </div>
  </aside>
</Teleport>
</template>
