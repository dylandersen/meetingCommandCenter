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

  @track recordFields = [];

  hoverTimeout;
  mouseX = 0;
  mouseY = 0;
  // Popover is rendered into document.body (portal) so it is never clipped by
  // the surrounding table cell overflow / scroll containers.
  portalEl = null;
  isHovering = false;

  // SLDS standard object icon colors used as a small accent in the header
  static OBJECT_COLORS = {
    Account: "#7f8de1",
    Contact: "#a094ed",
    Event: "#eb7092"
  };

  // SLDS utility icon path data (viewBox 0 0 52 52) for each object type
  static OBJECT_ICONS = {
    Account:
      '<path d="M21,4H7C5.3,4,4,5.3,4,7v40c0,0.5,0.5,1,1,1h4c0.6,0,1-0.4,1-1v-6c0-0.6,0.4-1,1-1h6c0.6,0,1,0.4,1,1v6c0,0.6,0.4,1,1,1h3c1.1,0,2-0.9,2-2V7C24,5.3,22.7,4,21,4z M12,35.5c0,0.3-0.2,0.5-0.5,0.5h-3C8.2,36,8,35.8,8,35.5v-5C8,30.2,8.2,30,8.5,30h3c0.3,0,0.5,0.2,0.5,0.5V35.5z M12,25.5c0,0.3-0.2,0.5-0.5,0.5h-3C8.2,26,8,25.8,8,25.5v-5C8,20.2,8.2,20,8.5,20h3c0.3,0,0.5,0.2,0.5,0.5V25.5z M12,15.5c0,0.3-0.2,0.5-0.5,0.5h-3C8.2,16,8,15.8,8,15.5v-5C8,10.2,8.2,10,8.5,10h3c0.3,0,0.5,0.2,0.5,0.5V15.5z M20,35.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V35.5z M20,25.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V25.5z M20,15.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V15.5z"/><path d="M45,14H31c-1.7,0-3,1.3-3,3v30c0,0.5,0.5,1,1,1h4c0.6,0,1-0.4,1-1v-6c0-0.6,0.4-1,1-1h6c0.6,0,1,0.4,1,1v6c0,0.6,0.4,1,1,1h3c1.1,0,2-0.9,2-2V17C48,15.3,46.7,14,45,14z M36,35.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V35.5z M36,25.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V25.5z M44,35.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V35.5z M44,25.5c0,0.3-0.2,0.5-0.5,0.5h-3c-0.3,0-0.5-0.2-0.5-0.5v-5c0-0.3,0.2-0.5,0.5-0.5h3c0.3,0,0.5,0.2,0.5,0.5V25.5z"/>',
    Contact:
      '<path d="M50,43v2.2c0,2.6-2.2,4.8-4.8,4.8H6.8C4.2,50,2,47.8,2,45.2V43c0-5.8,6.8-9.4,13.2-12.2c0.2-0.1,0.4-0.2,0.6-0.3c0.5-0.2,1-0.2,1.5,0.1c2.6,1.7,5.5,2.6,8.6,2.6s6.1-1,8.6-2.6c0.5-0.3,1-0.3,1.5-0.1c0.2,0.1,0.4,0.2,0.6,0.3C43.2,33.6,50,37.1,50,43z M26,2c6.6,0,11.9,5.9,11.9,13.2S32.6,28.4,26,28.4s-11.9-5.9-11.9-13.2S19.4,2,26,2z"/>',
    Event:
      '<path d="M46.5,20h-41C4.7,20,4,20.7,4,21.5V46c0,2.2,1.8,4,4,4h36c2.2,0,4-1.8,4-4V21.5C48,20.7,47.3,20,46.5,20z M19,42c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V42z M19,32c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V32z M29,42c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V42z M29,32c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V32z M39,42c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V42z M39,32c0,0.6-0.4,1-1,1h-4c-0.6,0-1-0.4-1-1v-4c0-0.6,0.4-1,1-1h4c0.6,0,1,0.4,1,1V32z"/><path d="M44,7h-4h-1V5c0-1.6-1.3-3-3-3l0,0c-1.6,0-3,1.3-3,3v2H19V5c0-1.6-1.3-3-3-3l0,0c-1.6,0-3,1.3-3,3v2h-1H8c-2.2,0-4,1.8-4,4v2.5C4,14.3,4.7,15,5.5,15h41c0.8,0,1.5-0.7,1.5-1.5V11C48,8.8,46.2,7,44,7z"/>'
  };

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
    this.refreshPortal();
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
    this.refreshPortal();
  }

  handleMouseEnter(event) {
    // Clear any existing timeout
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
    }

    // Store mouse position
    this.mouseX = event.clientX;
    this.mouseY = event.clientY;
    this.isHovering = true;

    // Show popover after delay
    this.hoverTimeout = setTimeout(() => {
      if (this.recordId && this.isHovering) {
        this.openPortal();
      }
    }, this.delay);
  }

  handleMouseLeave() {
    // Clear timeout if mouse leaves before delay
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
      this.hoverTimeout = null;
    }
    this.isHovering = false;
    this.closePortal();
  }

  /**
   * Compute a viewport-anchored position near the cursor, keeping the
   * popover fully on-screen.
   */
  computePosition() {
    const offsetX = 15;
    const offsetY = 10;
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const popoverWidth = 320;
    const popoverHeight = 200;

    let left = this.mouseX + offsetX;
    let top = this.mouseY + offsetY;

    if (left + popoverWidth > viewportWidth) {
      left = this.mouseX - popoverWidth - offsetX;
    }
    if (top + popoverHeight > viewportHeight) {
      top = this.mouseY - popoverHeight - offsetY;
    }

    left = Math.max(10, Math.min(left, viewportWidth - popoverWidth - 10));
    top = Math.max(10, Math.min(top, viewportHeight - popoverHeight - 10));

    return { left, top };
  }

  /**
   * Render the popover into document.body so it escapes the table cell's
   * overflow/stacking context (which was clipping it).
   */
  openPortal() {
    this.closePortal();

    const el = document.createElement("div");
    el.className = "rhp-portal";
    const { left, top } = this.computePosition();
    el.style.cssText = [
      "position: fixed",
      `left: ${left}px`,
      `top: ${top}px`,
      "z-index: 99999",
      "min-width: 300px",
      "max-width: 400px",
      "pointer-events: none",
      "font-family: var(--lwc-fontFamily, 'Salesforce Sans', Arial, sans-serif)"
    ].join(";");

    el.appendChild(this.buildCard());
    document.body.appendChild(el);
    this.portalEl = el;
  }

  /** Rebuild the portal contents in place if it is currently open. */
  refreshPortal() {
    if (!this.portalEl) {
      return;
    }
    this.portalEl.innerHTML = "";
    this.portalEl.appendChild(this.buildCard());
  }

  closePortal() {
    if (this.portalEl && this.portalEl.parentNode) {
      this.portalEl.parentNode.removeChild(this.portalEl);
    }
    this.portalEl = null;
  }

  /**
   * Build the popover card DOM (uses textContent for record values to avoid
   * any HTML injection from field data).
   */
  buildCard() {
    const accent =
      RecordHoverPopover.OBJECT_COLORS[this.objectApiName] || "#0176d3";

    const card = document.createElement("div");
    card.style.cssText = [
      "background-color: #ffffff",
      "box-shadow: 0 4px 16px rgba(0,0,0,0.18)",
      "border: 1px solid #e5e5e5",
      "border-radius: 0.5rem",
      "overflow: hidden"
    ].join(";");

    // Header
    const header = document.createElement("div");
    header.style.cssText = [
      "display: flex",
      "align-items: center",
      "gap: 0.5rem",
      "padding: 0.5rem 0.75rem",
      "background: linear-gradient(135deg, #fafaf9 0%, #f3f3f3 100%)",
      "border-bottom: 1px solid #e5e5e5"
    ].join(";");

    const badge = document.createElement("span");
    badge.style.cssText = [
      "display: inline-flex",
      "align-items: center",
      "justify-content: center",
      "width: 1.25rem",
      "height: 1.25rem",
      "border-radius: 50%",
      "flex-shrink: 0",
      "color: #ffffff",
      `background-color: ${accent}`
    ].join(";");
    const iconPaths = RecordHoverPopover.OBJECT_ICONS[this.objectApiName] || "";
    badge.innerHTML = `<svg viewBox="0 0 52 52" width="12" height="12" fill="currentColor" aria-hidden="true">${iconPaths}</svg>`;

    const title = document.createElement("span");
    title.textContent = this.objectApiName || "Record";
    title.style.cssText = [
      "font-weight: 600",
      "font-size: 0.75rem",
      "color: #181818",
      "text-transform: uppercase",
      "letter-spacing: 0.5px"
    ].join(";");

    header.appendChild(badge);
    header.appendChild(title);
    card.appendChild(header);

    // Content
    const content = document.createElement("div");
    content.style.cssText = [
      "padding: 0.75rem",
      "background-color: #ffffff",
      "min-height: 40px"
    ].join(";");

    if (this.recordFields && this.recordFields.length > 0) {
      this.recordFields.forEach((field, index) => {
        const row = document.createElement("div");
        row.style.cssText = [
          "display: flex",
          "flex-direction: column",
          "gap: 0.125rem",
          "padding: 0.4rem 0",
          index < this.recordFields.length - 1
            ? "border-bottom: 1px solid #f0f0f0"
            : ""
        ].join(";");

        const label = document.createElement("div");
        label.textContent = field.label;
        label.style.cssText = [
          "font-size: 0.6875rem",
          "color: #706e6b",
          "text-transform: uppercase",
          "letter-spacing: 0.5px",
          "font-weight: 600",
          "line-height: 1.2"
        ].join(";");

        const value = document.createElement("div");
        value.textContent = field.value;
        const valueColor =
          field.fieldType === "email" ? "#0176d3" : "#181818";
        value.style.cssText = [
          "font-size: 0.8125rem",
          `color: ${valueColor}`,
          "word-wrap: break-word",
          "line-height: 1.4"
        ].join(";");

        row.appendChild(label);
        row.appendChild(value);
        content.appendChild(row);
      });
    } else {
      const loading = document.createElement("div");
      loading.textContent = "Loading record details...";
      loading.style.cssText = [
        "text-align: center",
        "color: #706e6b",
        "font-size: 0.8125rem"
      ].join(";");
      content.appendChild(loading);
    }

    card.appendChild(content);
    return card;
  }

  disconnectedCallback() {
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout);
    }
    this.closePortal();
  }
}
