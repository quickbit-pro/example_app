<script setup lang="ts">
import { computed } from 'vue';
import { humanize, toneForStatus } from '@/lib/formatters';

const props = defineProps<{ label?: string | null; tone?: string }>();
const resolvedTone = computed(() => props.tone ?? toneForStatus(props.label));
</script>

<template>
  <span class="status-pill" :class="`status-pill--${resolvedTone}`">
    <span class="status-pill__dot" />
    {{ humanize(label) }}
  </span>
</template>
