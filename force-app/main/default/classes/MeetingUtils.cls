/**
 * Small, stateless helpers shared across the Meeting Command Center service
 * classes.
 */
public with sharing class MeetingUtils {
    /**
     * Extracts the JSON object from an AI response that may include extra
     * prose or markdown fences around it.
     * @param response Raw AI response text
     * @return The substring from the first '{' to the last '}', or null
     */
    public static String extractJsonFromResponse(String response) {
        if (String.isBlank(response)) {
            return null;
        }

        Integer startIndex = response.indexOf('{');
        Integer endIndex = response.lastIndexOf('}');

        if (startIndex >= 0 && endIndex > startIndex) {
            return response.substring(startIndex, endIndex + 1);
        }

        return null;
    }
}
