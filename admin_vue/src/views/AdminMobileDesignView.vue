<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, reactive, ref } from 'vue';
import AppShell from '@/components/AppShell.vue';
import { operationsApi, type MobileDesign } from '@/lib/operationsApi';

type EditableDesign = Omit<MobileDesign, 'schemaVersion' | 'updatedAt'>;
type PreviewScreen = 'login' | 'home' | 'card';

const design = reactive<EditableDesign>({
  accentColor: 'B6FF6E',
  appName: 'Mobile Banking',
  fontFamily: '',
  legalEntity: '',
  logoAsset: '',
  loginBackgroundColor: '',
  primaryColor: '7C5CFF',
  supportEmail: '',
  supportPhone: '',
  themeMode: 'dark',
});
const loading = ref(true);
const saving = ref(false);
const exporting = ref(false);
const error = ref('');
const message = ref('');
const updatedAt = ref<string | null>(null);
const original = ref('');
const previewScreen = ref<PreviewScreen>('home');
const previewBrightness = ref<'dark' | 'light'>('dark');
const logoPreviewUrl = ref('');
const localFontFamily = ref('');
let previewFont: FontFace | undefined;

const serializedDesign = computed(() => JSON.stringify(design));
const dirty = computed(() => original.value !== serializedDesign.value);
const initials = computed(() => design.appName.trim().split(/\s+/).slice(0, 2).map((word) => word[0]).join('').toUpperCase() || 'WL');
const effectiveBrightness = computed(() => design.themeMode === 'system' ? previewBrightness.value : design.themeMode);
const previewVariables = computed(() => {
  const dark = effectiveBrightness.value === 'dark';
  const primary = colorValue(design.primaryColor, '7C5CFF');
  const accent = colorValue(design.accentColor, 'B6FF6E');
  const loginBackground = design.loginBackgroundColor.trim()
    ? colorValue(design.loginBackgroundColor, '6E48FF')
    : '';
  return {
    '--mobile-primary': primary,
    '--mobile-primary-text': '#ffffff',
    '--mobile-accent': accent,
    '--mobile-accent-text': '#000000',
    '--mobile-bg': dark ? '#0B0B0F' : '#F6F7FB',
    '--mobile-surface': dark ? '#15161D' : '#FFFFFF',
    '--mobile-subtle': dark ? '#1B1D26' : '#F1F3F8',
    '--mobile-soft': dark ? '#22242F' : '#E9ECF4',
    '--mobile-pressed': dark ? '#2A2C38' : '#DFE3EE',
    '--mobile-border': dark ? '#262833' : '#E3E6EE',
    '--mobile-text': dark ? '#F5F6FA' : '#0E1116',
    '--mobile-muted': dark ? '#9AA3B2' : '#6B7280',
    '--mobile-success': '#22C58A',
    '--mobile-login-text': loginBackground ? contrastColor(loginBackground) : '#ffffff',
    '--mobile-card-a': dark ? '#0F172A' : '#0F172A',
    '--mobile-card-b': dark ? '#312E81' : '#312E81',
    '--mobile-card-c': dark ? '#7C3AED' : '#7C3AED',
    '--mobile-hero-a': loginBackground || (dark ? '#6E48FF' : '#7C5CFF'),
    '--mobile-hero-b': loginBackground || (dark ? '#301F9C' : '#4C32C7'),
    fontFamily: localFontFamily.value || design.fontFamily || 'Inter, ui-sans-serif, system-ui, sans-serif',
  };
});

function colorValue(value: string, fallback: string) {
  const normalized = value.trim().replace(/^#/, '');
  return `#${/^[0-9a-f]{6}$/i.test(normalized) ? normalized : fallback}`;
}

function contrastColor(color: string) {
  const hex = color.replace('#', '');
  const channels = [0, 2, 4].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16) / 255);
  const luminance = channels
    .map((channel) => channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4)
    .reduce((sum, channel, index) => sum + channel * [0.2126, 0.7152, 0.0722][index], 0);
  return luminance > 0.45 ? '#0E1116' : '#ffffff';
}

