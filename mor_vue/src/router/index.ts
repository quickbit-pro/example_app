import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '@/stores/auth';

const router = createRouter({ history: createWebHistory(), routes: [
  { path: '/', name: 'home', component: () => import('@/views/LoginView.vue'), meta: { requiresMor: true } },
  { path: '/login', name: 'login', component: () => import('@/views/LoginView.vue') },
  { path: '/mor/:tab?', name: 'mor-admin', component: () => import('@/views/MorDashboardView.vue'), meta: { portalRole: 'white_label_admin_mor' } },
  { path: '/simple', name: 'mor-user', component: () => import('@/views/MorUserDashboardView.vue'), meta: { portalRole: 'user_simple' } },
  { path: '/account-security', name: 'security', component: () => import('@/views/SecurityView.vue'), meta: { requiresMor: true } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
] });
router.beforeEach(async to => {
  const auth = useAuthStore();
  if (to.name === 'login') return true;
  if (!auth.isAuthenticated) return { name: 'login' };
  try {
    if (!auth.portalRole) await auth.loadPortalIdentity();
  } catch {
    return { name: 'login' };
  }
  if (to.name === 'home') return auth.homePath;
  if (to.meta.portalRole && to.meta.portalRole !== auth.portalRole) return auth.homePath;
  return true;
});
export default router;
