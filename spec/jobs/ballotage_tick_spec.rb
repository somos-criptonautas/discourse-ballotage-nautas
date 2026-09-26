# frozen_string_literal: true

RSpec.describe Jobs::BallotageTick do
  fab!(:voting_group, :group)
  fab!(:voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:other_voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:admin)

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
  end

  def create_ballot(starts_at:, ends_at:)
    Ballotage::Ballot.create!(
      title: "Ballot",
      starts_at: starts_at,
      ends_at: ends_at,
      created_by_id: admin.id,
    )
  end

  def run
    described_class.new.execute({})
  end

  it "announces an opened ballot to every eligible member, once" do
    create_ballot(starts_at: 1.minute.ago, ends_at: 3.days.from_now)

    expect { run }.to change { Notification.where(user_id: [voter.id, other_voter.id]).count }.by(2)
    expect { run }.not_to change { Notification.count }
  end

  it "reminds only members who haven't voted when a long ballot is about to close" do
    ballot = create_ballot(starts_at: 2.days.ago, ends_at: 3.hours.from_now)
    ballot.update_columns(opened_notified_at: 2.days.ago)
    ballot.cast_vote!(voter, "white")

    expect { run }.to change { Notification.where(user_id: other_voter.id).count }.by(1)
    expect(Notification.where(user_id: voter.id).count).to eq(0)
  end

  it "closes an ended ballot and freezes its outcome" do
    ballot = create_ballot(starts_at: 2.days.ago, ends_at: 1.day.from_now)
    ballot.cast_vote!(voter, "white")
    ballot.update_columns(ends_at: 1.minute.ago, opened_notified_at: 2.days.ago)

    run

    expect(ballot.reload.outcome).to eq("approved")
    expect(ballot.closed_at).to be_present
  end

  it "does nothing while the plugin is disabled" do
    create_ballot(starts_at: 1.minute.ago, ends_at: 3.days.from_now)
    SiteSetting.ballotage_enabled = false

    expect { run }.not_to change { Notification.count }
  end
end
