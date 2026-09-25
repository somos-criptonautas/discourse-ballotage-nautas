# frozen_string_literal: true

# name: discourse-ballotage-nautas
# about: Secret black/white-ball ballots (ballotage) for a member group, with participation oversight
# version: 1.0.0
# authors: Criptonautas (fork of DaniW42/discourse-ballotage)
# url: https://github.com/somos-criptonautas/discourse-ballotage-nautas
# required_version: 2026.7.0

enabled_site_setting :ballotage_enabled

register_asset "stylesheets/ballotage.scss"

%w[calendar-days check circle-info clock lock trash-can].each { |i| register_svg_icon i }

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
end
