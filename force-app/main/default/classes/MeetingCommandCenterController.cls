/**
 * Controller (facade) for the Meeting Command Center LWCs. This class exposes
 * the @AuraEnabled surface the components depend on and delegates the work to
 * focused, composable services:
 *
 *  - MeetingDataService          read-only event / recap / prep queries
 *  - MeetingContextService       Account/Opportunity/Contact context resolution
 *  - MeetingContentService       AI subject/description generation for events & tasks
 *  - MeetingRecapService         recap submit / insights / commit / persistence
 *  - MeetingTranscriptionService Deepgram speech-to-text
 *  - MeetingPromptFactory        prompt construction
 *  - MeetingAIGateway            Models API integration
 *  - MeetingUtils                shared JSON / date / string helpers
 *
 * Keeping the controller thin makes each concern independently testable and
 * lets prompts, queries, and persistence evolve without touching the LWC
 * contract.
 */
public with sharing class MeetingCommandCenterController {
    /**
     * Fetches events for a specific date for the current user.
     * @param selectedDate ISO date (YYYY-MM-DD); null/blank uses today.
     * @return Event field maps, each with a Recap_Completed__c flag.
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getTodaysEvents(String selectedDate) {
        return MeetingDataService.getTodaysEvents(selectedDate);
    }

    /**
     * Gets the Account info (accountId, accountName) for a list of Contact IDs.
     */
    @AuraEnabled(cacheable=true)
    public static Map<Id, Map<String, String>> getContactAccountMap(List<Id> contactIds) {
        return MeetingDataService.getContactAccountMap(contactIds);
    }

    /**
     * Gets the Meeting_Recap__c ID for a given Event ID, or null.
     */
    @AuraEnabled(cacheable=true)
    public static String getMeetingRecapId(String eventId) {
        return MeetingDataService.getMeetingRecapId(eventId);
    }

    /**
     * Gets the most recent Meeting_Prep__c ID for a given Event ID, or null.
     */
    @AuraEnabled(cacheable=true)
    public static String getMeetingPrepId(String eventId) {
        return MeetingDataService.getMeetingPrepId(eventId);
    }

    /**
     * Submits a meeting recap for AI processing and returns the recap ID.
     */
    @AuraEnabled
    public static String submitMeetingRecap(String eventId, String recapText) {
        return MeetingRecapService.submit(eventId, recapText);
    }

    /**
     * Retrieves the Deepgram API key from Custom Metadata, or null.
     */
    @AuraEnabled(cacheable=true)
    public static String getDeepgramApiKey() {
        return MeetingTranscriptionService.getApiKey();
    }

    /**
     * Transcribes an audio chunk using Deepgram and returns the text.
     */
    @AuraEnabled
    public static String transcribeAudioChunk(String audioBase64, String existingText) {
        return MeetingTranscriptionService.transcribe(audioBase64, existingText);
    }

    /**
     * Gets account prep information (account/opportunity/contact + AI activity
     * summary) for a meeting recap.
     */
    @AuraEnabled
    public static Map<String, Object> getAccountPrepInfo(String eventId) {
        return MeetingContextService.buildAccountPrepInfo(eventId);
    }

    /**
     * Generates an AI subject + description for a new event from related-record
     * context.
     */
    @AuraEnabled
    public static Map<String, String> generateEventContent(
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        return MeetingContentService.generateEventContent(accountId, contactId, opportunityId, caseId);
    }

    /**
     * Generates an AI subject + description for a new task from an action item.
     */
    @AuraEnabled
    public static Map<String, String> generateTaskContent(
        String taskText,
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        return MeetingContentService.generateTaskContent(taskText, accountId, contactId, opportunityId, caseId);
    }

    /**
     * Generates an AI subject + description for a new event from an action item.
     */
    @AuraEnabled
    public static Map<String, String> generateEventContentFromText(
        String eventText,
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        return MeetingContentService.generateEventContentFromText(
            eventText,
            accountId,
            contactId,
            opportunityId,
            caseId
        );
    }

    /**
     * Gets Event record data for hover popover display.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEventRecord(String eventId) {
        return MeetingDataService.getEventRecord(eventId);
    }

    /**
     * Analyzes recap notes into review-ready insights (no commit): summary,
     * suggested Opportunity updates, and suggested follow-up tasks.
     */
    @AuraEnabled
    public static Map<String, Object> generateRecapInsights(String eventId, String recapText) {
        return MeetingRecapService.generateInsights(eventId, recapText);
    }

    /**
     * Returns the current values + active stage options for a single
     * Opportunity (used when the rep re-targets the Opportunity in the UI).
     */
    @AuraEnabled
    public static Map<String, Object> getOpportunitySnapshot(String opportunityId) {
        if (String.isBlank(opportunityId)) {
            throw new AuraHandledException('Opportunity ID is required');
        }
        return MeetingContextService.opportunitySnapshot(opportunityId);
    }

    /**
     * Persists a reviewed recap (recap record, Opportunity updates, audit rows,
     * follow-up tasks) from a JSON payload and returns the recap ID.
     */
    @AuraEnabled
    public static String commitRecap(String payloadJson) {
        return MeetingRecapService.commitReviewedRecap(payloadJson);
    }
}
