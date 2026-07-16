/**
 * Owns the meeting-recap lifecycle: summarizing the rep's notes with the
 * Models API and upserting the Meeting_Recap__c record. Read context comes
 * from the Event, prompts from MeetingPromptFactory, and AI calls from
 * MeetingAIGateway.
 */
public with sharing class MeetingRecapService {
    /**
     * Summarizes a recap with the Models API and upserts the Meeting_Recap__c,
     * returning its ID for navigation.
     */
    public static String submit(String eventId, String recapText) {
        if (String.isBlank(eventId)) {
            throw new AuraHandledException('Event ID is required');
        }
        if (String.isBlank(recapText)) {
            throw new AuraHandledException('Recap text is required');
        }

        try {
            List<Event> events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, Location, WhatId, What.Name, WhoId, Who.Name
                FROM Event
                WHERE Id = :eventId
                LIMIT 1
            ];

            if (events.isEmpty()) {
                throw new AuraHandledException('Event not found');
            }

            Event evt = events[0];

            String prompt = MeetingPromptFactory.summarization(evt, recapText);
            String aiResponse = MeetingAIGateway.generate(prompt);

            return updateMeetingRecapWithSummary(evt, aiResponse, recapText);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in submit: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            System.debug('Exception type: ' + e.getTypeName());
            String errorMsg = 'Failed to save recap: ' + e.getMessage();
            if (e.getStackTraceString() != null) {
                errorMsg +=
                    ' | Stack: ' +
                    e.getStackTraceString().substring(0, Math.min(500, e.getStackTraceString().length()));
            }
            throw new AuraHandledException(errorMsg);
        }
    }

    /**
     * Parses the AI summary response and creates/updates the Meeting_Recap__c,
     * returning its ID.
     */
    private static String updateMeetingRecapWithSummary(Event evt, String aiResponse, String originalRecap) {
        try {
            if (evt == null || evt.Id == null) {
                throw new AuraHandledException('Invalid Event: Event ID is required');
            }

            String summary = '';
            String keyOutcomes = '';
            String nextSteps = '';

            try {
                String jsonContent = MeetingUtils.extractJsonFromResponse(aiResponse);

                if (String.isNotBlank(jsonContent)) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(jsonContent);
                    summary = (String) responseMap.get('summary');
                    keyOutcomes = (String) responseMap.get('keyOutcomes');
                    nextSteps = (String) responseMap.get('nextSteps');
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'Failed to parse AI response as JSON: ' + e.getMessage());
                summary = aiResponse;
            }

            if (String.isBlank(summary)) {
                summary = String.isNotBlank(originalRecap) ? 'Meeting recap: ' + originalRecap : 'Meeting recap';
            }

            List<Meeting_Recap__c> existingRecaps = [
                SELECT Id, Event__c
                FROM Meeting_Recap__c
                WHERE Event__c = :evt.Id
                LIMIT 1
            ];

            String recapId;
            if (!existingRecaps.isEmpty()) {
                Meeting_Recap__c recapToUpdate = existingRecaps[0];
                recapToUpdate.Original_Recap_Text__c = originalRecap;
                recapToUpdate.AI_Meeting_Summary__c = summary;
                recapToUpdate.AI_Key_Outcomes__c = String.isNotBlank(keyOutcomes) ? keyOutcomes : null;
                recapToUpdate.AI_Next_Steps__c = String.isNotBlank(nextSteps) ? nextSteps : null;
                recapToUpdate.Recap_Completed__c = true;
                update recapToUpdate;
                recapId = recapToUpdate.Id;
            } else {
                Meeting_Recap__c recapToInsert = new Meeting_Recap__c();
                recapToInsert.Event__c = evt.Id;
                recapToInsert.Original_Recap_Text__c = originalRecap;
                recapToInsert.AI_Meeting_Summary__c = summary;
                recapToInsert.AI_Key_Outcomes__c = String.isNotBlank(keyOutcomes) ? keyOutcomes : null;
                recapToInsert.AI_Next_Steps__c = String.isNotBlank(nextSteps) ? nextSteps : null;
                recapToInsert.Recap_Completed__c = true;
                insert recapToInsert;
                recapId = recapToInsert.Id;
            }

            return recapId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            String errorMsg = 'Failed to insert recap: ';
            for (Integer i = 0; i < e.getNumDml(); i++) {
                errorMsg += e.getDmlMessage(i) + ' (' + e.getDmlStatusCode(i) + ')';
                if (e.getDmlFieldNames(i) != null && !e.getDmlFieldNames(i).isEmpty()) {
                    errorMsg += ' Fields: ' + String.join(e.getDmlFieldNames(i), ', ');
                }
            }
            System.debug('DML error details: ' + errorMsg);
            throw new AuraHandledException(errorMsg);
        } catch (Exception e) {
            System.debug('Unexpected error in updateMeetingRecapWithSummary: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Failed to save recap: ' + e.getMessage());
        }
    }
}
