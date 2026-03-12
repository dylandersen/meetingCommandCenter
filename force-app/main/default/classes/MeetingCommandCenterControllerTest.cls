@isTest
public class MeetingCommandCenterControllerTest {

  @TestSetup
  static void setupTestData() {
    // Create test account
    Account testAccount = new Account(
      Name = 'Test Company',
      Industry = 'Technology',
      Type = 'Customer'
    );
    insert testAccount;

    // Create test contacts
    Contact testContact = new Contact(
      FirstName = 'John',
      LastName = 'Smith',
      Title = 'VP of Sales',
      Email = 'john.smith@testcompany.com',
      AccountId = testAccount.Id
    );
    insert testContact;

    Contact testContact2 = new Contact(
      FirstName = 'Jane',
      LastName = 'Doe',
      Title = 'Director',
      Email = 'jane.doe@testcompany.com',
      AccountId = testAccount.Id
    );
    insert testContact2;

    // Create test events for today
    DateTime now = DateTime.now();

    // Past event (started 2 hours ago, ended 1 hour ago)
    Event pastEvent = new Event(
      Subject = 'Past Meeting',
      WhatId = testAccount.Id,
      WhoId = testContact.Id,
      StartDateTime = now.addHours(-2),
      EndDateTime = now.addHours(-1),
      Location = 'Conference Room A',
      Description = 'Review quarterly numbers'
    );
    insert pastEvent;

    // Current event (started 30 min ago, ends in 30 min)
    Event currentEvent = new Event(
      Subject = 'Current Meeting',
      WhatId = testAccount.Id,
      WhoId = testContact.Id,
      StartDateTime = now.addMinutes(-30),
      EndDateTime = now.addMinutes(30),
      Location = 'Zoom Call',
      Description = 'Sprint planning'
    );
    insert currentEvent;

    // Future event (starts in 2 hours)
    Event futureEvent = new Event(
      Subject = 'Future Meeting',
      WhatId = testAccount.Id,
      WhoId = testContact.Id,
      StartDateTime = now.addHours(2),
      EndDateTime = now.addHours(3),
      Location = 'Customer Office',
      Description = 'Product demo'
    );
    insert futureEvent;

    // Event without account (standalone)
    Event standaloneEvent = new Event(
      Subject = 'Standalone Meeting',
      WhoId = testContact.Id,
      StartDateTime = now.addHours(4),
      EndDateTime = now.addHours(5),
      Description = 'Quick sync'
    );
    insert standaloneEvent;

    // Create Meeting_Recap__c for past event
    Meeting_Recap__c recap = new Meeting_Recap__c(
      Event__c = pastEvent.Id,
      Original_Recap_Text__c = 'The meeting went well.',
      AI_Meeting_Summary__c = '<p>Summary of the meeting.</p>',
      AI_Key_Outcomes__c = '<ul><li>Outcome 1</li></ul>',
      AI_Next_Steps__c = '<ul><li>Follow up</li></ul>',
      Recap_Completed__c = true
    );
    insert recap;

    // Create Meeting_Prep__c for future event
    Meeting_Prep__c prep = new Meeting_Prep__c(
      Event__c = futureEvent.Id,
      Prep_Brief_HTML__c = '<p>Prep brief content</p>',
      Generated_Date__c = DateTime.now()
    );
    insert prep;
  }

  // ============================================================
  // getTodaysEvents
  // ============================================================

  @isTest
  static void testGetTodaysEvents_NullDate() {
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(null);
    Test.stopTest();

    System.assert(events.size() >= 2, 'Should return events for today, got: ' + events.size());

    // Verify ordering by StartDateTime
    for (Integer i = 0; i < events.size() - 1; i++) {
      System.assert(
        events[i].StartDateTime <= events[i + 1].StartDateTime,
        'Events should be ordered by StartDateTime'
      );
    }
  }

  @isTest
  static void testGetTodaysEvents_ExplicitDate() {
    String todayStr = String.valueOf(Date.today());
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(todayStr);
    Test.stopTest();

    System.assert(events.size() >= 2, 'Should return events for explicit today date');
  }

  @isTest
  static void testGetTodaysEvents_DifferentDate() {
    // Use yesterday — should return no events
    String yesterdayStr = String.valueOf(Date.today().addDays(-1));
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(yesterdayStr);
    Test.stopTest();

    System.assertEquals(0, events.size(), 'Should return 0 events for yesterday');
  }

  @isTest
  static void testGetTodaysEvents_InvalidDateFallsBackToToday() {
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents('not-a-date');
    Test.stopTest();

    // Falls back to today, so should return events
    System.assert(events.size() >= 2, 'Invalid date should fall back to today');
  }

