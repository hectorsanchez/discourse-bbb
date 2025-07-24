import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { isEmpty } from "@ember/utils";
import I18n from "@ember/locales/i18n";
import { ajax } from "discourse/lib/ajax";

export default class InsertBbbModal extends Component {
  @tracked meetingName = "";
  @tracked startDate = "";
  @tracked startTime = "";
  @tracked duration = "";
  @tracked errorMsg = "";

  get insertDisabled() {
    return (
      isEmpty(this.meetingName) ||
      isEmpty(this.startDate) ||
      isEmpty(this.startTime) ||
      isEmpty(this.duration) ||
      isNaN(Number(this.duration)) ||
      Number(this.duration) <= 0
    );
  }

  @action
  handleInput(event) {
    const value = event.target.value;
    if (value.length > 30) {
      this.meetingName = value.substring(0, 30);
      event.target.value = this.meetingName;
    } else {
      this.meetingName = value;
    }
  }

  @action
  handleStartDateInput(event) {
    this.startDate = event.target.value;
  }

  @action
  handleStartTimeInput(event) {
    this.startTime = event.target.value;
  }

  @action
  handleDurationInput(event) {
    const value = event.target.value;
    // Solo permitir números positivos
    if (Number(value) < 1) {
      this.duration = "";
      event.target.value = "";
    } else {
      this.duration = value;
    }
  }

  @action
  async insert() {
    this.errorMsg = "";
    try {
      const data = {
        mode: "new",
        meetingName: this.meetingName,
        startDate: this.startDate,
        startTime: this.startTime,
        duration: this.duration
      };
      const res = await ajax("/bbb/create.json", {
        type: "POST",
        data
      });
      if (res.url) {
        window.open(res.url, "_blank");
        this.args.closeModal?.();
      } else if (res.error) {
        this.errorMsg = this._errorMessage(res.error);
      }
    } catch (e) {
      let msg = e?.jqXHR?.responseJSON?.error || e?.message;
      this.errorMsg = this._errorMessage(msg);
    }
  }

  _errorMessage(msg) {
    if (!msg) return I18n.t("js.bbb.errors.create_failed");
    if (msg.match(/not started/i)) return I18n.t("js.bbb.errors.not_started");
    if (msg.match(/already ended/i)) return I18n.t("js.bbb.errors.ended");
    if (msg.match(/missing/i)) return I18n.t("js.bbb.errors.missing_fields");
    if (msg.match(/invalid date/i)) return I18n.t("js.bbb.errors.invalid_date");
    if (msg.match(/invalid duration/i)) return I18n.t("js.bbb.errors.invalid_duration");
    return I18n.t("js.bbb.errors.create_failed");
  }
}
