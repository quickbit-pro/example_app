<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import Dialog from "primevue/dialog";
import {
  morGet,
  morUserName,
  morPost,
  morError,
  money,
  type MorCard,
  type MorCapabilities,
  type MorUser,
  type CardProduct,
  type Analytics,
} from "@/lib/morApi";
const props = defineProps<{ capabilities?: MorCapabilities }>();
const emit = defineEmits<{ changed: [] }>();
const cards = ref<MorCard[]>([]),
  users = ref<MorUser[]>([]),
  products = ref<CardProduct[]>([]),
  analytics = ref<Analytics>();
const loading = ref(false),
  busy = ref(false),
  error = ref(""),
  notice = ref(""),
  search = ref(""),
  assignment = ref("all");
const orderOpen = ref(false),
  productId = ref<number>(),
  quantity = ref(1),
  autoLock = ref(false),
  label = ref("");
const selected = ref<MorCard>(),
  action = ref<"assign" | "unassign" | "load" | "unload" | "cancel">("assign"),
  actionOpen = ref(false),
  amount = ref<number>(),
  userId = ref<number>();
const widgetUrl = ref(""),
  widgetOpen = ref(false);
const product = computed(() =>
  products.value.find((p) => p.cardTypeId === productId.value),
);
const visible = computed(() =>
  cards.value.filter(
    (c) =>
      (assignment.value === "all" ||
        (assignment.value === "assigned"
          ? !!c.assignedUserId
          : !c.assignedUserId)) &&
      `${c.maskedCardNumber} ${c.id} ${c.assignedUserName} ${c.assignedUserEmail}`
        .toLowerCase()
        .includes(search.value.toLowerCase()),
  ),
);
const maxSpend = computed(() =>
  Math.max(1, ...(analytics.value?.dailyUsage.map((d) => d.spendUsd) ?? [])),
);
const cancelled = (c: MorCard) =>
  ["CANCELLED", "CANCELED", "DELETED", "TERMINATED"].includes(
    c.status.toUpperCase(),
  );
