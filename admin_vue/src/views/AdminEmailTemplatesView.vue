<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import type Quill from 'quill';
import Editor from 'primevue/editor';
import AppShell from '@/components/AppShell.vue';
import StatusPill from '@/components/StatusPill.vue';
import { describeAdminError } from '@/lib/adminApi';
import { formatDateTime, relativeTime } from '@/lib/formatters';
import {
  operationsApi,
  type EmailDeliveryStatus,
  type EmailMessageRow,
  type EmailPreview,
  type EmailTemplate,
  type EmailTemplateDraft,
} from '@/lib/operationsApi';

type EditableField = 'heading' | 'htmlBody' | 'subject' | 'textBody';
type EditorMode = 'html' | 'visual';
type PreviewMode = 'html' | 'text';

const templates = ref<EmailTemplate[]>([]);
const delivery = ref<EmailDeliveryStatus | null>(null);
const selectedKey = ref('');
const draft = reactive<EmailTemplateDraft>({ htmlBody: '', isEnabled: true, subject: '', textBody: '' });
const original = ref('');

const loading = ref(true);
const saving = ref(false);
const resetting = ref(false);
const sendingTest = ref(false);
const error = ref('');
const message = ref('');

const preview = ref<EmailPreview | null>(null);
const previewMode = ref<PreviewMode>('html');
const previewLoading = ref(false);
const previewError = ref('');
let previewTimer: ReturnType<typeof setTimeout> | undefined;
let previewRequest = 0;

const testEmail = ref('');
const messages = ref<EmailMessageRow[]>([]);
const messagesLoading = ref(false);
const messagesFilter = ref<'all' | 'selected'>('selected');

const subjectInput = ref<HTMLInputElement | null>(null);
const headingInput = ref<HTMLInputElement | null>(null);
const htmlInput = ref<HTMLTextAreaElement | null>(null);
const textInput = ref<HTMLTextAreaElement | null>(null);
// PrimeVue's Editor exposes the underlying Quill instance as `quill`.
const editorRef = ref<{ quill?: Quill } | null>(null);
const lastFocused = ref<EditableField>('htmlBody');

// Visual editing works on the parts of the layout bracketed by these markers
// (written by the backend's template layout); the rest of the HTML is kept
// untouched so admins cannot break the email frame.
const HEADING_MARKERS = ['<!--heading:start-->', '<!--heading:end-->'] as const;
const CONTENT_MARKERS = ['<!--content:start-->', '<!--content:end-->'] as const;
const editorMode = ref<EditorMode>('visual');
const visual = reactive({ content: '', heading: '' });
let syncingVisual = false;

function markerSpan(html: string, [start, end]: readonly [string, string]) {
  const from = html.indexOf(start);
  const to = from === -1 ? -1 : html.indexOf(end, from + start.length);
  return from === -1 || to === -1 ? null : { from: from + start.length, to };
}

function parseVisual(html: string) {
  const heading = markerSpan(html, HEADING_MARKERS);
  const content = markerSpan(html, CONTENT_MARKERS);
  if (!heading || !content) return null;
  return {
    content: html.slice(content.from, content.to).trim(),
    heading: decodeEntities(html.slice(heading.from, heading.to).trim()),
  };
}

function decodeEntities(value: string) {
  const parser = new DOMParser().parseFromString(value, 'text/html');
  return parser.documentElement.textContent ?? value;
}

