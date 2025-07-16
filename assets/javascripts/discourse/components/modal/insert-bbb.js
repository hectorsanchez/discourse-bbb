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
  handleInput(event) {
    console.log("Event triggered!");
    console.log("Input value:", event.target.value);
    
    // Forzar límite de 30 caracteres
    const value = event.target.value;
    if (value.length > 30) {
      this.meetingName = value.substring(0, 30);
      event.target.value = this.meetingName; // Forzar el valor en el DOM
    } else {
      this.meetingName = value;
    }
    console.log("Final meetingName:", this.meetingName);
  }

  @action
  insert() {
    console.log("Insert called with:", this.meetingName);
    this.args.model.toolbarEvent.addText(
      `[wrap=discourse-bbb mode="new" meetingName="${this.meetingName}"][/wrap]`
    );
    
    this.args.closeModal?.();
  }
}
