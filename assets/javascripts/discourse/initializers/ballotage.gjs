import { tracked } from "@glimmer/tracking";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import richEditorExtension from "../../lib/rich-editor-extension";
import BallotageEmbed from "../components/ballotage-embed";
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

      if (perms?.can_vote || perms?.can_oversee) {
        api.addCommunitySectionLink(
          (BaseLink) =>
            class BallotageSectionLink extends BaseLink {
              // Open ballots this member hasn't voted in yet; the card
              // announces each vote so the badge updates without a reload.
              @tracked pendingCount = perms.pending_count || 0;

              constructor() {
                super(...arguments);
                this.appEvents.on("ballotage:voted", this, this.onVoted);
              }

              teardown() {
                this.appEvents.off("ballotage:voted", this, this.onVoted);
              }

              onVoted() {
                this.pendingCount = Math.max(0, this.pendingCount - 1);
              }

              get name() {
                return "ballotage";
              }

              get route() {
                return "ballotage.index";
              }

              get title() {
                return i18n("ballotage.sidebar.title");
              }

              get text() {
                return i18n("ballotage.sidebar.text");
              }

              get defaultPrefixValue() {
                return "check-to-slot";
              }

              get badgeText() {
                return this.pendingCount || null;
              }
            }
        );
      }
    });
  },
};