function encodeEntities(value: string) {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

const visualAvailable = computed(() => parseVisual(draft.htmlBody) !== null);

function syncVisualFromDraft() {
  const parsed = parseVisual(draft.htmlBody);
  syncingVisual = true;
  visual.heading = parsed?.heading ?? '';
  visual.content = parsed?.content ?? '';
  editorMode.value = parsed ? editorMode.value : 'html';
  void nextTick(() => {
    syncingVisual = false;
  });
}

function applyVisualToDraft() {
  if (syncingVisual || editorMode.value !== 'visual') return;
  const html = draft.htmlBody;
  const heading = markerSpan(html, HEADING_MARKERS);
  const content = markerSpan(html, CONTENT_MARKERS);
  if (!heading || !content) return;
  // Replace the later span first so the earlier offsets stay valid.
  const [first, second] = heading.from < content.from ? [heading, content] : [content, heading];
  // Quill emits every space as &nbsp;, which stops mail clients from wrapping
  // lines; plain spaces are what the email needs.
  const contentHtml = `\n${visual.content.replace(/&nbsp;/g, ' ')}\n`;
  const firstValue = first === heading ? encodeEntities(visual.heading) : contentHtml;
  const secondValue = second === heading ? encodeEntities(visual.heading) : contentHtml;
  const next = `${html.slice(0, first.from)}${firstValue}${html.slice(first.to, second.from)}${secondValue}${html.slice(second.to)}`;
  if (next !== html) draft.htmlBody = next;
}

function setEditorMode(mode: EditorMode) {
  if (mode === editorMode.value) return;
  if (mode === 'visual') {
    if (!visualAvailable.value) return;
    editorMode.value = 'visual';
    syncVisualFromDraft();
    return;
  }
  editorMode.value = 'html';
}

function insertIntoEditor(token: string) {
  const quill = editorRef.value?.quill;
  if (!quill) {
    visual.content = `${visual.content}<p>${token}</p>`;
    return;
  }
  const range = quill.getSelection(true) ?? { index: quill.getLength() - 1, length: 0 };
  if (range.length) quill.deleteText(range.index, range.length, 'user');
  quill.insertText(range.index, token, 'user');
  quill.setSelection(range.index + token.length, 0, 'user');
}

/// Plain-text version of the visual content for mail clients that block HTML.
function textFromVisual() {
  const doc = new DOMParser().parseFromString(`<div>${visual.content}</div>`, 'text/html');
  const lines: string[] = [];
  const blocks = doc.body.querySelectorAll('p, h1, h2, h3, li, blockquote');
  blocks.forEach((block) => {
    const text = (block.textContent ?? '').replace(/\s+/g, ' ').trim();
    if (!text) return;
    lines.push(block.tagName === 'LI' ? `- ${text}` : text);
    if (block.tagName !== 'LI') lines.push('');
  });
  if (!blocks.length) lines.push((doc.body.textContent ?? '').trim());
  const body = lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  return `${visual.heading.trim()}\n\n${body}\n\nNeed help? Contact {{supportEmail}}.`.trim();
}

function fillTextFromVisual() {
  if (draft.textBody.trim() && !window.confirm('Replace the plain-text body with text generated from the visual editor?')) return;
  draft.textBody = textFromVisual();
}

const selected = computed(() => templates.value.find((template) => template.key === selectedKey.value) ?? null);
const serializedDraft = computed(() => JSON.stringify(draft));
const dirty = computed(() => original.value !== serializedDraft.value);
const canSendTest = computed(() => Boolean(delivery.value?.configured) && /\S+@\S+\.\S+/.test(testEmail.value.trim()));
const previewDocument = computed(() => preview.value?.htmlBody ?? '');

function statusTone(status: string) {
  switch (status) {
    case 'sent':
      return 'success';
    case 'failed':
      return 'danger';
    case 'skipped':
      return 'neutral';
    default:
      return 'warning';
  }
}

function loadDraft(template: EmailTemplate) {
  draft.subject = template.subject;
  draft.htmlBody = template.htmlBody;
  draft.textBody = template.textBody;
  draft.isEnabled = template.isEnabled;
  original.value = JSON.stringify(draft);
  syncVisualFromDraft();
  if (visualAvailable.value) editorMode.value = 'visual';
}

function applySaved(template: EmailTemplate) {
  templates.value = templates.value.map((existing) => (existing.key === template.key ? template : existing));
  loadDraft(template);
}

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const data = await operationsApi.emailTemplates();
    templates.value = data.templates;
    delivery.value = data.delivery;
    const first = data.templates.find((template) => template.key === selectedKey.value) ?? data.templates[0];
    if (first) {
      selectedKey.value = first.key;
      loadDraft(first);
    }
    await loadMessages();
  } catch (caught) {
    error.value = describeAdminError(caught);
  } finally {
    loading.value = false;
  }
}

