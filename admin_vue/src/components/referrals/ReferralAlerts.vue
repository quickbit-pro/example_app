<script setup lang="ts">
import { ref, onMounted } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  referralSend,
  displayDate,
  humanLabel,
} from "@/lib/referralOperations";
type Settings = {
  Enabled: boolean;
  EmailRecipients: string[];
  SlackWebhookSecretReference: string | null;
  ExposureThresholdPercent: number;
  ExposureRecoveryPercent: number;
  StaleCreditMinutes: number;
  SampleWindowMinutes: number;
  MinimumSampleSize: number;
  CreditFailureThresholdPercent: number;
  ExcludedEventThresholdPercent: number;
  CooldownMinutes: number;
};
type Response = {
  Settings: Settings;
  SlackWebhookConfigured: boolean;
  UpdatedAt: string | null;
  WorkerEnabled: boolean;
};
type Incident = {
  Id: string;
  ProgramId: string | null;
  Currency: string;
  Kind: string;
  Status: string;
  Severity: string;
  ObservedValue: number;
  SampleSize: number;
  OpenedAt: string;
  LastObservedAt: string;
  ResolvedAt: string | null;
};
const settings = ref<Settings | null>(null),
  emails = ref(""),
  configured = ref(false),
  workerEnabled = ref(false),
  updated = ref<string | null>(null),
  busy = ref(false),
  error = ref(""),
  message = ref(""),
  incidents = ref<Incident[]>([]),
  health = ref<{
    Pending: number;
    Delivering: number;
    Delivered: number;
    DeadLetter: number;
    OldestPendingAt: string | null;
    RecentFailures: {
      Id: string;
      Channel: string;
      Status: string;
      Attempts: number;
      LastErrorCode: string | null;
      NextAttemptAt: string | null;
    }[];
  } | null>(null),
  page = ref(1);
