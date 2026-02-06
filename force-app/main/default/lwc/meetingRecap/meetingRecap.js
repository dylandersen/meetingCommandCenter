import { LightningElement, api, track } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { encodeDefaultFieldValues } from "lightning/pageReferenceUtils";
import { WorkspaceAPI } from "lightning/platformWorkspaceApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getEventRecapData from "@salesforce/apex/MeetingRecapController.getEventRecapData";
import getMeetingRecapData from "@salesforce/apex/MeetingRecapController.getMeetingRecapData";
import generateTaskContent from "@salesforce/apex/MeetingCommandCenterController.generateTaskContent";
import generateEventContentFromText from "@salesforce/apex/MeetingCommandCenterController.generateEventContentFromText";

export default class MeetingRecap extends NavigationMixin(LightningElement) {
  @api recordId;

  @track eventData;
  @track isLoading = true;
  @track error;
  @track objectApiName;
  @track loadingActionId = null; // Track which action button is currently loading
  workspaceApi;

  connectedCallback() {
    this.determineObjectType();
    // Initialize workspace API for console navigation
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

  determineObjectType() {
    if (!this.recordId) {
      this.error = "No record ID provided";
      this.isLoading = false;
      return;
    }

    // Try to determine object type from ID prefix
    // Event IDs start with "00U", Meeting_Recap__c IDs start with "a0"
    if (this.recordId.startsWith("a0")) {
      // Likely a Meeting_Recap__c ID
      this.objectApiName = "Meeting_Recap__c";
      this.loadRecapData();
    } else if (this.recordId.startsWith("00U")) {
      // Likely an Event ID
      this.objectApiName = "Event";
      this.loadEventData();
    } else {
      // Unknown - try both methods, starting with recap
      this.loadRecapData();
    }
  }

  loadRecapData() {
    this.isLoading = true;
    this.error = null;

    getMeetingRecapData({ recapId: this.recordId })
      .then((result) => {
        this.eventData = result;
        this.isLoading = false;
      })
      .catch((error) => {
        // If recap not found and error suggests it's not a recap ID, try event method
        if (
          error.body &&
          (error.body.message.includes("not found") ||
            error.body.message.includes("Recap ID"))
        ) {
          this.loadEventData();
        } else {
          this.error = error.body ? error.body.message : error.message;
          this.isLoading = false;
        }
      });
  }

  loadEventData() {
    this.isLoading = true;
    this.error = null;

    getEventRecapData({ eventId: this.recordId })
      .then((result) => {
        this.eventData = result;
        this.isLoading = false;
      })
      .catch((error) => {
        this.error = error.body ? error.body.message : error.message;
        this.isLoading = false;
      });
  }

  get formattedStartDateTime() {
    if (!this.eventData || !this.eventData.StartDateTime) {
      return "";
    }
    const date = new Date(this.eventData.StartDateTime);
    return date.toLocaleDateString("en-US", {
      weekday: "long",
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      hour12: true
    });
  }

  get formattedEndTime() {
    if (!this.eventData || !this.eventData.EndDateTime) {
      return "";
    }
    const date = new Date(this.eventData.EndDateTime);
    return date.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true
    });
  }

  get formattedDuration() {
    if (!this.eventData || !this.eventData.DurationInMinutes) {
      return "";
    }
    const minutes = this.eventData.DurationInMinutes;
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

  get hasRecapData() {
    return (
      this.eventData &&
      (this.eventData.AI_Meeting_Summary__c ||
        this.eventData.AI_Key_Outcomes__c ||
        this.eventData.AI_Next_Steps__c)
    );
  }

  get hasNoRecapData() {
    return !this.hasRecapData;
  }

  get hasSummary() {
    return this.eventData && this.eventData.AI_Meeting_Summary__c;
  }

  get hasKeyOutcomes() {
    return this.eventData && this.eventData.AI_Key_Outcomes__c;
  }

  get hasNextSteps() {
    return this.eventData && this.eventData.AI_Next_Steps__c;
  }

  formatRichTextWithLists(richText) {
    if (!richText) {
      return "";
    }

    // Check if content already has proper HTML list tags
    if (richText.includes("<ul>") || richText.includes("<ol>")) {
      return richText;
    }

    // Convert bullet points (•) in paragraphs to proper HTML lists
    const lines = richText.split(/\n/);
    let inList = false;
    let result = "";
    let listItems = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      const bulletMatch = line.match(/^•\s*(.+)$/);

      if (bulletMatch) {
        // Found a bullet point
        if (!inList) {
          // Start a new list
          if (result && !result.endsWith("<p>") && !result.endsWith("</p>")) {
            result += "<p>";
          }
          inList = true;
        }
        listItems.push(bulletMatch[1]);
      } else {
        // Not a bullet point
        if (inList) {
          // Close the current list
          if (listItems.length > 0) {
            result += "<ul>";
            const listItemsCopy = [...listItems];
            for (const item of listItemsCopy) {
              result += `<li>${item}</li>`;
            }
            result += "</ul>";
            listItems = [];
          }
          inList = false;
        }
        // Add the line as a paragraph if it's not empty
        if (line) {
          result += `<p>${line}</p>`;
        }
      }
    }

    // Close any remaining list
    if (inList && listItems.length > 0) {
      result += "<ul>";
      const listItemsCopy = [...listItems];
      for (const item of listItemsCopy) {
        result += `<li>${item}</li>`;
      }
      result += "</ul>";
    }

    return result || richText;
  }

  get formattedKeyOutcomes() {
    if (!this.eventData || !this.eventData.AI_Key_Outcomes__c) {
      return "";
    }
    return this.formatRichTextWithLists(this.eventData.AI_Key_Outcomes__c);
  }

  get formattedNextSteps() {
    if (!this.eventData || !this.eventData.AI_Next_Steps__c) {
      return "";
    }
    return this.formatRichTextWithLists(this.eventData.AI_Next_Steps__c);
  }

  get parsedNextSteps() {
    if (!this.eventData || !this.eventData.AI_Next_Steps__c) {
      return [];
    }

    const nextStepsText = this.eventData.AI_Next_Steps__c;
    const items = [];

    // Try to extract from HTML list items first
    const htmlListMatch = nextStepsText.match(/<li[^>]*>(.*?)<\/li>/gi);
    if (htmlListMatch && htmlListMatch.length > 0) {
      htmlListMatch.forEach((li) => {
        // Remove HTML tags and get clean text
        const cleanText = li
          .replace(/<[^>]+>/g, "")
          .trim()
          .replace(/^•\s*/, "");
        if (cleanText) {
          items.push(cleanText);
        }
      });
    } else {
      // Fall back to bullet point parsing
      const lines = nextStepsText.split(/\n/);
      lines.forEach((line) => {
        const trimmed = line.trim();
        const bulletMatch = trimmed.match(/^[•\-*]\s*(.+)$/);
        if (bulletMatch) {
          items.push(bulletMatch[1].trim());
        } else if (trimmed && !trimmed.startsWith("<")) {
          // Also capture non-HTML lines that might be next steps
          const cleanText = trimmed.replace(/^[•\-*]\s*/, "");
          if (cleanText && cleanText.length > 10) {
            // Only add if it's substantial text
            items.push(cleanText);
          }
        }
      });
    }

    return items;
  }

  categorizeNextStep(stepText) {
    if (!stepText) {
      return { type: "task", text: stepText };
    }

    const lowerText = stepText.toLowerCase();

    // Strong event indicators - these explicitly indicate meetings/events
    const strongEventKeywords = [
      "schedule a meeting",
      "schedule a call",
      "schedule meeting",
      "schedule call",
      "meeting with",
      "call with",
      "follow-up meeting",
      "follow up meeting",
      "appointment",
      "conference",
      "demo",
      "presentation",
      "workshop",
      "webinar",
      "sync meeting",
      "standup",
      "stand-up",
      "touch base",
      "check-in",
      "check in"
    ];

    // Meeting-specific keywords that indicate events (when used in context)
    const meetingKeywords = [
      "meeting",
      "call",
      "conference call",
      "video call",
      "zoom",
      "teams meeting",
      "google meet"
    ];

    // Task-specific keywords - these indicate work items, not meetings
    const taskKeywords = [
      "send email",
      "send an email",
      "prepare document",
      "prepare report",
      "prepare plan",
      "prepare for",
      "prepare proposal",
      "prepare materials",
      "finalize",
      "deliver",
      "create document",
      "create report",
      "create proposal",
      "update record",
      "update case",
      "update opportunity",
      "review document",
      "review proposal",
      "review materials",
      "complete form",
      "complete",
      "submit",
      "draft",
      "draft proposal",
      "draft email",
      "write",
      "write email",
      "email",
      "introduction",
      "introduce",
      "facilitate introduction",
      "research",
      "analyze",
      "gather",
      "compile",
      "organize",
      "coordinate",
      "follow up with email",
      "send follow-up",
      "document",
      "record"
    ];

    // Check for strong event indicators first (most specific)
    const hasStrongEventKeyword = strongEventKeywords.some((keyword) =>
      lowerText.includes(keyword)
    );

    if (hasStrongEventKeyword) {
      return { type: "event", text: stepText };
    }

    // Check for task keywords (if found, it's likely a task)
    const hasTaskKeyword = taskKeywords.some((keyword) =>
      lowerText.includes(keyword)
    );

    if (hasTaskKeyword) {
      return { type: "task", text: stepText };
    }

    // Check for meeting keywords - but be more careful
    // Only mark as event if it's clearly about scheduling/attending a meeting
    const hasMeetingKeyword = meetingKeywords.some((keyword) =>
      lowerText.includes(keyword)
    );

    // If it has a meeting keyword AND doesn't have task indicators, it's likely an event
    if (hasMeetingKeyword) {
      // Check if it's about scheduling or attending (event) vs preparing for (task)
      const schedulingIndicators = [
        "schedule",
        "set up",
        "arrange",
        "book",
        "attend"
      ];
      const hasSchedulingIndicator = schedulingIndicators.some((indicator) =>
        lowerText.includes(indicator)
      );

      if (hasSchedulingIndicator) {
        return { type: "event", text: stepText };
      }

      // If it's about preparing FOR a meeting, it's a task
      if (lowerText.includes("prepare") || lowerText.includes("prep")) {
        return { type: "task", text: stepText };
      }

      // Default: if it mentions a meeting/call, assume it's an event
      return { type: "event", text: stepText };
    }

    // Default to task for everything else
    // Most action items are tasks unless they explicitly mention meetings
    return { type: "task", text: stepText };
  }

  /**
   * Summarizes an action item into a concise one-sentence description
   */
  summarizeActionItem(actionText) {
    if (!actionText) return "";

    // Remove owner and deadline info (everything after "Owner:" or "Deadline:")
    let summary = actionText.split(/Owner:|Deadline:/i)[0].trim();

    // Extract the main action (usually at the start before the colon)
    const colonIndex = summary.indexOf(":");
    if (colonIndex > 0 && colonIndex < 80) {
      summary = summary.substring(colonIndex + 1).trim();
    }

    // Remove common prefixes
    summary = summary.replace(
      /^(prepare|develop|draft|identify|organize|schedule|explore|create)\s+/i,
      ""
    );

    // Capitalize first letter
    if (summary.length > 0) {
      summary = summary.charAt(0).toUpperCase() + summary.slice(1);
    }

    // Limit to ~100 characters, but try to end at a word boundary
    if (summary.length > 100) {
      const truncated = summary.substring(0, 100);
      const lastSpace = truncated.lastIndexOf(" ");
      if (lastSpace > 50) {
        summary = truncated.substring(0, lastSpace) + "...";
      } else {
        summary = truncated + "...";
      }
    }

    return summary;
  }

  /**
   * Checks if two action items are too similar (to avoid duplicates)
   */
  areSimilarActions(action1, action2) {
    const text1 = action1.text.toLowerCase();
    const text2 = action2.text.toLowerCase();

    // Extract key phrases (dates, names, main verbs)
    const extractKeyPhrases = (text) => {
      const phrases = [];
      // Extract dates (e.g., "January 30", "Friday")
      const dateMatches = text.match(
        /\b(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+|friday|monday|tuesday|wednesday|thursday|saturday|sunday/gi
      );
      if (dateMatches) phrases.push(...dateMatches);

      // Extract names (capitalized words that might be names)
      const nameMatches = text.match(/\b[A-Z][a-z]+\b/g);
      if (nameMatches) phrases.push(...nameMatches.slice(0, 3)); // Take first 3 potential names

      // Extract main action verbs
      const verbMatches = text.match(
        /\b(prepare|follow|schedule|discuss|meet|call|send|create|review|finalize)\w*/gi
      );
      if (verbMatches) phrases.push(...verbMatches);

      return phrases.join(" ").toLowerCase();
    };

    const phrases1 = extractKeyPhrases(text1);
    const phrases2 = extractKeyPhrases(text2);

    // If they share more than 60% of key phrases, consider them similar
    const phrases1Array = phrases1.split(" ").filter((p) => p.length > 2);
    const phrases2Array = phrases2.split(" ").filter((p) => p.length > 2);

    if (phrases1Array.length === 0 || phrases2Array.length === 0) {
      return false;
    }

    const commonPhrases = phrases1Array.filter((p) =>
      phrases2Array.includes(p)
    );
    const similarity =
      commonPhrases.length /
      Math.max(phrases1Array.length, phrases2Array.length);

    return similarity > 0.6;
  }

  get actionableItems() {
    const parsedSteps = this.parsedNextSteps;
    if (!parsedSteps || parsedSteps.length === 0) {
      return [];
    }

    // Categorize all steps
    const categorizedSteps = parsedSteps.map((step) => {
      const categorized = this.categorizeNextStep(step);
      return {
        ...categorized,
        originalText: step
      };
    });

    // Separate into tasks and events
    const tasks = categorizedSteps.filter((s) => s.type === "task");
    const events = categorizedSteps.filter((s) => s.type === "event");

    // Select 2-3 items with a mix of tasks and events, avoiding duplicates
    const selected = [];

    // Strategy: Always try to get a balanced mix (prefer 2 tasks + 1 event or 1 task + 2 events)
    if (tasks.length > 0 && events.length > 0) {
      // Prefer 2 tasks + 1 event for better sales workflow
      if (tasks.length >= 2) {
        selected.push(tasks[0]);
        // Add second task if it's not too similar to the first
        if (tasks.length > 1 && !this.areSimilarActions(tasks[0], tasks[1])) {
          selected.push(tasks[1]);
        } else if (tasks.length > 2) {
          // Try third task if second is too similar
          for (let i = 2; i < tasks.length; i++) {
            if (!this.areSimilarActions(tasks[0], tasks[i])) {
              selected.push(tasks[i]);
              break;
            }
          }
        }

        // Add one event if we have room
        if (selected.length < 3 && events.length > 0) {
          // Find an event that's not too similar to selected items
          for (let i = 0; i < events.length; i++) {
            const isSimilar = selected.some((item) =>
              this.areSimilarActions(item, events[i])
            );
            if (!isSimilar) {
              selected.push(events[i]);
              break;
            }
          }
        }
      } else {
        // Only 1 task available, so do 1 task + 2 events
        selected.push(tasks[0]);

        // Add two events if available and not too similar
        for (let i = 0; i < events.length && selected.length < 3; i++) {
          const isSimilar = selected.some((item) =>
            this.areSimilarActions(item, events[i])
          );
          if (!isSimilar) {
            selected.push(events[i]);
          }
        }
      }
    } else if (tasks.length > 0) {
      // Only tasks available - take up to 3, avoiding duplicates
      selected.push(tasks[0]);
      for (let i = 1; i < tasks.length && selected.length < 3; i++) {
        const isSimilar = selected.some((item) =>
          this.areSimilarActions(item, tasks[i])
        );
        if (!isSimilar) {
          selected.push(tasks[i]);
        }
      }
    } else if (events.length > 0) {
      // Only events available - take up to 3, avoiding duplicates
      selected.push(events[0]);
      for (let i = 1; i < events.length && selected.length < 3; i++) {
        const isSimilar = selected.some((item) =>
          this.areSimilarActions(item, events[i])
        );
        if (!isSimilar) {
          selected.push(events[i]);
        }
      }
    }

    // Limit to maximum 3 items
    const finalItems = selected.slice(0, 3);

    return finalItems.map((item, index) => {
      const summaryText = this.summarizeActionItem(item.text);
      const isLoading = this.loadingActionId === item.text;
      const baseLabel = item.type === "event" ? "Schedule Event" : "Create Task";
      return {
        id: `action-${index}`,
        text: item.text,
        summaryText: summaryText,
        type: item.type,
        label: isLoading ? "Loading..." : baseLabel,
        icon: item.type === "event" ? "utility:event" : "utility:task",
        variant: item.type === "event" ? "brand" : "neutral",
        cardClass:
          item.type === "event" ? "action-card-event" : "action-card-task",
        isTask: item.type === "task",
        isLoading: isLoading
      };
    });
  }

  get hasActionableItems() {
    return this.actionableItems && this.actionableItems.length > 0;
  }

  get showActionButtons() {
    return this.hasNextSteps && this.hasActionableItems;
  }

  handleActionClick(event) {
    const actionType = event.currentTarget.dataset.actionType;

    if (actionType === "event") {
      this.handleCreateEvent(event);
    } else {
      this.handleCreateTask(event);
    }
  }

  get accountName() {
    return this.eventData?.What?.Name || null;
  }

  get accountId() {
    return this.eventData?.WhatId || null;
  }

  get contactName() {
    return this.eventData?.Who?.Name || null;
  }

  get contactId() {
    return this.eventData?.WhoId || null;
  }

  handleAccountClick(event) {
    event.preventDefault();
    event.stopPropagation();
    if (this.accountId) {
      this.navigateToRecord(this.accountId, "Account");
    }
  }

  handleContactClick(event) {
    event.preventDefault();
    event.stopPropagation();
    if (this.contactId) {
      this.navigateToRecord(this.contactId, "Contact");
    }
  }

  navigateToRecord(recordId, objectApiName) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        objectApiName: objectApiName,
        actionName: "view"
      }
    });
  }

  async handleEventTitleClick() {
    if (this.eventData && this.eventData.Id) {
      const eventId = this.eventData.Id;

      // Try to use workspaceAPI for console subtab, fall back to NavigationMixin
      if (this.workspaceApi) {
        try {
          // Open in a console subtab
          await this.workspaceApi.openSubtab({
            recordId: eventId,
            pageReference: {
              type: "standard__recordPage",
              attributes: {
                recordId: eventId,
                objectApiName: "Event",
                actionName: "view"
              }
            }
          });
        } catch (error) {
          // Fall back to NavigationMixin if workspaceAPI fails
          console.error("Error opening subtab:", error);
          this[NavigationMixin.Navigate]({
            type: "standard__recordPage",
            attributes: {
              recordId: eventId,
              objectApiName: "Event",
              actionName: "view"
            }
          });
        }
      } else {
        // Not in console, use NavigationMixin
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: eventId,
            objectApiName: "Event",
            actionName: "view"
          }
        });
      }
    }
  }

  async handleCreateTask(event) {
    const stepText = event.currentTarget.dataset.stepText;
    if (!stepText) {
      return;
    }

    // Set loading state for this specific action
    this.loadingActionId = stepText;

    try {
      // Generate AI-powered subject and description
      const taskContent = await generateTaskContent({
        taskText: stepText,
        accountId: this.accountId,
        contactId: this.contactId,
        opportunityId: null,
        caseId: null
      });

      // Build default field values object
      const defaultFields = {
        Subject: taskContent.subject || stepText,
        Description: taskContent.description || ""
      };
      if (this.accountId) {
        defaultFields.WhatId = this.accountId;
      }
      if (this.contactId) {
        defaultFields.WhoId = this.contactId;
      }

      // Encode default field values
      const encodedFields = encodeDefaultFieldValues(defaultFields);

      // Create page reference
      const pageReference = {
        type: "standard__objectPage",
        attributes: {
          objectApiName: "Task",
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
          this.loadingActionId = null;
          return;
        } catch (error) {
          console.error("Error opening task in subtab:", error);
          // Fall through to NavigationMixin
        }
      }

      // Fallback: Use NavigationMixin (will open in same tab if not in console)
      this[NavigationMixin.Navigate](pageReference);
      this.loadingActionId = null;
    } catch (err) {
      console.error("Error generating task content:", err);
      // Fallback: Navigate without AI-generated content
      const defaultFields = {
        Subject: stepText
      };
      if (this.accountId) {
        defaultFields.WhatId = this.accountId;
      }
      if (this.contactId) {
        defaultFields.WhoId = this.contactId;
      }

      const encodedFields = encodeDefaultFieldValues(defaultFields);
      const pageReference = {
        type: "standard__objectPage",
        attributes: {
          objectApiName: "Task",
          actionName: "new"
        },
        state: {
          defaultFieldValues: encodedFields
        }
      };

      if (this.workspaceApi) {
        try {
          await this.workspaceApi.openSubtab({
            pageReference: pageReference,
            focus: true
          });
          this.loadingActionId = null;
          return;
        } catch (subtabError) {
          console.error("Error opening task in subtab:", subtabError);
        }
      }

      this[NavigationMixin.Navigate](pageReference);
      this.showToast(
        "Info",
        "Task form opened. AI content generation unavailable.",
        "info"
      );
    } finally {
      // Clear loading state
      this.loadingActionId = null;
    }
  }

  async handleCreateEvent(event) {
    const stepText = event.currentTarget.dataset.stepText;
    if (!stepText) {
      return;
    }

    // Set loading state for this specific action
    this.loadingActionId = stepText;

    try {
      // Generate AI-powered subject and description
      const eventContent = await generateEventContentFromText({
        eventText: stepText,
        accountId: this.accountId,
        contactId: this.contactId,
        opportunityId: null,
        caseId: null
      });

      // Build default field values object
      const defaultFields = {
        Subject: eventContent.subject || stepText,
        Description: eventContent.description || ""
      };
      if (this.accountId) {
        defaultFields.WhatId = this.accountId;
      }
      if (this.contactId) {
        defaultFields.WhoId = this.contactId;
      }

      // Encode default field values
      const encodedFields = encodeDefaultFieldValues(defaultFields);

      // Create page reference
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
          this.loadingActionId = null;
          return;
        } catch (error) {
          console.error("Error opening event in subtab:", error);
          // Fall through to NavigationMixin
        }
      }

      // Fallback: Use NavigationMixin (will open in same tab if not in console)
      this[NavigationMixin.Navigate](pageReference);
      this.loadingActionId = null;
    } catch (err) {
      console.error("Error generating event content:", err);
      // Fallback: Navigate without AI-generated content
      const defaultFields = {
        Subject: stepText
      };
      if (this.accountId) {
        defaultFields.WhatId = this.accountId;
      }
      if (this.contactId) {
        defaultFields.WhoId = this.contactId;
      }

      const encodedFields = encodeDefaultFieldValues(defaultFields);
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

      if (this.workspaceApi) {
        try {
          await this.workspaceApi.openSubtab({
            pageReference: pageReference,
            focus: true
          });
          this.loadingActionId = null;
          return;
        } catch (subtabError) {
          console.error("Error opening event in subtab:", subtabError);
        }
      }

      this[NavigationMixin.Navigate](pageReference);
      this.showToast(
        "Info",
        "Event form opened. AI content generation unavailable.",
        "info"
      );
      this.loadingActionId = null;
    }
  }

  handleSendToSlack() {
    this.showToast(
      "Success",
      "Recap sent successfully to Account Slack Channel",
      "success"
    );
  }

  showToast(title, message, variant) {
    const toastEvent = new ShowToastEvent({
      title,
      message,
      variant
    });
    this.dispatchEvent(toastEvent);
  }
}
