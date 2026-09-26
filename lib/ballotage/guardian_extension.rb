# frozen_string_literal: true

module Ballotage
  module GuardianExtension
    def can_vote_in_ballotage?
      return false if anonymous?
      ballotage_group_member?(SiteSetting.ballotage_voting_group)
    end

    # Sees the management page: participation during a ballot, the result after it.
    def can_oversee_ballotage?
      return false if anonymous?
      return true if is_admin?
      ballotage_group_member?(SiteSetting.ballotage_oversight_group)
    end

    # Creates, cancels and finalizes ballots.
    def can_manage_ballotage?
      return false if anonymous?
      return true if is_admin?
      SiteSetting.ballotage_oversight_can_manage &&
        ballotage_group_member?(SiteSetting.ballotage_oversight_group)
    end

    private

    def ballotage_group_member?(group_id)
      return false if group_id.blank?
      # One query per guardian (i.e. per request), however many checks run.
      @ballotage_group_ids ||= GroupUser.where(user_id: user.id).pluck(:group_id)
      @ballotage_group_ids.include?(group_id.to_i)
    end
  end
end
