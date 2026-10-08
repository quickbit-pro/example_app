<script setup lang="ts">
// Review step of the offer builder: draft → change preview → publish for versioned offers, plus the
// version history. Capabilities are loaded by the parent (one "unavailable" message per page); this
// component only knows whether versioned publishing is available. Browser drafts stay local (phase 1).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import StatusPill from '@/components/StatusPill.vue';
import { describeAdminError } from '@/lib/adminApi';
import { withProgramDefaults, type ReferralProgram } from '@/lib/referrals';
import { allocationErrors, draftRequest, isConflict, referralBuildApi, type Capabilities, type Draft, type Preview } from '@/lib/referralBuild';
import { changeRows, effectiveAtIso, effectiveTimeLabel, localTimeZone, previewState, remainingLabel, versionStatusLabel, versionStatusTone } from '@/lib/referralReview';
const props = defineProps<{ program: ReferralProgram; current: ReferralProgram | null; valid: boolean; available: boolean; capabilities: Capabilities | null }>();
const emit = defineEmits<{ published: []; restore: [ReferralProgram]; conflict: [string] }>();
const busy = ref(false); const error = ref(''); const notice = ref('');
const versions = ref<Draft[]>([]); const versionsError = ref('');
const draft = ref<Draft | null>(null); const preview = ref<Preview | null>(null);
const effectiveAt = ref(''); const reason = ref(''); const key = ref('');
const now = ref(Date.now()); let ticker: ReturnType<typeof setInterval> | undefined;
const timeZone = localTimeZone();
const margin = computed(() => props.program.MarginPolicy ?? null);
const validation = computed(() => margin.value ? [...allocationErrors(margin.value.Direct, false), ...(margin.value.Team ? allocationErrors(margin.value.Team, true) : [])] : []);
/** Draft content plus the requested effective time: a preview is only valid for exactly this pair. */
const fingerprint = computed(() => `${JSON.stringify(draftRequest(props.program, margin.value))}|${effectiveAt.value}`);
const previewFingerprint = ref('');
const state = computed(() => previewState(preview.value, now.value));
const stale = computed(() => !!preview.value && previewFingerprint.value !== fingerprint.value);
const rows = computed(() => preview.value ? changeRows(preview.value.ChangedFields, props.current, draft.value?.Draft.Policy as Partial<ReferralProgram> | undefined, draft.value?.Draft.Margin) : []);
const effective = computed(() => effectiveTimeLabel(preview.value?.EffectiveAt));
const capabilityBlock = computed(() => margin.value ? (!props.capabilities?.MarginSharingEnabled ? 'Margin sharing is disabled for publication on this platform.' : margin.value.Team && !props.capabilities?.SubpartnersEnabled ? 'Subpartner publication is disabled on this platform.' : '') : '');
const publishBlocker = computed(() => {
  if (!props.available) return 'Versioned publishing is unavailable on this platform.';
  if (!props.valid || validation.value.length) return 'Fix the validation issues before publishing.';
  if (!preview.value) return 'Save a draft and review its impact first.';
  if (stale.value) return 'The draft changed after this preview. Review the impact again.';
  if (state.value.status === 'expired') return 'This preview expired. Review the impact again to get a fresh one.';
  if (capabilityBlock.value) return capabilityBlock.value;
  if (!reason.value.trim()) return 'Give a reason for this change.';
  return '';
});
const canPublish = computed(() => !busy.value && !publishBlocker.value);
const localKey = computed(() => `example:referral-draft:${props.program.Id}`);
async function run(fn: () => Promise<void>) { if (busy.value) return; busy.value = true; error.value = ''; notice.value = ''; try { await fn(); } catch (e) { if (isConflict(e)) emit('conflict', describeAdminError(e)); else error.value = describeAdminError(e); } finally { busy.value = false; } }
async function loadVersions() {
  if (!props.available || !props.program.Id) return;
  try { versions.value = await referralBuildApi.versions(props.program.Id); versionsError.value = ''; }
  catch (e) { versionsError.value = describeAdminError(e); }
}
function saveLocal() { try { localStorage.setItem(localKey.value, JSON.stringify({ Program: props.program, Margin: margin.value })); notice.value = 'Draft saved on this browser. The live offer is unchanged.'; } catch { error.value = 'Browser storage is unavailable. Keep this page open to preserve your edits.'; } }
function restoreLocal() {
  try { const raw = localStorage.getItem(localKey.value); if (!raw) { notice.value = 'No browser draft exists for this program.'; return; }
    const saved = JSON.parse(raw); if (saved.Program?.Id !== props.program.Id) throw new Error();
    emit('restore', withProgramDefaults({ ...saved.Program, MarginPolicy: saved.Margin ?? null })); notice.value = 'Browser draft restored. Compare its revision with the current offer before saving.';
  } catch { error.value = 'This browser draft could not be read.'; }
}
function edit(d: Draft) {
  draft.value = d.Status === 'DRAFT' ? d : null; preview.value = null;
  emit('restore', withProgramDefaults({ ...props.program, ...d.Draft.Policy, Revision: d.BaseRevision, MarginPolicy: d.Draft.Margin ?? null } as ReferralProgram));
  notice.value = d.Status === 'DRAFT' ? `Draft ${d.Id.slice(0, 8)} opened for editing. Its base revision is ${d.BaseRevision}.` : `Version ${d.Id.slice(0, 8)} loaded read-only into the builder for comparison.`;
}
async function saveAndReview() {
  if (!props.valid || validation.value.length || !props.program.Id) return;
  await run(async () => {
    const id = props.program.Id!;
    draft.value = await referralBuildApi.saveDraft(id, draftRequest(props.program, margin.value, draft.value?.DraftRevision), draft.value?.Id);
    preview.value = await referralBuildApi.preview(id, draft.value, effectiveAtIso(effectiveAt.value));
    previewFingerprint.value = fingerprint.value; key.value = crypto.randomUUID(); now.value = Date.now();
    notice.value = 'Draft saved. Nothing is published yet; review the impact below.';
    await loadVersions();
  });
}
async function publish() {
  if (!canPublish.value || !preview.value || !props.program.Id) return;
  await run(async () => {
    const result = await referralBuildApi.publish(props.program.Id!, preview.value!, reason.value.trim(), key.value);
    const when = effectiveTimeLabel(result.EffectiveAt);
    notice.value = result.Status === 'PUBLISHED' ? 'Offer version published. New attributions from now accept it.' : result.Status === 'SCHEDULED' ? `Change scheduled for ${when.local} (${when.utc}). It applies when the platform activates it.` : `Version state: ${versionStatusLabel(result.Status)}.`;
    preview.value = null; draft.value = null; reason.value = ''; emit('published');
    await loadVersions();
  });
}
watch(() => props.available, value => { if (value) void loadVersions(); });
watch(preview, value => { if (ticker) clearInterval(ticker); ticker = undefined; if (value) ticker = setInterval(() => { now.value = Date.now(); }, 5000); });
onMounted(() => { void loadVersions(); });
onBeforeUnmount(() => { if (ticker) clearInterval(ticker); });
defineExpose({ loadVersions });
</script>

