<script setup lang="ts">
import { ref, onMounted } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import { referralGet, displayDate, humanLabel } from "@/lib/referralOperations";
type Attempt = {
  Id: string;
  State: string;
  EmailNormalized: string;
  LocalUserId: string | null;
  ProviderUserId: string | null;
  FailureReason: string | null;
  CreatedAt: string;
  UpdatedAt: string;
};
const rows = ref<Attempt[]>([]),
  detail = ref<{
    Attempt: Attempt;
    Deliveries: {
      Id: string;
      Kind: string;
      State: string;
      Reason: string | null;
      Attempts: number;
      DueAt: string;
      CreatedAt: string;
      UpdatedAt: string;
    }[];
  } | null>(null),
  page = ref(1),
  total = ref(0),
  state = ref(""),
  search = ref(""),
  busy = ref(false),
  error = ref("");
async function load() {
  busy.value = true;
  error.value = "";
  detail.value = null;
  try {
    const r = await referralGet<{ Items: Attempt[]; Total: number }>(
      "/signup-attempts",
      {
        state: state.value || undefined,
        search: search.value || undefined,
        page: page.value,
        pageSize: 25,
      },
    );
    rows.value = r.Items;
    total.value = r.Total;
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function open(id: string) {
  busy.value = true;
  error.value = "";
  try {
    detail.value = await referralGet(
      `/signup-attempts/${encodeURIComponent(id)}`,
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
onMounted(load);
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Signup and attribution delivery</h2>
    <p class="text-sm text-slate-500">
      Signup attempts across the company. Account creation can succeed while
      referral confirmation is pending. Uncertain identity creation requires
      authenticated reconciliation; email alone cannot claim an upstream
      account.
    </p>
    <form
      @submit.prevent="
        page = 1;
        load();
      "
      class="flex gap-3 flex-wrap items-end"
    >
      <label class="text-sm grid gap-1"
        >Search email or attempt<input
          v-model="search"
          class="field-control" /></label
      ><label class="text-sm grid gap-1"
        >State<input
          v-model="state"
          class="field-control"
          placeholder="e.g. CREATION_UNCERTAIN" /></label
      ><button class="secondary-button" :disabled="busy">
        {{ busy ? "Loading…" : "Search attempts" }}
      </button>
    </form>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <div class="overflow-x-auto">
      <table class="data-table min-w-[650px]">
        <thead>
          <tr>
            <th>Account email</th>
            <th>Creation state</th>
            <th>Reason</th>
            <th>Updated</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.Id">
            <td>{{ row.EmailNormalized }}</td>
            <td>{{ humanLabel(row.State) }}</td>
            <td>{{ row.FailureReason || "—" }}</td>
            <td>{{ displayDate(row.UpdatedAt) }}</td>
            <td>
              <button
                class="secondary-button"
                :disabled="busy"
                @click="open(row.Id)"
              >
                Details
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-if="!rows.length && !busy" class="text-sm text-slate-500">
      No matching signup attempts.
    </p>
    <div class="flex gap-2">
      <button
        class="secondary-button"
        :disabled="page === 1 || busy"
        @click="
          page--;
          load();
        "
      >
        Previous</button
      ><span class="text-sm self-center">{{ total }} attempts</span
      ><button
        class="secondary-button"
        :disabled="page * 25 >= total || busy"
        @click="
          page++;
          load();
        "
      >
        Next
      </button>
    </div>
    <div v-if="detail" class="border rounded-xl p-4 space-y-3">
      <div class="flex justify-between">
        <h3 class="font-semibold">{{ detail.Attempt.EmailNormalized }}</h3>
        <button class="secondary-button" @click="detail = null">Close</button>
      </div>
      <p class="text-xs text-slate-500 break-all">
        Attempt {{ detail.Attempt.Id }} · Local user
        {{ detail.Attempt.LocalUserId || "unbound" }} · Upstream user
        {{ detail.Attempt.ProviderUserId || "unconfirmed" }}
      </p>
      <div
        v-for="delivery in detail.Deliveries"
        :key="delivery.Id"
        class="bg-slate-50 rounded-lg p-3 text-sm"
      >
        <strong
          >{{ humanLabel(delivery.Kind) }} ·
          {{ humanLabel(delivery.State) }}</strong
        >
        <p>
          {{ delivery.Reason || "No failure reason" }} ·
          {{ delivery.Attempts }} attempts · due
          {{ displayDate(delivery.DueAt) }}
        </p>
      </div>
      <p v-if="!detail.Deliveries.length" class="text-sm text-slate-500">
        No attribution delivery intent has been recorded yet.
      </p>
    </div>
  </section>
</template>
