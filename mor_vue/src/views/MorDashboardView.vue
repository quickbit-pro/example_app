<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import MorShell from "@/components/MorShell.vue";
import StatusPill from "@/components/StatusPill.vue";
import MorKyb from "@/components/mor/MorKyb.vue";
import MorWallets from "@/components/mor/MorWallets.vue";
import MorUsers from "@/components/mor/MorUsers.vue";
import MorTransactions from "@/components/mor/MorTransactions.vue";
import MorCards from "@/components/mor/MorCards.vue";
import {
  morGet,
  morError,
  money,
  cardsReady,
  type Overview,
  type MorContext,
} from "@/lib/morApi";
import "@/styles/mor.css";
const route = useRoute();
const overview = ref<Overview>(),
  context = ref<MorContext>(),
  loading = ref(false),
  error = ref("");
const tabs = [
  { id: "overview", label: "Overview", icon: "pi-chart-bar" },
  { id: "kyb", label: "KYB", icon: "pi-shield" },
  { id: "wallets", label: "Wallets", icon: "pi-wallet" },
  {
    id: "transactions",
    label: "Transactions",
    icon: "pi-arrow-right-arrow-left",
  },
  { id: "users", label: "Users", icon: "pi-users" },
  { id: "cards", label: "Cards", icon: "pi-credit-card" },
];
const active = computed(() =>
  tabs.some((t) => t.id === route.params.tab)
    ? String(route.params.tab)
    : "overview",
);
const ready = computed(() => cardsReady(overview.value?.kyb));
const quantum = computed(() =>
  overview.value?.balances?.quantumWallets
    ?.filter((w) => w.tokenSymbol?.toUpperCase() === "USD")
    .reduce((sum, w) => sum + Number(w.balance), 0),
);
async function refresh() {
  if (loading.value) return;
  loading.value = true;
  error.value = "";
  try {
    context.value = await morGet<MorContext>("context");
    if (context.value.merchant)
      overview.value = await morGet<Overview>("overview");
  } catch (e) {
    error.value = morError(e);
  } finally {
    loading.value = false;
  }
}
onMounted(refresh);
</script>
<template>
  <MorShell
    ><div class="mor-page space-y-6">
      <header class="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div
            class="mb-2 text-xs font-semibold uppercase tracking-widest text-slate-400"
          >
            Merchant of Record
          </div>
          <h1 class="page-title">MoR Dashboard</h1>
          <p class="page-subtitle">
            {{
              overview?.company.name ||
              context?.company.name ||
              "Company operations"
            }}<span v-if="overview?.parentWhitelabel">
              · {{ overview.parentWhitelabel.name }}</span
            >
          </p>
        </div>
        <div class="flex flex-wrap items-center gap-2">
          <StatusPill
            v-if="overview"
            :label="overview.kyb?.status || 'Not submitted'"
          /><StatusPill v-if="overview?.kyb?.companyCardholderStatus" :label="`Cardholder ${overview.kyb.companyCardholderStatus}`" :tone="ready ? 'success' : 'warning'" /><button
            class="secondary-button"
            :disabled="loading"
            @click="refresh"
          >
            <i class="pi pi-refresh" :class="{ 'animate-spin': loading }" />
            Refresh
          </button>
        </div>
      </header>
      <p v-if="error" class="mor-error" role="alert">
        {{ error }} <button class="underline" @click="refresh">Retry</button>
      </p>
      <div v-if="loading && !overview" class="panel mor-empty" role="status">
        Loading your merchant dashboard…
      </div>
      <section v-else-if="context && !context.merchant" class="panel p-6"><h2 class="panel-heading">Merchant connection required</h2><p class="page-subtitle">This workspace requires your merchant company's MOR connection.</p></section>
      <template v-else-if="overview">
        <div class="grid gap-4 sm:grid-cols-3">
          <div
            v-for="item in [
              {
                label: 'Available USDT',
                value: money(overview.balances?.totalAvailableUSDT, 'USDT'),
              },
              {
                label: 'Available USDC',
                value: money(overview.balances?.totalAvailableUSDC, 'USDC'),
              },
              { label: 'Quantum USD', value: money(quantum) },
            ]"
            :key="item.label"
            class="metric-card"
          >
            <p
              class="text-xs font-semibold uppercase tracking-wide text-slate-400"
            >
              {{ item.label }}
            </p>
            <p class="mt-2 text-2xl font-bold tabular-nums">{{ item.value }}</p>
          </div>
        </div>
        <nav class="mor-tabs" aria-label="MoR Dashboard">
          <RouterLink
            v-for="tab in tabs"
            :key="tab.id"
            :to="tab.id === 'overview' ? '/mor' : `/mor/${tab.id}`"
            :class="{ 'mor-tab-active': active === tab.id }"
            :aria-current="active === tab.id ? 'page' : undefined"
            ><i :class="`pi ${tab.icon}`" />{{ tab.label
            }}<i v-if="tab.id === 'cards' && !ready" class="pi pi-lock text-xs"
          /></RouterLink>
        </nav>
        <div v-if="active === 'overview'" class="space-y-5">
          <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <div
              v-for="item in [
                {
                  label: 'Company users',
                  value: overview.counts.users,
                  detail: 'People in your company',
                },
                {
                  label: 'Total cards',
                  value: overview.counts.cards,
                  detail: 'Company card portfolio',
                },
                {
                  label: 'Assigned cards',
                  value: overview.counts.assignedCards,
                  detail: 'Cards assigned to users',
                },
                {
                  label: 'Unassigned cards',
                  value: overview.counts.unassignedCards,
                  detail: 'Ready for assignment',
                },
              ]"
              :key="item.label"
              class="metric-card"
            >
              <p class="text-sm text-slate-500">{{ item.label }}</p>
              <p class="mt-3 text-3xl font-bold">{{ item.value }}</p>
              <p class="mt-2 text-xs text-slate-400">{{ item.detail }}</p>
            </div>
          </div>
          <div class="grid gap-5 lg:grid-cols-2">
            <section class="panel p-6">
              <h2 class="panel-heading">Company & onboarding</h2>
              <dl class="mor-details mt-5">
                <div>
                  <dt>{{ overview.company.legalName ? "Legal name" : "Company" }}</dt>
                  <dd>
                    {{ overview.company.legalName || overview.company.name }}
                  </dd>
                </div>
                <div>
                  <dt>Company status</dt>
                  <dd>{{ overview.company.status || "—" }}</dd>
                </div>
                <div>
                  <dt>Parent white-label</dt>
                  <dd>{{ overview.parentWhitelabel?.name || "—" }}</dd>
                </div>
                <div>
                  <dt>KYB</dt>
                  <dd>{{ overview.kyb?.status || "Not submitted" }}</dd>
                </div>
                <div>
                  <dt>Cardholder</dt>
                  <dd>
                    {{ overview.kyb?.companyCardholderStatus || "Not created" }}
                  </dd>
                </div>
              </dl>
              <RouterLink
                v-if="!ready"
                to="/mor/kyb"
                class="primary-button mt-5"
                >Continue business verification</RouterLink
              >
            </section>
            <section class="panel p-6">
              <h2 class="panel-heading">Wallet snapshot</h2>
              <dl class="mor-details mt-5">
                <div>
                  <dt>Total value</dt>
                  <dd>{{ money(overview.balances?.totalUsdValue) }}</dd>
                </div>
                <div>
                  <dt>Quantum wallets</dt>
                  <dd>
                    {{ overview.balances?.quantumWallets?.length ?? "—" }}
                  </dd>
                </div>
                <div>
                  <dt>Crypto assets</dt>
                  <dd>{{ overview.balances?.cryptoAssets?.length ?? "—" }}</dd>
                </div>
              </dl>
              <RouterLink to="/mor/wallets" class="secondary-button mt-5"
                >Open wallets</RouterLink
              >
            </section>
          </div>
        </div>
        <MorKyb
          v-else-if="active === 'kyb'"
          :kyb="overview.kyb"
          @changed="refresh"
        />
        <MorWallets
          :capabilities="context?.capabilities"
          v-else-if="active === 'wallets'"
          @changed="refresh"
        />
        <MorTransactions v-else-if="active === 'transactions'" />
        <MorUsers v-else-if="active === 'users'" @changed="refresh" />
        <MorCards
          :capabilities="context?.capabilities"
          v-else-if="active === 'cards' && ready"
          @changed="refresh"
        />
        <section v-else class="panel p-6">
          <h2 class="panel-heading">Complete verification to manage cards</h2>
          <p class="page-subtitle">
            Company KYB must pass and your company cardholder must be approved.
          </p>
          <RouterLink to="/mor/kyb" class="primary-button mt-5"
            >Open business verification</RouterLink
          >
        </section>
      </template>
    </div></MorShell
  >
</template>
