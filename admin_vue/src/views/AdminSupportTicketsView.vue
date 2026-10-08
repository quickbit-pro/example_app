<script setup lang="ts">
import { onMounted, ref, watch } from 'vue';
import { isAxiosError } from 'axios';
import { useRoute } from 'vue-router';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { formatDateTime } from '@/lib/formatters';
import { supportApi, ticketStatusLabels, type TicketDetail, type TicketPage } from '@/lib/supportApi';

const route = useRoute();
const status = ref('');
const offset = ref(0);
const page = ref<TicketPage>({ items: [], totalCount: 0 });
const loading = ref(false);
const opening = ref(false);
const busy = ref(false);
const listError = ref('');
const error = ref('');
const success = ref('');
const detail = ref<TicketDetail | null>(null);
const draft = ref('');
let listRequest = 0;
let detailRequest = 0;

function message(caught: unknown): string {
  if (isAxiosError(caught)) return caught.response?.data?.message || 'The request could not be completed. Please try again.';
  return 'The request could not be completed. Please try again.';
}
async function load() {
  const request = ++listRequest;
  loading.value = true;
  listError.value = '';
  try {
    const result = await supportApi.list(status.value, offset.value);
    if (request === listRequest) page.value = result;
  } catch (caught) { if (request === listRequest) listError.value = message(caught); }
  finally { if (request === listRequest) loading.value = false; }
}
async function open(id: string) {
  if (busy.value) return;
  if (detail.value?.ticket.id !== id && draft.value.trim() && !window.confirm('Discard the unsent reply and open another ticket?')) return;
  const request = ++detailRequest;
  const sameTicket = detail.value?.ticket.id === id;
  opening.value = true;
  error.value = '';
  success.value = '';
  try {
    const result = await supportApi.get(id);
    if (request !== detailRequest) return;
    detail.value = result;
    if (!sameTicket) draft.value = '';
  } catch (caught) { if (request === detailRequest) error.value = message(caught); }
  finally { if (request === detailRequest) opening.value = false; }
}
async function update(action: 'reply' | 'resolved' | 'awaiting_support') {
  if (!detail.value || busy.value || opening.value) return;
  const ticket = detail.value.ticket;
  busy.value = true;
  error.value = '';
  success.value = '';
  try {
    detail.value = action === 'reply'
      ? await supportApi.reply(ticket.id, draft.value.trim(), ticket.revision)
      : await supportApi.setStatus(ticket.id, action, ticket.revision);
    if (action === 'reply') draft.value = '';
    success.value = action === 'reply' ? 'Reply submitted. The customer will be notified.' : 'Ticket status updated.';
    await load();
  } catch (caught) { error.value = message(caught); }
  finally { busy.value = false; }
}
watch(status, () => { offset.value = 0; void load(); });
// The customer page links here with ?ticket=<id>: open that ticket alongside the inbox.
onMounted(() => {
  void load();
  const ticket = typeof route.query.ticket === 'string' ? route.query.ticket : '';
  if (ticket) void open(ticket);
});
</script>

