# frozen_string_literal: true

if defined?(DiscourseWorkflows)
  module DiscourseWorkflows
    module Nodes
      module Ballot
        # Creates, reads, lists, cancels and finalizes secret ballots. Runs as
        # "Performed by user" and holds them to the same permissions as the web
        # UI: managing for create/cancel/finalize, oversight for get/list.
        # There is deliberately no "who hasn't voted" operation: Workflows keeps
        # node outputs in its execution history, so the list (in effect, who
        # voted) would outlive finalizing. Non-voters already get a reminder.
        class V1 < DiscourseWorkflows::NodeType
          include Payload

          OPERATIONS = %w[create get list cancel finalize].freeze
          MANAGE_OPERATIONS = %w[create cancel finalize].freeze
          BY_ID_OPERATIONS = %w[get cancel finalize].freeze
          STATES = %w[scheduled open ended cancelled].freeze
          MAX_LIST = 100

          def self.create_property(definition, kind: nil)
            show = { operation: ["create"] }
            show[:kind] = [kind] if kind
            definition.merge(display_options: { show: show })
          end

          description(
            name: "action:ballot",
            version: "1.0",
            defaults: {
              icon: "check-to-slot",
              color: "indigo",
            },
            group: "discourse_actions",
            available: -> { SiteSetting.ballotage_enabled },
            unavailable_reason_key: "discourse_workflows.node_unavailable.requires_ballotage",
            capabilities: {
              run_scope: "per_item",
            },
            output_contracts: [{ schema: Payload::SCHEMA }],
            properties: {
              operation: {
                type: :options,
                required: true,
                options: OPERATIONS,
                default: "get",
              },
              ballot_id: {
                type: :integer,
                required: true,
                ui: {
                  expression: true,
                },
                display_options: {
                  show: {
                    operation: BY_ID_OPERATIONS,
                  },
                },
              },
              title: create_property({ type: :string, required: true }),
              kind:
                create_property(
                  {
                    type: :options,
                    required: true,
                    default: "admission",
                    options: Ballotage::Ballot::KINDS,
                  },
                ),
              candidate_username:
                create_property(
                  { type: :string, required: false, ui: { control: :user, expression: true } },
                  kind: "admission",
                ),
              start_date: create_property({ type: :string, required: true }),
              start_time: create_property({ type: :string, required: false }),
              end_date: create_property({ type: :string, required: true }),
              end_time: create_property({ type: :string, required: false }),
              rejection_threshold:
                create_property({ type: :integer, required: false }, kind: "admission"),
              rejection_percent:
                create_property({ type: :integer, required: false }, kind: "admission"),
              approval_rule:
                create_property(
                  {
                    type: :options,
                    required: false,
                    default: "majority",
                    options: Ballotage::Ballot::APPROVAL_RULES,
                  },
                  kind: "proposal",
                ),
              quorum_percent: create_property({ type: :integer, required: false }),
              result_visibility:
                create_property(
                  { type: :options, required: false, options: Ballotage::Ballot::VISIBILITIES },
                ),
              keep_counts:
                create_property({ type: :boolean, required: false, ui: { control: :checkbox } }),
              topic_id:
                create_property({ type: :integer, required: false, ui: { expression: true } }),
              intro:
                create_property({ type: :string, required: false, ui: { control: :textarea } }),
              states: {
                type: :multi_options,
                required: false,
                default: [],
                options: STATES,
                display_options: {
                  show: {
                    operation: ["list"],
                  },
                },
              },
              limit: {
                type: :integer,
                required: false,
                default: 20,
                display_options: {
                  show: {
                    operation: ["list"],
                  },
                },
              },
              actor_username: {
                type: :string,
                required: false,
                default: "system",
                ui: {
                  control: :actor,
                },
              },
            },
          )

          def execute(exec_ctx)
            items =
              exec_ctx.input_items.flat_map.with_index do |item, item_index|
                paired_item = exec_ctx.paired_item_for(item)
                Array
                  .wrap(process(exec_ctx, item_index))
                  .map { |data| wrap(data, paired_item: paired_item) }
              end

            [items]
          end

          private

          def process(exec_ctx, item_index)
            operation = exec_ctx.get_node_parameter("operation", item_index, default: "get").to_s
            if OPERATIONS.exclude?(operation)
              raise_node_error!(
                I18n.t("ballotage.workflows.unknown_operation", operation: operation),
                item_index: item_index,
              )
            end

            actor = exec_ctx.actor_from_parameter("actor_username", item_index)
            ensure_allowed!(actor, operation, item_index)

            case operation
            when "create"
              create(exec_ctx, actor, item_index)
            when "list"
              list(exec_ctx, item_index)
            else
              ballot = find_ballot(exec_ctx, item_index)
              change_state(ballot, actor, operation, item_index) if operation != "get"
              ballot_item(ballot.reload)
            end
          rescue Ballotage::Ballot::InvalidState, ActiveRecord::RecordInvalid => e
            raise_node_error!(e.message, item_index: item_index)
          rescue Discourse::InvalidParameters => e
            raise_node_error!(
              I18n.t("ballotage.workflows.invalid_parameter", name: e.message),
              item_index: item_index,
            )
          end

          def ensure_allowed!(actor, operation, item_index)
            guardian = actor.guardian
            allowed =
              if MANAGE_OPERATIONS.include?(operation)
                guardian.can_manage_ballotage?
              else
                guardian.can_oversee_ballotage?
              end
            return if allowed

            raise_node_error!(
              I18n.t("ballotage.workflows.not_allowed", username: actor.username),
              item_index: item_index,
            )
          end

          def find_ballot(exec_ctx, item_index)
            id = exec_ctx.get_node_parameter("ballot_id", item_index)
            ballot = (Ballotage::Ballot.find_by(id: id.to_i) if id.to_s.match?(/\A\d+\z/))
            return ballot if ballot

            raise_node_error!(
              I18n.t("ballotage.workflows.ballot_not_found", id: id),
              item_index: item_index,
            )
          end

          def change_state(ballot, actor, operation, item_index)
            case operation
            when "cancel"
              ballot.cancel!
            when "finalize"
              ballot.finalize!
            end
            ballot.log_staff_action(actor, "ballotage_#{operation}")
          end

          def create(exec_ctx, actor, item_index)
            param = ->(name) { exec_ctx.get_node_parameter(name, item_index) }
            ballot =
              Ballotage::BallotCreator.create!(
                actor,
                {
                  title: param.("title"),
                  kind: param.("kind"),
                  subject_username: param.("candidate_username"),
                  start_date: param.("start_date"),
                  start_time: param.("start_time"),
                  end_date: param.("end_date"),
                  end_time: param.("end_time"),
                  rejection_threshold: param.("rejection_threshold"),
                  rejection_percent: param.("rejection_percent"),
                  approval_rule: param.("approval_rule"),
                  quorum_percent: param.("quorum_percent"),
                  result_visibility: param.("result_visibility"),
                  keep_counts: param.("keep_counts"),
                }.compact,
              )

            topic_id = param.("topic_id")
            embed(ballot, actor, topic_id, param.("intro"), item_index) if topic_id.present?
            ballot_item(ballot.reload)
          end

          # Posts the ballot as a reply in the topic; the post_created hook
          # then links it, flags the topic and tags its title, as for a ballot
          # inserted from the composer.
          def embed(ballot, actor, topic_id, intro, item_index)
            raw = [
              intro.to_s.strip.presence,
              "[ballotage id=#{ballot.id}]\n[/ballotage]",
            ].compact.join("\n\n")
            creator =
              ::PostCreator.new(actor, topic_id: topic_id.to_i, raw: raw, skip_workflows: true)
            return if creator.create

            raise_node_error!(
              I18n.t(
                "ballotage.workflows.embed_failed",
                id: ballot.id,
                errors: creator.errors.full_messages.join(", "),
              ),
              item_index: item_index,
            )
          end

          def list(exec_ctx, item_index)
            states =
              Array
                .wrap(exec_ctx.get_node_parameter("states", item_index, default: []))
                .compact_blank
                .map(&:to_s) & STATES
            limit = exec_ctx.get_node_parameter("limit", item_index, default: 20).to_i
            limit = 20 if limit <= 0

            scope = Ballotage::Ballot.includes(:subject_user, post: :topic)
            scope = scope.where(state_condition(states)) if states.present?
            scope
              .order(starts_at: :desc, id: :desc)
              .limit([limit, MAX_LIST].min)
              .map { |ballot| ballot_item(ballot) }
          end

          def state_condition(states)
            now = Time.zone.now
            table = Ballotage::Ballot.arel_table
            running = table[:cancelled_at].eq(nil)
            conditions = {
              "scheduled" => running.and(table[:starts_at].gt(now)),
              "open" => running.and(table[:starts_at].lteq(now)).and(table[:ends_at].gt(now)),
              "ended" => running.and(table[:ends_at].lteq(now)),
              "cancelled" => table[:cancelled_at].not_eq(nil),
            }
            states.map { |state| conditions.fetch(state) }.reduce(:or)
          end
        end
      end
    end
  end
end
