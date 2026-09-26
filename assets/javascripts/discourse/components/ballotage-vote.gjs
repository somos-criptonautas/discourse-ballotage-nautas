import { LinkTo } from "@ember/routing";
import { or } from "discourse/truth-helpers";
import DEmptyState from "discourse/ui-kit/d-empty-state";
import DPageHeader from "discourse/ui-kit/d-page-header";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import BallotageCard from "./ballotage-card";

// /ballotage — every scheduled or running ballot, each linking to its post.
const BallotageVote = <template>
  <div class="ballotage-page">
    <DPageHeader
      @titleLabel={{i18n "ballotage.title"}}
      @descriptionLabel={{i18n "ballotage.description"}}
      @hideTabs={{true}}
      @shouldDisplay={{true}}
    />

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

    {{#if @data.can_oversee}}
      <LinkTo @route="ballotage.manage" class="btn btn-default">
        {{dIcon "list-check"}}
        {{i18n "ballotage.manage.link"}}
      </LinkTo>
    {{/if}}
  </div>
</template>;

export default BallotageVote;
