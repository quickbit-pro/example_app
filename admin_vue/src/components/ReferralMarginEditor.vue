<script setup lang="ts">
// Settled-margin sharing for the Rewards step (blueprint p16: every rate names its denominator).
// v-model is the program's MarginPolicy; null means the level rates apply instead.
import { computed, ref, watch } from 'vue';
import { allocationErrors, emptyAllocation, type Allocation, type Capabilities, type MarginPolicy } from '@/lib/referralBuild';
const props = defineProps<{ modelValue: MarginPolicy | null | undefined; capabilities: Capabilities | null; available: boolean }>();
const emit = defineEmits<{ 'update:modelValue': [MarginPolicy | null] }>();
const marginMode = ref(!!props.modelValue); const teamMode = ref(!!props.modelValue?.Team);
const direct = ref<Allocation>(props.modelValue?.Direct ? { ...props.modelValue.Direct } : emptyAllocation());
const team = ref<Allocation>(props.modelValue?.Team ? { ...props.modelValue.Team } : emptyAllocation());
const policy = computed<MarginPolicy | null>(() => marginMode.value ? { Direct: { ...direct.value }, Team: teamMode.value ? { ...team.value } : null } : null);
const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);
watch(policy, value => { if (!same(value, props.modelValue)) emit('update:modelValue', value); }, { deep: true });
watch(() => props.modelValue, value => {
  if (same(value, policy.value)) return;
  marginMode.value = !!value; teamMode.value = !!value?.Team;
  direct.value = value?.Direct ? { ...value.Direct } : emptyAllocation(); team.value = value?.Team ? { ...value.Team } : emptyAllocation();
}, { deep: true });
const fields: { key: keyof Allocation; label: string; note: string }[] = [
  { key: 'CompanyBps', label: 'Company retains', note: 'plus any rounding remainder' }, { key: 'AffiliateBps', label: 'Affiliate receives', note: 'of settled margin' },
  { key: 'SubpartnerBps', label: 'Subpartner receives', note: 'of settled margin' }, { key: 'CustomerBps', label: 'Customer receives', note: 'of settled margin' },
  { key: 'BudgetBps', label: 'Approved recipient budget', note: 'affiliate + subpartner + customer may not exceed this' },
];
const routes = computed(() => [{ name: 'Direct route', hint: 'Partner invited the customer directly.', value: direct.value, team: false },
  ...(teamMode.value ? [{ name: 'Team route', hint: 'A subpartner invited the customer; the parent partner earns the subpartner share.', value: team.value, team: true }] : [])]);
const errorsFor = (route: { value: Allocation; team: boolean }) => allocationErrors(route.value, route.team);
const percent = (bps: number) => Number.isFinite(bps) ? `${(bps / 100).toLocaleString(undefined, { maximumFractionDigits: 2 })}%` : '—';
const allocated = (a: Allocation) => a.AffiliateBps + a.SubpartnerBps + a.CustomerBps;
</script>

<template>
<div class="space-y-4">
  <label class="check-row"><input v-model="marginMode" type="checkbox" /><span>Share of settled margin<small>Replace the recurring level rates with a share of settled fee minus attributable provider cost. One-time welcome and qualification bonuses stay separate.</small></span></label>
  <template v-if="marginMode">
    <p class="rounded-lg bg-amber-50 p-3 text-sm text-amber-900">
      <template v-if="!available">Versioned publishing is unavailable on this platform, so a margin policy can be drafted here but not published.</template>
      <template v-else-if="capabilities?.MarginSharingEnabled">Margin sharing is enabled by the platform. Every percentage below uses the available margin as its denominator.</template>
      <template v-else>Margin sharing is disabled for publication in this environment. You can prepare and simulate a draft; publishing is blocked until the platform enables it.</template>
    </p>
    <label class="check-row"><input v-model="teamMode" type="checkbox" /><span>Include one level of subpartners<small>One parent per subpartner, one generation only.</small></span></label>
    <p v-if="teamMode && available && !capabilities?.SubpartnersEnabled" class="text-sm text-amber-800">Subpartner publication is disabled on this platform.</p>
    <div v-for="route in routes" :key="route.name" class="space-y-3 rounded-xl border border-slate-200 p-4">
      <div><h4 class="font-semibold">{{ route.name }}</h4><p class="text-xs text-slate-500">{{ route.hint }} 100 basis points = 1%. Enter each share explicitly.</p></div>
      <label v-for="field in fields.filter(f => route.team || f.key !== 'SubpartnerBps')" :key="field.key" class="grid items-center gap-2 text-sm sm:grid-cols-[1.4fr_7rem_1fr]">
        <span>{{ field.label }}<small class="block text-xs font-normal text-slate-500">{{ field.note }}</small></span>
        <span class="flex items-center gap-1"><input v-model.number="route.value[field.key]" type="number" min="0" max="10000" step="1" class="field-control w-full" :aria-label="`${route.name} ${field.label} in basis points`" /><span class="text-xs text-slate-500">bps</span></span>
        <span class="font-mono text-sm text-slate-700">= {{ percent(route.value[field.key]) }}</span>
      </label>
      <p class="text-xs text-slate-500">Recipients allocated {{ percent(allocated(route.value)) }} of an approved budget of {{ percent(route.value.BudgetBps) }}.</p>
      <p v-for="item in errorsFor(route)" :key="item" role="alert" class="text-sm text-red-700">{{ item }}</p>
    </div>
  </template>
</div>
</template>
