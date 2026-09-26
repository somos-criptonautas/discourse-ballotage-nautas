import Component from "@glimmer/component";
import { action } from "@ember/object";
import Form from "discourse/components/form";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import { isoDateFromToday } from "../lib/ballotage-format";

// Creates a ballot; used by the composer button and the management page.
export default class BallotageForm extends Component {
  formData = {
    title: "",
    start_date: isoDateFromToday(1),
    end_date: isoDateFromToday(7),
    custom_times: false,
    start_time: "00:01",
    end_time: "23:59",
  };

  @action
  async submit(data) {
    const payload = {
      title: data.title,
      start_date: data.start_date,
      end_date: data.end_date,
    };
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
        @description={{unless
          data.custom_times
          (i18n "ballotage.manage.form.default_times_hint")
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

      <form.Actions>
        <form.Submit @label="ballotage.manage.form.submit" />
        {{#if @onCancel}}
          <form.Button class="btn-flat" @action={{@onCancel}} @label="cancel" />
        {{/if}}
      </form.Actions>
    </Form>
  </template>
}
