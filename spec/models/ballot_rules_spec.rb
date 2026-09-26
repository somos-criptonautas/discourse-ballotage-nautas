# frozen_string_literal: true

RSpec.describe Ballotage::Ballot do
  fab!(:voting_group, :group)
  fab!(:voters) { Fabricate.times(4, :user, group_ids: [voting_group.id]) }
  fab!(:admin)

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
  end

  # Casts the given votes (one per voter, in order), ends and closes the ballot.
  def closed_ballot(votes, **attrs)
    ballot =
      described_class.create!(
        title: "Ballot",
        starts_at: 2.hours.ago,
        ends_at: 1.hour.from_now,
        created_by_id: admin.id,
        **attrs,
      )
    votes.each_with_index { |choice, i| ballot.cast_vote!(voters[i], choice) }
    ballot.update_columns(ends_at: 1.minute.ago)
    ballot.close!
    ballot.reload
  end

  def notification_labels(user)
    Notification.where(user_id: user.id).map { |n| JSON.parse(n.data)["display_username"] }
  end

  describe "#close!" do
    it "rejects an admission once the black-ball threshold is reached" do
      expect(closed_ballot(%w[black white white], rejection_threshold: 1).outcome).to eq(
        "rejected",
      )
      expect(closed_ballot(%w[black white white], rejection_threshold: 2).outcome).to eq(
        "approved",
      )
    end

    it "applies the proposal rule, leaving abstentions out of the majority" do
      expect(closed_ballot(%w[white black abstain abstain], kind: "proposal").outcome).to eq(
        "rejected",
      )
      expect(
        closed_ballot(%w[white white black abstain], kind: "proposal", approval_rule: "two_thirds")
          .outcome,
      ).to eq("approved")
      expect(
        closed_ballot(%w[white white black], kind: "proposal", approval_rule: "unanimous").outcome,
      ).to eq("rejected")
    end

    it "reports no quorum when too few members voted, abstentions included" do
      expect(closed_ballot(%w[white], quorum_percent: 50).outcome).to eq("no_quorum")
      expect(closed_ballot(%w[abstain white], kind: "proposal", quorum_percent: 50).outcome).to eq(
        "approved",
      )
      expect(closed_ballot([]).outcome).to eq("no_quorum")
    end

    it "freezes the turnout and runs only once" do
      ballot = closed_ballot(%w[white white black])
      expect(ballot.closed_voter_count).to eq(3)
      expect(ballot.closed_eligible_count).to eq(4)
      expect(ballot.close!).to eq(false)
    end

    it "never closes a cancelled ballot" do
      ballot =
        described_class.create!(
          title: "Cancelled",
          starts_at: 2.hours.ago,
          ends_at: 1.hour.ago,
          cancelled_at: 90.minutes.ago,
          created_by_id: admin.id,
        )
      expect(ballot.close!).to eq(false)
      expect(ballot.reload.outcome).to be_nil
    end

    it "tells voters the outcome only when the ballot publishes it" do
      closed_ballot(%w[white], result_visibility: "outcome")
      expect(notification_labels(voters[0]).last).to include("Approved")

      closed_ballot(%w[white], result_visibility: "overseers")
      expect(notification_labels(voters[0]).last).not_to include("Approved")
    end
  end

  describe "#cast_vote!" do
    it "only accepts the choices of the ballot's kind" do
      ballot =
        described_class.create!(
          title: "Admission",
          starts_at: 1.hour.ago,
          ends_at: 1.hour.from_now,
          created_by_id: admin.id,
        )
      expect { ballot.cast_vote!(voters[0], "abstain") }.to raise_error(
        Discourse::InvalidParameters,
      )
    end
  end

  describe "#finalize!" do
    it "keeps published counts only when the ballot chose to, and always the outcome" do
      kept =
        closed_ballot(%w[white black], kind: "proposal", result_visibility: "counts", keep_counts: true)
      kept.finalize!
      expect(kept.reload.white_count).to eq(1)
      expect(kept.outcome).to eq("rejected")
      expect(kept.participations.count).to eq(0)

      dropped = closed_ballot(%w[white black], kind: "proposal", result_visibility: "outcome")
      dropped.finalize!
      expect(dropped.reload.white_count).to eq(0)
      expect(dropped.outcome).to eq("rejected")
    end
  end
end
