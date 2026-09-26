# frozen_string_literal: true

RSpec.describe Ballotage::BallotsController do
  fab!(:voting_group, :group)
  fab!(:oversight_group, :group)
  fab!(:voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:other_voter) { Fabricate(:user, username: "avoter", group_ids: [voting_group.id]) }
  fab!(:overseer) { Fabricate(:user, group_ids: [oversight_group.id]) }
  fab!(:plain_user, :user)
  fab!(:admin)

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
    SiteSetting.ballotage_oversight_group = oversight_group.id.to_s
  end

  def create_ballot(starts_at:, ends_at:, **attrs)
    Ballotage::Ballot.create!(
      title: "Test Ballot",
      starts_at: starts_at,
      ends_at: ends_at,
      created_by_id: admin.id,
      **attrs,
    )
  end

  describe "GET /ballotage" do
    it "returns 200 HTML for a logged in user" do
      sign_in(plain_user)
      get "/ballotage"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end

  describe "GET /ballotage/current.json" do
    it "returns the info text when set and null when empty" do
      sign_in(voter)

      get "/ballotage/current.json"
      expect(response.parsed_body["info_text"]).to be_nil

      SiteSetting.ballotage_info_text = "Only members may vote."
      get "/ballotage/current.json"
      expect(response.parsed_body["info_text"]).to eq("Only members may vote.")
    end

    it "shows the ballot to a voter, with has_voted false before voting" do
      freeze_time
      create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(voter)

      get "/ballotage/current.json"

      json = response.parsed_body
      expect(json["can_vote"]).to eq(true)
      expect(json["ballots"].size).to eq(1)
      expect(json["ballots"].first["has_voted"]).to eq(false)
    end

    it "reflects has_voted true after voting" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(voter, "black")
      sign_in(voter)

      get "/ballotage/current.json"

      expect(response.parsed_body["ballots"].first["has_voted"]).to eq(true)
    end

    it "hides the ballot from a user who is neither a voter nor an overseer" do
      freeze_time
      create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(plain_user)

      get "/ballotage/current.json"

      json = response.parsed_body
      expect(json["can_vote"]).to eq(false)
      expect(json["ballots"]).to eq([])
    end

    it "shows the ballot to an overseer who cannot vote, without has_voted being true" do
      freeze_time
      create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(overseer)

      get "/ballotage/current.json"

      json = response.parsed_body
      expect(json["can_oversee"]).to eq(true)
      expect(json["ballots"].first["has_voted"]).to eq(false)
      expect(json["ballots"].first["voter_count"]).to eq(0)
    end

    it "lists several scheduled or open ballots, soonest first" do
      freeze_time
      later = create_ballot(starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      open = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      create_ballot(starts_at: 3.hours.ago, ends_at: 2.hours.ago)
      sign_in(voter)

      get "/ballotage/current.json"

      expect(response.parsed_body["ballots"].map { |b| b["id"] }).to eq([open.id, later.id])
    end
  end

  describe "GET /ballotage/ballots/:id.json" do
    fab!(:ballot) do
      Ballotage::Ballot.create!(
        title: "Embedded",
        starts_at: 1.hour.ago,
        ends_at: 1.hour.from_now,
        created_by_id: Discourse.system_user.id,
      )
    end

    it "returns 404 to a member who can neither vote nor oversee" do
      sign_in(plain_user)
      get "/ballotage/ballots/#{ballot.id}.json"
      expect(response.status).to eq(404)
    end

    it "gives a voter has_voted but no participation or counts" do
      ballot.cast_vote!(other_voter, "white")
      sign_in(voter)

      get "/ballotage/ballots/#{ballot.id}.json"

      json = response.parsed_body["ballot"]
      expect(json["can_vote"]).to eq(true)
      expect(json["has_voted"]).to eq(false)
      expect(json).not_to have_key("voter_count")
      expect(json).not_to have_key("voters")
      expect(json).not_to have_key("white_count")
    end

    it "gives an overseer participation but no counts while open" do
      ballot.cast_vote!(voter, "black")
      sign_in(overseer)

      get "/ballotage/ballots/#{ballot.id}.json"

      json = response.parsed_body["ballot"]
      expect(json["voter_count"]).to eq(1)
      expect(json["eligible_count"]).to eq(2)
      expect(json).not_to have_key("black_count")
    end

    it "includes the linked post's url only for viewers who can see it" do
      post = Fabricate(:post, user: admin, raw: "[ballotage id=#{ballot.id}]\n[/ballotage]")
      ballot.update!(post_id: post.id)
      sign_in(voter)

      get "/ballotage/ballots/#{ballot.id}.json"
      expect(response.parsed_body["ballot"]["post_url"]).to eq(post.url)

      post.topic.update!(category: Fabricate(:private_category, group: Fabricate(:group)))
      get "/ballotage/ballots/#{ballot.id}.json"
      expect(response.parsed_body["ballot"]["post_url"]).to be_nil
    end
  end

  describe "POST /ballotage/vote.json" do
    it "records a vote and never echoes the choice back" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(voter)

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "black" }

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["ballot"]["has_voted"]).to eq(true)
      expect(json["ballot"]).not_to have_key("choice")
      expect(json["ballot"]).not_to have_key("black_count")
      expect(json["ballot"]).not_to have_key("white_count")
      expect(ballot.reload.black_count).to eq(1)
    end

    it "returns 400, not 500, for a non-scalar ballot_id" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(voter)

      post "/ballotage/vote.json", params: { ballot_id: [ballot.id], choice: "black" }

      expect(response.status).to eq(400)
      expect(ballot.reload.black_count).to eq(0)
    end

    it "rejects a second vote with 422" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(voter)
      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "black" }

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "white" }

      expect(response.status).to eq(422)
      expect(ballot.reload.black_count).to eq(1)
      expect(ballot.reload.white_count).to eq(0)
    end

    it "returns 403 for a user outside the voting group" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(plain_user)

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "black" }

      expect(response.status).to eq(403)
    end

    it "returns 422 when voting before the ballot has started" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      sign_in(voter)

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "black" }

      expect(response.status).to eq(422)
    end

    it "returns 422 when voting after the ballot was cancelled" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.update!(cancelled_at: Time.zone.now)
      sign_in(voter)

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "black" }

      expect(response.status).to eq(422)
    end
  end

  describe "GET /ballotage/ballots.json" do
    it "returns 403 for a plain user" do
      sign_in(plain_user)
      get "/ballotage/ballots.json"
      expect(response.status).to eq(403)
    end

    it "shows participation but no black/white counts while the ballot is open" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(voter, "black")
      sign_in(overseer)

      get "/ballotage/ballots.json"

      entry = response.parsed_body["ballots"].first
      expect(entry["voter_count"]).to eq(1)
      expect(entry).not_to have_key("black_count")
      expect(entry).not_to have_key("white_count")
    end

    it "shows black/white counts once the ballot has ended" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      Ballotage::Participation.create!(ballot_id: ballot.id, user_id: voter.id)
      ballot.update_columns(black_count: 1, white_count: 0)
      sign_in(overseer)

      get "/ballotage/ballots.json"

      entry = response.parsed_body["ballots"].first
      expect(entry["black_count"]).to eq(1)
      expect(entry["white_count"]).to eq(0)
    end

    it "shows black/white counts once the ballot has been cancelled" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.update!(cancelled_at: Time.zone.now)
      sign_in(overseer)

      get "/ballotage/ballots.json"

      entry = response.parsed_body["ballots"].first
      expect(entry).to have_key("black_count")
      expect(entry).to have_key("white_count")
    end

    it "lists voters sorted by username and never includes a choice" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(voter, "black")
      ballot.cast_vote!(other_voter, "white")
      sign_in(overseer)

      get "/ballotage/ballots.json"

      voters = response.parsed_body["ballots"].first["voters"]
      expect(voters.map { |v| v["username"] }).to eq([other_voter.username, voter.username].sort)
      voters.each { |v| expect(v.keys).to match_array(%w[id username name]) }
    end

    it "keeps a deleted user's participation in voter_count so it matches the tally" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(voter, "black")
      ballot.cast_vote!(other_voter, "white")
      UserDestroyer.new(Discourse.system_user).destroy(other_voter)
      freeze_time 2.hours.from_now
      sign_in(admin)

      get "/ballotage/ballots.json"

      json = response.parsed_body["ballots"].first
      expect(json["voter_count"]).to eq(2)
      expect(json["voters"].map { |v| v["id"] }).to eq([voter.id])
      expect(json["black_count"] + json["white_count"]).to eq(2)
    end

    it "omits voters, voter_count and counts for a finalized ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      Ballotage::Participation.create!(ballot_id: ballot.id, user_id: voter.id)
      ballot.update_columns(black_count: 1, white_count: 0)
      ballot.finalize!
      sign_in(overseer)

      get "/ballotage/ballots.json"

      entry = response.parsed_body["ballots"].first
      expect(entry["finalized"]).to eq(true)
      %w[voters voter_count black_count white_count].each do |key|
        expect(entry).not_to have_key(key)
      end
    end
  end

  describe "POST /ballotage/ballots.json (create)" do
    before { SiteSetting.ballotage_timezone = "Europe/Berlin" }

    def start_date
      8.days.from_now.strftime("%Y-%m-%d")
    end

    def end_date
      9.days.from_now.strftime("%Y-%m-%d")
    end

    it "allows an admin to create a ballot" do
      freeze_time
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Spring Ballot",
             start_date: start_date,
             end_date: end_date,
           }

      expect(response.status).to eq(201)
    end

    it "defaults start and end times to 00:01 and 23:59 in the configured time zone" do
      freeze_time
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Spring Ballot",
             start_date: start_date,
             end_date: end_date,
           }

      ballot = Ballotage::Ballot.last
      expect(ballot.starts_at).to eq_time(
        ActiveSupport::TimeZone["Europe/Berlin"].parse("#{start_date} 00:01"),
      )
      expect(ballot.ends_at).to eq_time(
        ActiveSupport::TimeZone["Europe/Berlin"].parse("#{end_date} 23:59"),
      )
    end

    it "accepts custom start and end times" do
      freeze_time
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Spring Ballot",
             start_date: start_date,
             start_time: "09:30",
             end_date: end_date,
             end_time: "18:15",
           }

      ballot = Ballotage::Ballot.last
      expect(ballot.starts_at).to eq_time(
        ActiveSupport::TimeZone["Europe/Berlin"].parse("#{start_date} 09:30"),
      )
      expect(ballot.ends_at).to eq_time(
        ActiveSupport::TimeZone["Europe/Berlin"].parse("#{end_date} 18:15"),
      )
    end

    %w[2026-13-01 2026-00-01 2026-01-00 2026-02-31].each do |bad_date|
      it "returns 400 and creates nothing for the impossible date #{bad_date}" do
        freeze_time Time.utc(2026, 1, 1)
        sign_in(admin)

        post "/ballotage/ballots.json",
             params: {
               title: "Bad",
               start_date: bad_date,
               end_date: "2026-12-31",
             }

        expect(response.status).to eq(400)
        expect(Ballotage::Ballot.count).to eq(0)
      end
    end

    it "returns 400 for an impossible time" do
      freeze_time
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Bad",
             start_date: start_date,
             end_date: end_date,
             end_time: "24:00",
           }

      expect(response.status).to eq(400)
    end

    it "allows a second ballot while one is scheduled or open" do
      freeze_time
      create_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Second Ballot",
             start_date: start_date,
             end_date: end_date,
           }

      expect(response.status).to eq(201)
      expect(response.parsed_body["ballot"]["title"]).to eq("Second Ballot")
      expect(Ballotage::Ballot.count).to eq(2)
    end

    it "returns 422 when the end date/time is in the past" do
      freeze_time
      sign_in(admin)

      post "/ballotage/ballots.json",
           params: {
             title: "Late Ballot",
             start_date: 2.days.ago.strftime("%Y-%m-%d"),
             end_date: 1.day.ago.strftime("%Y-%m-%d"),
           }

      expect(response.status).to eq(422)
    end

    it "returns 403 for an oversight group member when ballotage_oversight_can_manage is disabled" do
      SiteSetting.ballotage_oversight_can_manage = false
      sign_in(overseer)

      post "/ballotage/ballots.json",
           params: {
             title: "Spring Ballot",
             start_date: start_date,
             end_date: end_date,
           }

      expect(response.status).to eq(403)
    end

    it "allows an oversight group member to create a ballot when ballotage_oversight_can_manage is enabled" do
      freeze_time
      SiteSetting.ballotage_oversight_can_manage = true
      sign_in(overseer)

      post "/ballotage/ballots.json",
           params: {
             title: "Spring Ballot",
             start_date: start_date,
             end_date: end_date,
           }

      expect(response.status).to eq(201)
    end
  end

  describe "POST /ballotage/ballots/:id/cancel.json" do
    it "cancels a scheduled ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.from_now, ends_at: 2.hours.from_now)
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/cancel.json"

      expect(response.status).to eq(200)
      expect(ballot.reload.state).to eq("cancelled")
    end

    it "cancels an open ballot and keeps votes already cast" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      ballot.cast_vote!(voter, "black")
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/cancel.json"

      expect(response.status).to eq(200)
      ballot.reload
      expect(ballot.state).to eq("cancelled")
      expect(ballot.black_count).to eq(1)
      expect(ballot.participations.count).to eq(1)
    end

    it "returns 422 for an ended ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/cancel.json"

      expect(response.status).to eq(422)
    end
  end

  describe "POST /ballotage/ballots/:id/finalize.json" do
    it "finalizes an ended ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      Ballotage::Participation.create!(ballot_id: ballot.id, user_id: voter.id)
      ballot.update_columns(black_count: 1, white_count: 0)
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/finalize.json"

      expect(response.status).to eq(200)
      ballot.reload
      expect(ballot.finalized?).to eq(true)
      expect(ballot.black_count).to eq(0)
      expect(ballot.white_count).to eq(0)
      expect(ballot.participations.count).to eq(0)
    end

    it "returns 422 for an open ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/finalize.json"

      expect(response.status).to eq(422)
    end

    it "finalizes a cancelled ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
      ballot.update!(cancelled_at: Time.zone.now)
      sign_in(admin)

      post "/ballotage/ballots/#{ballot.id}/finalize.json"

      expect(response.status).to eq(200)
      expect(ballot.reload.finalized?).to eq(true)
    end
  end

  describe "DELETE /ballotage/ballots/:id.json" do
    it "deletes a finalized ballot entirely" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      ballot.finalize!
      sign_in(admin)

      delete "/ballotage/ballots/#{ballot.id}.json"

      expect(response.status).to eq(200)
      expect(Ballotage::Ballot.exists?(ballot.id)).to eq(false)
    end

    it "refuses an ended ballot that has not been finalized, keeping its result" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      Ballotage::Participation.create!(ballot_id: ballot.id, user_id: voter.id)
      ballot.update_columns(black_count: 1)
      sign_in(admin)

      delete "/ballotage/ballots/#{ballot.id}.json"

      expect(response.status).to eq(422)
      expect(ballot.reload.black_count).to eq(1)
      expect(ballot.participations.count).to eq(1)
    end

    it "refuses an open ballot" do
      freeze_time
      ballot = create_ballot(starts_at: 1.hour.ago, ends_at: 1.hour.from_now)
      sign_in(admin)

      delete "/ballotage/ballots/#{ballot.id}.json"

      expect(response.status).to eq(422)
      expect(Ballotage::Ballot.exists?(ballot.id)).to eq(true)
    end

    it "returns 403 for an oversight member without manage rights" do
      freeze_time
      ballot = create_ballot(starts_at: 2.hours.ago, ends_at: 1.hour.ago)
      ballot.finalize!
      sign_in(overseer)

      delete "/ballotage/ballots/#{ballot.id}.json"

      expect(response.status).to eq(403)
      expect(Ballotage::Ballot.exists?(ballot.id)).to eq(true)
    end
  end

  describe "GET /ballotage/ballots.json ordering" do
    it "lists the active ballot first, then newest start first, newest created on ties" do
      freeze_time
      same_start = 1.hour.ago
      cancelled = create_ballot(starts_at: same_start, ends_at: 2.days.from_now)
      cancelled.update!(cancelled_at: Time.zone.now)
      older = create_ballot(starts_at: 5.days.ago, ends_at: 4.days.ago)
      open = create_ballot(starts_at: same_start, ends_at: 3.days.from_now)
      later_cancelled = create_ballot(starts_at: same_start, ends_at: 2.days.from_now)
      later_cancelled.update!(cancelled_at: Time.zone.now)
      sign_in(admin)

      get "/ballotage/ballots.json"

      ids = response.parsed_body["ballots"].map { |b| b["id"] }
      expect(ids).to eq([open.id, later_cancelled.id, cancelled.id, older.id])
    end
  end

  describe "ballot JSON" do
    it "marks only finalized ballots as deletable" do
      freeze_time
      ended = create_ballot(starts_at: 3.hours.ago, ends_at: 2.hours.ago)
      finalized = create_ballot(starts_at: 5.hours.ago, ends_at: 4.hours.ago)
      finalized.finalize!
      sign_in(admin)

      get "/ballotage/ballots.json"

      by_id = response.parsed_body["ballots"].index_by { |b| b["id"] }
      expect(by_id[ended.id]["deletable"]).to eq(false)
      expect(by_id[finalized.id]["deletable"]).to eq(true)
    end
  end
end
