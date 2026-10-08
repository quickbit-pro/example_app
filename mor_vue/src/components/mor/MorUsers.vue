<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import {
  morGet,
  morUserName,
  morPost,
  morError,
  money,
  type MorUser,
  type MorCard,
} from "@/lib/morApi";
const emit = defineEmits<{ changed: [] }>();
const users = ref<MorUser[]>([]),
  cards = ref<MorCard[]>([]),
  loading = ref(false),
  saving = ref(false),
  error = ref(""),
  notice = ref(""),
  search = ref("");
const form = reactive({ email: "", firstName: "", lastName: "", phone: "", password: "" });
const visible = computed(() =>
  users.value.filter((u) =>
    `${morUserName(u)} ${u.email}`
      .toLowerCase()
      .includes(search.value.toLowerCase()),
  ),
);
const assigned = (id: number) =>
  cards.value.filter((c) => c.assignedUserId === id);
async function load() {
  loading.value = true;
  error.value = "";
  try {
    [users.value, cards.value] = await Promise.all([
      morGet<MorUser[]>("users"),
      morGet<MorCard[]>("cards"),
    ]);
  } catch (e) {
    error.value = morError(e);
  } finally {
    loading.value = false;
  }
}
async function create() {
  if (saving.value) return;
  saving.value = true;
  error.value = "";
  notice.value = "";
  try {
    const result = await morPost<MorUser>("users", { ...form });
    notice.value =
      result.invitationEmailSent === false
        ? "User created, but the invitation email was not sent. Share their credentials securely."
        : "User created. They can use the cards you assign to them.";
    Object.assign(form, {
      email: "",
      firstName: "",
      lastName: "",
      phone: "",
      password: "",
    });
    await load();
    emit("changed");
  } catch (e) {
    error.value = morError(e);
  } finally {
    saving.value = false;
  }
}
onMounted(load);
</script>
<template>
  <div class="space-y-5">
    <p v-if="error" role="alert" class="mor-error">{{ error }}</p>
    <p v-if="notice" role="status" class="mor-success">{{ notice }}</p>
    <form class="panel p-6" @submit.prevent="create">
      <h2 class="panel-heading">Add a user</h2>
      <p class="page-subtitle">
        Invite a user to your merchant company, then assign company cards.
      </p>
      <div class="mor-form-grid mt-5">
        <label class="mor-field"
          >First name<input
            v-model="form.firstName"
            required
            class="field-control"
            autocomplete="given-name" /></label
        ><label class="mor-field"
          >Last name<input
            v-model="form.lastName"
            required
            class="field-control"
            autocomplete="family-name" /></label
        ><label class="mor-field"
          >Email<input
            v-model="form.email"
            required
            type="email"
            class="field-control"
            autocomplete="off" /></label
        ><label class="mor-field"
          >Phone number<input
            v-model="form.phone"
            required
            type="tel"
            pattern="\+[1-9][0-9]{7,14}"
            placeholder="+38640123456"
            class="field-control"
            autocomplete="tel"
            aria-describedby="mor-user-phone-help" />
          <span id="mor-user-phone-help" class="text-xs text-slate-500">Include the country code without spaces. The user needs this number to reset their Hoppa password.</span></label
        ><label class="mor-field"
          >Temporary password<input
            v-model="form.password"
            required
            minlength="8"
            type="password"
            class="field-control"
            autocomplete="new-password"
        /></label>
      </div>
      <button class="primary-button mt-5" :disabled="saving">
        {{ saving ? "Creating…" : "Create user" }}
      </button>
    </form>
    <section class="panel p-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 class="panel-heading">
          Company users <span class="text-slate-400">{{ users.length }}</span>
        </h2>
        <label class="mor-field"
          ><span class="sr-only">Search users</span
          ><input
            v-model="search"
            placeholder="Search name or email"
            class="field-control"
            type="search" /></label
        ><button class="secondary-button" :disabled="loading" @click="load">
          Refresh
        </button>
      </div>
      <p v-if="loading" class="mor-empty">Loading users…</p>
      <div v-else class="mt-4 overflow-x-auto">
        <table class="mor-table">
          <thead>
            <tr>
              <th>User</th>
              <th>Email</th>
              <th>Assigned cards</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="user in visible" :key="user.userId">
              <td>{{ morUserName(user) }}</td>
              <td>{{ user.email }}</td>
              <td>
                <div v-for="card in assigned(user.userId)" :key="card.id">
                  •••• {{ card.cardNumberLastFour || card.id }} ·
                  {{ money(card.availableBalance, card.currency) }}
                </div>
                <span
                  v-if="!assigned(user.userId).length"
                  class="text-slate-400"
                  >No assigned cards</span
                >
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="!visible.length" class="mor-empty">
          {{
            search
              ? "No users match your search."
              : "No users yet. Add your first user above."
          }}
        </p>
      </div>
    </section>
  </div>
</template>
