<script setup>
// [TODO] This componet is too big and bulky to be in the same file, we can consider splitting this into multiple
// composables and components, useVirtualChatList, useChatlistFilters
import {
  ref,
  unref,
  provide,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  reactive,
  defineEmits,
} from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import {
  useMapGetter,
  useFunctionGetter,
} from 'dashboard/composables/store.js';

import { Virtualizer } from 'virtua/vue';
import ChatListHeader from './ChatListHeader.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ConversationFilter from 'next/filter/ConversationFilter.vue';
import SaveCustomView from 'next/filter/SaveCustomView.vue';
import ChatTypeTabs from './widgets/ChatTypeTabs.vue';
import ConversationItem from './ConversationItem.vue';
import DeleteCustomViews from 'dashboard/routes/dashboard/customviews/DeleteCustomViews.vue';
import ConversationBulkActions from './widgets/conversation/conversationBulkActions/Index.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import IntersectionObserver from 'dashboard/components/IntersectionObserver.vue';
import ConversationResolveAttributesModal from 'dashboard/components-next/ConversationWorkflow/ConversationResolveAttributesModal.vue';

import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAlert } from 'dashboard/composables';
import { useChatListKeyboardEvents } from 'dashboard/composables/chatlist/useChatListKeyboardEvents';
import { useBulkActions } from 'dashboard/composables/chatlist/useBulkActions';
import { useFilter } from 'shared/composables/useFilter';
import { useTrack } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import {
  useCamelCase,
  useSnakeCase,
} from 'dashboard/composables/useTransformKeys';
import { useEmitter } from 'dashboard/composables/emitter';
import { useConversationRequiredAttributes } from 'dashboard/composables/useConversationRequiredAttributes';
import { emitter } from 'shared/helpers/mitt';

import wootConstants from 'dashboard/constants/globals';
import advancedFilterOptions from './widgets/conversation/advancedFilterItems';
import filterQueryGenerator from '../helper/filterQueryGenerator.js';
import languages from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import countries from 'shared/constants/countries';
import { generateValuesForEditCustomViews } from 'dashboard/helper/customViewsHelper';
import { conversationListPageURL } from '../helper/URLHelper';
import {
  isOnMentionsView,
  isOnUnattendedView,
} from '../store/modules/conversations/helpers/actionHelpers';
import {
  getUserPermissions,
  filterItemsByPermission,
} from 'dashboard/helper/permissionsHelper.js';
import { matchesFilters } from '../store/modules/conversations/helpers/filterHelpers';
import { CONVERSATION_EVENTS } from '../helper/AnalyticsHelper/events';
import { ASSIGNEE_TYPE_TAB_PERMISSIONS } from 'dashboard/constants/permissions.js';

const TAB_PAGE_SIZE = 25;
const DEBUG_ALL_CONVERSATIONS = true;

function debugLog(...args) {
  if (DEBUG_ALL_CONVERSATIONS) {
    console.log('[ConversationList DEBUG]', ...args);
  }
}

const props = defineProps({
  conversationInbox: {
    type: [String, Number],
    default: 0,
  },
  teamId: {
    type: [String, Number],
    default: 0,
  },
  label: {
    type: String,
    default: '',
  },
  conversationType: {
    type: String,
    default: '',
  },
  foldersId: {
    type: [String, Number],
    default: 0,
  },
  showConversationList: {
    default: true,
    type: Boolean,
  },
  isOnExpandedLayout: {
    default: false,
    type: Boolean,
  },
});

const emit = defineEmits(['conversationLoad']);

const { uiSettings } = useUISettings();
const { t } = useI18n();
const router = useRouter();
const route = useRoute();
const store = useStore();

const resolveAttributesModalRef = ref(null);
const conversationListRef = ref(null);
const virtualListRef = ref(null);

let unsubscribeSocketBridge = null;

provide('contextMenuElementTarget', virtualListRef);

const activeAssigneeTab = ref(wootConstants.ASSIGNEE_TYPE.ME);
const activeStatus = ref(wootConstants.STATUS_TYPE.OPEN);
const activeSortBy = ref(wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC);
const showAdvancedFilters = ref(false);
const chatsOnView = ref([]);
const foldersQuery = ref({});
const showAddFoldersModal = ref(false);
const showDeleteFoldersModal = ref(false);
const isContextMenuOpen = ref(false);
const appliedFilter = ref([]);

const advancedFilterTypes = ref(
  advancedFilterOptions.map(filter => ({
    ...filter,
    attributeName: t(`FILTER.ATTRIBUTES.${filter.attributeI18nKey}`),
  }))
);

const tabState = reactive({
  me: {
    items: [],
    page: 0,
    loading: false,
    hasEndReached: false,
    initialized: false,
  },
  unassigned: {
    items: [],
    page: 0,
    loading: false,
    hasEndReached: false,
    initialized: false,
  },
  all: {
    items: [],
    page: 0,
    loading: false,
    hasEndReached: false,
    initialized: false,
  },
});

const currentUser = useMapGetter('getCurrentUser');
const chatLists = useMapGetter('getFilteredConversations');
const mineChatsList = useMapGetter('getMineChats');
const allChatList = useMapGetter('getAllStatusChats');
const unAssignedChatsList = useMapGetter('getUnAssignedChats');
const chatListLoading = useMapGetter('getChatListLoadingStatus');
const activeInbox = useMapGetter('getSelectedInbox');
const conversationStats = useMapGetter('conversationStats/getStats');
const appliedFilters = useMapGetter('getAppliedConversationFiltersV2');
const folders = useMapGetter('customViews/getConversationCustomViews');
const agentList = useMapGetter('agents/getAgents');
const teamsList = useMapGetter('teams/getTeams');
const inboxesList = useMapGetter('inboxes/getInboxes');
const campaigns = useMapGetter('campaigns/getAllCampaigns');
const labels = useMapGetter('labels/getLabels');
const currentAccountId = useMapGetter('getCurrentAccountId');
const getTeamFn = useMapGetter('teams/getTeam');
const getConversationById = useMapGetter('getConversationById');

useChatListKeyboardEvents(conversationListRef);

const {
  selectedConversations,
  selectedInboxes,
  selectConversation,
  deSelectConversation,
  selectAllConversations,
  resetBulkActions,
  isConversationSelected,
  onAssignAgent,
  onAssignLabels,
  onRemoveLabels,
  onAssignTeamsForBulk,
  onUpdateConversations,
} = useBulkActions();

