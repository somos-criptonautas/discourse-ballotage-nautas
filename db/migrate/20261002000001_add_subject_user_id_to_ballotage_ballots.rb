# frozen_string_literal: true

# The member an admission ballot is about, so automations can act on the
# outcome (e.g. add the candidate to a group). Nullable: optional, and
# proposals have no candidate.
class AddSubjectUserIdToBallotageBallots < ActiveRecord::Migration[7.2]
  def change
    add_column :ballotage_ballots, :subject_user_id, :bigint
    add_index :ballotage_ballots, :subject_user_id
  end
end
