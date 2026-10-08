import { createRouter, createWebHistory } from 'vue-router';
import { useAuthStore } from '@/stores/auth';
import AdminCardsView from '@/views/AdminCardsView.vue';
import AdminCustomerDetail from '@/views/AdminCustomerDetail.vue';
import AdminCustomersView from '@/views/AdminCustomersView.vue';
import AdminEmailTemplatesView from '@/views/AdminEmailTemplatesView.vue';
import AdminMoneyView from '@/views/AdminMoneyView.vue';
import AdminMobileDesignView from '@/views/AdminMobileDesignView.vue';
import AdminVerificationView from '@/views/AdminVerificationView.vue';
import LoginView from '@/views/LoginView.vue';

import AdminSupportTicketsView from '@/views/AdminSupportTicketsView.vue';

const AdminReferralsView = () => import('@/views/AdminReferralsView.vue');

const adminMeta = { requiresAdmin: true };

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: LoginView },
    { path: '/', name: 'admin-overview', component: () => import('@/views/AdminOverview.vue'), meta: adminMeta },
    { path: '/customers', name: 'admin-customers', component: AdminCustomersView, meta: adminMeta },
    { path: '/customers/:customerId', name: 'admin-customer-detail', component: AdminCustomerDetail, meta: adminMeta },
    { path: '/verification', name: 'admin-verification', component: AdminVerificationView, meta: adminMeta },
    { path: '/money', name: 'admin-money', component: AdminMoneyView, meta: adminMeta },
    { path: '/cards', name: 'admin-cards', component: AdminCardsView, meta: adminMeta },
    { path: '/mobile-design', name: 'admin-mobile-design', component: AdminMobileDesignView, meta: adminMeta },
    { path: '/referrals', name: 'admin-referrals', component: AdminReferralsView, meta: adminMeta },
    { path: '/support', name: 'admin-support', component: AdminSupportTicketsView, meta: adminMeta },
    { path: '/email-templates', name: 'admin-email-templates', component: AdminEmailTemplatesView, meta: adminMeta },
    { path: '/users/:lookup?', redirect: (to) => to.params.lookup ? `/customers/${to.params.lookup}` : '/customers' },
    { path: '/kyc', redirect: '/verification' },
    { path: '/transactions', redirect: '/money' },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
});

router.beforeEach((to) => {
  const auth = useAuthStore();
  if (to.meta.requiresAdmin && (!auth.isAuthenticated || !auth.isAdmin)) {
    auth.clearSession();
    return { name: 'login', query: { redirect: to.fullPath } };
  }
  if (to.name === 'login' && auth.isAuthenticated && auth.isAdmin) return { name: 'admin-overview' };
  return true;
});

export default router;
