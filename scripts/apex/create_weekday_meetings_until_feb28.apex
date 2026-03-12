// Script to create 6 realistic meetings for every weekday between today and Feb 28, 2026
// Meetings scheduled between 8am-4pm with all fields filled out
// Usage: sf org run apex -f scripts/apex/create_weekday_meetings_until_feb28.apex

// Get current user ID
Id currentUserId = UserInfo.getUserId();

// Query for real contacts with their accounts
List<Contact> contacts = [
    SELECT Id, Name, AccountId, Account.Name, Title, Email, Phone
    FROM Contact
    WHERE AccountId != null
    ORDER BY Account.Name, Name
    LIMIT 20
];

if (contacts.isEmpty()) {
    System.debug('ERROR: No contacts found with accounts!');
    return;
}

System.debug('Found ' + contacts.size() + ' contacts with accounts');

// Get unique accounts
Map<Id, Account> accountMap = new Map<Id, Account>();
for (Contact c : contacts) {
    if (c.AccountId != null && !accountMap.containsKey(c.AccountId)) {
        accountMap.put(c.AccountId, new Account(Id = c.AccountId, Name = c.Account.Name));
    }
}

// Create 6 meeting templates with realistic details (using List of Maps)
List<Map<String, Object>> meetingTemplates = new List<Map<String, Object>>();

// Meeting 1: Morning Strategy Session (8:00 AM - 9:30 AM)
Map<String, Object> mt1 = new Map<String, Object>();
mt1.put('subject', 'Q1 Budget Review & Strategic Planning Session');
mt1.put('startHour', 8);
mt1.put('startMinute', 0);
mt1.put('durationMinutes', 90);
mt1.put('location', 'Conference Room A - Main Office');
mt1.put('description', 'Review Q1 budget performance and discuss strategic initiatives for the remainder of the year. Focus on key projects, resource allocation, and alignment with business objectives. Prepare to discuss ROI metrics and upcoming initiatives.');
meetingTemplates.add(mt1);

// Meeting 2: Product Demo (9:45 AM - 10:45 AM)
Map<String, Object> mt2 = new Map<String, Object>();
mt2.put('subject', 'Platform Demo & Integration Discussion');
mt2.put('startHour', 9);
mt2.put('startMinute', 45);
mt2.put('durationMinutes', 60);
mt2.put('location', 'Virtual - Zoom');
mt2.put('description', 'Demonstrate new platform capabilities and discuss integration options. Address questions about API access, data synchronization, and custom workflows. Review implementation timeline and technical requirements.');
meetingTemplates.add(mt2);

// Meeting 3: Partnership Discussion (11:00 AM - 12:00 PM)
Map<String, Object> mt3 = new Map<String, Object>();
mt3.put('subject', 'Partnership Opportunities & Technical Integration');
mt3.put('startHour', 11);
mt3.put('startMinute', 0);
mt3.put('durationMinutes', 60);
mt3.put('location', 'Client Office - Conference Room');
mt3.put('description', 'Explore potential partnership opportunities and discuss technical integration possibilities. Review capabilities, identify synergies, and plan next steps for collaboration. Discuss mutual benefits and success metrics.');
meetingTemplates.add(mt3);

// Meeting 4: Sales Performance Review (1:00 PM - 2:00 PM)
Map<String, Object> mt4 = new Map<String, Object>();
mt4.put('subject', 'Q1 Sales Performance Review & Q2 Planning');
mt4.put('startHour', 13);
mt4.put('startMinute', 0);
mt4.put('durationMinutes', 60);
mt4.put('location', 'Virtual - Microsoft Teams');
mt4.put('description', 'Review Q1 sales metrics, discuss wins and challenges. Plan Q2 strategy focusing on enterprise accounts and expansion opportunities. Review pipeline health and forecast accuracy.');
meetingTemplates.add(mt4);

// Meeting 5: Technical Deep Dive (2:15 PM - 3:15 PM)
Map<String, Object> mt5 = new Map<String, Object>();
mt5.put('subject', 'Technical Architecture Review & Implementation Planning');
mt5.put('startHour', 14);
mt5.put('startMinute', 15);
mt5.put('durationMinutes', 60);
mt5.put('location', 'Engineering Office - Tech Lab');
mt5.put('description', 'Deep dive into technical architecture and implementation planning. Review system requirements, discuss scalability considerations, and plan deployment strategy. Address security and compliance requirements.');
meetingTemplates.add(mt5);

