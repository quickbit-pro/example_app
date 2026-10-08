<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import { morGet, morError, money, date, type Transactions } from "@/lib/morApi";
const data = ref<Transactions>(),
  loading = ref(false),
  error = ref("");
const filters = reactive({
  page: 1,
  pageSize: 25,
  userId: "",
  status: "",
  type: "",
});
let request = 0;
async function load(reset = false) {
  if (reset) filters.page = 1;
  const current = ++request;
  loading.value = true;
  error.value = "";
  try {
    const result = await morGet<Transactions>("transactions", {
      ...filters,
      userId: filters.userId === "" ? undefined : Number(filters.userId),
      status: filters.status || undefined,
      type: filters.type || undefined,
    });
    if (current === request) data.value = result;
  } catch (e) {
    if (current === request) {
      data.value = undefined;
      error.value = morError(e);
    }
  } finally {
    if (current === request) loading.value = false;
  }
}
function page(delta: number) {
  filters.page += delta;
  load();
}
onMounted(() => load());
</script>
<template>
  <section class="panel p-5">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="panel-heading">Transactions</h2>
        <p class="page-subtitle">
          Company and user activity ·
          {{ data?.stats.totalTransactions ?? "—" }} total transactions
        </p>
      </div>
      <button class="secondary-button" :disabled="loading" @click="load()">
        Refresh
      </button>
    </div>
    <form
      class="my-5 flex flex-wrap items-end gap-3"
      @submit.prevent="load(true)"
    >
      <label class="mor-field"
        >User<select v-model="filters.userId" class="field-control">
          <option value="">All users</option>
          <option
            v-for="user in data?.users"
            :key="user.userId"
            :value="String(user.userId)"
          >
            {{ user.name || user.email }}
          </option>
        </select></label
      >
      <label class="mor-field"
        >Status<select v-model="filters.status" class="field-control">
          <option value="">All statuses</option>
          <option
            v-for="(_, status) in data?.stats.countByStatus"
            :key="status"
          >
            {{ status }}
          </option>
        </select></label
      >
      <label class="mor-field"
        >Type<select v-model="filters.type" class="field-control">
          <option value="">All types</option>
          <option v-for="type in data?.transactionTypes" :key="type">
            {{ type }}
          </option>
        </select></label
      ><button class="primary-button" :disabled="loading">Apply filters</button>
    </form>
    <p v-if="error" class="mor-error" role="alert">{{ error }}</p>
    <p v-if="loading" class="mor-empty" role="status">Loading transactions…</p>
    <template v-else-if="data"
      ><div class="overflow-x-auto">
        <table class="mor-table">
          <thead>
            <tr>
              <th>Date</th>
              <th>User</th>
              <th>Type / merchant</th>
              <th>Amount</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in data.data" :key="row.id">
              <td>{{ date(row.transactionDate) }}</td>
              <td>
                {{ row.userName }}<small>{{ row.userEmail }}</small>
              </td>
              <td>
                {{ row.transactionType
                }}<small>{{ row.merchantName || row.description }}</small>
              </td>
              <td class="whitespace-nowrap">
                {{ money(row.amount, row.currency) }}
              </td>
              <td>
                <span class="mor-badge">{{ row.status }}</span>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!data.data.length" class="mor-empty">
          No transactions match these filters.
        </p>
      </div>
      <div
        class="mt-5 flex items-center justify-between gap-3 text-sm text-slate-500"
      >
        <span
          >{{ data.pagination.total }} results · Page
          {{ data.pagination.page }} of
          {{ Math.max(1, data.pagination.totalPages) }}</span
        >
        <div class="flex gap-2">
          <button
            class="secondary-button"
            :disabled="filters.page <= 1"
            @click="page(-1)"
          >
            Previous</button
          ><button
            class="secondary-button"
            :disabled="filters.page >= data.pagination.totalPages"
            @click="page(1)"
          >
            Next
          </button>
        </div>
      </div>
    </template>
  </section>
</template>