function select(key: string) {
  if (key === selectedKey.value) return;
  if (dirty.value && !window.confirm('Discard unsaved changes to this template?')) return;
  const template = templates.value.find((candidate) => candidate.key === key);
  if (!template) return;
  selectedKey.value = key;
  message.value = '';
  error.value = '';
  loadDraft(template);
  if (messagesFilter.value === 'selected') void loadMessages();
}

async function save() {
  if (!selected.value) return;
  saving.value = true;
  error.value = '';
  message.value = '';
  try {
    applySaved(await operationsApi.saveEmailTemplate(selected.value.key, { ...draft }));
    message.value = `${selected.value.name} saved.`;
  } catch (caught) {
    error.value = describeAdminError(caught);
  } finally {
    saving.value = false;
  }
}

async function resetToDefault() {
  if (!selected.value) return;
  if (!window.confirm(`Replace "${selected.value.name}" with the built-in default? Your edits will be removed.`)) return;
  resetting.value = true;
  error.value = '';
  message.value = '';
  try {
    applySaved(await operationsApi.resetEmailTemplate(selected.value.key));
    message.value = `${selected.value.name} restored to the default template.`;
  } catch (caught) {
    error.value = describeAdminError(caught);
  } finally {
    resetting.value = false;
  }
}

async function sendTest() {
  if (!selected.value || !canSendTest.value) return;
  sendingTest.value = true;
  error.value = '';
  message.value = '';
  try {
    const queued = await operationsApi.sendTestEmail(selected.value.key, testEmail.value.trim(), {
      htmlBody: draft.htmlBody,
      subject: draft.subject,
      textBody: draft.textBody,
    });
    message.value = `Test email queued for ${queued.toEmail}. Delivery status appears below within a few seconds.`;
    window.setTimeout(() => void loadMessages(), 6000);
    await loadMessages();
  } catch (caught) {
    error.value = describeAdminError(caught);
  } finally {
    sendingTest.value = false;
  }
}

async function loadMessages() {
  messagesLoading.value = true;
  try {
    const data = await operationsApi.emailMessages({
      take: 25,
      templateKey: messagesFilter.value === 'selected' ? selectedKey.value || undefined : undefined,
    });
    messages.value = data.items;
  } catch (caught) {
    error.value = describeAdminError(caught);
  } finally {
    messagesLoading.value = false;
  }
}

function schedulePreview() {
  if (previewTimer) clearTimeout(previewTimer);
  previewTimer = setTimeout(() => void refreshPreview(), 350);
}

async function refreshPreview() {
  if (!selected.value) return;
  const request = ++previewRequest;
  previewLoading.value = true;
  previewError.value = '';
  try {
    const rendered = await operationsApi.previewEmailTemplate(selected.value.key, {
      htmlBody: draft.htmlBody,
      subject: draft.subject,
      textBody: draft.textBody,
    });
    if (request === previewRequest) preview.value = rendered;
  } catch (caught) {
    if (request === previewRequest) previewError.value = describeAdminError(caught);
  } finally {
    if (request === previewRequest) previewLoading.value = false;
  }
}

function placeholderToken(name: string) {
  return `{{${name}}}`;
}

function insertPlaceholder(name: string) {
  const token = placeholderToken(name);
  const field = lastFocused.value;
  if (field === 'htmlBody' && editorMode.value === 'visual') {
    insertIntoEditor(token);
    return;
  }
  if (field === 'heading') {
    insertIntoInput(headingInput.value, token, visual.heading, (value) => {
      visual.heading = value;
    });
    return;
  }
  const element =
    field === 'subject' ? subjectInput.value : field === 'textBody' ? textInput.value : htmlInput.value;
  insertIntoInput(element, token, draft[field], (value) => {
    draft[field] = value;
  });
}

