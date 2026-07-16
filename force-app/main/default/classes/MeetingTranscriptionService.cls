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
            Deepgram_API_Config__mdt config;
            try {
                config = Deepgram_API_Config__mdt.getInstance('Default');
            } catch (Exception configEx) {
                System.debug('Error getting config: ' + configEx.getMessage());
                throw new AuraHandledException(
                    'Deepgram API configuration not found. Please configure the API key in Custom Metadata.'
                );
            }

            if (config == null || String.isBlank(config.API_Key__c)) {
                throw new AuraHandledException(
                    'Deepgram API key is not configured. Please set the API key in Custom Metadata Type: Deepgram_API_Config__mdt'
                );
            }

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

            HttpRequest req = new HttpRequest();
            req.setEndpoint(DEEPGRAM_ENDPOINT);
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
                throw new AuraHandledException(
                    'Failed to connect to Deepgram API. Please check your network connection and Remote Site Settings.'
                );
            }

            if (res.getStatusCode() == 200) {
                Map<String, Object> responseData;
                try {
                    responseData = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                } catch (Exception parseEx) {
                    System.debug('Error parsing response: ' + parseEx.getMessage());
                    System.debug('Response body: ' + res.getBody());
                    throw new AuraHandledException('Failed to parse transcription response from Deepgram API.');
                }

                String transcript = extractTranscript(responseData);
                return String.isNotBlank(transcript) ? transcript : '';
            } else {
                String errorBody = res.getBody();
                System.debug('Deepgram API error: ' + res.getStatusCode() + ' - ' + res.getStatus());
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
            throw e;
        } catch (Exception e) {
            String errorMsg = e.getMessage();
            if (String.isBlank(errorMsg)) {
                errorMsg = e.getTypeName();
            }
            if (String.isBlank(errorMsg)) {
                errorMsg = 'Unknown error occurred during transcription';
            }
            System.debug(LoggingLevel.ERROR, 'Error in transcribe: ' + errorMsg);
            System.debug('Exception type: ' + e.getTypeName());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Transcription error: ' + errorMsg);
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