const {
  initializeStatusAndAssigneeFilterToModal,
  initializeInboxTeamAndLabelFilterToModal,
} = useFilter({
  filteri18nKey: 'FILTER',
  attributeModel: 'conversation_attribute',
});

const { checkMissingAttributes } = useConversationRequiredAttributes();

const hasAppliedFilters = computed(() => {
  return appliedFilters.value.length !== 0;
});

const activeFolder = computed(() => {
  if (props.foldersId) {
    const activeView = folders.value.filter(
      view => view.id === Number(props.foldersId)
    );
    const [firstValue] = activeView;
    return firstValue;
  }
  return undefined;
});

const activeFolderName = computed(() => {
  return activeFolder.value?.name;
});

const hasActiveFolders = computed(() => {
  return Boolean(activeFolder.value && props.foldersId !== 0);
});

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return hasAppliedFilters.value || hasActiveFolders.value;
});

const currentUserDetails = computed(() => {
  const { id, name } = currentUser.value || {};
  return { id, name };
});

const userPermissions = computed(() => {
  return getUserPermissions(currentUser.value, currentAccountId.value);
});

const isAdmin = computed(() => {
  return currentUser.value?.role === 'administrator';
});

const currentUserId = computed(() => Number(currentUser.value?.id || 0));

function normalizeTeamId(item) {
  if (typeof item === 'number' || typeof item === 'string') {
    return Number(item);
  }

  return Number(item?.id ?? item?.team_id ?? item?.value ?? 0);
}

function normalizeTeamMemberId(member) {
  if (!member) return 0;
  if (typeof member === 'number' || typeof member === 'string') return Number(member);
  return Number(
    member.id || 
    member.user_id || 
    member.agent_id || 
    member.account_user_id || 
    member.user?.id || 0
  );
}

function getTeamMembers(team) {
  return [
    ...(Array.isArray(team?.agents) ? team.agents : []),
    ...(Array.isArray(team?.users) ? team.users : []),
    ...(Array.isArray(team?.members) ? team.members : []),
    ...(Array.isArray(team?.agent_ids) ? team.agent_ids : []),
    ...(Array.isArray(team?.user_ids) ? team.user_ids : []),
  ];
}

const myTeamIds = computed(() => {
  const teams = Array.isArray(teamsList.value) ? teamsList.value : [];
  const userId = currentUserId.value; // Seu ID é 18

  // Filtra a lista global de times para pegar só os que você é membro
  const ids = teams
    .filter(team => {
      // Coleta todos os membros possíveis do objeto do time
      const members = [
        ...(team.agents || []),
        ...(team.users || []),
        ...(team.account_users || []),
        ...(team.members || [])
      ];

      // Verifica se o seu ID (18) está na lista de membros ou no array de IDs
      const isMember = members.some(m => {
        const mId = Number(m?.id || m?.user_id || m?.agent_id || m);
        return mId === userId;
      });

      // Algumas versões usam apenas um array de IDs simples
      const isInIds = (team.agent_ids || []).map(Number).includes(userId);

      return isMember || isInIds;
    })
    .map(team => Number(team.id));

  const result = [...new Set(ids)].filter(Boolean);
  debugLog('myTeamIds:filtrado_por_membro_real', result);
  return result;
});


const allowedTeamIds = computed(() => {
  if (props.teamId) return [Number(props.teamId)];
  return myTeamIds.value;
});

function getConversationAssigneeId(conversation) {
  return Number(conversation.assignee_id ?? conversation.meta?.assignee?.id ?? 0);
}

function getConversationTeamId(conversation) {
  return Number(
    conversation?.team_id ??
      conversation?.meta?.team?.id ??
      conversation?.meta?.additional_attributes?.team_id ??
      0
  );
}

function isConversationInTeamScope(conversation) {
  const conversationTeamId = getConversationTeamId(conversation);

  if (isAdmin.value) {
    return true;
  }

  if (props.teamId) {
    return conversationTeamId === Number(props.teamId);
  }

  return allowedTeamIds.value.includes(conversationTeamId);
}

function isPendingTeamWithoutAgent(conversation) {
  const assigneeId = getConversationAssigneeId(conversation);
  const teamId = getConversationTeamId(conversation);

  return (
    conversation.status === 'pending' &&
    !assigneeId &&
    teamId > 0 &&
    isConversationInTeamScope(conversation)
  );
}

function isPendingFromMyTeams(conversation) {
  const teamId = getConversationTeamId(conversation);

  return (
    conversation.status === 'pending' &&
    allowedTeamIds.value.includes(teamId)
  );
}

function matchesCurrentContext(conversation) {
  if (!conversation) return false;

  if (
    props.conversationInbox &&
    Number(conversation.inbox_id) !== Number(props.conversationInbox)
  ) {
    return false;
  }

  if (props.label) {
    const conversationLabels = Array.isArray(conversation.labels)
      ? conversation.labels
      : [];

    if (!conversationLabels.includes(props.label)) {
      return false;
    }
  }

  if (props.conversationType) {
    if (conversation.conversation_type !== props.conversationType) {
      return false;
    }
  }

  return true;
}

function belongsToTab(conversation, tabKey) {
  if (!matchesCurrentContext(conversation)) return false;

  const assigneeId = getConversationAssigneeId(conversation);

  if (tabKey === 'me') {
    return conversation.status === 'open' && assigneeId === currentUserId.value;
  }

  if (tabKey === 'unassigned') {
    if (props.teamId) {
      return isPendingTeamWithoutAgent(conversation);
    }
    return isPendingFromMyTeams(conversation);
  }

  if (tabKey === 'all') {
    return conversation.status === 'resolved' && assigneeId === currentUserId.value;
  }

  return false;
}

function sortConversationsByLastActivity(items) {
  return [...items].sort((a, b) => {
    const aDate = new Date(a.last_activity_at || a.timestamp || a.created_at || 0);
    const bDate = new Date(b.last_activity_at || b.timestamp || b.created_at || 0);
    return bDate - aDate;
  });
}

