import { frontendURL } from 'dashboard/helper/URLHelper.js';

import ConversationHistoryView from './ConversationHistoryView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/conversation-history'),
    name: 'conversation_history_index',
    meta: {
      permissions: ['administrator'],
    },
    component: ConversationHistoryView,
  },
];

export default { routes };
