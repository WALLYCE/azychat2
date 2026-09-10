<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationHistoryAPI from 'dashboard/api/conversationHistory';

const props = defineProps({
  agent: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['openTranscript']);

const { t } = useI18n();

const PAGE_SIZE = 10;

const dialogRef = ref(null);
const conversations = ref([]);
const page = ref(1);
const totalCount = ref(0);
const visibleCount = ref(PAGE_SIZE);
const isLoading = ref(false);
const errorMessage = ref('');

const filters = ref({
  displayId: '',
  status: 'all',
  openedAfter: '',
  openedBefore: '',
  resolvedAfter: '',
  resolvedBefore: '',
});

const statusOptions = computed(() => [
  { value: 'all', label: t('CONVERSATION_HISTORY.STATUS.ALL') },
  { value: 'open', label: t('CONVERSATION_HISTORY.STATUS.OPEN') },
  { value: 'resolved', label: t('CONVERSATION_HISTORY.STATUS.RESOLVED') },
  { value: 'pending', label: t('CONVERSATION_HISTORY.STATUS.PENDING') },
  { value: 'snoozed', label: t('CONVERSATION_HISTORY.STATUS.SNOOZED') },
]);

const title = computed(() =>
  props.agent
    ? t('CONVERSATION_HISTORY.MODAL.TITLE', { name: props.agent.name })
    : ''
);

const visibleConversations = computed(() =>
  conversations.value.slice(0, visibleCount.value)
);

const canLoadMore = computed(
  () =>
    visibleCount.value < conversations.value.length ||
    conversations.value.length < totalCount.value
);

const formatDate = epoch =>
  epoch ? format(fromUnixTime(epoch), 'dd MMM yyyy, HH:mm') : null;

const contactName = conversation => conversation?.meta?.sender?.name || '—';

const fetchHistory = async ({ append = false } = {}) => {
  if (!props.agent) return;
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ConversationHistoryAPI.getAgentHistory({
      assigneeId: props.agent.id,
      filters: filters.value,
      page: page.value,
    });
    const payload = data.payload || [];
    conversations.value = append
      ? [...conversations.value, ...payload]
      : payload;
    totalCount.value = data.meta?.all_count ?? conversations.value.length;
  } catch (error) {
    errorMessage.value = t('CONVERSATION_HISTORY.ERROR');
  } finally {
    isLoading.value = false;
  }
};

const resetState = () => {
  page.value = 1;
  visibleCount.value = PAGE_SIZE;
  conversations.value = [];
  totalCount.value = 0;
  errorMessage.value = '';
};

const resetFilters = () => {
  filters.value = {
    displayId: '',
    status: 'all',
    openedAfter: '',
    openedBefore: '',
    resolvedAfter: '',
    resolvedBefore: '',
  };
};

const resetAndFetch = () => {
  resetState();
  fetchHistory();
};

const applyFilters = () => resetAndFetch();

const clearFilters = () => {
  resetFilters();
  resetAndFetch();
};

const onDialogClose = () => {
  resetFilters();
  resetState();
};

const loadMore = async () => {
  if (visibleCount.value < conversations.value.length) {
    visibleCount.value += PAGE_SIZE;
    return;
  }
  page.value += 1;
  await fetchHistory({ append: true });
  visibleCount.value += PAGE_SIZE;
};

const onRowClick = conversation => {
  emit('openTranscript', conversation);
};

