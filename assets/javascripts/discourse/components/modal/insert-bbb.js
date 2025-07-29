import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { isEmpty } from "@ember/utils";
import I18n from "I18n";
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
      isNaN(Number(this.duration)) ||
      Number(this.duration) < 0
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
        duration: this.duration || "60" // Default 60 minutos si está vacío
      };
      const res = await ajax("/bbb/create.json", {
        type: "POST",
        data
      });
      
      if (res.url) {
        // Si hay URL, abrir inmediatamente (está dentro del rango)
        window.open(res.url, "_blank");
        this.args.closeModal?.();
      } else if (res.success) {
        // Si se creó exitosamente pero está fuera del rango, insertar marcador único
        // Usar formato que NO active ningún conversor de Discourse
        const meetingData = `discourse-bbb|${this.meetingName}|${this.startDate}|${this.startTime}|${this.duration || '60'}`;
        this.args.model.toolbarEvent.addText(
          `{{BBB-MEETING:${meetingData}}}Join Meeting: ${this.meetingName}{{/BBB-MEETING}}`
        );
        this.args.closeModal?.();
      } else if (res.error) {
        this.errorMsg = this._errorMessage(res.error, res);
      }
    } catch (e) {
      let msg = e?.jqXHR?.responseJSON?.error || e?.message;
      let responseData = e?.jqXHR?.responseJSON;
      this.errorMsg = this._errorMessage(msg, responseData);
    }
  }

  _errorMessage(msg, responseData) {
    if (!msg) return I18n.t("js.bbb.errors.create_failed");
    
    if (msg.match(/not started/i)) {
      let startTime = responseData?.start_time ? new Date(responseData.start_time).toLocaleString() : '';
      return I18n.t("js.bbb.errors.not_started") + (startTime ? ` (Starts: ${startTime})` : '');
    }
    
    if (msg.match(/already ended/i)) {
      let endTime = responseData?.end_time ? new Date(responseData.end_time).toLocaleString() : '';
      return I18n.t("js.bbb.errors.ended") + (endTime ? ` (Ended: ${endTime})` : '');
    }
    
    if (msg.match(/past/i)) return I18n.t("js.bbb.errors.past_date");
    if (msg.match(/missing/i)) return I18n.t("js.bbb.errors.missing_fields");
    if (msg.match(/invalid date/i)) return I18n.t("js.bbb.errors.invalid_date");
    if (msg.match(/invalid duration/i)) return I18n.t("js.bbb.errors.invalid_duration");
    
    return I18n.t("js.bbb.errors.create_failed");
  }
}
