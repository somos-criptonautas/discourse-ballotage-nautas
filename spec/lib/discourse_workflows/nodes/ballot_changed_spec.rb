# frozen_string_literal: true

RSpec.describe DiscourseWorkflows::Nodes::BallotChanged::V1, discourse_workflows: true do
  fab!(:admin)
  fab!(:voting_group, :group)
  fab!(:voter) { Fabricate(:user, group_ids: [voting_group.id]) }
  fab!(:candidate, :user)
  fab!(:category)
  fab!(:other_category, :category)
  fab!(:tag)
  fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
  fab!(:post) { Fabricate(:post, topic: topic) }

  before do
    SiteSetting.ballotage_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.ballotage_voting_group = voting_group.id.to_s
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

  def trigger_context(parameters)
    DiscourseWorkflows::TriggerNodeContext.new({ "parameters" => parameters.deep_stringify_keys })
  end

  def publish_trigger_workflow(**parameters)
    graph =
      build_workflow_graph do |builder|
        builder.node "ballot", described_class.identifier, parameters: parameters
      end
    Fabricate(:discourse_workflows_workflow, created_by: admin, published: true, **graph)
  end

  def dispatched
    Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs.map { |job| job["args"].first["trigger_data"] }
  end

  describe "#matches?" do
    it "filters changes, kinds, outcomes, categories and tags" do
      freeze_time
      ballot = create_ballot(post: post, ends_at: 1.minute.ago, starts_at: 1.hour.ago)
      ballot.close!
      trigger = described_class.from_event(:ballotage_ballot_closed, ballot.reload)

      expect(trigger.matches?(trigger_context({}))).to eq(true)
      expect(trigger.matches?(trigger_context(changes: ["opened"]))).to eq(false)
      expect(trigger.matches?(trigger_context(kinds: ["proposal"]))).to eq(false)
      expect(trigger.matches?(trigger_context(outcomes: ["rejected"]))).to eq(false)
      expect(trigger.matches?(trigger_context(category_ids: [other_category.id]))).to eq(false)
      expect(trigger.matches?(trigger_context(tag_names: ["missing"]))).to eq(false)
      expect(
        trigger.matches?(
          trigger_context(
            changes: ["closed"],
            kinds: ["admission"],
            outcomes: [ballot.outcome],
            category_ids: [category.id],
            tag_names: [tag.name],
          ),
        ),
      ).to eq(true)
    end

    it "only matches a ballot without a post when no topic filter is set" do
      trigger = described_class.from_event(:ballotage_ballot_created, create_ballot)

      expect(trigger.matches?(trigger_context({}))).to eq(true)
      expect(trigger.matches?(trigger_context(category_ids: [category.id]))).to eq(false)
      expect(trigger.matches?(trigger_context(tag_names: [tag.name]))).to eq(false)
    end

    it "doesn't match an outcome filter before the ballot has one" do
      trigger = described_class.from_event(:ballotage_ballot_opened, create_ballot)

      expect(trigger.matches?(trigger_context(outcomes: ["approved"]))).to eq(false)
    end
  end

  describe "#valid?" do
    it "rejects events that aren't ballot changes" do
      expect(described_class.from_event(:ballotage_ballot_voted, create_ballot)).not_to be_valid
    end
  end

  describe "event dispatch" do
    it "dispatches each lifecycle change with an output matching the schema" do
      publish_trigger_workflow
      freeze_time

      ballot =
        Ballotage::BallotCreator.create!(
          admin,
          title: "Ana",
          start_date: Date.current.iso8601,
          start_time: "00:00",
          end_date: 2.days.from_now.to_date.iso8601,
          subject_username: candidate.username,
        )
      ballot.update_columns(starts_at: 1.hour.ago, ends_at: 2.hours.from_now)
      ballot.notify_opened!
      ballot.notify_reminder!
      ballot.cast_vote!(voter, "white")
      ballot.update_columns(ends_at: 1.minute.ago)
      ballot.close!
      ballot.finalize!

      expect(dispatched.pluck("change")).to eq(%w[created opened closing_soon closed finalized])
      expect(dispatched).to all(match_node_output_schema(described_class))
      closed = dispatched.find { |data| data["change"] == "closed" }
      expect(closed.dig("ballot", "outcome")).to eq("approved")
      expect(closed.dig("ballot", "closed_voter_count")).to eq(1)
      expect(closed.dig("candidate", "username")).to eq(candidate.username)
    end

    it "dispatches cancellation" do
      publish_trigger_workflow(changes: ["cancelled"])
      ballot = create_ballot

      ballot.cancel!

      expect(dispatched.pluck("change")).to eq(["cancelled"])
    end

    it "never puts unpublished counts on the item" do
      publish_trigger_workflow(changes: ["closed"])
      freeze_time
      ballot = create_ballot(result_visibility: "outcome")
      ballot.cast_vote!(voter, "black")
      ballot.update_columns(ends_at: 1.minute.ago)

      ballot.close!

      data = dispatched.sole
      expect(data.dig("ballot", "outcome")).to eq("rejected")
      expect(data["ballot"].keys).not_to include("black_count", "white_count", "abstain_count")
    end

    it "includes published counts once the ballot has ended" do
      publish_trigger_workflow(changes: ["closed"])
      freeze_time
      ballot = create_ballot(kind: "proposal", result_visibility: "counts")
      ballot.cast_vote!(voter, "white")
      ballot.update_columns(ends_at: 1.minute.ago)

      ballot.close!

      expect(dispatched.sole["ballot"]).to include("white_count" => 1, "black_count" => 0)
    end

    it "stops dispatching when ballots are disabled" do
      publish_trigger_workflow
      ballot = create_ballot
      SiteSetting.ballotage_enabled = false

      ballot.trigger_event("cancelled")

      expect(Jobs::DiscourseWorkflows::ExecuteWorkflow.jobs).to be_empty
      expect(DiscourseWorkflows::Registry.find_node_type(described_class.identifier)).to be_nil
    end
  end
end
