// Script to create 6 realistic meetings for today
// Usage: sf org run apex -f scripts/apex/create_today_meetings.apex

// Get current user ID
Id currentUserId = UserInfo.getUserId();

// Get today's date
Date today = Date.today();
DateTime now = DateTime.now();

// Create list of meetings
List<Event> meetingsToInsert = new List<Event>();

// 1. Morning Strategy Session - City of Irvine (9:00 AM - 10:30 AM)
Event meeting1 = new Event();
meeting1.Subject = 'Q1 Budget Review & Strategic Planning Session';
meeting1.StartDateTime = DateTime.newInstance(today, Time.newInstance(9, 0, 0, 0));
meeting1.EndDateTime = meeting1.StartDateTime.addMinutes(90);
meeting1.Location = 'City Hall - Conference Room A';
meeting1.Description = 'Review Q1 budget performance and discuss strategic initiatives for the remainder of the year. Focus on infrastructure projects and community services expansion.';
meeting1.OwnerId = currentUserId;
meeting1.WhatId = '001Hu00003xP25KIAS'; // City of Irvine
meeting1.WhoId = '003Hu00003vSDEaIAO'; // Scott Lawson, CFO
meetingsToInsert.add(meeting1);

// 2. Product Demo - AmaWaterways (11:00 AM - 12:00 PM)
Event meeting2 = new Event();
meeting2.Subject = 'Platform Demo & Integration Discussion';
meeting2.StartDateTime = DateTime.newInstance(today, Time.newInstance(11, 0, 0, 0));
meeting2.EndDateTime = meeting2.StartDateTime.addMinutes(60);
meeting2.Location = 'Virtual - Zoom';
meeting2.Description = 'Demonstrate new platform capabilities and discuss integration options for their booking system. Address questions about API access and data synchronization.';
meeting2.OwnerId = currentUserId;
meeting2.WhatId = '001Hu00003xP0HcIAK'; // AmaWaterways
meeting2.WhoId = '003Hu00003vSD1BIAW'; // Alex Pinelo, Chief Sales Officer
meetingsToInsert.add(meeting2);

// 3. Partnership Discussion - Perplexity (2:00 PM - 3:00 PM)
Event meeting3 = new Event();
meeting3.Subject = 'Partnership Opportunities & Technical Integration';
meeting3.StartDateTime = DateTime.newInstance(today, Time.newInstance(14, 0, 0, 0));
meeting3.EndDateTime = meeting3.StartDateTime.addMinutes(60);
meeting3.Location = 'Perplexity HQ - San Francisco';
meeting3.Description = 'Explore potential partnership opportunities and discuss technical integration possibilities. Review their AI capabilities and how we can leverage them for our platform.';
meeting3.OwnerId = currentUserId;
meeting3.WhatId = '001Hu00003Z6uDrIAJ'; // Perplexity
meeting3.WhoId = '003Hu00003vSCw3IAG'; // Aravind Srinivas, CEO
meetingsToInsert.add(meeting3);

// 4. Sales Strategy Review - Databook (3:30 PM - 4:15 PM)
Event meeting4 = new Event();
meeting4.Subject = 'Q1 Sales Performance Review & Q2 Planning';
meeting4.StartDateTime = DateTime.newInstance(today, Time.newInstance(15, 30, 0, 0));
meeting4.EndDateTime = meeting4.StartDateTime.addMinutes(45);
meeting4.Location = 'Virtual - Microsoft Teams';
meeting4.Description = 'Review Q1 sales metrics, discuss wins and challenges. Plan Q2 strategy focusing on enterprise accounts and expansion opportunities.';
meeting4.OwnerId = currentUserId;
meeting4.WhatId = '001Hu00003xOpKuIAK'; // Databook
meeting4.WhoId = '003Hu00003vSBITIA4'; // Emily Martinez, Chief Revenue Officer
meetingsToInsert.add(meeting4);

// 5. Infrastructure Planning - City of Irvine (4:30 PM - 5:30 PM)
Event meeting5 = new Event();
meeting5.Subject = 'IT Infrastructure Modernization Planning';
meeting5.StartDateTime = DateTime.newInstance(today, Time.newInstance(16, 30, 0, 0));
meeting5.EndDateTime = meeting5.StartDateTime.addMinutes(60);
meeting5.Location = 'City Hall - IT Department';
meeting5.Description = 'Discuss IT infrastructure modernization project. Review current systems, identify upgrade priorities, and plan implementation timeline. Focus on cloud migration and security enhancements.';
meeting5.OwnerId = currentUserId;
meeting5.WhatId = '001Hu00003xP25KIAS'; // City of Irvine
meeting5.WhoId = '003Hu00003vSDERIA4'; // Michael Chen, Chief Information Officer
meetingsToInsert.add(meeting5);

// 6. Contract Negotiation - AmaWaterways (5:30 PM - 6:15 PM)
Event meeting6 = new Event();
meeting6.Subject = 'Contract Renewal & Expansion Discussion';
meeting6.StartDateTime = DateTime.newInstance(today, Time.newInstance(17, 30, 0, 0));
meeting6.EndDateTime = meeting6.StartDateTime.addMinutes(45);
meeting6.Location = 'Virtual - Zoom';
meeting6.Description = 'Discuss contract renewal terms and explore expansion opportunities. Review current usage, discuss additional features needed, and negotiate pricing for increased volume.';
meeting6.OwnerId = currentUserId;
meeting6.WhatId = '001Hu00003xP0HcIAK'; // AmaWaterways
meeting6.WhoId = '003Hu00003vSD19IAG'; // Catherine Powell, CEO
meetingsToInsert.add(meeting6);

// Insert all meetings
try {
    insert meetingsToInsert;
    System.debug('Successfully created ' + meetingsToInsert.size() + ' meetings for today.');
    for (Event evt : meetingsToInsert) {
        System.debug('Created: ' + evt.Subject + ' at ' + evt.StartDateTime.format('h:mm a'));
    }
} catch (Exception e) {
    System.debug('Error creating meetings: ' + e.getMessage());
    System.debug('Stack trace: ' + e.getStackTraceString());
}