<template>
<div class="space-y-6">
  <section class="panel space-y-5 p-5 sm:p-6" aria-label="Publish a versioned offer">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div><h2 class="panel-heading">Publish a versioned offer</h2><p class="mt-2 text-sm text-slate-500">Save a separate draft, see who is affected and what changes, then publish. Accepted offers keep their terms; only new attributions after the effective time get the new version.</p></div>
      <div class="flex flex-wrap gap-2"><button type="button" class="secondary-button" @click="saveLocal">Save browser draft</button><button type="button" class="secondary-button" @click="restoreLocal">Restore browser draft</button></div>
    </div>
    <p v-if="error" role="alert" class="rounded-lg bg-red-50 p-3 text-sm text-red-800">{{ error }}</p>
    <p v-if="notice" role="status" class="rounded-lg bg-emerald-50 p-3 text-sm text-emerald-800">{{ notice }}</p>
    <template v-if="available">
      <div class="grid gap-4 sm:grid-cols-2">
        <label class="block text-sm font-semibold">Effective time<input v-model="effectiveAt" type="datetime-local" class="field-control mt-2 w-full font-normal" /><span class="mt-1 block text-xs font-normal text-slate-500">Entered in your timezone ({{ timeZone }}), stored in UTC. Leave empty to apply as soon as it is published. Cannot be backdated.</span></label>
        <div class="text-sm text-slate-600 sm:pt-7"><p v-if="draft">Editing draft <span class="font-mono">{{ draft.Id.slice(0, 8) }}</span> · base revision {{ draft.BaseRevision }} · draft revision {{ draft.DraftRevision }}</p><p v-else>No server draft open. Saving creates a new draft from the builder values (program revision {{ program.Revision }}).</p></div>
      </div>
      <p v-for="item in validation" :key="item" role="alert" class="text-sm text-red-700">{{ item }}</p>
      <button type="button" class="primary-button" :disabled="busy || !valid || validation.length > 0 || !program.Id" @click="saveAndReview">{{ busy ? 'Working…' : 'Save draft and review impact' }}</button>
      <p class="text-xs text-slate-500">Saving a draft never changes the live offer. Publishing requires a valid, unexpired preview from the server.</p>
    </template>
    <p v-else class="text-sm text-slate-600">Legacy save applies changes immediately; browser drafts remain available for preparing edits.</p>
    <div v-if="preview" class="space-y-4 rounded-xl border p-4" :class="state.status === 'valid' && !stale ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'" aria-live="polite">
      <div class="flex flex-wrap items-start justify-between gap-3">
        <h3 class="font-semibold">Review before publication</h3>
        <span class="text-xs" :class="state.status === 'valid' ? 'text-slate-600' : 'text-amber-900'">{{ state.status === 'valid' ? `Preview valid for ${remainingLabel(state.remainingSeconds)}` : 'Preview expired' }}</span>
      </div>
      <dl class="grid gap-3 text-sm sm:grid-cols-2">
        <div><dt class="text-xs uppercase tracking-wide text-slate-500">Effective</dt><dd class="font-semibold">{{ effective.local }}</dd><dd class="text-xs text-slate-500">{{ effective.utc }} · {{ timeZone }}</dd></div>
        <div><dt class="text-xs uppercase tracking-wide text-slate-500">Cohort</dt><dd>{{ preview.Cohort }}</dd></div>
        <div><dt class="text-xs uppercase tracking-wide text-slate-500">Protected running windows</dt><dd>{{ preview.ExistingQualified }} qualified relationships keep their accepted terms</dd></div>
        <div><dt class="text-xs uppercase tracking-wide text-slate-500">Attributed but not yet qualified</dt><dd>{{ preview.ExistingUnqualified }} relationships</dd></div>
        <div class="sm:col-span-2"><dt class="text-xs uppercase tracking-wide text-slate-500">Terms</dt><dd>{{ preview.TermsAcceptanceRequired ? 'Members must accept the new terms version again before sharing.' : 'No new terms acceptance is required.' }}</dd></div>
      </dl>
      <div>
        <p class="text-xs uppercase tracking-wide text-slate-500">What changes</p>
        <p v-if="!rows.length" class="mt-1 text-sm">No field differs from the live program; publishing records a new version with the same values{{ preview.TermsAcceptanceRequired ? ' and a new terms version' : '' }}.</p>
        <table v-else class="mt-2 w-full text-sm"><thead class="sr-only"><tr><th>Field</th><th>Before</th><th>After</th></tr></thead><tbody>
          <tr v-for="row in rows" :key="row.field" class="border-t border-slate-200/70 align-top" :class="row.detail ? 'text-slate-600' : ''"><td class="py-1.5 pr-3" :class="row.detail ? 'pl-4' : 'font-medium'">{{ row.label }}</td><td class="py-1.5 pr-3">{{ row.from ?? '—' }}</td><td class="py-1.5"><span v-if="row.from !== null && row.from === row.to" class="text-slate-500">→ same as shown; the platform recorded a change in this field</span><span v-else-if="row.from !== null || row.to !== null">→ {{ row.to ?? 'changed' }}</span><span v-else class="text-slate-500">changed (value not derivable here)</span></td></tr>
        </tbody></table>
      </div>
      <div v-if="preview.Warnings.length"><p class="text-xs uppercase tracking-wide text-slate-500">Warnings</p><ul class="mt-1 list-inside list-disc space-y-1 text-sm text-amber-900"><li v-for="warning in preview.Warnings" :key="warning">{{ warning }}</li></ul></div>
      <label class="block text-sm font-semibold">Reason for this change<textarea v-model="reason" maxlength="2000" rows="2" class="field-control mt-1 w-full py-2 font-normal" placeholder="Recorded with the version, e.g. Creator rate increase for Q4." /></label>
      <div class="flex flex-wrap items-center gap-3"><button type="button" class="primary-button" :disabled="!canPublish" @click="publish">{{ busy ? 'Publishing…' : 'Publish reviewed version' }}</button><span v-if="publishBlocker" class="text-sm text-amber-900">{{ publishBlocker }}</span></div>
      <p class="text-xs text-slate-600">The platform rechecks the revision, limits and impact atomically when publishing; a stale preview is refused.</p>
    </div>
  </section>
  <section v-if="available" class="panel p-5 sm:p-6" aria-label="Drafts and offer history">
    <div class="flex flex-wrap items-center justify-between gap-3"><h2 class="panel-heading">Drafts and offer history</h2><button type="button" class="secondary-button" :disabled="busy" @click="loadVersions">Refresh</button></div>
    <p v-if="versionsError" role="alert" class="mt-3 text-sm text-red-700">Could not load versions. {{ versionsError }}</p>
    <div v-else class="mt-4 overflow-x-auto"><table class="data-table min-w-[720px]"><thead><tr><th>Status</th><th>Effective</th><th>Reason</th><th>Revision</th><th>Version</th><th></th></tr></thead><tbody>
      <tr v-for="version in versions" :key="version.Id">
        <td><StatusPill :label="versionStatusLabel(version.Status)" :tone="versionStatusTone(version.Status)" /></td>
        <td class="text-xs"><template v-if="version.EffectiveAt">{{ effectiveTimeLabel(version.EffectiveAt).local }}<div class="text-slate-500">{{ effectiveTimeLabel(version.EffectiveAt).utc }}</div></template><span v-else class="text-slate-500">Not scheduled</span></td>
        <td class="text-xs">{{ version.Reason || (version.Status === 'DRAFT' ? 'Unpublished draft' : '—') }}</td>
        <td class="text-xs">base {{ version.BaseRevision }} · draft {{ version.DraftRevision }}</td>
        <td class="font-mono text-xs">{{ version.Id.slice(0, 8) }}</td>
        <td class="text-right"><button v-if="version.Status === 'DRAFT'" type="button" class="secondary-button" :disabled="busy" @click="edit(version)">Open draft</button><button v-else type="button" class="secondary-button" :disabled="busy" @click="edit(version)">Load into builder</button></td>
      </tr>
      <tr v-if="!versions.length"><td colspan="6">No drafts or published versions yet.</td></tr>
    </tbody></table></div>
  </section>
</div>
</template>
