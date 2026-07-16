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

    /**
     * The single combined prompt that returns the recap summary plus suggested
     * Opportunity updates and follow-up tasks as JSON.
     */
    public static String insights(
        Event evt,
        String recapText,
        Map<String, Object> ctx,
        Opportunity opp,
        List<Map<String, String>> stageOptions
    ) {
        String userName = currentUserFirstName();

        String prompt = 'You are an expert sales meeting assistant. Analyze the rep\'s meeting notes and return STRUCTURED JSON.\n\n';

        prompt += '## Meeting Details\n';
        prompt += '- Subject: ' + (evt.Subject != null ? evt.Subject : 'No subject') + '\n';
        if (evt.StartDateTime != null) {
            prompt += '- Date/Time: ' + evt.StartDateTime.format('MMMM d, yyyy h:mm a') + '\n';
        }
        if (ctx.get('accountName') != null) {
            prompt += '- Account: ' + ctx.get('accountName') + '\n';
        }
        if (ctx.get('contactName') != null) {
            prompt += '- Contact: ' + ctx.get('contactName') + '\n';
        }
        prompt += '- Rep (meeting participant): ' + userName + '\n';
        prompt += '- Today\'s date: ' + String.valueOf(Date.today()) + '\n';

        prompt += '\n## Naming Guidance (IMPORTANT)\n';
        if (ctx.get('contactName') != null) {
            prompt +=
                '- The CRM contact for this meeting is "' +
                ctx.get('contactName') +
                '". The rep may refer to this same person in the notes by their first name, a nickname, or a shortened form.\n';
        }
        if (ctx.get('accountName') != null) {
            prompt += '- The CRM account is "' + ctx.get('accountName') + '".\n';
        }
        prompt += '- ALWAYS refer to people using the exact name the REP used in their notes. If the rep writes a first name (e.g. "Dana") that clearly maps to the CRM contact (e.g. "Dana Chen"), use that first name ("Dana") throughout the summary, outcomes, next steps, and tasks. Do NOT substitute the contact\'s last name when the rep used their first name.\n';
        prompt += '- Never refer to the contact by last name alone unless the rep explicitly did so in the notes.\n';
        prompt += '- Reconcile each name mentioned in the notes against the CRM contact/account above (match on first name). When in doubt, use the precise name the rep wrote rather than guessing.\n';

        prompt += '\n## Rep\'s Meeting Notes\n' + recapText + '\n\n';

        if (opp != null) {
            prompt += '## Current Opportunity Values (suggest updates ONLY when the notes clearly indicate a change)\n';
            prompt += '- Opportunity: ' + opp.Name + '\n';
            prompt += '- Amount: ' + (opp.Amount != null ? String.valueOf(opp.Amount) : 'null') + '\n';
            prompt +=
                '- CloseDate: ' +
                (opp.CloseDate != null ? MeetingUtils.formatDateIso(opp.CloseDate) : 'null') +
                '\n';
            prompt += '- StageName: ' + (opp.StageName != null ? opp.StageName : 'null') + '\n';
            prompt += '- NextStep: ' + (opp.NextStep != null ? opp.NextStep : 'null') + '\n';
            List<String> stageVals = new List<String>();
            for (Map<String, String> s : stageOptions) {
                stageVals.add(s.get('value'));
            }
            prompt += '- Valid StageName values: ' + String.join(stageVals, ', ') + '\n\n';
        }

        prompt += '## Output Format - respond with ONLY this JSON (no markdown fences, no extra commentary):\n';
        prompt += '{\n';
        prompt +=
            '  "summary": "A thorough executive summary (3-5 paragraphs) covering the main discussion points, decisions made, and overall meeting outcomes. Use HTML <p> tags for paragraphs with a blank line (<br><br>) between each paragraph for readability. Be detailed and capture all important aspects of the meeting. When referring to the meeting participant, use their first name \'' +
            userName +
            '\' instead of \'the user\' (e.g. \'' +
            userName +
            ' discussed...\', \'' +
            userName +
            ' agreed to...\').",\n';
        prompt +=
            '  "keyOutcomes": "A comprehensive list of ALL key outcomes, decisions, insights, and accomplishments. Format as an HTML <ul><li> list with detailed, well-explained bullet points that include context. Include every significant outcome, not just a few. When referring to the meeting participant, use their first name \'' +
            userName +
            '\' (e.g. \'' +
            userName +
            ' committed to...\').",\n';
        prompt += '  "nextSteps": "A complete list of ALL actionable next steps, follow-up items, and commitments. Format as an HTML <ul><li> list. Include owners, deadlines, and context where mentioned; be thorough and capture every action item even minor ones. Write in second person using \'You should\' or \'You need to\' (never \'the user should\'). Include a mix of action types (prepare, send, research, draft, schedule, follow-up call) and avoid repeating similar items.",\n';
        if (opp != null) {
            prompt += '  "opportunityUpdates": { "amount": number-or-null, "closeDate": "YYYY-MM-DD"-or-null, "stageName": "an exact value from the valid list"-or-null, "nextStep": "string (REQUIRED - always provide a concise, specific next action; NEVER null)" },\n';
        } else {
            prompt += '  "opportunityUpdates": {},\n';
        }
        prompt += '  "tasks": [ { "subject": "short actionable title (max 80 chars)", "description": "1-2 sentence detail", "dueDate": "YYYY-MM-DD-or-null" } ]\n';
        prompt += '}\n\n';
        prompt += 'Rules: For opportunityUpdates, set stageName to null unless the notes clearly imply a new value. ';
        prompt += 'CLOSE DATE - be proactive: whenever the notes mention when the deal is expected, anticipated, targeted, or planned to close (or be signed/finalized), set "closeDate" to that date. ';
        prompt += 'Treat phrasing like "expecting to close", "expect to close", "should close", "close by/on", "closing on", "wrap up by", "signed by", "finalize by", "get this done by", or "land this by" as a CloseDate change - even when the rep is only stating their expectation and has not confirmed it with the customer. ';
        prompt += 'Resolve the spoken date (e.g. "June 10", "end of next month") into YYYY-MM-DD using today\'s date for the year. Do not leave closeDate null just because a date already exists on the opportunity. ';
        prompt += 'Example: "I\'m expecting to close this deal on June 10" with today in 2026 -> closeDate "2026-06-10". ';
        prompt += 'AMOUNT - be proactive: whenever the notes discuss pricing, a discount, a negotiated figure, a target deal value, or any new dollar amount for THIS opportunity, set "amount" to the new value (do not leave it null just because a number already exists). ';
        prompt += 'Treat phrasing like "discount to", "down to", "sell it at", "land at", "go for X", "come down to", "my lowest is X", "target X", or "around X" as a proposed Amount change. ';
        prompt += 'When MULTIPLE figures are mentioned, choose the amount the REP intends to actually pursue/sell at - i.e. the value the rep says they will "go for", their floor/lowest acceptable price, or the agreed target - NOT the current opportunity value and NOT the customer\'s opening ask. ';
        prompt += 'Example: if the deal is currently $720,000, the customer wants $500,000, and the rep says their lowest discount is $550,000 and "that\'s what we\'re gonna go for", set amount to 550000. ';
        prompt += 'Only leave amount null when the notes contain no pricing/value discussion at all. ';
        prompt += 'EXCEPTION - nextStep is MANDATORY: you must ALWAYS return a specific next action for the deal in the "nextStep" field (never null, never empty). ';
        prompt += 'Derive the single most important upcoming action from the notes (e.g. an upcoming meeting, a deliverable the rep owes, a follow-up to send). If the notes mention a clear next action, use it; if not, infer the most logical next step from the meeting context. ';
        prompt +=
            'VOICE: write nextStep in the FIRST PERSON, present-progressive tense, as the seller (' +
            userName +
            ') working this opportunity would write it for sales leadership reviewing the deal. Use confident, deal-centric language a veteran AE would use - reference the stakeholder and their role/title when known, the strategic intent behind the action, and how it advances the deal (e.g. "Working to get updated pricing out to Dana Chen, CEO, ahead of our June 16 meeting to lock in alignment with her executive team"). ';
        prompt += 'Convey momentum and where the deal stands - avoid terse imperative phrasing like "Send pricing" or "Schedule meeting"; instead frame it as the seller actively driving the deal forward. Keep it to one or two sentences and include a date when one is known. ';
        prompt += 'Resolve relative dates (e.g. "end of next month", "Friday") against today\'s date into YYYY-MM-DD. ';
        prompt += 'Only create tasks for concrete follow-ups or action items the rep committed to or must complete; return an empty array if there are none. ';
        prompt += 'Amounts must be plain numbers with no currency symbols or commas. ';
        prompt += 'The summary, keyOutcomes, and nextSteps fields support very long content - be comprehensive and detailed using proper HTML (<p>, <ul>, <li>); do not limit yourself to a few items.';

        return prompt;
    }
}
