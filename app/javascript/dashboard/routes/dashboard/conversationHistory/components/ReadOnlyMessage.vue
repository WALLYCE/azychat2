<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { format, fromUnixTime } from 'date-fns';

const props = defineProps({
  message: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// 0: incoming, 1: outgoing, 2: activity, 3: template
const isActivity = computed(() => props.message.message_type === 2);
const isIncoming = computed(() => props.message.message_type === 0);
const isPrivate = computed(() => !!props.message.private);

const alignmentClass = computed(() =>
  isIncoming.value ? 'items-start' : 'items-end'
);

const bubbleClass = computed(() => {
  if (isPrivate.value) return 'bg-n-amber-3 text-n-amber-12';
  return isIncoming.value
    ? 'bg-n-solid-2 text-n-slate-12'
    : 'bg-n-blue-9 text-white';
});

const senderName = computed(() => props.message.sender?.name || '');

const timeStamp = computed(() =>
  props.message.created_at
    ? format(fromUnixTime(props.message.created_at), 'dd MMM yyyy, HH:mm')
    : ''
);

const attachments = computed(() => props.message.attachments || []);

const isImage = attachment => attachment.file_type === 'image';
</script>

<template>
  <div v-if="isActivity" class="my-2 text-center">
    <span
      class="inline-block px-3 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-11"
    >
      {{ message.content }}
    </span>
  </div>

  <div v-else class="flex flex-col gap-1 my-2" :class="alignmentClass">
    <span v-if="senderName" class="text-xs text-n-slate-10">
      {{ senderName }}
    </span>
    <div
      class="max-w-[75%] rounded-xl px-3 py-2 text-sm whitespace-pre-wrap break-words"
      :class="bubbleClass"
    >
      <span
        v-if="isPrivate"
        class="block mb-1 text-[10px] font-semibold uppercase tracking-wide opacity-70"
      >
        {{ t('CONVERSATION_HISTORY.TRANSCRIPT.PRIVATE_NOTE') }}
      </span>
      <p v-if="message.content" class="m-0">{{ message.content }}</p>

      <div v-if="attachments.length" class="flex flex-col gap-2 mt-2">
        <template v-for="attachment in attachments" :key="attachment.id">
          <img
            v-if="isImage(attachment)"
            :src="attachment.data_url"
            :alt="attachment.file_type"
            class="max-w-full rounded-lg"
          />
          <a
            v-else
            :href="attachment.data_url"
            target="_blank"
            rel="noopener noreferrer"
            class="text-xs underline break-all"
          >
            {{ attachment.data_url }}
          </a>
        </template>
      </div>
    </div>
    <span class="text-[10px] text-n-slate-9">{{ timeStamp }}</span>
  </div>
</template>
