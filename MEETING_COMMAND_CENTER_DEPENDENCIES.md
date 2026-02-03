# Meeting Command Center LWC - Complete Dependency List

This document lists all dependencies required for the Meeting Command Center Lightning Web Component to function properly.

## Core Component Files

### Main Component
- `force-app/main/default/lwc/meetingCommandCenter/meetingCommandCenter.js`
- `force-app/main/default/lwc/meetingCommandCenter/meetingCommandCenter.html`
- `force-app/main/default/lwc/meetingCommandCenter/meetingCommandCenter.css`
- `force-app/main/default/lwc/meetingCommandCenter/meetingCommandCenter.js-meta.xml`

## Dependent Lightning Web Components

### 1. meetingRecapModal
**Location:** `force-app/main/default/lwc/meetingRecapModal/`
- **Files:**
  - `meetingRecapModal.js`
  - `meetingRecapModal.html`
  - `meetingRecapModal.css`
  - `meetingRecapModal.js-meta.xml`
- **Purpose:** Modal component for creating meeting recaps with voice transcription
- **Dependencies:**
  - Uses `MeetingCommandCenterController.submitMeetingRecap`
  - Uses `MeetingCommandCenterController.transcribeAudioChunk`
  - Uses `MeetingCommandCenterController.getAccountPrepInfo`
  - Uses `@salesforce/resourceUrl/AgentforceRGBIcon` (static resource)

### 2. recordHoverPopover
**Location:** `force-app/main/default/lwc/recordHoverPopover/`
- **Files:**
  - `recordHoverPopover.js`
  - `recordHoverPopover.html` (if exists)
  - `recordHoverPopover.css` (if exists)
  - `recordHoverPopover.js-meta.xml`
- **Purpose:** Displays record details on hover for Event, Account, and Contact records
- **Dependencies:**
  - Uses `MeetingCommandCenterController.getEventRecord`
  - Uses `lightning/uiRecordApi` for Account and Contact records

## Apex Classes

### 1. MeetingCommandCenterController
**Location:** `force-app/main/default/classes/MeetingCommandCenterController.cls`
**Metadata:** `force-app/main/default/classes/MeetingCommandCenterController.cls-meta.xml`

**Methods Used:**
- `getTodaysEvents(String selectedDate)` - Fetches events for a specific date
- `getMeetingRecapId(String eventId)` - Gets Meeting Recap ID for an event
- `getMeetingPrepId(String eventId)` - Gets Meeting Prep ID for an event
- `generateEventContent(String accountId, String contactId, String opportunityId, String caseId)` - Generates AI-powered event content
- `getEventRecord(String eventId)` - Gets Event record data for hover popover
- `submitMeetingRecap(String eventId, String recapText)` - Creates/updates meeting recap with AI summarization
- `transcribeAudioChunk(String audioBase64, String existingText)` - Transcribes audio using Deepgram API
- `getAccountPrepInfo(String eventId)` - Gets account prep information
- `getDeepgramApiKey()` - Retrieves Deepgram API key from Custom Metadata

**Dependencies:**
- Uses `aiplatform.ModelsAPI` for AI summarization
- Uses `Deepgram_API_Config__mdt` Custom Metadata Type
- Queries standard objects: Event, Account, Contact, Opportunity, Case, Task
- Queries custom objects: Meeting_Recap__c, Meeting_Prep__c

### 2. MeetingRecapController
**Location:** `force-app/main/default/classes/MeetingRecapController.cls`
**Metadata:** `force-app/main/default/classes/MeetingRecapController.cls-meta.xml`

**Methods Used:**
- `getEventRecapData(String eventId)` - Fetches Event data with related Meeting Recap data
- `getMeetingRecapData(String recapId)` - Fetches Meeting Recap data by ID

**Note:** This controller is used by the `meetingRecap` component (separate from the modal), but may be referenced indirectly.

## Custom Objects

### 1. Meeting_Recap__c
**Required Fields:**
- `Event__c` (Lookup to Event) - Links recap to the event
- `Recap_Completed__c` (Checkbox) - Indicates if recap is completed
- `Original_Recap_Text__c` (Long Text Area) - User's original recap text
- `AI_Meeting_Summary__c` (Rich Text Area) - AI-generated summary
- `AI_Key_Outcomes__c` (Rich Text Area) - AI-generated key outcomes
- `AI_Next_Steps__c` (Rich Text Area) - AI-generated next steps

**Location:** `force-app/main/default/objects/Meeting_Recap__c/`

### 2. Meeting_Prep__c (Referenced but not directly used)
**Purpose:** Used for meeting preparation functionality
**Note:** The component references this object but doesn't directly query it in the main component

## Custom Metadata Types

### Deepgram_API_Config__mdt
**Location:** `force-app/main/default/customMetadata/Deepgram_API_Config__mdt/`
**Required Fields:**
- `API_Key__c` (Text) - Deepgram API key for voice transcription

**Note:** Used for audio transcription feature in the meeting recap modal.

## Static Resources

### AgentforceRGBIcon
**Location:** `force-app/main/default/staticresources/AgentforceRGBIcon.resource-meta.xml`
**Purpose:** Icon used in the meeting recap modal

