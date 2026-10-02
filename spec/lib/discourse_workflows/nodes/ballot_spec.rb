# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::Ballot::V1, discourse_workflows: true do
  fab!(:admin)
  fab!(:voting_group, :group)
  fab!(:oversight_group, :group)
  fab!(:voter) { Fabricate(:user, username: "voter", group_ids: [voting_group.id]) }
  fab!(:overseer) { Fabricate(:user, group_ids: [oversight_group.id]) }
  fab!(:candidate, :user)
  fab!(:topic)
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
    SiteSetting.ballotage_oversight_group = oversight_group.id.to_s
  end

  def create_ballot(**attrs)
    Ballotage::Ballot.create!(
      title: "Ana",
      starts_at: 1.hour.ago,
      ends_at: 1.hour.from_now,
      created_by_id: admin.id,
      **attrs,
    )
  end

  def run(configuration)
    execute_node_output(configuration: configuration.deep_stringify_keys).first.map do |item|
      item["json"]
    end
  end

  def run_one(configuration)
    run(configuration).sole
  end

  def create_configuration(**overrides)
    {
      operation: "create",
      title: "Ana",
      kind: "admission",
      start_date: 1.day.from_now.to_date.iso8601,
      end_date: 3.days.from_now.to_date.iso8601,
      **overrides,
    }
  end

  describe "create" do
    it "creates a ballot with a candidate and logs it" do
      data = run_one(create_configuration(candidate_username: candidate.username))

      ballot = Ballotage::Ballot.find(data.dig("ballot", "id"))
      expect(ballot.subject_user).to eq(candidate)
      expect(ballot.created_by_id).to eq(Discourse.system_user.id)
      expect(ballot.result_visibility).to eq("outcome")
      expect(data.dig("candidate", "username")).to eq(candidate.username)
      expect(data).to match_node_output_schema(
        described_class,
        configuration: {
          "operation" => "create",
        },
      )
      expect(UserHistory.where(custom_type: "ballotage_create").count).to eq(1)
    end

    it "posts the ballot as a reply in the topic and links it" do
      data = run_one(create_configuration(topic_id: topic.id, intro: "Please vote on Ana."))

      ballot = Ballotage::Ballot.find(data.dig("ballot", "id"))
      expect(ballot.post.topic).to eq(topic)
      expect(ballot.post.raw).to eq(
        "Please vote on Ana.\n\n[ballotage id=#{ballot.id}]\n[/ballotage]",
      )
      expect(topic.reload.custom_fields["ballotage"]).to eq(true)
      expect(data.dig("topic", "id")).to eq(topic.id)
      expect(data.dig("post", "id")).to eq(ballot.post_id)
    end

    it "reports invalid input as a node error" do
      expect { run(create_configuration(start_date: "2026-02-30")) }.to raise_error(
        DiscourseWorkflows::NodeError,
        /date/,
      )
      expect {
        run(create_configuration(kind: "proposal", candidate_username: "x"))
      }.to raise_error(DiscourseWorkflows::NodeError)
      expect(Ballotage::Ballot.count).to eq(0)
    end

    it "refuses an actor who can't manage ballots" do
      expect { run(create_configuration(actor_username: overseer.username)) }.to raise_error(
        DiscourseWorkflows::NodeError,
        /#{overseer.username}/,
      )
      expect(Ballotage::Ballot.count).to eq(0)
    end
  end

  describe "get" do
    it "returns the ballot without counts while it runs" do
      ballot = create_ballot
      ballot.cast_vote!(voter, "black")

      data = run_one(operation: "get", ballot_id: ballot.id, actor_username: overseer.username)

      expect(data["ballot"]).to include("id" => ballot.id, "state" => "open", "voter_count" => 1)
      expect(data["ballot"].keys).not_to include("black_count", "white_count")
    end

    it "closes an ended ballot on read so the outcome is there" do
      freeze_time
      ballot = create_ballot
      ballot.cast_vote!(voter, "white")
      ballot.update_columns(ends_at: 1.minute.ago)

      data = run_one(operation: "get", ballot_id: ballot.id)

      expect(data.dig("ballot", "outcome")).to eq("approved")
    end

    it "reports a missing ballot" do
      expect { run(operation: "get", ballot_id: 0) }.to raise_error(
        DiscourseWorkflows::NodeError,
        /0/,
      )
    end

    it "refuses an actor who can't oversee ballots" do
      ballot = create_ballot

      expect { run(operation: "get", ballot_id: ballot.id, actor_username: voter.username) }.to(
        raise_error(DiscourseWorkflows::NodeError),
      )
    end
  end

  describe "list" do
    it "lists ballots filtered by state, newest first" do
      freeze_time
      open = create_ballot
      scheduled = create_ballot(starts_at: 1.day.from_now, ends_at: 2.days.from_now)
      cancelled = create_ballot(starts_at: 2.hours.ago)
      cancelled.cancel!

      expect(run(operation: "list").map { |d| d.dig("ballot", "id") }).to eq(
        [scheduled.id, open.id, cancelled.id],
      )
      expect(
        run(operation: "list", states: %w[open cancelled]).map { |d| d.dig("ballot", "id") },
      ).to eq([open.id, cancelled.id])
      expect(run(operation: "list", limit: 1).size).to eq(1)
    end
  end

  describe "cancel and finalize" do
    it "cancels, then finalizes, logging both" do
      ballot = create_ballot
      ballot.cast_vote!(voter, "black")

      cancelled = run_one(operation: "cancel", ballot_id: ballot.id)
      expect(cancelled.dig("ballot", "state")).to eq("cancelled")
      expect(ballot.reload.black_count).to eq(0)

      finalized = run_one(operation: "finalize", ballot_id: ballot.id)
      expect(finalized.dig("ballot", "finalized")).to eq(true)
      expect(finalized.dig("ballot", "voter_count")).to be_nil
      expect(ballot.participations.count).to eq(0)
      expect(UserHistory.where(custom_type: %w[ballotage_cancel ballotage_finalize]).count).to eq(2)
    end

    it "reports a step that isn't allowed in the current state" do
      ballot = create_ballot

      expect { run(operation: "finalize", ballot_id: ballot.id) }.to raise_error(
        DiscourseWorkflows::NodeError,
        /finalized/,
      )
    end
  end

  describe "operations" do
    it "doesn't offer a list of who hasn't voted, which would outlive finalizing" do
      expect(described_class::OPERATIONS).not_to include("non_voters")
      expect { run(operation: "non_voters", ballot_id: create_ballot.id) }.to raise_error(
        DiscourseWorkflows::NodeError,
      )
    end
  end
end
