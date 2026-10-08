import 'primeicons/primeicons.css';
import './styles.css';
import './styles/mor.css';

import Aura from '@primeuix/themes/aura';
import { definePreset } from '@primeuix/themes';
import { isAxiosError } from 'axios';
import { createPinia } from 'pinia';
import PrimeVue from 'primevue/config';
import { createApp } from 'vue';

import App from './App.vue';
import { apiClient } from './lib/apiClient';
import { appBrand } from './lib/appBrand';
import router from './router';
import { useAuthStore } from './stores/auth';

const pinia = createPinia();
const app = createApp(App);
const auth = useAuthStore(pinia);
let redirectingToLogin = false;

document.title = `${appBrand.name} MOR`;
const favicon = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
if (favicon) favicon.href = appBrand.logo;

const HoppaTheme = definePreset(Aura, {
  semantic: {
    primary: {
      50: '#f7f2fb',
      100: '#eee1f7',
      200: '#dec3ee',
      300: '#c59be0',
      400: '#a66acb',
      500: '#621a96',
      600: '#4e1578',
      700: '#46164a',
      800: '#35113d',
      900: '#240b2a',
      950: '#17061c',
    },
  },
});

apiClient.interceptors.response.use(
  (response) => response,
  async (error: unknown) => {
    if (isAxiosError(error) && error.response?.status === 401) {
      auth.clearSession();

      if (router.currentRoute.value.name !== 'login' && !redirectingToLogin) {
        redirectingToLogin = true;
        const redirect = router.currentRoute.value.fullPath;

        try {
          await router.replace({ name: 'login', query: { redirect } });
        } finally {
          redirectingToLogin = false;
        }
      }
    }

    return Promise.reject(error);
  },
);

auth.restoreSession();

app
  .use(pinia)
  .use(router)
  .use(PrimeVue, {
    theme: {
      preset: HoppaTheme,
      options: {
        darkModeSelector: false,
      },
    },
  })
  .mount('#app');
