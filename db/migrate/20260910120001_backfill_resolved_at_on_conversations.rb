class BackfillResolvedAtOnConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # For conversations that are already resolved we estimate `resolved_at` using the
  # most recent `conversation_resolved` reporting event. When there is no such event
  # (older data / events pruned) we fall back to `last_activity_at`, then `updated_at`.
  def up
    Conversation.resolved.where(resolved_at: nil).find_each(batch_size: 1000) do |conversation|
      event_end_time = ReportingEvent
                       .where(conversation_id: conversation.id, name: 'conversation_resolved')
                       .order(created_at: :desc)
                       .limit(1)
                       .pick(:event_end_time)

      timestamp = event_end_time || conversation.last_activity_at || conversation.updated_at

      # rubocop:disable Rails/SkipsModelValidations
      conversation.update_column(:resolved_at, timestamp)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def down
    # rubocop:disable Rails/SkipsModelValidations
    Conversation.where.not(resolved_at: nil).update_all(resolved_at: nil)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
