<script setup lang="ts">
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { appBrand } from '@/lib/appBrand';
import { useAuthStore } from '@/stores/auth';
const auth = useAuthStore(), router = useRouter(), mobileOpen = ref(false);
const nav = computed(() => auth.portalRole === 'white_label_admin_mor' ? [
  { label: 'MoR Dashboard', to: '/mor', icon: 'pi-chart-bar' },
  { label: 'Wallets', to: '/mor/wallets', icon: 'pi-wallet' },
  { label: 'Transactions', to: '/mor/transactions', icon: 'pi-arrow-right-arrow-left' },
  { label: 'Settings', to: '/account-security', icon: 'pi-cog' },
] : [ { label: 'My Cards', to: '/simple', icon: 'pi-credit-card' },
  { label: 'Settings', to: '/account-security', icon: 'pi-cog' } ]);
async function signOut() { try { await auth.logout(); } finally { await router.replace('/login'); } }
</script>
<template>
  <div class="min-h-screen bg-slate-50">
    <button v-if="mobileOpen" class="fixed inset-0 z-30 bg-slate-950/30 lg:hidden" aria-label="Close navigation" @click="mobileOpen = false" />
    <aside class="app-sidebar" :class="mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'">
      <RouterLink :to="auth.homePath" class="flex items-center gap-3 px-2"><img :src="appBrand.logo" alt="" class="size-10" /><span class="font-bold">{{ appBrand.name }} MOR</span></RouterLink>
      <p class="mt-8 px-3 text-xs font-semibold uppercase tracking-widest text-slate-400">{{ auth.portalRole === 'user_simple' ? 'Your cards' : 'Merchant workspace' }}</p>
      <nav aria-label="MOR navigation" class="mt-3 min-h-0 flex-1 space-y-2 overflow-y-auto">
        <RouterLink v-for="item in nav" :key="item.to" :to="item.to" class="nav-link" exact-active-class="nav-link--active" @click="mobileOpen = false"><i :class="`pi ${item.icon}`" /><span>{{ item.label }}</span></RouterLink>
      </nav>
      <div class="border-t border-slate-200 pt-4"><p class="truncate px-3 text-sm font-semibold">{{ auth.portalName || (auth.portalRole === 'user_simple' ? 'Cardholder' : 'MOR administrator') }}</p><p class="mt-1 truncate px-3 text-xs text-slate-500">{{ auth.portalEmail }}</p><button class="nav-link mt-3 w-full" @click="signOut"><i class="pi pi-sign-out" />Sign out</button></div>
    </aside>
    <main class="min-h-screen min-w-0 lg:pl-64">
      <header class="flex h-16 items-center gap-3 border-b border-slate-200 bg-white px-4 lg:hidden"><button class="icon-button" aria-label="Open navigation" @click="mobileOpen = true"><i class="pi pi-bars" /></button><b>{{ appBrand.name }} MOR</b></header>
      <div class="mx-auto max-w-[1540px] px-4 py-6 sm:px-7 lg:px-9 lg:py-8"><slot /></div>
    </main>
  </div>
</template>
