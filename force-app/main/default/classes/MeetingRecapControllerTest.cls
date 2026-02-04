@isTest
public class MeetingRecapControllerTest {
  
  @TestSetup
  static void setupTestData() {
    // Create test account
    Account testAccount = new Account(
      Name = 'Test Company',
      Industry = 'Technology',
      Type = 'Customer'
    );
    insert testAccount;

    // Create test contact
    Contact testContact = new Contact(
      FirstName = 'John',
      LastName = 'Smith',
      Title = 'VP of Sales',
      Email = 'john.smith@testcompany.com',
      AccountId = testAccount.Id
    );
    insert testContact;

    // Create test event
    DateTime now = DateTime.now();
    Event testEvent = new Event(
      Subject = 'Test Meeting',
      WhatId = testAccount.Id,
      WhoId = testContact.Id,
      StartDateTime = now.addHours(-1),
      EndDateTime = now.addHours(1),
      Location = 'Conference Room A',
      Description = 'Test meeting description'
    );
    insert testEvent;

    // Create Meeting Recap for the event
    Meeting_Recap__c testRecap = new Meeting_Recap__c(
      Event__c = testEvent.Id,
      Original_Recap_Text__c = 'The meeting went well. We discussed pricing.',
      AI_Meeting_Summary__c = '<p>Summary of the meeting discussion.</p>',
      AI_Key_Outcomes__c = '<ul><li>Outcome 1</li><li>Outcome 2</li></ul>',
      AI_Next_Steps__c = '<ul><li>Follow up next week</li></ul>',
      Recap_Completed__c = true
    );
    insert testRecap;

    // Create event without recap
    Event eventWithoutRecap = new Event(
      Subject = 'Meeting Without Recap',
      WhatId = testAccount.Id,
      WhoId = testContact.Id,
      StartDateTime = now.addHours(2),
      EndDateTime = now.addHours(3),
      Location = 'Zoom Call',
      Description = 'Another meeting'
    );
    insert eventWithoutRecap;

    // Create event without account/contact
    Event eventWithoutRelated = new Event(
      Subject = 'Standalone Meeting',
      StartDateTime = now.addHours(4),
      EndDateTime = now.addHours(5),
      Location = 'Office',
      Description = 'Meeting without related records'
    );
    insert eventWithoutRelated;
  }

  @isTest
  static void testGetEventRecapData_WithRecap() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Test Meeting' LIMIT 1];

    Test.startTest();
    Map<String, Object> result = MeetingRecapController.getEventRecapData(testEvent.Id);
    Test.stopTest();

    // Verify Event data
    System.assertEquals(testEvent.Id, result.get('Id'), 'Event ID should match');
    System.assertEquals('Test Meeting', result.get('Subject'), 'Subject should match');
    System.assertNotEquals(null, result.get('StartDateTime'), 'StartDateTime should be populated');
    System.assertNotEquals(null, result.get('EndDateTime'), 'EndDateTime should be populated');
    System.assertEquals('Conference Room A', result.get('Location'), 'Location should match');
    System.assertEquals('Test meeting description', result.get('Description'), 'Description should match');

    // Verify Meeting Recap data
    System.assertNotEquals(null, result.get('RecapId'), 'RecapId should be populated');
    System.assertNotEquals(null, result.get('AI_Meeting_Summary__c'), 'AI_Meeting_Summary__c should be populated');
    System.assertNotEquals(null, result.get('AI_Key_Outcomes__c'), 'AI_Key_Outcomes__c should be populated');
    System.assertNotEquals(null, result.get('AI_Next_Steps__c'), 'AI_Next_Steps__c should be populated');
    System.assertEquals(true, result.get('Recap_Completed__c'), 'Recap_Completed__c should be true');

    // Verify related data
    Map<String, Object> whatData = (Map<String, Object>) result.get('What');
    System.assertNotEquals(null, whatData, 'What data should be populated');
    System.assertEquals('Test Company', whatData.get('Name'), 'Account name should match');

