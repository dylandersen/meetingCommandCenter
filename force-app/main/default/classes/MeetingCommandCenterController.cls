/**
 * Controller for Meeting Command Center LWC
 * Provides methods to fetch today's events and process meeting recaps
 * using the Salesforce Models API for AI summarization
 */
public with sharing class MeetingCommandCenterController {
  /**
   * Fetches events for a specific date for the current user
   * @param selectedDate The date to fetch events for (ISO string format YYYY-MM-DD). If null, uses today.
   * @return List of Event records with related data
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getTodaysEvents(String selectedDate) {
    // Parse the selected date or use today
    Date targetDate;
    if (String.isNotBlank(selectedDate)) {
      try {
        targetDate = Date.valueOf(selectedDate);
      } catch (Exception e) {
        // If parsing fails, fall back to today
        targetDate = Date.today();
      }
    } else {
      targetDate = Date.today();
    }

    // Get start and end of the target date in user's timezone
    DateTime startOfDay = DateTime.newInstance(
      targetDate,
      Time.newInstance(0, 0, 0, 0)
    );
    DateTime endOfDay = DateTime.newInstance(
      targetDate,
      Time.newInstance(23, 59, 59, 999)
    );

    // Query events
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
      WHERE
        OwnerId = :UserInfo.getUserId()
        AND StartDateTime >= :startOfDay
        AND StartDateTime <= :endOfDay
      ORDER BY StartDateTime ASC
    ];

    // Query Meeting_Recap__c records for these events
    Set<Id> eventIds = new Set<Id>();
    for (Event evt : events) {
      eventIds.add(evt.Id);
    }

    Map<Id, Meeting_Recap__c> recapMap = new Map<Id, Meeting_Recap__c>();
    if (!eventIds.isEmpty()) {
      List<Meeting_Recap__c> recaps = [
        SELECT Id, Event__c, Recap_Completed__c
        FROM Meeting_Recap__c
        WHERE Event__c IN :eventIds
      ];
      for (Meeting_Recap__c recap : recaps) {
        recapMap.put(recap.Event__c, recap);
      }
    }

    // Convert events to Maps and add recap status
    List<Map<String, Object>> eventMaps = new List<Map<String, Object>>();
    for (Event evt : events) {
      Meeting_Recap__c recap = recapMap.get(evt.Id);
      // Convert Event to Map
      Map<String, Object> eventMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(evt));
      // Add Recap_Completed__c field
      eventMap.put(
        'Recap_Completed__c',
        recap != null && recap.Recap_Completed__c == true
      );
      eventMaps.add(eventMap);
    }

    return eventMaps;
  }

  /**
   * Gets the Meeting_Recap__c ID for a given Event ID
   * @param eventId The Event ID to look up
   * @return The Meeting_Recap__c ID or null if not found
   */
  @AuraEnabled(cacheable=true)
  public static String getMeetingRecapId(String eventId) {
    if (String.isBlank(eventId)) {
      return null;
    }

    List<Meeting_Recap__c> recaps = [
      SELECT Id
      FROM Meeting_Recap__c
      WHERE Event__c = :eventId
      LIMIT 1
    ];

    if (!recaps.isEmpty()) {
      return recaps[0].Id;
    }

    return null;
  }

  /**
   * Gets the Meeting_Prep__c ID for a given Event ID
   * @param eventId The Event ID to look up
   * @return The Meeting_Prep__c ID or null if not found
   */
  @AuraEnabled(cacheable=true)
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

    if (!preps.isEmpty()) {
      return preps[0].Id;
    }

    return null;
  }

  /**
   * Submits a meeting recap for AI processing
   * Calls Models API to summarize and update the Event record
   * @param eventId The Event ID to update
   * @param recapText The user's recap text
   * @return Success message or error
   */
  @AuraEnabled
  public static String submitMeetingRecap(String eventId, String recapText) {
    // Returns the Meeting Recap ID for navigation
    if (String.isBlank(eventId)) {
      throw new AuraHandledException('Event ID is required');
    }
    if (String.isBlank(recapText)) {
      throw new AuraHandledException('Recap text is required');
    }

    try {
      // Query the event for context
      List<Event> events = [
        SELECT
          Id,
          Subject,
          StartDateTime,
          EndDateTime,
          Location,
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

      // Build the AI prompt
      String prompt = buildSummarizationPrompt(evt, recapText);

      // Call Models API
      String aiResponse = callModelsAPI(prompt);

      // Parse the AI response and create/update Meeting_Recap__c record
      String recapId = updateMeetingRecapWithSummary(
        evt,
        aiResponse,
        recapText
      );

      return recapId;
    } catch (AuraHandledException e) {
      // Re-throw AuraHandledException as-is to preserve the original error message
      throw e;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in submitMeetingRecap: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
      System.debug('Exception type: ' + e.getTypeName());
      // Include full error details in the message
      String errorMsg = 'Failed to save recap: ' + e.getMessage();
      if (e.getStackTraceString() != null) {
        errorMsg +=
          ' | Stack: ' +
          e.getStackTraceString()
            .substring(0, Math.min(500, e.getStackTraceString().length()));
      }
      throw new AuraHandledException(errorMsg);
    }
  }

  /**
   * Builds the AI prompt for summarizing the meeting recap
   */
  private static String buildSummarizationPrompt(Event evt, String recapText) {
    // Get the current user's name
    String userName = UserInfo.getFirstName();
    if (String.isBlank(userName)) {
      userName = UserInfo.getName();
      // Extract first name if full name is provided
      if (userName.contains(' ')) {
        userName = userName.substring(0, userName.indexOf(' '));
      }
    }

    String prompt = 'You are an expert meeting summarizer for sales professionals. ';
    prompt += 'Given the following meeting recap notes from the user, generate a structured summary.\n\n';

    prompt += '## Meeting Details\n';
    prompt +=
      '- Subject: ' +
      (evt.Subject != null ? evt.Subject : 'No subject') +
      '\n';
    prompt +=
      '- Date/Time: ' +
      evt.StartDateTime.format('MMMM d, yyyy h:mm a') +
      '\n';
    if (evt.Location != null) {
      prompt += '- Location: ' + evt.Location + '\n';
    }
    if (evt.What != null) {
      prompt += '- Related Account: ' + evt.What.Name + '\n';
    }
    if (evt.Who != null) {
      prompt += '- Primary Contact: ' + evt.Who.Name + '\n';
    }
    prompt += '- Meeting Participant: ' + userName + '\n';

    prompt += '\n## User\'s Meeting Notes\n';
    prompt += recapText + '\n\n';

    prompt += '## Instructions\n';
    prompt += 'Generate a comprehensive, detailed response in the following JSON format:\n';
    prompt += '{\n';
    prompt +=
      '  "summary": "A thorough executive summary (3-5 paragraphs) covering the main discussion points, decisions made, and overall meeting outcomes. Use HTML formatting with <p> tags for paragraphs, and add a blank line (<br><br>) between each paragraph for better readability. Be detailed and capture all important aspects of the meeting. CRITICAL: When referring to the meeting participant, use their first name "' +
      userName +
      '" instead of "The user" or "the user". For example: "' +
      userName +
      ' discussed..." or "' +
      userName +
      ' agreed to..." instead of "The user discussed...".",\n';
    prompt +=
      '  "keyOutcomes": "A comprehensive list of ALL key outcomes, decisions, insights, and accomplishments from the meeting. Format as HTML <ul><li> list with detailed bullet points. Include all significant outcomes, not just a few. Each outcome should be well-explained with context. CRITICAL: When referring to the meeting participant, use their first name "' +
      userName +
      '" instead of "The user" or "the user". For example: "' +
      userName +
      ' committed to..." or "' +
      userName +
      ' decided..." instead of "The user committed...".",\n';
    prompt += '  "nextSteps": "A complete list of ALL actionable next steps, follow-up items, and commitments made during the meeting. Format as HTML <ul><li> list. Include owners, deadlines, and context where mentioned. Be thorough and capture all action items, even if they seem minor. CRITICAL: Write next steps in second person using "You should" or "You need to" - NEVER use "The user should" or third person. For example: "You should prepare for the scheduled follow-up meeting with Bobby on Friday, January 30" instead of "The user should prepare...". Write directly to the person reading the recap. IMPORTANT: Include a diverse mix of action types - include both tasks (like "prepare proposal", "send email", "research", "draft document") AND events (like "schedule meeting", "follow-up call"). Avoid generating multiple similar recommendations about the same meeting or event. Aim for variety to make the recommendations more useful."\n';
    prompt += '}\n\n';
    prompt += 'IMPORTANT: These fields support up to 131,000 characters each. Be comprehensive and detailed. Include all relevant information from the meeting notes, not just a brief summary. Use proper HTML formatting (<p>, <ul>, <li>) for rich text display. Do not limit yourself to just a few items - capture everything that matters.';

    return prompt;
  }

  /**
   * Calls the Salesforce Models API to generate the summary
   */
  private static String callModelsAPI(String prompt) {
    try {
      aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
      request.modelName = 'sfdc_ai__DefaultOpenAIGPT4Omni';

      aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
      request.body = requestBody;
      requestBody.prompt = prompt;

      aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
      aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(
        request
      );

      if (response.Code200 != null && response.Code200.generation != null) {
        return response.Code200.generation.generatedText;
      } else {
        throw new AuraHandledException(
          'No response from AI. Please verify Einstein Generative AI is enabled.'
        );
      }
    } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
      System.debug(
        LoggingLevel.ERROR,
        'Models API Response Exception: ' + e.getMessage()
      );
      throw new AuraHandledException('AI service error: ' + e.getMessage());
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Models API Error: ' + e.getMessage());
      throw new AuraHandledException(
        'AI service unavailable: ' + e.getMessage()
      );
    }
  }

  /**
   * Parses the AI response and creates/updates the Meeting_Recap__c record
   * @return The ID of the created/updated Meeting_Recap__c record
   */
  private static String updateMeetingRecapWithSummary(
    Event evt,
    String aiResponse,
    String originalRecap
  ) {
    try {
      // Validate Event ID is present
      if (evt == null || evt.Id == null) {
        throw new AuraHandledException('Invalid Event: Event ID is required');
      }

      String summary = '';
      String keyOutcomes = '';
      String nextSteps = '';

      try {
        // Try to parse JSON response
        // First, extract JSON from response (it might have extra text)
        String jsonContent = extractJsonFromResponse(aiResponse);

        if (String.isNotBlank(jsonContent)) {
          Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
            jsonContent
          );

          summary = (String) responseMap.get('summary');
          keyOutcomes = (String) responseMap.get('keyOutcomes');
          nextSteps = (String) responseMap.get('nextSteps');
        }
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'Failed to parse AI response as JSON: ' + e.getMessage()
        );
        // Fallback: use the entire response as the summary
        summary = aiResponse;
      }

      // Ensure we have at least some content
      if (String.isBlank(summary)) {
        if (String.isNotBlank(originalRecap)) {
          // Use full original recap text - fields support 131K characters
          summary = 'Meeting recap: ' + originalRecap;
        } else {
          summary = 'Meeting recap';
        }
      }

      // No truncation needed - Rich Text Area fields support 131K characters

      // Check if recap already exists for this event
      List<Meeting_Recap__c> existingRecaps = [
        SELECT Id, Event__c
        FROM Meeting_Recap__c
        WHERE Event__c = :evt.Id
        LIMIT 1
      ];

      String recapId;
      if (!existingRecaps.isEmpty()) {
        // Update existing recap
        Meeting_Recap__c recapToUpdate = existingRecaps[0];
        recapToUpdate.Original_Recap_Text__c = originalRecap;
        recapToUpdate.AI_Meeting_Summary__c = summary;
        recapToUpdate.AI_Key_Outcomes__c = String.isNotBlank(keyOutcomes)
          ? keyOutcomes
          : null;
        recapToUpdate.AI_Next_Steps__c = String.isNotBlank(nextSteps)
          ? nextSteps
          : null;
        recapToUpdate.Recap_Completed__c = true;
        update recapToUpdate;
        recapId = recapToUpdate.Id;
      } else {
        // Create new recap - use Event ID directly from the Event object
        Meeting_Recap__c recapToInsert = new Meeting_Recap__c();
        recapToInsert.Event__c = evt.Id;
        recapToInsert.Original_Recap_Text__c = originalRecap;
        recapToInsert.AI_Meeting_Summary__c = summary;
        recapToInsert.AI_Key_Outcomes__c = String.isNotBlank(keyOutcomes)
          ? keyOutcomes
          : null;
        recapToInsert.AI_Next_Steps__c = String.isNotBlank(nextSteps)
          ? nextSteps
          : null;
        recapToInsert.Recap_Completed__c = true;

        System.debug('Inserting Meeting_Recap__c with Event__c: ' + evt.Id);
        System.debug('Event ID type: ' + evt.Id.getSObjectType());

        // Use regular insert instead of Database.insert to get clearer errors
        insert recapToInsert;
        recapId = recapToInsert.Id;
      }

      return recapId;
    } catch (AuraHandledException e) {
      // Re-throw AuraHandledException as-is
      throw e;
    } catch (DmlException e) {
      // Handle DML exceptions specifically
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
      // Catch any other unexpected exceptions
      System.debug(
        'Unexpected error in updateMeetingRecapWithSummary: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
      throw new AuraHandledException('Failed to save recap: ' + e.getMessage());
    }
  }

  /**
   * Extracts JSON content from AI response that might include extra text
   */
  private static String extractJsonFromResponse(String response) {
    if (String.isBlank(response)) {
      return null;
    }

    // Find the first { and last }
    Integer startIndex = response.indexOf('{');
    Integer endIndex = response.lastIndexOf('}');

    if (startIndex >= 0 && endIndex > startIndex) {
      return response.substring(startIndex, endIndex + 1);
    }

    return null;
  }

  /**
   * Retrieves the Deepgram API key from Custom Metadata
   * @return The Deepgram API key or null if not configured
   */
  @AuraEnabled(cacheable=true)
  public static String getDeepgramApiKey() {
    try {
      Deepgram_API_Config__mdt config = Deepgram_API_Config__mdt.getInstance(
        'Default'
      );
      if (config == null || String.isBlank(config.API_Key__c)) {
        System.debug('Deepgram API key not configured in Custom Metadata');
        return null;
      }
      return config.API_Key__c;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error retrieving Deepgram API key: ' + e.getMessage()
      );
      return null;
    }
  }

  /**
   * Transcribes audio chunk using Deepgram REST API
   * @param audioBase64 Base64-encoded audio data
   * @param existingText Existing transcription text to append to
   * @return Transcribed text
   */
  @AuraEnabled
  public static String transcribeAudioChunk(
    String audioBase64,
    String existingText
  ) {
    if (String.isBlank(audioBase64)) {
      return '';
    }

    try {
      // Get API key from Custom Metadata
      Deepgram_API_Config__mdt config;
      try {
        config = Deepgram_API_Config__mdt.getInstance('Default');
      } catch (Exception configEx) {
        System.debug('Error getting config: ' + configEx.getMessage());
        throw new AuraHandledException('Deepgram API configuration not found. Please configure the API key in Custom Metadata.');
      }
      
      if (config == null || String.isBlank(config.API_Key__c)) {
        throw new AuraHandledException('Deepgram API key is not configured. Please set the API key in Custom Metadata Type: Deepgram_API_Config__mdt');
      }

      // Decode base64 audio
      Blob audioBlob;
      try {
        audioBlob = EncodingUtil.base64Decode(audioBase64);
        if (audioBlob == null || audioBlob.size() == 0) {
          throw new AuraHandledException('Invalid audio data: empty or corrupted');
        }
      } catch (Exception decodeEx) {
        System.debug('Error decoding audio: ' + decodeEx.getMessage());
        throw new AuraHandledException('Failed to decode audio data. Please try recording again.');
      }

      // Build Deepgram API request
      HttpRequest req = new HttpRequest();
      req.setEndpoint(
        'https://api.deepgram.com/v1/listen?model=nova-2&language=en-US&punctuate=true&smart_format=true'
      );
      req.setMethod('POST');
      req.setHeader('Authorization', 'Token ' + config.API_Key__c);
      req.setHeader('Content-Type', 'audio/webm');
      req.setBodyAsBlob(audioBlob);
      req.setTimeout(30000); // 30 second timeout

      Http http = new Http();
      HttpResponse res;
      try {
        res = http.send(req);
      } catch (Exception httpEx) {
        System.debug('HTTP callout error: ' + httpEx.getMessage());
        throw new AuraHandledException('Failed to connect to Deepgram API. Please check your network connection and Remote Site Settings.');
      }

      if (res.getStatusCode() == 200) {
        // Parse Deepgram response
        Map<String, Object> responseData;
        try {
          responseData = (Map<String, Object>) JSON.deserializeUntyped(
            res.getBody()
          );
        } catch (Exception parseEx) {
          System.debug('Error parsing response: ' + parseEx.getMessage());
          System.debug('Response body: ' + res.getBody());
          throw new AuraHandledException('Failed to parse transcription response from Deepgram API.');
        }

        // Extract transcript from response
        String transcript = extractTranscript(responseData);

        if (String.isNotBlank(transcript)) {
          return transcript;
        }
        return '';
      } else {
        String errorBody = res.getBody();
        System.debug(
          'Deepgram API error: ' + res.getStatusCode() + ' - ' + res.getStatus()
        );
        System.debug('Response body: ' + errorBody);
        
        String errorMessage = 'Deepgram API returned error code ' + res.getStatusCode();
        if (res.getStatusCode() == 401) {
          errorMessage = 'Deepgram API authentication failed. Please check your API key.';
        } else if (res.getStatusCode() == 400) {
          errorMessage = 'Invalid request to Deepgram API. The audio format may not be supported.';
        } else if (res.getStatusCode() >= 500) {
          errorMessage = 'Deepgram API server error. Please try again later.';
        }
        throw new AuraHandledException(errorMessage);
      }
    } catch (AuraHandledException e) {
      // Re-throw AuraHandledException as-is
      throw e;
    } catch (Exception e) {
      String errorMsg = e.getMessage();
      if (String.isBlank(errorMsg)) {
        errorMsg = e.getTypeName();
      }
      if (String.isBlank(errorMsg)) {
        errorMsg = 'Unknown error occurred during transcription';
      }
      System.debug(
        LoggingLevel.ERROR,
        'Error in transcribeAudioChunk: ' + errorMsg
      );
      System.debug('Exception type: ' + e.getTypeName());
      System.debug('Stack trace: ' + e.getStackTraceString());
      throw new AuraHandledException('Transcription error: ' + errorMsg);
    }
  }

  /**
   * Extracts transcript text from Deepgram API response
   */
  private static String extractTranscript(Map<String, Object> responseData) {
    try {
      Map<String, Object> results = (Map<String, Object>) responseData.get(
        'results'
      );
      if (results == null) {
        return '';
      }

      List<Object> channels = (List<Object>) results.get('channels');
      if (channels == null || channels.isEmpty()) {
        return '';
      }

      Map<String, Object> channel = (Map<String, Object>) channels[0];
      List<Object> alternatives = (List<Object>) channel.get('alternatives');
      if (alternatives == null || alternatives.isEmpty()) {
        return '';
      }

      Map<String, Object> alternative = (Map<String, Object>) alternatives[0];
      String transcript = (String) alternative.get('transcript');

      return transcript != null ? transcript.trim() : '';
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Error extracting transcript: ' + e.getMessage()
      );
      return '';
    }
  }

  /**
   * Gets account prep information for meeting recap
   * Returns account details, contact details, and AI-generated summary of recent activity
   * @param eventId The Event ID to get prep info for
   * @return Map containing accountName, accountId, contactName, contactId, and accountSummary
   */
  @AuraEnabled
  public static Map<String, Object> getAccountPrepInfo(String eventId) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      // Query the event with account and contact info
      List<Event> events = [
        SELECT Id, WhatId, What.Name, WhoId, Who.Name
        FROM Event
        WHERE Id = :eventId
        LIMIT 1
      ];

      if (events.isEmpty()) {
        return result;
      }

      Event evt = events[0];

      // Set account info
      if (evt.WhatId != null) {
        result.put('accountId', evt.WhatId);
        result.put('accountName', evt.What != null ? evt.What.Name : null);

        // Generate AI summary if we have an account
        if (evt.WhatId != null) {
          String summary = generateAccountSummary(evt.WhatId);
          result.put('accountSummary', summary);
        }
      }

      // Set contact info
      if (evt.WhoId != null) {
        result.put('contactId', evt.WhoId);
        result.put('contactName', evt.Who != null ? evt.Who.Name : null);
      }

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error in getAccountPrepInfo: ' + e.getMessage()
      );
      return result;
    }
  }

  /**
   * Generates an AI summary of recent account activity
   */
  private static String generateAccountSummary(String accountId) {
    try {
      // Query recent account activity (last 30 days)
      Date startDate = Date.today().addDays(-30);

      // Get recent cases
      List<Case> recentCases = [
        SELECT Id, Subject, Status, Priority, CreatedDate
        FROM Case
        WHERE AccountId = :accountId AND CreatedDate >= :startDate
        ORDER BY CreatedDate DESC
        LIMIT 10
      ];

      // Get recent opportunities
      List<Opportunity> recentOpps = [
        SELECT Id, Name, StageName, Amount, CloseDate
        FROM Opportunity
        WHERE AccountId = :accountId AND CreatedDate >= :startDate
        ORDER BY CreatedDate DESC
        LIMIT 10
      ];

      // Get recent tasks
      List<Task> recentTasks = [
        SELECT Id, Subject, Status, CreatedDate
        FROM Task
        WHERE WhatId = :accountId AND CreatedDate >= :startDate
        ORDER BY CreatedDate DESC
        LIMIT 10
      ];

      // Build context for AI
      String context = buildAccountContext(
        recentCases,
        recentOpps,
        recentTasks
      );

      // Build AI prompt
      String prompt = 'You are a sales assistant helping prepare for a meeting. ';
      prompt += 'Based on the following recent account activity, provide a brief 2-3 sentence summary ';
      prompt += 'of what\'s been happening with this account recently. Focus on key updates, ';
      prompt += 'open items, and anything relevant for an upcoming meeting.\n\n';
      prompt += context;
      prompt += '\n\nProvide a concise, actionable summary in plain text (no markdown or formatting).';

      // Call Models API
      return callModelsAPI(prompt);
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error generating account summary: ' + e.getMessage()
      );
      return null;
    }
  }

  /**
   * Builds context string from account activities
   */
  private static String buildAccountContext(
    List<Case> cases,
    List<Opportunity> opps,
    List<Task> tasks
  ) {
    String context = 'Recent Account Activity:\n\n';

    if (!cases.isEmpty()) {
      context += 'Recent Cases:\n';
      for (Case c : cases) {
        context +=
          '- ' +
          c.Subject +
          ' (' +
          c.Status +
          ', Priority: ' +
          c.Priority +
          ')\n';
      }
      context += '\n';
    }

    if (!opps.isEmpty()) {
      context += 'Recent Opportunities:\n';
      for (Opportunity o : opps) {
        String amount = o.Amount != null
          ? '$' + String.valueOf(o.Amount)
          : 'Amount not specified';
        context += '- ' + o.Name + ' (' + o.StageName + ', ' + amount + ')\n';
      }
      context += '\n';
    }

    if (!tasks.isEmpty()) {
      context += 'Recent Tasks:\n';
      for (Task t : tasks) {
        context +=
          '- ' +
          (t.Subject != null ? t.Subject : 'Task') +
          ' (' +
          t.Status +
          ')\n';
      }
      context += '\n';
    }

    if (cases.isEmpty() && opps.isEmpty() && tasks.isEmpty()) {
      context += 'No recent activity in the last 30 days.\n';
    }

    return context;
  }

  /**
   * Generates AI-powered subject and description for a new event
   * Uses context from account, contact, opportunity, or case to create professional, customer-facing content
   * @param accountId Optional Account ID for context
   * @param contactId Optional Contact ID for context
   * @param opportunityId Optional Opportunity ID for context
   * @param caseId Optional Case ID for context
   * @return Map containing 'subject' and 'description' fields
   */
  @AuraEnabled
  public static Map<String, String> generateEventContent(
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    Map<String, String> result = new Map<String, String>();

    try {
      // Build context for AI
      String context = buildEventContext(
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // If no specific context provided, try to gather general context
      if (String.isBlank(context)) {
        context = buildGeneralContext();
      }

      // Build AI prompt
      String prompt = buildEventGenerationPrompt(
        context,
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // Call Models API
      String aiResponse = callModelsAPI(prompt);

      // Parse AI response
      Map<String, String> parsedResponse = parseEventContentResponse(
        aiResponse
      );

      result.put('subject', parsedResponse.get('subject'));
      result.put('description', parsedResponse.get('description'));

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error generating event content: ' + e.getMessage()
      );
      // Return fallback values
      result.put('subject', 'Follow-up Meeting');
      result.put(
        'description',
        'Meeting to discuss next steps and follow-up items.'
      );
      return result;
    }
  }

  /**
   * Builds general context from user's recent activities when no specific IDs are provided
   */
  private static String buildGeneralContext() {
    String context = '';
    Id currentUserId = UserInfo.getUserId();
    Date startDate = Date.today().addDays(-7);

    try {
      // Get recent opportunities
      List<Opportunity> recentOpps = [
        SELECT Name, StageName, Amount, Account.Name
        FROM Opportunity
        WHERE OwnerId = :currentUserId AND CreatedDate >= :startDate
        ORDER BY CreatedDate DESC
        LIMIT 3
      ];

      // Get recent cases
      List<Case> recentCases = [
        SELECT Subject, Status, Priority, Account.Name
        FROM Case
        WHERE OwnerId = :currentUserId AND CreatedDate >= :startDate
        ORDER BY CreatedDate DESC
        LIMIT 3
      ];

      if (!recentOpps.isEmpty() || !recentCases.isEmpty()) {
        context += 'Recent Activity Context:\n';

        if (!recentOpps.isEmpty()) {
          context += '\nRecent Opportunities:\n';
          for (Opportunity o : recentOpps) {
            String amount = o.Amount != null
              ? '$' + String.valueOf(o.Amount)
              : 'Amount not specified';
            context +=
              '- ' +
              o.Name +
              ' with ' +
              (o.Account != null ? o.Account.Name : 'Account') +
              ' (' +
              o.StageName +
              ', ' +
              amount +
              ')\n';
          }
        }

        if (!recentCases.isEmpty()) {
          context += '\nRecent Cases:\n';
          for (Case c : recentCases) {
            context +=
              '- ' +
              c.Subject +
              ' for ' +
              (c.Account != null ? c.Account.Name : 'Account') +
              ' (' +
              c.Status +
              ', Priority: ' +
              c.Priority +
              ')\n';
          }
        }
      }
    } catch (Exception e) {
      System.debug('Error building general context: ' + e.getMessage());
    }

    return context;
  }

  /**
   * Builds context string from related records
   */
  private static String buildEventContext(
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    String context = '';

    // Get account information
    if (String.isNotBlank(accountId)) {
      try {
        List<Account> accounts = [
          SELECT Id, Name, Industry, Type, AnnualRevenue
          FROM Account
          WHERE Id = :accountId
          LIMIT 1
        ];
        if (!accounts.isEmpty()) {
          Account acc = accounts[0];
          context += 'Account: ' + acc.Name + '\n';
          if (String.isNotBlank(acc.Industry)) {
            context += 'Industry: ' + acc.Industry + '\n';
          }
          if (String.isNotBlank(acc.Type)) {
            context += 'Account Type: ' + acc.Type + '\n';
          }

          // Get recent account activity
          Date startDate = Date.today().addDays(-30);
          List<Case> recentCases = [
            SELECT Subject, Status, Priority
            FROM Case
            WHERE AccountId = :accountId AND CreatedDate >= :startDate
            ORDER BY CreatedDate DESC
            LIMIT 5
          ];
          List<Opportunity> recentOpps = [
            SELECT Name, StageName, Amount, CloseDate
            FROM Opportunity
            WHERE AccountId = :accountId AND CreatedDate >= :startDate
            ORDER BY CreatedDate DESC
            LIMIT 5
          ];

          if (!recentCases.isEmpty()) {
            context += '\nRecent Cases:\n';
            for (Case c : recentCases) {
              context +=
                '- ' +
                c.Subject +
                ' (' +
                c.Status +
                ', Priority: ' +
                c.Priority +
                ')\n';
            }
          }

          if (!recentOpps.isEmpty()) {
            context += '\nRecent Opportunities:\n';
            for (Opportunity o : recentOpps) {
              String amount = o.Amount != null
                ? '$' + String.valueOf(o.Amount)
                : 'Amount not specified';
              context +=
                '- ' +
                o.Name +
                ' (' +
                o.StageName +
                ', ' +
                amount +
                ')\n';
            }
          }
        }
      } catch (Exception e) {
        System.debug('Error querying account: ' + e.getMessage());
      }
    }

    // Get contact information
    if (String.isNotBlank(contactId)) {
      try {
        List<Contact> contacts = [
          SELECT Id, Name, Title, Email, Phone
          FROM Contact
          WHERE Id = :contactId
          LIMIT 1
        ];
        if (!contacts.isEmpty()) {
          Contact con = contacts[0];
          context += '\nContact: ' + con.Name + '\n';
          if (String.isNotBlank(con.Title)) {
            context += 'Title: ' + con.Title + '\n';
          }
        }
      } catch (Exception e) {
        System.debug('Error querying contact: ' + e.getMessage());
      }
    }

    // Get opportunity information
    if (String.isNotBlank(opportunityId)) {
      try {
        List<Opportunity> opps = [
          SELECT Id, Name, StageName, Amount, CloseDate, Probability
          FROM Opportunity
          WHERE Id = :opportunityId
          LIMIT 1
        ];
        if (!opps.isEmpty()) {
          Opportunity opp = opps[0];
          context += '\nOpportunity: ' + opp.Name + '\n';
          context += 'Stage: ' + opp.StageName + '\n';
          if (opp.Amount != null) {
            context += 'Amount: $' + String.valueOf(opp.Amount) + '\n';
          }
          if (opp.CloseDate != null) {
            context += 'Close Date: ' + opp.CloseDate.format() + '\n';
          }
        }
      } catch (Exception e) {
        System.debug('Error querying opportunity: ' + e.getMessage());
      }
    }

    // Get case information
    if (String.isNotBlank(caseId)) {
      try {
        List<Case> cases = [
          SELECT Id, Subject, Status, Priority, Description
          FROM Case
          WHERE Id = :caseId
          LIMIT 1
        ];
        if (!cases.isEmpty()) {
          Case c = cases[0];
          context += '\nCase: ' + c.Subject + '\n';
          context += 'Status: ' + c.Status + '\n';
          context += 'Priority: ' + c.Priority + '\n';
          if (String.isNotBlank(c.Description)) {
            context += 'Description: ' + c.Description + '\n';
          }
        }
      } catch (Exception e) {
        System.debug('Error querying case: ' + e.getMessage());
      }
    }

    return context;
  }

  /**
   * Builds the AI prompt for generating event subject and description
   */
  private static String buildEventGenerationPrompt(
    String context,
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    String prompt = 'You are a professional sales assistant helping create customer-facing meeting invitations. ';
    prompt += 'Generate a professional, appropriate subject line and description for a meeting.\n\n';

    if (String.isNotBlank(context)) {
      prompt += '## Context\n';
      prompt += context + '\n\n';
      prompt += 'Based on the context above, generate a meeting subject and description that is relevant to the account, contact, opportunity, or case information provided.\n\n';
    } else {
      prompt += 'No specific context is available for this meeting. Generate a professional, general-purpose meeting invitation that could be used for a follow-up or strategic discussion.\n\n';
    }

    prompt += '## Requirements\n';
    prompt += '1. **Subject Line**: Create a concise, professional subject line (maximum 80 characters). ';
    prompt += 'The subject should be customer-facing and appropriate for a calendar invitation. ';
    prompt += 'It should clearly indicate the purpose of the meeting without being too technical or internal. ';
    if (String.isNotBlank(context)) {
      prompt += 'Make it specific to the context provided (e.g., include account name, reference the opportunity, or mention the case topic). ';
    } else {
      prompt += 'Use a professional but general subject like "Strategic Discussion" or "Follow-up Meeting". ';
    }
    prompt += '\n\n';

    prompt += '2. **Description**: Write a professional description (2-4 sentences) that:\n';
    prompt += '   - Explains why this meeting is being scheduled\n';
    prompt += '   - Provides context about what will be discussed\n';
    prompt += '   - Is customer-facing and professional\n';
    prompt += '   - Avoids internal jargon or technical details\n';
    if (String.isNotBlank(context)) {
      prompt += '   - References specific details from the context (account name, recent cases, opportunities, etc.)\n';
      prompt += '   - If there are specific reasons (like follow-up on a case, opportunity discussion, etc.), mention them naturally\n';
    } else {
      prompt += '   - Uses professional language suitable for a business meeting\n';
      prompt += '   - Mentions that this is an opportunity to discuss next steps and collaboration\n';
    }
    prompt += '\n\n';

    // Add specific guidance based on what context is available
    if (String.isNotBlank(caseId)) {
      prompt += 'Note: This meeting is related to a support case. Frame it as a collaborative discussion to resolve the issue, not as a complaint or problem.\n\n';
    }
    if (String.isNotBlank(opportunityId)) {
      prompt += 'Note: This meeting is related to an opportunity. Frame it as a strategic discussion to move forward, not as a sales pitch.\n\n';
    }
    if (
      String.isNotBlank(accountId) &&
      String.isBlank(contactId) &&
      String.isBlank(opportunityId) &&
      String.isBlank(caseId)
    ) {
      prompt += 'Note: This meeting is with an account. Consider recent account activity and frame it as a relationship-building or strategic discussion.\n\n';
    }

    prompt += '## Output Format\n';
    prompt += 'Respond with ONLY a valid JSON object in this exact format:\n';
    prompt += '{\n';
    prompt += '  "subject": "Your generated subject line here",\n';
    prompt += '  "description": "Your generated description here"\n';
    prompt += '}\n\n';
    prompt += 'Do not include any additional text, explanations, or markdown formatting outside the JSON object.';

    return prompt;
  }

  /**
   * Generates AI-powered subject and description for a new task
   * Uses context from account, contact, opportunity, or case to create professional, customer-facing content
   * @param taskText The task action text from the meeting recap
   * @param accountId Optional Account ID for context
   * @param contactId Optional Contact ID for context
   * @param opportunityId Optional Opportunity ID for context
   * @param caseId Optional Case ID for context
   * @return Map containing 'subject' and 'description' fields
   */
  @AuraEnabled
  public static Map<String, String> generateTaskContent(
    String taskText,
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    Map<String, String> result = new Map<String, String>();

    try {
      // Build context for AI
      String context = buildEventContext(
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // If no specific context provided, try to gather general context
      if (String.isBlank(context)) {
        context = buildGeneralContext();
      }

      // Build AI prompt
      String prompt = buildTaskGenerationPrompt(
        taskText,
        context,
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // Call Models API
      String aiResponse = callModelsAPI(prompt);

      // Parse AI response
      Map<String, String> parsedResponse = parseEventContentResponse(
        aiResponse
      );

      result.put('subject', parsedResponse.get('subject'));
      result.put('description', parsedResponse.get('description'));

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error generating task content: ' + e.getMessage()
      );
      // Return fallback values
      result.put('subject', taskText != null ? taskText : 'Follow-up Task');
      result.put(
        'description',
        'Task to complete follow-up items and next steps.'
      );
      return result;
    }
  }

  /**
   * Generates AI-powered subject and description for a new event based on action text
   * Uses context from account, contact, opportunity, or case to create professional, customer-facing content
   * @param eventText The event action text from the meeting recap
   * @param accountId Optional Account ID for context
   * @param contactId Optional Contact ID for context
   * @param opportunityId Optional Opportunity ID for context
   * @param caseId Optional Case ID for context
   * @return Map containing 'subject' and 'description' fields
   */
  @AuraEnabled
  public static Map<String, String> generateEventContentFromText(
    String eventText,
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    Map<String, String> result = new Map<String, String>();

    try {
      // Build context for AI
      String context = buildEventContext(
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // If no specific context provided, try to gather general context
      if (String.isBlank(context)) {
        context = buildGeneralContext();
      }

      // Build AI prompt
      String prompt = buildEventTextGenerationPrompt(
        eventText,
        context,
        accountId,
        contactId,
        opportunityId,
        caseId
      );

      // Call Models API
      String aiResponse = callModelsAPI(prompt);

      // Parse AI response
      Map<String, String> parsedResponse = parseEventContentResponse(
        aiResponse
      );

      result.put('subject', parsedResponse.get('subject'));
      result.put('description', parsedResponse.get('description'));

      return result;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.ERROR,
        'Error generating event content from text: ' + e.getMessage()
      );
      // Return fallback values
      result.put('subject', eventText != null ? eventText : 'Follow-up Meeting');
      result.put(
        'description',
        'Meeting to discuss next steps and follow-up items. Please come prepared with any relevant materials or questions.'
      );
      return result;
    }
  }

  /**
   * Builds the AI prompt for generating task subject and description
   */
  private static String buildTaskGenerationPrompt(
    String taskText,
    String context,
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    String prompt = 'You are a professional sales assistant helping create customer-facing task descriptions. ';
    prompt += 'Generate a professional, appropriate subject line and description for a task based on the following action item.\n\n';

    prompt += '## Task Action Item\n';
    prompt += taskText + '\n\n';

    if (String.isNotBlank(context)) {
      prompt += '## Context\n';
      prompt += context + '\n\n';
      prompt += 'Based on the context above, generate a task subject and description that is relevant to the account, contact, opportunity, or case information provided.\n\n';
    }

    prompt += '## Requirements\n';
    prompt += '1. **Subject Line**: Create a concise, professional subject line (maximum 80 characters). ';
    prompt += 'The subject should be customer-facing and appropriate for a task. ';
    prompt += 'It should clearly indicate what needs to be done without being too technical or internal. ';
    if (String.isNotBlank(context)) {
      prompt += 'Make it specific to the context provided (e.g., include account name, reference the opportunity, or mention the case topic). ';
    }
    prompt += '\n\n';

    prompt += '2. **Description**: Write a professional description (2-4 sentences) that:\n';
    prompt += '   - Explains why this task needs to be completed\n';
    prompt += '   - Provides context about what should be done\n';
    prompt += '   - Is customer-facing and professional\n';
    prompt += '   - Avoids internal jargon or technical details\n';
    if (String.isNotBlank(context)) {
      prompt += '   - References specific details from the context (account name, recent cases, opportunities, etc.)\n';
      prompt += '   - If there are specific reasons (like follow-up on a case, opportunity discussion, etc.), mention them naturally\n';
    } else {
      prompt += '   - Uses professional language suitable for a business task\n';
      prompt += '   - Mentions that this is an important follow-up item\n';
    }
    prompt += '\n\n';

    prompt += '## Output Format\n';
    prompt += 'Respond with ONLY a valid JSON object in this exact format:\n';
    prompt += '{\n';
    prompt += '  "subject": "Your generated subject line here",\n';
    prompt += '  "description": "Your generated description here"\n';
    prompt += '}\n\n';
    prompt += 'Do not include any additional text, explanations, or markdown formatting outside the JSON object.';

    return prompt;
  }

  /**
   * Builds the AI prompt for generating event subject and description from action text
   */
  private static String buildEventTextGenerationPrompt(
    String eventText,
    String context,
    String accountId,
    String contactId,
    String opportunityId,
    String caseId
  ) {
    String prompt = 'You are a professional sales assistant helping create customer-facing calendar event invitations. ';
    prompt += 'Generate a professional, appropriate subject line and description for a calendar event based on the following action item.\n\n';

    prompt += '## Event Action Item\n';
    prompt += eventText + '\n\n';

    if (String.isNotBlank(context)) {
      prompt += '## Context\n';
      prompt += context + '\n\n';
      prompt += 'Based on the context above, generate an event subject and description that is relevant to the account, contact, opportunity, or case information provided.\n\n';
    }

    prompt += '## Requirements\n';
    prompt += '1. **Subject Line**: Create a concise, professional subject line (maximum 80 characters). ';
    prompt += 'The subject should be customer-facing and appropriate for a calendar invitation. ';
    prompt += 'It should clearly indicate the purpose of the meeting without being too technical or internal. ';
    if (String.isNotBlank(context)) {
      prompt += 'Make it specific to the context provided (e.g., include account name, reference the opportunity, or mention the case topic). ';
    }
    prompt += '\n\n';

    prompt += '2. **Description**: Write a professional description (3-5 sentences) that:\n';
    prompt += '   - Explains why this meeting is being scheduled\n';
    prompt += '   - Provides context about what will be discussed\n';
    prompt += '   - Includes a brief agenda or discussion topics\n';
    prompt += '   - Mentions any preparation needed or materials to bring\n';
    prompt += '   - Is customer-facing and professional\n';
    prompt += '   - Avoids internal jargon or technical details\n';
    if (String.isNotBlank(context)) {
      prompt += '   - References specific details from the context (account name, recent cases, opportunities, etc.)\n';
      prompt += '   - If there are specific reasons (like follow-up on a case, opportunity discussion, etc.), mention them naturally\n';
    } else {
      prompt += '   - Uses professional language suitable for a business meeting\n';
      prompt += '   - Mentions that this is an opportunity to discuss next steps and collaboration\n';
    }
    prompt += '\n\n';

    // Add specific guidance based on what context is available
    if (String.isNotBlank(caseId)) {
      prompt += 'Note: This meeting is related to a support case. Frame it as a collaborative discussion to resolve the issue, not as a complaint or problem.\n\n';
    }
    if (String.isNotBlank(opportunityId)) {
      prompt += 'Note: This meeting is related to an opportunity. Frame it as a strategic discussion to move forward, not as a sales pitch.\n\n';
    }
    if (
      String.isNotBlank(accountId) &&
      String.isBlank(contactId) &&
      String.isBlank(opportunityId) &&
      String.isBlank(caseId)
    ) {
      prompt += 'Note: This meeting is with an account. Consider recent account activity and frame it as a relationship-building or strategic discussion.\n\n';
    }

    prompt += '## Output Format\n';
    prompt += 'Respond with ONLY a valid JSON object in this exact format:\n';
    prompt += '{\n';
    prompt += '  "subject": "Your generated subject line here",\n';
    prompt += '  "description": "Your generated description here"\n';
    prompt += '}\n\n';
    prompt += 'Do not include any additional text, explanations, or markdown formatting outside the JSON object.';

    return prompt;
  }

  /**
   * Gets Event record data for hover popover display
   * @param eventId The Event ID to fetch
   * @return Map containing Event fields
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getEventRecord(String eventId) {
    Map<String, Object> result = new Map<String, Object>();
    
    if (String.isBlank(eventId)) {
      return result;
    }

    try {
      List<Event> events = [
        SELECT
          Id,
          Subject,
          StartDateTime,
          EndDateTime,
          Location,
          Description,
          Type,
          IsAllDayEvent
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

  /**
   * Parses the AI response to extract subject and description
   */
  private static Map<String, String> parseEventContentResponse(
    String aiResponse
  ) {
    Map<String, String> result = new Map<String, String>();

    try {
      // Extract JSON from response
      String jsonContent = extractJsonFromResponse(aiResponse);

      if (String.isNotBlank(jsonContent)) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
          jsonContent
        );

        String subject = (String) responseMap.get('subject');
        String description = (String) responseMap.get('description');

        // Clean up and validate
        if (String.isNotBlank(subject)) {
          // Truncate if too long (Event Subject field limit is 255 characters)
          if (subject.length() > 255) {
            subject = subject.substring(0, 252) + '...';
          }
          result.put('subject', subject.trim());
        } else {
          result.put('subject', 'Follow-up Meeting');
        }

        if (String.isNotBlank(description)) {
          result.put('description', description.trim());
        } else {
          result.put(
            'description',
            'Meeting to discuss next steps and follow-up items.'
          );
        }
      } else {
        // Fallback if JSON parsing fails
        result.put('subject', 'Follow-up Meeting');
        result.put(
          'description',
          'Meeting to discuss next steps and follow-up items.'
        );
      }
    } catch (Exception e) {
      System.debug('Error parsing event content response: ' + e.getMessage());
      result.put('subject', 'Follow-up Meeting');
      result.put(
        'description',
        'Meeting to discuss next steps and follow-up items.'
      );
    }

    return result;
  }
}