function removeConversationFromAllTabs(conversationId) {
  ['me', 'unassigned', 'all'].forEach(tabKey => {
    tabState[tabKey].items = tabState[tabKey].items.filter(
      item => item.id !== conversationId
    );
  });
}

function upsertConversationInTab(tabKey, conversation) {
  const currentItems = tabState[tabKey].items.filter(
    item => item.id !== conversation.id
  );

  tabState[tabKey].items = sortConversationsByLastActivity([
    conversation,
    ...currentItems,
  ]);
}

function syncConversationToTabs(conversation) {
  if (!conversation?.id) return;

  removeConversationFromAllTabs(conversation.id);

  if (belongsToTab(conversation, 'me')) {
    upsertConversationInTab('me', conversation);
  }

  if (belongsToTab(conversation, 'unassigned')) {
    upsertConversationInTab('unassigned', conversation);
  }

  if (belongsToTab(conversation, 'all')) {
    upsertConversationInTab('all', conversation);
  }
}

function syncConversationByPayload(payload) {
  let conversation = payload;

  if (!conversation?.id) {
    const conversationId = payload?.conversationId ?? payload?.id ?? null;
    if (conversationId) {
      conversation = getConversationById.value(conversationId);
    }
  }

  if (!conversation?.id) return;

  debugLog('syncConversationByPayload', {
    id: conversation.id,
    status: conversation.status,
    assigneeId: getConversationAssigneeId(conversation),
    teamId: getConversationTeamId(conversation),
  });

  syncConversationToTabs(conversation);
}

const assigneeTabItems = computed(() => {
  if (isAdmin.value) {
    return filterItemsByPermission(
      ASSIGNEE_TYPE_TAB_PERMISSIONS,
      userPermissions.value,
      item => item.permissions
    ).map(({ key, count: countKey }) => ({
      key,
      name: t(`CHAT_LIST.ASSIGNEE_TYPE_TABS.${key}`),
      count: conversationStats.value[countKey] || 0,
    }));
  }

  return [
    {
      key: 'me',
      name: 'Abertas',
      count: tabState.me.items.length,
    },
    {
      key: 'unassigned',
      name: 'Pendentes',
      count: tabState.unassigned.items.length,
    },
    {
      key: 'all',
      name: 'Finalizadas',
      count: tabState.all.items.length,
    },
  ];
});

const showAssigneeInConversationCard = computed(() => {
  return (
    hasAppliedFiltersOrActiveFolders.value ||
    activeAssigneeTab.value === wootConstants.ASSIGNEE_TYPE.ALL
  );
});

const currentPageFilterKey = computed(() => {
  return hasAppliedFiltersOrActiveFolders.value
    ? 'appliedFilters'
    : activeAssigneeTab.value;
});

const inbox = useFunctionGetter('inboxes/getInbox', activeInbox);
const currentPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  activeAssigneeTab
);
const currentFiltersPage = useFunctionGetter(
  'conversationPage/getCurrentPageFilter',
  currentPageFilterKey
);
const hasCurrentPageEndReached = useFunctionGetter(
  'conversationPage/getHasEndReached',
  currentPageFilterKey
);
const conversationCustomAttributes = useFunctionGetter(
  'attributes/getAttributesByModel',
  'conversation_attribute'
);

const activeAssigneeTabCount = computed(() => {
  const activeItem = assigneeTabItems.value.find(
    item => item.key === activeAssigneeTab.value
  );
  return activeItem?.count || 0;
});

const conversationListPagination = computed(() => {
  const conversationsPerPage = TAB_PAGE_SIZE;
  const hasChatsOnView =
    chatsOnView.value &&
    Array.isArray(chatsOnView.value) &&
    !chatsOnView.value.length;
  const isNoFiltersOrFoldersAndChatListNotEmpty =
    !hasAppliedFiltersOrActiveFolders.value && hasChatsOnView;
  const isUnderPerPage =
    chatsOnView.value.length < conversationsPerPage &&
    activeAssigneeTabCount.value < conversationsPerPage &&
    activeAssigneeTabCount.value > chatsOnView.value.length;

  if (isNoFiltersOrFoldersAndChatListNotEmpty && isUnderPerPage) {
    return 1;
  }

  return currentPage.value + 1;
});

const conversationFilters = computed(() => {
  let mappedAssigneeType = activeAssigneeTab.value;
  let mappedStatus = activeStatus.value;

  if (!isAdmin.value) {
    if (activeAssigneeTab.value === 'me') {
      mappedAssigneeType = 'me';
      mappedStatus = 'open';
    } else if (activeAssigneeTab.value === 'unassigned') {
      mappedAssigneeType = props.teamId ? 'unassigned' : 'all';
      mappedStatus = 'pending';
    } else if (activeAssigneeTab.value === 'all') {
      mappedAssigneeType = 'me';
      mappedStatus = 'resolved';
    }
  }

  return {
    inboxId: props.conversationInbox || undefined,
    assigneeType: mappedAssigneeType,
    status: mappedStatus,
    sortBy: activeSortBy.value,
    page: conversationListPagination.value,
    labels: props.label ? [props.label] : undefined,
    teamId: props.teamId || undefined,
    conversationType: props.conversationType || undefined,
  };
});

const activeTeam = computed(() => {
  if (props.teamId) {
    return getTeamFn.value(props.teamId);
  }
  return {};
});

const pageTitle = computed(() => {
  if (hasAppliedFilters.value) {
    return t('CHAT_LIST.TAB_HEADING');
  }

  if (inbox.value.name) {
    return inbox.value.name;
  }

  if (activeTeam.value.name) {
    return activeTeam.value.name;
  }

  if (props.label) {
    return `#${props.label}`;
  }

  if (props.conversationType === 'mention') {
    return t('CHAT_LIST.MENTION_HEADING');
  }

  if (props.conversationType === 'participating') {
    return t('CONVERSATION_PARTICIPANTS.SIDEBAR_MENU_TITLE');
  }

  if (props.conversationType === 'unattended') {
    return t('CHAT_LIST.UNATTENDED_HEADING');
  }

  if (hasActiveFolders.value) {
    return activeFolder.value.name;
  }

  return t('CHAT_LIST.TAB_HEADING');
});

const isRestrictedAgentView = computed(() => {
  return !isAdmin.value && !hasAppliedFiltersOrActiveFolders.value;
});

