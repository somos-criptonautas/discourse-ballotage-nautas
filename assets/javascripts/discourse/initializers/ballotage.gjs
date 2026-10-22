import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
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

// shortcut: the badge counts on page load and drops when voting here; a ballot
// opening mid-session shows after the next reload (notifications cover that).
function linkClass(base, currentUser) {
  return class extends base {
    name = "ballotage";
    route = "ballotage.index";
    title = i18n("ballotage.title");
    text = i18n("ballotage.title");
    prefixType = "icon";
    prefixValue = "check-to-slot";

    get badgeText() {
      return currentUser.ballotage?.pending || null;
    }
  };
}

// "community" puts the link in the Community section; "section" makes a section
// of its own titled in each reader's language (editable in Customize → Text);
// any other text becomes that section's title as typed.
function addSidebarLink(api, currentUser, section) {
  if (section.toLowerCase() === "community") {
    api.addCommunitySectionLink((base) => linkClass(base, currentUser));
    return;
  }
  const heading =
    section.toLowerCase() === "section"
      ? i18n("ballotage.sidebar.section_title")
      : section;
  api.addSidebarSection(
    (BaseSection, BaseLink) =>
      class extends BaseSection {
        name = "ballotage";
        text = heading;
        title = heading;
        links = [new (linkClass(BaseLink, currentUser))()];
      }
  );
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

      const section = container
        .lookup("service:site-settings")
        .ballotage_sidebar_section?.trim();
      if (section && (perms?.can_vote || perms?.can_oversee)) {
        addSidebarLink(api, currentUser, section);
      }

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
