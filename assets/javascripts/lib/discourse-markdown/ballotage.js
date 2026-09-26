// [ballotage id=12]
// [/ballotage]
// becomes an empty placeholder that the ballotage initializer replaces with
// the live ballot card. Nothing about the ballot is baked into the post.
const rule = {
  tag: "ballotage",

  wrap(token, info) {
    const id = parseInt(info.attrs.id, 10);
    if (!(id > 0)) {
      return false;
    }
    token.attrs = [
      ["class", "ballotage-embed"],
      ["data-ballot-id", String(id)],
    ];
    return true;
  },
};

export function setup(helper) {
  helper.allowList(["div.ballotage-embed", "div[data-ballot-id]"]);

  helper.registerOptions((opts, siteSettings) => {
    opts.features.ballotage = !!siteSettings.ballotage_enabled;
  });

  helper.registerPlugin((md) => {
    if (md.options.discourse.features.ballotage) {
      md.block.bbcode.ruler.push("ballotage", rule);
    }
  });
}