function applyResponse(response: MobileDesign) {
  design.appName = response.appName;
  design.primaryColor = response.primaryColor;
  design.accentColor = response.accentColor;
  design.themeMode = response.themeMode;
  design.fontFamily = response.fontFamily;
  design.logoAsset = response.logoAsset;
  design.loginBackgroundColor = response.loginBackgroundColor ?? '';
  design.supportEmail = response.supportEmail;
  design.supportPhone = response.supportPhone;
  design.legalEntity = response.legalEntity;
  updatedAt.value = response.updatedAt;
  original.value = JSON.stringify(design);
  if (response.themeMode !== 'system') previewBrightness.value = response.themeMode;
}

async function load() {
  loading.value = true;
  error.value = '';
  try {
    applyResponse(await operationsApi.mobileDesign());
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Mobile design could not be loaded.';
  } finally {
    loading.value = false;
  }
}

async function save(showMessage = true) {
  saving.value = true;
  error.value = '';
  message.value = '';
  try {
    applyResponse(await operationsApi.saveMobileDesign({ ...design }));
    if (showMessage) message.value = 'Mobile design saved for this white label.';
    return true;
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Mobile design could not be saved.';
    return false;
  } finally {
    saving.value = false;
  }
}

async function exportBuildFile() {
  exporting.value = true;
  error.value = '';
  message.value = '';
  try {
    if (dirty.value && !(await save(false))) return;
    const blob = await operationsApi.exportMobileDesign();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = 'wl-flutter-design.json';
    link.click();
    URL.revokeObjectURL(url);
    message.value = 'Flutter build file downloaded.';
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Build file could not be downloaded.';
  } finally {
    exporting.value = false;
  }
}

function setColor(field: 'primaryColor' | 'accentColor' | 'loginBackgroundColor', value: string) {
  design[field] = value.replace('#', '').toUpperCase();
}

function previewLogo(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (!file) return;
  if (logoPreviewUrl.value) URL.revokeObjectURL(logoPreviewUrl.value);
  logoPreviewUrl.value = URL.createObjectURL(file);
  design.logoAsset = `assets/brand/${file.name}`;
}

async function previewFontFile(event: Event) {
  const file = (event.target as HTMLInputElement).files?.[0];
  if (!file) return;
  try {
    if (previewFont) document.fonts.delete(previewFont);
    const family = `WLPreview${Date.now()}`;
    previewFont = new FontFace(family, await file.arrayBuffer());
    await previewFont.load();
    document.fonts.add(previewFont);
    localFontFamily.value = family;
    if (!design.fontFamily) design.fontFamily = file.name.replace(/\.(ttf|otf|woff2?)$/i, '').replace(/[-_]+/g, ' ');
  } catch {
    error.value = 'This font file could not be previewed.';
  }
}

onMounted(load);
onBeforeUnmount(() => {
  if (logoPreviewUrl.value) URL.revokeObjectURL(logoPreviewUrl.value);
  if (previewFont) document.fonts.delete(previewFont);
});
</script>