    Map<String, Object> whoData = (Map<String, Object>) result.get('Who');
    System.assertNotEquals(null, whoData, 'Who data should be populated');
    System.assertEquals('John Smith', whoData.get('Name'), 'Contact name should match');
  }

  @isTest
  static void testGetEventRecapData_WithoutRecap() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Meeting Without Recap' LIMIT 1];

    Test.startTest();
    Map<String, Object> result = MeetingRecapController.getEventRecapData(testEvent.Id);
    Test.stopTest();

    // Verify Event data
    System.assertEquals(testEvent.Id, result.get('Id'), 'Event ID should match');
    System.assertEquals('Meeting Without Recap', result.get('Subject'), 'Subject should match');

    // Verify Meeting Recap fields are null/false
    System.assertEquals(null, result.get('RecapId'), 'RecapId should be null');
    System.assertEquals(null, result.get('AI_Meeting_Summary__c'), 'AI_Meeting_Summary__c should be null');
    System.assertEquals(null, result.get('AI_Key_Outcomes__c'), 'AI_Key_Outcomes__c should be null');
    System.assertEquals(null, result.get('AI_Next_Steps__c'), 'AI_Next_Steps__c should be null');
    System.assertEquals(false, result.get('Recap_Completed__c'), 'Recap_Completed__c should be false');
  }

  @isTest
  static void testGetEventRecapData_WithoutRelatedRecords() {
    Event testEvent = [SELECT Id FROM Event WHERE Subject = 'Standalone Meeting' LIMIT 1];

    Test.startTest();
    Map<String, Object> result = MeetingRecapController.getEventRecapData(testEvent.Id);
    Test.stopTest();

    // Verify Event data
    System.assertEquals(testEvent.Id, result.get('Id'), 'Event ID should match');
    System.assertEquals('Standalone Meeting', result.get('Subject'), 'Subject should match');

    // Verify related data is null
    System.assertEquals(null, result.get('What'), 'What data should be null');
    System.assertEquals(null, result.get('Who'), 'Who data should be null');
    System.assertEquals(null, result.get('WhatId'), 'WhatId should be null');
    System.assertEquals(null, result.get('WhoId'), 'WhoId should be null');
  }

  @isTest
  static void testGetEventRecapData_BlankEventId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getEventRecapData('');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for blank Event ID');
  }

  @isTest
  static void testGetEventRecapData_NullEventId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getEventRecapData(null);
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for null Event ID');
  }

  @isTest
  static void testGetEventRecapData_InvalidEventId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getEventRecapData('00U000000000000AAA');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for invalid Event ID');
  }

  @isTest
  static void testGetMeetingRecapData_ValidRecap() {
    Meeting_Recap__c testRecap = [SELECT Id FROM Meeting_Recap__c LIMIT 1];

    Test.startTest();
    Map<String, Object> result = MeetingRecapController.getMeetingRecapData(testRecap.Id);
    Test.stopTest();

    // Verify Recap data
    System.assertEquals(testRecap.Id, result.get('RecapId'), 'RecapId should match');
    System.assertNotEquals(null, result.get('AI_Meeting_Summary__c'), 'AI_Meeting_Summary__c should be populated');
    System.assertNotEquals(null, result.get('AI_Key_Outcomes__c'), 'AI_Key_Outcomes__c should be populated');
    System.assertNotEquals(null, result.get('AI_Next_Steps__c'), 'AI_Next_Steps__c should be populated');
    System.assertEquals(true, result.get('Recap_Completed__c'), 'Recap_Completed__c should be true');

    // Verify Event data
    System.assertNotEquals(null, result.get('Id'), 'Event ID should be populated');
    System.assertEquals('Test Meeting', result.get('Subject'), 'Event Subject should match');
    System.assertNotEquals(null, result.get('StartDateTime'), 'StartDateTime should be populated');
    System.assertNotEquals(null, result.get('EndDateTime'), 'EndDateTime should be populated');

    // Verify related data
    Map<String, Object> whatData = (Map<String, Object>) result.get('What');
    System.assertNotEquals(null, whatData, 'What data should be populated');
    System.assertEquals('Test Company', whatData.get('Name'), 'Account name should match');

    Map<String, Object> whoData = (Map<String, Object>) result.get('Who');
    System.assertNotEquals(null, whoData, 'Who data should be populated');
    System.assertEquals('John Smith', whoData.get('Name'), 'Contact name should match');
  }

  @isTest
  static void testGetMeetingRecapData_BlankRecapId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getMeetingRecapData('');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for blank Recap ID');
  }

  @isTest
  static void testGetMeetingRecapData_NullRecapId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getMeetingRecapData(null);
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for null Recap ID');
  }

  @isTest
  static void testGetMeetingRecapData_InvalidRecapId() {
    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getMeetingRecapData('a0X000000000000AAA');
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception for invalid Recap ID');
  }

  @isTest
  static void testGetMeetingRecapData_RecapWithMissingEvent() {
    // Test with a valid recap but delete its event to simulate orphaned recap scenario
    Meeting_Recap__c testRecap = [SELECT Id, Event__c FROM Meeting_Recap__c LIMIT 1];
    Event testEvent = [SELECT Id FROM Event WHERE Id = :testRecap.Event__c LIMIT 1];
    
    // Delete the event to simulate orphaned recap scenario
    delete testEvent;

    Test.startTest();
    Boolean exceptionThrown = false;
    try {
      MeetingRecapController.getMeetingRecapData(testRecap.Id);
    } catch (Exception e) {
      exceptionThrown = true;
    }
    Test.stopTest();
    System.assert(exceptionThrown, 'Should throw an exception when Event is missing');
  }
}
