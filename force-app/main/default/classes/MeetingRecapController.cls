/**
 * Controller for Meeting Recap LWC
 * Provides methods to fetch Event and Meeting Recap data
 */
public with sharing class MeetingRecapController {
  /**
   * Fetches Event data with related Meeting Recap data
   * @param eventId The Event ID to query
   * @return Map containing Event data and Meeting Recap fields
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getEventRecapData(String eventId) {
    if (String.isBlank(eventId)) {
      throw new AuraHandledException('Event ID is required');
    }

    // Query Event
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
      WHERE Id = :eventId
      LIMIT 1
    ];

    if (events.isEmpty()) {
      throw new AuraHandledException('Event not found');
    }

    Event evt = events[0];

    // Query Meeting Recap for this Event
    List<Meeting_Recap__c> recaps = [
      SELECT
        Id,
        Original_Recap_Text__c,
        AI_Meeting_Summary__c,
        AI_Key_Outcomes__c,
        AI_Next_Steps__c,
        Recap_Completed__c
      FROM Meeting_Recap__c
      WHERE Event__c = :eventId
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];

    // Build result map with Event data
    Map<String, Object> result = new Map<String, Object>();
    result.put('Id', evt.Id);
    result.put('Subject', evt.Subject);
    result.put('StartDateTime', evt.StartDateTime);
    result.put('EndDateTime', evt.EndDateTime);
    result.put('Location', evt.Location);
    result.put('Description', evt.Description);
    result.put('DurationInMinutes', evt.DurationInMinutes);
    result.put('WhatId', evt.WhatId);
    result.put('WhoId', evt.WhoId);

    // Add related Account/Contact data
    if (evt.What != null) {
      Map<String, Object> whatData = new Map<String, Object>();
      whatData.put('Name', evt.What.Name);
      result.put('What', whatData);
    }

    if (evt.Who != null) {
      Map<String, Object> whoData = new Map<String, Object>();
      whoData.put('Name', evt.Who.Name);
      result.put('Who', whoData);
    }

    // Add Meeting Recap fields if recap exists
    if (!recaps.isEmpty()) {
      Meeting_Recap__c recap = recaps[0];
      result.put('AI_Meeting_Summary__c', recap.AI_Meeting_Summary__c);
      result.put('AI_Key_Outcomes__c', recap.AI_Key_Outcomes__c);
      result.put('AI_Next_Steps__c', recap.AI_Next_Steps__c);
      result.put('Recap_Completed__c', recap.Recap_Completed__c);
      result.put('RecapId', recap.Id);
    } else {
      result.put('AI_Meeting_Summary__c', null);
      result.put('AI_Key_Outcomes__c', null);
      result.put('AI_Next_Steps__c', null);
      result.put('Recap_Completed__c', false);
      result.put('RecapId', null);
    }

    return result;
  }

  /**
   * Fetches Meeting Recap data by Recap ID
   * @param recapId The Meeting_Recap__c ID to query
   * @return Map containing Event data and Meeting Recap fields
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getMeetingRecapData(String recapId) {
    if (String.isBlank(recapId)) {
      throw new AuraHandledException('Recap ID is required');
    }

    // Query Meeting Recap
    List<Meeting_Recap__c> recaps = [
      SELECT
        Id,
        Event__c,
        Original_Recap_Text__c,
        AI_Meeting_Summary__c,
        AI_Key_Outcomes__c,
        AI_Next_Steps__c,
        Recap_Completed__c
      FROM Meeting_Recap__c
      WHERE Id = :recapId
      LIMIT 1
    ];

    if (recaps.isEmpty()) {
      throw new AuraHandledException('Meeting Recap not found');
    }

    Meeting_Recap__c recap = recaps[0];

    // Query Event separately
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
      WHERE Id = :recap.Event__c
      LIMIT 1
    ];

    if (events.isEmpty()) {
      throw new AuraHandledException('Event not found for this Meeting Recap');
    }

    Event evt = events[0];

    // Build result map with Event data
    Map<String, Object> result = new Map<String, Object>();
    result.put('Id', evt.Id);
    result.put('Subject', evt.Subject);
    result.put('StartDateTime', evt.StartDateTime);
    result.put('EndDateTime', evt.EndDateTime);
    result.put('Location', evt.Location);
    result.put('Description', evt.Description);
    result.put('DurationInMinutes', evt.DurationInMinutes);
    result.put('WhatId', evt.WhatId);
    result.put('WhoId', evt.WhoId);

    // Add related Account/Contact data
    if (evt.What != null) {
      Map<String, Object> whatData = new Map<String, Object>();
      whatData.put('Name', evt.What.Name);
      result.put('What', whatData);
    }

    if (evt.Who != null) {
      Map<String, Object> whoData = new Map<String, Object>();
      whoData.put('Name', evt.Who.Name);
      result.put('Who', whoData);
    }

    // Add Meeting Recap fields
    result.put('AI_Meeting_Summary__c', recap.AI_Meeting_Summary__c);
    result.put('AI_Key_Outcomes__c', recap.AI_Key_Outcomes__c);
    result.put('AI_Next_Steps__c', recap.AI_Next_Steps__c);
    result.put('Recap_Completed__c', recap.Recap_Completed__c);
    result.put('RecapId', recap.Id);

    return result;
  }
}
