@JsonAccess(serializable='always' deserializable='always')
global class MeetingPrepInput {
  @AuraEnabled
  @InvocableVariable(label='Event ID' required=true)
  global String eventId;

  @AuraEnabled
  @InvocableVariable(
    label='Regenerate'
    description='Force regeneration even if prep brief already exists'
  )
  global Boolean regenerate;
}
