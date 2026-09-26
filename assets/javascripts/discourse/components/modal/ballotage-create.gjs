import Component from "@glimmer/component";
import { action } from "@ember/object";
import DModal from "discourse/ui-kit/d-modal";
import { i18n } from "discourse-i18n";
import BallotageForm from "../ballotage-form";

export default class BallotageCreate extends Component {
  @action
  created(ballot) {
    this.args.model.onCreated?.(ballot);
    this.args.closeModal();
  }

  <template>
    <DModal
      class="ballotage-create-modal"
      @title={{i18n "ballotage.manage.new"}}
      @closeModal={{@closeModal}}
    >
      <:body>
        {{#if @model.fromComposer}}
          <p class="ballotage-create-modal__intro">{{i18n
              "ballotage.composer.intro"
            }}</p>
        {{/if}}
        <BallotageForm @onCreated={{this.created}} @onCancel={{@closeModal}} />
      </:body>
    </DModal>
  </template>
}