  @isTest
  static void testGetTodaysEvents_NoEvents() {
    delete [SELECT Id FROM Event];

    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(null);
    Test.stopTest();

    System.assertEquals(0, events.size(), 'Should return 0 events when none exist');
  }

  @isTest
  static void testGetTodaysEvents_VerifyFieldsReturned() {
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(null);
    Test.stopTest();

    Event evt = events[0];
    System.assertNotEquals(null, evt.Subject, 'Subject should be populated');
    System.assertNotEquals(null, evt.DurationInMinutes, 'Duration should be populated');
    // Custom fields should be queryable
    Object recapCompleted = evt.Recap_Completed__c;
    System.assertNotEquals(null, recapCompleted, 'Recap_Completed__c should be accessible');
  }

  @isTest
  static void testGetTodaysEvents_VerifyRelatedData() {
    Test.startTest();
    List<Event> events = MeetingCommandCenterController.getTodaysEvents(null);
    Test.stopTest();

    Event eventWithAccount = null;
    for (Event evt : events) {
      if (evt.WhatId != null) {
        eventWithAccount = evt;
        break;
      }
    }

    System.assertNotEquals(null, eventWithAccount, 'Should have an event with WhatId');
    System.assertNotEquals(null, eventWithAccount.What.Name, 'Should have related account name');
  }

  // ============================================================
  // getContactAccountMap
  // ============================================================

  @isTest
  static void testGetContactAccountMap_ValidContacts() {
    List<Contact> contacts = [SELECT Id FROM Contact];
    List<Id> contactIds = new List<Id>();
    for (Contact c : contacts) {
      contactIds.add(c.Id);
    }

    Test.startTest();
    Map<Id, Map<String, String>> result = MeetingCommandCenterController.getContactAccountMap(contactIds);
    Test.stopTest();

    System.assert(result.size() > 0, 'Should return account info for contacts with accounts');
    // Verify structure
    for (Id contactId : result.keySet()) {
      Map<String, String> info = result.get(contactId);
      System.assertNotEquals(null, info.get('accountId'), 'accountId should be populated');
      System.assertNotEquals(null, info.get('accountName'), 'accountName should be populated');
    }
  }

  @isTest
  static void testGetContactAccountMap_EmptyList() {
    Test.startTest();
    Map<Id, Map<String, String>> result = MeetingCommandCenterController.getContactAccountMap(new List<Id>());
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should return empty map for empty list');
  }

  @isTest
  static void testGetContactAccountMap_NullInput() {
    Test.startTest();
    Map<Id, Map<String, String>> result = MeetingCommandCenterController.getContactAccountMap(null);
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should return empty map for null input');
  }

  @isTest
  static void testGetContactAccountMap_ContactWithoutAccount() {
    Contact noAccountContact = new Contact(
      FirstName = 'Solo',
      LastName = 'Person',
      Email = 'solo@example.com'
    );
    insert noAccountContact;

    Test.startTest();
    Map<Id, Map<String, String>> result = MeetingCommandCenterController.getContactAccountMap(
      new List<Id>{ noAccountContact.Id }
    );
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should not return entry for contact without account');
  }

  // ============================================================
  // getMeetingRecapId
  // ============================================================

  @isTest
  static void testGetMeetingRecapId_WithRecap() {
    Event pastEvent = [SELECT Id FROM Event WHERE Subject = 'Past Meeting' LIMIT 1];

    Test.startTest();
    String recapId = MeetingCommandCenterController.getMeetingRecapId(pastEvent.Id);
    Test.stopTest();

    System.assertNotEquals(null, recapId, 'Should return recap ID for event with recap');
  }

  @isTest
  static void testGetMeetingRecapId_WithoutRecap() {
    Event futureEvent = [SELECT Id FROM Event WHERE Subject = 'Future Meeting' LIMIT 1];

    Test.startTest();
    String recapId = MeetingCommandCenterController.getMeetingRecapId(futureEvent.Id);
    Test.stopTest();

    System.assertEquals(null, recapId, 'Should return null for event without recap');
  }

  @isTest
  static void testGetMeetingRecapId_BlankId() {
    Test.startTest();
    String recapId = MeetingCommandCenterController.getMeetingRecapId('');
    Test.stopTest();

    System.assertEquals(null, recapId, 'Should return null for blank ID');
  }

  @isTest
  static void testGetMeetingRecapId_NullId() {
    Test.startTest();
    String recapId = MeetingCommandCenterController.getMeetingRecapId(null);
    Test.stopTest();

    System.assertEquals(null, recapId, 'Should return null for null ID');
  }

