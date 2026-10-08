<script setup lang="ts">
import Button from 'primevue/button';
import Card from 'primevue/card';
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { appBrand } from '@/lib/appBrand';
import { useAuthStore } from '@/stores/auth';

const auth = useAuthStore();
const route = useRoute();
const router = useRouter();
const email = ref('');
const password = ref('');
// Off by default: tokens then live in sessionStorage and die with the tab.
const rememberSession = ref(false);
const loading = ref(false);
const errorMessage = ref('');
const twoFactorCode = ref('');
const needsTwoFactor = ref(false);
const allowLocalSession = import.meta.env.DEV;

function redirectAfterLogin() {
  router.replace((route.query.redirect as string | undefined) ?? '/');
}

async function signIn() {
  loading.value = true;
  errorMessage.value = '';

  try {
    if (needsTwoFactor.value) {
      await auth.completeTwoFactor(twoFactorCode.value.trim());
    } else {
      const challenged = await auth.login(email.value, password.value, rememberSession.value);
      if (challenged) {
        needsTwoFactor.value = true;
        return;
      }
    }

    if (!auth.isAdmin) {
      auth.clearSession();
      errorMessage.value = 'This account is authenticated but lacks the admin role.';
      return;
    }

    redirectAfterLogin();
  } catch (error) {
    errorMessage.value =
      error instanceof Error
        ? error.message
        : 'Unable to sign in with the admin service.';
  } finally {
    loading.value = false;
  }
}

function useLocalAdminSession() {
  auth.setSession('dev-admin-token', ['admin'], null, null, rememberSession.value);
  redirectAfterLogin();
}
</script>

<template>
  <main class="login-page grid min-h-screen place-items-center p-6">
    <Card class="login-card w-full max-w-md">
      <template #title>
        <div class="mb-4 flex items-center gap-3">
          <img :src="appBrand.logo" alt="" class="size-14 shrink-0 rounded-xl object-contain" />
          <div>
            <div class="brand-heading text-xl font-bold">{{ appBrand.name }} Admin</div>
            <div class="mt-1 text-sm font-medium text-slate-500">Sign in to your workspace</div>
          </div>
        </div>
      </template>
      <template #content>
        <form class="space-y-4" @submit.prevent="signIn">
          <p class="text-sm text-slate-600">
            Sign in with an account that has the admin role.
          </p>
          <div
            v-if="errorMessage"
            class="rounded-md border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700"
          >
            {{ errorMessage }}
          </div>
          <label v-if="needsTwoFactor" class="block">
            <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
              Authenticator or recovery code
            </span>
            <input
              v-model="twoFactorCode"
              autocomplete="one-time-code"
              class="field-control w-full"
              required
              type="text"
              autofocus
            />
            <button
              type="button"
              class="mt-2 text-xs font-semibold text-slate-600 underline"
              @click="needsTwoFactor = false; twoFactorCode = ''; auth.cancelTwoFactor()"
            >
              Start over
            </button>
          </label>
          <label v-if="!needsTwoFactor" class="block">
            <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
              Email
            </span>
            <input
              v-model="email"
              autocomplete="email"
              class="field-control w-full"
              required
              type="email"
            />
          </label>
          <label v-if="!needsTwoFactor" class="block">
            <span class="mb-1 block text-xs font-semibold uppercase text-slate-500">
              Password
            </span>
            <input
              v-model="password"
              autocomplete="current-password"
              class="field-control w-full"
              required
              type="password"
            />
          </label>
          <label class="flex items-center gap-2 text-sm font-medium text-slate-700">
            <input
              v-model="rememberSession"
              type="checkbox"
              class="brand-checkbox size-4 rounded border-slate-300"
            />
            <span>Remember me</span>
          </label>
          <Button
            icon="pi pi-sign-in"
            :label="needsTwoFactor ? 'Verify code' : 'Sign in'"
            type="submit"
            class="w-full"
            :loading="loading"
          />
          <Button
            v-if="allowLocalSession"
            icon="pi pi-wrench"
            label="Use local admin session"
            severity="secondary"
            outlined
            class="w-full"
            type="button"
            @click="useLocalAdminSession"
          />
        </form>
      </template>
    </Card>
  </main>
</template>
