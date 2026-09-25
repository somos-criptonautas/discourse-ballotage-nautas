# discourse-ballotage

[![Discourse Plugin](https://github.com/DaniW42/discourse-ballotage/actions/workflows/discourse-plugin.yml/badge.svg)](https://github.com/DaniW42/discourse-ballotage/actions/workflows/discourse-plugin.yml)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Discourse 2026.7+](https://img.shields.io/badge/Discourse-2026.7%2B-blue?logo=discourse)](https://www.discourse.org/)
[![Meta topic](https://img.shields.io/badge/Meta-discussion-orange?logo=discourse)](https://meta.discourse.org/t/ballotage-secret-black-white-ball-ballots/413266)

A [Discourse](https://www.discourse.org/) plugin for **secret black/white-ball ballots**
("ballotage" — in German "Kugelung"), as used by clubs, societies and other membership
organizations for admitting new members. A member either casts a black or a white ball;
who voted is recorded, but what they voted is not.

## What it does

- A voting page at `/ballotage` where eligible members cast one vote (black or white) in
  the currently open ballot. A vote cannot be changed once cast.
- A management page at `/ballotage/manage` for an oversight group (and admins), showing
  who has voted while a ballot is running, and the result once it has ended.
- Only one ballot can be scheduled or open at a time.
- Ballots can be scheduled with a start and end day (default opening/closing times of
  00:01 / 23:59, or custom times), cancelled before they end, and finalized afterwards.
- Finalizing a ballot irreversibly deletes the result and the list of who voted, leaving
  only the title, period and status.

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
  management page shows the participant list (who has voted) but not the black/white
  counts. Showing both at the same time would let an observer match a new name appearing
  on the list to whichever counter just moved. Once the ballot is over no further votes
  can arrive, so the final counts are shown.
- **Deleted users.** If a member who voted is deleted, their participation row is kept so
  "votes cast" keeps matching the black/white tally; they just drop off the voter list.
  Finalizing removes those rows like all others.
- **Finalizing is irreversible.** It deletes the participation rows and zeroes the
  counters, keeping only the ballot's title, period and status (ended/cancelled). There is
  no undo.

**Honest limits.** This protects against what the application itself reveals. It does not
protect against someone with direct database access watching the two counters change in
real time during an open ballot and correlating that with who is known to be voting at
that moment — such access is out of scope for an application-level plugin and needs to be
handled organizationally (e.g. restrict database/console access during ballots).

## Pages

- **`/ballotage`** — the voting page. Visible to members of the voting group (to cast a
  vote) and to the oversight group / admins (to see that a ballot exists, with a link to
  management).
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
| `ballotage_timezone` | `Europe/Berlin` | IANA time zone used for ballot start/end times. |

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
          - git clone https://github.com/DaniW42/discourse-ballotage.git
```

```bash
./launcher rebuild app
```

### Setup after install

1. Enable the `ballotage_enabled` site setting.
2. Choose the `ballotage_voting_group` (who may vote) and `ballotage_oversight_group`
   (who oversees ballots).
3. Set `ballotage_timezone` to the time zone your organization schedules ballots in.
4. Optionally decide whether the oversight group may manage ballots
   (`ballotage_oversight_can_manage`), or leave that to admins only.
5. Optionally add a link to `/ballotage` to the sidebar or a custom menu link so eligible
   members can find the voting page.

## Usage

- From `/ballotage/manage`, someone with manage permission creates a ballot with a title,
  a start day and an end day. By default it opens at 00:01 on the start day and closes at
  23:59 on the end day; check "custom times" to set specific start/end times instead.
- Only one ballot can be scheduled or open at a time — the form is hidden while one is
  active.
- A scheduled or open ballot can be cancelled; votes already cast are kept until the
  ballot is finalized.
- Once a ballot has ended (or been cancelled), it can be finalized. This is irreversible
  and permanently deletes the result and the participant list — a confirmation warns
  about this before proceeding.
- A finalized ballot can then be deleted to remove it from the list entirely. Only
  finalized ballots can be deleted, so a result can never be lost in a single step.

## Development & tests

There is a spec suite under `spec/` (models, requests, lib). Run it from inside a
Discourse checkout with this plugin in `plugins/`:

```bash
bundle exec rspec plugins/discourse-ballotage/spec
```

Linting uses the standard Discourse plugin configuration (ESLint, Prettier,
Stylelint, RuboCop, Syntax Tree), run from the Discourse checkout:

```bash
bin/lint plugins/discourse-ballotage
```

CI runs specs and linters on every push to `main` and on pull requests.

## Status

First release, not yet battle-tested in production. Compatible with Discourse 2026.7 and
later.

## License

GPL-3.0. See [LICENSE](LICENSE).

---

## Deutsch

**discourse-ballotage** ist ein Discourse-Plugin für geheime Kugelungen (Abstimmungen mit
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

**Seiten:** `/ballotage` (Abstimmung für stimmberechtigte Mitglieder) und
`/ballotage/manage` (Verwaltung für die Aufsichtsgruppe und Admins).

**Einrichtung:** Plugin per `git clone` in `plugins/` des Discourse-Checkouts einbinden
und mit `./launcher rebuild app` neu bauen (siehe `app.yml`-Beispiel oben). Danach:
`ballotage_enabled` aktivieren, Stimmberechtigten-Gruppe (`ballotage_voting_group`) und
Aufsichtsgruppe (`ballotage_oversight_group`) festlegen, Zeitzone
(`ballotage_timezone`) prüfen, optional der Aufsichtsgruppe auch die Verwaltung
erlauben (`ballotage_oversight_can_manage`) und `/ballotage` in der Seitenleiste oder
einem eigenen Menüpunkt verlinken.

**Nutzung:** Eine Kugelung wird mit Titel, Start- und Endtag angelegt (Standardzeiten
00:01–23:59, individuelle Uhrzeiten optional). Es kann immer nur eine Kugelung gleichzeitig
geplant oder laufend sein. Sie kann vor Ablauf storniert werden; nach Ende (oder
Stornierung) kann sie finalisiert werden — mit Warnhinweis, da dies unwiderruflich
Ergebnis und Teilnehmerliste löscht. Finalisierte Kugelungen lassen sich anschließend
ganz aus der Liste löschen.

Erstveröffentlichung, noch nicht im produktiven Langzeiteinsatz erprobt. Voraussetzung:
Discourse 2026.7 oder neuer. Lizenz: GPL-3.0.
