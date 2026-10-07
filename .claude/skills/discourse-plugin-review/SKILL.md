---
name: discourse-plugin-review
description: Evidence-based review of a Discourse plugin, theme or theme component (this repo or another) against the CodeWorksLabs 30-rule Discourse review method — supported integration, authorization, data lifecycle, migrations, privacy, compatibility, tests, docs and release readiness. Use when asked to review, audit or check release readiness of a Discourse extension, or after a significant plugin change. Read-only unless the user explicitly asks for fixes.
---

# Discourse plugin review

Adapted from the CodeWorksLabs platform-review wrapper (MIT, see `LICENSE` and
`UPSTREAM.md`) for Claude Code, Discourse only. Review the exact product and candidate
against the shared evidence discipline below and the Discourse platform package. Evaluate
software behavior and evidence, not whether a human or coding agent typed particular lines.

## Load the platform package — all of it

Before substantive review, read completely:

1. [references/DiscourseSkill.json](references/DiscourseSkill.json) — structured core:
   artifact routing, review modes, evidence thresholds, release policy, version matrix,
   report contract.
2. [references/DiscourseSkill.md](references/DiscourseSkill.md) — the numbered rules
   01–30 and the human-readable review method.
3. [references/PROVENANCE.md](references/PROVENANCE.md) — identities of the two files.

Neither is optional or replaceable by a summary. When integrated or release-readiness
verification is authorized, also read
[references/LOCAL_TEST_MATRIX.md](references/LOCAL_TEST_MATRIX.md), and for running
Discourse's own test suite in a Claude Code cloud container see
[LOCAL_ENV.md](LOCAL_ENV.md).

The platform package adds specialized analysis. It never narrows the user's exact review
instruction.

## Authority

Review authority is read-only unless the user expressly asks for fixes. Finding a defect,
having write tools, or being asked to continue does not authorize edits, commits, pushes,
installations, deployments, submissions or messages. Before any mutation, confirm the exact
action and target are within what the user asked for.

## Identify the candidate

Record, as applicable: repository and product type; branch, commit, tree, tag, declared
version (`plugin.rb`), dirty/staged state and relevant untracked files; claimed Discourse
versions (`required_version`, `.discourse-compatibility`); included and excluded scope.

The working checkout, tagged artifact, installed plugin and generated assets are separate
evidence surfaces. Success in one does not establish another.

## Declare the review mode

Pick one primary mode from the JSON core (`static_review`, `repository_verification`,
`integrated_verification`, `release_readiness`) plus any focus areas the user named. Do not
imply a lower-evidence mode established a higher-evidence conclusion; a focused result is
not a complete product or release review.

## Evidence discipline

For every material claim, distinguish independently observed, replayed, supplied but not
replayed, historical, inferred, unavailable and not applicable evidence, with the command or
procedure and its output. Use the repository's own checks first (its specs, `pnpm lint`,
rubocop/syntax_tree). A workflow file, test count or clean status does not substitute for
inspecting the behavior it claims to cover. Missing evidence is not automatically a defect,
but it limits the conclusion. A changed candidate needs fresh evidence where affected.

## Reporting

Follow the report contract in the JSON core and the "Required review output" section of the
Markdown, in that order: review scope, summary counts, required findings (severity, rule,
evidence with `file:line`, observed, impact, required change, verification, confidence),
test and verification gaps, optional improvements, rule matrix (Pass / Finding / Not
verified / Not applicable). Keep required corrections, unresolved verification and optional
improvements distinct.

Use only the allowed outcome language. Never claim Discourse or marketplace approval, a
comprehensive security audit, legal clearance, guaranteed compatibility or release
acceptance. Anything material that was not tested stays `Not verified`.

## Sensitive findings

Keep unresolved exploit details, credentials and private data out of anything published; a
sanitized report may follow the fix.
