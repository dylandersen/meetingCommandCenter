/**
 * Small, stateless helpers shared across the Meeting Command Center service
 * classes: extracting JSON from loosely-formatted AI responses, ISO date
 * formatting, and null-safe string truncation.
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

    /**
     * Formats a Date as an ISO 'yyyy-MM-dd' string (no time component), which
     * is what the HTML date input and the model both expect.
     */
    public static String formatDateIso(Date d) {
        if (d == null) {
            return null;
        }
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
    }

    /**
     * Null-safe string truncation for storing values into bounded Text fields.
     */
    public static String safeTrunc(String value, Integer maxLen) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLen ? value.substring(0, maxLen) : value;
    }
}