function insertIntoInput(
  element: HTMLInputElement | HTMLTextAreaElement | null,
  token: string,
  current: string,
  assign: (value: string) => void,
) {
  if (!element) {
    assign(`${current}${token}`);
    return;
  }
  const start = element.selectionStart ?? current.length;
  const end = element.selectionEnd ?? start;
  assign(`${current.slice(0, start)}${token}${current.slice(end)}`);
  void nextTick(() => {
    element.focus();
    const caret = start + token.length;
    element.setSelectionRange(caret, caret);
  });
}

watch(() => [draft.subject, draft.htmlBody, draft.textBody, selectedKey.value], schedulePreview);
watch(() => [visual.heading, visual.content], applyVisualToDraft);
watch(messagesFilter, () => void loadMessages());

onMounted(load);
onBeforeUnmount(() => {
  if (previewTimer) clearTimeout(previewTimer);
});
</script>

<template>
  <AppShell>
    <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
      <div>
        <h1 class="page-title">Email templates</h1>
        <p class="page-subtitle">Edit the transactional emails customers receive for password resets, email confirmation, and account connection. Changes apply to the next email sent.</p>
      </div>
      <div class="flex flex-wrap gap-2">
        <button v-if="selected?.isCustomized" class="secondary-button" :disabled="loading || resetting || saving" @click="resetToDefault"><i class="pi pi-refresh" />{{ resetting ? 'Restoring…' : 'Reset to default' }}</button>
        <button class="primary-button" :disabled="loading || saving || !dirty" @click="save"><i class="pi pi-check" />{{ saving ? 'Saving…' : 'Save template' }}</button>
      </div>
    </div>

    <div v-if="error" class="mt-5 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-700" role="alert">{{ error }}</div>
    <div v-if="message" class="mt-5 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm font-semibold text-emerald-700">{{ message }}</div>

    <div v-if="delivery" class="mt-5 flex flex-wrap items-center gap-x-6 gap-y-2 rounded-2xl border px-4 py-3 text-sm" :class="delivery.configured ? 'border-slate-200 bg-white text-slate-700' : 'border-amber-200 bg-amber-50 text-amber-800'">
      <span class="inline-flex items-center gap-2 font-semibold"><i :class="delivery.configured ? 'pi pi-check-circle text-emerald-600' : 'pi pi-exclamation-triangle'" />{{ delivery.provider }} {{ delivery.configured ? 'ready' : 'not configured' }}</span>
      <span v-if="delivery.fromEmail">From: <strong>{{ delivery.fromName ? `${delivery.fromName} <${delivery.fromEmail}>` : delivery.fromEmail }}</strong></span>
      <span v-if="delivery.replyToEmail">Reply-to: <strong>{{ delivery.replyToEmail }}</strong></span>
      <span v-if="!delivery.configured" class="text-xs">Set <code>Email:Provider</code>, <code>Email:FromEmail</code>, and <code>Email:SendGrid:ApiKey</code> in the backend configuration to enable delivery.</span>
    </div>

    <div v-if="loading" class="mt-6 panel h-[640px] animate-pulse bg-slate-100" />

    <div v-else class="mt-6 grid gap-5 xl:grid-cols-[minmax(0,1fr)_470px]">
      <div class="space-y-5">
        <section class="grid gap-3 md:grid-cols-3">
          <button
            v-for="template in templates"
            :key="template.key"
            type="button"
            class="panel p-4 text-left transition hover:border-blue-300"
            :class="template.key === selectedKey ? 'border-blue-500 ring-4 ring-blue-100' : ''"
            @click="select(template.key)"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="text-[15px] font-bold text-slate-950">{{ template.name }}</div>
              <span v-if="!template.isEnabled" class="status-pill status-pill--neutral">Off</span>
              <span v-else-if="template.isCustomized" class="status-pill status-pill--success">Custom</span>
              <span v-else class="status-pill status-pill--neutral">Default</span>
            </div>
            <p class="mt-1.5 text-xs leading-5 text-slate-500">{{ template.description }}</p>
          </button>
        </section>

        <section v-if="selected" class="panel p-5">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="panel-heading">{{ selected.name }}</h2>
              <p class="mt-1 text-xs text-slate-500">{{ selected.isCustomized && selected.updatedAt ? `Last saved ${relativeTime(selected.updatedAt)}` : 'Using the built-in default template' }}<span v-if="dirty" class="ml-2 font-semibold text-amber-600">Unsaved changes</span></p>
            </div>
            <label class="inline-flex cursor-pointer items-center gap-3 text-sm font-semibold text-slate-700">
              <span>Send this email</span>
              <span class="relative inline-flex h-6 w-11 items-center rounded-full transition" :class="draft.isEnabled ? 'bg-blue-600' : 'bg-slate-300'">
                <input v-model="draft.isEnabled" type="checkbox" class="peer sr-only" />
                <span class="absolute left-0.5 size-5 rounded-full bg-white shadow transition" :class="draft.isEnabled ? 'translate-x-5' : ''" />
              </span>
            </label>
          </div>
          <p v-if="!draft.isEnabled" class="mt-3 rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-800">While disabled, the app flow still works but no email is sent for this event.</p>

          <div class="mt-5 grid gap-4">
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Subject<input ref="subjectInput" v-model="draft.subject" class="field-control" maxlength="200" @focus="lastFocused = 'subject'" /></label>

            <div>
              <div class="text-sm font-semibold text-slate-700">Placeholders</div>
              <p class="mt-1 text-xs leading-5 text-slate-500">Click to insert at the cursor in the field you last edited (subject, heading, content or plain text). Values are filled in when the email is sent; HTML is escaped automatically.</p>
              <div class="mt-2 flex flex-wrap gap-1.5">
                <button
                  v-for="placeholder in selected.placeholders"
                  :key="placeholder.name"
                  type="button"
                  class="inline-flex items-center gap-1 rounded-lg border px-2.5 py-1 font-mono text-xs transition hover:border-blue-400 hover:bg-blue-50"
                  :class="placeholder.required ? 'border-blue-200 bg-blue-50 text-blue-800' : 'border-slate-200 bg-slate-50 text-slate-700'"
                  :title="`${placeholder.description} Example: ${placeholder.sample}${placeholder.required ? ' (required)' : ''}`"
                  @click="insertPlaceholder(placeholder.name)"
                >{{ placeholderToken(placeholder.name) }}<i v-if="placeholder.required" class="pi pi-asterisk text-[8px]" /></button>
              </div>
            </div>

            <div class="grid gap-2">
              <div class="flex flex-wrap items-center justify-between gap-2">
                <span class="text-sm font-semibold text-slate-700">Email body</span>
                <div class="flex rounded-xl bg-slate-100 p-1">
                  <button type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold" :class="editorMode === 'visual' ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" :disabled="!visualAvailable" :title="visualAvailable ? '' : 'Visual editing needs the standard layout markers.'" @click="setEditorMode('visual')"><i class="pi pi-pencil mr-1 text-[11px]" />Visual</button>
                  <button type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold" :class="editorMode === 'html' ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" @click="setEditorMode('html')"><i class="pi pi-code mr-1 text-[11px]" />HTML</button>
                </div>
              </div>
              <p v-if="!visualAvailable" class="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-xs leading-5 text-amber-800">This template's HTML no longer contains the layout markers the visual editor needs (it was edited by hand or saved before the visual editor existed). Edit the HTML directly, or use <strong>Reset to default</strong> and re-apply your wording in the visual editor.</p>

              <template v-if="editorMode === 'visual' && visualAvailable">
                <label class="grid gap-1.5 text-sm font-semibold text-slate-700">Heading<input ref="headingInput" v-model="visual.heading" class="field-control" maxlength="120" placeholder="Reset your password" @focus="lastFocused = 'heading'" /></label>
                <div class="grid gap-1.5 text-sm font-semibold text-slate-700" @focusin="lastFocused = 'htmlBody'">
                  <span>Content</span>
                  <Editor ref="editorRef" v-model="visual.content" editor-style="height: 320px" class="email-visual-editor">
                    <template #toolbar>
                      <span class="ql-formats">
                        <select class="ql-header" title="Text style"><option value="2">Section heading</option><option value="1">Large code line</option><option selected>Paragraph</option></select>
                      </span>
                      <span class="ql-formats">
                        <button class="ql-bold" type="button" title="Bold" /><button class="ql-italic" type="button" title="Italic" /><button class="ql-underline" type="button" title="Underline" />
                      </span>
                      <span class="ql-formats">
                        <button class="ql-list" value="ordered" type="button" title="Numbered list" /><button class="ql-list" value="bullet" type="button" title="Bullet list" />
                      </span>
                      <span class="ql-formats">
                        <button class="ql-link" type="button" title="Link" /><button class="ql-clean" type="button" title="Clear formatting" />
                      </span>
                    </template>
                  </Editor>
                  <span class="text-xs font-normal leading-5 text-slate-500">Type your wording and use the placeholder buttons above to insert values such as the code. “Large code line” renders as the big spaced-out number in the email; the frame, header and footer stay as designed.</span>
                </div>
              </template>
              <label v-else class="grid gap-1.5 text-sm font-semibold text-slate-700"><span class="sr-only">HTML body</span><textarea ref="htmlInput" v-model="draft.htmlBody" class="field-control min-h-[380px] resize-y py-3 font-mono text-xs leading-5" spellcheck="false" @focus="lastFocused = 'htmlBody'" /></label>
            </div>
            <label class="grid gap-1.5 text-sm font-semibold text-slate-700">
              <span class="flex flex-wrap items-center justify-between gap-2">Plain-text body<button v-if="visualAvailable" type="button" class="secondary-button !py-1 !text-xs" @click="fillTextFromVisual"><i class="pi pi-sparkles" />Fill from visual editor</button></span>
              <textarea ref="textInput" v-model="draft.textBody" class="field-control min-h-[160px] resize-y py-3 font-mono text-xs leading-5" spellcheck="false" @focus="lastFocused = 'textBody'" /><span class="text-xs font-normal leading-5 text-slate-500">Shown by mail clients that block HTML. Leave empty to send HTML only.</span></label>
          </div>
        </section>
      </div>

      <aside class="space-y-4 xl:sticky xl:top-8">
        <div class="panel p-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div><div class="panel-heading">Preview</div><div class="mt-1 text-xs text-slate-500">Rendered with sample values{{ previewLoading ? ' · updating…' : '' }}</div></div>
            <div class="flex rounded-xl bg-slate-100 p-1">
              <button v-for="mode in (['html', 'text'] as PreviewMode[])" :key="mode" type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold uppercase" :class="previewMode === mode ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" @click="previewMode = mode">{{ mode }}</button>
            </div>
          </div>
          <div v-if="previewError" class="mt-3 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700">{{ previewError }}</div>
          <div class="mt-4 rounded-xl border border-slate-200 bg-slate-50 px-3 py-2 text-sm"><span class="text-xs font-semibold uppercase tracking-wide text-slate-500">Subject</span><div class="mt-0.5 font-semibold text-slate-900">{{ preview?.subject || '—' }}</div></div>
          <iframe v-if="previewMode === 'html'" title="Email preview" class="mt-3 h-[560px] w-full rounded-xl border border-slate-200 bg-white" sandbox="" :srcdoc="previewDocument" />
          <pre v-else class="mt-3 h-[560px] overflow-auto whitespace-pre-wrap rounded-xl border border-slate-200 bg-white p-4 font-mono text-xs leading-5 text-slate-800">{{ preview?.textBody || 'No plain-text body.' }}</pre>
        </div>

        <div class="panel p-4">
          <div class="panel-heading">Send a test</div>
          <p class="mt-1 text-xs leading-5 text-slate-500">Sends the current draft with sample values through {{ delivery?.provider ?? 'the configured provider' }}. Unsaved edits are included.</p>
          <div class="mt-3 flex gap-2">
            <input v-model="testEmail" type="email" class="field-control min-w-0 flex-1" placeholder="you@example.com" @keyup.enter="sendTest" />
            <button class="secondary-button shrink-0" :disabled="!canSendTest || sendingTest" @click="sendTest"><i class="pi pi-send" />{{ sendingTest ? 'Sending…' : 'Send' }}</button>
          </div>
          <p v-if="delivery && !delivery.configured" class="mt-2 text-xs text-amber-700">Test sends are unavailable until the email provider is configured.</p>
        </div>
      </aside>
    </div>

    <section v-if="!loading" class="mt-5">
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div><h2 class="panel-heading">Recent deliveries</h2><p class="mt-1 text-xs text-slate-500">Emails queued by the backend and their delivery status.</p></div>
        <div class="flex items-center gap-2">
          <div class="flex rounded-xl bg-slate-100 p-1">
            <button type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold" :class="messagesFilter === 'selected' ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" @click="messagesFilter = 'selected'">This template</button>
            <button type="button" class="rounded-lg px-3 py-1.5 text-xs font-semibold" :class="messagesFilter === 'all' ? 'bg-white text-slate-950 shadow-sm' : 'text-slate-500'" @click="messagesFilter = 'all'">All</button>
          </div>
          <button class="icon-button" type="button" aria-label="Refresh deliveries" :disabled="messagesLoading" @click="loadMessages"><i class="pi pi-refresh" :class="{ 'animate-spin': messagesLoading }" /></button>
        </div>
      </div>
      <div v-if="messages.length" class="mt-3 table-shell overflow-x-auto">
        <table class="data-table min-w-[900px]">
          <thead><tr><th>Queued</th><th>Template</th><th>Recipient</th><th>Subject</th><th>Status</th><th>Sent</th><th>Error</th></tr></thead>
          <tbody>
            <tr v-for="row in messages" :key="row.id">
              <td class="whitespace-nowrap">{{ formatDateTime(row.createdAt) }}</td>
              <td><span class="font-mono text-xs">{{ row.templateKey }}</span></td>
              <td>{{ row.toEmail }}</td>
              <td class="max-w-[320px] truncate" :title="row.subject">{{ row.subject }}</td>
              <td><StatusPill :label="row.status" :tone="statusTone(row.status)" /><span v-if="row.attemptCount > 1" class="ml-2 text-xs text-slate-500">×{{ row.attemptCount }}</span></td>
              <td class="whitespace-nowrap">{{ row.sentAt ? formatDateTime(row.sentAt) : '—' }}</td>
              <td class="max-w-[280px] truncate text-xs text-red-700" :title="row.errorMessage ?? ''">{{ row.errorMessage ?? '' }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div v-else class="empty-state mt-3"><i class="pi pi-inbox text-2xl text-slate-400" /><p class="mt-3 text-sm font-semibold text-slate-700">No emails yet</p><p class="mt-1 text-xs text-slate-500">Deliveries appear here after a customer requests a code or you send a test.</p></div>
    </section>
  </AppShell>
</template>

<style scoped>
.email-visual-editor :deep(.p-editor-toolbar) {
  border-radius: 12px 12px 0 0;
  border-color: #e2e8f0;
  background: #f8fafc;
}
.email-visual-editor :deep(.p-editor-content) {
  border-radius: 0 0 12px 12px;
  border-color: #e2e8f0;
}
.email-visual-editor :deep(.ql-editor) {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  font-size: 15px;
  line-height: 1.55;
  color: #334155;
}
.email-visual-editor :deep(.ql-editor h1) {
  font-size: 30px;
  font-weight: 700;
  letter-spacing: 8px;
  color: #0f172a;
}
.email-visual-editor :deep(.ql-editor h2) {
  font-size: 18px;
  font-weight: 700;
  color: #0f172a;
}
</style>
