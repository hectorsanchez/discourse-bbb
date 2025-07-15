import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { isEmpty } from "@ember/utils";

export default class InsertBbbModal extends Component {
  @tracked meetingType = "existing"; // "existing" o "new"
  @tracked meetingID = "";
  @tracked meetingName = "";
  @tracked attendeePW = "";
  @tracked moderatorPW = "";
  @tracked buttonText = "";
  @tracked mobileIframe = false;
  @tracked desktopIframe = true;

  get insertDisabled() {
    if (this.meetingType === "existing") {
      return isEmpty(this.meetingID);
    } else {
      return isEmpty(this.meetingName);
    }
  }

  @action
  setMeetingType(type) {
    this.meetingType = type;
    // Limpiar campos cuando cambia el tipo
    this.meetingID = "";
    this.meetingName = "";
  }

  randomID() {
    return Math.random().toString(36).slice(-8);
  }

  @action
  insert() {
    const btnTxt = this.buttonText ? ` label="${this.buttonText}"` : "";
    
    if (this.meetingType === "new") {
      // Para nuevo meeting, usar meetingName y mode=new
      this.args.model.toolbarEvent.addText(
        `[wrap=discourse-bbb mode="new" meetingName="${
          this.meetingName
        }"${btnTxt} mobileIframe="${
          this.mobileIframe
        }" desktopIframe="${this.desktopIframe}"][/wrap]`
      );
    } else {
      // Para meeting existente, usar meetingID como antes
      this.args.model.toolbarEvent.addText(
        `[wrap=discourse-bbb meetingID="${
          this.meetingID
        }"${btnTxt} attendeePW="${this.randomID()}" moderatorPW="${this.randomID()}" mobileIframe="${
          this.mobileIframe
        }" desktopIframe="${this.desktopIframe}"][/wrap]`
      );
    }
    
    this.args.closeModal?.();
  }
}
