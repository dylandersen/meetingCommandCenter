/**
 * Read-only query layer for the Meeting Command Center: today's events with
 * recap status, contact/account lookups, recap and prep record IDs, and the
 * lightweight Event record used by the hover popover. Keeping the cacheable
 * reads here separates them from the AI/persistence services.
 */
public with sharing class MeetingDataService {
    /**
     * Returns the current user's events for the given date (today when blank)
     * as field maps, each augmented with a Recap_Completed__c flag.
     */
    public static List<Map<String, Object>> getTodaysEvents(String selectedDate) {
        Date targetDate;
        if (String.isNotBlank(selectedDate)) {
            try {
                targetDate = Date.valueOf(selectedDate);
            } catch (Exception e) {
                targetDate = Date.today();
            }
        } else {
            targetDate = Date.today();
        }

        DateTime startOfDay = DateTime.newInstance(targetDate, Time.newInstance(0, 0, 0, 0));
        DateTime endOfDay = DateTime.newInstance(targetDate, Time.newInstance(23, 59, 59, 999));

        List<Event> events = [
            SELECT
                Id,
                Subject,
                StartDateTime,
                EndDateTime,
                Location,
                Description,
                DurationInMinutes,
                WhatId,
                What.Name,
                WhoId,
                Who.Name
            FROM Event
            WHERE OwnerId = :UserInfo.getUserId() AND StartDateTime >= :startOfDay AND StartDateTime <= :endOfDay
            ORDER BY StartDateTime ASC
        ];

        Set<Id> eventIds = new Set<Id>();
        for (Event evt : events) {
            eventIds.add(evt.Id);
        }

        Map<Id, Meeting_Recap__c> recapMap = new Map<Id, Meeting_Recap__c>();
        if (!eventIds.isEmpty()) {
            for (Meeting_Recap__c recap : [
                SELECT Id, Event__c, Recap_Completed__c
                FROM Meeting_Recap__c
                WHERE Event__c IN :eventIds
            ]) {
                recapMap.put(recap.Event__c, recap);
            }
        }

        List<Map<String, Object>> eventMaps = new List<Map<String, Object>>();
        for (Event evt : events) {
            Meeting_Recap__c recap = recapMap.get(evt.Id);
            Map<String, Object> eventMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(evt));
            eventMap.put('Recap_Completed__c', recap != null && recap.Recap_Completed__c == true);
            eventMaps.add(eventMap);
        }

        return eventMaps;
    }

    /**
     * Maps each Contact ID to its account info (accountId, accountName).
     */
    public static Map<Id, Map<String, String>> getContactAccountMap(List<Id> contactIds) {
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
        if (contactIds == null || contactIds.isEmpty()) {
            return result;
        }

        for (Contact c : [
            SELECT Id, AccountId, Account.Name
            FROM Contact
            WHERE Id IN :contactIds AND AccountId != NULL
        ]) {
            result.put(c.Id, new Map<String, String>{ 'accountId' => c.AccountId, 'accountName' => c.Account.Name });
        }
        return result;
    }

    /**
     * Returns the Meeting_Recap__c ID for an Event, or null.
     */
    public static String getMeetingRecapId(String eventId) {
        if (String.isBlank(eventId)) {
            return null;
        }

        List<Meeting_Recap__c> recaps = [SELECT Id FROM Meeting_Recap__c WHERE Event__c = :eventId LIMIT 1];
        return recaps.isEmpty() ? null : recaps[0].Id;
    }

    /**
     * Returns the most recent Meeting_Prep__c ID for an Event, or null.
     */
    public static String getMeetingPrepId(String eventId) {
        if (String.isBlank(eventId)) {
            return null;
        }

        List<Meeting_Prep__c> preps = [
            SELECT Id
            FROM Meeting_Prep__c
            WHERE Event__c = :eventId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return preps.isEmpty() ? null : preps[0].Id;
    }

    /**
     * Returns the Event fields used by the hover popover as a field map.
     */
    public static Map<String, Object> getEventRecord(String eventId) {
        Map<String, Object> result = new Map<String, Object>();

        if (String.isBlank(eventId)) {
            return result;
        }

        try {
            List<Event> events = [
                SELECT Id, Subject, StartDateTime, EndDateTime, Location, Description, Type, IsAllDayEvent
                FROM Event
                WHERE Id = :eventId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            if (!events.isEmpty()) {
                Event evt = events[0];
                result.put('Id', evt.Id);
                result.put('Subject', evt.Subject);
                result.put('StartDateTime', evt.StartDateTime);
                result.put('EndDateTime', evt.EndDateTime);
                result.put('Location', evt.Location);
                result.put('Description', evt.Description);
                result.put('Type', evt.Type);
                result.put('IsAllDayEvent', evt.IsAllDayEvent);
            }
        } catch (Exception e) {
            System.debug('Error fetching Event record: ' + e.getMessage());
        }

        return result;
    }
}
