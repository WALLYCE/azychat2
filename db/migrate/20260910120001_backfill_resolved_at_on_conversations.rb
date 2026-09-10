class BackfillResolvedAtOnConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  # `resolved_at` is populated going forward by the Conversation model. For
  # conversations that were already resolved before this column existed we
  # approximate it with `last_activity_at` (falling back to `updated_at`).
  #
  # This runs as set-based UPDATEs in id-range batches so it stays fast on large
  # tables and keeps row locks short. It is idempotent (`resolved_at IS NULL`),
  # so a previously interrupted run can simply be re-applied.
  def up
    resolved = Conversation.statuses[:resolved]

    min_id = Conversation.where(status: resolved).minimum(:id)
    max_id = Conversation.where(status: resolved).maximum(:id)
    return if min_id.nil?

    batch_size = 50_000
    start_id = min_id

    while start_id <= max_id
      execute(<<~SQL.squish)
        UPDATE conversations
        SET resolved_at = COALESCE(last_activity_at, updated_at)
        WHERE id >= #{start_id.to_i}
          AND id < #{start_id.to_i + batch_size}
          AND status = #{resolved.to_i}
          AND resolved_at IS NULL
      SQL

      start_id += batch_size
    end
  end

  def down
    execute('UPDATE conversations SET resolved_at = NULL WHERE resolved_at IS NOT NULL')
  end
end
