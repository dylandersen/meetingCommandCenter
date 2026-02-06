@JsonAccess(serializable='always' deserializable='always')
global class MeetingPrepOutput {
  @AuraEnabled
  @InvocableVariable(label='Meeting Prep ID')
  global String meetingPrepId;

  @AuraEnabled
  @InvocableVariable(label='Event ID')
  global String eventId;

  @AuraEnabled
  @InvocableVariable(label='Event Subject')
  global String eventSubject;

  @AuraEnabled
  @InvocableVariable(label='Event Date/Time')
  global String eventDateTime;

  @AuraEnabled
  @InvocableVariable(label='Event Location')
  global String eventLocation;

  @AuraEnabled
  @InvocableVariable(label='Prep Brief HTML')
  global String prepBriefHTML;

  @AuraEnabled
  @InvocableVariable(label='Attendee Summary')
  global String attendeeSummary;

  @AuraEnabled
  @InvocableVariable(label='Key Talking Points')
  global String keyTalkingPoints;

  @AuraEnabled
  @InvocableVariable(label='Recent Updates')
  global String recentUpdates;

  @AuraEnabled
  @InvocableVariable(label='Questions To Ask')
  global String questionsToAsk;

  @AuraEnabled
  @InvocableVariable(label='Potential Objections')
  global String potentialObjections;

  @AuraEnabled
  @InvocableVariable(label='Competitive Intelligence')
  global String competitiveIntelligence;

  @AuraEnabled
  @InvocableVariable(label='Success')
  global Boolean success;

  @AuraEnabled
  @InvocableVariable(label='Message')
  global String message;
}
