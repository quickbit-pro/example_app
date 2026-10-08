<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue';
import Dialog from 'primevue/dialog';
import MorShell from '@/components/MorShell.vue';
import { money, date, morError } from '@/lib/morApi';
import { userGet, userPost, type AssignedCard, type UserCards, type CardHistory, type LoadRequest } from '@/lib/morUserApi';
const data = ref<UserCards>(), loading = ref(false), busy = ref(false), error = ref(''), notice = ref('');
const selected = ref<AssignedCard>(), dialog = ref<'history'|'load'|'secure'|'freeze'|null>(null), dialogError = ref('');
const amount = ref<number>(), note = ref(''), password = ref(''), code = ref(''), widgetUrl = ref('');
const history = ref<CardHistory>(), historyBusy = ref(false), offset = ref(0), pageSize = 25;
const open = computed({ get: () => dialog.value !== null, set: v => { if (!v && !busy.value) dialog.value = null; } });
const frozen = (c: AssignedCard) => c.isLocked || ['FROZEN','LOCKED'].includes(c.status.toUpperCase());
const closed = (c: AssignedCard) => ['CANCELLED','CANCELED','CLOSED','DELETED','TERMINATED'].includes(c.status.toUpperCase());
const number = (c?: AssignedCard) => c?.maskedCardNumber || `•••• •••• •••• ${c?.cardNumberLastFour || '----'}`;
const title = computed(() => ({history:'Card transactions',load:selected.value?.pendingLoadRequest ? 'Update load request' : 'Request a card load',secure:'Secure card details',freeze:selected.value && frozen(selected.value)?'Unfreeze card':'Freeze card'}[dialog.value || 'history']));
async function load() {
  loading.value = true; error.value = '';
  try { data.value = await userGet<UserCards>(); } catch (e) { error.value = morError(e); } finally { loading.value = false; }
}
function show(card: AssignedCard, action: typeof dialog.value) {
  selected.value = card; dialog.value = action; dialogError.value = ''; widgetUrl.value = ''; password.value = ''; code.value = '';
  amount.value = card.pendingLoadRequest?.amount; note.value = card.pendingLoadRequest?.note || '';
  history.value = undefined; offset.value = 0;
  if (action === 'history') void getHistory();
}
async function getHistory() {
  if (!selected.value) return;
  historyBusy.value = true; dialogError.value = '';
  try { history.value = await userGet<CardHistory>(`/${selected.value.id}/transactions`, { limit:pageSize, offset:offset.value }); }
  catch (e) { dialogError.value = morError(e); } finally { historyBusy.value = false; }
}
async function turnPage(delta:number) { offset.value = Math.max(0,offset.value + delta*pageSize); await getHistory(); }
async function submit() {
  if (!selected.value || busy.value) return;
  busy.value = true; dialogError.value = ''; notice.value = '';
  try {
    const id = selected.value.id;
    if (dialog.value === 'secure') {
      const result = await userPost<{success:boolean; widgetUrl:string; message?:string}>(`/${id}/widget`, {currentPassword:password.value, code:code.value || null});
      password.value = ''; code.value = '';
      if (!result.success || new URL(result.widgetUrl).protocol !== 'https:') throw new Error(result.message || 'Unable to reveal card details.');
      widgetUrl.value = result.widgetUrl;
      return;
    }
    if (dialog.value === 'load') {
      const result = await userPost<LoadRequest>(`/${id}/load-requests`, {amount:amount.value,note:note.value.trim() || null});
      notice.value = result.adminEmailSent ? 'Load request sent to your MOR administrator.' : 'Load request saved. The email notification could not be delivered; contact your MOR administrator.';
    } else {
      const isFrozen = frozen(selected.value);
      const result = await userPost<{success?:boolean; message?:string}>(`/${id}/${isFrozen?'unfreeze':'freeze'}`);
      if (result.success === false) throw new Error(result.message || 'Unable to update this card.');
      notice.value = isFrozen ? 'Card unfrozen.' : 'Card frozen.';
    }
    dialog.value = null; await load();
  } catch (e) { dialogError.value = morError(e); }
  finally { busy.value = false; }
}
watch(dialog, value => { if (!value) { widgetUrl.value = ''; password.value = ''; code.value = ''; } });
onMounted(load);
</script>
<template>
  <MorShell><div class="mor-page space-y-6">
    <header class="flex flex-wrap items-end justify-between gap-4"><div><h1 class="page-title">My Cards</h1><p class="page-subtitle">View balances and manage cards assigned to you.</p></div><button class="secondary-button" :disabled="loading" @click="load"><i class="pi pi-refresh" />Refresh</button></header>
    <p v-if="error" class="mor-error" role="alert">{{ error }}</p><p v-if="notice" class="mor-success" role="status">{{ notice }}</p>
    <p v-if="loading" class="mor-empty">Loading your cards…</p>
    <section v-else-if="data && !data.cards.length" class="panel p-14 text-center"><i class="pi pi-credit-card text-3xl text-slate-400" /><h2 class="mt-4 font-semibold">No assigned cards</h2><p class="page-subtitle">Your MOR administrator has not assigned a card to you yet.</p></section>
    <div v-else-if="data" class="grid items-start gap-5 xl:grid-cols-2">
      <article v-for="card in data.cards" :key="card.id" class="panel overflow-hidden">
        <header class="flex items-start justify-between gap-3 border-b border-slate-200 bg-white p-5"><div class="min-w-0"><p class="text-xs font-semibold uppercase tracking-wider text-slate-500">{{card.isPhysical?'Physical card':'Virtual card'}}</p><h2 class="mt-2 break-words font-mono text-lg font-semibold">{{ number(card) }}</h2><p class="mt-1 text-xs text-slate-500">{{card.cardholderName}}</p></div><span class="mor-badge">{{card.status}}</span></header>
        <div class="space-y-4 p-5">
          <div class="rounded-xl border border-slate-200 bg-slate-50 p-5"><p class="text-xs uppercase tracking-wide text-slate-500">Available balance</p><p class="mt-2 text-3xl font-semibold tracking-tight">{{money(card.availableBalance,card.currency)}}</p><p class="mt-2 text-xs text-slate-500">{{money(card.pendingBalance,card.currency)}} pending</p></div>
          <div v-if="card.pendingLoadRequest" class="rounded-xl border border-amber-200 bg-amber-50 p-4 text-sm"><b>Load request pending · {{money(card.pendingLoadRequest.amount,card.pendingLoadRequest.currency)}}</b><p class="mt-1 text-xs">Sent {{date(card.pendingLoadRequest.updatedAt)}}</p><p v-if="card.pendingLoadRequest.note" class="mt-2">{{card.pendingLoadRequest.note}}</p></div>
          <div class="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <button class="secondary-button" :disabled="closed(card)" @click="show(card,'secure')"><i class="pi pi-key" />Secure details</button>
            <button class="secondary-button" :disabled="!data.capabilities.transactions" @click="show(card,'history')"><i class="pi pi-history" />Transactions</button>
            <button class="secondary-button" :disabled="closed(card) || !data.capabilities.loadRequests" @click="show(card,'load')"><i class="pi pi-download" />{{card.pendingLoadRequest?'Update request':'Request load'}}</button>
            <button class="secondary-button" :disabled="closed(card)" @click="show(card,'freeze')"><i :class="`pi ${frozen(card)?'pi-lock-open':'pi-lock'}`" />{{frozen(card)?'Unfreeze':'Freeze'}}</button>
          </div>
          <p v-if="!data.capabilities.transactions || !data.capabilities.loadRequests" class="text-xs text-slate-500">{{!data.capabilities.transactions?'Transaction history is not enabled for this connection. ':''}}{{!data.capabilities.loadRequests?'Load requests are not enabled for this connection.':''}}</p>
        </div>
      </article>
    </div>
    <Dialog v-model:visible="open" modal :header="title" :closable="!busy" :style="{width:dialog==='history'?'46rem':'30rem',maxWidth:'95vw'}">
      <div class="space-y-4"><p class="text-sm text-slate-500">{{number(selected)}}</p><p v-if="dialogError" class="mor-error" role="alert">{{dialogError}}</p>
        <template v-if="dialog==='history'"><p v-if="historyBusy" class="mor-empty">Loading transactions…</p><template v-else-if="history"><p v-if="!history.data.length" class="mor-empty">No transactions yet.</p><div v-for="tx in history.data" :key="tx.id" class="flex justify-between gap-4 border-b border-slate-200 py-3"><div class="min-w-0"><p class="break-words font-semibold">{{tx.merchantName||tx.description||tx.transactionType}}</p><p class="mt-1 text-xs text-slate-500">{{date(tx.transactionDate)}}{{tx.category?` · ${tx.category}`:''}}</p></div><div class="shrink-0 text-right text-sm"><b>{{money(tx.amount,tx.currency)}}</b><p>{{tx.status}}</p></div></div><div class="flex items-center justify-between gap-3"><button class="secondary-button" :disabled="offset===0" @click="turnPage(-1)">Previous</button><span class="text-xs">{{history.total}} transactions</span><button class="secondary-button" :disabled="offset+pageSize>=history.total" @click="turnPage(1)">Next</button></div></template></template>
        <iframe v-else-if="dialog==='secure' && widgetUrl" :src="widgetUrl" title="Secure card details" referrerpolicy="no-referrer" sandbox="allow-scripts allow-same-origin allow-forms" class="h-96 w-full border-0" />
        <form v-else class="space-y-4" @submit.prevent="submit">
          <template v-if="dialog==='load'"><p class="text-sm text-slate-500">Your MOR administrator reviews and funds this request.</p><label class="mor-field">Amount ({{selected?.currency}})<input v-model.number="amount" type="number" min="0.01" max="250000" step="0.01" required class="field-control" /></label><label class="mor-field">Note (optional)<textarea v-model="note" maxlength="500" class="field-control" /></label></template>
          <template v-else-if="dialog==='secure'"><p class="text-sm text-slate-500">Confirm your identity to reveal these card details.</p><label class="mor-field">Current password<input v-model="password" type="password" autocomplete="current-password" required class="field-control" /></label><label class="mor-field">Authenticator code (if enabled)<input v-model="code" autocomplete="one-time-code" maxlength="16" class="field-control" /></label></template>
          <p v-else class="text-sm">{{selected && frozen(selected)?'Unfreeze this card to allow payments again?':'Freeze this card to temporarily prevent new payments?'}}</p>
          <button class="primary-button w-full" :disabled="busy">{{busy?'Processing…':dialog==='secure'?'Verify and reveal':dialog==='load'?'Send load request':'Confirm'}}</button>
        </form>
      </div>
    </Dialog>
  </div></MorShell>
</template>
