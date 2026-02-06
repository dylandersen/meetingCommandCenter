import { LightningElement, api } from "lwc";

export default class MeetingPrepRenderer extends LightningElement {
  @api value;

  displayData = {};
  showFullBrief = false;

  connectedCallback() {
    if (this.value) {
      this.displayData = {
        meetingPrepId: this.value.meetingPrepId,
        eventId: this.value.eventId,
        eventSubject: this.value.eventSubject,
        eventDateTime: this.value.eventDateTime,
        eventLocation: this.value.eventLocation,
        prepBriefHTML: this.value.prepBriefHTML,
        attendeeSummary: this.value.attendeeSummary,
        keyTalkingPoints: this.value.keyTalkingPoints,
        recentUpdates: this.value.recentUpdates,
        questionsToAsk: this.value.questionsToAsk,
        potentialObjections: this.value.potentialObjections,
        competitiveIntelligence: this.value.competitiveIntelligence,
        success: this.value.success,
        message: this.value.message
      };
    }
  }

  get hasError() {
    return this.displayData.success === false;
  }

  get hasSuccess() {
    return this.displayData.success === true;
  }

  toggleBrief() {
    this.showFullBrief = !this.showFullBrief;
  }

  navigateToEvent() {
    if (this.displayData.eventId) {
      window.open(
        `/lightning/r/Event/${this.displayData.eventId}/view`,
        "_blank"
      );
    }
  }

  navigateToMeetingPrep() {
    if (this.displayData.meetingPrepId) {
      window.open(
        `/lightning/r/Meeting_Prep__c/${this.displayData.meetingPrepId}/view`,
        "_blank"
      );
    }
  }
}
