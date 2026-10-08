<script setup lang="ts">
import { ref, computed, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralSend,
  referralGet,
  referralDownload,
  programPath,
  displayDate,
  csvTemplate,
  selectedBulkRows,
  type BulkPreview,
} from "@/lib/referralOperations";
const props = defineProps<{ programId: string; revision: number }>();
const csv = ref(""),
  kind = ref("MEMBERSHIP"),
  error = ref(""),
  busy = ref(false),
  preview = ref<BulkPreview | null>(null),
  selected = ref<number[]>([]),
  partial = ref(false),
  key = ref(""),
  resumeId = ref("");
const validSelection = computed(() =>
  preview.value ? selectedBulkRows(preview.value.Rows, selected.value) : [],
);
watch(
  () => [props.programId, csv.value],
  () => {
    preview.value = null;
    key.value = "";
    selected.value = [];
  },
);
async function fileChanged(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (!file) return;
  if (file.size > 262144) {
    error.value = "CSV must be 256 KiB or smaller.";
    return;
  }
  csv.value = await file.text();
}
async function validate() {
  busy.value = true;
  error.value = "";
  try {
    preview.value = await referralSend<BulkPreview>(
      "POST",
      `${programPath(props.programId)}/bulk/preview`,
      { Csv: csv.value, ExpectedProgramRevision: props.revision },
    );
    selected.value = preview.value.Rows.filter((r) => r.Status === "VALID").map(
      (r) => r.Row,
    );
    key.value = crypto.randomUUID();
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function execute() {
  if (!preview.value) return;
  busy.value = true;
  error.value = "";
  try {
    preview.value = await referralSend<BulkPreview>(
      "POST",
      `${programPath(props.programId)}/bulk/${preview.value.Id}/execute`,
      {
        PayloadHash: preview.value.PayloadHash,
        IdempotencyKey: key.value,
        SelectedRows: partial.value ? validSelection.value : null,
      },
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function resume() {
  busy.value = true;
  error.value = "";
  try {
    preview.value = await referralGet<BulkPreview>(
      `${programPath(props.programId)}/bulk/${encodeURIComponent(resumeId.value.trim())}`,
    );
    key.value = crypto.randomUUID();
    selected.value = preview.value.Rows.filter((r) => r.Status === "VALID").map(
      (r) => r.Row,
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function errorsCsv() {
  try {
    await referralDownload(
      `${programPath(props.programId)}/bulk/${preview.value!.Id}/errors.csv`,
      {},
      "referral-import-errors.csv",
    );
  } catch (e) {
    error.value = describeAdminError(e);
  }
}
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Bulk partner operations</h2>
    <p class="text-sm text-slate-500">
      Up to 200 rows. Preview validates every row before any changes. Level
      assignments use published levels; per-inviter benefits contain tiers and
      discounts. Omitted columns preserve existing values; an explicitly blank
      column clears its value. Apply membership changes before previewing
      benefits for the same user.
    </p>
    <div class="flex flex-wrap gap-3">
      <label class="text-sm grid gap-1"
        >Template<select v-model="kind" class="field-control">
          <option
            v-for="k in [
              'MEMBERSHIP',
              'LEVEL_ASSIGNMENT',
              'INVITE_BENEFIT',
              'EXPIRE_MEMBERSHIP',
              'EXPIRE_LEVEL_ASSIGNMENT',
            ]"
            :key="k"
          >
            {{ k }}
          </option>
        </select></label
      ><button class="secondary-button" @click="csv = csvTemplate(kind)">
        Use template</button
      ><label class="text-sm grid gap-1"
        >Upload CSV<input
          type="file"
          accept=".csv,text/csv"
          @change="fileChanged"
      /></label>
    </div>
    <div class="flex gap-3 items-end">
      <label class="text-sm grid gap-1"
        >Resume batch ID<input
          v-model="resumeId"
          class="field-control"
          placeholder="Saved preview UUID" /></label
      ><button
        class="secondary-button"
        :disabled="busy || !resumeId.trim()"
        @click="resume"
      >
        Load batch
      </button>
    </div>
    <label class="text-sm grid gap-1"
      >CSV contents<textarea
        v-model="csv"
        class="field-control font-mono"
        rows="7"
        placeholder="action,user_id,..."
      /></label
    ><button
      class="primary-button"
      :disabled="busy || !csv.trim()"
      @click="validate"
    >
      {{ busy ? "Working…" : "Validate and preview" }}
    </button>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <div v-if="preview" class="space-y-3">
      <p class="text-sm">
        Batch {{ preview.Id }} · {{ preview.Status }} · Preview expires
        {{ displayDate(preview.ExpiresAt) }} · Program revision
        {{ preview.ProgramRevision }}
      </p>
      <div class="table-shell overflow-x-auto">
        <table class="data-table">
          <thead>
            <tr>
              <th v-if="partial">Select</th>
              <th>CSV row</th>
              <th>Action</th>
              <th>User</th>
              <th>Status / explanation</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in preview.Rows" :key="row.Row">
              <td v-if="partial">
                <input
                  v-model="selected"
                  type="checkbox"
                  :value="row.Row"
                  :disabled="row.Status !== 'VALID'"
                  :aria-label="`Select CSV row ${row.Row}`"
                />
              </td>
              <td>{{ row.Row }}</td>
              <td>{{ row.Action }}</td>
              <td>{{ row.UserId ?? "—" }}</td>
              <td>
                {{ row.Status }}
                <p class="text-xs">{{ row.ErrorCode }} {{ row.Message }}</p>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <button class="secondary-button" @click="errorsCsv">
        Download row results</button
      ><template v-if="preview.Status === 'PREVIEW'"
        ><label class="flex gap-2 items-start text-sm"
          ><input v-model="partial" type="checkbox" /> Execute only the valid
          rows I select. Unselected and invalid rows will be skipped.</label
        >
        <p class="text-sm text-slate-500">
          {{
            partial
              ? `${validSelection.length} selected rows`
              : "Entire file, all-or-nothing"
          }}. Expired previews must be validated again.
        </p>
        <button
          class="primary-button"
          :disabled="
            busy ||
            (partial
              ? !validSelection.length
              : preview.Rows.some((r) => r.Status !== 'VALID'))
          "
          @click="execute"
        >
          Confirm and execute
          {{ partial ? validSelection.length : preview.Rows.length }} rows
        </button></template
      >
    </div>
  </section>
</template>
