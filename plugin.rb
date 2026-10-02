# frozen_string_literal: true

# name: discourse-ballotage-nautas
# about: Secret black/white-ball ballots (ballotage) for a member group, with participation oversight
# version: 1.0.0
# authors: DaniW42 — Forked by Criptonautas
# url: https://github.com/somos-criptonautas/discourse-ballotage-nautas
# required_version: 2026.7.0

enabled_site_setting :ballotage_enabled

register_asset "stylesheets/ballotage.scss"

%w[
  calendar-days
  check
  check-to-slot
  circle-info
  clock
  comment
  list-check
  lock
  plus
  scale-balanced
  trash-can
  user
  xmark
].each { |i| register_svg_icon i }

module ::Ballotage
  PLUGIN_NAME = "discourse-ballotage-nautas"
end

require_relative "lib/ballotage/engine"
# Top level, not after_initialize: the timezone setting's dropdown needs it.
require_relative "lib/ballotage/timezone_enum"

# Models and controllers under app/ are autoloaded by the engine; routes live in
# config/routes.rb, which the engine reloads with the route set. Routes drawn
# from after_initialize are lost on reload and every endpoint 404s.
after_initialize do
  # Keeps the vote choice out of the request log, which also records IP and
  # user. Appended in place: env_config holds this very array once the first
  # request has built it, so `+=` (a new array) could be silently ignored.
  Rails.application.config.filter_parameters << :choice

  require_relative "lib/ballotage/guardian_extension"
  require_relative "lib/ballotage/tick_job"

  reloadable_patch { Guardian.prepend(Ballotage::GuardianExtension) }

  # Discourse Workflows: a ballot lifecycle trigger and a ballot action. Only
  # when Workflows is installed; it stops when this plugin is disabled.
  if respond_to?(:register_discourse_workflows_node)
    register_discourse_workflows_node do
      [DiscourseWorkflows::Nodes::BallotChanged::V1, DiscourseWorkflows::Nodes::Ballot::V1]
    end
  end

  # Drives the composer button and the /ballotage header actions.
  add_to_serializer(:current_user, :ballotage) do
    {
      can_vote: scope.can_vote_in_ballotage?,
      can_oversee: scope.can_oversee_ballotage?,
      can_manage: scope.can_manage_ballotage?,
    }
  end

  # Marks topics that embed a ballot, for the icon in topic lists.
  register_topic_custom_field_type("ballotage", :boolean)
  add_preloaded_topic_list_custom_field("ballotage")
  add_to_serializer(
    :topic_list_item,
    :ballotage,
    include_condition: -> { object.custom_fields["ballotage"] },
  ) { true }

  on(:post_created) { |post| Ballotage::Ballot.link_to_post(post) }
  on(:post_edited) { |post| Ballotage::Ballot.link_to_post(post) }
end
