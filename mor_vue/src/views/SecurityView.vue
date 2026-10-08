<script setup lang="ts">
import { onMounted, ref } from 'vue';
import MorShell from '@/components/MorShell.vue';
import { apiClient } from '@/lib/apiClient';
import { morError } from '@/lib/morApi';
const security = ref<{twoFactorEnabled:boolean; recoveryCodesRemaining:number}>(), password = ref(''), nextPassword = ref(''), repeatPassword = ref('');
const setupPassword = ref(''), code = ref(''), secret = ref(''), recovery = ref<string[]>([]), busy = ref(false), error = ref(''), notice = ref('');
async function load() { try { security.value = (await apiClient.get('/api/v1/auth/security')).data; } catch(e) {error.value=morError(e);} }
async function action(kind: 'password'|'setup'|'enable'|'disable') {
  if (busy.value) return; busy.value=true;error.value='';notice.value='';
  try {
    if (kind==='password') {
      if (nextPassword.value!==repeatPassword.value) throw new Error('The new passwords do not match.');
      await apiClient.post('/api/v1/auth/password/change',{currentPassword:password.value,newPassword:nextPassword.value});
      password.value='';nextPassword.value='';repeatPassword.value='';notice.value='Password updated.';
    } else if(kind==='setup') {
      secret.value=(await apiClient.post('/api/v1/auth/2fa/setup',{currentPassword:setupPassword.value})).data.secret;
      setupPassword.value='';
    } else if(kind==='enable') {
      recovery.value=(await apiClient.post('/api/v1/auth/2fa/enable',{code:code.value})).data.recoveryCodes;
      secret.value='';code.value='';notice.value='Two-factor authentication enabled.';
    } else { await apiClient.post('/api/v1/auth/2fa/disable',{code:code.value});code.value='';notice.value='Two-factor authentication disabled.'; }
    await load();
  } catch(e) {error.value=morError(e);} finally {busy.value=false;}
}
onMounted(load);
</script>
<template>
  <MorShell><div class="mor-page space-y-6"><header><h1 class="page-title">Account Security</h1><p class="page-subtitle">Manage your sign-in password and two-factor authentication.</p></header>
    <p v-if="error" role="alert" class="mor-error">{{error}}</p><p v-if="notice" role="status" class="mor-success">{{notice}}</p>
    <div class="grid items-start gap-6 xl:grid-cols-2">
      <section class="panel p-6"><h2 class="panel-heading">Two-Factor Authentication</h2><p class="page-subtitle">Use an authenticator app to protect sign-in and secure card details.</p>
        <template v-if="security"><p class="my-5"><span class="mor-badge">{{security.twoFactorEnabled?'Enabled':'Disabled'}}</span></p>
          <form v-if="security.twoFactorEnabled" class="space-y-4" @submit.prevent="action('disable')"><p class="text-sm">{{security.recoveryCodesRemaining}} recovery codes remaining.</p><label class="mor-field">Authenticator or recovery code<input v-model="code" autocomplete="one-time-code" required class="field-control" /></label><button class="danger-button" :disabled="busy">Disable two-factor authentication</button></form>
          <form v-else-if="!secret" class="space-y-4" @submit.prevent="action('setup')"><label class="mor-field">Current password<input v-model="setupPassword" type="password" autocomplete="current-password" required class="field-control" /></label><button class="primary-button" :disabled="busy">Set Up Authenticator</button></form>
          <form v-else class="space-y-4" @submit.prevent="action('enable')"><p class="text-sm">Enter this setup key into your authenticator app, then confirm its current code.</p><code class="block break-all rounded-xl bg-slate-100 p-4">{{secret}}</code><label class="mor-field">Authenticator code<input v-model="code" autocomplete="one-time-code" required class="field-control" /></label><button class="primary-button" :disabled="busy">Enable two-factor authentication</button></form>
        </template>
        <div v-if="recovery.length" class="mt-5 rounded-xl bg-amber-50 p-4"><b>Save your recovery codes</b><p class="mt-2 text-sm">These are shown once. Keep them somewhere safe.</p><div class="mt-3 grid grid-cols-2 gap-2 font-mono text-sm"><span v-for="item in recovery" :key="item">{{item}}</span></div><button class="secondary-button mt-4" @click="recovery=[]">I saved my codes</button></div>
      </section>
      <section class="panel p-6"><h2 class="panel-heading">Password</h2><form class="mt-5 space-y-4" @submit.prevent="action('password')"><label class="mor-field">Current password<input v-model="password" type="password" required autocomplete="current-password" class="field-control" /></label><label class="mor-field">New password<input v-model="nextPassword" type="password" required autocomplete="new-password" class="field-control" /></label><label class="mor-field">Confirm new password<input v-model="repeatPassword" type="password" required autocomplete="new-password" class="field-control" /></label><button class="primary-button" :disabled="busy">Update password</button></form></section>
    </div>
  </div></MorShell>
</template>
