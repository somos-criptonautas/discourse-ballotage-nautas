# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module BallotChanged
        # Fires on a ballot's lifecycle changes (see Ballotage::Ballot::CHANGES).
        # There is deliberately no per-vote change: its timing next to the
        # counters would reveal the choice.
        class V1 < DiscourseWorkflows::NodeType
          include DiscourseWorkflows::Nodes::Ballot::Payload

          CHANGES = Ballotage::Ballot::CHANGES
          EVENT_PREFIX = "ballotage_ballot_"
          OUTCOMES = %w[approved rejected no_quorum].freeze

          OUTPUT_SCHEMA =
            DiscourseWorkflows::Schema.merge(
              Ballot::Payload::SCHEMA,
              DiscourseWorkflows::Schema.document(
                "change" => {
                  "type" => "string",
                  "enum" => CHANGES,
                },
              ),
            ).freeze

          description(
            name: "trigger:ballot_changed",
            version: "1.0",
            defaults: {
              icon: "check-to-slot",
              color: "indigo",
            },
            group: "discourse_triggers",
            event: CHANGES.map { |change| :"#{EVENT_PREFIX}#{change}" },
            available: -> { SiteSetting.ballotage_enabled },
            unavailable_reason_key: "discourse_workflows.node_unavailable.requires_ballotage",
            output_contracts: [{ schema: OUTPUT_SCHEMA }],
            properties: {
              changes: {
                type: :multi_options,
                required: false,
                default: [],
                options: CHANGES,
              },
              kinds: {
                type: :multi_options,
                required: false,
                default: [],
                options: Ballotage::Ballot::KINDS,
              },
              outcomes: {
                type: :multi_options,
                required: false,
                default: [],
                options: OUTCOMES,
              },
              **CATEGORY_FILTER_PROPERTIES,
              **TAG_FILTER_PROPERTIES,
            },
          )

          def self.from_event(event_name, ballot, *)
            new(event_name, ballot)
          end

          def initialize(event_name, ballot)
            super(parameters: {})
            @change = event_name.to_s.delete_prefix(EVENT_PREFIX)
            @ballot = ballot
          end

          def valid?
            CHANGES.include?(@change) && @ballot.present?
          end

          def output
            ballot_item(@ballot).merge(change: @change)
          end

          def matches?(trigger_ctx)
            matches_option?(trigger_ctx, "changes", @change) &&
              matches_option?(trigger_ctx, "kinds", @ballot.kind) &&
              matches_option?(trigger_ctx, "outcomes", @ballot.outcome) &&
              matches_ballot_topic?(trigger_ctx)
          end

          private

          def matches_option?(trigger_ctx, name, value)
            wanted = Array.wrap(trigger_ctx.get_node_parameter(name, [])).compact_blank.map(&:to_s)
            wanted.empty? || wanted.include?(value.to_s)
          end

          # Category and tag filters apply to the topic the ballot is embedded
          # in; a ballot without a post only matches when neither is set.
          def matches_ballot_topic?(trigger_ctx)
            topic = @ballot.post&.topic
            return matches_topic_filters?(topic, trigger_ctx) if topic

            category_ids_parameter(trigger_ctx).empty? &&
              normalize_tag_names(trigger_ctx.get_node_parameter("tag_names")).empty?
          end
        end
      end
    end
  end
end