<template>
  <AppShell>
    <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
      <div>
        <h1 class="page-title">Mobile design</h1>
        <p class="page-subtitle">Create the white-label Flutter theme, preview it, and export the build configuration.</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button class="secondary-button" :disabled="loading || exporting" @click="exportBuildFile"><i class="pi pi-download" />{{ exporting ? 'Preparing…' : 'Export build file' }}</button>
        <button class="primary-button" :disabled="loading || saving || !dirty" @click="save()"><i class="pi pi-check" />{{ saving ? 'Saving…' : 'Save design' }}</button>
      </div>
    </div>

    <div v-if="error" class="mt-5 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</div>
    <div v-if="message" class="mt-5 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-700">{{ message }}</div>
    <div v-if="loading" class="mt-6 panel h-[680px] animate-pulse bg-slate-100" />

    <div v-else class="mt-6 grid gap-5 xl:grid-cols-[minmax(0,1fr)_430px]">
      <div class="space-y-5">
        <section class="panel p-5">
          <h2 class="panel-heading">Brand identity</h2>
          <div class="mt-4 grid gap-4 2xl:grid-cols-2">
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">App name<input v-model="design.appName" class="field-control" maxlength="80" /></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Theme mode<select v-model="design.themeMode" class="field-control"><option value="dark">Dark</option><option value="light">Light</option><option value="system">Follow device</option></select></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Primary color<div class="flex gap-2"><input :value="colorValue(design.primaryColor, '7C5CFF')" type="color" class="h-11 w-14 cursor-pointer rounded-xl border border-slate-300 bg-white p-1" @input="setColor('primaryColor', ($event.target as HTMLInputElement).value)" /><input v-model="design.primaryColor" class="field-control min-w-0 flex-1 font-mono uppercase" maxlength="7" /></div></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Accent color<div class="flex gap-2"><input :value="colorValue(design.accentColor, 'B6FF6E')" type="color" class="h-11 w-14 cursor-pointer rounded-xl border border-slate-300 bg-white p-1" @input="setColor('accentColor', ($event.target as HTMLInputElement).value)" /><input v-model="design.accentColor" class="field-control min-w-0 flex-1 font-mono uppercase" maxlength="7" /></div></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700 2xl:col-span-2">Login background color<div class="flex flex-wrap gap-2"><input :value="colorValue(design.loginBackgroundColor, '6E48FF')" type="color" class="h-11 w-14 cursor-pointer rounded-xl border border-slate-300 bg-white p-1" @input="setColor('loginBackgroundColor', ($event.target as HTMLInputElement).value)" /><input v-model="design.loginBackgroundColor" class="field-control min-w-0 flex-1 font-mono uppercase" maxlength="7" placeholder="Default gradient" /><button v-if="design.loginBackgroundColor" type="button" class="secondary-button" @click="design.loginBackgroundColor = ''">Use default gradient</button></div><span class="text-xs font-normal leading-5 text-slate-500">Set a solid login background, or leave blank to keep the standard gradient.</span></label>
          </div>
        </section>

        <section class="panel p-5">
          <h2 class="panel-heading">Typography and logo</h2>
          <div class="mt-4 grid gap-4 2xl:grid-cols-2">
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Flutter font family<input v-model="design.fontFamily" class="field-control" maxlength="80" placeholder="System default" /><span class="text-xs font-normal leading-5 text-slate-500">Must match a family declared in the Flutter pubspec.</span></label>
            <label class="grid min-w-0 gap-1.5 text-sm font-semibold text-slate-700">Preview a font file<input type="file" accept=".ttf,.otf,.woff,.woff2" class="field-control w-full min-w-0 py-2" @change="previewFontFile" /><span class="text-xs font-normal leading-5 text-slate-500">The file stays on this computer; add it to the app before building.</span></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Flutter logo asset path<input v-model="design.logoAsset" class="field-control" maxlength="240" placeholder="assets/brand/logo.png" /><span class="text-xs font-normal leading-5 text-slate-500">Use a relative asset path declared in the Flutter pubspec.</span></label>
            <label class="grid min-w-0 gap-1.5 text-sm font-semibold text-slate-700">Preview a logo file<input type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml" class="field-control w-full min-w-0 py-2" @change="previewLogo" /><span class="text-xs font-normal leading-5 text-slate-500">Sets the suggested path to assets/brand/filename.</span></label>
          </div>
        </section>

        <section class="panel p-5">
          <h2 class="panel-heading">Customer support and legal</h2>
          <div class="mt-4 grid gap-4 2xl:grid-cols-2">
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Support email<input v-model="design.supportEmail" type="email" class="field-control" maxlength="320" /></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Support phone<input v-model="design.supportPhone" class="field-control" maxlength="40" /></label>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700 2xl:col-span-2">Legal entity<input v-model="design.legalEntity" class="field-control" maxlength="160" /></label>
          </div>
        </section>

        <section class="panel p-5">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><div><h2 class="panel-heading">Flutter build file</h2><p class="mt-1 text-sm text-slate-500">The exported JSON maps directly to the app’s existing compile-time branding fields.</p></div><button class="secondary-button shrink-0" :disabled="exporting" @click="exportBuildFile"><i class="pi pi-download" />Download JSON</button></div>
          <div class="mt-4 rounded-xl bg-slate-950 p-4 font-mono text-xs leading-6 text-slate-200">flutter build appbundle --dart-define-from-file=wl-flutter-design.json</div>
          <div class="mt-3 text-xs text-slate-500">Saving is automatic before export. Logo and font binaries are not uploaded; include them in the Flutter project at the paths above.</div>
        </section>
      </div>

      <aside class="xl:sticky xl:top-8">
        <div class="panel p-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div><div class="panel-heading">Live app preview</div><div class="mt-1 text-xs text-slate-500">{{ dirty ? 'Unsaved changes' : updatedAt ? 'Saved design' : 'Default design' }}</div></div>
            <button v-if="design.themeMode === 'system'" class="secondary-button !min-h-9 !px-3 !text-xs" @click="previewBrightness = previewBrightness === 'dark' ? 'light' : 'dark'"><i :class="previewBrightness === 'dark' ? 'pi pi-moon' : 'pi pi-sun'" />{{ previewBrightness }}</button>
          </div>
          <div class="mt-4 flex rounded-xl bg-slate-100 p-1">
            <button v-for="screen in (['login','home','card'] as PreviewScreen[])" :key="screen" class="flex-1 rounded-lg px-3 py-2 text-xs font-semibold capitalize" :class="previewScreen === screen ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" @click="previewScreen = screen">{{ screen }}</button>
          </div>

          <div class="mx-auto mt-5 max-w-[360px] rounded-[36px] bg-slate-950 p-[9px] shadow-2xl shadow-slate-900/20">
            <div class="mobile-preview relative h-[760px] overflow-hidden rounded-[28px]" :class="{ 'login-preview': previewScreen === 'login' }" :style="previewVariables">
              <div class="mobile-status-bar"><span>9:41</span><div class="flex items-center gap-1"><i class="pi pi-signal text-[10px]" /><i class="pi pi-wifi text-[10px]" /><i class="pi pi-battery-full text-[11px]" /></div></div>

              <!-- Mirrors LoginScreen's mobile branch: gradient hero + raised sign-in Card. -->
              <div v-if="previewScreen === 'login'" class="login-scroll">
                <div class="login-hero">
                  <div class="flex items-center gap-3.5">
                    <div class="login-logo"><img v-if="logoPreviewUrl" :src="logoPreviewUrl" alt="Logo preview" /><i v-else class="pi pi-bolt" /></div>
                    <div class="text-xl font-extrabold">{{ design.appName || 'Mobile Banking' }}</div>
                  </div>
                  <div class="login-subtitle mt-6 text-[15px]">Welcome</div>
                  <div class="mt-1 text-[27px] font-extrabold leading-none">Sign in to your account</div>
                </div>
                <div class="login-card">
                  <div class="text-[22px] font-extrabold">Sign in</div>
                  <div class="preview-muted mt-1 text-[12px]">Use your email and password to continue.</div>
                  <div class="preview-field mt-5"><i class="pi pi-envelope" /><span>Email</span></div>
                  <div class="preview-field mt-3"><i class="pi pi-lock" /><span>Password</span><i class="pi pi-eye ml-auto" /></div>
                  <div class="mt-2 flex items-center justify-between py-1.5"><div><div class="text-[12px] font-semibold">Remember email</div><div class="preview-muted text-[9px]">Only your email is stored locally.</div></div><div class="preview-switch"><span /></div></div>
                  <button class="preview-primary mt-3"><i class="pi pi-sign-in" /> Sign in</button>
                  <button class="preview-outline mt-2"><i class="pi pi-user-plus" /> Create account</button>
                </div>
              </div>

              <!-- Mirrors the real staging DashboardScreen captured in the emulator. -->
              <div v-else-if="previewScreen === 'home'" class="screen-scroll">
                <div class="real-home-app-bar"><div class="home-brand-mark"><img v-if="logoPreviewUrl" :src="logoPreviewUrl" alt="Logo preview" /><i v-else class="pi pi-wallet" /></div><div class="min-w-0 flex-1 truncate">Good afternoon, Rok</div><i class="pi pi-cog text-xl" /></div>
                <div class="px-4 pb-28 pt-1">
                  <div class="onboarding-complete"><div class="complete-icon"><i class="pi pi-verified" /></div><div class="min-w-0 flex-1"><div class="text-[13px] font-extrabold">Crypto card onboarding complete</div><div class="preview-muted mt-0.5 text-[11px]">Your Interlace Crypto Card KYC is approved.</div></div><i class="pi pi-angle-right text-emerald-500" /></div>
                  <div class="mt-3.5 grid grid-cols-4 gap-2"><div v-for="action in [{icon:'pi-arrow-up-right',label:'Send'},{icon:'pi-arrow-right-arrow-left',label:'Exchange'},{icon:'pi-plus',label:'Buy'},{icon:'pi-arrow-down',label:'Deposit'}]" :key="action.label" class="real-quick-action"><i class="pi" :class="action.icon" /><span>{{ action.label }}</span></div></div>
                  <div class="section-heading mt-7"><strong>Your balances</strong><span>View all</span></div>
                  <div class="provider-balance-card mt-3"><span class="provider-line primary" /><div class="min-w-0 flex-1"><div class="flex items-center gap-2"><strong class="truncate">Interlace Crypto card</strong><span class="active-badge ml-auto">Active</span></div><div class="preview-muted text-[10px]">Everyday account</div><div class="mt-3 text-[16px] font-extrabold">$7.38</div></div><i class="pi pi-angle-right self-center" /></div>
                  <div class="provider-balance-card mt-3"><span class="provider-line success" /><div class="min-w-0 flex-1"><div class="flex items-center gap-2"><strong>Equals Money</strong><span class="active-badge ml-auto">Active</span></div><div class="preview-muted text-[10px]">Card &amp; business budgets</div><div class="mt-3 text-[16px] font-extrabold">£380.00</div></div><i class="pi pi-angle-right self-center" /></div>
                  <div class="provider-balance-card mt-3"><span class="provider-line blue" /><div class="min-w-0 flex-1"><div class="flex items-center gap-2"><strong>BoomFi Exchange</strong><span class="active-badge ml-auto">Active</span></div><div class="preview-muted text-[10px]">Crypto account</div><div class="mt-3 text-[15px] font-extrabold">520.07 USDC<br />€90.25</div></div><i class="pi pi-angle-right self-center" /></div>
                  <div class="rewards-preview mt-3"><div class="rewards-icon"><i class="pi pi-gift" /></div><strong>Rewards</strong><i class="pi pi-angle-right ml-auto" /></div>
                </div>
              </div>

              <!-- Mirrors the real staging CardsScreen captured in the emulator. -->
              <div v-else class="screen-scroll">
                <div class="cards-app-bar"><div>Cards</div><span><i class="pi pi-plus" /> Order card</span></div>
                <div class="px-4 pb-28 pt-1">
                  <div class="spending-summary">
                    <div class="min-w-0 flex-1"><div class="preview-muted text-[11px]">Card spending</div><div class="mt-2 text-[24px] font-extrabold">USD 0.00</div><div class="preview-muted text-[11px]">this month</div></div>
                    <div class="count-metric"><strong>1</strong><span>Active</span></div><div class="count-metric"><strong>4</strong><span>Frozen</span></div>
                  </div>
                  <div class="real-bank-card mt-4"><div class="flex items-center"><div class="card-chip" /><i class="pi pi-mobile ml-3 text-white/80" /><span class="ml-auto text-[9px] font-bold tracking-[0.16em] text-white/80">VIRTUAL</span></div><div class="mt-10 text-[20px] font-extrabold text-white">USD 0.00</div><div class="mt-2 text-[11px] font-semibold tracking-[0.14em] text-white/90">CARD</div><div class="mt-3 font-mono text-[15px] font-semibold tracking-[0.17em] text-white">•••• •••• •••• 7541</div></div>
                  <div class="mt-3 grid grid-cols-3 gap-2"><div v-for="action in [{icon:'pi-eye',label:'Details'},{icon:'pi-sliders-h',label:'Controls'},{icon:'pi-receipt',label:'Activity'}]" :key="action.label" class="card-quick-action"><i class="pi" :class="action.icon" /><strong>{{ action.label }}</strong></div></div>
                  <div class="section-heading mt-7"><strong>Your cards</strong><span>Order</span></div>
                  <div class="grouped-cards mt-3">
                    <div class="card-list-row"><div class="card-state-icon frozen"><i class="pi pi-wifi" /></div><div class="min-w-0 flex-1"><div class="text-[13px]">Card</div><div class="card-list-balance"><span>•••• •••• •••• 3191</span><strong>USD 0.00</strong></div><div class="preview-muted text-[10px]">Crypto card • Virtual</div></div><span class="frozen-badge">Frozen</span><i class="pi pi-angle-right preview-muted" /></div>
                    <div class="card-list-row"><div class="card-state-icon active"><i class="pi pi-wifi" /></div><div class="min-w-0 flex-1"><div class="text-[13px]">Card</div><div class="card-list-balance"><span>•••• •••• •••• 7541</span><strong>GBP 125.00</strong></div><div class="preview-muted text-[10px]">Equals Money • Virtual</div></div><span class="active-badge">Active</span><i class="pi pi-angle-right preview-muted" /></div>
                  </div>
                </div>
              </div>

              <div v-if="previewScreen !== 'login'" class="mobile-bottom-nav">
                <div v-for="item in [{screen:'home',icon:'pi-home',label:'Home'},{screen:'money',icon:'pi-wallet',label:'Accounts'},{screen:'card',icon:'pi-credit-card',label:'Cards'},{screen:'activity',icon:'pi-receipt',label:'Activity'},{screen:'rewards',icon:'pi-gift',label:'Rewards'}]" :key="item.screen" :class="{ active: previewScreen === item.screen }"><i class="pi" :class="item.icon" /><span>{{ item.label }}</span></div>
              </div>
            </div>
          </div>
        </div>
      </aside>
    </div>
  </AppShell>
