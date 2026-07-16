/**
 * Single integration point for the Salesforce Models API. Centralizing the
 * call here keeps prompt construction, context gathering, and persistence
 * free of API plumbing and makes the model/config easy to change in one place.
 */
public with sharing class MeetingAIGateway {
    @TestVisible
    private static final String DEFAULT_MODEL = 'sfdc_ai__DefaultOpenAIGPT4Omni';

    /**
     * Sends a prompt to the Models API and returns the generated text.
     * @param prompt The fully-built prompt
     * @return The model's generated text
     */
    public static String generate(String prompt) {
        try {
            aiplatform.ModelsAPI.createGenerations_Request request = new aiplatform.ModelsAPI.createGenerations_Request();
            request.modelName = DEFAULT_MODEL;

            aiplatform.ModelsAPI_GenerationRequest requestBody = new aiplatform.ModelsAPI_GenerationRequest();
            request.body = requestBody;
            requestBody.prompt = prompt;

            aiplatform.ModelsAPI modelsAPI = new aiplatform.ModelsAPI();
            aiplatform.ModelsAPI.createGenerations_Response response = modelsAPI.createGenerations(request);

            if (response.Code200 != null && response.Code200.generation != null) {
                return response.Code200.generation.generatedText;
            } else {
                throw new AuraHandledException('No response from AI. Please verify Einstein Generative AI is enabled.');
            }
        } catch (aiplatform.ModelsAPI.createGenerations_ResponseException e) {
            System.debug(LoggingLevel.ERROR, 'Models API Response Exception: ' + e.getMessage());
            throw new AuraHandledException('AI service error: ' + e.getMessage());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Models API Error: ' + e.getMessage());
            throw new AuraHandledException('AI service unavailable: ' + e.getMessage());
        }
    }
}