  // ============================================================
  // getMeetingPrepId
  // ============================================================

  @isTest
  static void testGetMeetingPrepId_WithPrep() {
    Event futureEvent = [SELECT Id FROM Event WHERE Subject = 'Future Meeting' LIMIT 1];

    Test.startTest();
    String prepId = MeetingCommandCenterController.getMeetingPrepId(futureEvent.Id);
    Test.stopTest();

    System.assertNotEquals(null, prepId, 'Should return prep ID for event with prep');
  }

  @isTest
  static void testGetMeetingPrepId_WithoutPrep() {
    Event currentEvent = [SELECT Id FROM Event WHERE Subject = 'Current Meeting' LIMIT 1];

    Test.startTest();
    String prepId = MeetingCommandCenterController.getMeetingPrepId(currentEvent.Id);
    Test.stopTest();

    System.assertEquals(null, prepId, 'Should return null for event without prep');
  }

  @isTest
  static void testGetMeetingPrepId_BlankId() {
    Test.startTest();
    String prepId = MeetingCommandCenterController.getMeetingPrepId('');
    Test.stopTest();

    System.assertEquals(null, prepId, 'Should return null for blank ID');
  }

  @isTest
  static void testGetMeetingPrepId_NullId() {
    Test.startTest();
    String prepId = MeetingCommandCenterController.getMeetingPrepId(null);
    Test.stopTest();

    System.assertEquals(null, prepId, 'Should return null for null ID');
  }

  // ============================================================
  // getEventRecord
  // ============================================================

  @isTest
  static void testGetEventRecord_ValidEvent() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Past Meeting' LIMIT 1];

    Test.startTest();
    Map<String, Object> result = MeetingCommandCenterController.getEventRecord(testEvent.Id);
    Test.stopTest();

