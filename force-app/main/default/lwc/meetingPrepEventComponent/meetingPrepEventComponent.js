import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { WorkspaceAPI } from "lightning/platformWorkspaceApi";
import generateMeetingPrep from "@salesforce/apex/MeetingPrepIntelligence.generateMeetingPrepFromLWC";
import getEventWithRelatedData from "@salesforce/apex/MeetingPrepIntelligence.getEventWithRelatedData";
import AGENTFORCE_ICON from "@salesforce/resourceUrl/AgentforceRGBIcon";

export default class MeetingPrepEventComponent extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  agentforceIcon = AGENTFORCE_ICON;
  prepBrief;
  @track isLoading = false;
  @track error;
  @track currentLoadingMessage = "";
  hasExistingPrep = false;
  @track eventData;
  workspaceApi;

  connectedCallback() {
    this.resolveWorkspaceAPI();
    this.loadEventData();
  }

  async resolveWorkspaceAPI() {
    try {
      this.workspaceApi = await WorkspaceAPI.getInstance();
    } catch {
      // WorkspaceAPI not available (not in console), will fall back to NavigationMixin
      console.log("WorkspaceAPI not available, using NavigationMixin");
    }
  }

  loadEventData() {
    if (!this.recordId) return;

    getEventWithRelatedData({ eventId: this.recordId })
      .then((result) => {
        if (result) {
          this.eventData = result;
        }
      })
      .catch((error) => {
        console.error("Error loading event data:", error);
      });
  }

  loadingMessages = [
    "Analyzing meeting context with Agentforce...",
    "Gathering attendee profiles...",
    "Reviewing account health and opportunities...",
    "Analyzing recent activity timeline...",
    "Fetching competitive intelligence...",
    "Generating strategic talking points...",
    "Preparing questions and objection handling...",
    "Finalizing your meeting prep brief..."
  ];
  loadingMessageInterval = null;
  loadingMessageIndex = 0;

  disconnectedCallback() {
    this.stopLoadingMessages();
  }

  renderedCallback() {
    // Render competitive intel HTML when DOM is ready
    if (
      this.prepBrief &&
      this.prepBrief.competitiveIntelligence &&
      !this.isLoading
    ) {
      const intelContainer = this.template.querySelector(
        ".column-right .content-body"
      );
      if (intelContainer) {
        // Clear existing content first
        while (intelContainer.firstChild) {
          intelContainer.removeChild(intelContainer.firstChild);
        }
        // Create wrapper div and set innerHTML
        const wrapper = document.createElement("div");
        wrapper.className = "competitive-intel-content";
        // eslint-disable-next-line @lwc/lwc/no-inner-html
        wrapper.innerHTML = this.prepBrief.competitiveIntelligence;
        intelContainer.appendChild(wrapper);
      }
    }
  }

  get hasCompetitiveIntel() {
    return (
      this.prepBrief &&
      this.prepBrief.competitiveIntelligence &&
      this.prepBrief.competitiveIntelligence.trim().length > 0
    );
  }

  startLoadingMessages() {
    this.loadingMessageIndex = 0;
    this.currentLoadingMessage = this.loadingMessages[this.loadingMessageIndex];

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.loadingMessageInterval = setInterval(() => {
      this.loadingMessageIndex =
        (this.loadingMessageIndex + 1) % this.loadingMessages.length;
      this.currentLoadingMessage =
        this.loadingMessages[this.loadingMessageIndex];
    }, 3000);
  }

  stopLoadingMessages() {
    if (this.loadingMessageInterval) {
      clearInterval(this.loadingMessageInterval);
      this.loadingMessageInterval = null;
    }
    this.currentLoadingMessage = "";
  }

  get hasPrep() {
    return this.prepBrief != null;
  }

  get showGenerateButton() {
    return !this.hasPrep && !this.isLoading;
  }

  get showRegenerateButton() {
    return this.hasPrep && !this.isLoading;
  }

  handleGeneratePrep() {
    this.generatePrep(false);
  }

  handleRegeneratePrep() {
    this.generatePrep(true);
  }

  generatePrep(regenerate) {
    this.isLoading = true;
    this.error = undefined;
    this.startLoadingMessages();

    generateMeetingPrep({
      eventId: this.recordId,
      regenerate: regenerate
    })
      .then((result) => {
        if (result) {
          if (result.success) {
            this.prepBrief = result;
            this.hasExistingPrep = !regenerate;
            this.showSuccessToast("Meeting prep generated successfully!");
          } else {
            this.error = result.message || "Unknown error occurred";
            this.showErrorToast(
              result.message || "Error generating meeting prep"
            );
          }
        }
      })
      .catch((error) => {
        this.error = error.body
          ? error.body.message
          : error.message || "Unknown error";
        this.showErrorToast("Error generating meeting prep: " + this.error);
      })
      .finally(() => {
        this.isLoading = false;
        this.stopLoadingMessages();
      });
  }

  renderCompetitiveIntel() {
    if (this.prepBrief && this.prepBrief.competitiveIntelligence) {
      const intelContainer = this.template.querySelector(".intel-content");
      if (intelContainer) {
        // eslint-disable-next-line @lwc/lwc/no-inner-html
        intelContainer.innerHTML = this.prepBrief.competitiveIntelligence;
      }
    }
  }

  showSuccessToast(message) {
    const event = new ShowToastEvent({
      title: "Success",
      message: message,
      variant: "success"
    });
    this.dispatchEvent(event);
  }

  showErrorToast(message) {
    const event = new ShowToastEvent({
      title: "Error",
      message: message,
      variant: "error",
      mode: "sticky"
    });
    this.dispatchEvent(event);
  }

  navigateToMeetingPrep() {
    if (this.prepBrief && this.prepBrief.meetingPrepId) {
      this.navigateToRecord(this.prepBrief.meetingPrepId, "Meeting_Prep__c");
    }
  }

  async navigateToRecord(recordId, objectApiName, activeTab = null) {
    const pageReference = {
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        objectApiName: objectApiName,
        actionName: "view"
      }
    };

    // Add activeTab to state if provided
    if (activeTab) {
      pageReference.state = {
        activeTab: activeTab
      };
    }

    // Use WorkspaceAPI if in console, otherwise use NavigationMixin
    if (this.workspaceApi) {
      try {
        await this.workspaceApi.openSubtab({
          pageReference: pageReference,
          focus: true
        });
      } catch (error) {
        console.error("Error opening subtab:", error);
        // Fallback to NavigationMixin
        this[NavigationMixin.Navigate](pageReference);
      }
    } else {
      this[NavigationMixin.Navigate](pageReference);
    }
  }

  handleAccountClick(event) {
    event.stopPropagation();
    if (this.eventData && this.eventData.Account) {
      this.navigateToRecord(this.eventData.Account.Id, "Account");
    }
  }

  handleContactClick(event) {
    event.stopPropagation();
    if (this.eventData && this.eventData.Contact) {
      this.navigateToRecord(this.eventData.Contact.Id, "Contact");
    }
  }

  handleEventClick() {
    if (this.recordId) {
      this.navigateToRecord(this.recordId, "Event");
    }
  }

  get accountName() {
    return this.eventData?.Account?.Name || null;
  }

  get accountId() {
    return this.eventData?.Account?.Id || null;
  }

  get contactName() {
    return this.eventData?.Contact?.Name || null;
  }

  get contactId() {
    return this.eventData?.Contact?.Id || null;
  }

  get formattedEventDateTime() {
    if (!this.eventData || !this.eventData.StartDateTime) return "";
    const date = new Date(this.eventData.StartDateTime);
    return date.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hour12: true
    });
  }

  printPrep() {
    window.print();
  }
}
