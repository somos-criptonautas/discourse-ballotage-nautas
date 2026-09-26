import { withPluginApi } from "discourse/lib/plugin-api";
import richEditorExtension from "../../lib/rich-editor-extension";
import BallotageEmbed from "../components/ballotage-embed";
import BallotageTopicIcon from "../components/ballotage-topic-icon";
import BallotageCreate from "../components/modal/ballotage-create";

function attachBallots(elem, helper) {
  // No helper (or no renderGlimmer) outside the post stream, e.g. in some
  // previews; the placeholder then just stays empty.
  if (!helper?.renderGlimmer) {
    return;
  }
  elem.querySelectorAll(".ballotage-embed[data-ballot-id]").forEach((node) => {
    if (node.closest("blockquote")) {
      return;
    }
    const ballotId = node.dataset.ballotId;
    helper.renderGlimmer(
      node,
      <template><BallotageEmbed @ballotId={{ballotId}} /></template>
    );
  });
}

export default {
  name: "ballotage",

  initialize(container) {
    if (!container.lookup("service:site-settings").ballotage_enabled) {
      return;
    }

    withPluginApi((api) => {
      api.decorateCookedElement(attachBallots, { id: "ballotage" });
      api.registerRichEditorExtension(richEditorExtension);
      api.renderInOutlet("after-topic-status", BallotageTopicIcon);
      api.replaceIcon("notification.ballotage.notification", "check-to-slot");

      const currentUser = api.getCurrentUser();
      const perms = currentUser?.ballotage;

      if (perms?.can_manage) {
        const modal = container.lookup("service:modal");
        api.addComposerToolbarPopupMenuOption({
          name: "ballotage",
          icon: "check-to-slot",
          label: "ballotage.composer.insert",
          action: (toolbarEvent) =>
            modal.show(BallotageCreate, {
              model: {
                fromComposer: true,
                onCreated: (ballot) =>
                  toolbarEvent.addText(
                    `\n[ballotage id=${ballot.id}]\n[/ballotage]\n`
                  ),
              },
            }),
        });
      }
    });
  },
};