const headerStatusLabel = computed(() => {
  if (!isRestrictedAgentView.value) {
    return t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus.value}.TEXT`);
  }

  if (activeAssigneeTab.value === 'me') return 'Abertas';
  if (activeAssigneeTab.value === 'unassigned') return 'Pendentes';
  if (activeAssigneeTab.value === 'all') return 'Finalizadas';

  return t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus.value}.TEXT`);
});

const conversationList = computed(() => {
  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    return tabState[activeAssigneeTab.value]?.items || [];
  }

  let localConversationList = [];

  if (!hasAppliedFiltersOrActiveFolders.value) {
    const filters = conversationFilters.value;

    if (activeAssigneeTab.value === 'me') {
      localConversationList = [...mineChatsList.value(filters)];
    } else if (activeAssigneeTab.value === 'unassigned') {
      localConversationList = [...unAssignedChatsList.value(filters)];
    } else {
      localConversationList = [...allChatList.value(filters)];
    }
  } else {
    localConversationList = [...chatLists.value];
  }

  if (activeFolder.value) {
    const { payload } = activeFolder.value.query;
    localConversationList = localConversationList.filter(conversation => {
      return matchesFilters(conversation, payload);
    });
  }

  return localConversationList;
});

const isCurrentListLoading = computed(() => {
  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    return tabState[activeAssigneeTab.value]?.loading;
  }

  return chatListLoading.value && !conversationList.value.length;
});

const showEndOfListMessage = computed(() => {
  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    const currentTab = tabState[activeAssigneeTab.value];
    return currentTab.items.length && currentTab.hasEndReached && !currentTab.loading;
  }

  return (
    conversationList.value.length &&
    hasCurrentPageEndReached.value &&
    !chatListLoading.value
  );
});

const allConversationsSelected = computed(() => {
  return (
    conversationList.value.length === selectedConversations.value.length &&
    conversationList.value.every(el =>
      selectedConversations.value.includes(el.id)
    )
  );
});

const uniqueInboxes = computed(() => {
  return [...new Set(selectedInboxes.value)];
});

function resetTabState(tabKey = null) {
  const resetOne = key => {
    tabState[key].items = [];
    tabState[key].page = 0;
    tabState[key].loading = false;
    tabState[key].hasEndReached = false;
    tabState[key].initialized = false;
  };

  if (tabKey) {
    resetOne(tabKey);
    return;
  }

  resetOne('me');
  resetOne('unassigned');
  resetOne('all');
}

function setFiltersFromUISettings() {
  const { conversations_filter_by: filterBy = {} } = uiSettings.value;
  const { status, order_by: orderBy } = filterBy;

  activeStatus.value = status || wootConstants.STATUS_TYPE.OPEN;
  activeSortBy.value = Object.values(wootConstants.SORT_BY_TYPE).includes(orderBy)
    ? orderBy
    : wootConstants.SORT_BY_TYPE.LAST_ACTIVITY_AT_DESC;
}

function emitConversationLoaded() {
  emit('conversationLoad');
}

function getTabFilters(tabKey, page = 1, teamIdOverride = undefined) {
  const common = {
    inboxId: props.conversationInbox || undefined,
    sortBy: activeSortBy.value,
    page,
    labels: props.label ? [props.label] : undefined,
    conversationType: props.conversationType || undefined,
  };

  if (tabKey === 'me') {
    return {
      ...common,
      assigneeType: 'me',
      status: 'open',
      teamId: undefined,
    };
  }

  if (tabKey === 'unassigned') {
    return {
      ...common,
      assigneeType: props.teamId || teamIdOverride ? 'unassigned' : 'all',
      status: 'pending',
      teamId: teamIdOverride ?? (props.teamId || undefined),
    };
  }

  return {
    ...common,
    assigneeType: 'me',
    status: 'resolved',
    teamId: props.teamId || undefined,
  };
}

function normalizeConversationRows(responseData) {
  if (Array.isArray(responseData)) return responseData;
  if (Array.isArray(responseData?.payload)) return responseData.payload;
  if (Array.isArray(responseData?.data)) return responseData.data;
  if (Array.isArray(responseData?.conversations)) return responseData.conversations;
  return [];
}

function dedupeConversations(items) {
  const seen = new Set();

  return items.filter(item => {
    if (seen.has(item.id)) return false;
    seen.add(item.id);
    return true;
  });
}

async function fetchPendingForAllowedTeams(startPage = 1) {
  if (!allowedTeamIds.value.length) {
    debugLog('fetchPendingForAllowedTeams:vazio');
    return {
      rows: [],
      hasEndReached: true,
      lastScannedPage: startPage,
    };
  }

  debugLog('fetchPendingForAllowedTeams:buscando_por_time', {
    teamIds: allowedTeamIds.value,
    page: startPage,
  });

  const responses = await Promise.all(
    allowedTeamIds.value.map(teamId =>
      store.dispatch(
        'fetchConversationsByFilters',
        getTabFilters('unassigned', startPage, teamId)
      )
    )
  );

  const rawRows = responses.flatMap(response => normalizeConversationRows(response));

  debugLog(
    'fetchPendingForAllowedTeams:rawRows',
    rawRows.map(conversation => ({
      id: conversation.id,
      status: conversation.status,
      assignee_id: conversation.assignee_id,
      team_id: conversation.team_id,
      meta_team_id: conversation?.meta?.team?.id,
      resolvedTeamId: getConversationTeamId(conversation),
    }))
  );

  const seenIds = new Set();
  const rows = rawRows.filter(conversation => {
    const matchesContext = matchesCurrentContext(conversation);
    const isTeamScope = isConversationInTeamScope(conversation);

    debugLog('fetchPendingForAllowedTeams:check', {
      id: conversation.id,
      status: conversation.status,
      assigneeId: getConversationAssigneeId(conversation),
      teamId: getConversationTeamId(conversation),
      allowedTeamIds: allowedTeamIds.value,
      matchesContext,
      isTeamScope,
    });

    if (!matchesContext) return false;
    if (!isTeamScope) return false;
    if (seenIds.has(conversation.id)) return false;

    seenIds.add(conversation.id);
    return true;
  });

  const hasEndReached = responses.every(response => {
    const pageRows = normalizeConversationRows(response);
    return pageRows.length < TAB_PAGE_SIZE;
  });

  debugLog('fetchPendingForAllowedTeams:done', {
    collectedIds: rows.map(item => item.id),
    hasEndReached,
    lastScannedPage: startPage,
  });

  return {
    rows: sortConversationsByLastActivity(rows),
    hasEndReached,
    lastScannedPage: startPage,
  };
}

