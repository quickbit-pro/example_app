<script setup lang="ts">
import { ref, watch } from "vue";
import { describeAdminError } from "@/lib/adminApi";
import {
  referralGet,
  referralSend,
  programPath,
} from "@/lib/referralOperations";
const props = defineProps<{ programId: string }>();
type Policy = {
  PendingDeadlineExplanation?: string;
  PendingDeadlineBasis?: string;
  VersionId: string;
  Revision: number;
  Enabled: boolean;
  AllowedCountryCodes: string[];
  ExcludedCountryCodes?: string[];
  PendingExpiryDays: number;
  DefaultLocale: string;
  TermsVersion: number;
  TermsByLocale: Record<string, string>;
};
const policy = ref<Policy | null>(null),
  countries = ref(""),
  excludedCountries = ref(""),
  terms = ref<{ locale: string; text: string }[]>([]),
  busy = ref(false),
  error = ref(""),
  message = ref("");
function apply(data: Policy) {
  policy.value = data;
  countries.value = data.AllowedCountryCodes.join(", ");
  excludedCountries.value = (data.ExcludedCountryCodes ?? []).join(", ");
  terms.value = Object.entries(data.TermsByLocale).map(([locale, text]) => ({
    locale,
    text,
  }));
}
async function load() {
  busy.value = true;
  error.value = "";
  try {
    apply(
      await referralGet<Policy>(`${programPath(props.programId)}/geo-policy`),
    );
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
async function save() {
  if (!policy.value) return;
  busy.value = true;
  error.value = "";
  try {
    const codes = countries.value
      .split(/[,\s]+/)
      .map((s) => s.trim().toUpperCase())
      .filter(Boolean);
    if (codes.some((c) => !/^[A-Z]{2}$/.test(c)))
      throw new Error("Use two-letter ISO country codes, separated by commas.");
    const excluded = excludedCountries.value.split(/[,\s]+/)
      .map((s) => s.trim().toUpperCase()).filter(Boolean);
    if (excluded.some((c) => !/^[A-Z]{2}$/.test(c)))
      throw new Error("Use two-letter ISO country codes for exclusions.");
    const locales = terms.value.map((t) => t.locale.trim());
    if (new Set(locales.map((l) => l.toLowerCase())).size !== locales.length)
      throw new Error("Each language may appear only once.");
    apply(
      await referralSend<Policy>(
        "PUT",
        `${programPath(props.programId)}/geo-policy`,
        {
          ExpectedRevision: policy.value.Revision,
          Enabled: policy.value.Enabled,
          AllowedCountryCodes: [...new Set(codes)],
          ExcludedCountryCodes: [...new Set(excluded)],
          PendingExpiryDays: policy.value.PendingExpiryDays,
          DefaultLocale: policy.value.DefaultLocale,
          TermsVersion: policy.value.TermsVersion,
          TermsByLocale: Object.fromEntries(
            terms.value.map((t) => [t.locale.trim(), t.text]),
          ),
        },
      ),
    );
    message.value =
      "Policy saved. Excluded countries apply to existing and new participants. Accepted terms and paid rewards are preserved.";
  } catch (e) {
    error.value = describeAdminError(e);
  } finally {
    busy.value = false;
  }
}
watch(() => props.programId, load, { immediate: true });
</script>
<template>
  <section class="panel p-5 space-y-4">
    <h2 class="panel-heading">Country eligibility and localized terms</h2>
    <p class="text-sm text-slate-500">
      Eligibility uses provider-reviewed residence country. A customer without
      verified residence remains pending; interface language alone does not
      establish eligibility.
    </p>
    <p v-if="error" role="alert" class="text-red-700">{{ error }}</p>
    <p v-if="message" role="status" class="text-emerald-700">{{ message }}</p>
    <p v-if="busy && !policy" role="status">Loading policy…</p>
    <form v-if="policy" @submit.prevent="save" class="space-y-4">
      <label class="text-sm grid gap-1">
        Excluded residence countries — all participants
        <input v-model="excludedCountries" class="field-control" placeholder="GB, SG" />
        <span class="text-xs text-slate-500">
          Applies immediately to existing and new referrers and referred users, even when the
          new-offer policy below is disabled. Invitations and future rewards require verified
          residence outside these countries. Already-paid rewards remain unchanged.
        </span>
      </label>
      <label class="flex gap-2 text-sm"
        ><input v-model="policy.Enabled" type="checkbox" /> Enable country
        eligibility policy for new accepted offers</label
      ><label class="text-sm grid gap-1"
        >Permitted residence countries<input
          v-model="countries"
          class="field-control"
          placeholder="DE, GB, SI"
        /><span class="text-xs text-slate-500"
          >Two-letter ISO codes. The server validates the final allowlist.</span
        ></label
      >
      <div class="flex flex-wrap gap-2">
        <span
          v-for="country in countries.split(/[,\s]+/).filter(Boolean)"
          :key="country"
          class="status-pill status-pill--neutral"
          >{{ country.toUpperCase() }}</span
        >
      </div>
      <div class="grid sm:grid-cols-3 gap-3">
        <label class="text-sm grid gap-1"
          >Pending-country expiry (days)<input
            v-model.number="policy.PendingExpiryDays"
            type="number"
            min="1"
            max="365"
            required
            class="field-control" /></label
        ><label class="text-sm grid gap-1"
          >Default terms language<input
            v-model="policy.DefaultLocale"
            required
            class="field-control"
            placeholder="en" /></label
        ><label class="text-sm grid gap-1"
          >Terms version<input
            v-model.number="policy.TermsVersion"
            type="number"
            :min="policy.Enabled ? 1 : 0"
            required
            class="field-control"
        /></label>
      </div>
      <p class="text-sm text-slate-500">
        {{
          policy.PendingDeadlineExplanation ||
          "Verified residence evidence must reach the service before the pending deadline. Late evidence cannot revive an expired commitment."
        }}
      </p>
      <p class="text-sm text-slate-500">
        The default language is an explicit fallback when the requested
        translation is unavailable. Terms text is contractual content, separate
        from UI translations.
      </p>
      <fieldset
        v-for="(term, i) in terms"
        :key="i"
        class="border rounded-xl p-3 space-y-2"
      >
        <legend class="text-sm font-semibold px-2">
          Terms language {{ i + 1 }}
        </legend>
        <label class="text-sm grid gap-1"
          >Locale<input
            v-model="term.locale"
            required
            maxlength="20"
            class="field-control"
            placeholder="en or de-DE" /></label
        ><label class="text-sm grid gap-1"
          >Terms text<textarea
            v-model="term.text"
            required
            rows="6"
            class="field-control"
          /></label
        ><button
          type="button"
          class="text-sm text-red-700"
          @click="terms.splice(i, 1)"
        >
          Remove language
        </button>
      </fieldset>
      <button
        type="button"
        class="secondary-button"
        @click="terms.push({ locale: '', text: '' })"
      >
        Add language
      </button>
      <div>
        <button class="primary-button" :disabled="busy">Save policy</button
        ><span class="text-xs text-slate-500 ml-3"
          >Revision {{ policy.Revision }}</span
        >
      </div>
    </form>
  </section>
</template>
