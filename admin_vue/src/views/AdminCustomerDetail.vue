<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import { isAxiosError } from 'axios';
import { useRoute, useRouter } from 'vue-router';
import ReferralRelationships from '@/components/referrals/ReferralRelationships.vue';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { activeDeviceLabels, hiddenCurrencies, messageStatusLabel, platformLabel, ticketStatusLabel } from '@/lib/customerAccess';
import { formatCurrency, formatDate, formatDateTime, humanize, relativeTime } from '@/lib/formatters';
import { operationsApi, type CustomerDetail, type CustomerSupportData, type UnlockConflict } from '@/lib/operationsApi';
import { amountClass, amountSign, kindLabel } from '@/lib/transactionKinds';

const route = useRoute();
const router = useRouter();
const loading = ref(true);
const refreshing = ref(false);
const deciding = ref(false);
const error = ref('');
const message = ref('');
const decisionNote = ref('');
const detail = ref<CustomerDetail | null>(null);
// Optional second request: account access, tickets and messages. A backend without the endpoint
// answers 404 and those three panels simply stay hidden.
const support = ref<CustomerSupportData | null>(null);
const unlocking = ref(false);
const flagging = ref(false);

const customerId = computed(() => String(route.params.customerId));
const isPendingVerification = computed(() => ['pending', 'submitted', 'reviewing', 'manual_review', 'in_review'].includes(detail.value?.customer.verificationStatus ?? ''));
const canDecide = computed(() => detail.value?.customer.customerType === 'individual' && isPendingVerification.value && Boolean(detail.value?.referenceDetails.providerCustomerId));
const account = computed(() => support.value?.account ?? null);
const lock = computed(() => account.value?.lock ?? null);
const signedInOn = computed(() => (support.value ? activeDeviceLabels(support.value.sessions.items) : []));
const otherCurrencies = computed(() => hiddenCurrencies(detail.value?.balances ?? []));
const tickets = computed(() => support.value?.tickets.items.slice(0, 3) ?? []);
const messages = computed(() => support.value?.notifications.slice(0, 3) ?? []);
const failedMessages = computed(() => {
  const since = Date.now() - 7 * 24 * 3_600_000;
  return support.value?.notifications.filter(m => messageStatusLabel(m.status).tone === 'danger' && Date.parse(m.createdAt) >= since) ?? [];
});
const awaitingTicket = computed(() => support.value?.tickets.items.find(t => t.status === 'awaiting_support') ?? null);
const unlockHint = computed(() => (lock.value && !lock.value.canUnlockNow ? `Unlock is possible from ${formatDateTime(lock.value.unlockAvailableAt)}.` : ''));

function ticketNote(ticket: CustomerSupportData['tickets']['items'][number]) {
  if (ticket.status === 'resolved') return `Resolved ${relativeTime(ticket.updatedAt)}`;
  const when = relativeTime(ticket.lastMessageAt ?? ticket.updatedAt);
  return ticket.lastMessageFromAdmin ? `Support replied ${when} · waiting for the customer` : `Customer wrote ${when}`;
}
function messageNote(message: CustomerSupportData['notifications'][number]) {
  const parts = [message.kind === 'email' ? 'Email' : 'Push', relativeTime(message.sentAt ?? message.createdAt)];
  if (message.readAt) parts.push('opened by the customer');
  return parts.join(' · ');
}
function describe(caught: unknown, fallback: string) {
  if (isAxiosError(caught)) return (caught.response?.data as { message?: string } | undefined)?.message || caught.message || fallback;
  return caught instanceof Error ? caught.message : fallback;
}

async function loadSupport() {
  try {
    support.value = await operationsApi.customerSupport(customerId.value);
  } catch {
    support.value = null;
  }
}