async function fetchTab(tabKey, { append = false } = {}) {
  const tab = tabState[tabKey];
  if (tab.loading) return;

  tab.loading = true;

  try {
    const nextPage = append ? tab.page + 1 : 1;

    debugLog('fetchTab:start', {
      tabKey,
      append,
      nextPage,
      isAdmin: isAdmin.value,
      propsTeamId: props.teamId,
      allowedTeamIds: allowedTeamIds.value,
    });

    if (tabKey === 'unassigned' && !isAdmin.value && !props.teamId) {
      const { rows, hasEndReached, lastScannedPage } =
        await fetchPendingForAllowedTeams(nextPage);

      mirrorRowsToStore(rows);

      tab.items = append
        ? dedupeConversations([...tab.items, ...rows])
        : rows;

      tab.page = lastScannedPage;
      tab.hasEndReached = hasEndReached;
      tab.initialized = true;

      debugLog('fetchTab:unassignedDone', {
        rows: rows.map(item => ({
          id: item.id,
          status: item.status,
          teamId: getConversationTeamId(item),
        })),
        hasEndReached,
        lastScannedPage,
      });

      return;
    }

    const filters = getTabFilters(tabKey, nextPage);
    debugLog('fetchTab:request', { tabKey, filters });

    const responseData = await store.dispatch('fetchConversationsByFilters', filters);
    const rawRows = normalizeConversationRows(responseData);

    debugLog(
      'fetchTab:rawRows',
      rawRows.map(conversation => ({
        id: conversation.id,
        status: conversation.status,
        assignee_id: conversation.assignee_id,
        team_id: conversation.team_id,
        meta_team_id: conversation?.meta?.team?.id,
        resolvedTeamId: getConversationTeamId(conversation),
      }))
    );

    const rows = rawRows.filter(conversation => {
      if (!matchesCurrentContext(conversation)) return false;

      if (tabKey === 'unassigned') {
        return isPendingTeamWithoutAgent(conversation);
      }

      return true;
    });

    mirrorRowsToStore(rows);

    tab.items = append
      ? dedupeConversations([...tab.items, ...rows])
      : rows;

    tab.page = nextPage;
    tab.hasEndReached = rawRows.length < TAB_PAGE_SIZE;
    tab.initialized = true;

    debugLog('fetchTab:done', {
      tabKey,
      resultIds: rows.map(item => item.id),
      hasEndReached: tab.hasEndReached,
      page: tab.page,
    });
  } catch (error) {
    console.error('Erro no fetchTab:', error);
  } finally {
    tab.loading = false;
  }
}

async function prefetchAllTabs() {
  await Promise.all([
    fetchTab('me'),
    fetchTab('unassigned'),
    fetchTab('all'),
  ]);
}

function fetchFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  const page = currentFiltersPage.value + 1;

  const request = store
    .dispatch('fetchFilteredConversations', {
      queryData: filterQueryGenerator(payload),
      page,
    })
    .then(emitConversationLoaded);

  showAdvancedFilters.value = false;

  return request;
}

function fetchSavedFilteredConversations(payload) {
  payload = useSnakeCase(payload);
  const page = currentFiltersPage.value + 1;

  return store
    .dispatch('fetchFilteredConversations', {
      queryData: payload,
      page,
    })
    .then(emitConversationLoaded);
}

function onApplyFilter(payload) {
  payload = useSnakeCase(payload);
  resetBulkActions();
  foldersQuery.value = filterQueryGenerator(payload);
  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  fetchFilteredConversations(payload);
}

function closeAdvanceFiltersModal() {
  showAdvancedFilters.value = false;
  appliedFilter.value = [];
}

function onUpdateSavedFilter(payload, folderName) {
  const transformedPayload = useSnakeCase(payload);

  const payloadData = {
    ...unref(activeFolder),
    name: unref(folderName),
    query: filterQueryGenerator(transformedPayload),
  };

  store.dispatch('customViews/update', payloadData);
  closeAdvanceFiltersModal();
}

function onClickOpenAddFoldersModal() {
  showAddFoldersModal.value = true;
}

function onCloseAddFoldersModal() {
  showAddFoldersModal.value = false;
}

function onClickOpenDeleteFoldersModal() {
  showDeleteFoldersModal.value = true;
}

function onCloseDeleteFoldersModal() {
  showDeleteFoldersModal.value = false;
}

function setParamsForEditFolderModal() {
  return {
    agents: agentList.value,
    teams: teamsList.value,
    inboxes: inboxesList.value,
    labels: labels.value,
    campaigns: campaigns.value,
    languages,
    countries,
    priority: [
      { id: 'low', name: t('CONVERSATION.PRIORITY.OPTIONS.LOW') },
      { id: 'medium', name: t('CONVERSATION.PRIORITY.OPTIONS.MEDIUM') },
      { id: 'high', name: t('CONVERSATION.PRIORITY.OPTIONS.HIGH') },
      { id: 'urgent', name: t('CONVERSATION.PRIORITY.OPTIONS.URGENT') },
    ],
    filterTypes: advancedFilterTypes.value,
    allCustomAttributes: conversationCustomAttributes.value,
  };
}

function initializeExistingFilterToModal() {
  const statusFilter = initializeStatusAndAssigneeFilterToModal(
    activeStatus.value,
    currentUserDetails.value,
    activeAssigneeTab.value
  );

  if (statusFilter) {
    appliedFilter.value = [...appliedFilter.value, useCamelCase(statusFilter)];
  }

  const otherFilters = initializeInboxTeamAndLabelFilterToModal(
    props.conversationInbox,
    inbox.value,
    props.teamId,
    activeTeam.value,
    props.label
  ).map(useCamelCase);

  appliedFilter.value = [...appliedFilter.value, ...otherFilters];
}

