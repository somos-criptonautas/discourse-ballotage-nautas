# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module Ballot
        # What the ballot nodes put on an item. Holds the same secrecy line as
        # the web UI: participation is a number, never a list of names, and the
        # counts appear only once an ended ballot publishes them.
        module Payload
          BALLOT_PROPERTIES = JSON.parse(<<~JSON).freeze
            {
              "id": { "type": "integer" },
              "title": { "type": "string" },
              "kind": { "type": "string", "enum": ["admission", "proposal"] },
              "state": { "type": "string", "enum": ["scheduled", "open", "ended", "cancelled"] },
              "finalized": { "type": "boolean" },
              "url": { "type": "string" },
              "starts_at": { "type": "string", "format": "date-time" },
              "ends_at": { "type": "string", "format": "date-time" },
              "rejection_threshold": { "type": "integer" },
              "rejection_percent": { "type": ["integer", "null"] },
              "approval_rule": { "type": "string" },
              "quorum_percent": { "type": ["integer", "null"] },
              "result_visibility": { "type": "string", "enum": ["overseers", "outcome", "counts"] },
              "outcome": {
                "type": ["string", "null"],
                "enum": ["approved", "rejected", "no_quorum", null],
                "description": "Set once the ballot has closed"
              },
              "voter_count": {
                "type": ["integer", "null"],
                "description": "Members who have voted; null once finalized"
              },
              "eligible_count": { "type": ["integer", "null"] },
              "closed_voter_count": { "type": ["integer", "null"] },
              "closed_eligible_count": { "type": ["integer", "null"] },
              "black_count": {
                "type": "integer",
                "description": "Only when the ended ballot publishes its counts"
              },
              "white_count": {
                "type": "integer",
                "description": "Only when the ended ballot publishes its counts"
              },
              "abstain_count": {
                "type": "integer",
                "description": "Only when the ended ballot publishes its counts"
              }
            }
          JSON

          SCHEMA =
            DiscourseWorkflows::Schema.merge(
              DiscourseWorkflows::Schema.entity(
                "ballot",
                BALLOT_PROPERTIES,
                "Secret ballot (discourse-ballotage-nautas)",
              ),
              DiscourseWorkflows::Schema.entity(
                "candidate",
                DiscourseWorkflows::Schema::BASIC_USER_PROPERTIES,
                "The member an admission ballot is about, when set",
              ),
              DiscourseWorkflows::Schema::TOPIC_LIST_ITEM_SCHEMA,
              DiscourseWorkflows::Schema::POST_SCHEMA,
            ).freeze

          private

          # topic and post only when the ballot is embedded in one, candidate
          # only when set.
          def ballot_item(ballot)
            # Freezes the outcome when the ballot has ended but the job hasn't
            # run yet, like the web UI does on the first view.
            ballot.close! if ballot.closed_at.nil? && ballot.state == "ended"
            post = ballot.post
            {
              ballot: ballot_data(ballot),
              candidate: (serialize_user(ballot.subject_user) if ballot.subject_user),
              topic: (topic_data(post.topic) if post&.topic),
              post: (serialize_post(post) if post),
            }.compact
          end

          def ballot_data(ballot)
            data = {
              id: ballot.id,
              title: ballot.title,
              kind: ballot.kind,
              state: ballot.state,
              finalized: ballot.finalized?,
              url: ballot.post&.full_url || "#{Discourse.base_url}/ballotage",
              starts_at: ballot.starts_at.iso8601,
              ends_at: ballot.ends_at.iso8601,
              rejection_threshold: ballot.rejection_threshold,
              rejection_percent: ballot.rejection_percent,
              approval_rule: ballot.approval_rule,
              quorum_percent: ballot.quorum_percent,
              result_visibility: ballot.result_visibility,
              outcome: ballot.outcome,
              voter_count: (ballot.participations.count unless ballot.finalized?),
              eligible_count: Ballotage::Ballot.eligible_count,
              closed_voter_count: ballot.closed_voter_count,
              closed_eligible_count: ballot.closed_eligible_count,
            }
            if ballot.counts_published?
              data.merge!(
                black_count: ballot.black_count,
                white_count: ballot.white_count,
                abstain_count: ballot.abstain_count,
              )
            end
            data
          end
        end
      end
    end
  end
end