// Meeting 6: Contract & Expansion Discussion (3:30 PM - 4:00 PM)
Map<String, Object> mt6 = new Map<String, Object>();
mt6.put('subject', 'Contract Renewal & Expansion Discussion');
mt6.put('startHour', 15);
mt6.put('startMinute', 30);
mt6.put('durationMinutes', 30);
mt6.put('location', 'Virtual - Google Meet');
mt6.put('description', 'Discuss contract renewal terms and explore expansion opportunities. Review current usage, discuss additional features needed, and negotiate pricing for increased volume. Address service level agreements and support requirements.');
meetingTemplates.add(mt6);

// Generate dates for weekdays from today until Feb 28, 2026
Date startDate = Date.today(); // Jan 27, 2026
Date endDate = Date.newInstance(2026, 2, 28);
List<Date> weekdays = new List<Date>();

Date currentDate = startDate;
while (currentDate <= endDate) {
    // Convert to DateTime to get day of week
    DateTime currentDateTime = DateTime.newInstance(currentDate, Time.newInstance(0, 0, 0, 0));
    String dayOfWeek = currentDateTime.format('EEEE'); // Returns day name like "Monday", "Tuesday", etc.
    
    // Check if it's a weekday (not Saturday or Sunday)
    if (dayOfWeek != 'Saturday' && dayOfWeek != 'Sunday') {
        weekdays.add(currentDate);
    }
    currentDate = currentDate.addDays(1);
}

System.debug('Found ' + weekdays.size() + ' weekdays between ' + startDate + ' and ' + endDate);

// Create meetings for each weekday
List<Event> allMeetings = new List<Event>();
Integer contactIndex = 0;
Integer templateIndex = 0;

for (Date meetingDate : weekdays) {
    // Cycle through meeting templates
    for (Map<String, Object> template : meetingTemplates) {
        // Get contact and account (cycle through contacts)
        Contact selectedContact = contacts[Math.mod(contactIndex, contacts.size())];
        Account selectedAccount = accountMap.get(selectedContact.AccountId);
        
        // Create the meeting
        Event meeting = new Event();
        meeting.Subject = (String)template.get('subject') + ' - ' + selectedAccount.Name;
        meeting.StartDateTime = DateTime.newInstance(
            meetingDate,
            Time.newInstance((Integer)template.get('startHour'), (Integer)template.get('startMinute'), 0, 0)
        );
        meeting.EndDateTime = meeting.StartDateTime.addMinutes((Integer)template.get('durationMinutes'));
        meeting.Location = (String)template.get('location');
        meeting.Description = (String)template.get('description') + '\n\nAccount: ' + selectedAccount.Name + 
                            '\nContact: ' + selectedContact.Name + 
                            (selectedContact.Title != null ? '\nTitle: ' + selectedContact.Title : '') +
                            (selectedContact.Email != null ? '\nEmail: ' + selectedContact.Email : '') +
                            (selectedContact.Phone != null ? '\nPhone: ' + selectedContact.Phone : '');
        meeting.OwnerId = currentUserId;
        meeting.WhatId = selectedContact.AccountId;
        meeting.WhoId = selectedContact.Id;
        meeting.IsReminderSet = true;
        meeting.ReminderDateTime = meeting.StartDateTime.addMinutes(-15);
        
        allMeetings.add(meeting);
        
        contactIndex++;
    }
    templateIndex++;
}

System.debug('Created ' + allMeetings.size() + ' meetings to insert');

// Insert in batches to avoid governor limits
Integer batchSize = 200;
Integer totalInserted = 0;

for (Integer i = 0; i < allMeetings.size(); i += batchSize) {
    Integer endIndex = Math.min(i + batchSize, allMeetings.size());
    List<Event> batch = new List<Event>();
    for (Integer j = i; j < endIndex; j++) {
        batch.add(allMeetings[j]);
    }
    
    try {
        insert batch;
        totalInserted += batch.size();
        System.debug('Inserted batch: ' + batch.size() + ' meetings (Total: ' + totalInserted + ')');
    } catch (Exception e) {
        System.debug('Error inserting batch starting at index ' + i + ': ' + e.getMessage());
        System.debug('Stack trace: ' + e.getStackTraceString());
    }
}

System.debug('Successfully created ' + totalInserted + ' meetings for weekdays between ' + startDate + ' and ' + endDate);