function initializeFolderToFilterModal(newActiveFolder) {
  const query = unref(newActiveFolder)?.query?.payload;
  if (!Array.isArray(query)) return;

  const newFilters = query.map(filter => {
    const transformed = useCamelCase(filter);
    const values = Array.isArray(transformed.values)
      ? generateValuesForEditCustomViews(
          useSnakeCase(filter),
          setParamsForEditFolderModal()
        )
      : [];

    return {
      attributeKey: transformed.attributeKey,
      attributeModel: transformed.attributeModel,
      customAttributeType: transformed.customAttributeType,
      filterOperator: transformed.filterOperator,
      queryOperator: transformed.queryOperator ?? 'and',
      values,
    };
  });

  appliedFilter.value = [...appliedFilter.value, ...newFilters];
}

function initalizeAppliedFiltersToModal() {
  appliedFilter.value = [...appliedFilters.value];
}

function onToggleAdvanceFiltersModal() {
  if (showAdvancedFilters.value === true) {
    closeAdvanceFiltersModal();
    return;
  }

  if (!hasAppliedFilters.value && !hasActiveFolders.value) {
    initializeExistingFilterToModal();
  }

  if (hasActiveFolders.value) {
    initializeFolderToFilterModal(activeFolder.value);
  }

  if (hasAppliedFilters.value) {
    initalizeAppliedFiltersToModal();
  }

  showAdvancedFilters.value = true;
}

function fetchConversations(filters = conversationFilters.value) {
  store.dispatch('updateChatListFilters', filters);
  return store.dispatch('fetchAllConversations').then(emitConversationLoaded);
}

async function resetAndFetchData() {
  appliedFilter.value = [];
  resetBulkActions();

  debugLog('resetAndFetchData', {
    hasAppliedFiltersOrActiveFolders: hasAppliedFiltersOrActiveFolders.value,
    isAdmin: isAdmin.value,
    activeAssigneeTab: activeAssigneeTab.value,
    allowedTeamIds: allowedTeamIds.value,
  });

  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    resetTabState();
    await prefetchAllTabs();
    return;
  }

  store.dispatch('conversationPage/reset');
  store.dispatch('emptyAllConversations');
  store.dispatch('clearConversationFilters');

  if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    await fetchSavedFilteredConversations(payload);
    return;
  }

  if (props.foldersId) {
    return;
  }

  await fetchConversations();
}

async function loadMoreConversations() {
  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    const currentTab = tabState[activeAssigneeTab.value];

    debugLog('loadMoreConversations', {
      activeAssigneeTab: activeAssigneeTab.value,
      currentPage: currentTab.page,
      hasEndReached: currentTab.hasEndReached,
      loading: currentTab.loading,
    });

    if (currentTab.loading || currentTab.hasEndReached) {
      return;
    }

    await fetchTab(activeAssigneeTab.value, { append: true });
    return;
  }

  if (hasCurrentPageEndReached.value || chatListLoading.value) {
    return;
  }

  if (!hasAppliedFiltersOrActiveFolders.value) {
    fetchConversations();
  } else if (hasActiveFolders.value) {
    const payload = activeFolder.value.query;
    fetchSavedFilteredConversations(payload);
  } else if (hasAppliedFilters.value) {
    fetchFilteredConversations(appliedFilters.value);
  }
}

const intersectionObserverOptions = computed(() => ({
  root: conversationListRef.value,
  rootMargin: '100px 0px 100px 0px',
}));

function updateAssigneeTab(selectedTab) {
  if (activeAssigneeTab.value === selectedTab) return;

  debugLog('updateAssigneeTab', {
    from: activeAssigneeTab.value,
    to: selectedTab,
    allowedTeamIds: allowedTeamIds.value,
  });

  resetBulkActions();
  emitter.emit('clearSearchInput');
  activeAssigneeTab.value = selectedTab;

  if (!isAdmin.value) {
    if (selectedTab === 'me') {
      activeStatus.value = 'open';
    } else if (selectedTab === 'unassigned') {
      activeStatus.value = 'pending';
    } else if (selectedTab === 'all') {
      activeStatus.value = 'resolved';
    }
  }

  if (
    !hasAppliedFiltersOrActiveFolders.value &&
    !isAdmin.value &&
    !tabState[selectedTab].initialized
  ) {
    fetchTab(selectedTab);
  }
}

function onBasicFilterChange(value, type) {
  if (type === 'status') {
    if (isAdmin.value) {
      activeStatus.value = value;
    }
  } else {
    activeSortBy.value = value;
  }

  resetAndFetchData();
}

function openLastSavedItemInFolder() {
  const lastItemOfFolder = folders.value[folders.value.length - 1];
  const lastItemId = lastItemOfFolder.id;

  router.push({
    name: 'folder_conversations',
    params: { id: lastItemId },
  });
}

function openLastItemAfterDeleteInFolder() {
  if (folders.value.length > 0) {
    openLastSavedItemInFolder();
  } else {
    router.push({ name: 'home' });
    fetchConversations();
  }
}

function redirectToConversationList() {
  const {
    params: { accountId, inbox_id: inboxId, label, teamId },
    name,
  } = route;

  let conversationType = '';

  if (isOnMentionsView({ route: { name } })) {
    conversationType = 'mention';
  } else if (isOnUnattendedView({ route: { name } })) {
    conversationType = 'unattended';
  }

  router.push(
    conversationListPageURL({
      accountId,
      conversationType,
      customViewId: props.foldersId,
      inboxId,
      label,
      teamId,
    })
  );
}

async function assignPriority(priority, conversationId = null) {
  store.dispatch('setCurrentChatPriority', {
    priority,
    conversationId,
  });

  store.dispatch('assignPriority', {
    conversationId,
    priority,
  }).then(() => {
    useTrack(CONVERSATION_EVENTS.CHANGE_PRIORITY, {
      newValue: priority,
      from: 'Context menu',
    });

    useAlert(
      t('CONVERSATION.PRIORITY.CHANGE_PRIORITY.SUCCESSFUL', {
        priority,
        conversationId,
      })
    );
  });
}

async function markAsUnread(conversationId) {
  try {
    await store.dispatch('markMessagesUnread', {
      id: conversationId,
    });
    redirectToConversationList();
  } catch {
    // Ignore error
  }
}

async function markAsRead(conversationId) {
  try {
    await store.dispatch('markMessagesRead', {
      id: conversationId,
    });
  } catch {
    // Ignore error
  }
}

