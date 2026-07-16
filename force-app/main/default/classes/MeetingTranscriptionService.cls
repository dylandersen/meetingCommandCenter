/**
 * Encapsulates the Deepgram speech-to-text integration: reading the API key
 * from Custom Metadata, calling the REST endpoint, and extracting the
 * transcript from the response.
 */
public with sharing class MeetingTranscriptionService {
    private static final String DEEPGRAM_ENDPOINT = 'https://api.deepgram.com/v1/listen?model=nova-2&language=en-US&punctuate=true&smart_format=true';

    /**
     * Returns the configured Deepgram API key, or null if it isn't configured.
     */
    public static String getApiKey() {
        try {
            Deepgram_API_Config__mdt config = Deepgram_API_Config__mdt.getInstance('Default');
            if (config == null || String.isBlank(config.API_Key__c)) {
                System.debug('Deepgram API key not configured in Custom Metadata');
                return null;
            }
            return config.API_Key__c;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error retrieving Deepgram API key: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Transcribes a base64-encoded audio chunk via Deepgram and returns the
     * recognized text ('' when there is nothing to transcribe).
     */
    public static String transcribe(String audioBase64, String existingText) {
        if (String.isBlank(audioBase64)) {
            return '';
        }

        try {
            Deepgram_API_Config__mdt config = Deepgram_API_Config__mdt.getInstance('Default');
            if (config == null || String.isBlank(config.API_Key__c)) {
                throw new AuraHandledException('Deepgram API key not configured');
            }

            Blob audioBlob = EncodingUtil.base64Decode(audioBase64);

            HttpRequest req = new HttpRequest();
            req.setEndpoint(DEEPGRAM_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Token ' + config.API_Key__c);
            req.setHeader('Content-Type', 'audio/webm');
            req.setBodyAsBlob(audioBlob);
            req.setTimeout(30000); // 30 second timeout

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String transcript = extractTranscript(responseData);
                return String.isNotBlank(transcript) ? transcript : '';
            } else {
                System.debug('Deepgram API error: ' + res.getStatusCode() + ' - ' + res.getStatus());
                System.debug('Response body: ' + res.getBody());
                throw new AuraHandledException('Deepgram API returned error: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in transcribe: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Transcription error: ' + e.getMessage());
        }
    }

    /**
     * Extracts the transcript text from a Deepgram API response payload.
     */
    private static String extractTranscript(Map<String, Object> responseData) {
        try {
            Map<String, Object> results = (Map<String, Object>) responseData.get('results');
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
            System.debug(LoggingLevel.WARN, 'Error extracting transcript: ' + e.getMessage());
            return '';
        }
    }
}
