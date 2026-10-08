<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import { morGet, morPost, morError, date, type Kyb } from "@/lib/morApi";
const props = defineProps<{ kyb?: Kyb | null }>();
const emit = defineEmits<{ changed: [] }>();
const busy = ref(false),
  error = ref(""),
  message = ref(""),
  dob = ref("");
const form = reactive({
  companyName: "",
  registrationNumber: "",
  registrationCountry: "",
  industry: "",
  website: "",
});
const submissionLocked = computed(() =>
  ["PENDING", "PROCESSING", "PASSED"].includes(
    props.kyb?.status?.toUpperCase() ?? "",
  ),
);
const ubo = reactive({
  uboFirstName: "",
  uboLastName: "",
  uboGender: "",
  uboCountryCode: "",
  uboIdType: "",
  uboIdNumber: "",
  uboDob: "",
});
async function run(action: "refresh" | "submit" | "cardholder") {
  if (busy.value || (action === "submit" && submissionLocked.value)) return;
  busy.value = true;
  error.value = "";
  message.value = "";
  try {
    if (action === "refresh")
      await morGet("onboarding-status", { refresh: true });
    else if (action === "submit")
      await morPost("kyb", {
        ...form,
        registrationCountry: form.registrationCountry.toUpperCase(),
        uboInformation: {
          ...ubo,
          uboCountryCode: ubo.uboCountryCode.toUpperCase(),
        },
      });
    else {
      const result = await morPost<{ error?: string; status?: string }>(
        "cardholder",
        { dob: dob.value || null },
      );
      if (result.error) throw new Error(result.error);
    }
    message.value =
      action === "submit"
        ? "KYB submitted for review."
        : action === "refresh"
          ? "Onboarding status refreshed."
          : "Company cardholder checked.";
    emit("changed");
  } catch (e) {
    error.value = morError(e);
  } finally {
    busy.value = false;
  }
}
</script>
<template>
  <div class="space-y-5">
    <p v-if="error" class="mor-error" role="alert">{{ error }}</p>
    <p v-if="message" class="mor-success" role="status">{{ message }}</p>
    <section class="panel p-6">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="panel-heading">Business verification</h2>
          <p class="page-subtitle">
            Complete company KYB before ordering cards.
          </p>
        </div>
        <button
          class="secondary-button"
          :disabled="busy"
          @click="run('refresh')"
        >
          Refresh status
        </button>
      </div>
      <dl class="mor-details mt-5">
        <div>
          <dt>KYB status</dt>
          <dd>{{ kyb?.status || "Not submitted" }}</dd>
        </div>
        <div>
          <dt>Cardholder</dt>
          <dd>{{ kyb?.companyCardholderStatus || "Not created" }}</dd>
        </div>
        <div>
          <dt>Submitted</dt>
          <dd>{{ date(kyb?.submittedAt) }}</dd>
        </div>
        <div>
          <dt>Last checked</dt>
          <dd>{{ date(kyb?.lastPolledAt) }}</dd>
        </div>
      </dl>
      <p v-if="kyb?.rejectionReason" class="mor-error mt-4">
        {{ kyb.rejectionReason }}
      </p>
      <p v-if="kyb?.companyCardholderError" class="mor-error mt-4">
        {{ kyb.companyCardholderError }}
      </p>
      <form
        v-if="props.kyb?.status === 'PASSED'"
        class="mt-5 flex flex-wrap items-end gap-3"
        @submit.prevent="run('cardholder')"
      >
        <label class="mor-field"
          >Representative date of birth<input
            v-model="dob"
            type="date"
            class="field-control"
            :max="new Date().toISOString().slice(0, 10)" /></label
        ><button class="primary-button" :disabled="busy">
          Check / create cardholder
        </button>
      </form>
    </section>
    <form
      v-if="!submissionLocked"
      class="panel p-6"
      @submit.prevent="run('submit')"
    >
      <h2 class="panel-heading">
        {{ kyb ? "Resubmit company KYB" : "Company details" }}
      </h2>
      <div class="mor-form-grid mt-5">
        <label class="mor-field"
          >Company name<input
            v-model="form.companyName"
            required
            class="field-control"
            autocomplete="organization"
        /></label>
        <label class="mor-field"
          >Registration number<input
            v-model="form.registrationNumber"
            required
            class="field-control"
        /></label>
        <label class="mor-field"
          >Registration country (ISO code)<input
            v-model="form.registrationCountry"
            required
            pattern="[A-Za-z]{2}"
            maxlength="2"
            placeholder="SI"
            class="field-control"
        /></label>
        <label class="mor-field"
          >Industry<input
            v-model="form.industry"
            required
            class="field-control"
        /></label>
        <label class="mor-field sm:col-span-2"
          >Website<input
            v-model="form.website"
            required
            type="url"
            placeholder="https://"
            class="field-control"
        /></label>
      </div>
      <h3 class="panel-heading mb-4 mt-7">Ultimate beneficial owner</h3>
      <div class="mor-form-grid">
        <label class="mor-field"
          >First name<input
            v-model="ubo.uboFirstName"
            required
            class="field-control" /></label
        ><label class="mor-field"
          >Last name<input
            v-model="ubo.uboLastName"
            required
            class="field-control"
        /></label>
        <label class="mor-field"
          >Gender<select v-model="ubo.uboGender" required class="field-control">
            <option disabled value="">Select gender</option>
            <option value="M">Male</option>
            <option value="F">Female</option>
          </select></label
        >
        <label class="mor-field"
          >Country (ISO code)<input
            v-model="ubo.uboCountryCode"
            required
            pattern="[A-Za-z]{2}"
            maxlength="2"
            class="field-control"
        /></label>
        <label class="mor-field"
          >ID type<select
            v-model="ubo.uboIdType"
            required
            class="field-control"
          >
            <option disabled value="">Select identification</option>
            <option
              v-for="id in [
                'PASSPORT',
                'CN-RIC',
                'HK-HKID',
                'DLN',
                'Government-Issued ID Card',
              ]"
              :key="id"
            >
              {{ id }}
            </option>
          </select></label
        >
        <label class="mor-field"
          >ID number<input
            v-model="ubo.uboIdNumber"
            required
            class="field-control" /></label
        ><label class="mor-field"
          >Date of birth<input
            v-model="ubo.uboDob"
            required
            type="date"
            :max="new Date().toISOString().slice(0, 10)"
            class="field-control"
        /></label>
      </div>
      <button class="primary-button mt-6" :disabled="busy">
        {{ busy ? "Please wait…" : "Submit KYB" }}
      </button>
    </form>
  </div>
</template>
