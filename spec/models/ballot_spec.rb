# frozen_string_literal: true

RSpec.describe Ballotage::Ballot do
  fab!(:user)

  def build_ballot(starts_at:, ends_at:, **attrs)
    Ballotage::Ballot.create!(
      title: "Test Ballot",
      starts_at: starts_at,
      ends_at: ends_at,
      created_by_id: Fabricate(:admin).id,
      **attrs,
    )
  end

  describe "validations" do
    it "requires ends_at to be after starts_at" do
      start = 1.day.from_now
      ballot =
        Ballotage::Ballot.new(
          title: "Bad Ballot",
          starts_at: start,
          ends_at: start - 1.minute,
          created_by_id: user.id,
        )

      expect(ballot).not_to be_valid
      expect(ballot.errors[:ends_at]).to be_present
    end

    it "requires ends_at to be strictly after starts_at, not merely equal" do
      now = Time.zone.now
      ballot =
        Ballotage::Ballot.new(
          title: "Equal times",
          starts_at: now,
          ends_at: now,
          created_by_id: user.id,
        )

      expect(ballot).not_to be_valid
    end

    it "is valid when ends_at is after starts_at" do
      ballot = build_ballot(starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      expect(ballot).to be_valid
    end

    it "requires a title" do
      ballot =
        Ballotage::Ballot.new(
          starts_at: 1.day.from_now,
          ends_at: 2.days.from_now,
          created_by_id: user.id,
        )
      expect(ballot).not_to be_valid
      expect(ballot.errors[:title]).to be_present
    end
  end

  describe "state transitions over time" do
    it "moves scheduled -> open -> ended as the clock advances" do
      base = freeze_time
      ballot = build_ballot(starts_at: base + 1.hour, ends_at: base + 2.hours)

      expect(ballot.state).to eq("scheduled")

      freeze_time(base + 90.minutes)
      expect(ballot.state).to eq("open")
      freeze_time(base + 3.hours)
      expect(ballot.state).to eq("ended")
    end

    it "is cancelled regardless of the clock once cancelled_at is set" do
      base = freeze_time
      ballot = build_ballot(starts_at: base + 1.hour, ends_at: base + 2.hours)
      ballot.update!(cancelled_at: Time.zone.now)

      expect(ballot.state).to eq("cancelled")

      freeze_time(base + 3.hours)
      expect(ballot.state).to eq("cancelled")
    end

    it "reports open?, over?, cancellable? and finalizable? consistently with state" do
      base = freeze_time
      ballot = build_ballot(starts_at: base + 1.hour, ends_at: base + 2.hours)
      expect(ballot.open?).to eq(false)
      expect(ballot.over?).to eq(false)
      expect(ballot.cancellable?).to eq(true)
      expect(ballot.finalizable?).to eq(false)

      freeze_time(base + 90.minutes)
      expect(ballot.open?).to eq(true)
      expect(ballot.over?).to eq(false)
      expect(ballot.cancellable?).to eq(true)
      expect(ballot.finalizable?).to eq(false)

      freeze_time(base + 3.hours)
      expect(ballot.open?).to eq(false)
      expect(ballot.over?).to eq(true)
      expect(ballot.cancellable?).to eq(false)
      expect(ballot.finalizable?).to eq(true)
    end
  end

  describe "#cast_vote!" do
    it "increments the right counter and records participation" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      ballot.cast_vote!(user, "black")
      ballot.reload

      expect(ballot.black_count).to eq(1)
      expect(ballot.white_count).to eq(0)
      expect(ballot.voted?(user)).to eq(true)
      expect(Ballotage::Participation.where(ballot_id: ballot.id, user_id: user.id).count).to eq(1)
    end

    it "increments white_count for a white vote" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      ballot.cast_vote!(user, "white")
      ballot.reload

      expect(ballot.white_count).to eq(1)
      expect(ballot.black_count).to eq(0)
    end

    it "raises AlreadyVoted on a second vote and leaves the counters unchanged" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(user, "black")

      expect { ballot.cast_vote!(user, "white") }.to raise_error(Ballotage::Ballot::AlreadyVoted)

      ballot.reload
      expect(ballot.black_count).to eq(1)
      expect(ballot.white_count).to eq(0)
      expect(Ballotage::Participation.where(ballot_id: ballot.id, user_id: user.id).count).to eq(1)
    end

    it "raises on an invalid choice" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)

      expect { ballot.cast_vote!(user, "purple") }.to raise_error(Discourse::InvalidParameters)
      ballot.reload
      expect(ballot.black_count).to eq(0)
      expect(ballot.white_count).to eq(0)
    end

    it "raises Discourse::InvalidAccess when the ballot is not open (scheduled)" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)

      expect { ballot.cast_vote!(user, "black") }.to raise_error(Discourse::InvalidAccess)
    end

    it "raises Discourse::InvalidAccess when the ballot has ended" do
      freeze_time
      ballot = build_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)

      expect { ballot.cast_vote!(user, "black") }.to raise_error(Discourse::InvalidAccess)
    end

    it "raises Discourse::InvalidAccess when the ballot was cancelled" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.update!(cancelled_at: Time.zone.now)

      expect { ballot.cast_vote!(user, "black") }.to raise_error(Discourse::InvalidAccess)
    end

    it "does not change updated_at when a vote is cast" do
      freeze_time
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      original_updated_at = ballot.reload.updated_at

      freeze_time(10.minutes.from_now)
      ballot.cast_vote!(user, "black")

      expect(ballot.reload.updated_at).to eq_time(original_updated_at)
    end
  end

  describe "#finalize!" do
    it "wipes counters and participations and sets finalized_at" do
      freeze_time
      ballot = build_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      ballot.update_columns(black_count: 3, white_count: 5)
      Ballotage::Participation.create!(ballot_id: ballot.id, user_id: user.id)

      ballot.finalize!
      ballot.reload

      expect(ballot.black_count).to eq(0)
      expect(ballot.white_count).to eq(0)
      expect(ballot.finalized_at).to be_within(1.second).of(Time.zone.now)
      expect(ballot.finalized?).to eq(true)
      expect(ballot.participations.count).to eq(0)
    end
  end

  describe ".active" do
    it "is empty when there is no scheduled or open ballot" do
      expect(Ballotage::Ballot.active).to be_empty
    end

    it "returns scheduled and open ballots, soonest first" do
      scheduled = build_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      open = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      expect(Ballotage::Ballot.active).to eq([open, scheduled])
    end

    it "excludes ended and cancelled ballots" do
      build_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      cancelled = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      cancelled.update!(cancelled_at: Time.zone.now)
      expect(Ballotage::Ballot.active).to be_empty
    end
  end

  describe ".pending_for" do
    fab!(:member, :user)

    it "returns open ballots the user has not voted in" do
      voted = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      pending = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      build_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      voted.cast_vote!(member, "white")

      expect(Ballotage::Ballot.pending_for(member)).to eq([pending])
    end
  end

  describe ".link_to_post" do
    fab!(:admin)
    fab!(:member) { Fabricate(:user, trust_level: TrustLevel[1], refresh_auto_groups: true) }

    before { SiteSetting.ballotage_enabled = true }

    def create_post(user, ballot)
      PostCreator.create!(
        user,
        title: "Ballot topic #{SecureRandom.hex(4)}",
        raw: "Please vote.\n\n[ballotage id=#{ballot.id}]\n[/ballotage]",
      )
    end

    it "links an embedded ballot to a manager's post, once" do
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      post = create_post(admin, ballot)
      expect(post.cooked).to include(%(data-ballot-id="#{ballot.id}"))
      expect(ballot.reload.post_id).to eq(post.id)

      create_post(admin, ballot)
      expect(ballot.reload.post_id).to eq(post.id)
    end

    it "flags the topic so topic lists can mark it" do
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      post = create_post(admin, ballot)

      expect(post.topic.reload.custom_fields["ballotage"]).to eq(true)
    end

    it "ignores posts by members who cannot manage ballots" do
      ballot = build_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create_post(member, ballot)
      expect(ballot.reload.post_id).to be_nil
    end
  end
end