</template>

<style scoped>
.mobile-preview { background: var(--mobile-bg); color: var(--mobile-text); }
.mobile-status-bar { align-items:center; display:flex; font-size:10px; font-weight:700; height:28px; justify-content:space-between; padding:0 20px; position:relative; z-index:5; }
.preview-muted { color: var(--mobile-muted); }
.preview-primary-text { color: var(--mobile-primary); }
.login-preview { background:linear-gradient(135deg,var(--mobile-hero-a),var(--mobile-hero-b)); color:var(--mobile-login-text); }
.login-preview .mobile-status-bar { color:var(--mobile-login-text); opacity:.72; }
.login-subtitle { color:var(--mobile-login-text); opacity:.75; }
.login-scroll { height:732px; overflow:hidden; padding:22px 18px 24px; }
.login-hero { padding:12px 4px 0; }
.login-logo { align-items:center; background:rgba(255,255,255,.16); border-radius:16px; display:flex; font-size:22px; height:52px; justify-content:center; overflow:hidden; width:52px; }
.login-logo img { height:100%; object-fit:contain; padding:8px; width:100%; }
.login-card { background:var(--mobile-surface); border-radius:28px; color:var(--mobile-text); margin-top:24px; padding:22px; }
.preview-field { align-items:center; background:var(--mobile-subtle); border:1px solid var(--mobile-border); border-radius:14px; color:var(--mobile-muted); display:flex; font-size:12px; gap:10px; min-height:50px; padding:0 14px; }
.preview-primary,.preview-outline { align-items:center; border-radius:18px; display:flex; font-size:12px; font-weight:700; gap:8px; justify-content:center; min-height:48px; width:100%; }
.preview-primary { background:var(--mobile-primary); color:#fff; }
.preview-outline { border:1.2px solid var(--mobile-border); color:var(--mobile-text); }
.preview-switch { background:var(--mobile-pressed); border-radius:999px; height:22px; padding:3px; width:38px; }
.preview-switch span { background:var(--mobile-muted); border-radius:50%; display:block; height:16px; width:16px; }
.screen-scroll { height:732px; overflow:hidden; }
.real-home-app-bar { align-items:center; background:var(--mobile-bg); display:flex; font-size:16px; font-weight:800; gap:11px; height:64px; padding:0 16px; }
.home-brand-mark { align-items:center; background:var(--mobile-primary); border-radius:14px; color:#fff; display:flex; flex:0 0 auto; height:38px; justify-content:center; overflow:hidden; width:38px; }
.home-brand-mark img { height:100%; object-fit:contain; padding:5px; width:100%; }
.onboarding-complete { align-items:center; background:rgba(34,197,138,.10); border:1px solid rgba(34,197,138,.28); border-radius:22px; display:flex; gap:10px; padding:14px; }
.complete-icon { align-items:center; background:rgba(34,197,138,.16); border-radius:50%; color:var(--mobile-success); display:flex; flex:0 0 auto; height:40px; justify-content:center; width:40px; }
.real-quick-action { align-items:center; background:var(--mobile-subtle); border:1px solid var(--mobile-border); border-radius:18px; display:flex; flex-direction:column; font-size:10px; font-weight:700; gap:8px; height:74px; justify-content:center; }
.real-quick-action i { color:var(--mobile-primary); font-size:18px; }
.section-heading { align-items:center; display:flex; font-size:13px; justify-content:space-between; }
.section-heading span { color:var(--mobile-primary); font-size:10px; font-weight:700; }
.provider-balance-card { align-items:flex-start; background:var(--mobile-surface); border:1px solid var(--mobile-border); border-radius:22px; display:flex; gap:11px; min-height:100px; padding:14px; }
.provider-line { align-self:stretch; border-radius:999px; flex:0 0 4px; }
.provider-line.primary { background:var(--mobile-primary); }
.provider-line.success { background:var(--mobile-success); }
.provider-line.blue { background:#4C8DFF; }
.active-badge,.frozen-badge { border-radius:999px; font-size:9px; font-weight:700; padding:5px 9px; }
.active-badge { background:rgba(34,197,138,.13); color:var(--mobile-success); }
.frozen-badge { background:rgba(247,185,85,.16); color:#D9962E; }
.rewards-preview { align-items:center; background:color-mix(in srgb,var(--mobile-primary) 12%,var(--mobile-surface)); border:1px solid color-mix(in srgb,var(--mobile-primary) 28%,transparent); border-radius:22px; display:flex; gap:11px; padding:14px; }
.rewards-icon { align-items:center; background:color-mix(in srgb,var(--mobile-primary) 18%,transparent); border-radius:50%; color:var(--mobile-primary); display:flex; height:40px; justify-content:center; width:40px; }
.cards-app-bar { align-items:center; background:var(--mobile-bg); display:flex; font-size:20px; font-weight:800; height:64px; justify-content:space-between; padding:0 16px; }
.cards-app-bar span { align-items:center; color:var(--mobile-primary); display:flex; font-size:12px; gap:7px; }
.spending-summary { align-items:center; background:var(--mobile-surface); border:1px solid var(--mobile-border); border-radius:22px; display:flex; gap:14px; padding:16px; }
.count-metric { align-items:center; display:flex; flex-direction:column; }
.count-metric strong { font-size:18px; }
.count-metric span { color:var(--mobile-muted); font-size:10px; }
.real-bank-card { background:linear-gradient(135deg,#064E3B,#0F766E,#22C55E); border-radius:26px; box-shadow:0 12px 24px rgba(15,118,110,.26); height:210px; overflow:hidden; padding:20px; position:relative; }
.real-bank-card::after { background:rgba(255,255,255,.09); border-radius:50%; content:''; height:160px; position:absolute; right:-38px; top:-42px; width:160px; }
.card-chip { background:linear-gradient(135deg,#E5C56A,#B7873E); border-radius:5px; height:22px; width:30px; }
.card-quick-action { align-items:center; background:var(--mobile-subtle); border:1px solid var(--mobile-border); border-radius:18px; display:flex; flex-direction:column; font-size:10px; gap:10px; height:74px; justify-content:center; }
.card-quick-action i { color:var(--mobile-primary); font-size:18px; }
.grouped-cards { background:var(--mobile-surface); border:1px solid var(--mobile-border); border-radius:22px; overflow:hidden; }
.card-list-row { align-items:center; display:flex; gap:11px; min-height:72px; padding:12px 14px; }
.card-list-row + .card-list-row { border-top:1px solid var(--mobile-border); }
.card-list-balance { align-items:center; display:flex; font-size:10px; gap:8px; justify-content:space-between; white-space:nowrap; }
.card-list-balance strong { flex:0 0 auto; font-size:10px; }
.card-state-icon { align-items:center; border-radius:14px; display:flex; flex:0 0 auto; height:42px; justify-content:center; width:42px; }
.card-state-icon.frozen { background:rgba(247,185,85,.15); color:#D9962E; }
.card-state-icon.active { background:rgba(34,197,138,.13); color:var(--mobile-success); }
.mobile-bottom-nav { align-items:center; background:var(--mobile-surface); border:1px solid var(--mobile-border); border-radius:28px; bottom:10px; box-shadow:0 14px 28px rgba(0,0,0,.18); display:grid; grid-template-columns:repeat(5,1fr); height:70px; left:12px; overflow:hidden; padding:0 4px; position:absolute; right:12px; z-index:10; }
.mobile-bottom-nav > div { align-items:center; color:var(--mobile-muted); display:flex; flex-direction:column; font-size:8px; gap:4px; justify-content:center; min-width:0; }
.mobile-bottom-nav > div i { font-size:16px; }
.mobile-bottom-nav > div.active { color:var(--mobile-primary); }
.mobile-bottom-nav > div.active i { background:color-mix(in srgb,var(--mobile-primary) 18%,transparent); border-radius:999px; padding:6px 16px; }
</style>
