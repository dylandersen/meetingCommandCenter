# Meeting Command Center

A Salesforce Lightning Web Component for managing daily meetings and creating AI-powered meeting recaps.

## Overview

The Meeting Command Center provides a comprehensive dashboard for viewing daily meetings, creating AI-powered recaps, and managing meeting-related activities. It integrates with Salesforce's Einstein Generative AI to automatically generate meeting summaries, key outcomes, and next steps.

## Features

- **Daily Meeting View**: View all meetings for a selected date with intuitive navigation
- **AI-Powered Meeting Recaps**: Automatically generate comprehensive meeting summaries using Salesforce's Models API
- **Voice Transcription**: Record and transcribe meeting notes using Deepgram API integration
- **Meeting Preparation**: Access meeting prep information and related account/contact details
- **Actionable Next Steps**: Convert meeting outcomes into Tasks and Events with AI-generated content

## Components

### Lightning Web Components
- `meetingCommandCenter` - Main dashboard component
- `meetingRecapModal` - Modal for creating meeting recaps with voice transcription
- `recordHoverPopover` - Hover popover showing record details

### Apex Classes
- `MeetingCommandCenterController` - Main controller with methods for fetching events, generating AI content, and managing recaps
- `MeetingRecapController` - Controller for fetching meeting recap data

## Dependencies

See [MEETING_COMMAND_CENTER_DEPENDENCIES.md](./MEETING_COMMAND_CENTER_DEPENDENCIES.md) for a complete list of all dependencies.

### Key Dependencies
- **Custom Objects**: `Meeting_Recap__c`, `Meeting_Prep__c`
- **Custom Metadata**: `Deepgram_API_Config__mdt` (optional, for voice transcription)
- **Static Resources**: `AgentforceRGBIcon`
- **Salesforce AI Platform**: Einstein Generative AI (Models API)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/dylandersen/meetingCommandCenter.git
   ```
2. Deploy to your Salesforce org using Salesforce CLI:
   ```bash
   sf project deploy start --source-dir force-app
   ```
3. Configure Deepgram API key (optional) in Custom Metadata Type `Deepgram_API_Config__mdt`
4. Assign permission set `Meeting_Recap_All_Fields` to users who need access
5. Ensure Einstein Generative AI is enabled in your org

## Deployment Order

1. Custom Metadata Types (if using Deepgram)
2. Custom Objects and Fields
3. Apex Classes
4. Static Resources
5. Lightning Web Components
6. Permission Sets
7. Flexipages/Tabs/Apps

## Usage

1. Navigate to the Meeting Command Center tab or add the component to a Flexipage
2. Use the date navigation arrows to view meetings for different dates
3. Click "Recap Meeting" on past events to create AI-powered recaps
4. Use "Prep for Meeting" on upcoming events to access meeting preparation
5. View completed recaps by clicking "View Recap"

## Configuration

### Deepgram API (Optional)
To enable voice transcription:
1. Create a Custom Metadata Type record for `Deepgram_API_Config__mdt`
2. Set the Developer Name to "Default"
3. Add your Deepgram API key to the `API_Key__c` field

### Einstein Generative AI
Ensure Einstein Generative AI is enabled in your org. The component uses the `sfdc_ai__DefaultOpenAIGPT4Omni` model.

## Testing

Run the test class:
```bash
sf apex run test --class-names MeetingCommandCenterControllerTest --result-format human
```

## License

This project is open source and free to use. See LICENSE file for details.

## Support

**No support is provided for this project.**

For non-support requests, please contact Dylan Andersen at dylan.andersen@salesforce.com.

**Author:** Dylan Andersen, Senior Solution Engineer, Agentforce at Salesforce