async function load() {
  loading.value = true;
  error.value = "";
  try {
    [cards.value, users.value, products.value, analytics.value] =
      await Promise.all([
        morGet<MorCard[]>("cards"),
        morGet<MorUser[]>("users"),
        props.capabilities?.cardOrdering
          ? morGet<CardProduct[]>("cards/available")
          : Promise.resolve([]),
        morGet<Analytics>("cards/analytics", { days: 30 }),
      ]);
  } catch (e) {
    error.value = morError(e);
  } finally {
    loading.value = false;
  }
}
function openAction(card: MorCard, next: typeof action.value) {
  selected.value = card;
  action.value = next;
  amount.value = undefined;
  userId.value = card.assignedUserId;
  error.value = "";
  actionOpen.value = true;
}
async function order() {
  if (busy.value || !props.capabilities?.cardOrdering) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    const result = await morPost<{
      success: boolean;
      createdQuantity: number;
      requestedQuantity: number;
      errors: string[];
    }>("cards/batch", {
      cardTypeId: productId.value,
      quantity: quantity.value,
      autoLockEnabled: autoLock.value,
      labelPrefix: label.value || null,
    });
    orderOpen.value = false;
    quantity.value = 1;
    label.value = "";
    await load();
    emit("changed");
    if (!result.success)
      error.value = `${result.createdQuantity} of ${result.requestedQuantity} cards created. ${result.errors.join(" ")} Review your cards before ordering again.`;
    else notice.value = `${result.createdQuantity} card(s) created.`;
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
async function confirmAction() {
  if (!selected.value || busy.value) return;
  busy.value = true;
  error.value = "";
  notice.value = "";
  try {
    const body =
      action.value === "assign"
        ? { assignedUserId: userId.value }
        : ["load", "unload"].includes(action.value)
          ? { amount: amount.value }
          : {};
    const result = await morPost<{
      success?: boolean;
      message?: string;
      grossAmount?: number;
      netAmount?: number;
      feeAmount?: number;
    }>(`cards/${selected.value.id}/${action.value}`, body);
    if (result.success === false)
      throw new Error(result.message || "The card action was declined.");
    notice.value =
      result.grossAmount !== undefined
        ? `Completed: ${money(result.grossAmount, selected.value.currency)} gross · ${money(result.netAmount, selected.value.currency)} net · ${money(result.feeAmount, selected.value.currency)} fee.`
        : result.message || "Card updated.";
    actionOpen.value = false;
    await load();
    emit("changed");
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
async function reveal(card: MorCard) {
  if (busy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const data = await morGet<{
      success: boolean;
      widgetUrl: string;
      message?: string;
    }>(`cards/${card.id}/secure-widget`);
    if (!data.success || !data.widgetUrl)
      throw new Error(data.message || "Card details are unavailable.");
    const url = new URL(data.widgetUrl);
    if (url.protocol !== "https:")
      throw new Error("Invalid secure card widget URL.");
    widgetUrl.value = url.href;
    widgetOpen.value = true;
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
onMounted(load);
</script>
<template>
  <div class="space-y-5">
    <p v-if="error && !actionOpen && !orderOpen" role="alert" class="mor-error">
      {{ error }}
    </p>
    <p v-if="notice" role="status" class="mor-success">{{ notice }}</p>
    <p
      v-if="!capabilities?.cardOrdering || !capabilities?.cardCancellation"
      class="text-sm text-slate-500"
    >
      Card ordering and cancellation are not available for this connection.
      Existing cards can still be assigned, loaded, and unloaded.
    </p>
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h2 class="text-xl font-bold">Card portfolio</h2>
        <p class="page-subtitle">Company-owned cards · Last 30 days</p>
      </div>
      <div class="flex gap-2">
        <button
          class="secondary-button"
          :disabled="loading || busy"
          @click="load"
        >
          Refresh</button
        ><button
          class="primary-button"
          :disabled="loading || busy || !products.length"
          @click="
            orderOpen = true;
            error = '';
          "
        >
          Order cards
        </button>
      </div>
    </div>
    <div v-if="analytics" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      <div
        v-for="metric in [
          { label: 'Total cards', value: analytics.totalCards },
          { label: 'Active cards', value: analytics.activeCards },
          { label: 'Card spend', value: money(analytics.totalSpendUsd) },
          {
            label: 'Available balance',
            value: money(analytics.totalAvailableBalance),
          },
        ]"
        :key="metric.label"
        class="metric-card"
      >
        <p class="text-sm text-slate-500">{{ metric.label }}</p>
        <p class="mt-3 text-2xl font-bold">{{ metric.value }}</p>
      </div>
    </div>
    <section v-if="analytics" class="panel p-5">
      <div class="flex flex-wrap justify-between gap-2">
        <h3 class="panel-heading">Daily card spend</h3>
        <span class="text-sm text-slate-500"
          >{{ analytics.transactionCount }} transactions ·
          {{ analytics.cardsUsedInPeriod }} cards used</span
        >
      </div>
      <div
        class="mt-6 flex h-28 items-end gap-1"
        role="img"
        :aria-label="`Daily card spend over the last 30 days, total ${money(analytics.totalSpendUsd)}`"
      >
        <div
          v-for="day in analytics.dailyUsage"
          :key="day.date"
          class="mor-chart-bar"
          :style="{
            height: `${Math.max(2, (day.spendUsd / maxSpend) * 100)}%`,
          }"
          :title="`${day.date.slice(0, 10)}: ${money(day.spendUsd)} · ${day.transactionCount} transactions`"
        />
      </div>
      <p class="mt-3 text-xs text-slate-500">
        {{ analytics.assignedCards }} assigned ·
        {{ analytics.unassignedCards }} unassigned ·
        {{ analytics.cancelledCards }} cancelled · Average transaction
        {{ money(analytics.averageTransactionUsd) }}
      </p>
    </section>
    <section class="panel p-5">
      <div class="flex flex-wrap items-center gap-3">
        <label class="mor-field flex-1"
          ><span class="sr-only">Search cards</span
          ><input
            v-model="search"
            type="search"
            class="field-control"
            placeholder="Search card or assigned user" /></label
        ><label class="mor-field"
          ><span class="sr-only">Assignment</span
          ><select v-model="assignment" class="field-control">
            <option value="all">All cards</option>
            <option value="assigned">Assigned</option>
            <option value="unassigned">Unassigned</option>
          </select></label
        >
      </div>
      <p v-if="loading" class="mor-empty">Loading cards…</p>
      <div v-else class="mt-4 overflow-x-auto">
        <table class="mor-table">
          <thead>
            <tr>
              <th>Card</th>
              <th>Assigned user</th>
              <th>Balance</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="card in visible" :key="card.id">
              <td>
                <b>{{
                  card.maskedCardNumber ||
                  `•••• ${card.cardNumberLastFour || card.id}`
                }}</b
                ><small>{{
                  card.productName || (card.isVirtual ? "Virtual card" : "Card")
                }}</small
                ><button
                  class="mor-text-button"
                  :disabled="busy || cancelled(card)"
                  @click="reveal(card)"
                >
                  View secure details
                </button>
              </td>
              <td>
                {{ card.assignedUserName || "Unassigned"
                }}<small>{{ card.assignedUserEmail }}</small>
              </td>
              <td class="whitespace-nowrap">
                {{ money(card.availableBalance, card.currency)
                }}<small
                  >Pending
                  {{ money(card.pendingBalance, card.currency) }}</small
                ><small v-if="card.pendingLoadRequest" class="text-amber-700"
                  >Load requested:
                  {{
                    money(
                      card.pendingLoadRequest.amount,
                      card.pendingLoadRequest.currency,
                    )
                  }}
                  by {{ card.pendingLoadRequest.requestedByName }}
                  {{ card.pendingLoadRequest.note }}</small
                >
              </td>
              <td>
                <span class="mor-badge">{{ card.status }}</span
                ><small v-if="card.isLocked">Locked</small>
              </td>
              <td>
                <div class="flex min-w-40 flex-wrap gap-x-3 gap-y-2">
                  <button
                    class="mor-text-button"
                    :disabled="busy || cancelled(card)"
                    @click="openAction(card, 'assign')"
                  >
                    Assign</button
                  ><button
                    v-if="card.assignedUserId"
                    class="mor-text-button"
                    :disabled="busy || cancelled(card)"
                    @click="openAction(card, 'unassign')"
                  >
                    Unassign</button
                  ><button
                    class="mor-text-button"
                    :disabled="busy || cancelled(card)"
                    @click="openAction(card, 'load')"
                  >
                    Load</button
                  ><button
                    class="mor-text-button"
                    :disabled="
                      busy || cancelled(card) || card.availableBalance <= 0
                    "
                    @click="openAction(card, 'unload')"
                  >
                    Unload</button
                  ><button
                    class="mor-text-button text-red-700"
                    :disabled="
                      !capabilities?.cardCancellation ||
                      busy ||
                      cancelled(card) ||
                      card.availableBalance !== 0 ||
                      card.pendingBalance !== 0
                    "
                    @click="openAction(card, 'cancel')"
                  >
                    Cancel
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!visible.length" class="mor-empty">
          {{
            search
              ? "No cards match your search."
              : "No cards in this view. Order cards to get started."
          }}
        </p>
      </div>
    </section>
    <Dialog
      v-model:visible="orderOpen"
      modal
      header="Order company cards"
      :closable="!busy"
      :style="{ width: '34rem', maxWidth: '95vw' }"
      ><form class="space-y-4" @submit.prevent="order">
        <p v-if="error" class="mor-error" role="alert">{{ error }}</p>
        <label class="mor-field"
          >Card product<select
            v-model="productId"
            class="field-control"
            required
          >
            <option disabled :value="undefined">Choose a product</option>
            <option
              v-for="p in products"
              :key="p.cardTypeId"
              :value="p.cardTypeId"
            >
              {{ p.name }} · {{ p.tierName }}
            </option>
          </select></label
        >
        <div v-if="product" class="rounded-xl bg-slate-50 p-4 text-sm">
          <p>{{ product.description }}</p>
          <p class="mt-2">
            Issuance: {{ money(product.issuanceFee, product.currencyCode) }} /
            card
          </p>
          <p>
            Monthly:
            {{ money(product.monthlySubscriptionFee, product.currencyCode) }} ·
            Yearly:
            {{ money(product.yearlySubscriptionFee, product.currencyCode) }}
          </p>
          <p class="mt-2 font-semibold">
            Total issuance:
            {{ money(product.issuanceFee * quantity, product.currencyCode) }}
          </p>
        </div>
        <label class="mor-field"
          >Quantity (1–20)<input
            v-model.number="quantity"
            type="number"
            min="1"
            max="20"
            step="1"
            required
            class="field-control" /></label
        ><label class="mor-field"
          >Label prefix (optional)<input
            v-model="label"
            maxlength="64"
            class="field-control" /></label
        ><label class="flex gap-2 text-sm"
          ><input v-model="autoLock" type="checkbox" /> Enable auto-lock</label
        ><button class="primary-button w-full" :disabled="busy">
          {{ busy ? "Ordering…" : "Confirm card order" }}
        </button>
      </form></Dialog
    >
    <Dialog
      v-model:visible="actionOpen"
      modal
      :header="`${action[0].toUpperCase()}${action.slice(1)} card •••• ${selected?.cardNumberLastFour || selected?.id}`"
      :closable="!busy"
      :style="{ width: '30rem', maxWidth: '95vw' }"
      ><form class="space-y-4" @submit.prevent="confirmAction">
        <p v-if="error" class="mor-error" role="alert">{{ error }}</p>
        <label v-if="action === 'assign'" class="mor-field"
          >User<select v-model="userId" required class="field-control">
            <option disabled :value="undefined">Choose a user</option>
            <option v-for="u in users" :key="u.userId" :value="u.userId">
              {{ morUserName(u) }} · {{ u.email }}
            </option>
          </select></label
        ><template v-if="action === 'load' || action === 'unload'"
          ><p class="text-sm text-slate-500">
            {{
              action === "load"
                ? "Fund from your company account."
                : "Return funds to your company account."
            }}
            Fees are applied by your card provider.
          </p>
          <label class="mor-field"
            >Amount ({{ selected?.currency }})<input
              v-model.number="amount"
              required
              type="number"
              min="0.01"
              :max="
                action === 'unload' ? selected?.availableBalance : undefined
              "
              step="0.01"
              class="field-control"
          /></label>
          <p class="text-sm">
            Card available:
            {{ money(selected?.availableBalance, selected?.currency) }}
          </p></template
        >
        <p v-if="action === 'cancel'" class="text-sm">
          Permanently cancel this card? All available, pending, and frozen
          balances must be zero. This cannot be undone.
        </p>
        <p v-if="action === 'unassign'" class="text-sm">
          Remove this user's access to the card? Pending load requests will also
          be cancelled. The card stays in your company portfolio.
        </p>
        <button
          :class="
            action === 'cancel'
              ? 'danger-button w-full'
              : 'primary-button w-full'
          "
          :disabled="busy"
        >
          {{ busy ? "Processing…" : `Confirm ${action}` }}
        </button>
      </form></Dialog
    >
    <Dialog
      v-model:visible="widgetOpen"
      modal
      header="Secure card details"
      :style="{ width: '36rem', maxWidth: '95vw' }"
      @hide="widgetUrl = ''"
      ><iframe
        v-if="widgetUrl"
        :src="widgetUrl"
        title="Secure card details"
        referrerpolicy="no-referrer"
        sandbox="allow-scripts allow-same-origin allow-forms"
        class="h-96 w-full border-0"
    /></Dialog>
  </div>
</template>
