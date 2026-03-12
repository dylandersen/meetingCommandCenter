# Meeting Command Center x Education Cloud
## CEA CAPA Deployment & Sales Enablement Guide

**Prepared for:** On-site deployment at CEA CAPA Education Abroad
**Date:** March 2026
**Target Org:** Salesforce Education Cloud (Education Data Architecture / EDA)

---

## Table of Contents

1. [CEA CAPA Company Profile](#1-cea-capa-company-profile)
2. [Education Cloud Data Schema Overview](#2-education-cloud-data-schema-overview)
3. [Meeting Command Center Architecture](#3-meeting-command-center-architecture)
4. [Schema Compatibility Matrix](#4-schema-compatibility-matrix)
5. [Use Cases for CEA CAPA](#5-use-cases-for-cea-capa)
6. [Talk Track & Demo Script](#6-talk-track--demo-script)
7. [Deployment Checklist](#7-deployment-checklist)
8. [Risks & Mitigations](#8-risks--mitigations)

---

## 1. CEA CAPA Company Profile

### Overview

| Detail | Value |
|--------|-------|
| **Full Name** | CEA CAPA Education Abroad |
| **Website** | ceastudyabroad.com (redirects from ceacapa.com) |
| **HQ** | Phoenix, AZ (702 E. Osborn Rd., Suite 200) |
| **Revenue** | ~$75M annually |
| **Employees** | ~700 globally |
| **Students Served** | 10,000+ annually |
| **University Partners** | 375+ U.S. universities, 50+ international institutions |
| **Destinations** | 92 cities across 37 countries |
| **Study Centers** | 12 owned/operated centers |
| **Parent Company** | Infinedi Partners (PE-backed) |
| **School of Record** | University of New Haven |

### What They Do

CEA CAPA is a **third-party study abroad provider** — they don't grant degrees. They sell study abroad, internship abroad, and hybrid academic programs to U.S. colleges and universities. The universities send students to CEA CAPA destinations, students earn transferable credit, and CEA CAPA handles academics, housing, safety, and on-site operations.

### Programs Offered

- **Study Abroad** — Traditional semester/summer coursework in international settings
- **Intern Abroad** — International internship placements across sectors
- **Study + Internship** — Blended academic + work experience programs
- **Study + Consulting** — Business consulting immersive programs
- **Pre-Health Abroad** — Pre-med coursework and clinical shadowing
- **Pre-Law Abroad** — Law-focused academic preparation
- **Custom / Faculty-Led** — Short-term programs tailored to individual universities
- **First-Year Experience** — Targeted programs for first-generation students

### How They Sell to Higher Ed

CEA CAPA's revenue model is **B2B2C**: they sell institutional partnerships to universities, who then funnel students into CEA CAPA programs.

**Sales motion:**
1. **Regional Directors** on the Institutional Relations team own geographic territories of U.S. colleges/universities
2. They pitch a **non-binding affiliate agreement** — no minimum cohort requirements
3. Universities agree to display CEA CAPA materials, process financial aid, facilitate credit transfer, and arrange campus visits
4. CEA CAPA provides **custom marketing collateral** (branded emails, websites, brochures, presentation templates)
5. Revenue comes from **program tuition** paid by enrolled students

**Key stakeholders at partner institutions:**
- Study Abroad Office Directors
- International Programs VPs/Deans
- Provost / Chief Academic Officer
- Financial Aid Office
- Registrar (for credit transfer)

### Recent Acquisitions (July 2025)

CEA CAPA acquired **CIS Abroad**, **CISaustralia**, and **Barcelona SAE** — expanding their portfolio and geographic reach significantly. This means more complexity in partner management, more meetings, more pipeline.

### Technology Stack

CEA CAPA uses **Salesforce as their CRM**. Staff record notes in CRM regarding student communication, and job postings indicate Salesforce experience is preferred. This is important — **they already know the platform**.

---

## 2. Education Cloud Data Schema Overview

Education Cloud is built on the **Education Data Architecture (EDA)** — a managed package that extends the standard Salesforce data model with education-specific objects. Here's the complete schema landscape:

### Account Model (EDA-Specific)

In EDA, the Account object uses **record types** to distinguish between:

| Record Type | Purpose | CEA CAPA Equivalent |
|-------------|---------|---------------------|
| **Academic Program** | University/college academic departments | Partner university departments |
| **Educational Institution** | Schools, colleges, universities | Partner institutions (375+) |
| **University Department** | Subdivisions within institutions | Study Abroad Offices, Registrar |
| **Household** | Family/guardian grouping | Student households |
| **Business Organization** | Standard companies | CEA CAPA itself, employers for internships |
| **Sports Organization** | Athletics | N/A |

### Contact Model

EDA uses a **1-Contact-to-1-Account** model (unlike standard SF where contacts share accounts). Each Contact has their own individual Account plus **Affiliations** to institutional Accounts.

For CEA CAPA:
- **Students** = Contacts affiliated with their home university AND with CEA CAPA programs
- **University Staff** (Study Abroad Directors, etc.) = Contacts affiliated with the institution
- **CEA CAPA Staff** = Internal users

### Core EDA Objects

| Object | API Name | Description | CEA CAPA Relevance |
|--------|----------|-------------|-------------------|
| **Affiliation** | `hed__Affiliation__c` | Links Contact to Account (student→university) | Track which students belong to which partner universities |
| **Program** | `Program` | Degree or educational program | CEA CAPA program offerings (Barcelona semester, London internship, etc.) |
| **Program Enrollment** | `LearnerProgram` | Student enrolled in a program | Student enrolled in a CEA CAPA program |
| **Course Offering** | `CourseOffering` | Specific course instance in a term | CEA CAPA course sections |
| **Course Connection** | `CourseOfferingParticipant` | Links student to a course offering | Student registered in a specific CEA CAPA course |
| **Term** | `hed__Term__c` | Academic term (Fall, Spring, Summer) | Program session dates |
| **Application** | `IndividualApplication` | Student application record | CEA CAPA program application |
| **Application Review** | `ApplicationReview` | Review/decision on application | Admissions decisions |

### Extended Education Cloud Objects

| Object | API Name | Description | CEA CAPA Relevance |
|--------|----------|-------------|-------------------|
| **Learning Program** | `LearningProgram` | Structured learning program | Maps to CEA CAPA's 6 program types |
| **Learning Program Plan** | `LearningProgramPlan` | Program curriculum/plan | Semester course plans per destination |
| **Learning Course** | `LearningCourse` | Course definition | Master course catalog |
| **Learning Pathway** | `LearningPathway` | Guided learning path | Pre-Health track, Pre-Law track |
| **Learning Equivalency** | `LearningEquivalency` | Credit transfer mapping | **Critical** — maps CEA CAPA courses to home university credit |
| **Person Education** | `PersonEducation` | Educational history | Student's home institution details |
| **Person Employment** | `PersonEmployment` | Employment records | Internship placement tracking |
| **Person Examination** | `PersonExamination` | Test/exam records | Assessment results |
| **Educational Institution Offering** | `EducInstitutionOffering` | What institutions offer | Programs available at each CEA CAPA destination |
| **Action Plan Template** | `ActionPlanTemplate` | Guided process template | Pre-departure checklists, visa workflows |
| **Document Checklist Item** | `DocumentChecklistItem` | Required document tracking | Passport, visa, insurance, transcripts |
| **Award** | `Award` | Scholarships/grants | CEA CAPA's $2M+ annual scholarship pool |
| **Benefit Assignment** | `BenefitAssignment` | Financial aid allocation | Scholarship/grant awards to students |
| **Benefit Disbursement** | `BenefitDisbursement` | Payment tracking | Scholarship payouts |
| **Waitlist** | `Waitlist` | Program waitlist | Oversubscribed program sessions |
| **Contact Profile** | `ContactProfile` | Extended contact data | Student profiles |
| **Goal Assignment** | `GoalAssignment` | Learning goals | Student learning objectives |

### Standard Objects (Still Present in Education Cloud)

These standard Salesforce objects are **fully available** in Education Cloud:

| Object | CEA CAPA Use |
|--------|-------------|
| **Account** | Partner universities, CEA CAPA destinations, employer accounts |
| **Contact** | Students, university staff, CEA CAPA contacts |
| **Opportunity** | Partnership deals, program enrollments as revenue |
| **Case** | Student support cases, partner institution issues |
| **Event** | Meetings with university partners, campus visits, orientations |
| **Task** | Follow-ups, action items from meetings |
| **Lead** | Prospective university partners, prospective students |
| **Campaign** | Recruitment campaigns, campus events |
| **Activity** | All logged activities (calls, emails, meetings) |

---

## 3. Meeting Command Center Architecture

### What It Does

Meeting Command Center is an AI-powered meeting productivity suite built as a Salesforce LWC. It provides:

1. **Daily Meeting Dashboard** — See all your meetings for any date, with related Account/Contact context
2. **Meeting Prep Intelligence** — AI-generated pre-meeting briefs with account research, talking points, competitive intelligence, and attendee profiles
3. **Meeting Recap** — Post-meeting AI summarization from voice notes or text input, producing structured outcomes, next steps, and recommended actions
4. **Agentforce Integration** — GenAiFunction for autonomous meeting prep generation

### Objects Used by Meeting Command Center

| Object | API Name | Fields Used | Purpose |
|--------|----------|-------------|---------|
| **Event** | `Event` | Subject, StartDateTime, EndDateTime, Location, Description, WhatId, WhoId, OwnerId, DurationInMinutes | Core meeting record |
| **Account** | `Account` | Name, Industry, Type, AnnualRevenue, NumberOfEmployees, Website, Description, Phone, OwnerId, BillingAddress, Rating | Account context for prep |
| **Contact** | `Contact` | FirstName, LastName, Title, Email, Phone, AccountId, Department, MailingAddress | Attendee info |
| **Opportunity** | `Opportunity` | Name, Amount, StageName, CloseDate, Probability, NextStep, Type, Description | Deal context |
| **Case** | `Case` | Subject, Status, Priority, Description, AccountId, ContactId | Support context |
| **Task** | `Task` | Subject, Status, Priority, ActivityDate, WhatId, WhoId, Description | Open action items |
| **Meeting_Prep__c** | `Meeting_Prep__c` | Event__c, Generated_Date__c, Prep_Brief_HTML__c, Attendee_Summary__c, Key_Talking_Points__c, Competitive_Intelligence__c, Potential_Objections__c, Questions_To_Ask__c, Recent_Updates__c | AI-generated prep brief |
| **Meeting_Recap__c** | `Meeting_Recap__c` | Event__c, Original_Recap_Text__c, AI_Meeting_Summary__c, AI_Key_Outcomes__c, AI_Next_Steps__c, Recap_Completed__c | AI-structured recap |
| **Activity** (custom fields) | `Activity` | Recap_Completed__c, AI_Meeting_Summary__c, AI_Key_Outcomes__c, AI_Next_Steps__c | Recap data on the Event itself |
| **Tavily_API_Config__mdt** | Custom Metadata | API_Key__c | Web research API key for account intel |
| **Deepgram_API_Config__mdt** | Custom Metadata | API_Key__c | Voice transcription API key |

### External Service Dependencies

| Service | Purpose | Required? |
|---------|---------|-----------|
| **Salesforce Models API** | AI summarization (xgen-salesforce model) | Yes — core AI engine |
| **Tavily API** | Real-time web research for account intelligence | Optional — enriches prep briefs |
| **Deepgram API** | Voice-to-text transcription for meeting recaps | Optional — can use text input instead |

---

## 4. Schema Compatibility Matrix

### Will Meeting Command Center Work in Education Cloud?

**Yes.** Here's why:

Meeting Command Center operates entirely on **standard Salesforce objects** (Event, Account, Contact, Opportunity, Case, Task) plus two **custom objects** (Meeting_Prep__c, Meeting_Recap__c) that we deploy ourselves. Education Cloud doesn't remove or fundamentally alter these standard objects — it adds EDA objects alongside them.

| MCC Object | Education Cloud Status | Compatibility | Notes |
|------------|----------------------|---------------|-------|
| Event | Standard — fully available | **Full** | No changes needed |
| Account | Standard — extended with EDA record types | **Full** | Works with any Account record type |
| Contact | Standard — extended with EDA model | **Full** | 1:1 Account model doesn't affect MCC |
| Opportunity | Standard — fully available | **Full** | May not be used for student enrollment; used for partnership deals |
| Case | Standard — fully available | **Full** | Student support cases work as-is |
| Task | Standard — fully available | **Full** | No changes needed |
| Meeting_Prep__c | Custom — we deploy it | **Full** | No conflicts |
| Meeting_Recap__c | Custom — we deploy it | **Full** | No conflicts |
| Activity custom fields | Custom — we deploy them | **Full** | No conflicts |

### Potential EDA-Specific Considerations

| Consideration | Risk | Mitigation |
|--------------|------|------------|
| Account record types (Academic vs. Business) | Low — MCC queries Account generically | MCC displays Account.Name regardless of record type |
| 1:1 Contact-Account model | None — MCC queries Contact.AccountId | Works identically |
| EDA triggers/flows | Low — EDA doesn't trigger on Event or custom objects | Test in sandbox first |
| Sharing model differences | Low — MCC uses `with sharing` | Respects org sharing rules |
| Managed package namespace (`hed__`) | None — MCC doesn't query EDA objects | No namespace conflicts |
| Custom metadata (Tavily/Deepgram) | None — independent custom metadata | No conflicts |
| Models API availability | Verify — needs Einstein AI enabled | Confirm license in customer org |

---

## 5. Use Cases for CEA CAPA

### Use Case 1: Regional Director Meeting Prep for University Pitches

**Persona:** Regional Director, Institutional Relations
**Scenario:** Preparing for a campus visit to pitch CEA CAPA affiliate partnership to a new university

**Before Meeting Command Center:**
- Manually researches the university's existing study abroad offerings
- Checks CRM for past interactions, open opportunities
- Reviews competitor programs the university currently uses (CIEE, IES Abroad, API)
- Builds talking points from scratch in a Google Doc

**With Meeting Command Center:**
- Opens the command center, sees today's campus visit on the calendar
- Clicks "Generate Prep" — AI pulls:
  - **Account intel**: University enrollment size, academic focus areas, existing international programs (via Tavily web research)
  - **CRM context**: Past meetings, open opportunities, any prior partnership discussions
  - **Attendee profiles**: Study Abroad Director's title, contact history, previous conversations
  - **Talking points**: AI-generated based on university profile and CEA CAPA's matching programs
  - **Competitive intelligence**: What programs the university currently sends students to
  - **Objection handling**: Common concerns (credit transfer, liability, cost, safety protocols)

**Value statement:** *"Your Regional Directors walk into every campus meeting fully briefed in 30 seconds instead of 30 minutes."*

---

### Use Case 2: Post-Meeting Recap After University Partner Check-In

**Persona:** Regional Director or Account Executive
**Scenario:** Just finished a quarterly check-in with an existing partner university's Study Abroad Office

**Before Meeting Command Center:**
- Types scattered notes into Salesforce activity
- Forgets key action items
- Follow-up tasks fall through the cracks
- No structured way to track meeting outcomes across the team

**With Meeting Command Center:**
- Opens the recap modal immediately after the meeting
- Dictates meeting notes via voice (Deepgram transcription) or types quick notes
- AI structures the raw input into:
  - **Summary**: "Discussed expanding partnership to include summer pre-health program in Barcelona. Study abroad director expressed interest in custom faculty-led option for nursing students. Enrollment pipeline looks strong for Fall 2026."
  - **Key Outcomes**: Partnership renewal confirmed, new program interest identified, student feedback shared
  - **Next Steps**: Send pre-health program proposal by March 20, connect CEA CAPA academic team with nursing department chair, share updated scholarship info
  - **Recommended Actions**: Auto-generates follow-up Tasks and Events in Salesforce

**Value statement:** *"Every meeting produces a structured, actionable record that the entire team can reference — no notes get lost, no follow-ups get dropped."*

---

### Use Case 3: Selling Custom Programs to Private Universities & Colleges

**Persona:** Senior Regional Director
**Scenario:** Meeting with a private liberal arts college to pitch a custom faculty-led program

**The story for CEA CAPA sellers:**

Private colleges and smaller institutions have specific pain points:
- **Limited study abroad staff** — often just 1-2 people running the entire international office
- **Need for differentiation** — private colleges compete on experiential learning and "transformative experiences"
- **Faculty engagement** — professors want to lead short-term programs but lack logistics infrastructure
- **Liability concerns** — smaller institutions worry about risk exposure for international travel
- **Financial constraints** — smaller student populations mean lower tuition revenue per program

**Meeting Prep Intelligence generates:**
- College's current study abroad participation rates (from NAFSA/IIE data via Tavily)
- Their stated strategic plan priorities (globalization, experiential learning)
- Which competitor providers they currently use
- Talking points tailored to small-college pain points

**After the meeting, Recap captures:**
- Faculty disciplines interested in leading programs
- Budget parameters discussed
- Timeline for program launch
- Specific destinations and program types of interest
- Decision-makers and approval process at the institution

---

### Use Case 4: Managing the Post-Acquisition Portfolio Expansion

**Persona:** VP of Partnerships / Senior Leadership
**Scenario:** After acquiring CIS Abroad, CISaustralia, and Barcelona SAE (July 2025), CEA CAPA needs to consolidate partner relationships and cross-sell expanded offerings to existing partners

**Meeting Command Center value:**
- Regional Directors now represent **3x the program portfolio** — Meeting Prep ensures they know the full catalog
- AI prep briefs include: "This university previously partnered with CIS Abroad for Australia programs. Now that CIS is part of CEA CAPA, discuss consolidated partnership and expanded European options."
- Recap tracks which partners have been briefed on the expanded portfolio and their interest level
- Leadership can review AI-structured recaps across the team to gauge acquisition integration progress

---

### Use Case 5: Scholarship & Financial Aid Coordination

**Persona:** Institutional Relations Manager
**Scenario:** Meeting with a university's Financial Aid office to streamline scholarship and aid transfer processes

**Meeting Prep generates:**
- CEA CAPA's $2M+ annual scholarship/grant pool details
- The specific university's financial aid policies (from web research)
- Past scholarship utilization data from CRM
- Questions to ask about consortium agreements, Title IV eligibility

**Recap captures:**
- Financial aid transfer process requirements
- Consortium agreement status and next steps
- Timeline for paperwork completion
- Specific scholarship programs the university wants to promote

---

### Use Case 6: Pre-Health / Pre-Law Program Specialized Pitches

**Persona:** Regional Director with specialized program focus
**Scenario:** Meeting with a university's pre-med advisory committee or pre-law faculty

**Meeting Prep generates:**
- University's pre-health/pre-law program size and competitiveness
- Clinical placement or legal shadowing opportunities at relevant CEA CAPA destinations
- Competitor pre-health abroad programs and their limitations
- Talking points on accreditation, credit transfer for science courses, clinical hours recognition

**Recap captures:**
- Specific clinical/legal requirements the university needs met
- Faculty champions who support the program
- Curriculum alignment requirements
- Student volume projections

---

### Use Case 7: Conference & Event Follow-Up (NAFSA, Forum)

**Persona:** Entire Institutional Relations team
**Scenario:** CEA CAPA attends NAFSA or Forum on Education Abroad conference, meets dozens of university contacts

**Meeting Command Center value:**
- After each conference conversation, Regional Directors open the recap modal and capture notes immediately
- AI structures raw notes into consistent, searchable format
- Follow-up tasks auto-generated for each conversation
- Leadership reviews all conference meetings in one dashboard the next day
- No conference leads fall through the cracks

---

## 6. Talk Track & Demo Script

### Opening (2 minutes)

> "You know how before every campus visit, your team spends 20-30 minutes pulling up the university's profile, checking past notes, reviewing what programs they're already using? And then after the meeting, half the notes end up in someone's notebook and the follow-ups don't get logged until Friday?
>
> Meeting Command Center eliminates both problems. It's an AI-powered meeting productivity layer that lives right inside Salesforce — right where your team already works. Before the meeting, it generates a comprehensive prep brief. After the meeting, it structures your notes into actionable outcomes. All in your CRM, all searchable, all visible to your team."

### Demo Flow (10 minutes)

**1. Daily Calendar View (2 min)**
- Show today's meetings — campus visits, partner calls, internal syncs
- Point out the Account/Contact context visible for each meeting
- "Your Regional Directors see their entire day at a glance with all the context they need."

**2. Meeting Prep Generation (4 min)**
- Click "Generate Prep" on a university partner meeting
- Walk through the generated brief:
  - Account research: "See how it pulled the university's enrollment data, their strategic priorities, and their existing study abroad partnerships?"
  - Attendee summary: "It knows who you're meeting — their title, your conversation history, their hot buttons"
  - Talking points: "These are tailored to this specific university based on your CRM data and web research"
  - Objection handling: "It anticipates the pushback — credit transfer concerns, cost, safety protocols"
  - Questions to ask: "Smart questions that show you've done your homework"
- "This took 15 seconds. Previously this was a 30-minute manual process."

**3. Meeting Recap (4 min)**
- After the "meeting," open the recap modal
- Either dictate via voice or type quick notes
- Submit and show the AI-structured output:
  - Clean summary paragraph
  - Bulleted key outcomes
  - Specific next steps with owners and dates
  - Recommended follow-up actions
- "Now your entire team can see what happened in this meeting. No notes lost. No follow-ups dropped."
- Show how it appears on the Event record and the Meeting_Recap__c record

### Closing / Value Props (3 minutes)

**For CEA CAPA specifically, emphasize:**

1. **Scale** — "You have 375+ university partners and growing. After the CIS/CISaustralia acquisition, your Regional Directors are managing significantly more relationships. This tool helps them stay prepared and organized at scale."

2. **Consistency** — "Every meeting gets documented the same way. When a Regional Director leaves or transfers territories, their successor has a complete, AI-structured record of every partner interaction."

3. **Speed** — "Your sellers spend more time selling and less time prepping and logging. For a team of Regional Directors doing 5-10 campus meetings a week, that's hours back every week."

4. **Intelligence** — "The prep briefs aren't just CRM data — they include real-time web research. If a university just announced a new international programs initiative, your team knows about it before they walk in."

5. **Accountability** — "Leadership gets visibility into meeting outcomes across the entire team. You can see which partners have been briefed on the expanded portfolio, which deals are stalling, and where follow-ups are overdue."

---

## 7. Deployment Checklist

### Pre-Deployment Verification

- [ ] **Einstein AI / Models API** — Confirm CEA CAPA's Education Cloud org has Einstein AI features enabled (required for AI summarization). Check for `sfdc_copilot__Einstein_GPT_*` permission sets.
- [ ] **API Access** — Verify Salesforce Models API is available (`/services/data/vXX.0/einstein/llm/` endpoint)
- [ ] **Custom Object Limits** — Confirm org has capacity for 2 custom objects (Meeting_Prep__c, Meeting_Recap__c) and custom fields on Activity
- [ ] **Remote Site Settings** — Add Tavily API and Deepgram API endpoints if using web research and voice transcription
- [ ] **Custom Metadata** — Create `Tavily_API_Config__mdt` and `Deepgram_API_Config__mdt` records with customer's own API keys

### Deployment Steps

1. **Deploy metadata** via `sf project deploy start` or Metadata API
2. **Assign permission set** `Meeting_Command_Center_Access` to target users
3. **Add FlexiPage** to relevant Lightning app(s) — likely their internal CRM app
4. **Configure Custom Metadata** — Insert API keys for Tavily and Deepgram
5. **Test in sandbox first** — Verify no conflicts with EDA triggers/flows
6. **Validate Activity custom fields** — Ensure Recap_Completed__c, AI_Meeting_Summary__c, AI_Key_Outcomes__c, AI_Next_Steps__c deploy cleanly on the Activity object

### Education Cloud-Specific Deployment Notes

| Item | Action |
|------|--------|
| **Account Record Types** | No changes needed — MCC works with all record types. Events linked to Educational Institution accounts will show institution name in the meeting dashboard. |
| **EDA Managed Package** | No conflicts — MCC doesn't query `hed__` namespaced objects |
| **Sharing Rules** | MCC uses `with sharing` — inherits org's sharing model. Verify Regional Directors can see their partner university Account records. |
| **EDA Triggers** | Test that EDA auto-creation triggers don't fire unexpectedly when MCC creates Events or Tasks via recommended actions |
| **Flow Conflicts** | Check for any org-specific flows on Event, Task, or Account that might conflict |

### Post-Deployment Validation

- [ ] Create a test Event linked to a university Account
- [ ] Generate a Meeting Prep brief — verify Tavily web research returns results
- [ ] Submit a Meeting Recap — verify AI summarization works
- [ ] Verify Meeting_Prep__c and Meeting_Recap__c records are created
- [ ] Verify Activity custom fields populate on the Event
- [ ] Test voice transcription (if Deepgram configured)
- [ ] Confirm no EDA trigger conflicts

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Models API not enabled** in Education Cloud license | Medium | Blocker | Verify Einstein AI licensing before committing to deployment date. May need add-on license. |
| **EDA flows/triggers conflict** with MCC Event or Task creation | Low | Medium | Deploy to sandbox first. Test all MCC workflows. |
| **Tavily/Deepgram API costs** surprise the customer | Low | Low | Both are optional. Tavily has a free tier. Deepgram can be skipped (text input works). |
| **Account data quality** — university records may be sparse | Medium | Medium | MCC still works with minimal Account data. Prep briefs rely more on Tavily web research than CRM fields. |
| **User adoption** — Regional Directors may not use it | Medium | High | Demo during team meeting, get champion buy-in from a top-performing RD. Show time savings. |
| **Credit transfer / EDA-specific data** not surfaced in MCC | Low | Low | MCC doesn't display EDA objects. This is a **future enhancement** opportunity, not a current gap. |
| **SDO-specific flows** (like `SDO Service - Case - On Create`) | N/A | N/A | Only affects SDO orgs. Customer's Education Cloud org won't have these. |

### Future Enhancement Opportunities

If the deployment goes well, here are natural expansion opportunities:

1. **Surface EDA data in Meeting Prep** — Pull Program Enrollment, Course Connection, and Affiliation data into prep briefs so RDs see exactly which programs a partner university's students are enrolled in
2. **Application pipeline integration** — Show pending student applications from the partner university in the prep brief
3. **Scholarship/Award context** — Include scholarship utilization data in meeting prep for financial aid meetings
4. **Credit transfer tracking** — Surface LearningEquivalency data to prep RDs for academic affairs meetings
5. **Student success metrics** — Pull Student Success Hub data into prep briefs to show partner universities their students' outcomes
6. **Conference mode** — Rapid-fire recap entry optimized for back-to-back conference meetings at NAFSA/Forum

---

## Appendix: Education Cloud Object Quick Reference

### EDA (Managed Package) Objects — `hed__` Namespace

```
hed__Affiliation__c          — Contact ↔ Account relationship
hed__Application__c          — Student application
hed__Course__c               — Course definition
hed__Course_Enrollment__c    — Student ↔ Course link (Course Connection)
hed__Course_Offering__c      — Specific course instance in a term
hed__Program_Enrollment__c   — Student ↔ Program link
hed__Program_Plan__c         — Program curriculum requirements
hed__Term__c                 — Academic term
hed__Relationship__c         — Contact ↔ Contact relationship
hed__Address__c              — Address records
hed__Trigger_Handler__c      — EDA automation configuration
```

### Education Cloud Platform Objects (No Namespace)

```
Program                      — Program definition
LearnerProgram              — Learner enrolled in program
LearningCourse              — Course in learning context
LearningProgram             — Structured learning program
LearningEquivalency         — Credit transfer mapping
CourseOffering              — Course offering (platform version)
CourseOfferingParticipant   — Student in course offering
IndividualApplication       — Application record
ApplicationReview           — Application decision
PersonEducation             — Educational history
PersonEmployment            — Employment records
Award                       — Scholarship/grant
BenefitAssignment           — Financial aid allocation
DocumentChecklistItem       — Required document tracking
ActionPlanTemplate          — Guided process template
Waitlist                    — Program waitlist
```

### Meeting Command Center Custom Objects

```
Meeting_Prep__c             — AI-generated meeting preparation brief
  └── Event__c (Lookup → Event)
  └── Prep_Brief_HTML__c (Long Text Area)
  └── Generated_Date__c (DateTime)
  └── Attendee_Summary__c (Long Text Area)
  └── Key_Talking_Points__c (Long Text Area)
  └── Competitive_Intelligence__c (Long Text Area)
  └── Potential_Objections__c (Long Text Area)
  └── Questions_To_Ask__c (Long Text Area)
  └── Recent_Updates__c (Long Text Area)

Meeting_Recap__c            — AI-structured meeting recap
  └── Event__c (Lookup → Event)
  └── Original_Recap_Text__c (Long Text Area)
  └── AI_Meeting_Summary__c (Long Text Area)
  └── AI_Key_Outcomes__c (Long Text Area)
  └── AI_Next_Steps__c (Long Text Area)
  └── Recap_Completed__c (Checkbox)

Activity (custom fields)    — Recap data stamped on Event
  └── Recap_Completed__c (Checkbox)
  └── AI_Meeting_Summary__c (Long Text Area)
  └── AI_Key_Outcomes__c (Long Text Area)
  └── AI_Next_Steps__c (Long Text Area)
```

---

*Document generated March 2026. Sources: CEA CAPA website, Salesforce Education Cloud Developer Guide (Spring '26, v66.0), Salesforce EDA documentation, LeadIQ company profiles, BusinessWire press releases.*
