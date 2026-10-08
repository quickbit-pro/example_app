<script setup lang="ts">
import { ref, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import { referralGet, displayDate, utc } from "@/lib/referralOperations";
const props = defineProps<{ programId: string }>();
type Row = {
  Id: number;
  ActorType: string;
  ActorId: string;
  OriginalActorId: string | null;
  ExecutorId: string;
  Action: string;
  TargetType: string;
  TargetId: string;
  Changes: Record<string, { Before: unknown; After: unknown }>;
  Reason: string | null;
  RecordedAt: string;
  CorrelationId: string;
};
const rows = ref<Row[]>([]),
  cursor = ref<number | null>(null),
  busy = ref(false),
  error = ref(""),
  filters = ref({ actorId: "", action: "", from: "", to: "" });
function value(v: unknown) {
  return v == null
    ? "—"
    : typeof v === "object"
      ? JSON.stringify(v)
      : String(v);
}
async function load(more = false) {
  busy.value = true;
  error.value = "";
  try {
    const r = await referralGet<{ Items: Row[]; NextBeforeId: number | null }>(
      "/audit",
      {
        programId: props.programId,
        actorId: filters.value.actorId || undefined,
        action: filters.value.action || undefined,
        from: filters.value.from ? utc(filters.value.from) : undefined,
        to: filters.value.to ? utc(filters.value.to) : undefined,
        beforeId: more ? cursor.value : undefined,
        pageSize: 50,
      },
    );
    rows.value = more ? [...rows.value, ...r.Items] : r.Items;
    cursor.value = r.NextBeforeId;
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
watch(
  () => props.programId,
  () => {
    rows.value = [];
    load();
  },
  { immediate: true },
);
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Audit trail</h2>
    <p class="text-sm text-slate-500">
      Server-recorded actors, field changes and reasons. Automated and delegated
      actions retain their executor.
    </p>
    <form @submit.prevent="load()" class="flex flex-wrap gap-3 items-end">
      <label class="text-sm grid gap-1"
        >Actor reference<input
          v-model="filters.actorId"
          class="field-control" /></label
      ><label class="text-sm grid gap-1"
        >Exact action<input
          v-model="filters.action"
          class="field-control"
          placeholder="e.g. referrals.program.saved" /></label
      ><label class="text-sm grid gap-1"
        >From<input
          v-model="filters.from"
          type="datetime-local"
          class="field-control" /></label
      ><label class="text-sm grid gap-1"
        >To (exclusive)<input
          v-model="filters.to"
          type="datetime-local"
          class="field-control" /></label
      ><button class="secondary-button" :disabled="busy">
        {{ busy ? "Loading…" : "Search" }}
      </button>
    </form>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <p v-if="!busy && !rows.length && !error" class="text-sm text-slate-500">
      No audit entries match these filters.
    </p>
    <details v-for="row in rows" :key="row.Id" class="border rounded-xl p-4">
      <summary class="cursor-pointer text-sm">
        <strong>{{ row.Action }}</strong> · {{ displayDate(row.RecordedAt) }} ·
        {{ row.ActorType }} {{ row.ActorId }}
      </summary>
      <div class="mt-3 space-y-2 text-sm">
        <p>{{ row.TargetType }} {{ row.TargetId }}</p>
        <p v-if="row.Reason">Reason: {{ row.Reason }}</p>
        <p class="text-xs text-slate-500">
          Executor {{ row.ExecutorId
          }}<span v-if="row.OriginalActorId">
            · Original actor {{ row.OriginalActorId }}</span
          >
          · Correlation {{ row.CorrelationId }}
        </p>
        <div class="overflow-x-auto">
          <table class="data-table min-w-[480px]">
            <thead>
              <tr>
                <th>Field</th>
                <th>Before</th>
                <th>After</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(change, field) in row.Changes" :key="field">
                <td>{{ field }}</td>
                <td class="whitespace-pre-wrap break-words max-w-xs">
                  {{ value(change.Before) }}
                </td>
                <td class="whitespace-pre-wrap break-words max-w-xs">
                  {{ value(change.After) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </details>
    <button
      v-if="cursor"
      class="secondary-button"
      :disabled="busy"
      @click="load(true)"
    >
      Load older entries
    </button>
  </section>
</template>