async function unlock() {
  if (!lock.value || unlocking.value || !lock.value.canUnlockNow) return;
  if (!window.confirm(`Unlock the account of ${detail.value?.customer.name ?? 'this customer'}? They will be able to sign in again immediately.`)) return;
  unlocking.value = true;
  message.value = '';
  error.value = '';
  try {
    await operationsApi.unlockAccount(customerId.value);
    message.value = 'The account was unlocked.';
    await Promise.all([load(), loadSupport()]);
  } catch (caught) {
    const body = isAxiosError(caught) && caught.response?.status === 409 ? (caught.response.data as Partial<UnlockConflict>) : null;
    error.value = body?.unlockAvailableAt ? `${body.message || 'The account cannot be unlocked yet.'} Unlock is possible from ${formatDateTime(body.unlockAvailableAt)}.` : describe(caught, 'The account could not be unlocked.');
    await loadSupport();
  } finally {
    unlocking.value = false;
  }
}

async function toggleTestAccount() {
  if (!detail.value || flagging.value) return;
  const next = !detail.value.customer.isTestAccount;
  flagging.value = true;
  message.value = '';
  error.value = '';
  try {
    await operationsApi.setTestAccount(customerId.value, next);
    detail.value.customer.isTestAccount = next;
    message.value = next ? 'Marked as a test account. It is left out of the Overview KPIs.' : 'No longer a test account. It counts in the Overview KPIs again.';
  } catch (caught) {
    error.value = describe(caught, 'The test account setting could not be saved.');
  } finally {
    flagging.value = false;
  }
}

const onboardingSteps = computed(() => {
  const current = humanize(detail.value?.onboarding.currentStep);
  const complete = detail.value?.onboarding.status === 'completed';
  return [
    { label: 'Account created', state: 'completed' },
    { label: 'Customer information', state: complete || current.toLowerCase().includes('verification') ? 'completed' : 'current' },
    { label: detail.value?.customer.customerType === 'business' ? 'Business verification' : 'Identity verification', state: complete ? 'completed' : current.toLowerCase().includes('verification') ? 'current' : 'upcoming' },
    { label: 'Account ready', state: complete ? 'completed' : 'upcoming' },
  ];
});

async function load() {
  loading.value = true;
  error.value = '';
  try {
    detail.value = await operationsApi.customer(customerId.value);
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Customer information could not be loaded.';
  } finally {
    loading.value = false;
  }
}

async function refresh() {
  refreshing.value = true;
  message.value = '';
  try {
    await operationsApi.refreshCustomer(customerId.value);
    await Promise.all([load(), loadSupport()]);
    message.value = 'Customer information was refreshed.';
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Customer refresh failed.';
  } finally {
    refreshing.value = false;
  }
}

async function decide(decision: 'approved' | 'rejected') {
  const providerId = detail.value?.referenceDetails.providerCustomerId;
  if (!providerId || !decisionNote.value.trim()) return;
  deciding.value = true;
  message.value = '';
  try {
    await operationsApi.decideVerification(providerId, decision, decisionNote.value.trim());
    message.value = `Verification ${decision}.`;
    decisionNote.value = '';
    await refresh();
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'The verification decision could not be saved.';
  } finally {
    deciding.value = false;
  }
}

function openCardTransactions(card: CustomerDetail['cards'][number]) {
  router.push({ path: '/money', query: { customerId: customerId.value, cardId: card.reference, context: `${humanize(card.type)} card •••• ${card.lastFour || '—'}` } });
}

function openBudgetTransactions(account: CustomerDetail['accounts'][number]) {
  if (!account.transactionReference) return;
  router.push({ path: '/money', query: { customerId: customerId.value, budgetId: account.transactionReference, context: `${account.name}${account.currency ? ` · ${account.currency}` : ''}` } });
}

function loadAll() { void load(); void loadSupport(); }
watch(customerId, () => { support.value = null; loadAll(); });
onMounted(loadAll);
</script>