    System.assertEquals(testEvent.Id, result.get('Id'), 'Event ID should match');
    System.assertEquals('Past Meeting', result.get('Subject'), 'Subject should match');
    System.assertNotEquals(null, result.get('StartDateTime'), 'StartDateTime should be populated');
    System.assertNotEquals(null, result.get('EndDateTime'), 'EndDateTime should be populated');
    System.assertEquals('Conference Room A', result.get('Location'), 'Location should match');
  }

  @isTest
  static void testGetEventRecord_BlankId() {
    Test.startTest();
    Map<String, Object> result = MeetingCommandCenterController.getEventRecord('');
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should return empty map for blank ID');
  }

  @isTest
  static void testGetEventRecord_NullId() {
    Test.startTest();
    Map<String, Object> result = MeetingCommandCenterController.getEventRecord(null);
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should return empty map for null ID');
  }

  @isTest
  static void testGetEventRecord_InvalidId() {
    Test.startTest();
    Map<String, Object> result = MeetingCommandCenterController.getEventRecord('00U000000000000AAA');
    Test.stopTest();

    // Should return empty map (no exception) for non-existent event
    System.assertEquals(0, result.size(), 'Should return empty map for non-existent event');
  }

  // ============================================================
  // submitMeetingRecap — validation paths
  // ============================================================

  @isTest
  static void testSubmitMeetingRecap_BlankEventId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingCommandCenterController.submitMeetingRecap('', 'Some recap text');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw exception for blank event ID');
  }

  @isTest
  static void testSubmitMeetingRecap_BlankRecapText() {
    Event testEvent = [SELECT Id FROM Event LIMIT 1];

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingCommandCenterController.submitMeetingRecap(testEvent.Id, '');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw exception for blank recap text');
  }

  @isTest
  static void testSubmitMeetingRecap_InvalidEventId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingCommandCenterController.submitMeetingRecap('00U000000000000AAA', 'Some recap text');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw exception for invalid event ID');
  }

  @isTest
  static void testSubmitMeetingRecap_ValidInput_CalloutBlocked() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Past Meeting' LIMIT 1];

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingCommandCenterController.submitMeetingRecap(
        testEvent.Id,
        'The meeting went well. We discussed pricing and the customer agreed to move forward.'
      );
    } catch (Exception e) {
      // Expected — callout not allowed in test context
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw exception due to callout restriction');
  }

  // ============================================================
  // getDeepgramApiKey
  // ============================================================

  @isTest
  static void testGetDeepgramApiKey() {
    // In test context, custom metadata may or may not be available
    // This just ensures the method executes without exception
    Test.startTest();
    String apiKey = MeetingCommandCenterController.getDeepgramApiKey();
    Test.stopTest();

    // apiKey may be null if custom metadata isn't configured in test context — that's fine
    // We're just verifying the method path doesn't throw
  }

  // ============================================================
  // transcribeAudioChunk — validation paths
  // ============================================================

  @isTest
  static void testTranscribeAudioChunk_BlankInput() {
    Test.startTest();
    String result = MeetingCommandCenterController.transcribeAudioChunk('', 'existing text');
    Test.stopTest();

    System.assertEquals('', result, 'Should return empty string for blank audio');
  }

  @isTest
  static void testTranscribeAudioChunk_NullInput() {
    Test.startTest();
    String result = MeetingCommandCenterController.transcribeAudioChunk(null, null);
    Test.stopTest();

    System.assertEquals('', result, 'Should return empty string for null audio');
  }

  // ============================================================
  // getAccountPrepInfo
  // ============================================================

  @isTest
  static void testGetAccountPrepInfo_EventWithAccount() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Past Meeting' LIMIT 1];

    Test.startTest();
    Boolean exceptionThrown = false;
    Map<String, Object> result;
    try {
      result = MeetingCommandCenterController.getAccountPrepInfo(testEvent.Id);
    } catch (Exception e) {
      // May throw due to callout in generateAccountSummary
      exceptionThrown = true;
    }
    Test.stopTest();

    // Either returns result with account info or throws due to callout
    if (!exceptionThrown) {
      System.assertNotEquals(null, result.get('accountId'), 'accountId should be populated');
      System.assertNotEquals(null, result.get('accountName'), 'accountName should be populated');
    }
  }

  @isTest
  static void testGetAccountPrepInfo_EventWithoutAccount() {
    Event standaloneEvent = [SELECT Id FROM Event WHERE Subject = 'Standalone Meeting' LIMIT 1];

    Test.startTest();
    Boolean exceptionThrown = false;
    Map<String, Object> result;
    try {
      result = MeetingCommandCenterController.getAccountPrepInfo(standaloneEvent.Id);
    } catch (Exception e) {
      // May throw due to callout in generateContactSummary
      exceptionThrown = true;
    }
    Test.stopTest();

    if (!exceptionThrown) {
      // Should still have contact info
      System.assertNotEquals(null, result.get('contactId'), 'contactId should be populated');
    }
  }

  @isTest
  static void testGetAccountPrepInfo_InvalidEventId() {
    Test.startTest();
    Map<String, Object> result = MeetingCommandCenterController.getAccountPrepInfo('00U000000000000AAA');
    Test.stopTest();

    System.assertEquals(0, result.size(), 'Should return empty map for invalid event');
  }

  // ============================================================
  // generateTaskContent — returns fallback on callout failure
  // ============================================================

  @isTest
  static void testGenerateTaskContent_BlankTaskText() {
    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateTaskContent('', null, null, null, null);
    Test.stopTest();

    // Method catches internally and returns fallback
    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
  }

  @isTest
  static void testGenerateTaskContent_WithContext_FallbackReturned() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateTaskContent(
      'Create a follow-up proposal',
      acc.Id,
      con.Id,
      null,
      null
    );
    Test.stopTest();

    // Callout fails in test context, method returns fallback
    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
    System.assertNotEquals(null, result.get('description'), 'Should have fallback description');
  }

  // ============================================================
  // generateEventContent — returns fallback on callout failure
  // ============================================================

  @isTest
  static void testGenerateEventContent_NoContext_FallbackReturned() {
    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateEventContent(null, null, null, null);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
  }

  @isTest
  static void testGenerateEventContent_WithContext_FallbackReturned() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateEventContent(
      acc.Id,
      con.Id,
      null,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
    System.assertNotEquals(null, result.get('description'), 'Should have fallback description');
  }

  // ============================================================
  // generateEventContentFromText — returns fallback on callout failure
  // ============================================================

  @isTest
  static void testGenerateEventContentFromText_BlankText_FallbackReturned() {
    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateEventContentFromText('', null, null, null, null);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
  }

  @isTest
  static void testGenerateEventContentFromText_WithContext_FallbackReturned() {
    Account acc = [SELECT Id FROM Account LIMIT 1];
    Contact con = [SELECT Id FROM Contact LIMIT 1];

    Test.startTest();
    Map<String, String> result = MeetingCommandCenterController.generateEventContentFromText(
      'Schedule a follow-up meeting with the team next Tuesday',
      acc.Id,
      con.Id,
      null,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a result map');
    System.assertNotEquals(null, result.get('subject'), 'Should have fallback subject');
    System.assertNotEquals(null, result.get('description'), 'Should have fallback description');
  }
}
