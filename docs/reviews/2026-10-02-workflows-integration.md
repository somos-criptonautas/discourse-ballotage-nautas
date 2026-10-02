# Review — Discourse Workflows integration (2026-10-02)

Method: `discourse-plugin-review` skill (CodeWorksLabs Discourse review core, ruleset
0.1.2, community draft). This is a technical review, not approval by Discourse or anyone
else, and not a comprehensive security audit. The reviewer also wrote the reviewed change.

## 1. Review scope

| | |
|---|---|
| Extension | `discourse-ballotage-nautas`, plugin |
| Declared version | `1.0.0` (`plugin.rb`) |
| Candidate | branch `claude/plugin-discourse-workflows-actions-ckevx8`, code commit `3884bde` (`04a0678` adds only `.claude/skills/`); clean tree |
| Change under focus | `165277d..3884bde`: Workflows trigger and action, candidate field, `BallotCreator`, `Ballot#cancel!`, lifecycle events |
| Claimed compatibility | `required_version: 2026.7.0` |
| Review mode | `integrated_verification`, one target; full scope, emphasis on the change |
| Environment | Discourse `main` @ `67bc74d0d8` (v2026.10.0-latest), Ruby 3.4.9, PostgreSQL 16 + pgvector 0.8.0, Redis 7.0, Chromium 1194 via Playwright, Ubuntu 24.04 cloud container |

Commands executed (in the environment above):

- `bin/rake db:create db:migrate` with `LOAD_PLUGINS=1`, which ran `20261002000001_add_subject_user_id_to_ballotage_ballots`
- `bin/rspec plugins/discourse-ballotage-nautas/spec`: **149 examples, 0 failures**, including 6 system (browser) specs
- the same suite on the pre-change code (`git stash -u`): 118 non-system specs passed before the change
- `bin/rails runner` registry check: both nodes registered and owned by this plugin; Zeitwerk eager-load of every autoload root succeeded
- in the plugin: rubocop (31 files, no offenses), syntax_tree check, `pnpm lint:js`, `pnpm lint:prettier`, `git diff --check`: all clean
- sweep for high-risk constructs (raw SQL, HTML-safe, shell, HTTP, eval, YAML, CSRF skips, custom fields): no actionable hits

Not tested: Discourse 2026.7 ESR, 2026.8 and 2026.9; upgrade from a populated v1.0.0
site; migration rollback; the Workflows visual builder UI; expression-valued node
parameters; multisite.

## 2. Summary

| Critical | High | Medium | Low | Info | Unverified material concerns |
|---|---|---|---|---|---|
| 0 | 0 | 1 | 3 | 4 | 3 |

Four required corrections were identified. Release readiness was not assessed. Under the
skill's policy, the Medium finding would block a positive release-readiness conclusion,
because it concerns private data.

## 3. Required findings

### [Medium] Rule 08 — Non-voter lists outlive finalizing in Workflows execution history

Evidence:
- `lib/discourse_workflows/nodes/ballot/v1.rb` — `non_voters` returns one item per eligible member who hasn't voted
- Workflows core `app/models/discourse_workflows/execution_data.rb` — node outputs are stored in `data.run_data`
- Workflows core `config/settings.yml` — `workflow_executions_retention_days`, default 30, hidden
- `README.md` *Secrecy model*: "Finalizing is irreversible. It deletes the participation rows…"; `confirm_finalize` in `config/locales/client.*.yml`

Observed: running *List members who haven't voted* stores the usernames in that run's
execution data. That list is the voting group minus the people who had voted, so it is
effectively a voter list. Finalizing deletes `ballotage_participations` but cannot reach
Workflows' tables.

Impact: after an administrator finalizes a ballot, believing that "who voted" is now
permanently deleted, admins can still read that list in Workflows execution history for up
to 30 days, or longer if retention was raised.

Required change: either drop the `non_voters` operation, or disclose it where the promise
is made. That means the README secrecy section, the node description and the finalize
confirmation, saying that workflow runs keep their outputs under Workflows' retention.

