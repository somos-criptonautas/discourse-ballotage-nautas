import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Ballot-box icon before the title in topic lists, next to core's
// pinned/closed status icons, for topics that embed a ballot.
const BallotageTopicIcon = <template>
  {{#if @outletArgs.topic.ballotage}}
    <span
      class="ballotage-topic-icon"
      title={{i18n "ballotage.topic_list_title"}}
    >{{dIcon "check-to-slot"}}</span>
  {{/if}}
</template>;

export default BallotageTopicIcon;
