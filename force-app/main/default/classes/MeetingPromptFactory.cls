/**
 * Builds every Models API prompt used by the Meeting Command Center. Keeping
 * prompt text in one place separates the (frequently tuned) wording from the
 * data-gathering and persistence logic in the service classes.
 */
public with sharing class MeetingPromptFactory {
    /**
     * Returns the current user's first name, falling back to the first token
     * of their full name.
     */
    public static String currentUserFirstName() {
        String userName = UserInfo.getFirstName();
        if (String.isBlank(userName)) {
            userName = UserInfo.getName();
            if (userName != null && userName.contains(' ')) {
                userName = userName.substring(0, userName.indexOf(' '));
            }
        }
        return userName;
    }

    /**
     * Prompt for summarizing a single meeting recap into summary / key
     * outcomes / next steps JSON.
     */
    public static String summarization(Event evt, String recapText) {
        String userName = currentUserFirstName();

        String prompt = 'You are an expert meeting summarizer for sales professionals. ';
        prompt += 'Given the following meeting recap notes from the user, generate a structured summary.\n\n';

        prompt += '## Meeting Details\n';
        prompt += '- Subject: ' + (evt.Subject != null ? evt.Subject : 'No subject') + '\n';
        prompt += '- Date/Time: ' + evt.StartDateTime.format('MMMM d, yyyy h:mm a') + '\n';
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
     * Prompt for a brief plain-text summary of recent account activity.
     */
    public static String accountActivity(String context) {
        String prompt = 'You are a sales assistant helping prepare for a meeting. ';
        prompt += 'Based on the following recent account activity, provide a brief 2-3 sentence summary ';
        prompt += 'of what\'s been happening with this account recently. Focus on key updates, ';
        prompt += 'open items, and anything relevant for an upcoming meeting.\n\n';
        prompt += context;
        prompt += '\n\nProvide a concise, actionable summary in plain text (no markdown or formatting).';
        return prompt;
    }

    /**
     * Prompt for a brief plain-text summary of recent contact activity (used
     * when the meeting has no related account).
     */
    public static String contactActivity(String context) {
        String prompt = 'You are a sales assistant helping prepare for a meeting. ';
        prompt += 'Based on the following recent activity for this contact, provide a brief 2-3 sentence summary ';
        prompt += 'of what\'s been happening with this contact recently. Focus on key updates, ';
        prompt += 'open items, and anything relevant for an upcoming meeting.\n\n';
        prompt += context;
        prompt += '\n\nProvide a concise, actionable summary in plain text (no markdown or formatting).';
        return prompt;
    }

    /**
     * Prompt for generating a meeting subject + description from related-record
     * context.
     */
    public static String eventGeneration(
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
     * Prompt for generating a task subject + description from an action item.
     */
    public static String taskGeneration(
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
     * Prompt for generating a calendar-event subject + description from an
     * action item.
     */
    public static String eventTextGeneration(
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
}
