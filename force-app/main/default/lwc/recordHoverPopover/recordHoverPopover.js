import { LightningElement, api, track, wire } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import getEventRecord from "@salesforce/apex/MeetingCommandCenterController.getEventRecord";

// Common fields for Account
const ACCOUNT_FIELDS = [
  "Account.Name",
  "Account.Phone",
  "Account.Website",
  "Account.Industry",
  "Account.Type",
  "Account.BillingCity",
  "Account.BillingState"
];

// Common fields for Contact
const CONTACT_FIELDS = [
  "Contact.Name",
  "Contact.Email",
  "Contact.Phone",
  "Contact.Title",
  "Contact.Department",
  "Contact.MailingCity",
  "Contact.MailingState"
];

// Common fields for Event
const EVENT_FIELDS = [
  "Event.Subject",
  "Event.StartDateTime",
  "Event.EndDateTime",
  "Event.Location",
  "Event.Description",
  "Event.Type",
  "Event.IsAllDayEvent"
];

export default class RecordHoverPopover extends LightningElement {
  @api recordId;
  @api objectApiName;
  @api delay = 300; // Delay before showing popover (ms)

  @track showPopover = false;
  @track popoverStyle = "";
  @track recordFields = [];

  hoverTimeout;
  mouseX = 0;
  mouseY = 0;

  get fields() {
    if (this.objectApiName === "Account") {
      return ACCOUNT_FIELDS;
    } else if (this.objectApiName === "Contact") {
      return CONTACT_FIELDS;
    } else if (this.objectApiName === "Event") {
      return EVENT_FIELDS;
    }
    return [];
  }

  @wire(getRecord, { recordId: "$recordId", fields: "$fields" })
  wiredRecord({ error, data }) {
    // Skip wire adapter for Event objects - use imperative Apex instead
    if (this.objectApiName === "Event") {
      return;
    }
    
    if (data) {
      this.processRecordData(data);
    } else if (error) {
      console.error("Error loading record:", error);
      this.recordFields = [];
    }
  }

  connectedCallback() {
    // Load Event data imperatively since Event is not supported by UI API
    if (this.objectApiName === "Event" && this.recordId) {
      this.loadEventData();
    }
  }

  loadEventData() {
    getEventRecord({ eventId: this.recordId })
      .then((data) => {
        if (data && Object.keys(data).length > 0) {
          this.processEventData(data);
        } else {
          this.recordFields = [];
        }
      })
      .catch((error) => {
        console.error("Error loading Event record:", error);
        this.recordFields = [];
      });
  }