const fields: {
  key: keyof Settings;
  label: string;
  min: number;
  max: number;
}[] = [
  {
    key: "ExposureThresholdPercent",
    label: "Exposure warning (%)",
    min: 1,
    max: 100,
  },
  {
    key: "ExposureRecoveryPercent",
    label: "Exposure recovery (%)",
    min: 0,
    max: 99,
  },
  {
    key: "StaleCreditMinutes",
    label: "Stale credit after (minutes)",
    min: 1,
    max: 1440,
  },
  {
    key: "SampleWindowMinutes",
    label: "Spike sample window (minutes)",
    min: 5,
    max: 1440,
  },
  {
    key: "MinimumSampleSize",
    label: "Minimum events in sample",
    min: 1,
    max: 100000,
  },
  {
    key: "CreditFailureThresholdPercent",
    label: "Credit failure spike (%)",
    min: 1,
    max: 100,
  },
  {
    key: "ExcludedEventThresholdPercent",
    label: "Excluded event spike (%)",
    min: 1,
    max: 100,
  },
  {
    key: "CooldownMinutes",
    label: "Alert cooldown (minutes)",
    min: 5,
    max: 10080,
  },
];
async function load() {
  busy.value = true;
  error.value = "";
  try {
    const [r, i, h] = await Promise.all([
      referralGet<Response>("/alert-settings"),
      referralGet<Incident[]>("/alert-incidents", {
        page: page.value,
        pageSize: 25,
      }),
      referralGet<NonNullable<typeof health.value>>("/alert-delivery-health"),
    ]);
    settings.value = r.Settings;
    emails.value = r.Settings.EmailRecipients.join(", ");
    configured.value = r.SlackWebhookConfigured;
    updated.value = r.UpdatedAt;
    workerEnabled.value = r.WorkerEnabled;
    incidents.value = i;
    health.value = h;
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function save() {
  if (!settings.value) return;
  busy.value = true;
  error.value = "";
  try {
    const r = await referralSend<Response>("PUT", "/alert-settings", {
      ...settings.value,
      EmailRecipients: emails.value
        .split(/[,;\n]/)
        .map((s) => s.trim())
        .filter(Boolean),
      SlackWebhookSecretReference:
        settings.value.SlackWebhookSecretReference?.trim() || null,
    });
    settings.value = r.Settings;
    configured.value = r.SlackWebhookConfigured;
    updated.value = r.UpdatedAt;
    workerEnabled.value = r.WorkerEnabled;
    message.value =
      "Alert settings saved. Delivery also requires deployment-level enablement.";
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
onMounted(load);
</script>
<template>
  <div class="space-y-4">
    <section class="panel p-5 space-y-4">
      <h2 class="panel-heading">Company alert settings</h2>
      <p class="text-sm text-slate-500">
        Exposure, stale credits and failure spikes. These settings apply across
        the company. Delivery also requires server configuration.
      </p>
      <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
      <p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
      <p
        v-if="settings && !workerEnabled"
        class="text-sm text-amber-900 bg-amber-50 rounded-lg p-3"
      >
        Delivery worker is disabled in this environment. Saved company settings
        will not send alerts until it is enabled.
      </p>
      <form v-if="settings" @submit.prevent="save" class="space-y-4">
        <label class="flex gap-2 text-sm"
          ><input v-model="settings.Enabled" type="checkbox" /> Enable referral
          alerts</label
        >
        <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <label
            v-for="field in fields"
            :key="field.key"
            class="text-sm grid gap-1"
            >{{ field.label
            }}<input
              v-model.number="settings[field.key]"
              type="number"
              :min="field.min"
              :max="field.max"
              required
              class="field-control"
          /></label>
        </div>
        <label class="text-sm grid gap-1"
          >Email recipients (up to 10, comma separated)<input
            v-model="emails"
            class="field-control"
            placeholder="ops@example.com" /></label
        ><label class="text-sm grid gap-1"
          >Configured Slack destination alias<input
            v-model="settings.SlackWebhookSecretReference"
            class="field-control"
            maxlength="64"
            pattern="[A-Za-z0-9_-]*"
            placeholder="e.g. referral-operations"
        /></label>
        <p class="text-xs text-slate-500">
          Use a deployment-managed alias, never a webhook URL or token. Blank
          removes Slack delivery. Destination
          {{ configured ? "is configured" : "is not configured" }}.
        </p>
        <button class="primary-button" :disabled="busy">Save settings</button
        ><span class="ml-3 text-xs text-slate-500"
          >Updated {{ displayDate(updated) }}</span
        >
      </form>
      <p v-else-if="busy" role="status">Loading alert settings…</p>
    </section>
    <section class="panel p-5 space-y-4">
      <div class="flex justify-between">
        <h2 class="panel-heading">Incidents and delivery</h2>
        <button class="secondary-button" :disabled="busy" @click="load">
          Refresh
        </button>
      </div>
      <div v-if="health" class="grid gap-3 sm:grid-cols-4">
        <div
          v-for="key in [
            'Pending',
            'Delivering',
            'Delivered',
            'DeadLetter',
          ] as const"
          :key="key"
          class="metric-card"
        >
          <p class="text-sm text-slate-500">{{ key }}</p>
          <p class="font-semibold">{{ health[key] }}</p>
        </div>
      </div>
      <div class="overflow-x-auto">
        <table class="data-table min-w-[650px]">
          <thead>
            <tr>
              <th>Incident</th>
              <th>Status</th>
              <th>Value / sample</th>
              <th>Last observed</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="incident in incidents" :key="incident.Id">
              <td>
                {{ humanLabel(incident.Kind) }}
                <div class="text-xs">
                  {{ incident.Currency }} ·
                  {{ incident.ProgramId?.slice(0, 8) || "Company" }}
                </div>
              </td>
              <td>{{ incident.Status }}</td>
              <td>
                {{ incident.ObservedValue }} / {{ incident.SampleSize }} events
              </td>
              <td>{{ displayDate(incident.LastObservedAt) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="!incidents.length && !busy" class="text-sm text-slate-500">
        No incidents on this page.
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
        ><button
          class="secondary-button"
          :disabled="incidents.length < 25 || busy"
          @click="
            page++;
            load();
          "
        >
          Next
        </button>
      </div>
      <ul v-if="health?.RecentFailures.length" class="space-y-2">
        <li
          v-for="failure in health.RecentFailures"
          :key="failure.Id"
          class="text-sm text-red-700"
        >
          {{ failure.Channel }} · {{ failure.Status }} ·
          {{ failure.Attempts }} attempts · {{ failure.LastErrorCode }} · next
          {{ displayDate(failure.NextAttemptAt) }}
        </li>
      </ul>
    </section>
  </div>
</template>
