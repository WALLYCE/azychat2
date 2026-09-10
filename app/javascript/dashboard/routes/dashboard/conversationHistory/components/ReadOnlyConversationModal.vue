<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationHistoryAPI from 'dashboard/api/conversationHistory';
import ReadOnlyMessage from './ReadOnlyMessage.vue';

const props = defineProps({
  conversation: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const dialogRef = ref(null);
const messages = ref([]);
const isLoading = ref(false);
const hasMoreBefore = ref(false);
const errorMessage = ref('');

const title = computed(() =>
  props.conversation
    ? t('CONVERSATION_HISTORY.TRANSCRIPT.TITLE', { id: props.conversation.id })
    : ''
);

const sortedMessages = computed(() =>
  [...messages.value].sort((a, b) => {
    if (a.created_at !== b.created_at) return a.created_at - b.created_at;
    return a.id - b.id;
  })
);

const fetchMessages = async ({ before } = {}) => {
  if (!props.conversation) return;
  isLoading.value = true;
  errorMessage.value = '';
  try {
    const { data } = await ConversationHistoryAPI.getMessages({
      conversationId: props.conversation.id,
      before,
    });
    const payload = data.payload || [];
    if (before) {
      const existingIds = new Set(messages.value.map(m => m.id));
      messages.value = [
        ...payload.filter(m => !existingIds.has(m.id)),
        ...messages.value,
      ];
    } else {
      messages.value = payload;
    }
    hasMoreBefore.value = payload.length >= 20;
  } catch (error) {
    errorMessage.value = t('CONVERSATION_HISTORY.ERROR');
  } finally {
    isLoading.value = false;
  }
};

const loadPrevious = () => {
  const oldest = sortedMessages.value[0];
  if (oldest) fetchMessages({ before: oldest.id });
};

const open = () => {
  messages.value = [];
  hasMoreBefore.value = false;
  fetchMessages();
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
    overflow-y-auto
  >
    <div class="flex flex-col gap-3">
      <div
        class="flex items-center gap-2 px-3 py-2 text-xs rounded-lg bg-n-amber-3 text-n-amber-12"
      >
        <span class="i-lucide-eye size-4" />
        {{ t('CONVERSATION_HISTORY.TRANSCRIPT.READ_ONLY_NOTICE') }}
      </div>

      <p v-if="errorMessage" class="text-sm text-n-ruby-11">
        {{ errorMessage }}
      </p>

      <div class="max-h-[60vh] overflow-y-auto pr-1">
        <div v-if="hasMoreBefore" class="flex justify-center my-2">
          <Button
            :label="t('CONVERSATION_HISTORY.TRANSCRIPT.LOAD_PREVIOUS')"
            size="sm"
            variant="ghost"
            color="slate"
            :is-loading="isLoading"
            @click="loadPrevious"
          />
        </div>

        <p
          v-if="!isLoading && !sortedMessages.length"
          class="py-10 text-sm text-center text-n-slate-11"
        >
          {{ t('CONVERSATION_HISTORY.TRANSCRIPT.EMPTY') }}
        </p>

        <ReadOnlyMessage
          v-for="message in sortedMessages"
          :key="message.id"
          :message="message"
        />

        <p
          v-if="isLoading"
          class="py-4 text-xs text-center text-n-slate-10"
        >
          {{ t('CONVERSATION_HISTORY.MODAL.LOADING') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
