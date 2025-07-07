import Controller from "@ember/controller";
import { action } from "@ember/object";
import { tracked } from "@glimmer/tracking";
import { isEmpty } from "@ember/utils";

export default class InsertBbbController extends Controller {
  @tracked meetingID = "";
  @tracked attendeePW = "";
  @tracked moderatorPW = "";
  @tracked buttonText = "";
  @tracked mobileIframe = false;
  @tracked desktopIframe = true;

  keyDown(e) {
    if (e.keyCode === 13) {
      e.preventDefault();
      e.stopPropagation();
      return false;
    }
  }

  onShow() {
    this.meetingID = "";
    this.attendeePW = "";
    this.moderatorPW = "";
    this.buttonText = "";
    this.mobileIframe = false;
    this.desktopIframe = true;
  }

  randomID() {
    return Math.random().toString(36).slice(-8);
  }

  get insertDisabled() {
    return isEmpty(this.meetingID);
  }

  @action
  insert() {
    const btnTxt = this.buttonText ? ` label="${this.buttonText}"` : "";
    this.model.toolbarEvent.addText(
      `[wrap=discourse-bbb meetingID="${
        this.meetingID
      }"${btnTxt} attendeePW="${this.randomID()}" moderatorPW="${this.randomID()}" mobileIframe="${
        this.mobileIframe
      }" desktopIframe="${this.desktopIframe}"][/wrap]`
    );
    this.model.closeModal();
  }

  @action
  cancel() {
    this.model.closeModal();
  }
}
