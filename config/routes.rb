# frozen_string_literal: true

Ballotage::Engine.routes.draw do
  get "/" => "ballots#page"
  get "/manage" => "ballots#page"
  get "/current" => "ballots#current"
  post "/vote" => "ballots#vote"
  get "/ballots" => "ballots#index"
  get "/ballots/:id" => "ballots#show"
  post "/ballots" => "ballots#create"
  post "/ballots/:id/cancel" => "ballots#cancel"
  post "/ballots/:id/finalize" => "ballots#finalize"
  delete "/ballots/:id" => "ballots#destroy"
end

Discourse::Application.routes.draw { mount Ballotage::Engine, at: "/ballotage" }
