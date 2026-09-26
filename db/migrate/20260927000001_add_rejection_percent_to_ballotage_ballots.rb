# frozen_string_literal: true

# Admissions can reject by share of black balls (e.g. 25% of votes cast)
# instead of a fixed number; null keeps the fixed rejection_threshold.
class AddRejectionPercentToBallotageBallots < ActiveRecord::Migration[7.2]
  def change
    add_column :ballotage_ballots, :rejection_percent, :integer
  end
end
