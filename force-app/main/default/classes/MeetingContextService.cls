/**
 * Gathers and shapes the CRM context (Account / Contact activity, plus related
 * record details) that the AI prompts and meeting prep UI depend on. All of the
 * read-only relationship resolution and "recent activity" querying lives here
 * so the prompt and persistence layers stay focused.
 */
public with sharing class MeetingContextService {
    /**
     * Builds the account prep info map for an Event: account/contact details
     * plus an AI-generated activity summary. Falls back to a contact-based
     * summary when the Event has no related account.
     */
    public static Map<String, Object> buildAccountPrepInfo(String eventId) {
        Map<String, Object> result = new Map<String, Object>();

        try {
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

            if (evt.WhatId != null) {
                result.put('accountId', evt.WhatId);
                result.put('accountName', evt.What != null ? evt.What.Name : null);
                result.put('accountSummary', generateAccountSummary(evt.WhatId));
            }

            if (evt.WhoId != null) {
                result.put('contactId', evt.WhoId);
                result.put('contactName', evt.Who != null ? evt.Who.Name : null);

                if (evt.WhatId == null) {
                    result.put('accountSummary', generateContactSummary(evt.WhoId));
                }
            }

            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in buildAccountPrepInfo: ' + e.getMessage());
            return result;
        }
    }

    /**
     * Generates an AI summary of recent account activity (last 30 days).
     */
    public static String generateAccountSummary(String accountId) {
        try {
            Date startDate = Date.today().addDays(-30);

            List<Case> recentCases = [
                SELECT Id, Subject, Status, Priority, CreatedDate
                FROM Case
                WHERE AccountId = :accountId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            List<Opportunity> recentOpps = [
                SELECT Id, Name, StageName, Amount, CloseDate
                FROM Opportunity
                WHERE AccountId = :accountId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            List<Task> recentTasks = [
                SELECT Id, Subject, Status, CreatedDate
                FROM Task
                WHERE WhatId = :accountId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            String context = buildAccountContext(recentCases, recentOpps, recentTasks);
            return MeetingAIGateway.generate(MeetingPromptFactory.accountActivity(context));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating account summary: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Generates an AI summary of recent contact activity (used when no account
     * is linked to the meeting).
     */
    public static String generateContactSummary(String contactId) {
        try {
            Date startDate = Date.today().addDays(-30);

            List<Contact> contacts = [
                SELECT Id, Name, Title, AccountId, Account.Name, Email
                FROM Contact
                WHERE Id = :contactId
                LIMIT 1
            ];

            String accountId = null;
            String contactContext = '';
            if (!contacts.isEmpty()) {
                Contact c = contacts[0];
                contactContext += 'Contact: ' + c.Name;
                if (c.Title != null) {
                    contactContext += ' (' + c.Title + ')';
                }
                if (c.Account != null) {
                    contactContext += ' at ' + c.Account.Name;
                    accountId = c.AccountId;
                }
                contactContext += '\n\n';
            }

            List<Case> recentCases = [
                SELECT Id, Subject, Status, Priority, CreatedDate
                FROM Case
                WHERE ContactId = :contactId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            List<Task> recentTasks = [
                SELECT Id, Subject, Status, CreatedDate
                FROM Task
                WHERE WhoId = :contactId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 10
            ];

            List<Event> recentEvents = [
                SELECT Id, Subject, StartDateTime
                FROM Event
                WHERE WhoId = :contactId AND CreatedDate >= :startDate
                ORDER BY StartDateTime DESC
                LIMIT 5
            ];

            List<Opportunity> recentOpps = new List<Opportunity>();
            if (accountId != null) {
                recentOpps = [
                    SELECT Id, Name, StageName, Amount, CloseDate
                    FROM Opportunity
                    WHERE AccountId = :accountId AND CreatedDate >= :startDate
                    ORDER BY CreatedDate DESC
                    LIMIT 10
                ];
            }

            String context = contactContext + 'Recent Activity:\n\n';

            if (!recentCases.isEmpty()) {
                context += 'Recent Cases:\n';
                for (Case c : recentCases) {
                    context += '- ' + c.Subject + ' (' + c.Status + ', Priority: ' + c.Priority + ')\n';
                }
                context += '\n';
            }

            if (!recentOpps.isEmpty()) {
                context += 'Recent Opportunities:\n';
                for (Opportunity o : recentOpps) {
                    String amount = o.Amount != null ? '$' + String.valueOf(o.Amount) : 'Amount not specified';
                    context += '- ' + o.Name + ' (' + o.StageName + ', ' + amount + ')\n';
                }
                context += '\n';
            }

            if (!recentTasks.isEmpty()) {
                context += 'Recent Tasks:\n';
                for (Task t : recentTasks) {
                    context += '- ' + (t.Subject != null ? t.Subject : 'Task') + ' (' + t.Status + ')\n';
                }
                context += '\n';
            }

            if (!recentEvents.isEmpty()) {
                context += 'Recent Meetings:\n';
                for (Event e : recentEvents) {
                    context +=
                        '- ' +
                        (e.Subject != null ? e.Subject : 'Event') +
                        ' (' +
                        e.StartDateTime.format() +
                        ')\n';
                }
                context += '\n';
            }

            if (recentCases.isEmpty() && recentOpps.isEmpty() && recentTasks.isEmpty() && recentEvents.isEmpty()) {
                context += 'No recent activity in the last 30 days.\n';
            }

            return MeetingAIGateway.generate(MeetingPromptFactory.contactActivity(context));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating contact summary: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Builds a plain-text context block from recent account activity.
     */
    private static String buildAccountContext(List<Case> cases, List<Opportunity> opps, List<Task> tasks) {
        String context = 'Recent Account Activity:\n\n';

        if (!cases.isEmpty()) {
            context += 'Recent Cases:\n';
            for (Case c : cases) {
                context += '- ' + c.Subject + ' (' + c.Status + ', Priority: ' + c.Priority + ')\n';
            }
            context += '\n';
        }

        if (!opps.isEmpty()) {
            context += 'Recent Opportunities:\n';
            for (Opportunity o : opps) {
                String amount = o.Amount != null ? '$' + String.valueOf(o.Amount) : 'Amount not specified';
                context += '- ' + o.Name + ' (' + o.StageName + ', ' + amount + ')\n';
            }
            context += '\n';
        }

        if (!tasks.isEmpty()) {
            context += 'Recent Tasks:\n';
            for (Task t : tasks) {
                context += '- ' + (t.Subject != null ? t.Subject : 'Task') + ' (' + t.Status + ')\n';
            }
            context += '\n';
        }

        if (cases.isEmpty() && opps.isEmpty() && tasks.isEmpty()) {
            context += 'No recent activity in the last 30 days.\n';
        }

        return context;
    }

    /**
     * Builds a context string from the specific related records provided
     * (account/contact/opportunity/case). Returns '' when no IDs are supplied.
     */
    public static String buildEventContext(String accountId, String contactId, String opportunityId, String caseId) {
        String context = '';

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
                            context += '- ' + c.Subject + ' (' + c.Status + ', Priority: ' + c.Priority + ')\n';
                        }
                    }

                    if (!recentOpps.isEmpty()) {
                        context += '\nRecent Opportunities:\n';
                        for (Opportunity o : recentOpps) {
                            String amount = o.Amount != null ? '$' + String.valueOf(o.Amount) : 'Amount not specified';
                            context += '- ' + o.Name + ' (' + o.StageName + ', ' + amount + ')\n';
                        }
                    }
                }
            } catch (Exception e) {
                System.debug('Error querying account: ' + e.getMessage());
            }
        }

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
     * Builds general context from the current user's recent activity (last 7
     * days) when no specific related-record IDs are available.
     */
    public static String buildGeneralContext() {
        String context = '';
        Id currentUserId = UserInfo.getUserId();
        Date startDate = Date.today().addDays(-7);

        try {
            List<Opportunity> recentOpps = [
                SELECT Name, StageName, Amount, Account.Name
                FROM Opportunity
                WHERE OwnerId = :currentUserId AND CreatedDate >= :startDate
                ORDER BY CreatedDate DESC
                LIMIT 3
            ];

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
                        String amount = o.Amount != null ? '$' + String.valueOf(o.Amount) : 'Amount not specified';
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
}
