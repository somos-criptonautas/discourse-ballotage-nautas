# frozen_string_literal: true

# Ballot kinds with their decision rule, result visibility, and the outcome
# frozen when a ballot closes (it survives finalizing). The *_at columns make
# the notification job idempotent.
class AddRulesAndOutcomeToBallotageBallots < ActiveRecord::Migration[7.2]
  def change
    add_column :ballotage_ballots, :kind, :string, null: false, default: "admission"
    add_column :ballotage_ballots, :abstain_count, :integer, null: false, default: 0
    add_column :ballotage_ballots, :rejection_threshold, :integer, null: false, default: 1
    add_column :ballotage_ballots, :approval_rule, :string, null: false, default: "majority"
    add_column :ballotage_ballots, :quorum_percent, :integer
    add_column :ballotage_ballots, :result_visibility, :string, null: false, default: "overseers"
    add_column :ballotage_ballots, :keep_counts, :boolean, null: false, default: false
    add_column :ballotage_ballots, :outcome, :string
    add_column :ballotage_ballots, :closed_voter_count, :integer
    add_column :ballotage_ballots, :closed_eligible_count, :integer
    add_column :ballotage_ballots, :opened_notified_at, :datetime
    add_column :ballotage_ballots, :reminded_at, :datetime
    add_column :ballotage_ballots, :closed_at, :datetime

    # Existing ballots predate notifications: mark what already happened as done
    # so the first job run doesn't notify about the past. Closed legacy ballots
    # have no rules, so they get no outcome either.
    reversible { |dir| dir.up { execute <<~SQL } }
          UPDATE ballotage_ballots
          SET opened_notified_at = CASE WHEN starts_at <= NOW() THEN NOW() END,
              reminded_at = CASE WHEN ends_at <= NOW() + INTERVAL '24 hours' THEN NOW() END,
              closed_at = CASE WHEN ends_at <= NOW() THEN NOW() END
        SQL
  end
end
