/**
 * Gathers and shapes the CRM context (Account / Opportunity / Contact / Case
 * activity) that the AI prompts and recap review UI depend on. All of the
 * read-only relationship resolution and "recent activity" querying lives here
 * so the prompt and persistence layers stay focused.
 */
public with sharing class MeetingContextService {
    /**
     * Builds the account prep info map for an Event (account, opportunity,
     * contact, and an AI activity summary), resolving the polymorphic WhatId.
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

            Id accountId = null;
            String accountName = null;

            if (evt.WhatId != null) {
                String whatType = String.valueOf(evt.WhatId.getSObjectType());

                if (whatType == 'Opportunity') {
                    result.put('opportunityId', evt.WhatId);
                    result.put('opportunityName', evt.What != null ? evt.What.Name : null);

                    List<Opportunity> opps = [
                        SELECT Id, AccountId, Account.Name
                        FROM Opportunity
                        WHERE Id = :evt.WhatId
                        LIMIT 1
                    ];
                    if (!opps.isEmpty() && opps[0].AccountId != null) {
                        accountId = opps[0].AccountId;
                        accountName = opps[0].Account != null ? opps[0].Account.Name : null;
                    }
                } else if (whatType == 'Account') {
                    accountId = evt.WhatId;
                    accountName = evt.What != null ? evt.What.Name : null;
                }
            }

            if (accountId != null) {
                result.put('accountId', accountId);
                result.put('accountName', accountName);
                result.put('accountSummary', generateAccountSummary(accountId));
            }

            if (evt.WhoId != null) {
                result.put('contactId', evt.WhoId);
                result.put('contactName', evt.Who != null ? evt.Who.Name : null);
            }

            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in buildAccountPrepInfo: ' + e.getMessage());
            return result;
        }
    }

    /**
     * Generates an AI account-research summary from a complete 90-day CRM
     * activity packet. The account summary is shown during meeting prep, so
     * include both durable account context and time-bound deal momentum.
     */
    public static String generateAccountSummary(String accountId) {
        try {
            Date startDate = Date.today().addDays(-90);
            DateTime startDateTime = DateTime.now().addDays(-90);

            Account account = [
                SELECT
                    Id,
                    Name,
                    Industry,
                    Type,
                    Website,
                    AnnualRevenue,
                    NumberOfEmployees,
                    Description,
                    BillingCity,
                    BillingState
                FROM Account
                WHERE Id = :accountId
                LIMIT 1
            ];

            List<Contact> contacts = [
                SELECT Id, Name, FirstName, LastName, Title, Department, Email, Phone
                FROM Contact
                WHERE AccountId = :accountId
                ORDER BY LastModifiedDate DESC
                LIMIT 25
            ];

            List<Opportunity> opportunities = [
                SELECT
                    Id,
                    Name,
                    StageName,
                    Amount,
                    CloseDate,
                    Probability,
                    NextStep,
                    IsClosed,
                    IsWon,
                    CreatedDate,
                    LastModifiedDate
                FROM Opportunity
                WHERE AccountId = :accountId
                ORDER BY IsClosed ASC, CloseDate ASC NULLS LAST, LastModifiedDate DESC
                LIMIT 25
            ];

            List<Case> cases = [
                SELECT Id, Subject, Status, Priority, Origin, CreatedDate, LastModifiedDate, ClosedDate
                FROM Case
                WHERE AccountId = :accountId AND (CreatedDate >= :startDateTime OR LastModifiedDate >= :startDateTime)
                ORDER BY LastModifiedDate DESC
                LIMIT 25
            ];

            List<Task> tasks = [
                SELECT
                    Id,
                    Subject,
                    Status,
                    Priority,
                    Type,
                    ActivityDate,
                    Description,
                    CreatedDate,
                    LastModifiedDate,
                    Who.Name
                FROM Task
                WHERE (WhatId = :accountId OR AccountId = :accountId) AND CreatedDate >= :startDateTime
                ORDER BY ActivityDate DESC NULLS LAST, CreatedDate DESC
                LIMIT 50
            ];

            List<EmailMessage> emails = [
                SELECT Id, Subject, FromName, FromAddress, ToAddress, TextBody, MessageDate, Incoming, Status
                FROM EmailMessage
                WHERE RelatedToId = :accountId AND MessageDate >= :startDateTime
                ORDER BY MessageDate DESC
                LIMIT 50
            ];

            Set<Id> opportunityIds = new Set<Id>();
            for (Opportunity opportunity : opportunities) {
                opportunityIds.add(opportunity.Id);
            }

            List<Event> events = new List<Event>();
            if (opportunityIds.isEmpty()) {
                events = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, Location, Description, Who.Name, What.Name
                    FROM Event
                    WHERE WhatId = :accountId AND StartDateTime >= :startDateTime
                    ORDER BY StartDateTime DESC
                    LIMIT 25
                ];
            } else {
                events = [
                    SELECT Id, Subject, StartDateTime, EndDateTime, Location, Description, Who.Name, What.Name
                    FROM Event
                    WHERE (WhatId = :accountId OR WhatId IN :opportunityIds) AND StartDateTime >= :startDateTime
                    ORDER BY StartDateTime DESC
                    LIMIT 25
                ];
            }

            String context = buildAccountContext(
                account,
                contacts,
                opportunities,
                cases,
                tasks,
                emails,
                events,
                startDate
            );
            return MeetingAIGateway.generate(MeetingPromptFactory.accountActivity(context));
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error generating account summary: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Builds a grounded research packet for the account-summary prompt.
     */
    private static String buildAccountContext(
        Account account,
        List<Contact> contacts,
        List<Opportunity> opportunities,
        List<Case> cases,
        List<Task> tasks,
        List<EmailMessage> emails,
        List<Event> events,
        Date startDate
    ) {
        String context = 'ACCOUNT RESEARCH PACKET\n';
        context += 'Research window: ' + startDate.format() + ' through ' + Date.today().format() + ' (90 days)\n\n';

        context += 'Account Profile:\n';
        context += '- Name: ' + account.Name + '\n';
        if (String.isNotBlank(account.Industry)) {
            context += '- Industry: ' + account.Industry + '\n';
        }
        if (String.isNotBlank(account.Type)) {
            context += '- Type: ' + account.Type + '\n';
        }
        if (String.isNotBlank(account.Website)) {
            context += '- Website: ' + account.Website + '\n';
        }
        if (account.AnnualRevenue != null) {
            context += '- Annual revenue: $' + String.valueOf(account.AnnualRevenue) + '\n';
        }
        if (account.NumberOfEmployees != null) {
            context += '- Employees: ' + String.valueOf(account.NumberOfEmployees) + '\n';
        }
        if (String.isNotBlank(account.BillingCity) || String.isNotBlank(account.BillingState)) {
            context +=
                '- Location: ' +
                String.valueOf(account.BillingCity) +
                ', ' +
                String.valueOf(account.BillingState) +
                '\n';
        }
        if (String.isNotBlank(account.Description)) {
            context += '- Description: ' + truncateText(account.Description, 600) + '\n';
        }
        context += '\n';

        context += 'Key Contacts (' + contacts.size() + '):\n';
        if (contacts.isEmpty()) {
            context += '- No contacts found.\n';
        } else {
            for (Contact contact : contacts) {
                context +=
                    '- ' +
                    contact.Name +
                    (String.isNotBlank(contact.Title) ? ' — ' + contact.Title : '') +
                    (String.isNotBlank(contact.Department) ? ' (' + contact.Department + ')' : '') +
                    (String.isNotBlank(contact.Email) ? ', ' + contact.Email : '') +
                    '\n';
            }
        }
        context += '\n';

        context += 'Opportunities (' + opportunities.size() + '):\n';
        if (opportunities.isEmpty()) {
            context += '- No opportunities found.\n';
        } else {
            for (Opportunity opportunity : opportunities) {
                String amount = opportunity.Amount != null
                    ? '$' + String.valueOf(opportunity.Amount)
                    : 'amount not specified';
                String status = opportunity.IsClosed ? (opportunity.IsWon ? 'closed won' : 'closed lost') : 'open';
                context +=
                    '- ' +
                    opportunity.Name +
                    ' | ' +
                    status +
                    ' | stage: ' +
                    opportunity.StageName +
                    ' | amount: ' +
                    amount;
                if (opportunity.CloseDate != null) {
                    context += ' | close date: ' + opportunity.CloseDate.format();
                }
                if (opportunity.Probability != null) {
                    context += ' | probability: ' + String.valueOf(opportunity.Probability) + '%';
                }
                if (String.isNotBlank(opportunity.NextStep)) {
                    context += ' | next step: ' + truncateText(opportunity.NextStep, 300);
                }
                context += '\n';
            }
        }
        context += '\n';

        context += 'Support Cases in Window (' + cases.size() + '):\n';
        if (cases.isEmpty()) {
            context += '- None.\n';
        } else {
            for (Case supportCase : cases) {
                context +=
                    '- ' +
                    supportCase.Subject +
                    ' | status: ' +
                    supportCase.Status +
                    ' | priority: ' +
                    supportCase.Priority +
                    ' | last modified: ' +
                    supportCase.LastModifiedDate.format();
                if (String.isNotBlank(supportCase.Origin)) {
                    context += ' | origin: ' + supportCase.Origin;
                }
                context += '\n';
            }
        }
        context += '\n';

        context += 'Tasks in Window (' + tasks.size() + '):\n';
        if (tasks.isEmpty()) {
            context += '- None.\n';
        } else {
            for (Task task : tasks) {
                context +=
                    '- ' +
                    (task.Subject != null ? task.Subject : 'Task') +
                    ' | status: ' +
                    task.Status +
                    ' | priority: ' +
                    task.Priority +
                    (String.isNotBlank(task.Type) ? ' | type: ' + task.Type : '') +
                    (task.Who != null ? ' | contact: ' + task.Who.Name : '');
                if (task.ActivityDate != null) {
                    context += ' | due: ' + task.ActivityDate.format();
                }
                if (String.isNotBlank(task.Description)) {
                    context += ' | detail: ' + truncateText(task.Description, 400);
                }
                context += '\n';
            }
        }
        context += '\n';

        context += 'Email Conversation in Window (' + emails.size() + '):\n';
        if (emails.isEmpty()) {
            context += '- None.\n';
        } else {
            for (EmailMessage email : emails) {
                String direction = email.Incoming ? 'INBOUND' : 'OUTBOUND';
                context +=
                    '- ' +
                    String.valueOf(email.MessageDate) +
                    ' | ' +
                    direction +
                    ' | from: ' +
                    email.FromName +
                    ' <' +
                    email.FromAddress +
                    '> | subject: ' +
                    email.Subject +
                    '\n';
                if (String.isNotBlank(email.TextBody)) {
                    context += '  excerpt: ' + truncateText(email.TextBody, 600) + '\n';
                }
            }
        }
        context += '\n';

        context += 'Meetings in Window (' + events.size() + '):\n';
        if (events.isEmpty()) {
            context += '- None.\n';
        } else {
            for (Event meeting : events) {
                String timing = meeting.StartDateTime > DateTime.now() ? 'UPCOMING' : 'PAST';
                context +=
                    '- ' +
                    timing +
                    ' | ' +
                    String.valueOf(meeting.StartDateTime) +
                    ' | ' +
                    meeting.Subject +
                    (meeting.Who != null ? ' | contact: ' + meeting.Who.Name : '') +
                    (meeting.What != null ? ' | related: ' + meeting.What.Name : '') +
                    (String.isNotBlank(meeting.Location) ? ' | location: ' + meeting.Location : '') +
                    '\n';
            }
        }

        context +=
            '\nResearch rules: Treat this packet as the source of truth. Distinguish facts from reasonable inferences. ' +
            'Do not invent external research, contacts, deal stages, or commitments that are not present above.';
        return context;
    }

    private static String truncateText(String value, Integer maxLength) {
        if (String.isBlank(value) || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength) + '...';
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

    /**
     * Resolves the Account / Opportunity / Contact related to an Event.
     * Event.WhatId is polymorphic (Opportunity or Account). When it is an
     * Opportunity, the parent Account is derived. When we have an Account but
     * no Opportunity, the most relevant open Opportunity is surfaced so the
     * rep can update it from the recap.
     */
    public static Map<String, Object> resolveOpportunityContext(Event evt) {
        Map<String, Object> ctx = new Map<String, Object>{
            'accountId' => null,
            'accountName' => null,
            'opportunityId' => null,
            'opportunityName' => null,
            'contactId' => null,
            'contactName' => null
        };

        if (evt.WhoId != null) {
            ctx.put('contactId', evt.WhoId);
            ctx.put('contactName', evt.Who != null ? evt.Who.Name : null);
        }

        Id accountId = null;
        if (evt.WhatId != null) {
            String whatType = String.valueOf(evt.WhatId.getSObjectType());
            if (whatType == 'Opportunity') {
                ctx.put('opportunityId', evt.WhatId);
                ctx.put('opportunityName', evt.What != null ? evt.What.Name : null);
                for (Opportunity o : [
                    SELECT Id, AccountId, Account.Name
                    FROM Opportunity
                    WHERE Id = :evt.WhatId
                    LIMIT 1
                ]) {
                    accountId = o.AccountId;
                    ctx.put('accountName', o.Account != null ? o.Account.Name : null);
                }
            } else if (whatType == 'Account') {
                accountId = evt.WhatId;
                ctx.put('accountName', evt.What != null ? evt.What.Name : null);
            }
        }

        // Fallback: when the Event is linked only to a Contact (no WhatId),
        // derive the Account from that Contact so we can still surface a
        // relevant Opportunity to update from the recap.
        if (accountId == null && evt.WhoId != null && String.valueOf(evt.WhoId.getSObjectType()) == 'Contact') {
            for (Contact c : [
                SELECT Id, AccountId, Account.Name
                FROM Contact
                WHERE Id = :evt.WhoId AND AccountId != NULL
                LIMIT 1
            ]) {
                accountId = c.AccountId;
                if (ctx.get('accountName') == null) {
                    ctx.put('accountName', c.Account != null ? c.Account.Name : null);
                }
            }
        }

        if (accountId != null) {
            ctx.put('accountId', accountId);
        }

        // Fallback: surface the most relevant open Opportunity on the Account -
        // the one with the soonest close date (most likely to be actively worked).
        if (ctx.get('opportunityId') == null && accountId != null) {
            for (Opportunity o : [
                SELECT Id, Name
                FROM Opportunity
                WHERE AccountId = :accountId AND IsClosed = FALSE
                ORDER BY CloseDate ASC NULLS LAST, LastModifiedDate DESC
                LIMIT 1
            ]) {
                ctx.put('opportunityId', o.Id);
                ctx.put('opportunityName', o.Name);
            }
        }

        return ctx;
    }

    /**
     * Loads a single Opportunity's review fields, or null if not found.
     */
    public static Opportunity loadOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        for (Opportunity o : [
            SELECT Id, Name, Amount, CloseDate, StageName, NextStep
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ]) {
            return o;
        }
        return null;
    }

    /**
     * Returns the active StageName picklist values as label/value maps.
     */
    public static List<Map<String, String>> activeStageOptions() {
        List<Map<String, String>> stageOptions = new List<Map<String, String>>();
        for (Schema.PicklistEntry pe : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                stageOptions.add(new Map<String, String>{ 'label' => pe.getLabel(), 'value' => pe.getValue() });
            }
        }
        return stageOptions;
    }

    /**
     * Builds the current-values + stage-options snapshot for a single
     * Opportunity, used when the rep re-targets a different Opportunity in the
     * recap review UI.
     */
    public static Map<String, Object> opportunitySnapshot(String opportunityId) {
        Opportunity opp = loadOpportunity(opportunityId);
        if (opp == null) {
            throw new AuraHandledException('Opportunity not found');
        }

        Map<String, Object> result = new Map<String, Object>();
        result.put('id', opp.Id);
        result.put('name', opp.Name);
        result.put(
            'current',
            new Map<String, Object>{
                'amount' => opp.Amount,
                'closeDate' => MeetingUtils.formatDateIso(opp.CloseDate),
                'stageName' => opp.StageName,
                'nextStep' => opp.NextStep
            }
        );
        result.put('stageOptions', activeStageOptions());
        return result;
    }
}
