<script setup lang="ts">
import type { ReferralCapMode } from '@/lib/referrals';
const props = defineProps<{ label: string; currency: string; amount: number | null | undefined; mode?: ReferralCapMode; tier?: boolean; effective?: string }>();
const emit = defineEmits<{ 'update:amount': [number | null]; 'update:mode': [ReferralCapMode] }>();
function changeMode(event: Event) {
  const mode = (event.target as HTMLSelectElement).value as ReferralCapMode;
  emit('update:mode', mode);
  // Selecting a real cap starts at a real zero; unlimited is always represented by null.
  emit('update:amount', mode === 'CAPPED' ? props.amount ?? 0 : null);
}
</script>
<template>
  <div class="referral-field">
    <label>{{ label }} ({{ currency }})
      <select :value="tier ? mode ?? 'INHERIT' : amount == null ? 'UNLIMITED' : 'CAPPED'" class="field-control mt-1" @change="changeMode">
        <option v-if="tier" value="INHERIT">Inherit program default</option>
        <option value="UNLIMITED">No cap</option>
        <option value="CAPPED">Set amount</option>
      </select>
    </label>
    <input v-if="tier ? mode === 'CAPPED' : amount != null" :aria-label="`${label} amount`" :value="amount ?? ''" type="number" min="0" step="0.01" required class="field-control" @input="emit('update:amount', ($event.target as HTMLInputElement).value === '' ? Number.NaN : Number(($event.target as HTMLInputElement).value))" />
    <small v-if="effective">Applies: {{ effective }}</small>
    <small>0 is a real cap and prevents eligible volume or recurring rewards. Select No cap for unlimited.</small>
  </div>
</template>
