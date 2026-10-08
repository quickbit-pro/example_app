<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import { appBrand } from '@/lib/appBrand';
import { apiClient } from '@/lib/apiClient';
import { morError } from '@/lib/morApi';
const auth = useAuthStore(), router = useRouter();
const connect = ref(false), claimId = ref(''), claimCode = ref(''), claimPassword = ref(''), notice = ref('');
const email = ref(''), password = ref(''), code = ref(''), remember = ref(false), challenge = ref(false), busy = ref(false), error = ref('');
async function connectAccount() {
  busy.value = true; error.value = ''; notice.value = '';
  try {
    if (!claimId.value) {
      const {data} = await apiClient.post('/api/v1/auth/account-claim/challenges', {email:email.value});
      claimId.value = data.challengeId; notice.value = data.message;
    } else {
      await apiClient.post('/api/v1/auth/account-claim/complete', {email:email.value,challengeId:claimId.value,code:claimCode.value,password:claimPassword.value});
      connect.value = false; claimId.value = ''; claimPassword.value = ''; claimCode.value = '';
      notice.value = 'Account connected. Sign in with your new portal password.';
    }
  } catch(e) { error.value = morError(e); } finally {busy.value = false;}
}
async function login() {
  busy.value = true; error.value = '';
  try {
    if (challenge.value) await auth.completeTwoFactor(code.value);
    else if (await auth.login(email.value, password.value, remember.value)) { challenge.value = true; password.value = ''; return; }
    await auth.loadPortalIdentity();
    await router.replace(auth.homePath);
  } catch (e) { error.value = morError(e); }
  finally { busy.value = false; }
}
</script>
<template>
  <main class="grid min-h-screen place-items-center bg-slate-50 p-4">
    <section class="panel w-full max-w-md p-8">
      <img :src="appBrand.logo" alt="" class="mb-6 size-12" /><p class="text-xs font-semibold uppercase tracking-widest text-purple-700">{{ appBrand.name }} MOR</p>
      <h1 class="mt-3 text-3xl font-bold tracking-tight">Welcome back</h1><p class="mt-3 text-sm leading-6 text-slate-500">Sign in to your company workspace or your assigned cards.</p>
      <p v-if="notice" role="status" class="mor-success mt-5">{{notice}}</p>
      <form v-if="connect" class="mt-7 space-y-5" @submit.prevent="connectAccount">
        <p v-if="error" role="alert" class="mor-error">{{error}}</p>
        <p class="text-sm text-slate-500">Connect your existing MOR account using the code sent to your email, then set a password for this portal.</p>
        <label class="mor-field">Email<input v-model="email" :readonly="!!claimId" type="email" autocomplete="email" required class="field-control" /></label>
        <template v-if="claimId"><label class="mor-field">Email verification code<input v-model="claimCode" inputmode="numeric" pattern="[0-9]{6}" maxlength="6" autocomplete="one-time-code" required class="field-control" /></label><label class="mor-field">Portal password<input v-model="claimPassword" type="password" autocomplete="new-password" required class="field-control" /></label></template>
        <button class="primary-button w-full" :disabled="busy">{{busy?'Processing…':claimId?'Connect account':'Send verification code'}}</button>
        <button type="button" class="mor-text-button" @click="connect=false; claimId=''; error=''; claimPassword=''">Back to sign in</button>
      </form>
      <form v-else class="mt-7 space-y-5" @submit.prevent="login">
        <p v-if="error" role="alert" class="mor-error">{{ error }}</p>
        <template v-if="!challenge"><label class="mor-field">Email<input v-model="email" type="email" autocomplete="username" required class="field-control" /></label><label class="mor-field">Password<input v-model="password" type="password" autocomplete="current-password" required class="field-control" /></label></template>
        <label v-else class="mor-field">Authenticator or recovery code<input v-model="code" autocomplete="one-time-code" required class="field-control" /></label>
        <label class="flex items-center gap-2 text-sm"><input v-model="remember" type="checkbox" />Remember me</label>
        <button class="primary-button w-full" :disabled="busy">{{ busy ? 'Signing in…' : challenge ? 'Verify and sign in' : 'Sign in' }}</button>
        <button v-if="!challenge" type="button" class="mor-text-button" @click="connect=true; error=''; notice=''; password=''">First time here? Connect your MOR account</button>
        <button v-if="challenge" type="button" class="mor-text-button" @click="challenge = false; auth.cancelTwoFactor()">Start over</button>
      </form>
    </section>
  </main>
</template>
