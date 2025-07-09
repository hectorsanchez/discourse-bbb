import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { isEmpty } from "@ember/utils";

export default class InsertBbbModal extends Component {
  @tracked meetingID = "";
  @tracked attendeePW = "";
  @tracked moderatorPW = "";
  @tracked buttonText = "";
  @tracked mobileIframe = false;
  @tracked desktopIframe = true;

  get insertDisabled() {
    return isEmpty(this.meetingID);
  }

  randomID() {
    return Math.random().toString(36).slice(-8);
  }

  @action
  insert() {
    const btnTxt = this.buttonText ? ` label="${this.buttonText}"` : "";
    this.args.model.toolbarEvent.addText(
      `[wrap=discourse-bbb meetingID="${
        this.meetingID
      }"${btnTxt} attendeePW="${this.randomID()}" moderatorPW="${this.randomID()}" mobileIframe="${
        this.mobileIframe
      }" desktopIframe="${this.desktopIframe}"][/wrap]`
    );
    this.args.closeModal();
  }
}
