import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { isEmpty } from "@ember/utils";

export default class InsertBbbModal extends Component {
  @tracked meetingName = "";

  get insertDisabled() {
    return isEmpty(this.meetingName);
  }

  @action
  updateMeetingName(value) {
    console.log("Input value:", value);
    // Forzar límite de 30 caracteres
    if (value.length > 30) {
      this.meetingName = value.substring(0, 30);
    } else {
      this.meetingName = value;
    }
    console.log("Final meetingName:", this.meetingName);
  }

  @action
  insert() {
    // Solo crear nuevo meeting con el nombre
    this.args.model.toolbarEvent.addText(
      `[wrap=discourse-bbb mode="new" meetingName="${this.meetingName}"][/wrap]`
    );
    
    this.args.closeModal?.();
  }
}
