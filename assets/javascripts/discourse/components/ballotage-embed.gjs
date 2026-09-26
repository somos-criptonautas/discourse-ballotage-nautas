import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { ajax } from "discourse/lib/ajax";
import DConditionalLoadingSpinner from "discourse/ui-kit/d-conditional-loading-spinner";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import BallotageCard from "./ballotage-card";

// The live card behind a [ballotage id=N] placeholder in a post. Members who
// may neither vote nor oversee get a 404 and see only a neutral notice.
export default class BallotageEmbed extends Component {
  @tracked ballot = null;
  @tracked unavailable = false;
  @tracked loading = true;

  constructor() {
    super(...arguments);
    this.load();
  }

  async load() {
    try {
      const result = await ajax(
        `/ballotage/ballots/${this.args.ballotId}.json`
      );
      this.ballot = result.ballot;
    } catch {
      this.unavailable = true;
    } finally {
      this.loading = false;
    }
  }

  <template>
    <DConditionalLoadingSpinner @condition={{this.loading}} @size="small">
      {{#if this.ballot}}
        <BallotageCard @ballot={{this.ballot}} />
      {{else if this.unavailable}}
        <p class="ballotage-embed__unavailable">
          {{dIcon "lock"}}
          {{i18n "ballotage.embed.unavailable"}}
        </p>
      {{/if}}
    </DConditionalLoadingSpinner>
  </template>
}
