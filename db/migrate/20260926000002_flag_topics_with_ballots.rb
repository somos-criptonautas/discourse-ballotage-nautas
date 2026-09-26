# frozen_string_literal: true

# Topic lists mark topics that embed a ballot via a preloaded topic custom
# field; set it for ballots already linked to a post.
class FlagTopicsWithBallots < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      INSERT INTO topic_custom_fields (topic_id, name, value, created_at, updated_at)
      SELECT DISTINCT posts.topic_id, 'ballotage', 't', NOW(), NOW()
      FROM ballotage_ballots
      JOIN posts ON posts.id = ballotage_ballots.post_id
      WHERE NOT EXISTS (
        SELECT 1 FROM topic_custom_fields tcf
        WHERE tcf.topic_id = posts.topic_id AND tcf.name = 'ballotage'
      )
    SQL
  end

  def down
    execute "DELETE FROM topic_custom_fields WHERE name = 'ballotage'"
  end
end
