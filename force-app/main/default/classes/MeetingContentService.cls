/**
 * Generates AI-powered, customer-facing subject + description content for new
 * events and tasks. Each method gathers context, builds the matching prompt,
 * calls the Models API, and parses the response with safe fallbacks.
 */
public with sharing class MeetingContentService {
    /**
     * Generates a meeting subject + description from related-record context.
     */
    public static Map<String, String> generateEventContent(
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        Map<String, String> result = new Map<String, String>();
        try {
            String context = contextFor(accountId, contactId, opportunityId, caseId);
            String prompt = MeetingPromptFactory.eventGeneration(context, accountId, contactId, opportunityId, caseId);
            return parseResponse(MeetingAIGateway.generate(prompt));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating event content: ' + e.getMessage());
            result.put('subject', 'Follow-up Meeting');
            result.put('description', 'Meeting to discuss next steps and follow-up items.');
            return result;
        }
    }

    /**
     * Generates a task subject + description from an action item plus context.
     */
    public static Map<String, String> generateTaskContent(
        String taskText,
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        Map<String, String> result = new Map<String, String>();
        try {
            String context = contextFor(accountId, contactId, opportunityId, caseId);
            String prompt = MeetingPromptFactory.taskGeneration(
                taskText,
                context,
                accountId,
                contactId,
                opportunityId,
                caseId
            );
            return parseResponse(MeetingAIGateway.generate(prompt));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating task content: ' + e.getMessage());
            result.put('subject', taskText != null ? taskText : 'Follow-up Task');
            result.put('description', 'Task to complete follow-up items and next steps.');
            return result;
        }
    }

    /**
     * Generates a calendar-event subject + description from an action item
     * plus context.
     */
    public static Map<String, String> generateEventContentFromText(
        String eventText,
        String accountId,
        String contactId,
        String opportunityId,
        String caseId
    ) {
        Map<String, String> result = new Map<String, String>();
        try {
            String context = contextFor(accountId, contactId, opportunityId, caseId);
            String prompt = MeetingPromptFactory.eventTextGeneration(
                eventText,
                context,
                accountId,
                contactId,
                opportunityId,
                caseId
            );
            return parseResponse(MeetingAIGateway.generate(prompt));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating event content from text: ' + e.getMessage());
            result.put('subject', eventText != null ? eventText : 'Follow-up Meeting');
            result.put(
                'description',
                'Meeting to discuss next steps and follow-up items. Please come prepared with any relevant materials or questions.'
            );
            return result;
        }
    }

    /**
     * Resolves specific related-record context, falling back to the user's
     * general recent activity when nothing specific is provided.
     */
    private static String contextFor(String accountId, String contactId, String opportunityId, String caseId) {
        String context = MeetingContextService.buildEventContext(accountId, contactId, opportunityId, caseId);
        if (String.isBlank(context)) {
            context = MeetingContextService.buildGeneralContext();
        }
        return context;
    }

    /**
     * Parses the subject/description JSON from the AI response, with fallbacks
     * and Event Subject length enforcement (255 chars).
     */
    private static Map<String, String> parseResponse(String aiResponse) {
        Map<String, String> result = new Map<String, String>();

        try {
            String jsonContent = MeetingUtils.extractJsonFromResponse(aiResponse);

            if (String.isNotBlank(jsonContent)) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(jsonContent);

                String subject = (String) responseMap.get('subject');
                String description = (String) responseMap.get('description');

                if (String.isNotBlank(subject)) {
                    if (subject.length() > 255) {
                        subject = subject.substring(0, 252) + '...';
                    }
                    result.put('subject', subject.trim());
                } else {
                    result.put('subject', 'Follow-up Meeting');
                }

                if (String.isNotBlank(description)) {
                    result.put('description', description.trim());
                } else {
                    result.put('description', 'Meeting to discuss next steps and follow-up items.');
                }
            } else {
                result.put('subject', 'Follow-up Meeting');
                result.put('description', 'Meeting to discuss next steps and follow-up items.');
            }
        } catch (Exception e) {
            System.debug('Error parsing event content response: ' + e.getMessage());
            result.put('subject', 'Follow-up Meeting');
            result.put('description', 'Meeting to discuss next steps and follow-up items.');
        }

        return result;
    }
}