  processEventData(data) {
    const fields = [];

    if (data.Subject) {
      fields.push({
        label: "Subject",
        value: data.Subject,
        apiName: "Subject",
        fieldType: "subject"
      });
    }

    if (data.StartDateTime) {
      const date = new Date(data.StartDateTime);
      const formattedDate = date.toLocaleString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
        hour12: true
      });
      fields.push({
        label: "Start",
        value: formattedDate,
        apiName: "StartDateTime",
        fieldType: "datetime"
      });
    }

    if (data.EndDateTime) {
      const date = new Date(data.EndDateTime);
      const formattedDate = date.toLocaleString("en-US", {
        month: "short",
        day: "numeric",
        year: "numeric",
        hour: "numeric",
        minute: "2-digit",
        hour12: true
      });
      fields.push({
        label: "End",
        value: formattedDate,
        apiName: "EndDateTime",
        fieldType: "datetime"
      });
    }

    if (data.Location) {
      fields.push({
        label: "Location",
        value: data.Location,
        apiName: "Location",
        fieldType: "location"
      });
    }

    if (data.Type) {
      fields.push({
        label: "Type",
        value: data.Type,
        apiName: "Type",
        fieldType: "type"
      });
    }

    if (data.Description) {
      const description = data.Description;
      const truncated = description.length > 100 
        ? description.substring(0, 100) + "..." 
        : description;
      fields.push({
        label: "Description",
        value: truncated,
        apiName: "Description",
        fieldType: "description"
      });
    }

    // Filter out empty values and limit to 5 fields
    this.recordFields = fields
      .filter((field) => field.value !== null && field.value !== undefined && field.value !== "")
      .slice(0, 5);
  }

  processRecordData(data) {
    if (!data || !data.fields) {
      this.recordFields = [];
      return;
    }

    const fields = [];
    const fieldMap = data.fields;

    // Process Account fields
    if (this.objectApiName === "Account") {
      if (fieldMap.Name) {
        fields.push({
          label: "Name",
          value: getFieldValue(data, ACCOUNT_FIELDS[0]),
          apiName: "Name",
          fieldType: "name"
        });
      }
      if (fieldMap.Phone) {
        fields.push({
          label: "Phone",
          value: getFieldValue(data, ACCOUNT_FIELDS[1]),
          apiName: "Phone",
          fieldType: "phone"
        });
      }
      if (fieldMap.Website) {
        fields.push({
          label: "Website",
          value: getFieldValue(data, ACCOUNT_FIELDS[2]),
          apiName: "Website",
          fieldType: "website"
        });
      }
      if (fieldMap.Industry) {
        fields.push({
          label: "Industry",
          value: getFieldValue(data, ACCOUNT_FIELDS[3]),
          apiName: "Industry",
          fieldType: "industry"
        });
      }
      if (fieldMap.Type) {
        fields.push({
          label: "Type",
          value: getFieldValue(data, ACCOUNT_FIELDS[4]),
          apiName: "Type",
          fieldType: "type"
        });
      }
      if (fieldMap.BillingCity || fieldMap.BillingState) {
        const city = getFieldValue(data, ACCOUNT_FIELDS[5]) || "";
        const state = getFieldValue(data, ACCOUNT_FIELDS[6]) || "";
        const location = [city, state].filter(Boolean).join(", ");
        if (location) {
          fields.push({
            label: "Location",
            value: location,
            apiName: "Location",
            fieldType: "location"
          });
        }
      }
    }
    // Process Contact fields
    else if (this.objectApiName === "Contact") {
      if (fieldMap.Name) {
        fields.push({
          label: "Name",
          value: getFieldValue(data, CONTACT_FIELDS[0]),
          apiName: "Name",
          fieldType: "name"
        });
      }
      if (fieldMap.Email) {
        fields.push({
          label: "Email",
          value: getFieldValue(data, CONTACT_FIELDS[1]),
          apiName: "Email",
          fieldType: "email"
        });
      }
      if (fieldMap.Phone) {
        fields.push({
          label: "Phone",
          value: getFieldValue(data, CONTACT_FIELDS[2]),
          apiName: "Phone",
          fieldType: "phone"
        });
      }
      if (fieldMap.Title) {
        fields.push({
          label: "Title",
          value: getFieldValue(data, CONTACT_FIELDS[3]),
          apiName: "Title",
          fieldType: "title"
        });
      }
      if (fieldMap.Department) {
        fields.push({
          label: "Department",
          value: getFieldValue(data, CONTACT_FIELDS[4]),
          apiName: "Department",
          fieldType: "department"
        });
      }
      if (fieldMap.MailingCity || fieldMap.MailingState) {
        const city = getFieldValue(data, CONTACT_FIELDS[5]) || "";
        const state = getFieldValue(data, CONTACT_FIELDS[6]) || "";
        const location = [city, state].filter(Boolean).join(", ");
        if (location) {
          fields.push({
            label: "Location",
            value: location,
            apiName: "Location",
            fieldType: "location"
          });
        }
      }
    }

    // Process Event fields
    else if (this.objectApiName === "Event") {
      if (fieldMap.Subject) {
        fields.push({
          label: "Subject",
          value: getFieldValue(data, EVENT_FIELDS[0]),
          apiName: "Subject",
          fieldType: "subject"
        });
      }
      if (fieldMap.StartDateTime) {
        const startDate = getFieldValue(data, EVENT_FIELDS[1]);
        if (startDate) {
          const date = new Date(startDate);
          const formattedDate = date.toLocaleString("en-US", {
            month: "short",
            day: "numeric",
            year: "numeric",
            hour: "numeric",
            minute: "2-digit",
            hour12: true
          });
          fields.push({
            label: "Start",
            value: formattedDate,
            apiName: "StartDateTime",
            fieldType: "datetime"
          });
        }
      }
      if (fieldMap.EndDateTime) {
        const endDate = getFieldValue(data, EVENT_FIELDS[2]);
        if (endDate) {
          const date = new Date(endDate);
          const formattedDate = date.toLocaleString("en-US", {
            month: "short",
            day: "numeric",
            year: "numeric",
            hour: "numeric",
            minute: "2-digit",
            hour12: true
          });
          fields.push({
            label: "End",
            value: formattedDate,
            apiName: "EndDateTime",
            fieldType: "datetime"
          });
        }
      }
      if (fieldMap.Location) {
        fields.push({
          label: "Location",
          value: getFieldValue(data, EVENT_FIELDS[3]),
          apiName: "Location",
          fieldType: "location"
        });
      }
      if (fieldMap.Type) {
        fields.push({
          label: "Type",
          value: getFieldValue(data, EVENT_FIELDS[5]),
          apiName: "Type",
          fieldType: "type"
        });
      }
      if (fieldMap.Description) {
        const description = getFieldValue(data, EVENT_FIELDS[4]);
        if (description) {
          // Truncate long descriptions
          const truncated = description.length > 100 
            ? description.substring(0, 100) + "..." 
            : description;
          fields.push({
            label: "Description",
            value: truncated,
            apiName: "Description",
            fieldType: "description"
          });
        }
      }
    }

    // Filter out empty values and limit to 5 fields
    this.recordFields = fields
      .filter((field) => field.value !== null && field.value !== undefined && field.value !== "")
      .slice(0, 5);
  }

  handleMouseEnter(event) {
    // Clear any existing timeout
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
    }

    // Store mouse position
    this.mouseX = event.clientX;
    this.mouseY = event.clientY;

    // Show popover after delay
    this.hoverTimeout = setTimeout(() => {
      if (this.recordId) {
        this.updatePopoverPosition();
        this.showPopover = true;
      }
    }, this.delay);
  }

  handleMouseLeave() {
    // Clear timeout if mouse leaves before delay
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
      this.hoverTimeout = null;
    }
    this.showPopover = false;
  }

  updatePopoverPosition() {
    // Position popover near cursor, offset to avoid covering the link
    const offsetX = 15;
    const offsetY = 10;

    // Get viewport dimensions
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;

    // Calculate position
    let left = this.mouseX + offsetX;
    let top = this.mouseY + offsetY;

    // Adjust if popover would go off-screen
    // We'll estimate popover size (typically ~300px wide, ~200px tall)
    const popoverWidth = 320;
    const popoverHeight = 200;

    if (left + popoverWidth > viewportWidth) {
      // Position to the left of cursor instead
      left = this.mouseX - popoverWidth - offsetX;
    }

    if (top + popoverHeight > viewportHeight) {
      // Position above cursor instead
      top = this.mouseY - popoverHeight - offsetY;
    }

    // Ensure popover stays within viewport
    left = Math.max(10, Math.min(left, viewportWidth - popoverWidth - 10));
    top = Math.max(10, Math.min(top, viewportHeight - popoverHeight - 10));

    this.popoverStyle = `left: ${left}px; top: ${top}px;`;
  }

  get iconName() {
    if (this.objectApiName === "Account") {
      return "standard:account";
    } else if (this.objectApiName === "Contact") {
      return "standard:contact";
    } else if (this.objectApiName === "Event") {
      return "standard:event";
    }
    return "standard:record";
  }

  get hasFields() {
    return this.recordFields && this.recordFields.length > 0;
  }

  disconnectedCallback() {
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
    }
  }
}
