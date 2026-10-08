<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import UserPicker from '@/components/UserPicker.vue';
import { communityApi, communityVolumeEquivalent, type CommunityMember, type CommunityPolicy } from '@/lib/referralCommunity';
import { describeAdminError } from '@/lib/adminApi';
import type { UserOption } from '@/lib/referrals';
const props = defineProps<{ programId: string; users: UserOption[] }>();
const policy = ref<CommunityPolicy | null>(null); const members = ref<CommunityMember[]>([]);
const loading = ref(true); const busy = ref(false); const error = ref(''); const message = ref('');
const userId = ref<number | null>(null); const plan = ref<'LEADER' | 'COMMUNITY'>('LEADER');
const parent = ref<number | null>(null); const expiresAt = ref(''); const agreement = ref(''); const notes = ref('');
const revokeTarget = ref<CommunityMember | null>(null); const reason = ref('');
const leaders = computed(() => members.value.filter(x => x.Status === 'ACTIVE' && x.Plan === 'LEADER'));
const userName = (id: number) => props.users.find(x => x.Id === id)?.Name ?? `User #${id}`;
async function load() { loading.value = true; error.value = ''; try { const result = await Promise.all([communityApi.policy(props.programId), communityApi.members(props.programId)]); policy.value = result[0]; members.value = result[1]; } catch (e) { error.value = describeAdminError(e); } finally { loading.value = false; } }
async function run(action: () => Promise<unknown>, success: string) { busy.value = true; error.value = ''; message.value = ''; try { await action(); await load(); message.value = success; } catch (e) { error.value = describeAdminError(e); } finally { busy.value = false; } }
async function savePolicy() { if (policy.value) await run(() => communityApi.savePolicy(props.programId, policy.value!), 'Community policy saved. Existing membership plans stay protected.'); }
async function enable() {
  if (!userId.value || (plan.value === 'COMMUNITY' && !parent.value)) { error.value = 'Select a member and, for Community, an active Leader.'; return; }
  const expiry = expiresAt.value ? new Date(expiresAt.value).toISOString() : null;
  await run(() => communityApi.enable(props.programId, userId.value!, { Plan: plan.value, ParentUserId: plan.value === 'COMMUNITY' ? parent.value : null, ExpiresAt: expiry, AgreementReference: agreement.value || null, Notes: notes.value || null }), 'Member enabled prospectively on the current plan. Earlier top-ups are unchanged.');
}
async function revoke() { if (!revokeTarget.value || !reason.value.trim()) { error.value = 'Enter a reason.'; return; } await run(() => communityApi.revoke(props.programId, revokeTarget.value!.UserId, reason.value), 'Membership revoked for future top-ups. Earned rewards are retained.'); revokeTarget.value = null; reason.value = ''; }
onMounted(load);
</script>
<template>
  <section class="panel p-5 sm:p-6 space-y-5" aria-label="Community Partners administration">
    <div><h2 class="panel-heading">Community Partners</h2><p class="mt-2 text-sm text-slate-500">Private three-generation rewards on the existing referral tree. Direct accepted rewards stay protected. Non-members do not see Community in Rewards.</p></div>
    <p v-if="loading" role="status">Loading community settings…</p>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p><p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
    <fieldset v-if="policy" :disabled="busy || loading" class="space-y-5">
      <label class="check-row"><input v-model="policy.Enabled" type="checkbox" />Enable Community Partner memberships and future community accruals</label>
      <div class="grid gap-4 sm:grid-cols-2"><div v-for="kind in ['Community', 'Leader'] as const" :key="kind" class="rounded-xl border p-4"><h3 class="font-semibold">{{ kind }} plan</h3>
        <label class="referral-field mt-3">L2 share (basis points of settled margin)<input v-model.number="policy[`${kind}L2Bps`]" type="number" min="0" max="6500" step="1" class="field-control" /></label>
        <small>{{ policy[`${kind}L2Bps`] / 100 }}% of settled margin · approximately {{ communityVolumeEquivalent(policy[`${kind}L2Bps`]) }} of gross top-up at 2% margin</small>
        <label class="referral-field mt-3">L3 share (basis points of settled margin)<input v-model.number="policy[`${kind}L3Bps`]" type="number" min="0" max="6500" step="1" class="field-control" /></label>
        <small>{{ policy[`${kind}L3Bps`] / 100 }}% of settled margin · approximately {{ communityVolumeEquivalent(policy[`${kind}L3Bps`]) }} of gross top-up at 2% margin</small>
      </div></div>
      <p class="text-sm text-slate-600">Recurring rewards share a 65% margin budget. L3 is reduced first, then L2. A 50% direct reward and 15% L2 leave no L3 payment. Fixed public bonuses are separate. Changes apply only when a member is newly enabled or explicitly re-enabled.</p>
      <button class="primary-button" type="button" @click="savePolicy">Save community policy</button>
      <div class="border-t pt-5 space-y-3"><h3 class="font-semibold">Enable or re-enable a partner</h3><p class="text-sm text-slate-500">A Leader is enabled directly by your company. A Community member is enabled under a Leader. This parent records membership sponsorship; rewards follow existing inviter relationships.</p>
        <label class="referral-field">Partner<UserPicker v-model="userId" required /></label>
        <div class="grid gap-3 sm:grid-cols-2"><label class="referral-field">Plan<select v-model="plan" class="field-control"><option value="LEADER">Leader</option><option value="COMMUNITY">Community</option></select></label>
        <label v-if="plan === 'COMMUNITY'" class="referral-field">Leader<select v-model="parent" class="field-control"><option :value="null">Choose a Leader</option><option v-for="leader in leaders.filter(x => x.UserId !== userId)" :key="leader.Id" :value="leader.UserId">{{ userName(leader.UserId) }}</option></select></label>
        <label class="referral-field">Expiry (optional)<input v-model="expiresAt" type="datetime-local" class="field-control" /></label><label class="referral-field">Agreement reference<input v-model="agreement" class="field-control" /></label></div>
        <label class="referral-field">Admin notes<textarea v-model="notes" class="field-control" /></label>
        <button class="primary-button" type="button" :disabled="!policy.Enabled" @click="enable">Enable on current plan</button>
      </div>
      <div class="overflow-x-auto"><table class="data-table w-full"><thead><tr><th>Partner</th><th>Plan</th><th>L2 / L3 of margin</th><th>Status</th><th>Enabled</th><th>Action</th></tr></thead><tbody>
        <tr v-for="member in members" :key="member.Id"><td>{{ userName(member.UserId) }}</td><td>{{ member.Plan }} · v{{ member.PlanRevision }}</td><td>{{ member.L2Bps / 100 }}% / {{ member.L3Bps / 100 }}% of settled margin<small class="block">Approximately {{ communityVolumeEquivalent(member.L2Bps) }} / {{ communityVolumeEquivalent(member.L3Bps) }} of gross top-up at 2% margin</small></td><td>{{ member.Status }}</td><td>{{ new Date(member.EnabledAt).toLocaleString() }}</td><td><button v-if="member.Status === 'ACTIVE'" type="button" class="secondary-button" @click="revokeTarget = member">Revoke</button></td></tr>
        <tr v-if="!members.length"><td colspan="6">No Community Partners enabled.</td></tr></tbody></table></div>
      <div v-if="revokeTarget" class="rounded-xl border p-4 space-y-3"><p>Revoke {{ userName(revokeTarget.UserId) }} for future events?</p><label class="referral-field">Reason<input v-model="reason" class="field-control" /></label><button type="button" class="primary-button" @click="revoke">Revoke membership</button><button type="button" class="secondary-button ml-2" @click="revokeTarget = null">Cancel</button></div>
    </fieldset>
  </section>
</template>
