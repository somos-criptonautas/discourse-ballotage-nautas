# Upstream

Source: https://github.com/CodeWorksLabs/review-skills at commit
`74cd93ca73bcce4183a40c90a9934c116070e24f` (2026-09-22), MIT License © 2026 CodeWorksLabs
(see `LICENSE`).

## Unchanged

Copied byte-for-byte from
`.agents/skills/codeworkslabs-platform-review/references/platforms/discourse/`, so the
identities recorded in `references/PROVENANCE.md` still verify:

| File | SHA-256 |
|---|---|
| `references/DiscourseSkill.md` | `78786b92d15bcbf95fb81c920c3aa9f0fd802c41f4e6b7605d2655d9c72dc268` |
| `references/DiscourseSkill.json` | `21cf151b91d355443259727ed1346c0666fcb78354b71722f1f5abf6c038ceb6` |
| `references/LOCAL_TEST_MATRIX.md` | `5f39f9a366520c6566e0a8ac9c05c209763bbf1abb72b3a140667e373089ba05` |
| `references/PROVENANCE.md` | as published |

## Adapted

- `SKILL.md` — the upstream `codeworkslabs-platform-review` wrapper, renamed for Claude
  Code, limited to Discourse (Statamic routing removed), with the two-report requirement
  for platform submissions dropped and the authority, candidate, mode, evidence and
  reporting rules kept.

## Added (not from upstream)

- `LOCAL_ENV.md` — how to run Discourse's test suite with this plugin in a Claude Code cloud
  container, written in this repository.

To update: re-copy the four reference files from a newer upstream commit, check their
hashes against the new `PROVENANCE.md`, and update this file's commit and table.
