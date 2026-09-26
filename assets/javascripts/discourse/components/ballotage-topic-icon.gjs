import { eq } from "discourse/truth-helpers";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// Ballot-box icon among core's topic status icons (pinned, closed…) in topic
// lists. after-topic-status lives inside core's TopicStatus, which every topic
// list layout renders — including themes like Horizon that drop other outlets.
const BallotageTopicIcon = <template>
  {{#if (eq @outletArgs.context "topic-list")}}
    {{#if @outletArgs.topic.ballotage}}
      <span
        class="topic-status --ballotage"
        title={{i18n "ballotage.topic_list_title"}}
      >{{dIcon "check-to-slot"}}</span>
    {{/if}}
  {{/if}}
</template>;

export default BallotageTopicIcon;
