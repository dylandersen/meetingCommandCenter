import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { NavigationMixin } from "lightning/navigation";
import { WorkspaceAPI } from "lightning/platformWorkspaceApi";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import getTodaysEvents from "@salesforce/apex/MeetingCommandCenterController.getTodaysEvents";
import getMeetingRecapId from "@salesforce/apex/MeetingCommandCenterController.getMeetingRecapId";
import getMeetingPrepId from "@salesforce/apex/MeetingCommandCenterController.getMeetingPrepId";
import generateEventContent from "@salesforce/apex/MeetingCommandCenterController.generateEventContent";

export default class MeetingCommandCenter extends NavigationMixin(
  LightningElement
) {
  @track events = [];
  @track isLoading = true;
  @track error = null;
  @track showRecapModal = false;
  @track selectedEventId = null;
  @track selectedEventSubject = null;
  @track selectedEventAccountName = null;
  @track selectedEventAccountId = null;
  @track selectedEventContactName = null;
  @track selectedEventContactId = null;
  @track selectedDate = new Date(); // Track the currently selected date
  workspaceApi;

  connectedCallback() {
    // Initialize selectedDate to today in user's timezone
    this.selectedDate = this.getTodayInUserTimezone();
    this.hideDefaultHeader();
    this.detectContainerContext();
    this.loadEvents();
    this.resolveWorkspaceAPI();
  }

  async resolveWorkspaceAPI() {
    try {
      this.workspaceApi = await WorkspaceAPI.getInstance();
    } catch {
      // WorkspaceAPI not available (not in console), will fall back to NavigationMixin
      console.log("WorkspaceAPI not available, using NavigationMixin");
    }
  }

  hideDefaultHeader() {
    // Use setTimeout to ensure DOM is ready and flexipage has rendered
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      // eslint-disable-next-line @lwc/lwc/no-document-query
      const flexipageContainer = document.querySelector(".flexipageTemplate");
      if (!flexipageContainer) return;

      const defaultHeaders = flexipageContainer.querySelectorAll(
        ".slds-page-header, header.slds-page-header, .slds-template__app .slds-page-header"
      );

      defaultHeaders.forEach((header) => {
        const isOurHeader =
          header.closest("c-meeting-command-center") ||
          header.querySelector("c-meeting-command-center") ||
          header.classList.contains("header-section");

        if (!isOurHeader) {
          const headerText = header.textContent || "";
          if (
            headerText.includes("Meeting Command Center") ||
            header.querySelector(".slds-page-header__title")
          ) {
            header.style.display = "none";
            header.style.visibility = "hidden";
            header.style.height = "0";
            header.style.overflow = "hidden";
          }
        }
      });
    }, 200);
  }

  detectContainerContext() {
    // Detect if component is in a Flexipage tab container for styling adjustments
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    setTimeout(() => {
      try {
        // eslint-disable-next-line @lwc/lwc/no-document-query
        const container = this.template.host.closest(
          ".slds-tabs_default__content, .slds-tabs_scoped__content, [data-aura-class*='tab']"
        );
        if (container) {
          // Component is in a tab - apply tab-specific styling class
          this.template.host.classList.add("in-tab-container");
        } else {
          // Component is standalone or in main flexipage region
          this.template.host.classList.add("standalone-page");
        }
      } catch (error) {
        // If detection fails, default to standalone styling
        console.log("Could not detect container context:", error);
        this.template.host.classList.add("standalone-page");
      }
    }, 100);
  }

  loadEvents() {
    this.isLoading = true;
    this.error = null;

    // Format date as YYYY-MM-DD for Apex in user's timezone
    const dateString = this.formatDateForApex(this.selectedDate);

    getTodaysEvents({ selectedDate: dateString })
      .then((result) => {
        this.processEvents(result);
      })
      .catch((error) => {
        this.error = error.body ? error.body.message : error.message;
        this.showToast(
          "Error",
          "Failed to load events: " + this.error,
          "error"
        );
      })
      .finally(() => {
        this.isLoading = false;
      });
  }

  processEvents(rawEvents) {
    const now = new Date();

    this.events = rawEvents.map((event) => {
      const startDateTime = new Date(event.StartDateTime);
      const endDateTime = new Date(event.EndDateTime);
      const isPast = endDateTime < now;
      const isNow = startDateTime <= now && endDateTime >= now;
      const showRecapButton = isPast && !event.Recap_Completed__c;
      const isUpcoming = !isPast && !isNow;

      return {
        ...event,
        formattedStartTime: this.formatTime(startDateTime),
        durationText: this.formatDuration(event.DurationInMinutes),
        isPast,
        isNow,
        isUpcoming,
        showRecapButton,
        relatedName: event.What ? event.What.Name : null,
        relatedId: event.WhatId,
        whoName: event.Who ? event.Who.Name : null,
        whoId: event.WhoId
      };
    });
  }

  formatTime(date) {
    return date.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
      timeZone: TIME_ZONE
    });
  }

  formatDuration(minutes) {
    if (minutes < 60) {
      return `${minutes} min`;
    }
    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    if (remainingMinutes === 0) {
      return `${hours} hr`;
    }
    return `${hours} hr ${remainingMinutes} min`;
  }

  formatDateForApex(date) {
    // Format date as YYYY-MM-DD in user's timezone
    return date.toLocaleDateString("en-CA", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      timeZone: TIME_ZONE
    });
  }

  getTodayInUserTimezone() {
    const now = new Date();
    const userDateStr = now.toLocaleDateString("en-CA", {
      timeZone: TIME_ZONE
    });
    // Parse back to Date object (will be in local timezone but represents correct date)
    const [year, month, day] = userDateStr.split("-");
    return new Date(year, month - 1, day);
  }

  get formattedDate() {
    return this.selectedDate.toLocaleDateString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
      timeZone: TIME_ZONE
    });
  }

  get isToday() {
    // Compare dates formatted in user's timezone
    const todayInUserTz = this.getTodayInUserTimezone();
    const selectedDateStr = this.formatDateForApex(this.selectedDate);
    const todayDateStr = this.formatDateForApex(todayInUserTz);
    return selectedDateStr === todayDateStr;
  }

  get eventCountText() {
    const count = this.events.length;
    if (count === 0) return "No meetings";

    if (count === 1) {
      const event = this.events[0];
      const startTime = event.formattedStartTime;
      const duration = event.durationText;
      return `1 meeting at ${startTime} (${duration})`;
    }

    // Multiple meetings - calculate summary
    const sortedEvents = [...this.events].sort((a, b) => {
      return new Date(a.StartDateTime) - new Date(b.StartDateTime);
    });

    const firstEvent = sortedEvents[0];
    const lastEvent = sortedEvents[sortedEvents.length - 1];
    const firstStartTime = firstEvent.formattedStartTime;
    const lastEndTime = this.formatTime(new Date(lastEvent.EndDateTime));

    // Calculate total hours
    const totalMinutes = this.events.reduce((sum, event) => {
      return sum + (event.DurationInMinutes || 0);
    }, 0);
    const totalHours = (totalMinutes / 60).toFixed(1);

    return `${count} meetings starting at ${firstStartTime}, last meeting at ${lastEndTime} - ${totalHours} hours of meetings total`;
  }

  get emptyStateTitle() {
    return this.isToday ? "No Meetings Today" : "No Meetings on This Day";
  }

  get emptyStateMessage() {
    if (this.isToday) {
      return "You have a clear schedule today. Take advantage of this time to prepare for upcoming meetings or catch up on important tasks.";
    }
    return "No meetings are scheduled for this day. Use the navigation arrows to view other days or create a new meeting.";
  }

  get hasEvents() {
    return !this.isLoading && !this.error && this.events.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.error && this.events.length === 0;
  }

  handleEventClick(event) {
    const eventId = event.currentTarget.dataset.eventId;
    this.navigateToRecord(eventId, "Event");
  }

  handleAccountClick(event) {
    event.stopPropagation();
    const accountId = event.currentTarget.dataset.accountId;
    if (accountId) {
      this.navigateToRecord(accountId, "Account");
    }
  }

  handleContactClick(event) {
    event.stopPropagation();
    const contactId = event.currentTarget.dataset.contactId;
    if (contactId) {
      this.navigateToRecord(contactId, "Contact");
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
    // For FlexiPage tabs, use the tab title (not identifier)
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

  handleRecapClick(event) {
    event.stopPropagation();
    const eventId = event.target.dataset.eventId;
    const selectedEvent = this.events.find((e) => e.Id === eventId);

    if (selectedEvent) {
      this.selectedEventId = eventId;
      this.selectedEventSubject = selectedEvent.Subject;
      this.selectedEventAccountName = selectedEvent.relatedName || null;
      this.selectedEventAccountId = selectedEvent.relatedId || null;
      this.selectedEventContactName = selectedEvent.whoName || null;
      this.selectedEventContactId = selectedEvent.whoId || null;
      this.showRecapModal = true;
    }
  }

  handlePrepClick(event) {
    event.stopPropagation();
    const eventId = event.target.dataset.eventId;
    // Simply navigate to the Event record
    this.navigateToRecord(eventId, "Event");
  }

  handleViewRecap(event) {
    event.stopPropagation();
    const eventId = event.target.dataset.eventId;

    // Get the Meeting_Recap__c ID for this event
    getMeetingRecapId({ eventId: eventId })
      .then((recapId) => {
        if (recapId) {
          // Navigate to the Meeting_Recap__c record page
          this.navigateToRecord(recapId, "Meeting_Recap__c");
        } else {
          // Fallback: if no recap found, navigate to event
          this.navigateToRecord(eventId, "Event");
          this.showToast(
            "Info",
            "No meeting recap found for this event.",
            "info"
          );
        }
      })
      .catch((error) => {
        // On error, fallback to event navigation
        console.error("Error getting recap ID:", error);
        this.navigateToRecord(eventId, "Event");
        this.showToast(
          "Error",
          "Unable to load meeting recap. Navigating to event.",
          "warning"
        );
      });
  }

  handleViewPrep(event) {
    event.stopPropagation();
    const eventId = event.target.dataset.eventId;

    // Get the Meeting_Prep__c ID for this event
    getMeetingPrepId({ eventId: eventId })
      .then((prepId) => {
        if (prepId) {
          // Navigate to the Meeting_Prep__c record page
          this.navigateToRecord(prepId, "Meeting_Prep__c");
        } else {
          // Fallback: if no prep found, navigate to event
          this.navigateToRecord(eventId, "Event");
          this.showToast(
            "Info",
            "No meeting prep found for this event.",
            "info"
          );
        }
      })
      .catch((error) => {
        // On error, fallback to event navigation
        console.error("Error getting prep ID:", error);
        this.navigateToRecord(eventId, "Event");
        this.showToast(
          "Error",
          "Unable to load meeting prep. Navigating to event.",
          "warning"
        );
      });
  }

  handleModalClose() {
    this.showRecapModal = false;
    this.selectedEventId = null;
    this.selectedEventSubject = null;
    this.selectedEventAccountName = null;
    this.selectedEventAccountId = null;
    this.selectedEventContactName = null;
    this.selectedEventContactId = null;
  }

  handleRecapSave(event) {
    const { eventId, recapId } = event.detail;

    // Refresh the event in the list
    this.events = this.events.map((evt) => {
      if (evt.Id === eventId) {
        return {
          ...evt,
          Recap_Completed__c: true,
          showRecapButton: false
        };
      }
      return evt;
    });

    this.showRecapModal = false;
    this.selectedEventId = null;
    this.selectedEventSubject = null;

    // Show toast notification
    this.showToast("Success", "Meeting recap saved and summarized!", "success");

    // Navigate to the Meeting Recap record page
    if (recapId) {
      this.navigateToRecord(recapId, "Meeting_Recap__c");
    }
  }

  showToast(title, message, variant) {
    const toastEvent = new ShowToastEvent({
      title,
      message,
      variant
    });
    this.dispatchEvent(toastEvent);
  }

  async handleCreateMeeting() {
    try {
      // Show loading state
      this.isLoading = true;

      // Generate AI-powered subject and description
      // We don't have specific context here, so pass null for all optional parameters
      // The AI will generate appropriate content based on general best practices
      const eventContent = await generateEventContent({
        accountId: null,
        contactId: null,
        opportunityId: null,
        caseId: null
      });

      // Build default field values object
      const defaultFields = {
        Subject: eventContent.subject || "Follow-up Meeting"
      };

      // Add description if available
      if (eventContent.description) {
        defaultFields.Description = eventContent.description;
      }

      // Encode default field values
      const encodedFields = encodeDefaultFieldValues(defaultFields);

      // Create page reference with prefilled values
      const pageReference = {
        type: "standard__objectPage",
        attributes: {
          objectApiName: "Event",
          actionName: "new"
        },
        state: {
          defaultFieldValues: encodedFields
        }
      };

      // Try to open in console subtab if available
      if (this.workspaceApi) {
        try {
          await this.workspaceApi.openSubtab({
            pageReference: pageReference,
            focus: true
          });
          this.isLoading = false;
          return;
        } catch (error) {
          console.error("Error opening event in subtab:", error);
          // Fall through to NavigationMixin
        }
      }

      // Fallback: Use NavigationMixin
      this[NavigationMixin.Navigate](pageReference);
      this.isLoading = false;
    } catch (error) {
      this.isLoading = false;
      console.error("Error generating event content:", error);
      // Fallback: Navigate without prefilled values
      this[NavigationMixin.Navigate]({
        type: "standard__objectPage",
        attributes: {
          objectApiName: "Event",
          actionName: "new"
        }
      });
      this.showToast(
        "Info",
        "Event form opened. AI content generation unavailable.",
        "info"
      );
    }
  }

  handleViewCalendar() {
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Event",
        actionName: "list"
      }
    });
  }

  handlePreviousDay(event) {
    event.currentTarget.blur(); // Remove focus to prevent highlight
    const newDate = new Date(this.selectedDate);
    newDate.setDate(newDate.getDate() - 1);
    this.selectedDate = newDate;
    this.loadEvents();
  }

  handleNextDay(event) {
    event.currentTarget.blur(); // Remove focus to prevent highlight
    const newDate = new Date(this.selectedDate);
    newDate.setDate(newDate.getDate() + 1);
    this.selectedDate = newDate;
    this.loadEvents();
  }

  handleGoToToday() {
    this.selectedDate = this.getTodayInUserTimezone();
    this.loadEvents();
  }

  handleRefresh(event) {
    event.currentTarget.blur(); // Remove focus after click
    this.loadEvents();
    this.showToast("Success", "Meetings refreshed", "success");
  }
}
