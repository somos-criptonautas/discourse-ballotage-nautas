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
              "kind": {
                "type": "string",
                "enum": ["admission", "proposal"],
                "description": "admission: black/white-ball vote on admitting the candidate; proposal: approve/reject/abstain"
              },
              "state": {
                "type": "string",
                "enum": ["scheduled", "open", "ended", "cancelled"],
                "description": "From the clock: scheduled before starts_at, open until ends_at, then ended"
              },
              "finalized": { "type": "boolean" },
              "url": { "type": "string", "description": "The post embedding the ballot, else the /ballotage page" },
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
                "description": "Set once the ballot has closed; only approved means accepted"
              },
              "voter_count": {
                "type": ["integer", "null"],
                "description": "How many members have voted, never who or how; null once finalized"
              },
              "eligible_count": { "type": ["integer", "null"] },
              "closed_voter_count": { "type": ["integer", "null"] },
              "closed_eligible_count": { "type": ["integer", "null"] },
              "black_count": {
                "type": "integer",
                "description": "Reject votes; only when the ended ballot publishes its counts"
              },
              "white_count": {
                "type": "integer",
                "description": "Approve votes; only when the ended ballot publishes its counts"
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
                # Discourse AI's workflow author only reads descriptions on objects, so the
                # hints it needs about the scalar fields live here.
                "Secret ballot from the ballotage plugin (member admissions and proposals " \
                  "with anonymous counts). Not a Discourse poll: unrelated to [poll] in posts " \
                  "and to poll votes. kind admission = black/white-ball vote on admitting " \
                  "candidate; proposal = approve/reject/abstain. outcome (approved, rejected, " \
                  "no_quorum) is set once closed. voter_count says how many voted, never who " \
                  "or how. Counts (black = reject, white = approve, abstain) appear only once " \
                  "an ended ballot publishes them. The trigger's closing_soon fires about 24 h before the end, " \
                  "only for ballots longer than 24 h; there is no per-vote event. topic and post " \
                  "are present only when the ballot is embedded in a post.",
              ),
              DiscourseWorkflows::Schema.entity(
                "candidate",
                DiscourseWorkflows::Schema::BASIC_USER_PROPERTIES,
                "The member an admission ballot is about; present only when one was picked. " \
                  "Use candidate.username for group or message actions.",
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
