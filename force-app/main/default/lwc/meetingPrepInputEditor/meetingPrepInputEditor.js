import { api, LightningElement } from "lwc";

export default class MeetingPrepInputEditor extends LightningElement {
  /**
   * Indicate whether in readonly state
   */
  @api
  get readOnly() {
    return this._readOnly;
  }
  set readOnly(value) {
    this._readOnly = value;
  }
  _readOnly = false;
  _value;

  @api
  get value() {
    return this._value;
  }
  set value(value) {
    this._value = value;
  }

  eventId;
  regenerate = false;

  connectedCallback() {
    if (this.value) {
      this.eventId = this.value?.eventId || "";
      this.regenerate = this.value?.regenerate || false;
    }
  }

  handleEventChange(event) {
    this.eventId = event.target.value;
    this.dispatchValueChange();
  }

  handleRegenerateChange(event) {
    this.regenerate = event.target.checked;
    this.dispatchValueChange();
  }

  dispatchValueChange() {
    const valueData = {
      eventId: this.eventId,
      regenerate: this.regenerate
    };

    this.dispatchEvent(
      new CustomEvent("valuechange", {
        detail: {
          value: valueData
        }
      })
    );
  }
}