## Standard Objects & Fields Used

### Event (Standard Object)
**Fields Used:**
- `Id`
- `Subject`
- `StartDateTime`
- `EndDateTime`
- `Location`
- `Description`
- `DurationInMinutes`
- `WhatId` (Lookup to Account)
- `What.Name` (Related Account Name)
- `WhoId` (Lookup to Contact)
- `Who.Name` (Related Contact Name)
- `OwnerId`
- `Type`
- `IsAllDayEvent`

### Account (Standard Object)
**Fields Used:**
- `Id`
- `Name`
- `Phone`
- `Website`
- `Industry`
- `Type`
- `BillingCity`
- `BillingState`
- `AnnualRevenue`

### Contact (Standard Object)
**Fields Used:**
- `Id`
- `Name`
- `Email`
- `Phone`
- `Title`
- `Department`
- `MailingCity`
- `MailingState`

### Opportunity (Standard Object)
**Fields Used:** (In controller for context building)
- `Id`
- `Name`
- `StageName`
- `Amount`
- `CloseDate`
- `Probability`
- `AccountId`
- `Account.Name`
- `CreatedDate`
- `OwnerId`

### Case (Standard Object)
**Fields Used:** (In controller for context building)
- `Id`
- `Subject`
- `Status`
- `Priority`
- `Description`
- `AccountId`
- `Account.Name`
- `CreatedDate`
- `OwnerId`

### Task (Standard Object)
**Fields Used:** (In controller for context building)
- `Id`
- `Subject`
- `Status`
- `WhatId`
- `CreatedDate`

## Lightning Platform APIs & Modules

### Core LWC Modules
- `lwc` - Core Lightning Web Component framework
- `lightning/platformShowToastEvent` - Toast notifications
- `lightning/navigation` - Navigation service
- `lightning/platformWorkspaceApi` - Workspace API for console navigation
- `lightning/pageReferenceUtils` - Page reference utilities (encodeDefaultFieldValues)
- `lightning/uiRecordApi` - Record data service (used by recordHoverPopover)
- `@salesforce/i18n/timeZone` - User timezone information

### Salesforce AI Platform
- `aiplatform.ModelsAPI` - Salesforce Models API for AI summarization
- Model: `sfdc_ai__DefaultOpenAIGPT4Omni` (used for AI generation)

## Standard Lightning Components Used

### Base Components
- `lightning-card`
- `lightning-icon`
- `lightning-button`
- `lightning-badge`
- `lightning-spinner`

## Metadata Files

### Flexipage
- `force-app/main/default/flexipages/Meeting_Command_Center.flexipage-meta.xml`

### Tab
- `force-app/main/default/tabs/Meeting_Command_Center.tab-meta.xml`

### App
- `force-app/main/default/applications/Meeting_Command_Center_App.app-meta.xml` (if exists)

## Test Classes

### MeetingCommandCenterControllerTest
**Location:** `force-app/main/default/classes/MeetingCommandCenterControllerTest.cls`
**Purpose:** Unit tests for MeetingCommandCenterController

## Permission Sets & Profiles

### Permission Set
- `Meeting_Recap_All_Fields` - Grants access to Meeting_Recap__c fields
  **Location:** `force-app/main/default/permissionsets/Meeting_Recap_All_Fields.permissionset-meta.xml`

### Profiles
- System Administrator profile includes field-level security for Meeting_Recap__c fields
- Admin profile includes field-level security for Activity.Recap_Completed__c

## External APIs

### Deepgram API
**Purpose:** Voice transcription for meeting recap modal
**Endpoint:** `https://api.deepgram.com/v1/listen`
**Configuration:** Stored in `Deepgram_API_Config__mdt` Custom Metadata Type

## Summary of File Counts

- **LWC Components:** 3 (meetingCommandCenter, meetingRecapModal, recordHoverPopover)
- **Apex Classes:** 2 (MeetingCommandCenterController, MeetingRecapController)
- **Custom Objects:** 2 (Meeting_Recap__c, Meeting_Prep__c)
- **Custom Metadata Types:** 1 (Deepgram_API_Config__mdt)
- **Static Resources:** 1 (AgentforceRGBIcon)
- **Standard Objects Used:** 6 (Event, Account, Contact, Opportunity, Case, Task)

## Notes for Repository Setup

1. **Deployment Order:**
   - Deploy Custom Metadata Types first
   - Deploy Custom Objects and Fields
   - Deploy Apex Classes
   - Deploy Static Resources
   - Deploy LWC Components (all together)
   - Deploy Permission Sets
   - Deploy Flexipages/Tabs/Apps

2. **Required Configuration:**
   - Configure Deepgram API key in Custom Metadata Type
   - Ensure Einstein Generative AI is enabled in org
   - Set up field-level security for Meeting_Recap__c fields
   - Configure permission sets for users who need access

3. **Optional Dependencies:**
   - Meeting_Prep__c object is referenced but not strictly required for core functionality
   - Deepgram transcription is optional (component handles missing API key gracefully)
