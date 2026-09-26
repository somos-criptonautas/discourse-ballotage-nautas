import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { and, eq, not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";
import {
  formatDateTime,
  formatRelative,
  percent,
} from "../lib/ballotage-format";

// One ballot, as shown in a post, on /ballotage and on the management page.
// What it shows follows from the JSON: voters get has_voted, overseers also
// get participation (and black/white once over), managers get the actions.
export default class BallotageCard extends Component {
  @service appEvents;
  @service dialog;
  @service siteSettings;

  // Replaces @ballot after an action. Holds has_voted only — the chosen
  // colour is never kept anywhere on the client.
  @tracked updated = null;
  @tracked deleted = false;
  @tracked busy = false;

  get ballot() {
    return this.updated ?? this.args.ballot;
  }

  get period() {
    const tz = this.siteSettings.ballotage_timezone;
    return i18n("ballotage.period", {
      start: formatDateTime(this.ballot.starts_at, tz),
      end: formatDateTime(this.ballot.ends_at, tz),
    });
  }

  get stateLabel() {
    const { state, finalized } = this.ballot;
    if (finalized && state === "ended") {
      return i18n("ballotage.state.completed");
    }
    return i18n(`ballotage.state.${state}`);
  }

  get timeHint() {
    const { state, starts_at, ends_at } = this.ballot;
    if (state === "scheduled") {
      return i18n("ballotage.vote.starts_relative", {
        relative: formatRelative(starts_at),
      });
    }
    if (state === "open") {
      return i18n("ballotage.vote.ends_relative", {
        relative: formatRelative(ends_at),
      });
    }
    return null;
  }

  get mayVote() {
    const b = this.ballot;
    return b.can_vote && b.state === "open" && !b.has_voted;
  }

  get oversees() {
    return this.ballot.voter_count !== undefined;
  }

  get over() {
    return ["ended", "cancelled"].includes(this.ballot.state);
  }

  get turnout() {
    const { voter_count, eligible_count } = this.ballot;
    return eligible_count
      ? i18n("ballotage.manage.participation_of", {
          voted: voter_count,
          total: eligible_count,
        })
      : i18n("ballotage.manage.participation", { voted: voter_count });
  }

  get turnoutStyle() {
    const { voter_count, eligible_count } = this.ballot;
    return this.barStyle(voter_count, eligible_count);
  }

  get results() {
    const { black_count, white_count } = this.ballot;
    const total = black_count + white_count;
    return ["black", "white"].map((choice) => {
      const count = this.ballot[`${choice}_count`];
      return {
        choice,
        count,
        label: i18n(`ballotage.choice.${choice}`),
        percent: percent(count, total),
        style: this.barStyle(count, total),
      };
    });
  }

  barStyle(part, total) {
    // Numeric only, clamped by percent(), so safe to mark as trusted.
    return trustHTML(`width: ${percent(part, total)}%`);
  }

  @action
  vote(choice) {
    this.dialog.yesNoConfirm({
      message: i18n(`ballotage.vote.confirm_${choice}`),
      didConfirm: async () => {
        const ok = await this.request("/ballotage/vote.json", "POST", {
          ballot_id: this.ballot.id,
          choice,
        });
        if (ok) {
          this.appEvents.trigger("ballotage:voted");
        }
      },
    });
  }

  @action
  cancel() {
    this.dialog.yesNoConfirm({
      message: i18n("ballotage.manage.confirm_cancel", {
        title: this.ballot.title,
      }),
      didConfirm: () =>
        this.request(`/ballotage/ballots/${this.ballot.id}/cancel.json`),
    });
  }

  @action
  finalize() {
    this.dialog.deleteConfirm({
      title: i18n("ballotage.manage.finalize_title"),
      message: i18n("ballotage.manage.confirm_finalize", {
        title: this.ballot.title,
      }),
      confirmButtonLabel: "ballotage.manage.finalize",
      didConfirm: () =>
        this.request(`/ballotage/ballots/${this.ballot.id}/finalize.json`),
    });
  }

  @action
  delete() {
    this.dialog.deleteConfirm({
      title: i18n("ballotage.manage.delete_title"),
      message: i18n("ballotage.manage.confirm_delete", {
        title: this.ballot.title,
      }),
      didConfirm: async () => {
        if (
          await this.request(
            `/ballotage/ballots/${this.ballot.id}.json`,
            "DELETE"
          )
        ) {
          this.deleted = true;
        }
      },
    });
  }

  async request(url, type = "POST", data = undefined) {
    this.busy = true;
    try {
      const result = await ajax(url, { type, data });
      if (result.ballot) {
        this.updated = result.ballot;
      }
      return true;
    } catch (e) {
      popupAjaxError(e);
      return false;
    } finally {
      this.busy = false;
    }
  }

  <template>
    {{#unless this.deleted}}
      <section
        class="ballotage-card ballotage-card--{{this.ballot.state}}"
        aria-labelledby="ballotage-card-title-{{this.ballot.id}}"
      >
        <header class="ballotage-card__header">
          <div class="ballotage-card__heading">
            <h3
              class="ballotage-card__title"
              id="ballotage-card-title-{{this.ballot.id}}"
            >
              {{dIcon "check-to-slot"}}
              <span>{{this.ballot.title}}</span>
            </h3>
            <span
              class="ballotage-status ballotage-status--{{this.ballot.state}}"
            >{{this.stateLabel}}</span>
          </div>
          <p class="ballotage-card__meta">
            <span>{{dIcon "calendar-days"}} {{this.period}}</span>
            {{#if this.timeHint}}
              <span>{{dIcon "clock"}} {{this.timeHint}}</span>
            {{/if}}
          </p>
        </header>

        <div class="ballotage-card__body">
          {{#if this.ballot.finalized}}
            <p class="ballotage-card__text">{{i18n
                "ballotage.manage.finalized_hint"
              }}</p>
          {{else if (eq this.ballot.state "scheduled")}}
            <p class="ballotage-card__text">{{i18n
                "ballotage.vote.not_started"
              }}</p>
          {{else if this.ballot.has_voted}}
            <p class="ballotage-card__done">
              {{dIcon "check"}}
              <span>{{i18n "ballotage.vote.done"}}</span>
            </p>
          {{else if this.mayVote}}
            <p class="ballotage-card__text">{{i18n
                "ballotage.vote.instructions"
              }}</p>
            <div class="ballotage-choices">
              <DButton
                class="btn-default ballotage-choice ballotage-choice--black"
                @action={{fn this.vote "black"}}
                @disabled={{this.busy}}
              >
                <span class="ballotage-ball" aria-hidden="true"></span>
                {{i18n "ballotage.choice.black"}}
              </DButton>
              <DButton
                class="btn-default ballotage-choice ballotage-choice--white"
                @action={{fn this.vote "white"}}
                @disabled={{this.busy}}
              >
                <span class="ballotage-ball" aria-hidden="true"></span>
                {{i18n "ballotage.choice.white"}}
              </DButton>
            </div>
          {{else if (and this.ballot.can_vote this.over)}}
            <p class="ballotage-card__text">{{i18n "ballotage.vote.closed"}}</p>
          {{/if}}

          {{#if (and this.oversees (not this.ballot.finalized))}}
            <div class="ballotage-oversight">
              <div class="ballotage-meter">
                <span class="ballotage-meter__label">{{this.turnout}}</span>
                {{#if this.ballot.eligible_count}}
                  <span class="ballotage-meter__track" aria-hidden="true">
                    <span
                      class="ballotage-meter__bar"
                      style={{this.turnoutStyle}}
                    ></span>
                  </span>
                {{/if}}
              </div>

              {{#if this.over}}
                <ul class="ballotage-results">
                  {{#each this.results as |r|}}
                    <li class="ballotage-meter ballotage-meter--{{r.choice}}">
                      <span class="ballotage-meter__label">
                        <span class="ballotage-ball" aria-hidden="true"></span>
                        {{r.label}}
                        <strong>{{r.count}}</strong>
                        <span class="ballotage-meter__pct">{{r.percent}}%</span>
                      </span>
                      <span class="ballotage-meter__track" aria-hidden="true">
                        <span
                          class="ballotage-meter__bar"
                          style={{r.style}}
                        ></span>
                      </span>
                    </li>
                  {{/each}}
                </ul>
              {{else}}
                <p class="ballotage-card__hint">{{i18n
                    "ballotage.manage.result_after_end"
                  }}</p>
              {{/if}}

              {{#if this.ballot.voters.length}}
                <details class="ballotage-voters">
                  <summary>{{i18n "ballotage.manage.voters"}}</summary>
                  <ul>
                    {{#each this.ballot.voters as |voter|}}
                      <li>
                        <a
                          href="/u/{{voter.username}}"
                          data-user-card={{voter.username}}
                        >{{voter.username}}</a>
                        {{#if voter.name}}
                          <span
                            class="ballotage-voters__name"
                          >{{voter.name}}</span>
                        {{/if}}
                      </li>
                    {{/each}}
                  </ul>
                </details>
              {{/if}}
            </div>
          {{/if}}
        </div>

        {{#if (or this.ballot.can_manage @showPostLink)}}
          <footer class="ballotage-card__footer">
            {{#if (and @showPostLink this.ballot.post_url)}}
              <a
                class="ballotage-card__post-link"
                href={{this.ballot.post_url}}
              >
                {{dIcon "comment"}}
                {{i18n "ballotage.view_discussion"}}
              </a>
            {{/if}}
            {{#if this.ballot.can_manage}}
              <div class="ballotage-card__actions">
                {{#if this.ballot.cancellable}}
                  <DButton
                    class="btn-default btn-small"
                    @action={{this.cancel}}
                    @icon="xmark"
                    @label="ballotage.manage.cancel"
                    @disabled={{this.busy}}
                  />
                {{/if}}
                {{#if this.ballot.finalizable}}
                  <DButton
                    class="btn-danger btn-small"
                    @action={{this.finalize}}
                    @icon="lock"
                    @label="ballotage.manage.finalize"
                    @disabled={{this.busy}}
                  />
                {{/if}}
                {{#if this.ballot.deletable}}
                  <DButton
                    class="btn-danger btn-small"
                    @action={{this.delete}}
                    @icon="trash-can"
                    @label="ballotage.manage.delete"
                    @disabled={{this.busy}}
                  />
                {{/if}}
              </div>
            {{/if}}
          </footer>
        {{/if}}
      </section>
    {{/unless}}
  </template>
}
