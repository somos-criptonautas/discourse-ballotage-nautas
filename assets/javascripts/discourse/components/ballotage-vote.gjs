import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { or } from "discourse/truth-helpers";
import DEmptyState from "discourse/ui-kit/d-empty-state";
import DPageHeader from "discourse/ui-kit/d-page-header";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import BallotageCard from "./ballotage-card";
import BallotageCreate from "./modal/ballotage-create";

// /ballotage — every scheduled or running ballot, each linking to its post.
// Overseers and managers get their actions in the page header, like core
// admin pages (collapsed into a "⋮" menu on narrow screens).
export default class BallotageVote extends Component {
  @service currentUser;
  @service modal;
  @service router;

  get canManage() {
    return this.currentUser?.ballotage?.can_manage;
  }

  @action
  newBallot() {
    this.modal.show(BallotageCreate, {
      model: { onCreated: () => this.router.refresh() },
    });
  }

  <template>
    <div class="ballotage-page">
      <DPageHeader
        @titleLabel={{i18n "ballotage.title"}}
        @descriptionLabel={{i18n "ballotage.description"}}
        @hideTabs={{true}}
        @shouldDisplay={{true}}
      >
        <:actions as |actions|>
          {{#if @data.can_oversee}}
            <actions.Default
              @route="ballotage.manage"
              @icon="list-check"
              @label="ballotage.manage.link"
            />
          {{/if}}
          {{#if this.canManage}}
            <actions.Primary
              @action={{this.newBallot}}
              @icon="plus"
              @label="ballotage.manage.new"
            />
          {{/if}}
        </:actions>
      </DPageHeader>

      {{#if @data.loadError}}
        <div class="alert alert-error">{{i18n "ballotage.load_error"}}</div>
      {{else if (or @data.can_vote @data.can_oversee)}}
        {{#each @data.ballots as |ballot|}}
          <BallotageCard @ballot={{ballot}} @showPostLink={{true}} />
        {{else}}
          <DEmptyState
            @identifier="ballotage-none"
            @title={{i18n "ballotage.none"}}
          />
        {{/each}}
      {{else}}
        <DEmptyState
          @identifier="ballotage-not-eligible"
          @title={{i18n "ballotage.vote.not_eligible"}}
        />
      {{/if}}

      {{#if @data.info_text}}
        <aside class="ballotage-info">
          {{dIcon "circle-info"}}
          <p>{{@data.info_text}}</p>
        </aside>
      {{/if}}
    </div>
  </template>
}
