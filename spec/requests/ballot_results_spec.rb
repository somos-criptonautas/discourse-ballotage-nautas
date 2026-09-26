# frozen_string_literal: true

RSpec.describe Ballotage::BallotsController do
  fab!(:voting_group, :group)
  fab!(:voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:reader, :user)
  fab!(:admin)

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
    SiteSetting.ballotage_timezone = "Europe/Berlin"
  end

  def ended_ballot(**attrs)
    ballot =
      Ballotage::Ballot.create!(
        title: "Proposal: chat",
        kind: "proposal",
        starts_at: 2.hours.ago,
        ends_at: 1.hour.from_now,
        created_by_id: admin.id,
        **attrs,
      )
    ballot.cast_vote!(voter, "white")
    post = Fabricate(:post, user: admin)
    ballot.update_columns(ends_at: 1.minute.ago, post_id: post.id)
    ballot
  end

  describe "POST /ballotage/ballots.json" do
    def create(params)
      post "/ballotage/ballots.json",
           params: {
             title: "Ballot",
             start_date: 2.days.from_now.strftime("%Y-%m-%d"),
             end_date: 3.days.from_now.strftime("%Y-%m-%d"),
           }.merge(params)
    end

    before { sign_in(admin) }

    it "defaults a proposal to publishing and keeping its counts" do
      create(kind: "proposal")

      ballot = Ballotage::Ballot.last
      expect(response.status).to eq(201)
      expect(ballot.result_visibility).to eq("counts")
      expect(ballot.keep_counts).to eq(true)
      expect(response.parsed_body["ballot"]["choices"]).to eq(%w[white black abstain])
    end

    it "defaults an admission to publishing only its outcome" do
      create(rejection_threshold: "2")

      ballot = Ballotage::Ballot.last
      expect(ballot.result_visibility).to eq("outcome")
      expect(ballot.rejection_threshold).to eq(2)
    end

    it "rejects unknown rules" do
      create(approval_rule: "whatever")
      expect(response.status).to eq(422)

      create(quorum_percent: "lots")
      expect(response.status).to eq(400)
    end

    it "records the action in the staff action log" do
      create({})
      expect(UserHistory.where(custom_type: "ballotage_create", acting_user_id: admin.id)).to exist
    end
  end

  describe "GET /ballotage/ballots/:id.json for readers outside the ballot" do
    it "shows the published outcome, without counts, once ended" do
      ballot = ended_ballot(result_visibility: "outcome")
      sign_in(reader)

      get "/ballotage/ballots/#{ballot.id}.json"

      json = response.parsed_body["ballot"]
      expect(json["outcome"]).to eq("approved")
      expect(json["closed_voter_count"]).to eq(1)
      expect(json).not_to have_key("white_count")
      expect(json).not_to have_key("voters")
    end

    it "includes the counts when the ballot publishes them" do
      ballot = ended_ballot(result_visibility: "counts")
      sign_in(reader)

      get "/ballotage/ballots/#{ballot.id}.json"

      expect(response.parsed_body["ballot"]["white_count"]).to eq(1)
    end

    it "serves anonymous visitors of a public topic" do
      ballot = ended_ballot(result_visibility: "outcome")

      get "/ballotage/ballots/#{ballot.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body["ballot"]["outcome"]).to eq("approved")
    end

    it "stays hidden while running, for overseer-only results, and for unreadable posts" do
      sign_in(reader)

      running = ended_ballot(result_visibility: "outcome")
      running.update_columns(ends_at: 1.hour.from_now, closed_at: nil)
      get "/ballotage/ballots/#{running.id}.json"
      expect(response.status).to eq(404)

      private_result = ended_ballot(result_visibility: "overseers")
      get "/ballotage/ballots/#{private_result.id}.json"
      expect(response.status).to eq(404)

      hidden = ended_ballot(result_visibility: "outcome")
      hidden.post.topic.update!(category: Fabricate(:private_category, group: Fabricate(:group)))
      get "/ballotage/ballots/#{hidden.id}.json"
      expect(response.status).to eq(404)
    end
  end

  describe "POST /ballotage/vote.json" do
    it "accepts an abstention on a proposal" do
      ballot =
        Ballotage::Ballot.create!(
          title: "Proposal",
          kind: "proposal",
          starts_at: 1.hour.ago,
          ends_at: 1.hour.from_now,
          created_by_id: admin.id,
        )
      sign_in(voter)

      post "/ballotage/vote.json", params: { ballot_id: ballot.id, choice: "abstain" }

      expect(response.status).to eq(200)
      expect(ballot.reload.abstain_count).to eq(1)
    end
  end
end
