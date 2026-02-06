public with sharing class MeetingPrepIntelligence {
  /**
   * LWC-callable method to get Event with related Account and Contact data
   * @param eventId The Event ID
   * @return Map containing Event data with related Account and Contact info
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getEventWithRelatedData(String eventId) {
    Map<String, Object> result = new Map<String, Object>();

    if (String.isBlank(eventId)) {
      return result;
    }

    List<Event> events = [
      SELECT
        Id,
        Subject,
        StartDateTime,
        EndDateTime,
        Location,
        Description,
        WhatId,
        What.Name,
        WhoId,
        Who.Name
      FROM Event
      WHERE Id = :eventId
      LIMIT 1
    ];

    if (events.isEmpty()) {
      return result;
    }

    Event evt = events[0];
    result.put('Id', evt.Id);
    result.put('Subject', evt.Subject);
    result.put('StartDateTime', evt.StartDateTime);
    result.put('EndDateTime', evt.EndDateTime);
    result.put('Location', evt.Location);
    result.put('Description', evt.Description);
    result.put('WhatId', evt.WhatId);
    result.put('WhoId', evt.WhoId);

    // Add Account data if available
    if (evt.What != null && evt.WhatId != null) {
      String whatIdPrefix = String.valueOf(evt.WhatId).substring(0, 3);
      if (whatIdPrefix == '001') {
        // It's an Account
        Map<String, Object> accountData = new Map<String, Object>();
        accountData.put('Id', evt.WhatId);
        accountData.put('Name', evt.What.Name);
        result.put('Account', accountData);
      }
    }

    // Add Contact data if available
    if (evt.Who != null && evt.WhoId != null) {
      String whoIdPrefix = String.valueOf(evt.WhoId).substring(0, 3);
      if (whoIdPrefix == '003') {
        // It's a Contact
        Map<String, Object> contactData = new Map<String, Object>();
        contactData.put('Id', evt.WhoId);
        contactData.put('Name', evt.Who.Name);
        result.put('Contact', contactData);
      }
    }

    return result;
  }

  /**
   * LWC-callable method to generate meeting prep brief
   * @param eventId The Event ID
   * @param regenerate Whether to force regeneration
   * @return Meeting prep output
   */
  @AuraEnabled
  public static MeetingPrepOutput generateMeetingPrepFromLWC(
    String eventId,
    Boolean regenerate
  ) {
    MeetingPrepInput input = new MeetingPrepInput();
    input.eventId = eventId;
    input.regenerate = regenerate != null ? regenerate : false;

    List<MeetingPrepOutput> results = generateMeetingPrep(
      new List<MeetingPrepInput>{ input }
    );

    return results.isEmpty() ? null : results[0];
  }

  /**
   * Main invocable method to generate meeting prep brief using AI
   * @param inputs List of meeting prep requests
   * @return List of meeting prep results
   */
  @InvocableMethod(
    label='Generate Meeting Prep'
    description='Analyzes upcoming meeting and generates comprehensive prep brief with AI'
  )
  public static List<MeetingPrepOutput> generateMeetingPrep(
    List<MeetingPrepInput> inputs
  ) {
    List<MeetingPrepOutput> results = new List<MeetingPrepOutput>();

    if (inputs == null || inputs.isEmpty()) {
      results.add(createErrorOutput('No event ID provided for meeting prep.'));
      return results;
    }

    MeetingPrepInput input = inputs[0];
    String eventId = input.eventId;
    Boolean regenerate = input.regenerate != null ? input.regenerate : false;

    // Check if prep already exists (unless regenerate flag is true)
    if (!regenerate) {
      List<Meeting_Prep__c> existingPreps = [
        SELECT
          Id,
          Event__c,
          Prep_Brief_HTML__c,
          Attendee_Summary__c,
          Key_Talking_Points__c,
          Recent_Updates__c,
          Questions_To_Ask__c,
          Potential_Objections__c,
          Competitive_Intelligence__c,
          Generated_Date__c
        FROM Meeting_Prep__c
        WHERE Event__c = :eventId
        ORDER BY Generated_Date__c DESC
        LIMIT 1
      ];

      if (!existingPreps.isEmpty()) {
        return new List<MeetingPrepOutput>{
          convertToOutput(existingPreps[0], eventId)
        };
      }
    }

    // Query Event data
    List<Event> events = queryEventData(eventId);
    if (events.isEmpty()) {
      results.add(createErrorOutput('Event not found with ID: ' + eventId));
      return results;
    }

    Event evt = events[0];

    // Query attendees via Event Relations with full Contact details
    List<AttendeeDetail> attendees = getAttendeeDetails(eventId);

    // Query Account data (priority: WhatId if Account, then WhoId contact, then EventRelation contacts)
    String accountId = null;
    if (evt.WhatId != null) {
      String whatIdPrefix = String.valueOf(evt.WhatId).substring(0, 3);
      if (whatIdPrefix == '001') {
        accountId = evt.WhatId;
      } else if (whatIdPrefix == '006' || whatIdPrefix == '003') {
        accountId = queryAccountFromRelatedRecord(evt.WhatId);
      }
    }

    // Try WhoId contact's account
    if (accountId == null && evt.WhoId != null) {
      accountId = queryAccountFromContact(evt.WhoId);
    }

    // Fall back to EventRelation attendees' accounts
    if (accountId == null && !attendees.isEmpty()) {
      accountId = queryAccountFromAttendees(eventId);
    }

    Account acc = accountId != null ? queryAccountData(accountId) : null;

    // Query related opportunities
    List<Opportunity> opportunities = accountId != null
      ? queryRelatedOpportunities(accountId)
      : new List<Opportunity>();

    // Query related cases
    List<Case> cases = accountId != null
      ? queryRelatedCases(accountId)
      : new List<Case>();

    // Query recent activity timeline
    ActivityData activityData = accountId != null
      ? queryRecentActivity(accountId)
      : new ActivityData();

    // Get competitive intelligence via Tavily API
    // Try Account first, then fall back to Lead Company if no Account
    String companyName = null;
    String companyWebsite = null;

    if (acc != null && String.isNotBlank(acc.Name)) {
      companyName = acc.Name;
      companyWebsite = acc.Website;
    } else if (evt.WhoId != null) {
      // Try to get company name from Lead if no Account
      String whoPrefix = String.valueOf(evt.WhoId).substring(0, 3);
      if (whoPrefix == '00Q') {
        List<Lead> leads = [
          SELECT Company, Website
          FROM Lead
          WHERE Id = :evt.WhoId
          LIMIT 1
        ];
        if (!leads.isEmpty() && String.isNotBlank(leads[0].Company)) {
          companyName = leads[0].Company;
          companyWebsite = leads[0].Website;
        }
      }
    }

    String competitiveIntel = String.isNotBlank(companyName)
      ? getCompetitiveIntelligence(companyName, companyWebsite)
      : 'No competitive intelligence available (no account or company linked to meeting).';

    // Build comprehensive AI prompt
    String promptText = buildMeetingPrepPrompt(
      evt,
      attendees,
      acc,
      opportunities,
      cases,
      activityData,
      competitiveIntel
    );

    // Call Einstein AI to generate prep brief
    String prepBriefHTML = callEinsteinAI(promptText);

    // Store the meeting prep
    Meeting_Prep__c prep = new Meeting_Prep__c();
    prep.Event__c = eventId;
    prep.Generated_Date__c = DateTime.now();
    prep.Prep_Brief_HTML__c = prepBriefHTML;
    prep.Attendee_Summary__c = JSON.serialize(buildAttendeeSummary(attendees));
    prep.Competitive_Intelligence__c = competitiveIntel;

    try {
      insert prep;
      prep = [
        SELECT
          Id,
          Event__c,
          Prep_Brief_HTML__c,
          Attendee_Summary__c,
          Key_Talking_Points__c,
          Recent_Updates__c,
          Questions_To_Ask__c,
          Potential_Objections__c,
          Competitive_Intelligence__c,
          Generated_Date__c
        FROM Meeting_Prep__c
        WHERE Id = :prep.Id
        LIMIT 1
      ];
      results.add(convertToOutput(prep, eventId));
    } catch (Exception e) {
      results.add(
        createErrorOutput('Error saving meeting prep: ' + e.getMessage())
      );
    }

    return results;
  }

  /**
   * Query event data with related information
   */
  private static List<Event> queryEventData(String eventId) {
    return [
      SELECT
        Id,
        Subject,
        StartDateTime,
        EndDateTime,
        Location,
        Description,
        WhatId,
        WhoId,
        What.Name,
        Who.Name,
        DurationInMinutes,
        OwnerId,
        Owner.Name
      FROM Event
      WHERE Id = :eventId
      LIMIT 1
    ];
  }

  /**
   * Query event attendees via EventRelation with full Contact details
   */
  private static List<EventRelation> queryEventAttendees(String eventId) {
    try {
      // First get the EventRelations
      List<EventRelation> relations = [
        SELECT Id, RelationId, Relation.Name
        FROM EventRelation
        WHERE EventId = :eventId AND RelationId != NULL
        LIMIT 100
      ];

      if (relations.isEmpty()) {
        return relations;
      }

      // Extract Contact IDs (prefix 003)
      Set<Id> contactIds = new Set<Id>();
      for (EventRelation rel : relations) {
        if (rel.RelationId != null) {
          String relIdStr = String.valueOf(rel.RelationId);
          if (relIdStr.startsWith('003')) {
            contactIds.add(rel.RelationId);
          }
        }
      }

      // Query full Contact details
      Map<Id, Contact> contactMap = new Map<Id, Contact>();
      if (!contactIds.isEmpty()) {
        for (Contact c : [
          SELECT Id, Name, Title, Email, Phone
          FROM Contact
          WHERE Id IN :contactIds
        ]) {
          contactMap.put(c.Id, c);
        }
      }

      // Enrich EventRelation data with Contact details
      for (EventRelation rel : relations) {
        if (contactMap.containsKey(rel.RelationId)) {
          Contact c = contactMap.get(rel.RelationId);
          // Store Contact data in a way we can access it
          // We'll use a wrapper class approach
        }
      }

      return relations;
    } catch (Exception e) {
      System.debug('Error querying EventRelation: ' + e.getMessage());
      return new List<EventRelation>();
    }
  }

  /**
   * Enhanced method to get attendee details with full Contact info
   */
  private static List<AttendeeDetail> getAttendeeDetails(String eventId) {
    List<AttendeeDetail> attendees = new List<AttendeeDetail>();

    try {
      // Get EventRelations
      List<EventRelation> relations = [
        SELECT Id, RelationId, Relation.Name
        FROM EventRelation
        WHERE EventId = :eventId AND RelationId != NULL
        LIMIT 100
      ];

      if (relations.isEmpty()) {
        return attendees;
      }

      // Extract Contact IDs
      Set<Id> contactIds = new Set<Id>();
      for (EventRelation rel : relations) {
        if (rel.RelationId != null) {
          String relIdStr = String.valueOf(rel.RelationId);
          if (relIdStr.startsWith('003')) {
            contactIds.add(rel.RelationId);
          }
        }
      }

      // Query full Contact details
      if (!contactIds.isEmpty()) {
        for (Contact c : [
          SELECT Id, Name, Title, Email, Phone
          FROM Contact
          WHERE Id IN :contactIds
        ]) {
          AttendeeDetail detail = new AttendeeDetail();
          detail.name = c.Name;
          detail.title = c.Title;
          detail.email = c.Email;
          detail.phone = c.Phone;
          attendees.add(detail);
        }
      }

      return attendees;
    } catch (Exception e) {
      System.debug('Error getting attendee details: ' + e.getMessage());
      return attendees;
    }
  }

  /**
   * Wrapper class for attendee details
   */
  private class AttendeeDetail {
    public String name;
    public String title;
    public String email;
    public String phone;
  }

  /**
   * Query account data for context
   */
  private static String queryAccountFromContact(String whoId) {
    String whoPrefix = String.valueOf(whoId).substring(0, 3);
    if (whoPrefix == '003') {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :whoId
        LIMIT 1
      ];
      return !contacts.isEmpty() ? contacts[0].AccountId : null;
    } else if (whoPrefix == '00Q') {
      List<Lead> leads = [
        SELECT ConvertedAccountId, Company
        FROM Lead
        WHERE Id = :whoId
        LIMIT 1
      ];
      if (!leads.isEmpty()) {
        // First try ConvertedAccountId
        if (leads[0].ConvertedAccountId != null) {
          return leads[0].ConvertedAccountId;
        }
        // For unconverted leads, try to find Account by Company name
        if (String.isNotBlank(leads[0].Company)) {
          List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Name = :leads[0].Company
            LIMIT 1
          ];
          if (!accounts.isEmpty()) {
            return accounts[0].Id;
          }
        }
      }
    }
    return null;
  }

  /**
   * Query account from related record (Opportunity, Case, etc.)
   */
  private static String queryAccountFromRelatedRecord(String whatId) {
    String whatPrefix = String.valueOf(whatId).substring(0, 3);
    if (whatPrefix == '006') {
      List<Opportunity> opps = [
        SELECT AccountId
        FROM Opportunity
        WHERE Id = :whatId
        LIMIT 1
      ];
      return !opps.isEmpty() ? opps[0].AccountId : null;
    } else if (whatPrefix == '500') {
      List<Case> cases = [
        SELECT AccountId
        FROM Case
        WHERE Id = :whatId
        LIMIT 1
      ];
      return !cases.isEmpty() ? cases[0].AccountId : null;
    }
    return null;
  }

  /**
   * Query account from EventRelation contacts
   */
  private static String queryAccountFromAttendees(String eventId) {
    try {
      // Get EventRelations
      List<EventRelation> relations = [
        SELECT Id, RelationId
        FROM EventRelation
        WHERE EventId = :eventId AND RelationId != NULL
        LIMIT 1
      ];

      if (relations.isEmpty()) {
        return null;
      }

      // Check if RelationId is a Contact
      String relationId = relations[0].RelationId;
      if (String.valueOf(relationId).startsWith('003')) {
        List<Contact> contacts = [
          SELECT AccountId
          FROM Contact
          WHERE Id = :relationId AND AccountId != NULL
          LIMIT 1
        ];
        if (!contacts.isEmpty() && contacts[0].AccountId != null) {
          return contacts[0].AccountId;
        }
      }
    } catch (Exception e) {
      System.debug('Error querying account from attendees: ' + e.getMessage());
    }
    return null;
  }

  /**
   * Query comprehensive account data
   */
  private static Account queryAccountData(String accountId) {
    List<Account> accounts = [
      SELECT
        Id,
        Name,
        Industry,
        Type,
        AnnualRevenue,
        NumberOfEmployees,
        Website,
        Phone,
        Description
      FROM Account
      WHERE Id = :accountId
      LIMIT 1
    ];
    return !accounts.isEmpty() ? accounts[0] : null;
  }

  /**
   * Query related opportunities
   */
  private static List<Opportunity> queryRelatedOpportunities(String accountId) {
    return [
      SELECT
        Id,
        Name,
        StageName,
        Amount,
        CloseDate,
        Probability,
        NextStep,
        Type,
        Description,
        IsClosed,
        IsWon
      FROM Opportunity
      WHERE AccountId = :accountId
      ORDER BY IsClosed ASC, CloseDate ASC
      LIMIT 20
    ];
  }

  /**
   * Query related cases
   */
  private static List<Case> queryRelatedCases(String accountId) {
    return [
      SELECT
        Id,
        CaseNumber,
        Subject,
        Status,
        Priority,
        CreatedDate,
        ClosedDate,
        Description,
        IsClosed
      FROM Case
      WHERE AccountId = :accountId
      ORDER BY IsClosed ASC, CreatedDate DESC
      LIMIT 20
    ];
  }

  /**
   * Query recent activity timeline
   */
  private static ActivityData queryRecentActivity(String accountId) {
    ActivityData data = new ActivityData();
    DateTime cutoffDate = DateTime.now().addDays(-120);

    // Query emails with ActivityId and TextBody
    try {
      data.emails = [
        SELECT
          Subject,
          TextBody,
          FromAddress,
          ToAddress,
          MessageDate,
          Status,
          ActivityId
        FROM EmailMessage
        WHERE RelatedToId = :accountId AND MessageDate >= :cutoffDate
        ORDER BY MessageDate DESC
        LIMIT 50
      ];

      // Get contact names from activities linked to emails
      Set<Id> activityIds = new Set<Id>();
      for (EmailMessage em : data.emails) {
        if (em.ActivityId != null) {
          activityIds.add(em.ActivityId);
        }
      }

      // Query Tasks linked to emails to get contact names
      if (!activityIds.isEmpty()) {
        List<Task> emailTasks = [
          SELECT Id, WhoId, Who.Name, Who.FirstName
          FROM Task
          WHERE Id IN :activityIds AND WhoId != NULL
        ];
        for (Task t : emailTasks) {
          String contactName = '';
          if (t.Who.FirstName != null) {
            contactName = t.Who.FirstName;
          } else if (t.Who.Name != null) {
            String[] nameParts = t.Who.Name.split(' ');
            contactName = nameParts[0];
          }
          if (String.isNotBlank(contactName)) {
            data.activityToContactName.put(t.Id, contactName);
          }
        }
      }
    } catch (Exception e) {
      data.emails = new List<EmailMessage>();
    }

    // Query tasks with contact information
    data.tasks = [
      SELECT
        Subject,
        Status,
        ActivityDate,
        Priority,
        Description,
        CreatedDate,
        WhoId,
        Who.Name
      FROM Task
      WHERE
        (WhatId = :accountId
        OR AccountId = :accountId)
        AND CreatedDate >= :cutoffDate
      ORDER BY CreatedDate DESC
      LIMIT 30
    ];

    // Query recent events (past meetings) with contact information
    data.events = [
      SELECT
        Subject,
        StartDateTime,
        EndDateTime,
        Description,
        Location,
        WhoId,
        Who.Name
      FROM Event
      WHERE WhatId = :accountId AND StartDateTime >= :cutoffDate
      ORDER BY StartDateTime DESC
      LIMIT 20
    ];

    return data;
  }

  /**
   * Get competitive intelligence via Tavily API + AI Analysis
   */
  private static String getCompetitiveIntelligence(
    String accountName,
    String website
  ) {
    try {
      // Get API key from Custom Metadata
      Tavily_API_Config__mdt config = Tavily_API_Config__mdt.getInstance(
        'Default'
      );
      if (config == null || String.isBlank(config.API_Key__c)) {
        return '<p>Tavily API key not configured. Competitive intelligence unavailable.</p>';
      }

      // Build search query for comprehensive company research
      String query =
        accountName +
        ' company news challenges growth hiring competitors industry trends';

      // Build Tavily API request payload
      Map<String, Object> payload = new Map<String, Object>{
        'query' => query,
        'search_depth' => 'advanced',
        'include_answer' => true,
        'max_results' => 10
      };

      // Make HTTP callout
      HttpRequest req = new HttpRequest();
      req.setEndpoint('https://api.tavily.com/search');
      req.setMethod('POST');
      req.setHeader('Content-Type', 'application/json');
      req.setHeader('Authorization', 'Bearer ' + config.API_Key__c);
      req.setBody(JSON.serialize(payload));
      req.setTimeout(30000);

      Http http = new Http();
      HttpResponse res = http.send(req);

      if (res.getStatusCode() == 200) {
        Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        String answer = (String) responseData.get('answer');
        List<Object> results = (List<Object>) responseData.get('results');

        // Build context for AI analysis
        String tavilyContext = buildTavilyContext(accountName, answer, results);

        // Use AI to generate strategic competitive intelligence
        try {
          return generateStrategicIntelligence(accountName, tavilyContext);
        } catch (Exception aiEx) {
          System.debug('Error in generateStrategicIntelligence: ' + aiEx.getTypeName() + ' - ' + aiEx.getMessage());
          System.debug('Stack trace: ' + aiEx.getStackTraceString());
          // Return raw research data if AI fails
          return '<p>Error generating strategic analysis: ' +
            aiEx.getMessage() +
            '. Using raw research data.</p><pre>' +
            tavilyContext +
            '</pre>';
        }
      } else {
        return '<p>Tavily API returned error ' +
          res.getStatusCode() +
          '. Competitive intelligence unavailable.</p>';
      }
    } catch (Exception e) {
      System.debug('Tavily API error: ' + e.getMessage());
      return '<p>Error fetching competitive intelligence: ' +
        e.getMessage() +
        '</p>';
    }
  }

  /**
   * Build context from Tavily results for AI analysis
   */
  private static String buildTavilyContext(
    String accountName,
    String answer,
    List<Object> results
  ) {
    List<String> contextParts = new List<String>();

    contextParts.add('# COMPANY RESEARCH DATA FOR: ' + accountName + '\n\n');

    if (String.isNotBlank(answer)) {
      contextParts.add('## SUMMARY\n' + answer + '\n\n');
    }

    if (results != null && !results.isEmpty()) {
      contextParts.add('## RECENT NEWS & ARTICLES\n\n');
      contextParts.add(
        'IMPORTANT: When referencing information from these articles in your response, include the source URL as a hyperlink using HTML format: <a href="[URL]" target="_blank">[Article Title]</a>\n\n'
      );
      Integer count = 0;
      for (Object resultObj : results) {
        Map<String, Object> result = (Map<String, Object>) resultObj;
        String title = (String) result.get('title');
        String content = (String) result.get('content');
        String url = (String) result.get('url');

        if (String.isNotBlank(title)) {
          count++;
          contextParts.add('ARTICLE ' + count + ':\n');
          contextParts.add('Title: ' + title + '\n');
          if (String.isNotBlank(url)) {
            contextParts.add('URL: ' + url + '\n');
          }
          if (String.isNotBlank(content)) {
            contextParts.add('Content: ' + content + '\n');
          }
          contextParts.add('\n');
        }
      }
    }

    return String.join(contextParts, '');
  }

  /**
   * Generate strategic competitive intelligence using AI
   */
  private static String generateStrategicIntelligence(
    String accountName,
    String tavilyContext
  ) {
    try {
      List<String> promptParts = new List<String>();

      promptParts.add(
        'You are an expert Sales Intelligence Analyst preparing competitive intelligence for a sales meeting. Your goal is to create a compelling, actionable brief that helps sales reps understand the prospect deeply and engage meaningfully.\n\n'
      );
      promptParts.add(
        'Based on the company research data below, generate strategic competitive intelligence that will help a sales rep prepare for a meeting. Make this intelligence engaging, insightful, and immediately actionable.\n\n'
      );
      promptParts.add(tavilyContext + '\n\n');

      promptParts.add('## YOUR TASK\n\n');
      promptParts.add(
        'Analyze the research data and generate a comprehensive competitive intelligence brief with the following sections. Write in a compelling, engaging style that makes the information come alive:\n\n'
      );

      promptParts.add(
        '1. **Company Overview** - Brief, engaging summary of what the company does and their market position. Use specific details and paint a clear picture.\n'
      );
      promptParts.add(
        '2. **Business Model & Revenue** - Answer: How does this company make money? What are their revenue streams? What is their pricing model? Include specific details when available.\n'
      );
      promptParts.add(
        '3. **Customer Base** - Answer: Who are their customers? What industries/segments do they serve? What is their ideal customer profile? Be specific about customer segments.\n'
      );
      promptParts.add(
        '4. **Ownership & Investors** - Answer: Who owns or has invested in the business? Recent funding rounds? Key investors? Valuation? Include specific names and amounts when available.\n'
      );
      promptParts.add(
        '5. **Current Challenges & Pain Points** - Based on news articles, what challenges or struggles are they facing? What problems might they need help solving? Be specific and cite evidence from the research.\n'
      );
      promptParts.add(
        '6. **Growth Indicators** - Are they hiring? Expanding? Investing in new initiatives? What does this tell us about their priorities? Use specific examples from the research.\n'
      );
      promptParts.add(
        '7. **Recent Developments** - Key news, announcements, or changes in the last 6 months. Highlight the most significant developments that matter for sales conversations.\n'
      );
      promptParts.add(
        '8. **Sales Opportunity Analysis** - Where might we be able to add value? What solutions would resonate based on their current situation? Be specific and actionable.\n'
      );
      promptParts.add(
        '9. **Competitive Positioning** - How should we position our solution? What angles would be most compelling? Provide strategic guidance.\n'
      );
      promptParts.add(
        '10. **Key Talking Points** - 3-5 specific talking points to reference in the meeting. Format these as a bulleted list using <ul> and <li> tags. Make each point concise, impactful, and conversation-ready.\n\n'
      );

      promptParts.add('## CRITICAL REQUIREMENTS\n\n');
      promptParts.add(
        '**SOURCES & LINKS:** When referencing information from the research data, include hyperlinks to the source articles. Use the URLs provided in the research data (they appear as "Source: [URL]"). Format links as: <a href="[URL]" target="_blank">[Article Title or descriptive text]</a>. Include sources for key facts, especially in Recent Developments, Growth Indicators, and Current Challenges sections.\n\n'
      );
      promptParts.add(
        '**FORMATTING:** Use bullet points (<ul> and <li>) liberally throughout the document, especially for:\n'
      );
      promptParts.add(
        '- Key Talking Points section (MANDATORY - must be bulleted)\n'
      );
      promptParts.add('- Lists of challenges, opportunities, or key facts\n');
      promptParts.add('- Multiple revenue streams or customer segments\n');
      promptParts.add('- Recent developments or growth indicators\n\n');
      promptParts.add(
        '**WRITING STYLE:** Write in a compelling, engaging manner. Use:\n'
      );
      promptParts.add('- Specific details and concrete examples\n');
      promptParts.add('- Strong, action-oriented language\n');
      promptParts.add('- Emphasis on what matters for sales conversations\n');
      promptParts.add(
        '- <strong> tags to highlight key company names, metrics, amounts, and important facts\n'
      );
      promptParts.add('- Varied sentence structure to keep it engaging\n\n');

      promptParts.add('## OUTPUT FORMAT\n\n');
      promptParts.add(
        '**CRITICAL:** Return ONLY clean HTML. NO markdown, NO code blocks (```), NO backticks, NO <br/> between sections.\n\n'
      );
      promptParts.add('**HTML STRUCTURE:**\n');
      promptParts.add('- <h3> for section headers (CSS handles margins)\n');
      promptParts.add('- <p> for paragraphs (CSS handles spacing)\n');
      promptParts.add('- <ul> and <li> for bullet lists (USE FREQUENTLY)\n');
      promptParts.add(
        '- <strong> for emphasis on company names, metrics, amounts, key facts\n'
      );
      promptParts.add(
        '- <a href="URL" target="_blank">Link Text</a> for source links\n'
      );
      promptParts.add(
        '- DO NOT use <br/> tags between sections - use <p> tags only\n'
      );
      promptParts.add(
        '- Keep concise but compelling - sales-focused insights with engaging writing\n\n'
      );
      promptParts.add('**DO NOT:**\n');
      promptParts.add('- Start with ```html or any code block markers\n');
      promptParts.add('- End with ``` or any markdown syntax\n');
      promptParts.add('- Use markdown formatting (* or ** or #)\n');
      promptParts.add('- Include any text before the first <h3> tag\n');
      promptParts.add('- Add <br/> tags between major sections\n');
      promptParts.add(
        '- Forget to include source links for key information\n\n'
      );

      String promptText = String.join(promptParts, '');

      // Call Einstein AI - use OpenAI GPT4 Omni (proven to work in this org)
      String modelName = 'sfdc_ai__DefaultOpenAIGPT4Omni';

      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = modelName;

      aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
      request.body = requestBody;
      requestBody.prompt = promptText;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(
        request
      );

      if (response != null && response.Code200 != null && response.Code200.generation != null) {
        String generatedText = response.Code200.generation.generatedText;
        if (String.isNotBlank(generatedText)) {
          // Clean up any markdown artifacts from the response
          return cleanAIResponse(generatedText);
        } else {
          System.debug('AI returned empty response');
          throw new CalloutException('AI returned empty response');
        }
      } else {
        System.debug('No AI response received. Response: ' + (response != null ? JSON.serialize(response) : 'null'));
        throw new CalloutException('No response from AI service. Response was null or did not contain generation.');
      }
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      System.debug('Einstein AI ModelsAPI error: ' + e.getMessage());
      
      // If Gemini model not available, try OpenAI fallback
      String errorMsg = e.getMessage();
      if (errorMsg != null && (errorMsg.contains('not found') || errorMsg.contains('model') || errorMsg.contains('404') || errorMsg.contains('unavailable'))) {
        System.debug('Gemini model not available, trying OpenAI fallback...');
        try {
          return generateStrategicIntelligenceFallback(accountName, tavilyContext);
        } catch (Exception fallbackEx) {
          System.debug('Fallback also failed: ' + fallbackEx.getMessage());
          return '<p>Error: AI models not available. Please ensure Einstein Generative AI is enabled. Using raw research data.</p><pre>' +
            tavilyContext +
            '</pre>';
        }
      } else {
        // Other error - return with details
        return '<p>Error generating strategic analysis: ' +
          errorMsg +
          '. Using raw research data.</p><pre>' +
          tavilyContext +
          '</pre>';
      }
    } catch (Exception e) {
      System.debug('AI analysis error: ' + e.getTypeName() + ' - ' + e.getMessage());
      System.debug('Stack trace: ' + e.getStackTraceString());
      
      // Try fallback for any exception
      try {
        System.debug('Attempting fallback model...');
        return generateStrategicIntelligenceFallback(accountName, tavilyContext);
      } catch (Exception fallbackEx) {
        System.debug('Fallback also failed: ' + fallbackEx.getTypeName() + ' - ' + fallbackEx.getMessage());
        System.debug('Fallback stack trace: ' + fallbackEx.getStackTraceString());
        // Return a user-friendly error message
        String errorMsg = e.getMessage();
        if (String.isBlank(errorMsg) || errorMsg == 'Script-thrown exception') {
          errorMsg = 'AI service unavailable. Please ensure Einstein Generative AI is enabled in Setup.';
        }
        return '<p>Error generating strategic analysis: ' +
          errorMsg +
          '. Using raw research data.</p><pre>' +
          tavilyContext +
          '</pre>';
      }
    }
  }

  /**
   * Fallback method using OpenAI GPT4 Omni model
   */
  private static String generateStrategicIntelligenceFallback(
    String accountName,
    String tavilyContext
  ) {
    try {
      // Use the same prompt but with a different model
      List<String> promptParts = new List<String>();
      promptParts.add(
        'You are an expert Sales Intelligence Analyst preparing competitive intelligence for a sales meeting. Based on the company research data below, generate strategic competitive intelligence.\n\n'
      );
      promptParts.add(tavilyContext + '\n\n');
      promptParts.add(
        'Generate a comprehensive competitive intelligence brief with sections: Company Overview, Business Model, Customer Base, Current Challenges, Growth Indicators, Recent Developments, Sales Opportunity Analysis, and Key Talking Points. Format as clean HTML with <h3> for headers, <p> for paragraphs, and <ul>/<li> for lists. Include source links where available.\n\n'
      );

      String promptText = String.join(promptParts, '');

      String modelName = 'sfdc_ai__DefaultOpenAIGPT4Omni';

      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = modelName;

      aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
      request.body = requestBody;
      requestBody.prompt = promptText;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(
        request
      );

      if (response.Code200 != null && response.Code200.generation != null) {
        String generatedText = response.Code200.generation.generatedText;
        return cleanAIResponse(generatedText);
      } else {
        throw new CalloutException('No response from fallback model');
      }
    } catch (Exception e) {
      System.debug('Fallback model error: ' + e.getMessage());
      throw e;
    }
  }

  /**
   * Clean AI response by removing markdown code blocks and fixing unclosed tags
   */
  private static String cleanAIResponse(String response) {
    if (String.isBlank(response)) {
      return '';
    }

    String cleaned = response.trim();

    // Remove markdown code block markers
    if (cleaned.startsWith('```html')) {
      cleaned = cleaned.substring(7);
    }
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.substring(3);
    }
    if (cleaned.endsWith('```')) {
      cleaned = cleaned.substring(0, cleaned.length() - 3);
    }

    cleaned = cleaned.trim();

    // Convert markdown bold syntax to HTML
    cleaned = convertMarkdownToHtml(cleaned);

    // Fix unclosed HTML tags (common AI mistakes)
    cleaned = fixUnclosedTags(cleaned);

    return cleaned;
  }

  /**
   * Convert markdown formatting to HTML
   */
  private static String convertMarkdownToHtml(String text) {
    if (String.isBlank(text)) {
      return '';
    }

    // Replace **text** with <strong>text</strong>
    // Use a simple pattern replacement approach
    String result = text;

    // Pattern: **word** or **multiple words**
    while (result.contains('**')) {
      Integer firstPos = result.indexOf('**');
      if (firstPos >= 0) {
        Integer secondPos = result.indexOf('**', firstPos + 2);
        if (secondPos >= 0) {
          String beforeFirst = result.substring(0, firstPos);
          String boldText = result.substring(firstPos + 2, secondPos);
          String afterSecond = result.substring(secondPos + 2);
          result =
            beforeFirst +
            '<strong>' +
            boldText +
            '</strong>' +
            afterSecond;
        } else {
          // No closing **, just remove the opening
          result =
            result.substring(0, firstPos) + result.substring(firstPos + 2);
          break;
        }
      } else {
        break;
      }
    }

    return result;
  }

  /**
   * Fix unclosed HTML tags that can break rendering
   */
  private static String fixUnclosedTags(String html) {
    if (String.isBlank(html)) {
      return '';
    }

    // Count opening and closing tags for critical elements
    Map<String, Integer> tagCounts = new Map<String, Integer>{
      'strong' => 0,
      'b' => 0,
      'p' => 0,
      'ul' => 0,
      'ol' => 0,
      'li' => 0
    };

    // Simple tag counting (not perfect but handles most cases)
    for (String tagName : tagCounts.keySet()) {
      Integer openCount =
        html.countMatches('<' + tagName + '>') +
        html.countMatches('<' + tagName + ' ');
      Integer closeCount = html.countMatches('</' + tagName + '>');
      tagCounts.put(tagName, openCount - closeCount);
    }

    // Append missing closing tags at the end
    List<String> closingTags = new List<String>();

    // Close inline tags first (strong, b)
    if (tagCounts.get('strong') > 0) {
      for (Integer i = 0; i < tagCounts.get('strong'); i++) {
        closingTags.add('</strong>');
      }
    }
    if (tagCounts.get('b') > 0) {
      for (Integer i = 0; i < tagCounts.get('b'); i++) {
        closingTags.add('</b>');
      }
    }

    // Close list items and lists
    if (tagCounts.get('li') > 0) {
      for (Integer i = 0; i < tagCounts.get('li'); i++) {
        closingTags.add('</li>');
      }
    }
    if (tagCounts.get('ul') > 0) {
      for (Integer i = 0; i < tagCounts.get('ul'); i++) {
        closingTags.add('</ul>');
      }
    }
    if (tagCounts.get('ol') > 0) {
      for (Integer i = 0; i < tagCounts.get('ol'); i++) {
        closingTags.add('</ol>');
      }
    }
    if (tagCounts.get('p') > 0) {
      for (Integer i = 0; i < tagCounts.get('p'); i++) {
        closingTags.add('</p>');
      }
    }

    return html + String.join(closingTags, '');
  }

  /**
   * Build attendee summary
   */
  private static List<Map<String, String>> buildAttendeeSummary(
    List<AttendeeDetail> attendees
  ) {
    List<Map<String, String>> summary = new List<Map<String, String>>();
    for (AttendeeDetail attendee : attendees) {
      Map<String, String> attendeeMap = new Map<String, String>();
      attendeeMap.put('name', attendee.name != null ? attendee.name : '');
      attendeeMap.put('title', attendee.title != null ? attendee.title : '');
      attendeeMap.put('email', attendee.email != null ? attendee.email : '');
      attendeeMap.put('phone', attendee.phone != null ? attendee.phone : '');
      attendeeMap.put('account', '');
      summary.add(attendeeMap);
    }
    return summary;
  }

  /**
   * Build comprehensive meeting prep prompt for AI
   */
  private static String buildMeetingPrepPrompt(
    Event evt,
    List<AttendeeDetail> attendees,
    Account acc,
    List<Opportunity> opportunities,
    List<Case> cases,
    ActivityData activityData,
    String competitiveIntel
  ) {
    List<String> promptParts = new List<String>();

    promptParts.add(
      'You are an expert Sales & Service Executive preparing for an important meeting. Generate a comprehensive, detailed meeting prep brief (5-10 minute read) that will enable the meeting owner to walk in fully prepared.\n\n'
    );

    promptParts.add(
      '**CONTEXT:** Today is ' +
        Date.today().format() +
        '. The meeting is scheduled for ' +
        (evt.StartDateTime != null
          ? evt.StartDateTime.format()
          : 'Unknown time') +
        '.\n\n'
    );

    // Meeting Overview
    promptParts.add('## MEETING DETAILS\n\n');
    promptParts.add('- **Subject:** ' + evt.Subject + '\n');
    promptParts.add(
      '- **Date/Time:** ' +
        (evt.StartDateTime != null
          ? evt.StartDateTime.format()
          : 'Not specified') +
        '\n'
    );
    promptParts.add(
      '- **Duration:** ' +
        (evt.DurationInMinutes != null
          ? evt.DurationInMinutes + ' minutes'
          : 'Not specified') +
        '\n'
    );
    promptParts.add(
      '- **Location:** ' +
        (String.isNotBlank(evt.Location) ? evt.Location : 'Not specified') +
        '\n'
    );
    if (String.isNotBlank(evt.Description)) {
      promptParts.add('- **Description:** ' + evt.Description + '\n');
    }
    promptParts.add('\n');

    // Attendees
    promptParts.add('## ATTENDEES\n\n');
    if (!attendees.isEmpty()) {
      for (AttendeeDetail attendee : attendees) {
        promptParts.add('- **' + attendee.name + '**\n');
        if (String.isNotBlank(attendee.title)) {
          promptParts.add('  - Title: ' + attendee.title + '\n');
        } else {
          promptParts.add('  - Title: Not specified\n');
        }
        if (String.isNotBlank(attendee.email)) {
          promptParts.add('  - Email: ' + attendee.email + '\n');
        }
      }
      promptParts.add('\n');
    } else {
      promptParts.add('No attendees specified via Event Relations.\n\n');
    }

    // Account Context
    if (acc != null) {
      promptParts.add('## ACCOUNT CONTEXT: ' + acc.Name + '\n\n');
      promptParts.add(
        '- **Industry:** ' +
          (String.isNotBlank(acc.Industry) ? acc.Industry : 'Not specified') +
          '\n'
      );
      promptParts.add(
        '- **Type:** ' +
          (String.isNotBlank(acc.Type) ? acc.Type : 'Not specified') +
          '\n'
      );
      promptParts.add(
        '- **Annual Revenue:** ' +
          (acc.AnnualRevenue != null
            ? '$' + String.valueOf(acc.AnnualRevenue.format())
            : 'Not specified') +
          '\n'
      );
      promptParts.add(
        '- **Employees:** ' +
          (acc.NumberOfEmployees != null
            ? String.valueOf(acc.NumberOfEmployees)
            : 'Not specified') +
          '\n'
      );
      promptParts.add(
        '- **Website:** ' +
          (String.isNotBlank(acc.Website) ? acc.Website : 'Not specified') +
          '\n'
      );
      promptParts.add(
        '- **Support Contract:** Not specified\n'
      );
      if (String.isNotBlank(acc.Description)) {
        promptParts.add('- **Description:** ' + acc.Description + '\n');
      }
      promptParts.add('\n');
    } else {
      promptParts.add(
        '## ACCOUNT CONTEXT\n\nNo account linked to this meeting.\n\n'
      );
    }

    // Opportunities
    if (!opportunities.isEmpty()) {
      promptParts.add(
        '## RELATED OPPORTUNITIES (' + opportunities.size() + ')\n\n'
      );
      Integer openCount = 0;
      Integer closedWonCount = 0;
      Decimal totalPipeline = 0;

      for (Opportunity opp : opportunities) {
        if (!opp.IsClosed) {
          openCount++;
          if (opp.Amount != null) {
            totalPipeline += opp.Amount;
          }
          promptParts.add('### ' + opp.Name + '\n');
          promptParts.add('- **Stage:** ' + opp.StageName + '\n');
          promptParts.add(
            '- **Amount:** ' +
              (opp.Amount != null
                ? '$' + String.valueOf(opp.Amount.format())
                : 'Not specified') +
              '\n'
          );
          promptParts.add(
            '- **Close Date:** ' +
              (opp.CloseDate != null
                ? String.valueOf(opp.CloseDate)
                : 'Not specified') +
              '\n'
          );
          promptParts.add(
            '- **Probability:** ' +
              (opp.Probability != null
                ? String.valueOf(opp.Probability) + '%'
                : 'N/A') +
              '\n'
          );
          if (String.isNotBlank(opp.NextStep)) {
            promptParts.add('- **Next Step:** ' + opp.NextStep + '\n');
          }
          promptParts.add('\n');
        } else if (opp.IsWon) {
          closedWonCount++;
        }
      }

      promptParts.add(
        '**Summary:** ' +
          openCount +
          ' open opportunity(ies) totaling ' +
          (totalPipeline > 0
            ? '$' + String.valueOf(totalPipeline.format())
            : '$0') +
          ' in pipeline. ' +
          closedWonCount +
          ' closed won.\n\n'
      );
    } else {
      promptParts.add(
        '## RELATED OPPORTUNITIES\n\nNo opportunities found.\n\n'
      );
    }

    // Cases
    if (!cases.isEmpty()) {
      promptParts.add('## RELATED CASES (' + cases.size() + ')\n\n');
      Integer openCases = 0;
      Integer highPriorityCases = 0;

      for (Case c : cases) {
        if (!c.IsClosed) {
          openCases++;
          if (c.Priority == 'High' || c.Priority == 'Critical') {
            highPriorityCases++;
          }
          promptParts.add('### Case ' + c.CaseNumber + ': ' + c.Subject + '\n');
          promptParts.add('- **Status:** ' + c.Status + '\n');
          promptParts.add('- **Priority:** ' + c.Priority + '\n');
          promptParts.add(
            '- **Opened:** ' +
              (c.CreatedDate != null ? c.CreatedDate.format() : 'Unknown') +
              '\n'
          );
          if (String.isNotBlank(c.Description)) {
            String descText = c.Description.length() > 150
              ? c.Description.substring(0, 150) + '...'
              : c.Description;
            promptParts.add('- **Description:** ' + descText + '\n');
          }
          promptParts.add('\n');
        }
      }

      promptParts.add(
        '**Summary:** ' +
          openCases +
          ' open case(s), ' +
          highPriorityCases +
          ' high/critical priority.\n\n'
      );
    } else {
      promptParts.add('## RELATED CASES\n\nNo cases found.\n\n');
    }

    // Recent Activity - Enhanced with contact names and content excerpts
    promptParts.add('## RECENT ACTIVITY (Last 120 Days)\n\n');

    if (!activityData.emails.isEmpty()) {
      promptParts.add(
        '### Recent Emails (' + activityData.emails.size() + ')\n'
      );
      Integer count = 0;
      for (EmailMessage email : activityData.emails) {
        if (count >= 15)
          break;

        String contactName = '';
        if (
          email.ActivityId != null &&
          activityData.activityToContactName.containsKey(email.ActivityId)
        ) {
          contactName = activityData.activityToContactName.get(
            email.ActivityId
          );
        }

        String emailExcerpt = '';
        if (String.isNotBlank(email.TextBody)) {
          String truncatedBody = email.TextBody.length() > 300
            ? email.TextBody.substring(0, 300) + '...'
            : email.TextBody;
          emailExcerpt = truncatedBody.replace('\n', ' ').trim();
        }

        promptParts.add(
          '- **' +
            (String.isNotBlank(contactName) ? contactName : 'Contact') +
            '** - ' +
            (email.MessageDate != null
              ? email.MessageDate.format()
              : 'Unknown date') +
            ': ' +
            (String.isNotBlank(email.Subject) ? email.Subject : 'No subject')
        );
        if (String.isNotBlank(emailExcerpt)) {
          promptParts.add('\n  Excerpt: ' + emailExcerpt);
        }
        promptParts.add('\n');
        count++;
      }
      promptParts.add('\n');
    } else {
      promptParts.add('### Recent Emails\nNo recent emails.\n\n');
    }

    if (!activityData.tasks.isEmpty()) {
      promptParts.add('### Recent Tasks (' + activityData.tasks.size() + ')\n');
      Integer count = 0;
      for (Task t : activityData.tasks) {
        if (count >= 15)
          break;

        String contactName = '';
        if (t.Who != null && String.isNotBlank(t.Who.Name)) {
          String[] nameParts = t.Who.Name.split(' ');
          contactName = nameParts[0];
        }

        promptParts.add(
          '- **' +
            (String.isNotBlank(contactName) ? contactName : 'Contact') +
            '** - ' +
            (String.isNotBlank(t.Subject) ? t.Subject : 'No subject') +
            ' - ' +
            t.Status
        );
        if (String.isNotBlank(t.Description)) {
          String taskDesc = t.Description.length() > 200
            ? t.Description.substring(0, 200) + '...'
            : t.Description;
          promptParts.add('\n  Description: ' + taskDesc);
        }
        promptParts.add('\n');
        count++;
      }
      promptParts.add('\n');
    } else {
      promptParts.add('### Recent Tasks\nNo recent tasks.\n\n');
    }

    if (!activityData.events.isEmpty()) {
      promptParts.add(
        '### Recent Meetings (' + activityData.events.size() + ')\n'
      );
      Integer count = 0;
      for (Event e : activityData.events) {
        if (count >= 15)
          break;

        String contactName = '';
        if (e.Who != null && String.isNotBlank(e.Who.Name)) {
          String[] nameParts = e.Who.Name.split(' ');
          contactName = nameParts[0];
        }

        promptParts.add(
          '- **' +
            (String.isNotBlank(contactName) ? contactName : 'Contact') +
            '** - ' +
            (e.StartDateTime != null ? e.StartDateTime.format() : 'Unknown') +
            ': ' +
            (String.isNotBlank(e.Subject) ? e.Subject : 'No subject')
        );
        if (String.isNotBlank(e.Description)) {
          String eventDesc = e.Description.length() > 200
            ? e.Description.substring(0, 200) + '...'
            : e.Description;
          promptParts.add('\n  Description: ' + eventDesc);
        }
        promptParts.add('\n');
        count++;
      }
      promptParts.add('\n');
    } else {
      promptParts.add('### Recent Meetings\nNo recent meetings.\n\n');
    }

    // Competitive Intelligence
    promptParts.add('## COMPETITIVE INTELLIGENCE\n\n');
    promptParts.add(competitiveIntel + '\n\n');

    // Instructions for AI
    promptParts.add('## YOUR TASK\n\n');
    promptParts.add(
      'Generate a CONSISTENT, FOCUSED, and SCANNABLE meeting prep brief following this EXACT structure:\n\n'
    );

    promptParts.add('## REQUIRED OUTPUT STRUCTURE\n\n');
    promptParts.add('**CRITICAL CONSISTENCY RULES:**\n');
    promptParts.add('- Use EXACTLY the same HTML structure every time\n');
    promptParts.add(
      '- Keep each section concise and focused (2-3 sentences or 3-5 bullet points max)\n'
    );
    promptParts.add('- Use bullet points for lists, NOT long paragraphs\n');
    promptParts.add('- Bold key data points: names, dates, amounts, metrics\n');
    promptParts.add(
      '- Avoid redundancy - don\'t repeat information across sections\n\n'
    );

    promptParts.add('**EXACT TEMPLATE TO FOLLOW:**\n\n');

    promptParts.add('<h1>1. Meeting Overview</h1>\n');
    promptParts.add(
      '<p>Write ONE focused paragraph (2-3 sentences) covering: meeting purpose, key objectives, and why this meeting matters. Include <b>date</b> and <b>account name</b> in bold.</p>\n\n'
    );

    promptParts.add('<h1>2. Attendee Profiles</h1>\n');
    promptParts.add(
      '<p>For each attendee listed in the ATTENDEES section, provide their name, title, influence level, and detailed engagement history. Use actual data from the ATTENDEES section and recent activity data above.</p>\n'
    );
    promptParts.add('<p>For EACH attendee, include:</p>\n');
    promptParts.add('<ul>\n');
    promptParts.add(
      '<li><b>[Attendee name]</b> - [Title]<br/>Influence: [Decision Maker/Influencer/Stakeholder based on title]<br/>Engagement: [Specific engagement details from activity data - mention emails, calls, meetings]<br/><b>What they said:</b> [Quotes or summaries from their past emails/communications - use actual excerpts from RECENT ACTIVITY section]<br/><b>Key concerns:</b> [Topics or issues they\'ve raised based on activity data]<br/><b>What others said:</b> [What other contacts in the account have mentioned about them or related topics]</li>\n'
    );
    promptParts.add('</ul>\n');
    promptParts.add(
      '<p>If no attendees listed in ATTENDEES section, write: "No specific attendees identified. Prepare for general account discussion."</p>\n\n'
    );

    promptParts.add('<h1>3. Account Relationship Status</h1>\n');
    promptParts.add(
      '<p>Provide detailed, data-driven relationship status based on actual activity data from the last 120 days:</p>\n'
    );
    promptParts.add('<ul>\n');
    promptParts.add(
      '<li><b>Pipeline:</b> [X] open opportunities totaling <b>$[amount]</b></li>\n'
    );
    promptParts.add('<li><b>Recent Wins:</b> [X] closed won deals</li>\n');
    promptParts.add(
      '<li><b>Open Issues:</b> [X] open cases ([priorities if any])</li>\n'
    );
    promptParts.add(
      '<li><b>Activity Level (Last 120 Days):</b> [X] emails ([X] sent, [X] received), [X] calls, [X] meetings. Break down by contact name when available from RECENT ACTIVITY section.</li>\n'
    );
    promptParts.add(
      '<li><b>Key Contact Engagement:</b> For each contact mentioned in RECENT ACTIVITY, summarize their communication frequency and recent topics discussed. Include specific quotes or summaries from their emails.</li>\n'
    );
    promptParts.add(
      '<li><b>Recent Communication Highlights:</b> Summarize 2-3 key points from recent emails/tasks/events, attributing them to specific contacts when possible. Use actual excerpts from RECENT ACTIVITY section.</li>\n'
    );
    promptParts.add(
      '<li><b>Relationship Health:</b> [Healthy/Stable/At Risk - 1-2 sentences explaining why based on activity patterns, engagement trends, and communication sentiment]</li>\n'
    );
    promptParts.add('</ul>\n\n');

    promptParts.add('<h1>4. Key Talking Points</h1>\n');
    promptParts.add('<p>Prioritized topics to discuss (LIMIT TO 5):</p>\n');
    promptParts.add('<ol>\n');
    promptParts.add('<li>[Talking point - 1 sentence, bold key terms]</li>\n');
    promptParts.add('<li>[Talking point - 1 sentence, bold key terms]</li>\n');
    promptParts.add('<li>[Talking point - 1 sentence, bold key terms]</li>\n');
    promptParts.add('<li>[Talking point - 1 sentence, bold key terms]</li>\n');
    promptParts.add('<li>[Talking point - 1 sentence, bold key terms]</li>\n');
    promptParts.add('</ol>\n\n');

    promptParts.add('<h1>5. Strategic Questions</h1>\n');
    promptParts.add('<p>Ask these discovery questions (LIMIT TO 5-7):</p>\n');
    promptParts.add('<ul>\n');
    promptParts.add('<li>[Question focused on their challenges/needs]</li>\n');
    promptParts.add('<li>[Question about their priorities/timeline]</li>\n');
    promptParts.add(
      '<li>[Question about decision process/stakeholders]</li>\n'
    );
    promptParts.add('<li>[Question about budget/investment]</li>\n');
    promptParts.add('<li>[Question about success criteria]</li>\n');
    promptParts.add('</ul>\n\n');

    promptParts.add('<h1>6. Potential Objections & Responses</h1>\n');
    promptParts.add(
      '<p>Anticipate and prepare for these objections (LIMIT TO 3-4):</p>\n'
    );
    promptParts.add('<ul>\n');
    promptParts.add(
      '<li><b>Objection:</b> "[Likely objection]"<br/><b>Response:</b> [How to handle - 1 sentence]</li>\n'
    );
    promptParts.add('</ul>\n\n');

    promptParts.add('<h1>7. Desired Meeting Outcomes</h1>\n');
    promptParts.add('<ul>\n');
    promptParts.add(
      '<li>[Specific outcome - e.g., "Schedule follow-up demo"]</li>\n'
    );
    promptParts.add(
      '<li>[Specific outcome - e.g., "Get commitment on timeline"]</li>\n'
    );
    promptParts.add(
      '<li>[Specific outcome - e.g., "Identify additional stakeholders"]</li>\n'
    );
    promptParts.add('</ul>\n\n');

    promptParts.add('## STRICT FORMATTING RULES\n\n');
    promptParts.add(
      '1. Return ONLY the HTML output - no markdown, no code blocks, no backticks\n'
    );
    promptParts.add('2. Use <h1> for section numbers (1., 2., 3., etc.)\n');
    promptParts.add(
      '3. Use <b> tags to bold: names, amounts, dates, metrics, key terms\n'
    );
    promptParts.add(
      '4. Use <ul><li> for bullet lists, <ol><li> for numbered lists\n'
    );
    promptParts.add('5. Keep lists SHORT - no more than items specified\n');
    promptParts.add('6. Each bullet/list item should be 1-2 sentences MAX\n');
    promptParts.add('7. Use <br/> for line breaks within list items\n');
    promptParts.add(
      '8. ALWAYS include a blank line (empty paragraph <p></p> or double newline) between each section heading (<h1>) to ensure proper spacing\n'
    );
    promptParts.add(
      '9. Focus on ACTIONABLE insights, not generic statements\n\n'
    );

    promptParts.add('## CONTENT QUALITY RULES\n\n');
    promptParts.add(
      '- Base ALL analysis on the data provided - don\'t speculate or invent information\n'
    );
    promptParts.add(
      '- If data is missing for a section, acknowledge it briefly and move on\n'
    );
    promptParts.add('- Prioritize recent information over old data\n');
    promptParts.add(
      '- Connect competitive intelligence insights to talking points\n'
    );
    promptParts.add('- Make questions SPECIFIC to this account, not generic\n');
    promptParts.add(
      '- Objections should be based on industry, company size, or visible challenges\n'
    );
    promptParts.add(
      '- Every recommendation should be ACTIONABLE with clear next steps\n\n'
    );

    return String.join(promptParts, '');
  }

  /**
   * Call Einstein AI to generate meeting prep brief
   */
  private static String callEinsteinAI(String promptText) {
    try {
      String modelName = 'sfdc_ai__DefaultOpenAIGPT4OmniMini';

      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = modelName;

      aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
      request.body = requestBody;
      requestBody.prompt = promptText;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(
        request
      );

      if (response.Code200 != null && response.Code200.generation != null) {
        String generatedText = response.Code200.generation.generatedText;
        // Clean up any markdown artifacts
        return cleanAIResponse(generatedText);
      } else {
        return '<p>No response received from Einstein AI. Please verify Einstein Generative AI is enabled in your org.</p>';
      }
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      System.debug('Einstein AI error: ' + e.getMessage());
      return '<p>Error generating meeting prep: ' +
        e.getMessage() +
        '</p><p>Please ensure Einstein AI Models are enabled in Setup → Einstein Setup.</p>';
    } catch (Exception e) {
      System.debug('Unexpected error: ' + e.getMessage());
      return '<p>Unexpected error during AI analysis: ' +
        e.getMessage() +
        '</p>';
    }
  }

  /**
   * Convert Meeting_Prep__c to MeetingPrepOutput
   */
  private static MeetingPrepOutput convertToOutput(
    Meeting_Prep__c prep,
    String eventId
  ) {
    MeetingPrepOutput output = new MeetingPrepOutput();
    output.success = true;
    output.message = 'Meeting prep generated successfully.';
    output.meetingPrepId = prep.Id;
    output.eventId = prep.Event__c;

    // Query Event details separately since Event__c is a text field
    List<Event> events = queryEventData(eventId);
    if (!events.isEmpty()) {
      Event evt = events[0];
      output.eventSubject = evt.Subject;
      output.eventDateTime = evt.StartDateTime != null
        ? evt.StartDateTime.format()
        : '';
      output.eventLocation = evt.Location;
    }

    output.prepBriefHTML = prep.Prep_Brief_HTML__c;
    output.attendeeSummary = prep.Attendee_Summary__c;
    output.keyTalkingPoints = prep.Key_Talking_Points__c;
    output.recentUpdates = prep.Recent_Updates__c;
    output.questionsToAsk = prep.Questions_To_Ask__c;
    output.potentialObjections = prep.Potential_Objections__c;
    output.competitiveIntelligence = prep.Competitive_Intelligence__c;
    return output;
  }

  /**
   * Create error output
   */
  private static MeetingPrepOutput createErrorOutput(String message) {
    MeetingPrepOutput output = new MeetingPrepOutput();
    output.success = false;
    output.message = message;
    output.prepBriefHTML = '<p><b>Error:</b> ' + message + '</p>';
    return output;
  }

  /**
   * Wrapper class for activity data
   */
  private class ActivityData {
    public List<EmailMessage> emails;
    public List<Task> tasks;
    public List<Event> events;
    public Map<Id, String> activityToContactName; // ActivityId -> Contact Name
    public Map<Id, List<EmailMessage>> contactEmailsMap; // ContactId -> List of emails

    public ActivityData() {
      this.emails = new List<EmailMessage>();
      this.tasks = new List<Task>();
      this.events = new List<Event>();
      this.activityToContactName = new Map<Id, String>();
      this.contactEmailsMap = new Map<Id, List<EmailMessage>>();
    }
  }
}