async function onAssignTeam(team, conversationId = null) {
  try {
    await store.dispatch('assignTeam', {
      conversationId,
      teamId: team.id,
    });

    useAlert(
      t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.SUCCESFUL', {
        team: team.name,
        conversationId,
      })
    );
  } catch {
    useAlert(t('CONVERSATION.CARD_CONTEXT_MENU.API.TEAM_ASSIGNMENT.FAILED'));
  }
}

function toggleConversationStatus(
  conversationId,
  status,
  snoozedUntil,
  customAttributes = null
) {
  const payload = {
    conversationId,
    status,
    snoozedUntil,
  };

  if (customAttributes) {
    payload.customAttributes = customAttributes;
  }

  store.dispatch('toggleStatus', payload).then(() => {
    useAlert(t('CONVERSATION.CHANGE_STATUS'));
  });
}

function handleResolveConversation(conversationId, status, snoozedUntil) {
  if (status !== wootConstants.STATUS_TYPE.RESOLVED) {
    toggleConversationStatus(conversationId, status, snoozedUntil);
    return;
  }

  const conversation = getConversationById.value(conversationId);
  const currentCustomAttributes = conversation?.custom_attributes || {};
  const { hasMissing, missing } = checkMissingAttributes(currentCustomAttributes);

  if (hasMissing) {
    const conversationContext = {
      id: conversationId,
      snoozedUntil,
    };

    resolveAttributesModalRef.value?.open(
      missing,
      currentCustomAttributes,
      conversationContext
    );
  } else {
    toggleConversationStatus(conversationId, status, snoozedUntil);
  }
}

function handleResolveWithAttributes({ attributes, context }) {
  if (context) {
    const existingConversation = getConversationById.value(context.id);
    const currentCustomAttributes = existingConversation?.custom_attributes || {};
    const mergedAttributes = {
      ...currentCustomAttributes,
      ...attributes,
    };

    toggleConversationStatus(
      context.id,
      wootConstants.STATUS_TYPE.RESOLVED,
      context.snoozedUntil,
      mergedAttributes
    );
  }
}

function allSelectedConversationsStatus(status) {
  if (!selectedConversations.value.length) return false;

  return selectedConversations.value.every(item => {
    return getConversationById.value(item)?.status === status;
  });
}

function onContextMenuToggle(state) {
  isContextMenuOpen.value = state;
}

function toggleSelectAll(check) {
  selectAllConversations(check, conversationList);
}

function mirrorRowsToStore(rows) {
  rows.forEach(conversation => {
    const existingConversation = getConversationById.value(conversation.id);

    if (!existingConversation) {
      store.dispatch('addConversation', conversation);
    }

    store.dispatch('updateConversation', conversation);
  });
}

useEmitter('fetch_conversation_stats', () => {
  if (hasAppliedFiltersOrActiveFolders.value) return;
  store.dispatch('conversationStats/get', conversationFilters.value);
});

onMounted(async () => {
  try {
    await store.dispatch('teams/get');
  } catch {
    // ignora, segue com a tela
  }

  debugLog('onMounted:teamsLoaded', {
    currentUserId: currentUserId.value,
    currentUser: currentUser.value,
    teams: teamsList.value,
    myTeamIds: myTeamIds.value,
    allowedTeamIds: allowedTeamIds.value,
    propsTeamId: props.teamId,
  });

  setFiltersFromUISettings();
  store.dispatch('setChatStatusFilter', activeStatus.value);
  store.dispatch('setChatSortFilter', activeSortBy.value);

  if (!hasAppliedFiltersOrActiveFolders.value && !isAdmin.value) {
    await prefetchAllTabs();
  } else {
    store.dispatch('setChatListFilters', conversationFilters.value);
    await store.dispatch('fetchAllConversations');
    emitConversationLoaded();
  }

  if (hasActiveFolders.value) {
    store.dispatch('campaigns/get');
  }

  unsubscribeSocketBridge = store.subscribeAction({
    after: action => {
      const type = action.type;

      if (
        type === 'addConversation' ||
        type === 'updateConversation' ||
        type === 'updateConversationLastActivity' ||
        type === 'setCurrentChatAssignee' ||
        type === 'setCurrentChatTeam' ||
        type === 'updateConversationContact' ||
        type === 'toggleStatus'
      ) {
        syncConversationByPayload(action.payload);
      }

      if (type === 'deleteConversation') {
        removeConversationFromAllTabs(action.payload);
      }
    },
  });
});

onBeforeUnmount(() => {
  if (unsubscribeSocketBridge) {
    unsubscribeSocketBridge();
  }
});

const deleteConversationDialogRef = ref(null);
const selectedConversationId = ref(null);

async function deleteConversation() {
  try {
    await store.dispatch('deleteConversation', selectedConversationId.value);
    redirectToConversationList();
    selectedConversationId.value = null;
    deleteConversationDialogRef.value.close();
    useAlert(t('CONVERSATION.SUCCESS_DELETE_CONVERSATION'));
  } catch {
    useAlert(t('CONVERSATION.FAIL_DELETE_CONVERSATION'));
  }
}

const handleDelete = conversationId => {
  selectedConversationId.value = conversationId;
  deleteConversationDialogRef.value.open();
};

provide('selectConversation', selectConversation);
provide('deSelectConversation', deSelectConversation);
provide('assignAgent', onAssignAgent);
provide('assignTeam', onAssignTeam);
provide('assignLabels', onAssignLabels);
provide('removeLabels', onRemoveLabels);
provide('updateConversationStatus', handleResolveConversation);
provide('toggleContextMenu', onContextMenuToggle);
provide('markAsUnread', markAsUnread);
provide('markAsRead', markAsRead);
provide('assignPriority', assignPriority);
provide('isConversationSelected', isConversationSelected);
provide('deleteConversation', handleDelete);

watch(
  myTeamIds,
  async (newIds, oldIds) => {
    const oldValue = Array.isArray(oldIds) ? oldIds.join(',') : '';
    const newValue = Array.isArray(newIds) ? newIds.join(',') : '';

    debugLog('watch:myTeamIds', newIds);

    if (!newIds.length) return;
    if (oldValue === newValue) return;
    if (isAdmin.value) return;
    if (props.teamId) return;
    if (hasAppliedFiltersOrActiveFolders.value) return;

    resetTabState('unassigned');
    await fetchTab('unassigned');
  },
  { immediate: true }
);

