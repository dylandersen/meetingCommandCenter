@isTest
public class MeetingPrepIntelligenceTest {
  @TestSetup
  static void setupTestData() {
    // Create test account
    Account testAccount = new Account(
      Name = 'Test Company',
      Industry = 'Technology',
      Type = 'Customer',
      AnnualRevenue = 5000000,
      NumberOfEmployees = 100,
      Website = 'https://www.testcompany.com'
    );
    insert testAccount;

    // Create test contacts
    List<Contact> contacts = new List<Contact>();
    contacts.add(
      new Contact(
        FirstName = 'John',
        LastName = 'Smith',
        Title = 'VP of Sales',
        Email = 'john.smith@testcompany.com',
        AccountId = testAccount.Id
      )
    );
    contacts.add(
      new Contact(
        FirstName = 'Jane',
        LastName = 'Doe',
        Title = 'Director of Operations',
        Email = 'jane.doe@testcompany.com',
        AccountId = testAccount.Id
      )
    );
    insert contacts;

    // Create test opportunity
    Opportunity testOpp = new Opportunity(
      Name = 'Test Deal',
      AccountId = testAccount.Id,
      Amount = 100000,
      StageName = 'Negotiation',
      Type = 'New Business',
      NextStep = 'Finalize contract',
      Description = 'Large enterprise deal',
      CloseDate = Date.today().addDays(15),
      Probability = 75
    );
    insert testOpp;

    // Create test case
    Case testCase = new Case(
      Subject = 'Integration Issue',
      AccountId = testAccount.Id,
      Status = 'Open',
      Priority = 'High',
      Description = 'Customer experiencing API integration problems'
    );
    insert testCase;

    // Create test event
    Event testEvent = new Event(
      Subject = 'Executive Business Review',
      WhatId = testAccount.Id,
      WhoId = contacts[0].Id,
      StartDateTime = Datetime.now().addDays(2),
      EndDateTime = Datetime.now().addDays(2).addHours(1),
      Location = 'Customer Office',
      Description = 'Quarterly review meeting with executive team'
    );
    insert testEvent;

    // Create event relations
    List<EventRelation> relations = new List<EventRelation>();
    relations.add(
      new EventRelation(EventId = testEvent.Id, RelationId = contacts[1].Id)
    );
    insert relations;

    // Create tasks
    List<Task> tasks = new List<Task>();
    tasks.add(
      new Task(
        Subject = 'Prepare presentation',
        WhatId = testAccount.Id,
        Status = 'In Progress',
        ActivityDate = Date.today().addDays(1),
        Priority = 'High'
      )
    );
    insert tasks;
  }

  @isTest
  static void testGenerateMeetingPrep_ValidEvent() {
    // Get test event
    Event testEvent = [SELECT Id FROM Event LIMIT 1];

    // Create input
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = testEvent.Id;
    input.regenerate = false;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify results
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      true,
      results[0].success,
      'Generation should be successful'
    );
    System.assertNotEquals(
      null,
      results[0].meetingPrepId,
      'Meeting prep ID should not be null'
    );
    System.assertNotEquals(
      null,
      results[0].prepBriefHTML,
      'Prep brief HTML should not be null'
    );
    System.assert(
      results[0].prepBriefHTML.length() > 0,
      'Prep brief should have content'
    );

    // Verify Meeting_Prep__c record was created
    List<Meeting_Prep__c> preps = [
      SELECT Id, Event__c, Prep_Brief_HTML__c
      FROM Meeting_Prep__c
      WHERE Event__c = :testEvent.Id
    ];
    System.assertEquals(
      1,
      preps.size(),
      'Should create one Meeting_Prep__c record'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_ExistingPrep() {
    // Get test event
    Event testEvent = [SELECT Id FROM Event LIMIT 1];

    // Create existing prep
    Meeting_Prep__c existingPrep = new Meeting_Prep__c();
    existingPrep.Event__c = testEvent.Id;
    existingPrep.Generated_Date__c = DateTime.now().addDays(-1);
    existingPrep.Prep_Brief_HTML__c = '<p>Existing prep brief</p>';
    insert existingPrep;

    // Create input without regenerate flag
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = testEvent.Id;
    input.regenerate = false;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify existing prep is returned
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      existingPrep.Id,
      results[0].meetingPrepId,
      'Should return existing prep ID'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_Regenerate() {
    // Get test event
    Event testEvent = [SELECT Id FROM Event LIMIT 1];

    // Create existing prep
    Meeting_Prep__c existingPrep = new Meeting_Prep__c();
    existingPrep.Event__c = testEvent.Id;
    existingPrep.Generated_Date__c = DateTime.now().addDays(-1);
    existingPrep.Prep_Brief_HTML__c = '<p>Old prep brief</p>';
    insert existingPrep;

    // Create input with regenerate flag
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = testEvent.Id;
    input.regenerate = true;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify new prep is generated
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertNotEquals(
      existingPrep.Id,
      results[0].meetingPrepId,
      'Should create new prep, not return existing'
    );

    // Verify two preps exist
    List<Meeting_Prep__c> preps = [
      SELECT Id
      FROM Meeting_Prep__c
      WHERE Event__c = :testEvent.Id
    ];
    System.assertEquals(2, preps.size(), 'Should have two prep records');
  }

  @isTest
  static void testGenerateMeetingPrep_InvalidEventId() {
    // Create input with invalid event ID
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = '00U000000000000'; // Invalid ID
    input.regenerate = false;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify error result
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      false,
      results[0].success,
      'Generation should fail for invalid ID'
    );
    System.assert(
      results[0].message.contains('Event not found'),
      'Should return error message about event not found'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_EmptyInput() {
    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>()
    );
    Test.stopTest();

    // Verify error result
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      false,
      results[0].success,
      'Generation should fail for empty input'
    );
    System.assert(
      results[0].message.contains('No event ID provided'),
      'Should return error message about missing event ID'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_NullInput() {
    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      null
    );
    Test.stopTest();

    // Verify error result
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      false,
      results[0].success,
      'Generation should fail for null input'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_EventWithoutAccount() {
    // Create event without account linkage
    Contact testContact = new Contact(
      FirstName = 'Bob',
      LastName = 'Johnson',
      Email = 'bob@example.com'
    );
    insert testContact;

    Event testEvent = new Event(
      Subject = 'Standalone Meeting',
      WhoId = testContact.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1)
    );
    insert testEvent;

    // Create input
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = testEvent.Id;
    input.regenerate = false;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify results - should still generate prep even without account
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(
      true,
      results[0].success,
      'Generation should succeed even without account'
    );
  }

  @isTest
  static void testGenerateMeetingPrep_WithOpportunityLink() {
    // Get test data
    Opportunity testOpp = [SELECT Id FROM Opportunity LIMIT 1];

    // Create event linked to opportunity
    Event testEvent = new Event(
      Subject = 'Deal Review',
      WhatId = testOpp.Id,
      StartDateTime = Datetime.now().addDays(1),
      EndDateTime = Datetime.now().addDays(1).addHours(1)
    );
    insert testEvent;

    // Create input
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = testEvent.Id;
    input.regenerate = false;

    Test.startTest();
    List<MeetingPrepOutput> results = MeetingPrepIntelligence.generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );
    Test.stopTest();

    // Verify results include opportunity context
    System.assertEquals(1, results.size(), 'Should return exactly one result');
    System.assertEquals(true, results[0].success, 'Generation should succeed');
    System.assertNotEquals(
      null,
      results[0].prepBriefHTML,
      'Prep brief should be generated'
    );
  }
}