Verification: if removed, a spec asserting the operation is gone. If kept, review the
copy, and add a spec that the node description mentions retention.

Confidence: Medium. The storage path was read in Workflows source but not observed in an
execution record.

### [Low] Rule 12 — Candidate link ignores the subfolder base path

Evidence: `assets/javascripts/discourse/components/ballotage-card.gjs:281`
(`href="/u/{{…}}"`). The voters list at `:413` already used the same pattern.

Observed: the link is root-relative and hard-coded.

Impact: on a forum served from a subfolder (e.g. `/forum`), the candidate link (and the
existing voter links) point to `/u/<name>` and 404.

Required change: build the URL with Discourse's `userPath()` (`discourse/lib/url`) or
`getURL`.

Verification: a system or component test with `set_subfolder`, or a unit assertion on the
rendered `href`.

Confidence: High (static); not run on a subfolder install.

### [Low] Rule 25 — "Closing soon" is documented as universal but only fires for ballots longer than 24 h

Evidence: `README.md` *Discourse Workflows* ("has about 24 h left");
`app/models/ballotage/ballot.rb:126-127` (`ends_at - starts_at > REMINDER_BEFORE`).

Observed: `closing_soon` fires only from `notify_reminder!`, which skips ballots that run
24 h or less.

Impact: a workflow that relies on *Closing soon* for last-call messages never fires for
short ballots.

Required change: say so in the README and in the `changes_closing_soon` label or its
description.

Verification: copy review. The existing tick-job specs already cover the scheduling rule.

Confidence: High.

### [Low] Rule 18 — Version not bumped for a schema and feature change

Evidence: `plugin.rb` `# version: 1.0.0`; tag `v1.0.0` points to different code; this
branch adds a migration and new features.

Observed: two materially different builds report the same version.

Impact: administrators and support can't tell from *Admin → Plugins* whether a site has
the migration and the Workflows nodes.

Required change: bump the version, for example to `1.1.0`, when this lands.

Verification: inspect `plugin.rb`.

Confidence: High.

## 4. Test and verification gaps

- **Rule 21 compatibility:** only `main` was exercised. The 2026.7 ESR claimed by
  `required_version`, and 2026.8 and 2026.9, are Not verified. The Workflows hook is
  guarded by `respond_to?(:register_discourse_workflows_node)`, so older cores should skip
  it, but that was not run.
- **Rule 19 upgrade:** the additive migration was applied to a fresh database only.
  Upgrading a populated v1.0.0 site was not executed.
- **Workflows builder UI:** node labels, option labels and `display_options` were not
  rendered in the visual editor. Only server-side execution, registration, output schemas
  and trigger dispatch are covered.
- Expression-valued parameters (`={{ … }}`) in the action were not exercised.
- Multisite and the action's behavior when `ballotage_enabled` is off were not exercised.
  Trigger disablement is covered by a spec.
- Keyboard and screen-reader use of the candidate picker: only the system spec
  (mouse-driven) covers it.

## 5. Optional improvements

- **Info, Rule 03:** `subject_user_id` has no foreign key and isn't cleared when the user
  is deleted. The ballot keeps a dangling id. The card and the item then omit the
  candidate, which is harmless, but an `on(:user_destroyed)` hook could clear it.
- **Info, Rule 09:** `list` runs two count queries per ballot (`participations.count`,
  `eligible_count`), with at most 100 ballots. `eligible_count` could be computed once per
  run.
- **Info:** `get` and `list`, like the web card, freeze the outcome on read via `close!`,
  which notifies voters and fires `closed`. This is deliberate (see the comment in
  `ballot_json`), but it is a side effect of a read operation.
- **Info, Rule 08:** the trigger and the action always include the outcome, even for
  overseer-only ballots. This is by design and documented, and only admins build
  workflows. A workflow that posts it publicly would widen its audience.

## 6. Rule matrix