watch(
  allowedTeamIds,
  value => {
    debugLog('watch:allowedTeamIds', value);
  },
  { immediate: true }
);

watch(activeTeam, () => resetAndFetchData());

watch(
  computed(() => props.conversationInbox),
  () => resetAndFetchData()
);

watch(
  computed(() => props.label),
  () => resetAndFetchData()
);

watch(
  computed(() => props.conversationType),
  () => resetAndFetchData()
);

watch(activeFolder, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    store.dispatch('customViews/setActiveConversationFolder', newVal || null);
  }
  resetAndFetchData();
});

watch(
  conversationList,
  value => {
    chatsOnView.value = value;
    debugLog(
      'watch:conversationList',
      value.map(item => ({
        id: item.id,
        status: item.status,
        assigneeId: getConversationAssigneeId(item),
        teamId: getConversationTeamId(item),
      }))
    );
  },
  { immediate: true }
);

watch(conversationFilters, (newVal, oldVal) => {
  if (newVal !== oldVal) {
    debugLog('watch:conversationFilters', { oldVal, newVal });
    store.dispatch('updateChatListFilters', newVal);
  }
});
</script>

<template>
  <div
    class="flex flex-col flex-shrink-0 conversations-list-wrap bg-n-surface-1"
    :class="[
      { hidden: !showConversationList },
      isOnExpandedLayout ? 'basis-full' : 'w-[340px] 2xl:w-[412px]',
    ]"
  >
    <slot />

    <ChatListHeader
      :page-title="pageTitle"
      :has-applied-filters="hasAppliedFilters"
      :has-active-folders="hasActiveFolders"
      :active-status="activeStatus"
      :is-on-expanded-layout="isOnExpandedLayout"
      :conversation-stats="conversationStats"
      :is-list-loading="isCurrentListLoading"
      :status-chip-label="headerStatusLabel"
      :hide-basic-status-filter="isRestrictedAgentView"
      @add-folders="onClickOpenAddFoldersModal"
      @delete-folders="onClickOpenDeleteFoldersModal"
      @filters-modal="onToggleAdvanceFiltersModal"
      @reset-filters="resetAndFetchData"
      @basic-filter-change="onBasicFilterChange"
    />

    <TeleportWithDirection
      v-if="showAddFoldersModal"
      to="#saveFilterTeleportTarget"
    >
      <SaveCustomView
        v-model="appliedFilter"
        :custom-views-query="foldersQuery"
        :open-last-saved-item="openLastSavedItemInFolder"
        @close="onCloseAddFoldersModal"
      />
    </TeleportWithDirection>

    <DeleteCustomViews
      v-if="showDeleteFoldersModal"
      v-model:show="showDeleteFoldersModal"
      :active-custom-view="activeFolder"
      :custom-views-id="foldersId"
      :open-last-item-after-delete="openLastItemAfterDeleteInFolder"
      @close="onCloseDeleteFoldersModal"
    />

    <ChatTypeTabs
      v-if="!hasAppliedFiltersOrActiveFolders"
      :items="assigneeTabItems"
      :active-tab="activeAssigneeTab"
      is-compact
      @chat-tab-change="updateAssigneeTab"
    />

    <p
      v-if="!isCurrentListLoading && !conversationList.length"
      class="flex overflow-auto justify-center items-center p-4"
    >
      {{ $t('CHAT_LIST.LIST.404') }}
    </p>

    <ConversationBulkActions
      v-if="selectedConversations.length"
      :conversations="selectedConversations"
      :all-conversations-selected="allConversationsSelected"
      :selected-inboxes="uniqueInboxes"
      :show-open-action="allSelectedConversationsStatus('open')"
      :show-resolved-action="allSelectedConversationsStatus('resolved')"
      :show-snoozed-action="allSelectedConversationsStatus('snoozed')"
      @select-all-conversations="toggleSelectAll"
      @assign-agent="onAssignAgent"
      @update-conversations="onUpdateConversations"
      @assign-labels="onAssignLabels"
      @assign-team="onAssignTeamsForBulk"
    />

    <div
      ref="conversationListRef"
      class="flex-1 min-h-0 overflow-y-auto conversations-list"
      :class="{ '!overflow-hidden': isContextMenuOpen }"
    >
      <Virtualizer
        ref="virtualListRef"
        v-slot="{ item, index }"
        :data="conversationList"
      >
        <ConversationItem
          :source="item"
          :label="label"
          :team-id="teamId"
          :folders-id="foldersId"
          :conversation-type="conversationType"
          :show-assignee="showAssigneeInConversationCard"
          :data-index="index"
          @select-conversation="selectConversation"
          @de-select-conversation="deSelectConversation"
        />
      </Virtualizer>

      <div v-if="isCurrentListLoading" class="flex justify-center my-4">
        <Spinner class="text-n-brand" />
      </div>

      <p
        v-else-if="showEndOfListMessage"
        class="p-4 text-center text-n-slate-11"
      >
        {{ $t('CHAT_LIST.EOF') }}
      </p>

      <IntersectionObserver
        v-else
        :options="intersectionObserverOptions"
        @observed="loadMoreConversations"
      />
    </div>

    <Dialog
      ref="deleteConversationDialogRef"
      type="alert"
      :title="
        $t('CONVERSATION.DELETE_CONVERSATION.TITLE', {
          conversationId: selectedConversationId,
        })
      "
      :description="$t('CONVERSATION.DELETE_CONVERSATION.DESCRIPTION')"
      :confirm-button-label="$t('CONVERSATION.DELETE_CONVERSATION.CONFIRM')"
      @confirm="deleteConversation"
      @close="selectedConversationId = null"
    />

    <TeleportWithDirection
      v-if="showAdvancedFilters"
      to="#conversationFilterTeleportTarget"
    >
      <ConversationFilter
        v-model="appliedFilter"
        :folder-name="activeFolderName"
        :is-folder-view="hasActiveFolders"
        @apply-filter="onApplyFilter"
        @update-folder="onUpdateSavedFilter"
        @close="closeAdvanceFiltersModal"
      />
    </TeleportWithDirection>

    <ConversationResolveAttributesModal
      ref="resolveAttributesModalRef"
      @submit="handleResolveWithAttributes"
    />
  </div>
</template>
