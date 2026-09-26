# discourse-ballotage-nautas

[![Discourse Plugin](https://github.com/somos-criptonautas/discourse-ballotage-nautas/actions/workflows/discourse-plugin.yml/badge.svg)](https://github.com/somos-criptonautas/discourse-ballotage-nautas/actions/workflows/discourse-plugin.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Discourse 2026.7+](https://img.shields.io/badge/Discourse-2026.7%2B-blue?logo=discourse)](https://www.discourse.org/)

> **This is a fork** of [DaniW42/discourse-ballotage](https://github.com/DaniW42/discourse-ballotage)
> by DaniW42, maintained by [Criptonautas](https://github.com/somos-criptonautas). All credit
> for the original design and implementation goes to them — see the upstream
> [Meta topic](https://meta.discourse.org/t/ballotage-secret-black-white-ball-ballots/413266).
> Please report issues with this fork here, not upstream.

## Differences from upstream

Forked from upstream `v1.0.0-2-g753691d`. Kept up to date with every change in this fork:

- **Plugin name** is `discourse-ballotage-nautas` (install path, `PLUGIN_NAME`, JS module
  paths). Settings, tables and routes are kept; one column is added (`post_id`), so
  upstream data migrates forward cleanly.
- **Ballots live in posts.** `[ballotage id=N]…[/ballotage]` embeds a live ballot card in
  any post; a composer button ("Insert secret ballot") creates the ballot and inserts the
  tag. The first manager's post embedding a ballot is linked to it (`post_id`).
- **Several ballots at once** — upstream allows only one scheduled/open ballot site-wide.
- **Native UI:** one ballot card (core buttons, colour variables, poll-like layout) used in
  posts, on `/ballotage` and on `/ballotage/manage`; the pages use core page headers,
  empty states and a FormKit create form in a modal. Managers can cancel/finalize/delete
  straight from the card.
- **Sidebar link** "Ballots" (in the Community section's *More* drawer) for voters and
  overseers, with a badge counting open ballots you haven't voted in.
- **Ballot kinds and decision rules.** *Admission* (black/white balls; rejected once N
  black balls are cast) or *Proposal* (approve / reject / abstain; simple majority,
  two-thirds or unanimous; abstentions count toward quorum only). Optional quorum as a
  share of the voting group. Rules are set at creation and can't be changed afterwards.
- **Outcome.** When a ballot ends, "Approved", "Rejected" or "No quorum" and the turnout
  are frozen on it; the outcome survives finalizing.
- **Published results** (per ballot): only overseers, the outcome, or the outcome and
  counts — shown on the card to everyone who can read the post (anonymous visitors of a
  public topic included), only after the end, never who voted. A ballot that publishes
  its counts can keep them after finalizing.
- **Notifications:** eligible members are notified when a ballot opens and, if they
  haven't voted, about 24 h before it closes; voters are notified when it closes (with
  the outcome if published). Runs in a scheduled job every 5 minutes.
- **Audit log:** creating, cancelling, finalizing and deleting ballots is recorded in
  *Admin → Logs → Staff actions* (`ballotage_*`).
- **Spanish** translation.
- **Time zone** setting is a dropdown of real zones, and empty by default ("automatic"):
  new ballots use their creator's profile time zone and everyone sees times in their own
  zone. Upstream defaults to a fixed `Europe/Berlin` text value.
- **Kind tag:** ballots show **[ADMISSION]** or **[PROPOSAL]** before their title (on the
  card and in notifications), added at display time in each reader's language
  ([ADMISIÓN] / [PROPUESTA] in Spanish) — never stored in the title.
- **Topic lists** show a small ballot-box icon before the title of topics that embed a
  ballot (next to core's pinned/closed icons).
- **API:** `GET /ballotage/ballots/:id.json` (card data, 404 for non-eligible members);
  `/ballotage/current.json` returns `ballots: [...]` instead of a single `ballot`; create,
  cancel and finalize respond with `{ ballot: ... }`.
- **Input validation:** `POST /ballotage/vote` returns 400 (not 500) for a non-scalar
  `ballot_id`/`choice`; ballot creation returns 400 for impossible dates or times
  (e.g. `2026-13-01`, `2026-02-31`, `24:00`) instead of a 500 or a silently shifted date.
- **Deleted users:** their participation rows are kept, and `voter_count` counts rows,
  so "votes cast" always equals black + white (see *Secrecy model*).

A [Discourse](https://www.discourse.org/) plugin for **secret ballots** — black/white-ball
admissions ("ballotage", in German "Kugelung") as used by clubs and membership
organizations, and approve/reject/abstain votes on proposals. Who voted is recorded, but
what they voted is not.

## What it does

- Ballots are embedded in posts (`[ballotage id=N]`), so the discussion about a candidate
  or proposal and the vote sit in the same topic. Eligible members cast one vote (black or
  white) right in the post; a vote cannot be changed once cast.
- `/ballotage` lists every scheduled or open ballot with a link to its post.
- The oversight group (and admins) see on the card, and at `/ballotage/manage`, who has
  voted while a ballot is running, and the result once it has ended.
- Several ballots can be scheduled or open at the same time.
- Ballots can be scheduled with a start and end day (default opening/closing times of
  00:01 / 23:59, or custom times), cancelled before they end, and finalized afterwards.
- Each ballot has a kind (admission or proposal), a decision rule, an optional quorum and
  a result visibility; the outcome is decided and frozen when it ends.
- Finalizing a ballot irreversibly deletes the list of who voted and (unless it keeps its
  published counts) the counts, leaving the title, period, status and outcome.

## Screenshots

| Voting page | After voting |
|---|---|
| ![Voting page with black and white choices](docs/screenshots/vote-open.png) | ![Confirmation after the vote has been cast](docs/screenshots/vote-done.png) |

| Management while open | Management after the end |
|---|---|
| ![Participation shown, result hidden while the ballot is open](docs/screenshots/manage-running.png) | ![Result shown once the ballot has ended](docs/screenshots/manage-ended.png) |

While a ballot is open, the management page shows who has voted but not the
black/white counts; the result appears only once the ballot has ended.

## Secrecy model

The database is deliberately structured so that nothing in it links a member to a choice:

- **Participation table** (`ballotage_participations`): one row per member who voted in a
  ballot, recording *that* they voted. It has no `choice` column and, deliberately, no
  timestamps at all — a `created_at` per row, compared against the ballot's counters,
  could otherwise help reconstruct individual votes.
- **Two anonymous counters** on the ballot itself (`black_count`, `white_count`), bumped
  with `update_counters`, which does not touch `updated_at`. The ballot row carries no
  timestamp of the last vote either.
- **Counts are hidden until the ballot is over.** While a ballot is running, the
  card and management page show the participant list (who has voted) but not the black/white
  counts. Showing both at the same time would let an observer match a new name appearing
  on the list to whichever counter just moved. Once the ballot is over no further votes
  can arrive, so the final counts are shown.
- **Deleted users.** If a member who voted is deleted, their participation row is kept so
  "votes cast" keeps matching the black/white tally; they just drop off the voter list.
  Finalizing removes those rows like all others.
- **Published results never include who voted**, and only appear after the end, so
  publishing doesn't reopen the correlation above.
- **Finalizing is irreversible.** It deletes the participation rows and zeroes the
  counters (unless the ballot published its counts and chose to keep them), keeping the
  title, period, status and frozen outcome. There is no undo.

**Honest limits.** This protects against what the application itself reveals. It does not
protect against someone with direct database access watching the two counters change in
real time during an open ballot and correlating that with who is known to be voting at
that moment — such access is out of scope for an application-level plugin and needs to be
handled organizationally (e.g. restrict database/console access during ballots).

## Pages and embedding

- **In a post** — `[ballotage id=N]` + `[/ballotage]` renders the ballot card. Members who
  can neither vote nor oversee see only a neutral "secret ballot attached" notice; the
  server returns 404 to them, so not even the title leaks.
- **`/ballotage`** — all scheduled and open ballots. Visible to members of the voting group
  (to vote) and to the oversight group / admins (participation, link to management).
- **`/ballotage/manage`** — the management page. Visible to the oversight group (if
  `ballotage_oversight_can_manage` is enabled, they can also create, cancel and finalize
  ballots) and to admins, who always have full access.

## Settings

| Setting | Default | Description |
|---|---|---|
| `ballotage_enabled` | `false` | Enables the plugin and the `/ballotage` page. |
| `ballotage_voting_group` | *(none)* | Group whose members may vote. |
| `ballotage_oversight_group` | *(none)* | Group that can see, at `/ballotage/manage`, who has voted and — after the end — the result. |
| `ballotage_oversight_can_manage` | `false` | Whether the oversight group may also create, cancel and finalize ballots (otherwise only admins can). |
| `ballotage_info_text` | *(empty)* | Optional plain-text notice shown below the content on `/ballotage`, e.g. who is eligible. Nothing is shown when empty. |
| `ballotage_timezone` | *(automatic)* | Time zone for ballot start/end times. Automatic: the creator's profile zone; everyone sees times in their own zone. Pick a zone to force one for everyone. |

## Permissions

| | Vote | See who has voted (during) | See result (after end) | Create / cancel / finalize / delete |
|---|---|---|---|---|
| Admin | no (unless also in voting group) | yes | yes | yes |
| Oversight group member | no (unless also in voting group) | yes | yes | only if `ballotage_oversight_can_manage` is enabled |
| Voting group member | yes | no | no | no |
| Everyone else | no | no | no | no |

## Installation

Add the plugin to your `app.yml` and rebuild:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/somos-criptonautas/discourse-ballotage-nautas.git
```

```bash
./launcher rebuild app
```

### Setup after install

1. Enable the `ballotage_enabled` site setting.
2. Choose the `ballotage_voting_group` (who may vote) and `ballotage_oversight_group`
   (who oversees ballots).
3. Optionally pick a fixed `ballotage_timezone`; left empty, each ballot uses its creator's time zone.
4. Optionally decide whether the oversight group may manage ballots
   (`ballotage_oversight_can_manage`), or leave that to admins only.
5. A "Ballots" link appears for voters and overseers in the sidebar's Community section
   (under *More*); admins can move it to the main list via the section editor.

## Usage

- Someone with manage permission writes a post (e.g. the candidate's introduction or a
  feature proposal), opens the composer's ⚙ menu → **Insert secret ballot**, and fills in
  the type (admission or proposal), title, start and end day, the rule (black balls to
  reject / majority), an optional quorum and who sees the result. The ballot is created
  and its tag inserted into the post.
  By default it opens at 00:01 on the start day and closes at 23:59 on the end day; check
  "custom times" to set specific times. **New ballot** on `/ballotage/manage` does the same
  without a post; paste `[ballotage id=N]` into a post later if wanted.
- A ballot created from the composer exists even if the post is discarded — cancel it from
  `/ballotage/manage`.
- A scheduled or open ballot can be cancelled; votes already cast are kept until the
  ballot is finalized.
- Once a ballot has ended (or been cancelled), it can be finalized. This is irreversible
  and permanently deletes the participant list and (unless kept) the counts — a
  confirmation warns about this before proceeding. The outcome remains.
- A finalized ballot can then be deleted to remove it from the list entirely. Only
  finalized ballots can be deleted, so a result can never be lost in a single step.

## Development & tests

There is a spec suite under `spec/` (models, requests, lib). Run it from inside a
Discourse checkout with this plugin in `plugins/`:

```bash
bundle exec rspec plugins/discourse-ballotage-nautas/spec
```

Linting uses the standard Discourse plugin configuration (ESLint, Prettier,
Stylelint, RuboCop, Syntax Tree), run from the Discourse checkout:

```bash
bin/lint plugins/discourse-ballotage-nautas
```

CI runs specs and linters on every push to `main` and on pull requests.

## Status

First release, not yet battle-tested in production. Compatible with Discourse 2026.7 and
later.

## License

GPL-3.0. See [LICENSE](LICENSE). Original work © DaniW42; fork modifications © Criptonautas.

---

## Deutsch

**discourse-ballotage-nautas** (ein Fork von
[DaniW42/discourse-ballotage](https://github.com/DaniW42/discourse-ballotage)) ist ein Discourse-Plugin für geheime Kugelungen (Abstimmungen mit
schwarzen/weissen Kugeln), wie sie z. B. Vereine, Gesellschaften und andere
Mitgliedsorganisationen zur Aufnahme neuer Mitglieder einsetzen. Jedes stimmberechtigte
Mitglied gibt genau eine Stimme (Schwarz oder Weiss) ab; dass es abgestimmt hat, wird
erfasst — was es gestimmt hat, nicht.

**Geheimhaltung:** In der Datenbank gibt es keine Verknüpfung zwischen Mitglied und
Stimme. Die Teilnahme-Tabelle speichert nur, wer teilgenommen hat, ohne Stimme und ohne
Zeitstempel; zwei anonyme Zähler (Schwarz/Weiss) auf der Kugelung selbst führen ebenfalls
keine Zeitstempel. Solange eine Kugelung läuft, zeigt die Verwaltungsseite, wer
abgestimmt hat, aber nicht den Zwischenstand — sonst liesse sich ein neu erscheinender
Name mit dem gerade veränderten Zähler in Verbindung bringen. Nach Ende der Kugelung wird
das Ergebnis angezeigt. Beim Finalisieren werden Ergebnis und Teilnehmerliste
unwiderruflich gelöscht; erhalten bleiben nur Titel, Zeitraum und Status. Zu beachten
bleibt: Wer direkten Datenbankzugriff hat und die Zähler während einer laufenden
Kugelung live beobachtet, könnte Rückschlüsse ziehen — das lässt sich technisch nicht
verhindern und muss organisatorisch abgesichert werden (Zugriff einschränken).

**Einbindung und Seiten:** Kugelungen werden mit `[ballotage id=N]` in Beiträge
eingebunden (im Editor über ⚙ → „Geheime Kugelung einfügen“); dort wird direkt abgestimmt.
Nicht Berechtigte sehen nur einen neutralen Hinweis. `/ballotage` listet alle geplanten
und laufenden Kugelungen, `/ballotage/manage` ist die Verwaltung für die Aufsichtsgruppe
und Admins. Für Stimmberechtigte erscheint ein Link „Kugelungen“ in der Seitenleiste.

**Einrichtung:** Plugin per `git clone` in `plugins/` des Discourse-Checkouts einbinden
und mit `./launcher rebuild app` neu bauen (siehe `app.yml`-Beispiel oben). Danach:
`ballotage_enabled` aktivieren, Stimmberechtigten-Gruppe (`ballotage_voting_group`) und
Aufsichtsgruppe (`ballotage_oversight_group`) festlegen, Zeitzone
(`ballotage_timezone`, leer = automatisch) prüfen und optional der Aufsichtsgruppe auch die Verwaltung
erlauben (`ballotage_oversight_can_manage`).

**Nutzung:** Eine Kugelung wird mit Titel, Start- und Endtag angelegt (Standardzeiten
00:01–23:59, individuelle Uhrzeiten optional). Mehrere Kugelungen können gleichzeitig
geplant oder laufend sein. Sie kann vor Ablauf storniert werden; nach Ende (oder
Stornierung) kann sie finalisiert werden — mit Warnhinweis, da dies unwiderruflich
Ergebnis und Teilnehmerliste löscht. Finalisierte Kugelungen lassen sich anschließend
ganz aus der Liste löschen.

Erstveröffentlichung, noch nicht im produktiven Langzeiteinsatz erprobt. Voraussetzung:
Discourse 2026.7 oder neuer. Lizenz: GPL-3.0.
