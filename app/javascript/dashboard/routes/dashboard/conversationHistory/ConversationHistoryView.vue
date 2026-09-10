<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ConversationHistoryModal from './components/ConversationHistoryModal.vue';
import ReadOnlyConversationModal from './components/ReadOnlyConversationModal.vue';

const { t } = useI18n();
const store = useStore();

const agents = useMapGetter('agents/getVerifiedAgents');
const teams = useMapGetter('teams/getTeams');
const getTeamMembers = useMapGetter('teamMembers/getTeamMembers');

const scope = ref('team');
const selectedTeamId = ref('');
const selectedAgentId = ref('');

const historyModalRef = ref(null);
const transcriptModalRef = ref(null);
const activeAgent = ref(null);
const activeConversation = ref(null);

const scopeOptions = computed(() => [
  { value: 'team', label: t('CONVERSATION_HISTORY.SCOPE.TEAM') },
  { value: 'agent', label: t('CONVERSATION_HISTORY.SCOPE.AGENT') },
]);

const teamOptions = computed(() =>
  teams.value.map(team => ({ value: team.id, label: team.name }))
);

const agentOptions = computed(() =>
  agents.value.map(agent => ({ value: agent.id, label: agent.name }))
);

const displayedMembers = computed(() => {
  if (scope.value === 'team') {
    if (!selectedTeamId.value) return [];
    return getTeamMembers.value(selectedTeamId.value) || [];
  }
  if (!selectedAgentId.value) return [];
  const agent = agents.value.find(a => a.id === selectedAgentId.value);
  return agent ? [agent] : [];
});

const hasSelection = computed(
  () =>
    (scope.value === 'team' && !!selectedTeamId.value) ||
    (scope.value === 'agent' && !!selectedAgentId.value)
);

const emptyMessage = computed(() => {
  if (!hasSelection.value) return null;
  if (displayedMembers.value.length) return null;
  return scope.value === 'team'
    ? t('CONVERSATION_HISTORY.EMPTY.NO_MEMBERS')
    : t('CONVERSATION_HISTORY.EMPTY.NO_AGENT');
});

watch(selectedTeamId, teamId => {
  if (teamId) {
    store.dispatch('teamMembers/get', { teamId });
  }
});

watch(scope, () => {
  selectedTeamId.value = '';
  selectedAgentId.value = '';
});

const openHistory = agent => {
  activeAgent.value = agent;
  historyModalRef.value?.open(agent);
};

const openTranscript = conversation => {
  activeConversation.value = conversation;
  transcriptModalRef.value?.open(conversation);
};

onMounted(() => {
  store.dispatch('agents/get');
  store.dispatch('teams/get');
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <header class="px-6 pt-6 pb-4">
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CONVERSATION_HISTORY.HEADER_TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11">
        {{ t('CONVERSATION_HISTORY.HEADER_DESCRIPTION') }}
      </p>
    </header>

    <div class="flex flex-wrap items-end gap-3 px-6 pb-6">
      <Select v-model="scope" :options="scopeOptions" class="!w-40" />
      <Select
        v-if="scope === 'team'"
        v-model="selectedTeamId"
        :options="teamOptions"
        :placeholder="t('CONVERSATION_HISTORY.SELECT_TEAM_PLACEHOLDER')"
        class="!w-64"
      />
      <Select
        v-else
        v-model="selectedAgentId"
        :options="agentOptions"
        :placeholder="t('CONVERSATION_HISTORY.SELECT_AGENT_PLACEHOLDER')"
        class="!w-64"
      />
    </div>

    <div class="flex-1 px-6 pb-10">
      <div
        v-if="!hasSelection"
        class="flex flex-col items-center justify-center gap-2 py-24 text-center"
      >
        <span class="i-lucide-history size-8 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CONVERSATION_HISTORY.EMPTY.NO_SELECTION_TITLE') }}
        </p>
        <p class="max-w-sm text-sm text-n-slate-11">
          {{ t('CONVERSATION_HISTORY.EMPTY.NO_SELECTION_SUBTITLE') }}
        </p>
      </div>

      <p v-else-if="emptyMessage" class="py-24 text-sm text-center text-n-slate-11">
        {{ emptyMessage }}
      </p>

      <div
        v-else
        class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <div
          v-for="member in displayedMembers"
          :key="member.id"
          class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        >
          <div class="flex items-center gap-3">
            <Avatar
              :name="member.name"
              :src="member.thumbnail"
              :size="40"
              rounded-full
            />
            <div class="min-w-0">
              <p class="text-sm font-medium truncate text-n-slate-12">
                {{ member.name }}
              </p>
              <p class="text-xs truncate text-n-slate-11">
                {{ member.email }}
              </p>
            </div>
          </div>
          <Button
            :label="t('CONVERSATION_HISTORY.CARD.VIEW_HISTORY')"
            variant="outline"
            color="slate"
            size="sm"
            class="w-full"
            @click="openHistory(member)"
          />
        </div>
      </div>
    </div>

    <ConversationHistoryModal
      ref="historyModalRef"
      :agent="activeAgent"
      @open-transcript="openTranscript"
    />
    <ReadOnlyConversationModal
      ref="transcriptModalRef"
      :conversation="activeConversation"
    />
  </div>
</template>
