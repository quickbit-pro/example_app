<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import {
  morGet,
  morPost,
  morError,
  money,
  type WalletResponse,
  type MorCapabilities,
} from "@/lib/morApi";
defineProps<{ capabilities?: MorCapabilities }>();
const emit = defineEmits<{ changed: [] }>();
const data = ref<WalletResponse>(),
  loading = ref(false),
  busy = ref(false),
  error = ref(""),
  notice = ref("");
const amount = ref<number>(),
  source = ref("USDT");
interface Quote {
  baseAmount: string;
  baseCurrency: string;
  rfqAmount: string;
  rfqCurrency: string;
  fee: string;
  feeCurrency?: string;
  rate: string;
}
interface Estimate {
  success: boolean;
  message?: string;
  usdtToUsd?: Quote;
  usdcToUsd?: Quote;
}
const estimate = ref<Estimate>();
const quote = computed(() =>
  source.value === "USDT"
    ? estimate.value?.usdtToUsd
    : estimate.value?.usdcToUsd,
);
const wallets = computed(() =>
  (data.value?.wallets.wallets ?? []).filter((w) => !w.onlyDeposit),
);
const deposits = computed(() =>
  (data.value?.wallets.wallets ?? []).filter(
    (w) =>
      w.walletAddress &&
      !(data.value?.wallets.disabledCryptoAddresses ?? []).includes(
        w.walletAddress,
      ),
  ),
);
watch([amount, source], () => {
  estimate.value = undefined;
});
async function load() {
  loading.value = true;
  error.value = "";
  try {
    data.value = await morGet<WalletResponse>("wallets");
  } catch (e) {
    error.value = morError(e);
  } finally {
    loading.value = false;
  }
}
async function getEstimate() {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const result = await morGet<Estimate>("wallets/quantum-topup/estimate", {
      amount: amount.value,
    });
    if (!result.success)
      throw new Error(result.message || "Estimate unavailable.");
    estimate.value = result;
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
async function transfer() {
  if (busy.value || !quote.value) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    const result = await morPost<{
      success: boolean;
      message?: string;
      errorMessage?: string;
    }>("wallets/crypto-to-quantum-transfer", {
      sourceCurrency: source.value,
      destinationCurrency: "USD",
      amount: amount.value,
    });
    if (!result.success)
      throw new Error(
        result.errorMessage || result.message || "Transfer was declined.",
      );
    estimate.value = undefined;
    amount.value = undefined;
    notice.value = result.message || "Transfer submitted.";
    await load();
    emit("changed");
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
async function copy(address?: string) {
  if (!address) return;
  try {
    await navigator.clipboard.writeText(address);
    notice.value = "Deposit address copied.";
  } catch {
    error.value = "Copy failed. Select and copy the address below.";
  }
}
onMounted(load);
</script>
<template>
  <div class="space-y-5">
    <div class="flex justify-end">
      <button
        class="secondary-button"
        :disabled="loading || busy"
        @click="load"
      >
        Refresh wallets
      </button>
    </div>
    <p v-if="error" class="mor-error" role="alert">{{ error }}</p>
    <p v-if="notice" class="mor-success" role="status">{{ notice }}</p>
    <p v-if="loading" class="mor-empty">Loading wallet balances…</p>
    <template v-if="data && !loading"
      ><p v-if="data.wallets.refreshSuccessful === false" class="mor-error">
        {{
          data.wallets.errorMessage ||
          "Wallet refresh failed. Balances may be out of date."
        }}
      </p>
      <div class="grid gap-4 sm:grid-cols-3">
        <div
          v-for="item in [
            {
              label: 'Total wallet value',
              value: money(data.balances.totalUsdValue),
            },
            {
              label: 'Available USDT',
              value: money(data.balances.totalAvailableUSDT, 'USDT'),
            },
            {
              label: 'Available USDC',
              value: money(data.balances.totalAvailableUSDC, 'USDC'),
            },
          ]"
          :key="item.label"
          class="metric-card"
        >
          <p class="text-sm text-slate-500">{{ item.label }}</p>
          <p class="mt-3 text-xl font-bold">{{ item.value }}</p>
        </div>
      </div>
      <section class="panel p-5">
        <h2 class="panel-heading">Wallet balances</h2>
        <div class="mt-4 overflow-x-auto">
          <table class="mor-table">
            <thead>
              <tr>
                <th>Asset</th>
                <th>Network</th>
                <th>Balance</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(wallet, index) in wallets" :key="index">
                <td>{{ wallet.tokenSymbol }}</td>
                <td>{{ wallet.network }}</td>
                <td>{{ money(wallet.balance, wallet.tokenSymbol) }}</td>
                <td>{{ wallet.status }}</td>
              </tr>
            </tbody>
          </table>
          <p v-if="!wallets.length" class="mor-empty">
            No wallet balances returned.
          </p>
        </div>
      </section>
      <section class="panel p-5">
        <h2 class="panel-heading">Deposit addresses</h2>
        <p class="page-subtitle">
          Use the address and network shown for the asset you are depositing.
        </p>
        <div class="mt-4 divide-y divide-slate-100">
          <div
            v-for="(wallet, index) in deposits"
            :key="index"
            class="flex flex-wrap items-center justify-between gap-3 py-4"
          >
            <div class="min-w-0">
              <b class="text-sm"
                >{{ wallet.tokenSymbol }} · {{ wallet.network }}</b
              >
              <p class="mt-1 break-all font-mono text-xs text-slate-500">
                {{ wallet.walletAddress }}
              </p>
            </div>
            <button
              class="secondary-button"
              @click="copy(wallet.walletAddress)"
            >
              Copy address
            </button>
          </div>
        </div>
        <p v-if="!deposits.length" class="mor-empty">
          No deposit addresses are available yet.
        </p>
      </section>
      <section
        v-if="
          capabilities?.quantumFunding &&
          data.wallets.walletOutflowsEnabled !== false
        "
        class="panel p-6"
      >
        <h2 class="panel-heading">Fund Quantum USD wallet</h2>
        <p class="page-subtitle">
          Move company stablecoins to your USD funding wallet.
        </p>
        <form
          class="mt-5 flex flex-wrap items-end gap-3"
          @submit.prevent="getEstimate"
        >
          <label class="mor-field"
            >Estimate currency<select
              v-model="source"
              :disabled="busy"
              class="field-control"
            >
              <option>USDT</option>
              <option>USDC</option>
            </select></label
          ><label class="mor-field"
            >USD amount<input
              v-model.number="amount"
              :disabled="busy"
              required
              type="number"
              min="0.01"
              step="0.01"
              class="field-control" /></label
          ><button class="secondary-button" :disabled="busy">
            Get estimate
          </button>
        </form>
        <div v-if="quote" class="mt-4 rounded-xl bg-slate-50 p-4 text-sm">
          <p>
            Estimated source amount:
            {{ money(quote.baseAmount, quote.baseCurrency) }}
          </p>
          <p>
            Fee: {{ money(quote.fee, quote.feeCurrency || quote.baseCurrency) }}
          </p>
          <p class="my-3 text-slate-500">
            The final rate and funding source are selected from your available
            company balances when the transfer is processed.
          </p>
          <button class="primary-button" :disabled="busy" @click="transfer">
            {{ busy ? "Processing…" : "Confirm transfer" }}
          </button>
        </div>
        <p v-else-if="estimate" class="mor-error mt-4">
          No quote is available for this source currency.
        </p>
      </section>
    </template>
  </div>
</template>
