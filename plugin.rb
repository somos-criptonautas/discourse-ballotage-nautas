# frozen_string_literal: true

# name: discourse-ballotage-nautas
# about: Secret black/white-ball ballots (ballotage) for a member group, with participation oversight
# version: 1.0.0
# authors: Criptonautas (fork of DaniW42/discourse-ballotage)
# url: https://github.com/somos-criptonautas/discourse-ballotage-nautas
# required_version: 2026.7.0

enabled_site_setting :ballotage_enabled

register_asset "stylesheets/ballotage.scss"

%w[calendar-days check check-to-slot circle-info clock comment list-check lock plus trash-can xmark].each { |i| register_svg_icon i }

module ::Ballotage
  PLUGIN_NAME = "discourse-ballotage-nautas"
end

require_relative "lib/ballotage/engine"

# Models and controllers under app/ are autoloaded by the engine; routes live in
# config/routes.rb, which the engine reloads with the route set. Routes drawn
# from after_initialize are lost on reload and every endpoint 404s.
after_initialize do
  require_relative "lib/ballotage/guardian_extension"

  reloadable_patch { Guardian.prepend(Ballotage::GuardianExtension) }

  # Drives the composer button, the sidebar link and its badge.
  add_to_serializer(:current_user, :ballotage) do
    can_vote = scope.can_vote_in_ballotage?
    {
      can_vote: can_vote,
      can_oversee: scope.can_oversee_ballotage?,
      can_manage: scope.can_manage_ballotage?,
      pending_count: can_vote ? Ballotage::Ballot.pending_for(object).count : 0,
    }
  end

  on(:post_created) { |post| Ballotage::Ballot.link_to_post(post) }
  on(:post_edited) { |post| Ballotage::Ballot.link_to_post(post) }
end