const open = () => {
  resetAndFetch();
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="title"
    width="3xl"
    :show-confirm-button="false"
    :cancel-button-label="t('CONVERSATION_HISTORY.MODAL.FILTERS.CLEAR')"
    overflow-y-auto
    @close="onDialogClose"
  >
    <div class="flex flex-col gap-4">
      <!-- Filters -->
      <div class="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.CONVERSATION_ID') }}
          <input
            v-model="filters.displayId"
            type="number"
            min="1"
            :placeholder="
              t('CONVERSATION_HISTORY.MODAL.FILTERS.CONVERSATION_ID_PLACEHOLDER')
            "
            class="px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.STATUS') }}
          <Select v-model="filters.status" :options="statusOptions" class="!w-full" />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.OPENED_FROM') }}
          <input
            v-model="filters.openedAfter"
            type="date"
            class="px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.OPENED_TO') }}
          <input
            v-model="filters.openedBefore"
            type="date"
            class="px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.RESOLVED_FROM') }}
          <input
            v-model="filters.resolvedAfter"
            type="date"
            class="px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
          />
        </label>
        <label class="flex flex-col gap-1 text-xs text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.MODAL.FILTERS.RESOLVED_TO') }}
          <input
            v-model="filters.resolvedBefore"
            type="date"
            class="px-3 py-2 text-sm border rounded-lg bg-n-background border-n-weak text-n-slate-12"
          />
        </label>
      </div>

      <div class="flex items-center gap-2">
        <Button
          :label="t('CONVERSATION_HISTORY.MODAL.FILTERS.APPLY')"
          size="sm"
          color="blue"
          :is-loading="isLoading"
          @click="applyFilters"
        />
        <Button
          :label="t('CONVERSATION_HISTORY.MODAL.FILTERS.CLEAR')"
          size="sm"
          variant="ghost"
          color="slate"
          @click="clearFilters"
        />
      </div>

      <p class="text-xs text-n-slate-11">
        {{ t('CONVERSATION_HISTORY.MODAL.SHOWING_LATEST', { count: PAGE_SIZE }) }}
      </p>

      <p v-if="errorMessage" class="text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>

      <!-- Table -->
      <div class="overflow-x-auto border rounded-lg border-n-weak">
        <table class="w-full text-sm">
          <thead class="text-xs text-left text-n-slate-11 bg-n-solid-1">
            <tr>
              <th class="px-3 py-2 font-medium">
                {{ t('CONVERSATION_HISTORY.MODAL.TABLE.ID') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CONVERSATION_HISTORY.MODAL.TABLE.CONTACT') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CONVERSATION_HISTORY.MODAL.TABLE.STATUS') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CONVERSATION_HISTORY.MODAL.TABLE.OPENED_AT') }}
              </th>
              <th class="px-3 py-2 font-medium">
                {{ t('CONVERSATION_HISTORY.MODAL.TABLE.RESOLVED_AT') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="conversation in visibleConversations"
              :key="conversation.id"
              class="border-t cursor-pointer border-n-weak hover:bg-n-alpha-1"
              @click="onRowClick(conversation)"
            >
              <td class="px-3 py-2 font-medium text-n-slate-12">
                #{{ conversation.id }}
              </td>
              <td class="px-3 py-2 text-n-slate-12">
                {{ contactName(conversation) }}
              </td>
              <td class="px-3 py-2 capitalize text-n-slate-11">
                {{ conversation.status }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{ formatDate(conversation.created_at) }}
              </td>
              <td class="px-3 py-2 text-n-slate-11">
                {{
                  formatDate(conversation.resolved_at) ||
                  t('CONVERSATION_HISTORY.MODAL.TABLE.NOT_RESOLVED')
                }}
              </td>
            </tr>
            <tr v-if="!isLoading && !visibleConversations.length">
              <td colspan="5" class="px-3 py-8 text-center text-n-slate-11">
                {{ t('CONVERSATION_HISTORY.MODAL.EMPTY') }}
              </td>
            </tr>
            <tr v-if="isLoading">
              <td colspan="5" class="px-3 py-8 text-center text-n-slate-11">
                {{ t('CONVERSATION_HISTORY.MODAL.LOADING') }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div v-if="canLoadMore" class="flex justify-center">
        <Button
          :label="t('CONVERSATION_HISTORY.MODAL.LOAD_MORE')"
          size="sm"
          variant="outline"
          color="slate"
          :is-loading="isLoading"
          @click="loadMore"
        />
      </div>
    </div>
  </Dialog>
</template>
