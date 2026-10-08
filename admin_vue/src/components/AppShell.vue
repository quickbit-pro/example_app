<script setup lang="ts">
import { ref } from 'vue';
import { useRouter } from 'vue-router';
import { appBrand } from '@/lib/appBrand';
import { useAuthStore } from '@/stores/auth';

const auth = useAuthStore();
const router = useRouter();
const mobileOpen = ref(false);

const navItems = [
  { icon: 'pi pi-chart-bar', label: 'Overview', to: '/' },
  { icon: 'pi pi-users', label: 'Customers', to: '/customers' },
  { icon: 'pi pi-shield', label: 'Verification', to: '/verification' },
  { icon: 'pi pi-wallet', label: 'Money', to: '/money' },
  { icon: 'pi pi-credit-card', label: 'Cards', to: '/cards' },
  { icon: 'pi pi-gift', label: 'Referral program', to: '/referrals' },
  { icon: 'pi pi-ticket', label: 'Support tickets', to: '/support' },
  { icon: 'pi pi-envelope', label: 'Email templates', to: '/email-templates' },
];

async function signOut() {
  await auth.logout();
  router.replace({ name: 'login' });
}
</script>

<template>
  <div class="min-h-screen bg-[#f6f8fb]">
    <button
      v-if="mobileOpen"
      aria-label="Close navigation"
      class="fixed inset-0 z-30 bg-slate-950/30 lg:hidden"
      @click="mobileOpen = false"
    />
    <aside class="app-sidebar" :class="mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'">
      <div class="flex items-center gap-3 px-2">
        <img :src="appBrand.logo" alt="" class="size-10 shrink-0 rounded-xl object-contain" />
        <div class="min-w-0">
          <div class="truncate text-[15px] font-bold text-slate-950">{{ appBrand.name }}</div>
          <div class="text-xs font-medium text-slate-500">Admin console</div>
        </div>
      </div>
      <nav class="mt-10 flex-1 space-y-1.5" aria-label="Main navigation">
        <RouterLink
          v-for="item in navItems"
          :key="item.to"
          :to="item.to"
          class="nav-link"
          active-class="nav-link--active"
          @click="mobileOpen = false"
        >
          <i :class="item.icon" class="w-5 text-center" />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>
      <div class="border-t border-slate-200 pt-4">
        <div class="px-3 pb-3">
          <div class="text-sm font-semibold text-slate-800">Administrator</div>
          <div class="text-xs text-slate-500">{{ appBrand.name }} operations</div>
        </div>
        <button class="nav-link w-full" type="button" @click="signOut">
          <i class="pi pi-sign-out w-5 text-center" />
          <span>Sign out</span>
        </button>
      </div>
    </aside>
    <main class="min-h-screen lg:pl-64">
      <header class="sticky top-0 z-20 flex h-16 items-center border-b border-slate-200 bg-white/95 px-4 backdrop-blur sm:px-7 lg:hidden">
        <button class="icon-button" aria-label="Open navigation" @click="mobileOpen = true">
          <i class="pi pi-bars" />
        </button>
        <div class="ml-3 font-semibold text-slate-900">{{ appBrand.name }}</div>
      </header>
      <div class="mx-auto max-w-[1540px] px-4 py-6 sm:px-7 lg:px-9 lg:py-8">
        <slot />
      </div>
    </main>
  </div>
</template>
