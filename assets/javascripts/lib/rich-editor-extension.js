import { i18n } from "discourse-i18n";

// Lets the rich-text composer keep [ballotage id=N][/ballotage]: parsed into
// an uneditable block and written back verbatim. Without it the editor drops
// the unknown block.
export default {
  nodeSpec: {
    ballotage: {
      attrs: { id: {} },
      group: "block",
      atom: true,
      selectable: true,
      draggable: true,
      parseDOM: [
        {
          tag: "div.ballotage-embed",
          getAttrs: (dom) => ({ id: dom.dataset.ballotId }),
        },
      ],
      toDOM: (node) => [
        "div",
        {
          class: "ballotage-embed ballotage-embed--editor",
          "data-ballot-id": node.attrs.id,
        },
        i18n("ballotage.composer.placeholder", { id: node.attrs.id }),
      ],
    },
  },

  parse: {
    wrap_bbcode(state, token) {
      if (token.tag !== "div") {
        return false;
      }
      if (
        token.nesting === 1 &&
        token.attrGet("class") === "ballotage-embed"
      ) {
        state.openNode(state.schema.nodes.ballotage, {
          id: token.attrGet("data-ballot-id"),
        });
        return true;
      }
      if (token.nesting === -1 && state.top().type.name === "ballotage") {
        state.closeNode();
        return true;
      }
      return false;
    },
  },

  serializeNode: {
    ballotage(state, node) {
      state.write(`[ballotage id=${node.attrs.id}]\n[/ballotage]`);
      state.closeBlock(node);
    },
  },
};
