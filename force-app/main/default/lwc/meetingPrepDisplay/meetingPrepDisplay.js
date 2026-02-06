import { LightningElement, api, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import PREP_BRIEF_HTML from "@salesforce/schema/Meeting_Prep__c.Prep_Brief_HTML__c";
import COMPETITIVE_INTELLIGENCE from "@salesforce/schema/Meeting_Prep__c.Competitive_Intelligence__c";
import ATTENDEE_SUMMARY from "@salesforce/schema/Meeting_Prep__c.Attendee_Summary__c";
import EVENT_FIELD from "@salesforce/schema/Meeting_Prep__c.Event__c";

// Only query fields that we know exist and have data
const FIELDS = [
  PREP_BRIEF_HTML,
  COMPETITIVE_INTELLIGENCE,
  ATTENDEE_SUMMARY,
  EVENT_FIELD
];

export default class MeetingPrepDisplay extends LightningElement {
  @api recordId;

  prepBriefHTML;
  competitiveIntelligence;
  attendeeSummary;
  keyTalkingPoints;
  recentUpdates;
  questionsToAsk;
  potentialObjections;
  eventId;
  generatedDate;
  recordLoaded = false;
  errorMessage;

  connectedCallback() {
    console.log(
      "MeetingPrepDisplay connectedCallback - recordId:",
      this.recordId
    );
  }

  get recordIdValue() {
    return this.recordId;
  }

  @wire(getRecord, { recordId: "$recordIdValue", fields: FIELDS })
  wiredRecord({ error, data }) {
    console.log(
      "wiredRecord called - recordId:",
      this.recordId,
      "data:",
      data,
      "error:",
      error
    );
    if (!this.recordId) {
      console.log("No recordId yet, waiting...");
      return;
    }

    if (data) {
      this.prepBriefHTML = getFieldValue(data, PREP_BRIEF_HTML);
      this.competitiveIntelligence = getFieldValue(
        data,
        COMPETITIVE_INTELLIGENCE
      );
      this.attendeeSummary = getFieldValue(data, ATTENDEE_SUMMARY);
      this.eventId = getFieldValue(data, EVENT_FIELD);
      // Optional fields - set to null if not available
      this.generatedDate = null;
      this.keyTalkingPoints = null;
      this.recentUpdates = null;
      this.questionsToAsk = null;
      this.potentialObjections = null;
      this.recordLoaded = true;
      this.errorMessage = null;
      console.log(
        "Record loaded - prepBriefHTML:",
        this.prepBriefHTML ? "has content" : "empty"
      );
      console.log(
        "Record loaded - competitiveIntelligence:",
        this.competitiveIntelligence ? "has content" : "empty"
      );
      console.log(
        "Record loaded - attendeeSummary:",
        this.attendeeSummary ? "has content" : "empty"
      );
    } else if (error) {
      console.error("Error loading record:", error);
      this.errorMessage = error.body
        ? error.body.message
        : error.message || "Error loading record";
      this.recordLoaded = true;
    }
  }

  get hasPrepBrief() {
    return this.prepBriefHTML && this.prepBriefHTML.trim().length > 0;
  }

  get hasCompetitiveIntelligence() {
    return (
      this.competitiveIntelligence &&
      this.competitiveIntelligence.trim().length > 0
    );
  }

  get hasAttendeeSummary() {
    return this.attendeeSummary && this.attendeeSummary.trim().length > 0;
  }

  get hasKeyTalkingPoints() {
    return this.keyTalkingPoints && this.keyTalkingPoints.trim().length > 0;
  }

  get hasRecentUpdates() {
    return this.recentUpdates && this.recentUpdates.trim().length > 0;
  }

  get hasQuestionsToAsk() {
    return this.questionsToAsk && this.questionsToAsk.trim().length > 0;
  }

  get hasPotentialObjections() {
    return (
      this.potentialObjections && this.potentialObjections.trim().length > 0
    );
  }

  get hasAnyContent() {
    return (
      this.hasPrepBrief ||
      this.hasCompetitiveIntelligence ||
      this.hasAttendeeSummary ||
      this.hasKeyTalkingPoints ||
      this.hasRecentUpdates ||
      this.hasQuestionsToAsk ||
      this.hasPotentialObjections
    );
  }

  renderedCallback() {
    // Render HTML content for fields that need manual DOM manipulation
    if (this.recordLoaded && this.competitiveIntelligence) {
      const intelContainer = this.template.querySelector(
        ".competitive-intel-content"
      );
      if (intelContainer && intelContainer.children.length === 0) {
        const wrapper = document.createElement("div");
        wrapper.className = "competitive-intel-content";
        // eslint-disable-next-line @lwc/lwc/no-inner-html
        wrapper.innerHTML = this.competitiveIntelligence;
        intelContainer.appendChild(wrapper);
      }
    }

    if (this.recordLoaded && this.attendeeSummary) {
      const attendeeContainer = this.template.querySelector(
        ".attendee-summary-content"
      );
      if (attendeeContainer && attendeeContainer.children.length === 0) {
        const wrapper = document.createElement("div");
        wrapper.className = "attendee-summary-content";

        // Check if it's JSON or HTML
        let contentToDisplay = this.attendeeSummary;
        try {
          // Try to parse as JSON
          const parsed = JSON.parse(this.attendeeSummary);
          if (Array.isArray(parsed)) {
            // Format as HTML list
            contentToDisplay =
              "<ul>" +
              parsed
                .map((attendee) => {
                  const parts = [];
                  if (attendee.name)
                    parts.push(`<strong>${attendee.name}</strong>`);
                  if (attendee.title) parts.push(attendee.title);
                  if (attendee.email) parts.push(`Email: ${attendee.email}`);
                  if (attendee.phone) parts.push(`Phone: ${attendee.phone}`);
                  return `<li>${parts.join(" • ")}</li>`;
                })
                .join("") +
              "</ul>";
          }
        } catch {
          // Not JSON, use as-is (might be HTML)
          contentToDisplay = this.attendeeSummary;
        }

        // eslint-disable-next-line @lwc/lwc/no-inner-html
        wrapper.innerHTML = contentToDisplay;
        attendeeContainer.appendChild(wrapper);
      }
    }
  }
}