| Rule | Status | Evidence / reason |
|---|---|---|
| 01 Clear capability | Pass | README; nodes add a coherent automation surface |
| 02 Supported integration | Pass | `register_discourse_workflows_node` and the `lib/discourse_workflows/` autoload convention, as used by solved and topic-voting; `DiscourseEvent`; no core patches |
| 03 Data lifecycle | Pass | `belongs_to :subject_user, optional`; dangling id after user deletion noted as Info |
| 04 Migration safety | Pass | additive nullable column and index on a plugin table; ran clean |
| 05 Server authorization | Pass | `ensure_allowed!` uses the manage or oversee guardians; specs cover refusals |
| 06 Input validation | Pass | strict date/time parsing; integer params; `ballot_id` format; Arel state filter; `limit` capped at 100 |
| 07 Credentials / external | Not applicable | no external services or secrets |
| 08 Privacy | Finding | non-voter lists outlive finalizing (Medium) |
| 09 Background work | Pass | events dispatch through Workflows jobs; tick job idempotent via `*_at` stamps |
| 10 Synchronization | Not applicable | no cross-system sync |
| 11 Native admin | Pass | nodes use Workflows' native configurator; staff action log |
| 12 User-facing behavior | Finding | subfolder links (Low) |
| 13 Frontend integration | Pass | FormKit custom field with core `UserChooser`; no DOM patching |
| 14 Site settings | Pass | `available:` lambda and `plugin.on` gate on `ballotage_enabled`; spec |
| 15 API contracts | Pass | output schemas declared and asserted with `match_node_output_schema` |
| 16 Tests | Pass | 31 new examples, including negative paths |
| 17 Quality checks | Pass | specs, rubocop, syntax_tree, eslint, prettier executed |
| 18 Installable release | Finding | version not bumped (Low) |
| 19 Upgrades | Not verified | populated-site upgrade not executed |
| 20 Disablement | Pass | trigger stops when disabled (spec); data kept |
| 21 Compatibility | Not verified | only `main` tested |
| 22 Dependencies | Pass | no new dependencies; Workflows is optional and guarded |
| 23 Security boundaries | Pass | actor guardian enforced; default actor `system` as in core nodes |
| 24 Operational behavior | Pass | events and nodes documented in README |
| 25 Documentation | Finding | closing-soon scope (Low) |
| 26 Honest representation | Pass | secrecy trade-offs stated |
| 27 Distribution rights | Pass | GPL-3.0 code; vendored review skill under MIT with notice |
| 28 Hygiene | Pass | no secrets or local paths; clean tree |
| 29 Pre-release honesty | Pass | README *Status* section |
| 30 Obsolete compatibility code | Not applicable | none added |

## 7. Resolution (re-review after fixes)

Each finding was rechecked against the corrected code. The full plugin suite was re-run on
the same environment: **148 examples, 0 failures** (6 system specs). Rubocop,
syntax_tree, eslint and prettier are clean.

| Finding | Resolution | Evidence |
|---|---|---|
| Medium, Rule 08: non-voter lists outlive finalizing | **Resolved.** The `non_voters` operation was removed; the node and README explain why. Non-voters still get the plugin's own reminder notification. | `lib/discourse_workflows/nodes/ballot/v1.rb` (`OPERATIONS`, class comment); spec "doesn't offer a list of who hasn't voted" in `spec/lib/discourse_workflows/nodes/ballot_spec.rb`; README *Discourse Workflows* |
| Low, Rule 12: subfolder links | **Resolved.** Candidate and voter links use core `userPath()`, which applies the base path. | `ballotage-card.gjs` (`userPath` import and both `href`s); `spec/system/ballot_create_spec.rb` asserts the rendered `href`. A subfolder install itself was not run. |
| Low, Rule 25: closing-soon scope | **Resolved.** README and the trigger's *Changes* description (EN/ES/DE) state that it only fires for ballots longer than 24 h. | `README.md`; `changes_description` in `config/locales/client.*.yml` |
| Low, Rule 18: version | **Resolved.** `plugin.rb` version is `1.1.0`. | `plugin.rb:5` |

The rule matrix changes accordingly: 08, 12, 18 and 25 are now **Pass**. The
verification gaps in section 4 are unchanged; release readiness remains unverified.
