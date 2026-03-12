import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { WorkspaceAPI } from "lightning/platformWorkspaceApi";
import generateMeetingPrep from "@salesforce/apex/MeetingPrepIntelligence.generateMeetingPrepFromLWC";
import generateBriefOnly from "@salesforce/apex/MeetingPrepIntelligence.generateMeetingPrepBriefOnly";
import generateIntelOnly from "@salesforce/apex/MeetingPrepIntelligence.generateCompetitiveIntelOnly";
import getEventWithRelatedData from "@salesforce/apex/MeetingPrepIntelligence.getEventWithRelatedData";
import AGENTFORCE_ICON from "@salesforce/resourceUrl/AgentforceRGBIcon";

export default class MeetingPrepEventComponent extends NavigationMixin(
  LightningElement
) {
  @api recordId;

  agentforceIcon = AGENTFORCE_ICON;
  prepBrief;
  @track isLoading = false;
  @track isLoadingBrief = false;
  @track isLoadingIntel = false;
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

  // Phase 1: Both loading
  bothLoadingMessages = [
    "Agentforce is analyzing your meeting context...",
    "Gathering attendee profiles and account data...",
    "Reviewing opportunities, cases, and activity...",
    "Researching competitive intelligence in parallel...",
    "Generating your strategic meeting prep brief..."
  ];

  // Phase 2: Brief done, intel still loading
  intelOnlyMessages = [
    "Agentforce is almost done \u2014 finishing competitive intelligence...",
    "Analyzing market positioning and recent news...",
    "Wrapping up competitive insights for your meeting..."
  ];

  // Phase 3: Intel done, brief still loading (less common)
  briefOnlyMessages = [
    "Agentforce is finalizing your meeting prep brief...",
    "Generating talking points and strategic questions...",
    "Almost there \u2014 preparing your full brief..."
  ];

  loadingMessageInterval = null;
  loadingMessageIndex = 0;

  disconnectedCallback() {
    this.stopLoadingMessages();
  }

  renderedCallback() {
    // Render prep brief HTML into manual DOM (matches competitive intel approach)
    if (
      this.prepBrief &&
      this.prepBrief.prepBriefHTML &&
      !this.isLoadingBrief
    ) {
      const briefContainer = this.template.querySelector(
        ".prep-brief-content"
      );
      if (briefContainer && !briefContainer._rendered) {
        const wrapper = document.createElement("div");
        wrapper.className = "prep-brief-inner-content";
        // eslint-disable-next-line @lwc/lwc/no-inner-html
        wrapper.innerHTML = this.prepBrief.prepBriefHTML;
        briefContainer.appendChild(wrapper);
        briefContainer._rendered = true;
      }
    }

    // Render competitive intel HTML when DOM is ready
    if (
      this.prepBrief &&
      this.prepBrief.competitiveIntelligence &&
      !this.isLoadingIntel
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

  get activeLoadingMessages() {
    if (this.isLoadingBrief && this.isLoadingIntel) {
      return this.bothLoadingMessages;
    } else if (this.isLoadingIntel) {
      return this.intelOnlyMessages;
    } else if (this.isLoadingBrief) {
      return this.briefOnlyMessages;
    }
    return [];
  }

  startLoadingMessages() {
    this.loadingMessageIndex = 0;
    this.currentLoadingMessage = this.activeLoadingMessages[0] || "";

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.loadingMessageInterval = setInterval(() => {
      const messages = this.activeLoadingMessages;
      if (messages.length > 0) {
        this.loadingMessageIndex =
          (this.loadingMessageIndex + 1) % messages.length;
        this.currentLoadingMessage = messages[this.loadingMessageIndex];
      }
    }, 7000);
  }

  transitionLoadingMessages() {
    // Reset index when switching phases so messages start fresh
    this.loadingMessageIndex = 0;
    const messages = this.activeLoadingMessages;
    if (messages.length > 0) {
      this.currentLoadingMessage = messages[0];
    }
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
    return this.hasPrep && !this.isLoading && !this.isLoadingBrief;
  }

  get showSkeletonLayout() {
    return this.isLoadingBrief || this.isLoadingIntel;
  }

  handleGeneratePrep() {
    this.generatePrep(false);
  }

  handleRegeneratePrep() {
    this.generatePrep(true);
  }

  generatePrep(regenerate) {
    this.isLoading = true;
    this.isLoadingBrief = true;
    this.isLoadingIntel = true;
    this.error = undefined;
    this.startLoadingMessages();

    // Fire both calls in parallel
    const briefPromise = generateBriefOnly({
      eventId: this.recordId,
      regenerate: regenerate
    })
      .then((result) => {
        if (result) {
          if (result.success) {
            // Initialize or merge into prepBrief — preserve any intel already loaded
            if (this.prepBrief) {
              const existingIntel = this.prepBrief.competitiveIntelligence;
              this.prepBrief = { ...result };
              if (existingIntel) {
                this.prepBrief.competitiveIntelligence = existingIntel;
              }
            } else {
              this.prepBrief = { ...result };
            }
            this.hasExistingPrep = !regenerate;
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
        this.isLoadingBrief = false;
        if (this.isLoadingIntel) {
          this.transitionLoadingMessages();
        }
      });

    const intelPromise = generateIntelOnly({
      eventId: this.recordId,
      regenerate: regenerate
    })
      .then((result) => {
        if (result && result.success && result.competitiveIntelligence) {
          if (this.prepBrief) {
            this.prepBrief = {
              ...this.prepBrief,
              competitiveIntelligence: result.competitiveIntelligence
            };
          } else {
            // Brief hasn't resolved yet — store intel for merge
            this.prepBrief = { competitiveIntelligence: result.competitiveIntelligence };
          }
        }
      })
      .catch((error) => {
        console.error("Error generating competitive intel:", error);
        // Non-fatal — brief still works without intel
      })
      .finally(() => {
        this.isLoadingIntel = false;
        if (this.isLoadingBrief) {
          this.transitionLoadingMessages();
        }
      });

    Promise.all([briefPromise, intelPromise]).finally(() => {
      this.isLoading = false;
      this.stopLoadingMessages();
      if (this.prepBrief && this.prepBrief.success) {
        this.showSuccessToast("Meeting prep generated successfully!");
      }
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
