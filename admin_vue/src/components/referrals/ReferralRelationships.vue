<script setup lang="ts">
import { ref, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  relationshipApi,
  displayDate,
  humanLabel,
  type RelationshipRow,
  type RelationshipDetail,
} from "@/lib/referralOperations";
const props = defineProps<{ programId?: string; customerId?: string }>();
const rows = ref<RelationshipRow[]>([]),
  detail = ref<RelationshipDetail | null>(null),
  error = ref(""),
  busy = ref(false),
  detailBusy = ref(false),
  cursor = ref<number | null>(null);
const filters = ref({ search: "", stage: "", source: "", direction: "all" });
let generation = 0,
  detailGeneration = 0;
async function load(more = false) {
  const run = ++generation;
  busy.value = true;
  error.value = "";
  if (!more) {
    rows.value = [];
    cursor.value = null;
    detail.value = null;
  }
  try {
    const query = {
      programId: props.programId,
      ...filters.value,
      afterId: more ? cursor.value : undefined,
      pageSize: 50,
    };
    const data = props.customerId
      ? await relationshipApi.support(props.customerId, query)
      : await relationshipApi.list(query);
    if (run !== generation) return;
    rows.value = more ? [...rows.value, ...data.Items] : data.Items;
    cursor.value = data.NextCursor;
  } catch (e) {
    if (run === generation) error.value = describeAdminError(e);
  } finally {
    if (run === generation) busy.value = false;
  }
}
async function open(row: RelationshipRow) {
  const run = ++detailGeneration;
  detail.value = null;
  detailBusy.value = true;
  error.value = "";
  try {
    const response = await relationshipApi.detail(row.Id);
    if (run === detailGeneration) detail.value = response;
  } catch (e) {
    if (run === detailGeneration) error.value = describeAdminError(e);
  } finally {
    if (run === detailGeneration) detailBusy.value = false;
  }
}
watch(
  () => [props.programId, props.customerId],
  () => load(),
  { immediate: true },
);
</script>
<template>
  <section class="panel p-5 space-y-4">
    <div>
      <h2 class="panel-heading">
        {{ customerId ? "Customer referrals" : "Relationships" }}
      </h2>
      <p class="text-sm text-slate-500 mt-2">
        See who invited a customer and which qualification conditions remain.
        Identity details are restricted to authorised support staff.
      </p>
    </div>
    <form class="flex flex-wrap gap-3 items-end" @submit.prevent="load()">
      <label v-if="!customerId" class="text-sm grid gap-1"
        >Search inviter or friend<input
          v-model="filters.search"
          class="field-control"
          placeholder="Name, email or user ID"
          maxlength="120"
      /></label>
      <label v-if="!customerId" class="text-sm grid gap-1"
        >Stage<select v-model="filters.stage" class="field-control">
          <option value="">All stages</option>
          <option
            v-for="s in [
              'SIGNED_UP',
              'KYC',
              'PAID_CARD',
              'FIRST_TOPUP',
              'QUALIFIED',
              'ACTIVE',
              'HELD',
              'CANCELLED',
              'EXPIRED',
            ]"
            :key="s"
            :value="s"
          >
            {{ humanLabel(s) }}
          </option>
        </select></label
      >
      <label v-if="!customerId" class="text-sm grid gap-1"
        >Source<select v-model="filters.source" class="field-control">
          <option value="">All sources</option>
          <option
            v-for="s in [
              'MANUAL_CODE',
              'LINK',
              'CAMPAIGN_LINK',
              'EMAIL_INVITATION',
              'EMAIL_VERIFIED_FALLBACK',
            ]"
            :key="s"
            :value="s"
          >
            {{ humanLabel(s) }}
          </option>
        </select></label
      >
      <label v-if="customerId" class="text-sm grid gap-1"
        >Direction<select v-model="filters.direction" class="field-control">
          <option value="all">Incoming and outgoing</option>
          <option value="incoming">Who invited this customer</option>
          <option value="outgoing">Invited by this customer</option>
        </select></label
      >
      <button class="secondary-button" :disabled="busy">
        {{ busy ? "Loading…" : "Search" }}
      </button>
    </form>
    <p v-if="error" role="alert" class="text-red-700 text-sm">{{ error }}</p>
    <p v-if="!busy && !rows.length && !error" class="text-sm text-slate-500">
      No relationships match these filters.
    </p>
    <div v-if="rows.length" class="table-shell overflow-x-auto">
      <table class="data-table min-w-[760px]">
        <thead>
          <tr>
            <th>Inviter</th>
            <th>Friend</th>
            <th>Program / source</th>
            <th>Stage / missing conditions</th>
            <th>Attributed</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="row in rows" :key="row.Id">
            <td>
              {{ row.Inviter.Name }}
              <div class="text-xs text-slate-500">
                {{ row.Inviter.Email }} · #{{ row.Inviter.Id }}
              </div>
            </td>
            <td>
              {{ row.Friend.Name }}
              <div class="text-xs text-slate-500">
                {{ row.Friend.Email }} · #{{ row.Friend.Id }}
              </div>
            </td>
            <td>
              {{ row.ProgramName }}
              <div class="text-xs">{{ humanLabel(row.AttributionSource) }}</div>
            </td>
            <td>
              {{ humanLabel(row.Stage) }}
              <div class="text-xs text-slate-500">
                {{
                  row.MissingConditions.map(humanLabel).join(", ") ||
                  "No missing conditions"
                }}
              </div>
            </td>
            <td>{{ displayDate(row.AttributedAt) }}</td>
            <td>
              <button class="secondary-button" @click="open(row)">
                Details
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <button
      v-if="cursor"
      class="secondary-button"
      :disabled="busy"
      @click="load(true)"
    >
      Load more
    </button>
    <p v-if="detailBusy" role="status">Loading relationship…</p>
    <section
      v-if="detail"
      class="rounded-xl border border-slate-200 p-4 space-y-4"
      aria-label="Relationship details"
    >
      <div class="flex justify-between gap-3">
        <h3 class="font-semibold">
          {{ detail.Relationship.Inviter.Name }} invited
          {{ detail.Relationship.Friend.Name }}
        </h3>
        <button class="secondary-button" @click="detail = null">Close</button>
      </div>
      <dl class="grid sm:grid-cols-2 gap-3 text-sm">
        <div>
          <dt class="text-slate-500">Accepted terms</dt>
          <dd>
            Version {{ detail.TermsVersionAccepted ?? "unknown" }} ·
            {{ displayDate(detail.AcceptedAt) }}
          </dd>
        </div>
        <div>
          <dt class="text-slate-500">Offer protection</dt>
          <dd>
            {{
              detail.Relationship.ProtectedOffer
                ? "Accepted offer preserved"
                : "Legacy policy"
            }}
            {{ detail.Relationship.OfferVersionId?.slice(0, 8) }}
          </dd>
        </div>
        <div>
          <dt class="text-slate-500">Qualification / earning until</dt>
          <dd>
            {{ displayDate(detail.Relationship.QualifiedAt) }} /
            {{ displayDate(detail.Relationship.EarningWindowEndsAt) }}
          </dd>
        </div>
        <div>
          <dt class="text-slate-500">Campaign reference</dt>
          <dd class="break-all">
            {{ detail.CampaignLinkId || "No campaign link" }}
          </dd>
        </div>
      </dl>
      <ul class="space-y-2">
        <li
          v-for="condition in detail.Conditions"
          :key="condition.Code"
          class="rounded-lg bg-slate-50 p-3 text-sm"
        >
          <strong>{{ condition.Label }}</strong> —
          {{
            !condition.Required
              ? "Not required"
              : condition.Met
                ? "Completed"
                : "Still required"
          }}<span v-if="condition.MetAt">
            · {{ displayDate(condition.MetAt) }}</span
          >
          <p v-if="condition.Evidence" class="text-xs text-slate-500 mt-1">
            {{ condition.Evidence }}
          </p>
        </li>
      </ul>
      <div class="overflow-x-auto">
        <table class="data-table min-w-[640px]">
          <thead>
            <tr>
              <th>Event</th>
              <th>Time</th>
              <th>Amount / funding</th>
              <th>Status / exclusion</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="event in detail.Events"
              :key="event.EventType + event.SourceEventKey"
            >
              <td>{{ humanLabel(event.EventType) }}</td>
              <td>{{ displayDate(event.OccurredAt) }}</td>
              <td>
                {{ event.Amount }} {{ event.Currency }}
                <div class="text-xs">{{ event.FundingSource }}</div>
              </td>
              <td>
                {{ humanLabel(event.Status) }}
                <div class="text-xs">{{ event.ExcludedReason }}</div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!detail.Events.length" class="text-sm text-slate-500">
          No source events recorded yet.
        </p>
      </div>
      <p class="text-xs text-slate-500">
        Evaluated {{ displayDate(detail.AsOf) }}. Conditions can complete in any
        order.
      </p>
    </section>
  </section>
</template>
