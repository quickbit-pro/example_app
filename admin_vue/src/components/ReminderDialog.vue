<script setup lang="ts">
// Preview-then-confirm dialog for lifecycle reminder emails. The server decides who is eligible
// (verified, unlocked, not a test account, not reminded within the cooldown) and re-checks the
// count on send, so the operator always confirms the number that actually goes out.
import { computed, onMounted, ref } from 'vue';
import { isAxiosError } from 'axios';
import { stageLabel } from '@/lib/customerStages';
import { operationsApi, type ReminderPreview } from '@/lib/operationsApi';

const props = defineProps<{ stage: string }>();
const emit = defineEmits<{ close: []; sent: [queued: number] }>();

const loading = ref(true);
const sending = ref(false);
const error = ref('');
const preview = ref<ReminderPreview | null>(null);

const skippedLines = computed(() => {
  const skipped = preview.value?.skipped;
  if (!skipped) return [];
  return [
    [skipped.recentlyReminded, `already got this reminder in the last ${preview.value!.cooldownDays} days`],
    [skipped.emailNotConfirmed, 'have not confirmed their email address'],
    [skipped.testAccounts, 'are test accounts'],
    [skipped.locked, 'are locked'],
    [skipped.overLimit, 'are over the per-send limit and can be sent next time'],
  ].filter(([count]) => Number(count) > 0) as [number, string][];
});
const canSend = computed(() => Boolean(preview.value && preview.value.recipients > 0 && preview.value.templateEnabled && preview.value.appUrlConfigured && !sending.value));

function describe(caught: unknown, fallback: string) {
  if (isAxiosError(caught)) return (caught.response?.data as { message?: string } | undefined)?.message || caught.message || fallback;
  return caught instanceof Error ? caught.message : fallback;
}
async function load() {
  loading.value = true;
  error.value = '';
  try { preview.value = await operationsApi.previewReminder(props.stage); }
  catch (caught) { error.value = describe(caught, 'The reminder could not be prepared.'); }
  finally { loading.value = false; }
}
async function send() {
  if (!preview.value || !canSend.value) return;
  sending.value = true;
  error.value = '';
  try {
    const result = await operationsApi.sendReminder(props.stage, preview.value.recipients);
    emit('sent', result.queued);
  } catch (caught) {
    error.value = describe(caught, 'The reminder could not be sent.');
    if (isAxiosError(caught) && caught.response?.status === 409) await load();
  } finally {
    sending.value = false;
  }
}
onMounted(load);
</script>

<template>
  <div class="fixed inset-0 z-40 grid place-items-center bg-slate-950/40 p-4" role="dialog" aria-modal="true" aria-labelledby="reminder-title" @click.self="emit('close')">
    <div class="w-full max-w-lg rounded-2xl bg-white p-6 shadow-xl">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 id="reminder-title" class="text-lg font-bold text-slate-950">Send a reminder</h2>
          <p class="mt-1 text-sm text-slate-500">To customers in “{{ stageLabel(stage) }}”</p>
        </div>
        <button type="button" class="icon-button" aria-label="Close" @click="emit('close')"><i class="pi pi-times" /></button>
      </div>

      <div v-if="loading" class="mt-5 space-y-2" aria-busy="true"><div class="h-4 animate-pulse rounded bg-slate-100" /><div class="h-4 w-2/3 animate-pulse rounded bg-slate-100" /></div>
      <template v-else-if="preview">
        <div class="mt-5 rounded-xl border border-slate-200 p-4">
          <div class="text-xs font-semibold uppercase tracking-wide text-slate-500">{{ preview.templateName }}</div>
          <div class="mt-1 font-semibold text-slate-900">{{ preview.subject }}</div>
          <RouterLink to="/email-templates" class="mt-2 inline-block text-xs font-semibold text-blue-700 hover:underline">Edit the email</RouterLink>
        </div>
        <p class="mt-4 text-sm text-slate-700">
          <span class="text-2xl font-bold text-slate-950">{{ preview.recipients.toLocaleString() }}</span>
          {{ preview.recipients === 1 ? 'customer will get this email' : 'customers will get this email' }}<template v-if="preview.sampleNames.length">, including {{ preview.sampleNames.slice(0, 3).join(', ') }}</template>.
        </p>
        <ul v-if="skippedLines.length" class="mt-3 space-y-1 text-xs text-slate-500">
          <li v-for="[count, reason] in skippedLines" :key="reason"><i class="pi pi-minus-circle mr-1.5 text-slate-400" />{{ count }} {{ reason }}</li>
        </ul>
        <div v-if="!preview.templateEnabled" class="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">This email template is turned off. Turn it on under Email templates to send it.</div>
        <div v-if="!preview.appUrlConfigured" class="mt-4 rounded-xl bg-amber-50 p-3 text-sm text-amber-900">The link to the app is not configured on the server (AdminReminders:AppUrl), so the email button would not work.</div>
      </template>
      <div v-if="error" class="mt-4 rounded-xl bg-red-50 p-3 text-sm text-red-700">{{ error }}</div>

      <div class="mt-6 flex justify-end gap-2">
        <button type="button" class="secondary-button" @click="emit('close')">Cancel</button>
        <button type="button" class="primary-button" :disabled="!canSend" @click="send">
          <i class="pi pi-send" />{{ sending ? 'Sending…' : preview ? `Send to ${preview.recipients.toLocaleString()}` : 'Send' }}
        </button>
      </div>
    </div>
  </div>
</template>
