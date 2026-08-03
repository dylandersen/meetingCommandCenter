import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { updateRecord } from "lightning/uiRecordApi";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import TIME_ZONE from "@salesforce/i18n/timeZone";
import EVENT_ID_FIELD from "@salesforce/schema/Event.Id";
import EVENT_LOCATION_FIELD from "@salesforce/schema/Event.Location";
import getTodaysEvents from "@salesforce/apex/MeetingCommandCenterController.getTodaysEvents";
import getContactAccountMap from "@salesforce/apex/MeetingCommandCenterController.getContactAccountMap";
import getMeetingRecapId from "@salesforce/apex/MeetingCommandCenterController.getMeetingRecapId";
import getMeetingPrepId from "@salesforce/apex/MeetingCommandCenterController.getMeetingPrepId";
import generateEventContent from "@salesforce/apex/MeetingCommandCenterController.generateEventContent";

const ONE_DAY_IN_MS = 24 * 60 * 60 * 1000;

export default class MeetingCommandCenterMobile extends NavigationMixin(
  LightningElement
) {
  events = [];
  selectedDate = new Date();
  isLoading = true;
  isCreatingMeeting = false;
  error = null;
  resultAnnouncement = "";

  showRecapModal = false;
  selectedEventId = null;
  selectedEventSubject = null;
  selectedEventAccountName = null;
  selectedEventAccountId = null;
  selectedEventContactName = null;
  selectedEventContactId = null;

  showLocationModal = false;
  selectedLocationEventId = null;
  selectedLocationEventSubject = null;
  locationDraft = "";
  isSavingLocation = false;
  shouldFocusLocationInput = false;
  shouldRestoreLocationFocus = false;

  connectedCallback() {
    this.selectedDate = this.getTodayInUserTimezone();
    this.loadEvents();
  }

  renderedCallback() {
    if (this.shouldFocusLocationInput) {
      this.shouldFocusLocationInput = false;
      this.template.querySelector("[data-location-input]")?.focus();
    }

    if (this.shouldRestoreLocationFocus && this.selectedLocationEventId) {
      this.shouldRestoreLocationFocus = false;
      const trigger = this.template.querySelector(
        `[data-location-trigger][data-event-id="${this.selectedLocationEventId}"]`
      );
      trigger?.focus();
      this.clearLocationSelection();
    }
  }

  async loadEvents() {
    this.isLoading = true;
    this.error = null;
    this.resultAnnouncement = "Loading meetings.";

    try {
      const rawEvents = await getTodaysEvents({
        selectedDate: this.selectedDateValue
      });
      this.events = this.processEvents(rawEvents || []);
      await this.addContactAccounts();

      const count = this.events.length;
      this.resultAnnouncement = `${count} ${
        count === 1 ? "meeting" : "meetings"
      } loaded for ${this.formattedDate}.`;
    } catch (error) {
      this.error = this.getErrorMessage(error);
      this.resultAnnouncement = `Meetings could not be loaded. ${this.error}`;
    } finally {
      this.isLoading = false;
    }
  }

  processEvents(rawEvents) {
    const now = new Date();

    return rawEvents.map((event) => {
      const startDateTime = new Date(event.StartDateTime);
      const endDateTime = new Date(event.EndDateTime);
      const isPast = endDateTime < now;
      const isNow = startDateTime <= now && endDateTime >= now;
      const isUpcoming = !isPast && !isNow;
      const relatedName = event.What?.Name || null;
      const whoName = event.Who?.Name || null;

      let statusLabel = "Upcoming";
      let statusClass = "status-pill status-pill--upcoming";

      if (isNow) {
        statusLabel = "In progress";
        statusClass = "status-pill status-pill--live";
      } else if (isPast) {
        statusLabel = "Ended";
        statusClass = "status-pill status-pill--ended";
      }

      return {
        ...event,
        formattedStartTime: this.formatTime(startDateTime),
        formattedEndTime: this.formatTime(endDateTime),
        durationText: this.formatDuration(event.DurationInMinutes),
        relatedName,
        relatedId: event.WhatId,
        whoName,
        whoId: event.WhoId,
        accountName: relatedName,
        accountId: event.WhatId,
        isPast,
        isNow,
        isUpcoming,
        canCreateRecap: isPast && !event.Recap_Completed__c,
        canViewRecap: Boolean(event.Recap_Completed__c),
        canPrep: isUpcoming,
        showLiveActions: isNow && !event.Recap_Completed__c,
        statusLabel,
        statusClass,
        locationLabel: event.Location || "Add location",
        locationActionLabel: event.Location
          ? `Edit location for ${event.Subject}`
          : `Add location for ${event.Subject}`,
        eventActionLabel: `Open ${event.Subject}`,
        contactActionLabel: whoName ? `Open contact ${whoName}` : "",
        accountActionLabel: relatedName ? `Open account ${relatedName}` : ""
      };
    });
  }

  async addContactAccounts() {
    const contactIds = [
      ...new Set(
        this.events
          .filter((event) => event.whoId && !event.relatedId)
          .map((event) => event.whoId)
      )
    ];

    if (contactIds.length === 0) {
      return;
    }

    try {
      const accountMap = await getContactAccountMap({ contactIds });
      this.events = this.events.map((event) => {
        const account = accountMap?.[event.whoId];
        if (!account || event.relatedId) {
          return event;
        }

        return {
          ...event,
          accountId: account.accountId,
          accountName: account.accountName,
          contactAccountId: account.accountId,
          contactAccountName: account.accountName,
          accountActionLabel: `Open account ${account.accountName}`
        };
      });
    } catch (error) {
      // Contact-to-account context is supplemental; keep the meetings usable.
      // eslint-disable-next-line no-console
      console.error("Unable to load contact accounts", error);
    }
  }

  get selectedDateValue() {
    return this.formatDateForApex(this.selectedDate);
  }

  get formattedDate() {
    return this.selectedDate.toLocaleDateString("en-US", {
      weekday: "long",
      month: "long",
      day: "numeric",
      timeZone: TIME_ZONE
    });
  }

  get dateContextLabel() {
    const selected = this.dateAtLocalMidnight(this.selectedDateValue);
    const today = this.dateAtLocalMidnight(
      this.formatDateForApex(this.getTodayInUserTimezone())
    );
    const difference = Math.round((selected - today) / ONE_DAY_IN_MS);

    if (difference === 0) return "Today";
    if (difference === 1) return "Tomorrow";
    if (difference === -1) return "Yesterday";
    return "Selected day";
  }

  get isToday() {
    return (
      this.selectedDateValue ===
      this.formatDateForApex(this.getTodayInUserTimezone())
    );
  }

  get hasEvents() {
    return !this.isLoading && !this.error && this.events.length > 0;
  }

  get showEmptyState() {
    return !this.isLoading && !this.error && this.events.length === 0;
  }

  get meetingCountLabel() {
    const count = this.events.length;
    return `${count} ${count === 1 ? "meeting" : "meetings"}`;
  }

  get totalMeetingTimeLabel() {
    const totalMinutes = this.events.reduce(
      (total, event) => total + (event.DurationInMinutes || 0),
      0
    );
    return this.formatDuration(totalMinutes);
  }

  get emptyStateTitle() {
    return this.isToday ? "Your day is open" : "No meetings this day";
  }

  get emptyStateMessage() {
    return this.isToday
      ? "Use the time to prepare, follow up, or schedule your next conversation."
      : "Choose another date or create a meeting from here.";
  }

  get createMeetingLabel() {
    return this.isCreatingMeeting ? "Preparing meeting…" : "Create meeting";
  }

  get selectedLocationTitle() {
    return this.selectedLocationEventSubject
      ? `Meeting location: ${this.selectedLocationEventSubject}`
      : "Meeting location";
  }

  get locationSaveDisabled() {
    return this.isSavingLocation || !this.locationDraft.trim();
  }

  formatDateForApex(date) {
    return date.toLocaleDateString("en-CA", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      timeZone: TIME_ZONE
    });
  }

  getTodayInUserTimezone() {
    return this.dateAtLocalMidnight(
      new Date().toLocaleDateString("en-CA", { timeZone: TIME_ZONE })
    );
  }

  dateAtLocalMidnight(dateString) {
    const [year, month, day] = dateString.split("-").map(Number);
    return new Date(year, month - 1, day);
  }

  formatTime(date) {
    return date.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
      timeZone: TIME_ZONE
    });
  }

  formatDuration(minutes = 0) {
    if (minutes < 60) return `${minutes} min`;

    const hours = Math.floor(minutes / 60);
    const remainingMinutes = minutes % 60;
    return remainingMinutes ? `${hours} hr ${remainingMinutes} min` : `${hours} hr`;
  }

  getErrorMessage(error) {
    return error?.body?.message || error?.message || "An unexpected error occurred.";
  }

  handleDateChange(event) {
    if (!event.target.value) return;
    this.selectedDate = this.dateAtLocalMidnight(event.target.value);
    this.loadEvents();
  }

  handlePreviousDay() {
    this.shiftSelectedDate(-1);
  }

  handleNextDay() {
    this.shiftSelectedDate(1);
  }

  handleGoToToday() {
    if (this.isToday) return;
    this.selectedDate = this.getTodayInUserTimezone();
    this.loadEvents();
  }

  handleRefresh() {
    this.loadEvents();
  }

  shiftSelectedDate(days) {
    const nextDate = new Date(this.selectedDate);
    nextDate.setDate(nextDate.getDate() + days);
    this.selectedDate = nextDate;
    this.loadEvents();
  }

  handleEventClick(event) {
    this.navigateToRecord(event.currentTarget.dataset.eventId, "Event");
  }

  handleContactClick(event) {
    this.navigateToRecord(event.currentTarget.dataset.contactId, "Contact");
  }

  handleAccountClick(event) {
    this.navigateToRecord(event.currentTarget.dataset.accountId, "Account");
  }

  handlePrepClick(event) {
    this.navigateToRecord(event.currentTarget.dataset.eventId, "Event");
  }

  async handleViewPrep(event) {
    const eventId = event.currentTarget.dataset.eventId;

    try {
      const prepId = await getMeetingPrepId({ eventId });
      if (prepId) {
        this.navigateToRecord(prepId, "Meeting_Prep__c");
        return;
      }
      this.navigateToRecord(eventId, "Event");
      this.showToast("Prep not found", "Opening the meeting instead.", "info");
    } catch (error) {
      this.navigateToRecord(eventId, "Event");
      this.showToast("Unable to open prep", this.getErrorMessage(error), "warning");
    }
  }

  handleRecapClick(event) {
    const eventId = event.currentTarget.dataset.eventId;
    const selectedEvent = this.events.find((item) => item.Id === eventId);
    if (!selectedEvent) return;

    this.selectedEventId = eventId;
    this.selectedEventSubject = selectedEvent.Subject;
    this.selectedEventAccountName = selectedEvent.accountName || null;
    this.selectedEventAccountId = selectedEvent.accountId || null;
    this.selectedEventContactName = selectedEvent.whoName || null;
    this.selectedEventContactId = selectedEvent.whoId || null;
    this.showRecapModal = true;
  }

  async handleViewRecap(event) {
    const eventId = event.currentTarget.dataset.eventId;

    try {
      const recapId = await getMeetingRecapId({ eventId });
      if (recapId) {
        this.navigateToRecord(recapId, "Meeting_Recap__c");
        return;
      }
      this.navigateToRecord(eventId, "Event");
      this.showToast("Recap not found", "Opening the meeting instead.", "info");
    } catch (error) {
      this.navigateToRecord(eventId, "Event");
      this.showToast("Unable to open recap", this.getErrorMessage(error), "warning");
    }
  }

  handleModalClose() {
    this.resetRecapSelection();
  }

  handleRecapSave(event) {
    const { eventId, recapId } = event.detail;
    this.events = this.events.map((item) =>
      item.Id === eventId
        ? {
            ...item,
            Recap_Completed__c: true,
            canCreateRecap: false,
            canViewRecap: true,
            showLiveActions: false
          }
        : item
    );
    this.resetRecapSelection();
    this.showToast("Recap saved", "Your meeting recap is ready.", "success");

    if (recapId) {
      this.navigateToRecord(recapId, "Meeting_Recap__c");
    }
  }

  resetRecapSelection() {
    this.showRecapModal = false;
    this.selectedEventId = null;
    this.selectedEventSubject = null;
    this.selectedEventAccountName = null;
    this.selectedEventAccountId = null;
    this.selectedEventContactName = null;
    this.selectedEventContactId = null;
  }

  handleOpenLocationModal(event) {
    const eventId = event.currentTarget.dataset.eventId;
    const selectedEvent = this.events.find((item) => item.Id === eventId);
    if (!selectedEvent) return;

    this.selectedLocationEventId = eventId;
    this.selectedLocationEventSubject = selectedEvent.Subject;
    this.locationDraft = selectedEvent.Location || "";
    this.showLocationModal = true;
    this.shouldFocusLocationInput = true;
  }

  handleLocationChange(event) {
    this.locationDraft = event.target.value;
  }

  handleLocationModalKeyDown(event) {
    if (event.key === "Escape") {
      this.handleCloseLocationModal();
      return;
    }

    if (event.key !== "Tab") {
      return;
    }

    const focusableElements = Array.from(
      this.template.querySelectorAll(
        ".mobile-modal button:not([disabled]), .mobile-modal lightning-input:not([disabled])"
      )
    );
    const firstElement = focusableElements[0];
    const lastElement = focusableElements[focusableElements.length - 1];
    const activeElement = this.template.activeElement;

    if (event.shiftKey && activeElement === firstElement) {
      event.preventDefault();
      lastElement?.focus();
    } else if (!event.shiftKey && activeElement === lastElement) {
      event.preventDefault();
      firstElement?.focus();
    }
  }

  handleCloseLocationModal() {
    if (this.isSavingLocation) return;
    this.showLocationModal = false;
    this.shouldRestoreLocationFocus = true;
  }

  async handleSaveLocation() {
    const location = this.locationDraft.trim();
    if (!location) return;

    this.isSavingLocation = true;
    try {
      const fields = {
        [EVENT_ID_FIELD.fieldApiName]: this.selectedLocationEventId,
        [EVENT_LOCATION_FIELD.fieldApiName]: location
      };
      await updateRecord({ fields });
      this.events = this.events.map((item) =>
        item.Id === this.selectedLocationEventId
          ? {
              ...item,
              Location: location,
              locationLabel: location,
              locationActionLabel: `Edit location for ${item.Subject}`
            }
          : item
      );
      this.showToast("Location saved", "The meeting location was updated.", "success");
      this.showLocationModal = false;
      this.shouldRestoreLocationFocus = true;
    } catch (error) {
      this.showToast("Unable to save location", this.getErrorMessage(error), "error");
    } finally {
      this.isSavingLocation = false;
    }
  }

  clearLocationSelection() {
    this.selectedLocationEventId = null;
    this.selectedLocationEventSubject = null;
    this.locationDraft = "";
  }

  async handleCreateMeeting() {
    this.isCreatingMeeting = true;

    try {
      const eventContent = await generateEventContent({
        accountId: null,
        contactId: null,
        opportunityId: null,
        caseId: null
      });
      const defaultFields = {
        Subject: eventContent?.subject || "Follow-up Meeting"
      };
      if (eventContent?.description) {
        defaultFields.Description = eventContent.description;
      }

      this.navigateToNewEvent(encodeDefaultFieldValues(defaultFields));
    } catch (error) {
      this.navigateToNewEvent();
      this.showToast(
        "Meeting form opened",
        "AI suggestions are temporarily unavailable.",
        "info"
      );
    } finally {
      this.isCreatingMeeting = false;
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

  navigateToNewEvent(defaultFieldValues) {
    const pageReference = {
      type: "standard__objectPage",
      attributes: {
        objectApiName: "Event",
        actionName: "new"
      }
    };
    if (defaultFieldValues) {
      pageReference.state = { defaultFieldValues };
    }
    this[NavigationMixin.Navigate](pageReference);
  }

  navigateToRecord(recordId, objectApiName) {
    if (!recordId) return;

    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName,
        actionName: "view"
      }
    });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
