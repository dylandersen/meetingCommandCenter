// Script to create 2 test events from earlier today with contacts and accounts
// Usage: sf org run apex -f scripts/apex/create_test_recap_events.apex

// Get current user ID
Id currentUserId = UserInfo.getUserId();

// Get contacts with their accounts
List<Contact> contacts = [
    SELECT Id, Name, AccountId, Account.Name 
    FROM Contact 
    WHERE AccountId != null 
    ORDER BY CreatedDate DESC 
    LIMIT 10
];

if (contacts.isEmpty()) {
    System.debug('ERROR: No contacts with accounts found. Please create contacts first.');
    return;
}

// Get today's date and current time
Date today = Date.today();
DateTime now = DateTime.now();

// Create 2 events from earlier today
List<Event> eventsToInsert = new List<Event>();

// Event 1: Morning meeting (2 hours ago)
DateTime event1Start = now.addHours(-2);
Event evt1 = new Event(
    Subject = 'Client Strategy Session - ' + contacts[0].Account.Name,
    StartDateTime = event1Start,
    EndDateTime = event1Start.addHours(1),
    OwnerId = currentUserId,
    WhoId = contacts[0].Id,
    WhatId = contacts[0].AccountId,
    Description = 'Strategic planning session to discuss Q1 objectives and key initiatives.',
    Location = 'Conference Room B'
);
eventsToInsert.add(evt1);

// Event 2: Mid-morning call (3 hours ago)
DateTime event2Start = now.addHours(-3);
Event evt2 = new Event(
    Subject = 'Product Roadmap Review - ' + (contacts.size() > 1 ? contacts[1].Account.Name : contacts[0].Account.Name),
    StartDateTime = event2Start,
    EndDateTime = event2Start.addMinutes(45),
    OwnerId = currentUserId,
    WhoId = contacts.size() > 1 ? contacts[1].Id : contacts[0].Id,
    WhatId = contacts.size() > 1 ? contacts[1].AccountId : contacts[0].AccountId,
    Description = 'Review upcoming product features and gather feedback on priorities.',
    Location = 'Virtual - Zoom'
);
eventsToInsert.add(evt2);

// Insert events
try {
    insert eventsToInsert;
    System.debug('Successfully created ' + eventsToInsert.size() + ' test events for earlier today:');
    for (Event e : eventsToInsert) {
        System.debug('Event: ' + e.Subject + ' - Start: ' + e.StartDateTime + ' - Contact: ' + e.WhoId + ' - Account: ' + e.WhatId);
    }
} catch (Exception e) {
    System.debug('Error creating events: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
}

System.debug('Script completed!');
