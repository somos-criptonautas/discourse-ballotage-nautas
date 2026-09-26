# frozen_string_literal: true

# The post a ballot is embedded in via [ballotage id=N], so the management list
# can link to the discussion. Nullable: ballots can still exist without a post.
class AddPostIdToBallotageBallots < ActiveRecord::Migration[7.2]
  def change
    add_column :ballotage_ballots, :post_id, :bigint
    add_index :ballotage_ballots, :post_id
  end
end