<template>
  <AppShell>
    <h1 class="page-title">Support tickets</h1>
    <p class="page-subtitle">Review requests and reply when ready. Customers are told that replies are not immediate.</p>
    <div class="mt-7 grid items-start gap-5 xl:grid-cols-[minmax(320px,2fr)_minmax(0,3fr)]">
      <section class="panel min-w-0 p-4" aria-label="Ticket inbox">
        <div class="flex gap-3">
          <select v-model="status" class="field-control min-w-0 flex-1" aria-label="Filter by ticket status">
            <option value="">All tickets</option>
            <option v-for="(label, value) in ticketStatusLabels" :key="value" :value="value">{{ label }}</option>
          </select>
          <button class="icon-button" :disabled="loading" aria-label="Refresh tickets" @click="load"><i class="pi pi-refresh" /></button>
        </div>
        <div v-if="listError" class="mt-4 text-sm text-red-700" role="alert">{{ listError }} <button class="underline" @click="load">Retry</button></div>
        <p v-if="loading" class="p-6 text-sm text-slate-500" role="status">Loading tickets…</p>
        <template v-else-if="!listError">
          <p v-if="!page.items.length" class="py-10 text-center text-sm text-slate-500">No tickets match this filter.</p>
          <button v-for="ticket in page.items" :key="ticket.id" type="button" :disabled="busy || opening"
            class="mt-3 w-full rounded-xl border p-4 text-left transition hover:border-blue-300 disabled:opacity-60"
            :class="detail?.ticket.id === ticket.id ? 'border-blue-400 bg-blue-50' : 'border-slate-200'" @click="open(ticket.id)">
            <div class="break-words font-semibold text-slate-950">{{ ticket.subject }}</div>
            <div class="mt-1 break-all text-xs text-slate-500">{{ ticket.customerName || ticket.customerEmail || 'Customer' }}</div>
            <div class="mt-3 flex flex-wrap items-center justify-between gap-2">
              <StatusPill :label="ticketStatusLabels[ticket.status]" />
              <time class="text-xs text-slate-500">{{ formatDateTime(ticket.updatedAt) }}</time>
            </div>
          </button>
          <div v-if="page.totalCount > 30" class="mt-4 flex items-center justify-between text-sm">
            <button class="secondary-button" :disabled="offset === 0" @click="offset -= 30; load()">Previous</button>
            <span>{{ offset + 1 }}–{{ Math.min(offset + 30, page.totalCount) }} of {{ page.totalCount }}</span>
            <button class="secondary-button" :disabled="offset + 30 >= page.totalCount" @click="offset += 30; load()">Next</button>
          </div>
        </template>
      </section>
      <section class="panel min-w-0 p-5 sm:p-7" aria-label="Ticket correspondence" :aria-busy="opening">
        <p v-if="opening" class="mb-4 text-sm text-slate-500" role="status">Loading ticket…</p>
        <div v-if="error" class="mb-4 rounded-xl bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</div>
        <div v-if="success" class="mb-4 rounded-xl bg-emerald-50 p-4 text-sm text-emerald-800" role="status">{{ success }}</div>
        <template v-if="detail">
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0">
              <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">Ticket #{{ detail.ticket.id.slice(-8).toUpperCase() }}</div>
              <h2 class="mt-2 break-words text-xl font-bold text-slate-950">{{ detail.ticket.subject }}</h2>
              <p class="mt-1 break-all text-sm text-slate-500">{{ detail.ticket.customerName }} · {{ detail.ticket.customerEmail }}</p>
              <RouterLink v-if="detail.ticket.customerId" :to="`/customers/${encodeURIComponent(detail.ticket.customerId)}`"
                target="_blank" rel="noopener noreferrer" class="mt-3 inline-flex items-center gap-2 text-sm font-semibold text-blue-700 hover:underline"
                aria-label="Open customer profile (opens in a new tab)">
                Open customer profile <i class="pi pi-external-link text-xs" aria-hidden="true" />
              </RouterLink>
              <p v-if="detail.ticket.customerId" class="mt-1 text-xs text-slate-500">View customer data, balances and transactions in a new tab.</p>
            </div>
            <button class="icon-button shrink-0" :disabled="busy || opening" aria-label="Refresh ticket" @click="open(detail.ticket.id)"><i class="pi pi-refresh" /></button>
          </div>
          <div class="mt-4 flex flex-wrap items-center gap-3">
            <StatusPill :label="ticketStatusLabels[detail.ticket.status]" />
            <button class="secondary-button" :disabled="busy || opening" @click="update(detail.ticket.status === 'resolved' ? 'awaiting_support' : 'resolved')">
              {{ detail.ticket.status === 'resolved' ? 'Reopen ticket' : 'Mark resolved' }}
            </button>
          </div>
          <ol class="mt-6 space-y-4">
            <li v-for="entry in detail.messages" :key="entry.id" class="rounded-xl border border-slate-200 p-4" :class="entry.isAdmin ? 'bg-slate-50' : 'bg-white'">
              <div class="flex flex-wrap justify-between gap-2 text-xs text-slate-500">
                <span class="font-semibold text-slate-700">{{ entry.isAdmin ? 'Support team' : (detail.ticket.customerName || 'Customer') }}</span>
                <time>{{ formatDateTime(entry.createdAt) }}</time>
              </div>
              <p class="mt-3 whitespace-pre-wrap break-words text-sm leading-relaxed text-slate-800">{{ entry.body }}</p>
            </li>
          </ol>
          <form class="mt-6 border-t border-slate-200 pt-5" @submit.prevent="update('reply')">
            <label for="support-reply" class="text-sm font-semibold text-slate-900">Reply to customer</label>
            <p class="mt-1 text-xs text-slate-500">Your reply is saved to this ticket and the customer is notified in the app.</p>
            <textarea id="support-reply" v-model="draft" class="field-control mt-3 w-full" rows="6" maxlength="8000" required :disabled="busy || opening" />
            <div class="mt-3 flex items-center justify-between gap-3">
              <span class="text-xs text-slate-500">{{ draft.length.toLocaleString() }} / 8,000</span>
              <button class="primary-button" type="submit" :disabled="busy || opening || !draft.trim()">{{ busy ? 'Saving…' : 'Submit reply' }}</button>
            </div>
          </form>
        </template>
        <div v-else-if="!opening" class="py-20 text-center text-slate-500"><i class="pi pi-ticket text-3xl" /><p class="mt-4">Select a ticket to read and reply.</p></div>
      </section>
    </div>
  </AppShell>
</template>
