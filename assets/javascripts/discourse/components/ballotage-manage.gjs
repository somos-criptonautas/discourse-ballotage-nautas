import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DBreadcrumbsItem from "discourse/ui-kit/d-breadcrumbs-item";
import DEmptyState from "discourse/ui-kit/d-empty-state";
import DPageHeader from "discourse/ui-kit/d-page-header";
import { i18n } from "discourse-i18n";
import BallotageCard from "./ballotage-card";
import BallotageCreate from "./modal/ballotage-create";

// /ballotage/manage — oversight list; managers also create and act on ballots.
export default class BallotageManage extends Component {
  @service modal;
  @service router;

  @action
  newBallot() {
    this.modal.show(BallotageCreate, {
      model: { onCreated: () => this.router.refresh() },
    });
  }

  <template>
    <div class="ballotage-page ballotage-manage">
      <DPageHeader
        @titleLabel={{i18n "ballotage.manage.title"}}
        @descriptionLabel={{i18n "ballotage.manage.description"}}
        @hideTabs={{true}}
        @shouldDisplay={{true}}
      >
        <:breadcrumbs>
          <DBreadcrumbsItem
            @path="/ballotage"
            @label={{i18n "ballotage.title"}}
          />
          <DBreadcrumbsItem
            @path="/ballotage/manage"
            @label={{i18n "ballotage.manage.title"}}
          />
        </:breadcrumbs>
        <:actions as |actions|>
          {{#if @data.can_manage}}
            <actions.Primary
              @action={{this.newBallot}}
              @icon="plus"
              @label="ballotage.manage.new"
            />
          {{/if}}
        </:actions>
      </DPageHeader>

      {{#if @data.forbidden}}
        <div class="alert alert-error">{{i18n
            "ballotage.manage.forbidden"
          }}</div>
      {{else if @data.loadError}}
        <div class="alert alert-error">{{i18n "ballotage.load_error"}}</div>
      {{else}}
        {{#each @data.ballots key="id" as |ballot|}}
          <BallotageCard @ballot={{ballot}} @showPostLink={{true}} />
        {{else}}
          <DEmptyState
            @identifier="ballotage-empty"
            @title={{i18n "ballotage.manage.empty"}}
          />
        {{/each}}
      {{/if}}
    </div>
  </template>
}
