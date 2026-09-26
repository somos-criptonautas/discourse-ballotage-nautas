import Component from "@glimmer/component";
import { concat } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import { isoDateFromToday } from "../lib/ballotage-format";

const APPROVAL_RULES = ["majority", "two_thirds", "unanimous"];
const VISIBILITIES = ["outcome", "counts", "overseers"];

// Creates a ballot; used by the composer button and the management page.
export default class BallotageForm extends Component {
  @service currentUser;
  @service siteSettings;

  formData = {
    kind: "admission",
    rejection_threshold: 1,
    approval_rule: "majority",
    quorum_percent: null,
    result_visibility: "outcome",
    keep_counts: false,
    title: "",
    start_date: isoDateFromToday(1),
    end_date: isoDateFromToday(7),
    custom_times: false,
    start_time: "00:01",
    end_time: "23:59",
  };

  // Switching kind resets visibility to that kind's usual practice:
  // admissions announce only the outcome, proposals their counts too.
  // Same fallback as the server: configured zone, else the creator's own.
  get zone() {
    return (
      this.siteSettings.ballotage_timezone ||
      this.currentUser?.user_option?.timezone ||
      Intl.DateTimeFormat().resolvedOptions().timeZone
    );
  }

  @action
  async setKind(value, { set }) {
    await set("kind", value);
    const proposal = value === "proposal";
    await set("result_visibility", proposal ? "counts" : "outcome");
    await set("keep_counts", proposal);
  }

  @action
  async submit(data) {
    const payload = {
      title: data.title,
      start_date: data.start_date,
      end_date: data.end_date,
      kind: data.kind,
      result_visibility: data.result_visibility,
      keep_counts: data.result_visibility === "counts" && !!data.keep_counts,
    };
    if (data.kind === "admission") {
      payload.rejection_threshold = data.rejection_threshold;
    } else {
      payload.approval_rule = data.approval_rule;
    }
    if (data.quorum_percent) {
      payload.quorum_percent = data.quorum_percent;
    }
    if (data.custom_times) {
      payload.start_time = data.start_time;
      payload.end_time = data.end_time;
    }
    try {
      const result = await ajax("/ballotage/ballots.json", {
        type: "POST",
        data: payload,
      });
      this.args.onCreated?.(result.ballot);
    } catch (e) {
      popupAjaxError(e);
    }
  }

  <template>
    <Form
      class="ballotage-form"
      @data={{this.formData}}
      @onSubmit={{this.submit}}
      as |form data|
    >
      <form.Field
        @name="kind"
        @title={{i18n "ballotage.manage.form.kind"}}
        @type="radio-group"
        @validation="required"
        @onSet={{this.setKind}}
        @format="full"
        as |field|
      >
        <field.Control as |group|>
          <group.Radio @value="admission">{{i18n
              "ballotage.kind.admission"
            }}</group.Radio>
          <group.Radio @value="proposal">{{i18n
              "ballotage.kind.proposal"
            }}</group.Radio>
        </field.Control>
      </form.Field>

      <form.Field
        @name="title"
        @title={{i18n "ballotage.manage.form.title"}}
        @type="input-text"
        @validation="required|length:1,255"
        @format="full"
        as |field|
      >
        <field.Control
          placeholder={{i18n "ballotage.manage.form.title_placeholder"}}
        />
      </form.Field>

      <form.Row as |row|>
        <row.Col @size={{6}}>
          <form.Field
            @name="start_date"
            @title={{i18n "ballotage.manage.form.start_date"}}
            @type="input-date"
            @validation="required"
            @format="full"
            as |field|
          >
            <field.Control />
          </form.Field>
        </row.Col>
        <row.Col @size={{6}}>
          <form.Field
            @name="end_date"
            @title={{i18n "ballotage.manage.form.end_date"}}
            @type="input-date"
            @validation="required"
            @format="full"
            as |field|
          >
            <field.Control />
          </form.Field>
        </row.Col>
      </form.Row>

      <form.Field
        @name="custom_times"
        @title={{i18n "ballotage.manage.form.custom_times"}}
        @type="checkbox"
        @description={{if
          data.custom_times
          (i18n "ballotage.manage.form.times_zone_hint" zone=this.zone)
          (i18n "ballotage.manage.form.default_times_hint" zone=this.zone)
        }}
        as |field|
      >
        <field.Control />
      </form.Field>

      {{#if data.custom_times}}
        <form.Row as |row|>
          <row.Col @size={{6}}>
            <form.Field
              @name="start_time"
              @title={{i18n "ballotage.manage.form.start_time"}}
              @type="input-time"
              @validation="required"
              @format="full"
              as |field|
            >
              <field.Control />
            </form.Field>
          </row.Col>
          <row.Col @size={{6}}>
            <form.Field
              @name="end_time"
              @title={{i18n "ballotage.manage.form.end_time"}}
              @type="input-time"
              @validation="required"
              @format="full"
              as |field|
            >
              <field.Control />
            </form.Field>
          </row.Col>
        </form.Row>
      {{/if}}

      <form.Row as |row|>
        <row.Col @size={{6}}>
          {{#if (eq data.kind "admission")}}
            <form.Field
              @name="rejection_threshold"
              @title={{i18n "ballotage.manage.form.rejection_threshold"}}
              @description={{i18n
                "ballotage.manage.form.rejection_threshold_hint"
              }}
              @type="input-number"
              @validation="required|integer|between:1,1000"
              @format="full"
              as |field|
            >
              <field.Control min="1" />
            </form.Field>
          {{else}}
            <form.Field
              @name="approval_rule"
              @title={{i18n "ballotage.manage.form.approval_rule"}}
              @description={{i18n "ballotage.manage.form.approval_rule_hint"}}
              @type="select"
              @validation="required"
              @format="full"
              as |field|
            >
              <field.Control as |select|>
                {{#each APPROVAL_RULES as |rule|}}
                  <select.Option @value={{rule}}>{{i18n
                      (concat "ballotage.approval_rule." rule)
                    }}</select.Option>
                {{/each}}
              </field.Control>
            </form.Field>
          {{/if}}
        </row.Col>
        <row.Col @size={{6}}>
          <form.Field
            @name="quorum_percent"
            @title={{i18n "ballotage.manage.form.quorum_percent"}}
            @description={{i18n "ballotage.manage.form.quorum_percent_hint"}}
            @type="input-number"
            @validation="integer|between:1,100"
            @format="full"
            as |field|
          >
            <field.Control min="1" max="100" />
          </form.Field>
        </row.Col>
      </form.Row>

      <form.Field
        @name="result_visibility"
        @title={{i18n "ballotage.manage.form.result_visibility"}}
        @type="select"
        @validation="required"
        @format="full"
        as |field|
      >
        <field.Control as |select|>
          {{#each VISIBILITIES as |visibility|}}
            <select.Option @value={{visibility}}>{{i18n
                (concat "ballotage.result_visibility." visibility)
              }}</select.Option>
          {{/each}}
        </field.Control>
      </form.Field>

      {{#if (eq data.result_visibility "counts")}}
        <form.Field
          @name="keep_counts"
          @title={{i18n "ballotage.manage.form.keep_counts"}}
          @description={{i18n "ballotage.manage.form.keep_counts_hint"}}
          @type="checkbox"
          as |field|
        >
          <field.Control />
        </form.Field>
      {{/if}}

      <form.Actions>
        <form.Submit @label="ballotage.manage.form.submit" />
        {{#if @onCancel}}
          <form.Button class="btn-flat" @action={{@onCancel}} @label="cancel" />
        {{/if}}
      </form.Actions>
    </Form>
  </template>
}
