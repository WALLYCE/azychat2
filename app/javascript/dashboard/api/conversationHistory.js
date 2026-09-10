/* global axios */
import ApiClient from './ApiClient';

/**
 * API helper for the "Conversation History" admin screen.
 *
 * It leans on the existing `/conversations/filter` endpoint to pull the
 * conversation history for a given agent (assignee) and on the
 * `/conversations/:id/messages` endpoint to render a read-only transcript.
 */
class ConversationHistoryAPI extends ApiClient {
  constructor() {
    super('conversations', { accountScoped: true });
  }

  /**
   * @param {Object} options
   * @param {Number|String} options.assigneeId - agent id whose history we want
   * @param {Object}  [options.filters]
   * @param {String}  [options.filters.displayId]      - exact conversation display id
   * @param {String}  [options.filters.status]         - open | resolved | pending | snoozed | all
   * @param {String}  [options.filters.openedAfter]    - ISO date (created_at >=)
   * @param {String}  [options.filters.openedBefore]   - ISO date (created_at <=)
   * @param {String}  [options.filters.resolvedAfter]  - ISO date (resolved_at >=)
   * @param {String}  [options.filters.resolvedBefore] - ISO date (resolved_at <=)
   * @param {Number}  [options.page=1]
   */
  getAgentHistory({ assigneeId, filters = {}, page = 1 }) {
    const payload = [];
    const add = (attributeKey, filterOperator, values) => {
      payload.push({
        attribute_key: attributeKey,
        filter_operator: filterOperator,
        values,
        query_operator: 'and',
      });
    };

    add('assignee_id', 'equal_to', [assigneeId]);

    if (filters.displayId) {
      add('display_id', 'equal_to', [filters.displayId]);
    }
    if (filters.status && filters.status !== 'all') {
      add('status', 'equal_to', [filters.status]);
    }
    if (filters.openedAfter) {
      add('created_at', 'is_greater_than', [filters.openedAfter]);
    }
    if (filters.openedBefore) {
      add('created_at', 'is_less_than', [filters.openedBefore]);
    }
    if (filters.resolvedAfter) {
      add('resolved_at', 'is_greater_than', [filters.resolvedAfter]);
    }
    if (filters.resolvedBefore) {
      add('resolved_at', 'is_less_than', [filters.resolvedBefore]);
    }

    // The last condition must not carry a trailing query operator, otherwise the
    // filter endpoint rejects the payload.
    payload[payload.length - 1].query_operator = undefined;

    return axios.post(
      `${this.url}/filter`,
      { payload },
      { params: { page } }
    );
  }

  /**
   * Read-only transcript for a single conversation.
   * @param {Object} options
   * @param {Number|String} options.conversationId - conversation display id
   * @param {Number} [options.before] - message id to paginate older messages
   */
  getMessages({ conversationId, before }) {
    return axios.get(`${this.url}/${conversationId}/messages`, {
      params: { before },
    });
  }
}

export default new ConversationHistoryAPI();
