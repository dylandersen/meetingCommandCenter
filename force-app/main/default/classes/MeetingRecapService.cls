/**
 * Owns the meeting-recap lifecycle: the legacy one-shot submit, the
 * review-first "generate insights" analysis, and the "commit" that persists an
 * approved recap (Meeting_Recap__c, Opportunity field updates, audit rows, and
 * follow-up Tasks). Read context comes from MeetingContextService, prompts
 * from MeetingPromptFactory, and AI calls from MeetingAIGateway.
 */
public with sharing class MeetingRecapService {
    /**
     * Legacy path: summarizes a recap with the Models API and upserts the
     * Meeting_Recap__c, returning its ID for navigation.
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

    /**
     * Analyzes recap notes into review-ready insights WITHOUT committing:
     * summary/outcomes/next steps, suggested Opportunity updates (with current
     * values for comparison), and suggested follow-up tasks.
     */
    public static Map<String, Object> generateInsights(String eventId, String recapText) {
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

            Map<String, Object> ctx = MeetingContextService.resolveOpportunityContext(evt);
            Id opportunityId = (Id) ctx.get('opportunityId');

            Opportunity opp;
            List<Map<String, String>> stageOptions = new List<Map<String, String>>();
            if (opportunityId != null) {
                opp = MeetingContextService.loadOpportunity(opportunityId);
                stageOptions = MeetingContextService.activeStageOptions();
            }

            String prompt = MeetingPromptFactory.insights(evt, recapText, ctx, opp, stageOptions);
            String aiResponse = MeetingAIGateway.generate(prompt);
            Map<String, Object> parsed = parseInsightsResponse(aiResponse, recapText);

            Map<String, Object> output = new Map<String, Object>();
            output.put('summary', parsed.get('summary'));
            output.put('keyOutcomes', parsed.get('keyOutcomes'));
            output.put('nextSteps', parsed.get('nextSteps'));
            output.put('tasks', parsed.get('tasks'));

            Map<String, Object> oppBlock = new Map<String, Object>();
            oppBlock.put('hasOpportunity', opportunityId != null);
            if (opportunityId != null && opp != null) {
                oppBlock.put('id', opportunityId);
                oppBlock.put('name', ctx.get('opportunityName'));
                oppBlock.put(
                    'current',
                    new Map<String, Object>{
                        'amount' => opp.Amount,
                        'closeDate' => MeetingUtils.formatDateIso(opp.CloseDate),
                        'stageName' => opp.StageName,
                        'nextStep' => opp.NextStep
                    }
                );
                oppBlock.put('suggested', parsed.get('opportunityUpdates'));
                oppBlock.put('stageOptions', stageOptions);
            }
            output.put('opportunity', oppBlock);

            output.put('accountId', ctx.get('accountId'));
            output.put('accountName', ctx.get('accountName'));
            output.put('contactId', ctx.get('contactId'));
            output.put('contactName', ctx.get('contactName'));
            output.put('opportunityId', opportunityId);
            output.put('opportunityName', ctx.get('opportunityName'));
            output.put('currentUserName', UserInfo.getName());

            return output;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'generateInsights error: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            throw new AuraHandledException('Failed to analyze recap: ' + e.getMessage());
        }
    }

    /**
     * Persists a reviewed recap from a JSON payload: saves the
     * Meeting_Recap__c, applies approved Opportunity field updates, writes the
     * field-change audit rows, and creates approved follow-up tasks.
     */
    public static String commitReviewedRecap(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Nothing to save.');
        }
        try {
            Map<String, Object> p = (Map<String, Object>) JSON.deserializeUntyped(payloadJson);

            String eventId = (String) p.get('eventId');
            if (String.isBlank(eventId)) {
                throw new AuraHandledException('Event ID is required');
            }

            // 1) Save the recap record
            String recapId = saveRecapRecord(
                eventId,
                (String) p.get('summary'),
                (String) p.get('keyOutcomes'),
                (String) p.get('nextSteps'),
                (String) p.get('recapText')
            );

            // 2) Apply approved Opportunity field updates
            String opportunityId = (String) p.get('opportunityId');
            applyOpportunityUpdates(opportunityId, p.get('opportunityUpdates'));

            // 2b) Persist the field-change audit rows
            insertChangeRows(recapId, p.get('changes'));

            // 3) Create approved follow-up tasks
            insertFollowUpTasks(p, opportunityId);

            return recapId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'commit error: ' + e.getMessage());
            System.debug(e.getStackTraceString());
            throw new AuraHandledException('Failed to save recap: ' + e.getMessage());
        }
    }

    /**
     * Applies the approved Opportunity field updates, only issuing DML when at
     * least one field actually changed.
     */
    private static void applyOpportunityUpdates(String opportunityId, Object oppUpdatesObj) {
        if (String.isBlank(opportunityId) || !(oppUpdatesObj instanceof Map<String, Object>)) {
            return;
        }
        Map<String, Object> u = (Map<String, Object>) oppUpdatesObj;
        if (u.isEmpty()) {
            return;
        }

        Opportunity o = new Opportunity(Id = opportunityId);
        Boolean hasChange = false;
        if (u.get('amount') != null) {
            o.Amount = Decimal.valueOf(String.valueOf(u.get('amount')));
            hasChange = true;
        }
        if (u.get('closeDate') != null && String.isNotBlank(String.valueOf(u.get('closeDate')))) {
            o.CloseDate = Date.valueOf(String.valueOf(u.get('closeDate')));
            hasChange = true;
        }
        if (u.get('stageName') != null && String.isNotBlank(String.valueOf(u.get('stageName')))) {
            o.StageName = String.valueOf(u.get('stageName'));
            hasChange = true;
        }
        if (u.containsKey('nextStep') && u.get('nextStep') != null) {
            o.NextStep = String.valueOf(u.get('nextStep'));
            hasChange = true;
        }
        if (hasChange) {
            update o;
        }
    }

    /**
     * Inserts the field-change audit rows so the recap display can show what
     * changed (previous value, new value, AI override).
     */
    private static void insertChangeRows(String recapId, Object changesObj) {
        if (String.isBlank(recapId) || !(changesObj instanceof List<Object>)) {
            return;
        }
        List<Object> changeList = (List<Object>) changesObj;
        List<Meeting_Recap_Change__c> changeRows = new List<Meeting_Recap_Change__c>();
        for (Object c : changeList) {
            Map<String, Object> cm = (Map<String, Object>) c;
            String fieldLabel = (String) cm.get('fieldLabel');
            if (String.isBlank(fieldLabel)) {
                continue;
            }
            Meeting_Recap_Change__c row = new Meeting_Recap_Change__c();
            row.Meeting_Recap__c = recapId;
            row.Field_Label__c = MeetingUtils.safeTrunc(fieldLabel, 255);
            row.Field_API_Name__c = MeetingUtils.safeTrunc((String) cm.get('fieldApiName'), 255);
            row.Object_Name__c = MeetingUtils.safeTrunc((String) cm.get('objectName'), 255);
            row.Previous_Value__c = (String) cm.get('previousValue');
            row.New_Value__c = (String) cm.get('newValue');
            row.AI_Suggested_Value__c = (String) cm.get('aiSuggestedValue');
            row.AI_Overridden__c = cm.get('overridden') == true;
            row.Target_Record_Id__c = MeetingUtils.safeTrunc((String) cm.get('targetRecordId'), 18);
            changeRows.add(row);
        }
        if (!changeRows.isEmpty()) {
            insert changeRows;
        }
    }

    /**
     * Creates the approved follow-up tasks, defaulting Related To (WhatId) to
     * the meeting's Opportunity/Account and Name (WhoId) to its Contact.
     */
    private static void insertFollowUpTasks(Map<String, Object> p, String opportunityId) {
        Object tasksObj = p.get('tasks');
        if (!(tasksObj instanceof List<Object>)) {
            return;
        }
        List<Object> taskList = (List<Object>) tasksObj;
        String defaultWhatId = String.isNotBlank(opportunityId) ? opportunityId : (String) p.get('accountId');
        String whoId = (String) p.get('contactId');
        List<Task> toInsert = new List<Task>();
        for (Object t : taskList) {
            Map<String, Object> tm = (Map<String, Object>) t;
            String subject = (String) tm.get('subject');
            if (String.isBlank(subject)) {
                continue;
            }
            Task task = new Task();
            task.Subject = subject.length() > 255 ? subject.substring(0, 255) : subject;
            task.Description = (String) tm.get('description');
            Object dd = tm.get('dueDate');
            if (dd != null && String.isNotBlank(String.valueOf(dd))) {
                try {
                    task.ActivityDate = Date.valueOf(String.valueOf(dd));
                } catch (Exception ignore) {
                    // leave ActivityDate null if the value is unparseable
                }
            }
            task.Status = 'Not Started';
            task.Priority = 'Normal';
            task.OwnerId = UserInfo.getUserId();
            String taskWhatId = tm.get('whatId') != null ? String.valueOf(tm.get('whatId')) : defaultWhatId;
            if (String.isNotBlank(taskWhatId)) {
                task.WhatId = taskWhatId;
            }
            if (String.isNotBlank(whoId)) {
                task.WhoId = whoId;
            }
            toInsert.add(task);
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * Parses the combined insights JSON, with safe fallbacks.
     */
    private static Map<String, Object> parseInsightsResponse(String aiResponse, String fallbackRecap) {
        Map<String, Object> result = new Map<String, Object>{
            'summary' => '',
            'keyOutcomes' => null,
            'nextSteps' => null,
            'opportunityUpdates' => new Map<String, Object>(),
            'tasks' => new List<Object>()
        };

        try {
            String jsonContent = MeetingUtils.extractJsonFromResponse(aiResponse);
            if (String.isNotBlank(jsonContent)) {
                Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(jsonContent);
                if (m.get('summary') != null) {
                    result.put('summary', m.get('summary'));
                }
                if (m.get('keyOutcomes') != null) {
                    result.put('keyOutcomes', m.get('keyOutcomes'));
                }
                if (m.get('nextSteps') != null) {
                    result.put('nextSteps', m.get('nextSteps'));
                }
                if (m.get('opportunityUpdates') instanceof Map<String, Object>) {
                    result.put('opportunityUpdates', m.get('opportunityUpdates'));
                }
                if (m.get('tasks') instanceof List<Object>) {
                    result.put('tasks', m.get('tasks'));
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to parse insights JSON: ' + e.getMessage());
        }

        if (String.isBlank((String) result.get('summary'))) {
            result.put('summary', 'Meeting recap: ' + fallbackRecap);
        }
        return result;
    }

    /**
     * Upserts the Meeting_Recap__c record for an Event.
     */
    private static String saveRecapRecord(
        Id eventId,
        String summary,
        String keyOutcomes,
        String nextSteps,
        String originalRecap
    ) {
        List<Meeting_Recap__c> existing = [SELECT Id FROM Meeting_Recap__c WHERE Event__c = :eventId LIMIT 1];
        Meeting_Recap__c recap = existing.isEmpty() ? new Meeting_Recap__c() : existing[0];
        recap.Event__c = eventId;
        recap.Original_Recap_Text__c = originalRecap;
        recap.AI_Meeting_Summary__c = String.isNotBlank(summary) ? summary : 'Meeting recap';
        recap.AI_Key_Outcomes__c = String.isNotBlank(keyOutcomes) ? keyOutcomes : null;
        recap.AI_Next_Steps__c = String.isNotBlank(nextSteps) ? nextSteps : null;
        recap.Recap_Completed__c = true;
        upsert recap;
        return recap.Id;
    }
}