<template>
  <AppShell>
    <div v-if="loading" class="space-y-4">
      <div class="h-24 animate-pulse rounded-2xl bg-slate-100" />
      <div class="grid gap-4 md:grid-cols-4"><div v-for="item in 4" :key="item" class="h-28 animate-pulse rounded-2xl bg-slate-100" /></div>
    </div>

    <div v-else-if="error && !detail" class="empty-state">
      <i class="pi pi-exclamation-circle text-3xl text-red-500" />
      <div class="mt-4 font-semibold text-slate-950">Customer unavailable</div>
      <div class="mt-1 text-sm text-slate-500">{{ error }}</div>
      <RouterLink to="/customers" class="secondary-button mt-4">Back to customers</RouterLink>
    </div>

    <template v-else-if="detail">
      <div class="text-sm font-semibold text-slate-500"><RouterLink to="/customers" class="text-blue-700 hover:underline">Customers</RouterLink><span class="mx-2">/</span>{{ detail.customer.name }}</div>
      <section class="mt-5 flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div>
          <div class="flex flex-wrap items-center gap-3">
            <h1 class="page-title">{{ detail.customer.name }}</h1>
            <StatusPill :label="detail.customer.accountStatus" />
            <span v-if="detail.customer.attentionReason" class="status-pill status-pill--warning"><span class="status-pill__dot" />Needs follow-up</span>
            <span v-if="detail.customer.isTestAccount" class="rounded-md bg-violet-50 px-2 py-1 text-xs font-bold uppercase tracking-wide text-violet-700">Test account</span>
          </div>
          <div class="mt-2 flex flex-wrap gap-x-5 gap-y-1 text-sm text-slate-500">
            <span><i class="pi pi-envelope mr-2" />{{ detail.customer.email }}</span>
            <span v-if="detail.customer.phone"><i class="pi pi-phone mr-2" />{{ detail.customer.phone }}</span>
            <span><i :class="detail.customer.customerType === 'business' ? 'pi pi-briefcase' : 'pi pi-user'" class="mr-2" />{{ detail.customer.customerType === 'business' ? 'Business' : 'Person' }}</span>
            <span v-if="account"><i class="pi pi-calendar mr-2" />Customer since {{ formatDate(account.createdAt) }}<template v-if="account.lastLoginAt"> · last sign-in {{ relativeTime(account.lastLoginAt) }}</template><template v-else> · never signed in</template></span>
          </div>
        </div>
        <div class="flex flex-wrap gap-2">
          <button class="secondary-button" :disabled="flagging" :title="detail.customer.isTestAccount ? 'Count this customer in the Overview KPIs again' : 'Leave this internal or test account out of the Overview KPIs'" @click="toggleTestAccount"><i class="pi pi-flag" />{{ detail.customer.isTestAccount ? 'Not a test account' : 'Mark as test account' }}</button>
          <button class="secondary-button" :disabled="refreshing" @click="refresh"><i class="pi pi-refresh" :class="refreshing ? 'pi-spin' : ''" />{{ refreshing ? 'Refreshing…' : 'Refresh data' }}</button>
        </div>
      </section>

      <div v-if="message" class="mt-5 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-800">{{ message }}</div>
      <div v-if="error" class="mt-5 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{{ error }}</div>

      <section v-if="detail.customer.attentionReason" class="mt-6 flex gap-4 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950">
        <i class="pi pi-exclamation-circle mt-0.5 text-xl text-amber-600" />
        <div><div class="font-bold">{{ detail.customer.attentionReason }}</div><div class="mt-1 text-sm text-amber-800">Review the customer’s progress and help them complete the next step.</div></div>
      </section>

      <section v-if="lock" class="mt-4 flex flex-wrap gap-4 rounded-2xl border border-red-200 bg-red-50 p-5 text-red-950">
        <i class="pi pi-lock mt-0.5 text-xl text-red-600" />
        <div class="min-w-0 flex-1 basis-64">
          <div class="font-bold">Account locked since {{ formatDate(lock.lockedAt) }}</div>
          <div class="mt-1 text-sm text-red-800">{{ lock.lockReason === 'duress' ? 'The customer entered their duress password.' : lock.lockReason ? humanize(lock.lockReason) : 'The account was locked for security reasons.' }} {{ lock.canUnlockNow ? 'Unlock is possible now.' : unlockHint }}</div>
        </div>
        <button class="danger-button w-full sm:ml-auto sm:w-auto" :disabled="unlocking || !lock.canUnlockNow" :title="unlockHint || undefined" @click="unlock"><i class="pi pi-lock-open" />{{ unlocking ? 'Unlocking…' : 'Unlock account' }}</button>
      </section>

      <section v-if="awaitingTicket" class="mt-4 flex flex-wrap gap-4 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950">
        <i class="pi pi-ticket mt-0.5 text-xl text-amber-600" />
        <div class="min-w-0 flex-1 basis-64"><div class="font-bold">A support ticket is waiting for a reply</div><div class="mt-1 text-sm text-amber-800">“{{ awaitingTicket.subject }}”, {{ awaitingTicket.lastMessageFromAdmin ? 'updated' : 'written' }} {{ relativeTime(awaitingTicket.lastMessageAt ?? awaitingTicket.updatedAt) }}. The customer is waiting for support.</div></div>
        <RouterLink :to="{ path: '/support', query: { ticket: awaitingTicket.id } }" class="secondary-button w-full sm:ml-auto sm:w-auto">Open ticket</RouterLink>
      </section>

      <section v-if="failedMessages.length" class="mt-4 flex gap-4 rounded-2xl border border-amber-200 bg-amber-50 p-5 text-amber-950">
        <i class="pi pi-send mt-0.5 text-xl text-amber-600" />
        <div class="min-w-0 flex-1"><div class="font-bold">{{ failedMessages.length === 1 ? 'The last message could not be delivered' : `${failedMessages.length} messages could not be delivered` }}</div><div class="mt-1 text-sm text-amber-800">“{{ failedMessages[0].title }}” ({{ failedMessages[0].kind === 'email' ? 'email' : 'push' }}) failed{{ failedMessages[0].attemptCount > 1 ? ` ${failedMessages[0].attemptCount} times` : '' }}<template v-if="failedMessages[0].errorMessage">: {{ failedMessages[0].errorMessage }}</template>. Check the {{ failedMessages[0].kind === 'email' ? 'email address' : 'app notification settings' }} with the customer.</div></div>
      </section>

      <section class="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <div class="metric-card"><div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Onboarding</div><div class="mt-3 text-lg font-bold text-slate-950">{{ humanize(detail.onboarding.currentStep) }}</div><div class="mt-2"><StatusPill :label="detail.onboarding.status" /></div></div>
        <div class="metric-card"><div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Verification</div><div class="mt-3 text-lg font-bold text-slate-950">{{ detail.customer.customerType === 'business' ? 'KYB' : 'KYC' }}</div><div class="mt-2"><StatusPill :label="detail.customer.verificationStatus" /></div></div>
        <div class="metric-card"><div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Available funds</div><div v-if="detail.balances.length" class="mt-3 space-y-1"><div v-for="balance in detail.balances.slice(0, 2)" :key="balance.currency" class="text-lg font-bold text-slate-950">{{ formatCurrency(balance.amount, balance.currency) }}</div><div v-if="otherCurrencies.length" class="text-xs text-slate-500">+ {{ otherCurrencies.join(', ') }} below</div></div><div v-else class="mt-3 text-sm text-slate-500">Not available</div></div>
        <div class="metric-card"><div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Cards</div><div class="mt-3 text-lg font-bold text-slate-950">{{ detail.customer.activeCards }} active</div><div class="mt-2 text-xs text-slate-500">{{ detail.customer.totalCards }} total</div></div>
      </section>

      <section class="mt-4 grid gap-4 xl:grid-cols-3">
        <div class="space-y-4">
        <div class="panel p-5">
          <h2 class="panel-heading">Onboarding progress</h2>
          <div class="mt-5 space-y-0">
            <div v-for="(step, index) in onboardingSteps" :key="step.label" class="relative flex gap-3 pb-7 last:pb-0">
              <div v-if="index < onboardingSteps.length - 1" class="absolute left-[15px] top-8 h-[calc(100%-1rem)] w-0.5 bg-slate-200" />
              <div class="relative z-10 grid size-8 shrink-0 place-items-center rounded-full text-xs font-bold" :class="step.state === 'completed' ? 'bg-emerald-600 text-white' : step.state === 'current' ? 'bg-blue-600 text-white' : 'border border-slate-300 bg-white text-slate-500'">
                <i v-if="step.state === 'completed'" class="pi pi-check text-xs" /><span v-else>{{ index + 1 }}</span>
              </div>
              <div class="pt-1"><div class="text-sm font-semibold text-slate-900">{{ step.label }}</div><div class="mt-1 text-xs text-slate-500">{{ step.state === 'completed' ? 'Completed' : step.state === 'current' ? 'In progress' : 'Not started' }}</div></div>
            </div>
          </div>
        </div>

        <div v-if="account" class="panel p-5">
          <div class="flex items-center justify-between"><h2 class="panel-heading">Account access</h2><StatusPill v-if="lock" label="Locked" tone="danger" /><StatusPill v-else-if="account.status === 'active'" label="Can sign in" tone="success" /><StatusPill v-else :label="account.status" /></div>
          <div class="mt-4 grid grid-cols-[110px_minmax(0,1fr)] gap-x-3 gap-y-3 text-sm">
            <div class="text-[13px] text-slate-500">Last sign-in</div><div class="font-semibold text-slate-800">{{ account.lastLoginAt ? `${formatDateTime(account.lastLoginAt)} · ${relativeTime(account.lastLoginAt)}` : 'Never signed in' }}</div>
            <div class="text-[13px] text-slate-500">Signed in on</div><div class="font-semibold text-slate-800">{{ signedInOn.length ? signedInOn.join(' · ') : 'No device right now' }}</div>
            <div class="text-[13px] text-slate-500">Email</div><div><StatusPill v-if="account.emailVerifiedAt" label="Verified" tone="success" /><StatusPill v-else label="Not verified" tone="warning" /></div>
            <div class="text-[13px] text-slate-500">Two-factor</div><div><StatusPill v-if="account.twoFactorEnabled" label="On" tone="success" /><StatusPill v-else label="Off" tone="neutral" /></div>
            <template v-if="support?.devices.length"><div class="text-[13px] text-slate-500">App</div><div class="font-semibold text-slate-800">{{ support.devices.map(d => `${platformLabel(d.platform)} app${d.appVersion ? ` ${d.appVersion}` : ''}, notifications ${d.isEnabled ? 'on' : 'off'}`).join(' · ') }}</div></template>
            <template v-if="lock"><div class="text-[13px] text-slate-500">Locked</div><div class="font-semibold text-red-700">{{ formatDateTime(lock.lockedAt) }}<span v-if="lock.lockReason" class="font-normal text-slate-500"> · {{ humanize(lock.lockReason) }}</span></div></template>
          </div>
          <button v-if="lock" class="danger-button mt-4 w-full" :disabled="unlocking || !lock.canUnlockNow" :title="unlockHint || undefined" @click="unlock"><i class="pi pi-lock-open" />{{ unlocking ? 'Unlocking…' : 'Unlock account' }}</button>
          <p v-if="lock && unlockHint" class="mt-2 text-xs text-slate-500">{{ unlockHint }}</p>
        </div>
        </div>

        <div class="space-y-4">
          <div class="panel p-5">
            <div class="flex items-center justify-between"><h2 class="panel-heading">Verification</h2><StatusPill :label="detail.customer.verificationStatus" /></div>
            <div class="mt-4 grid grid-cols-2 gap-3 text-sm"><div><div class="text-xs text-slate-500">Submitted</div><div class="mt-1 font-semibold text-slate-800">{{ formatDateTime(detail.verification.submittedAt) }}</div></div><div><div class="text-xs text-slate-500">Level</div><div class="mt-1 font-semibold text-slate-800">{{ humanize(detail.verification.level) }}</div></div></div>
            <div v-if="canDecide" class="mt-5 border-t border-slate-100 pt-4">
              <label class="text-xs font-semibold text-slate-600">Decision note</label>
              <textarea v-model="decisionNote" rows="2" class="field-control mt-2 w-full py-2.5" placeholder="Reason for the decision" />
              <div class="mt-3 flex gap-2"><button class="primary-button flex-1" :disabled="deciding || !decisionNote.trim()" @click="decide('approved')"><i class="pi pi-check" />Approve</button><button class="danger-button flex-1" :disabled="deciding || !decisionNote.trim()" @click="decide('rejected')"><i class="pi pi-times" />Reject</button></div>
            </div>
          </div>

          <div class="panel p-5">
            <div class="flex items-center justify-between"><h2 class="panel-heading">Cards</h2><RouterLink to="/cards" class="text-xs font-semibold text-blue-700">View all</RouterLink></div>
            <div v-if="detail.cards.length" class="mt-4 space-y-3"><button v-for="card in detail.cards" :key="card.reference" class="flex w-full items-center justify-between rounded-xl border border-slate-200 p-3 text-left transition hover:border-blue-200 hover:bg-blue-50/50" @click="openCardTransactions(card)"><div><div class="text-sm font-semibold text-slate-900">{{ humanize(card.type) }} ·•••• {{ card.lastFour || '—' }}</div><div class="mt-1 text-xs text-slate-500">Issued {{ formatDate(card.issuedAt) }}<span v-if="card.balance !== null && card.currency"> · {{ formatCurrency(card.balance, card.currency) }}</span></div></div><div class="flex items-center gap-3"><StatusPill :label="card.status" /><i class="pi pi-angle-right text-slate-400" /></div></button></div>
            <div v-else class="mt-4 text-sm text-slate-500">No cards have been issued.</div>
          </div>

          <div v-if="support" class="panel p-5">
            <div class="flex items-center justify-between"><h2 class="panel-heading">Support tickets</h2><RouterLink to="/support" class="text-xs font-semibold text-blue-700">Open inbox</RouterLink></div>
            <div v-if="tickets.length" class="mt-4 divide-y divide-slate-100">
              <RouterLink v-for="ticket in tickets" :key="ticket.id" :to="{ path: '/support', query: { ticket: ticket.id } }" class="flex items-center justify-between gap-3 py-3 first:pt-0 last:pb-0 hover:text-blue-700">
                <div class="min-w-0"><div class="truncate text-sm font-semibold text-slate-900">{{ ticket.subject }}</div><div class="mt-1 text-xs text-slate-500">{{ ticketNote(ticket) }}</div></div>
                <div class="flex shrink-0 items-center gap-3"><StatusPill :label="ticketStatusLabel(ticket.status).label" :tone="ticketStatusLabel(ticket.status).tone" /><i class="pi pi-angle-right text-slate-400" /></div>
              </RouterLink>
            </div>
            <div v-else class="mt-4 text-sm text-slate-500">The customer has not opened any tickets.</div>
            <div v-if="support.tickets.totalCount > tickets.length" class="mt-3 text-xs text-slate-500">{{ support.tickets.totalCount - tickets.length }} older {{ support.tickets.totalCount - tickets.length === 1 ? 'ticket' : 'tickets' }} in the inbox.</div>
          </div>
        </div>

        <div class="space-y-4">
          <div class="panel p-5">
            <div class="flex items-center justify-between"><h2 class="panel-heading">Accounts, budgets & balances</h2><RouterLink to="/money" class="text-xs font-semibold text-blue-700">View money</RouterLink></div>
            <div v-if="detail.accounts.length" class="mt-4 divide-y divide-slate-100"><button v-for="account in detail.accounts" :key="account.reference" class="flex w-full items-center justify-between py-3 text-left first:pt-0" :class="account.transactionReference ? 'cursor-pointer hover:text-blue-700' : 'cursor-default'" @click="openBudgetTransactions(account)"><div><div class="text-sm font-semibold">{{ account.name }}</div><div class="mt-1 text-xs text-slate-500">{{ humanize(account.status) }}</div></div><div class="flex items-center gap-3"><div v-if="account.balance !== null && account.currency" class="text-sm font-bold text-slate-950">{{ formatCurrency(account.balance, account.currency) }}</div><div v-else class="text-xs text-slate-400">Not available</div><i v-if="account.transactionReference" class="pi pi-angle-right text-slate-400" /></div></button></div>
            <div v-else-if="detail.balances.length" class="mt-4 divide-y divide-slate-100"><div v-for="balance in detail.balances" :key="balance.currency" class="flex items-center justify-between py-3"><span class="font-semibold text-slate-700">{{ balance.currency }}</span><span class="font-bold text-slate-950">{{ formatCurrency(balance.amount, balance.currency) }}</span></div></div>
            <div v-else class="mt-4 text-sm text-slate-500">Account balances are not available yet.</div>
          </div>

          <div class="panel p-5">
            <div class="flex items-center justify-between"><h2 class="panel-heading">Recent activity</h2><RouterLink :to="{ path: '/money', query: { customerId } }" class="text-xs font-semibold text-blue-700">View all</RouterLink></div>
            <div v-if="detail.recentTransactions.length" class="mt-4 divide-y divide-slate-100"><div v-for="transaction in detail.recentTransactions.slice(0, 6)" :key="transaction.reference" class="flex items-center justify-between gap-3 py-3 first:pt-0"><div class="min-w-0"><div class="truncate text-sm font-semibold text-slate-900" :title="transaction.description">{{ transaction.merchant || transaction.description }}</div><div class="mt-1 text-xs text-slate-500">{{ kindLabel(transaction.kind, transaction.feeType) }} · {{ relativeTime(transaction.occurredAt) }} · {{ humanize(transaction.status) }}</div></div><div class="whitespace-nowrap text-sm font-bold" :class="amountClass(transaction)">{{ amountSign(transaction.direction) }}{{ formatCurrency(transaction.amount, transaction.currency) }}</div></div></div>
            <div v-else class="mt-4 text-sm text-slate-500">No recent transactions.</div>
          </div>

          <div v-if="support" class="panel p-5">
            <h2 class="panel-heading">Messages sent to the customer</h2>
            <div v-if="messages.length" class="mt-4 divide-y divide-slate-100">
              <div v-for="item in messages" :key="item.id" class="py-3 first:pt-0 last:pb-0">
                <div class="flex items-center justify-between gap-3">
                  <div class="min-w-0"><div class="truncate text-sm font-semibold text-slate-900">{{ item.title || (item.kind === 'email' ? 'Email' : 'Push notification') }}</div><div class="mt-1 text-xs text-slate-500">{{ messageNote(item) }}</div></div>
                  <StatusPill :label="messageStatusLabel(item.status).label" :tone="messageStatusLabel(item.status).tone" />
                </div>
                <div v-if="messageStatusLabel(item.status).tone === 'danger' && item.errorMessage" class="mt-2 rounded-lg bg-red-50 px-3 py-2 text-xs text-red-700">{{ item.errorMessage }}</div>
              </div>
            </div>
            <div v-else class="mt-4 text-sm text-slate-500">Nothing has been sent to this customer yet.</div>
          </div>
        </div>
      </section>

      <div class="mt-4"><ReferralRelationships :key="customerId" :customer-id="customerId" /></div>
      <details class="panel mt-4 p-5 text-sm">
        <summary class="cursor-pointer font-semibold text-slate-700">Reference details</summary>
        <div class="mt-4 grid gap-4 text-xs text-slate-500 sm:grid-cols-2"><div><div class="font-semibold text-slate-700">Internal customer reference</div><div class="mt-1 break-all">{{ detail.referenceDetails.localCustomerId }}</div></div><div><div class="font-semibold text-slate-700">Banking provider reference</div><div class="mt-1 break-all">{{ detail.referenceDetails.providerCustomerId || 'Not connected' }}</div></div></div>
      </details>
    </template>
  </AppShell>
</template>
