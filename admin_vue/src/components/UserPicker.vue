<script setup lang="ts">
// Searchable user picker: type a name, email or #id. Without `options` it searches the platform
// (first 50 matches, debounced); with `options` it filters that list locally (private programmes).
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import type { UserOption } from '@/lib/referrals';
import { referralsApi } from '@/lib/referralsApi';
import { debounce, filterUsers, userLabel } from '@/lib/userPicker';

const props = withDefaults(defineProps<{
  modelValue: number | null;
  options?: UserOption[] | null;
  /** Label to show for the current value when it is not in the loaded list (e.g. an existing partner). */
  selectedLabel?: string;
  placeholder?: string;
  required?: boolean;
  disabled?: boolean;
  id?: string;
}>(), { options: null, selectedLabel: '', placeholder: 'Type a name or email', required: false, disabled: false, id: undefined });
const emit = defineEmits<{ 'update:modelValue': [value: number | null]; select: [user: UserOption | null] }>();

const query = ref('');
const open = ref(false);
const loading = ref(false);
const error = ref('');
const remote = ref<UserOption[]>([]);
const hasMore = ref(false);
const active = ref(0);
const chosen = ref<UserOption | null>(null);
const listId = `user-picker-list-${Math.random().toString(36).slice(2, 8)}`;

const serverMode = computed(() => props.options === null || props.options === undefined);
const matches = computed(() => serverMode.value ? remote.value : filterUsers(props.options ?? [], query.value).slice(0, 50));
const currentLabel = computed(() => {
  if (props.modelValue === null) return '';
  if (chosen.value?.Id === props.modelValue) return userLabel(chosen.value);
  const known = [...(props.options ?? []), ...remote.value].find(u => u.Id === props.modelValue);
  return known ? userLabel(known) : props.selectedLabel || `#${props.modelValue}`;
});

async function search(text: string) {
  if (!serverMode.value) return;
  loading.value = true; error.value = '';
  try {
    const result = await referralsApi.options(text);
    remote.value = result.Users;
    hasMore.value = result.HasMoreUsers;
    active.value = 0;
  } catch (caught) {
    error.value = caught instanceof Error ? caught.message : 'Search failed.';
  } finally {
    loading.value = false;
  }
}
const debounced = debounce((text: string) => { void search(text); }, 250);

function onFocus() {
  open.value = true;
  if (serverMode.value && !remote.value.length && !loading.value) void search(query.value);
}
function onInput(event: Event) {
  query.value = (event.target as HTMLInputElement).value;
  open.value = true;
  active.value = 0;
  if (serverMode.value) debounced.call(query.value);
}
function choose(user: UserOption) {
  chosen.value = user;
  query.value = '';
  open.value = false;
  emit('update:modelValue', user.Id);
  emit('select', user);
}
function clear() {
  chosen.value = null;
  query.value = '';
  emit('update:modelValue', null);
  emit('select', null);
}
function onKeydown(event: KeyboardEvent) {
  if (!open.value && ['ArrowDown', 'ArrowUp'].includes(event.key)) { open.value = true; return; }
  if (event.key === 'ArrowDown') { event.preventDefault(); active.value = Math.min(active.value + 1, matches.value.length - 1); }
  else if (event.key === 'ArrowUp') { event.preventDefault(); active.value = Math.max(active.value - 1, 0); }
  else if (event.key === 'Enter') { if (open.value && matches.value[active.value]) { event.preventDefault(); choose(matches.value[active.value]); } }
  else if (event.key === 'Escape') { open.value = false; query.value = ''; }
}
function onBlur() { setTimeout(() => { open.value = false; query.value = ''; }, 120); }

watch(() => props.modelValue, value => { if (value === null) chosen.value = null; });
onBeforeUnmount(() => debounced.cancel());
</script>

<template>
  <div class="relative">
    <div class="field-control flex items-center gap-2 !px-3" :class="disabled ? 'bg-slate-50' : ''">
      <i class="pi pi-search text-xs text-slate-400" aria-hidden="true" />
      <input
        :id="id"
        type="text"
        role="combobox"
        class="min-w-0 flex-1 bg-transparent outline-none placeholder:text-slate-400"
        :value="open ? query : currentLabel"
        :placeholder="modelValue === null ? placeholder : currentLabel"
        :aria-expanded="open"
        :aria-controls="listId"
        :aria-activedescendant="open && matches[active] ? `${listId}-${matches[active].Id}` : undefined"
        :required="required && modelValue === null"
        :disabled="disabled"
        autocomplete="off"
        @focus="onFocus"
        @input="onInput"
        @keydown="onKeydown"
        @blur="onBlur"
      />
      <button v-if="modelValue !== null && !disabled" type="button" class="grid size-6 place-items-center rounded-md text-slate-400 hover:bg-slate-100 hover:text-slate-700" aria-label="Clear selected user" @mousedown.prevent @click="clear"><i class="pi pi-times text-xs" aria-hidden="true" /></button>
    </div>
    <ul v-if="open" :id="listId" role="listbox" class="absolute z-30 mt-1 max-h-72 w-full overflow-auto rounded-xl border border-slate-200 bg-white py-1 shadow-lg">
      <li v-if="loading" class="px-3 py-2 text-sm text-slate-500">Searching…</li>
      <li v-else-if="error" class="px-3 py-2 text-sm text-red-700">{{ error }}</li>
      <li v-else-if="!matches.length" class="px-3 py-2 text-sm text-slate-500">{{ query ? 'No user matches.' : 'Type to search users.' }}</li>
      <li
        v-for="(user, index) in matches"
        :id="`${listId}-${user.Id}`"
        :key="user.Id"
        role="option"
        :aria-selected="user.Id === modelValue"
        class="cursor-pointer px-3 py-2 text-sm"
        :class="index === active ? 'bg-blue-50 text-blue-800' : 'text-slate-800 hover:bg-slate-50'"
        @mousedown.prevent
        @click="choose(user)"
        @mousemove="active = index"
      >
        <span class="font-semibold">{{ user.Name || user.Email }}</span><span v-if="user.Name && user.Email" class="text-slate-500"> · {{ user.Email }}</span><span class="ml-1 text-xs text-slate-400">#{{ user.Id }}</span>
      </li>
      <li v-if="!loading && !error && hasMore && serverMode" class="border-t border-slate-100 px-3 py-2 text-xs text-slate-500">Showing the first 50 matches. Keep typing to narrow the search.</li>
    </ul>
  </div>
</template>
