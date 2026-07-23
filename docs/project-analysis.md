# Project Analysis: Salesforce Bank CRM Take-Home Assignment

**Source:** `project_task.md`  
**Scope of this document:** Requirements analysis only. No solution design.

---

## 1. Executive Summary

A leading bank needs a Salesforce CRM to manage customers and loan requests. The assignment spans five parts:

| Part | Focus |
|------|--------|
| A | System design & architecture (data model, security, external integration) |
| B | Apex trigger on `LoanRequest__c` (high-value Task, approval email, audit) |
| C | Automated Flow on loan status change (customer status, manager notify, audit) |
| D | LWC loan request form with Apex save and cross-component communication |
| E | Unit tests, performance considerations, and ≥90% Apex code coverage |

Core business objects are `Customer__c` and `LoanRequest__c`. Supporting artifacts include `Audit__c`, Tasks for manager notification when loan amount exceeds ₪250,000, and customer status updates tied to loan approval/rejection. Deliverables include Apex, Flow (with screenshot and short explanation), LWCs, tests, and documentation in `.txt` or `.docx` format.

---

## 2. Functional Requirements

### Part A – System Design & Architecture

1. Design a data model for the bank CRM, including objects, fields, and relationships.
2. Represent bank customers using the `Customer__c` object.
3. Represent loan requests using the `LoanRequest__c` object, associated with a customer.
4. Notify a manager whenever a loan amount exceeds ₪250,000.
5. Record all relevant events in an Audit Log.
6. Describe security mechanisms to protect sensitive data and enforce access permissions.
7. Explain how to integrate with an external loan approval system.

### Part B – Apex Trigger on LoanRequest__c

8. Implement an Apex Trigger on `LoanRequest__c` that runs on create and update.
9. If `LoanAmount__c` is greater than ₪250,000, create a Task assigned to the bank manager.
10. If loan status changes to `"Approved"`, send an email notification to the customer confirming approval.
11. Whenever loan status changes, create an `Audit__c` record containing loan request details and the customer’s name.
12. Support bulk operations (bulkification).
13. Properly handle exceptions in the Apex implementation.
14. Explain how the code would be efficient, scalable, and production-ready.

### Part C – Flow for Loan Request Management

15. Create an automated Flow that runs whenever `LoanStatus__c` changes.
16. If the request is Approved, update `Customer__c.Status__c` to `"Active Customer"`.
17. If the request is Rejected, update `Customer__c.Status__c` to `"Requires Additional Review"`.
18. If the loan amount exceeds ₪250,000, send an automatic notification to the manager and create an `Audit__c` record.
19. Build the Flow with Decision elements and proper exception handling.
20. Include a screenshot of the completed Flow showing structure and connections between elements/decision branches.
21. Provide a short document explaining the main Flow steps.

### Part D – LWC Development

22. Create a loan request form allowing entry of Customer Name, Loan Amount, and Loan Status.
23. Provide a Save button that submits data to create a `LoanRequest__c` record in Salesforce.
24. Send form data to Salesforce through an Apex controller on Save.
25. Implement an Apex class that receives data from the LWC, creates a `LoanRequest__c` record, and stores it.
26. Component A displays the form and, after Save, sends entered data to Component B.
27. Component B receives data from Component A and displays Customer Name, Loan Amount, and Loan Status.
28. Component A and Component B must not share a common parent component.
29. After saving, reload the latest data from Salesforce.
30. Component B must display updated information retrieved from Salesforce after save/reload.
31. Ensure a clean, intuitive UI including all required fields.
32. Display a loading spinner while processing or saving data.
33. Provide documentation describing code structure and implementation challenges encountered.

### Part E – Testing & Optimization

34. Write unit tests verifying a Task is created when loan amount exceeds ₪250,000.
35. Write unit tests verifying customer status is updated to `"Active Customer"` when a loan request is approved.
36. Write unit tests verifying data is correctly passed between LWC components.
37. Write unit tests verifying handling of incomplete or invalid input data.
38. Explain performance improvements for large data volumes, covering Batch Apex, SOQL governor limits, and database indexing.
39. Achieve at least 90% Apex code coverage through unit tests.

### Submission / Packaging

40. Submit Apex code, Flow, and LWC components in `.txt` or `.docx` format (per submission guidelines).
41. Submit Flow screenshot and brief Flow steps document.
42. Submit complete source code for both LWC components plus a concise explanation of structure and logic.

---

## 3. Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-1 | Scalability / bulk | Apex must support bulk operations (bulkification). |
| NFR-2 | Reliability | Apex must properly handle exceptions. |
| NFR-3 | Production readiness | Implementation should be efficient, scalable, and production-ready (explained). |
| NFR-4 | Flow quality | Flow should use optimal design with Decision elements and exception handling. |
| NFR-5 | UX | Interface must be clean and intuitive; required fields present. |
| NFR-6 | UX feedback | Loading spinner during processing/saving. |
| NFR-7 | Security | Protect sensitive data and enforce access permissions (described in Part A). |
| NFR-8 | Performance (large volume) | Address Batch Apex, SOQL governor limits, and database indexing. |
| NFR-9 | Test coverage | Minimum 90% Apex code coverage. |
| NFR-10 | Deliverable format | Submission in `.txt` or `.docx`; screenshots and short docs as specified. |
| NFR-11 | Architecture documentation | Data model, security, and external integration must be explained (Part A). |

---

## 4. Salesforce Features Required

| Feature area | How it appears in the assignment |
|--------------|----------------------------------|
| **Custom Objects** | `Customer__c`, `LoanRequest__c`, `Audit__c` |
| **Standard Objects** | `Task` (manager notification); likely `User` for manager assignment (implied) |
| **Fields / Relationships** | Data model design; `LoanAmount__c`, `LoanStatus__c`, `Status__c`; customer–loan association |
| **Apex Triggers** | Trigger on `LoanRequest__c` (insert/update) |
| **Apex Classes** | Trigger handler logic; LWC Apex controller; email sending; possibly helper/service classes |
| **Apex Email** | Email to customer on approval |
| **Flow (Automated)** | Record-triggered (or equivalent) Flow on `LoanStatus__c` change |
| **Flow Decision elements** | Explicitly required |
| **Flow fault / exception handling** | Explicitly required |
| **Lightning Web Components (LWC)** | Form component (A) and display component (B) |
| **LWC–Apex integration** | `@AuraEnabled` (or equivalent) controller for create |
| **LWC component communication** | Cross-component messaging without a shared parent |
| **Lightning UI / UX** | Form fields, Save, spinner |
| **Security** | Access permissions and sensitive-data protection (design description) |
| **Integration** | External loan approval system (design explanation) |
| **Unit Testing (Apex)** | Coverage ≥90%; tests for Task, customer status, invalid input |
| **LWC Testing** | Tests that data is passed between components (method not specified) |
| **Performance concepts** | Batch Apex, SOQL limits, indexing (explanation) |
| **Audit logging** | `Audit__c` records for status changes / high-amount events |

---

## 5. Objects Mentioned

### Explicitly named

| Object | Role in assignment |
|--------|-------------------|
| `Customer__c` | Bank customer; `Status__c` updated by Flow on approve/reject |
| `LoanRequest__c` | Loan request associated with a customer; primary trigger/Flow/LWC target |
| `Audit__c` | Audit log records for status changes and (in Flow) high-amount events |
| `Task` | Created for bank manager when loan amount > ₪250,000 |

### Implied / referenced but not named as Salesforce objects

| Concept | Notes |
|---------|--------|
| Bank manager | Recipient of Task and notifications; no `Manager__c` object named |
| External loan approval system | Integration target in Part A; not a Salesforce object |
| Email / customer contact channel | Needed to email customer on approval; no Email object named |
| Audit Log | Described as a capability; implemented via `Audit__c` |

### Fields explicitly named

| Field | Object (stated or strongly implied) |
|-------|-------------------------------------|
| `LoanAmount__c` | `LoanRequest__c` |
| `LoanStatus__c` | `LoanRequest__c` |
| `Status__c` | `Customer__c` |

### Values / labels explicitly named

- Loan status: `"Approved"`, `"Rejected"` (and form allows entering Loan Status generally)
- Customer status: `"Active Customer"`, `"Requires Additional Review"`
- Threshold: ₪250,000

### Data concepts required but not given API names

- Customer Name (form field; also stored on audit with “customer’s name”)
- Loan request details (content of `Audit__c`)
- Relationship field linking `LoanRequest__c` to `Customer__c`
- Manager identity / assignment target for Task and notifications
- Customer email (or other address) for approval notification

---

## 6. Automations Required

| # | Automation | Trigger / event | Actions |
|---|------------|-----------------|---------|
| A1 | Apex Trigger on `LoanRequest__c` | Create or update | If amount > ₪250,000 → create Task for manager; if status changes to Approved → email customer; if status changes → create `Audit__c` with loan details + customer name |
| A2 | Automated Flow | Whenever `LoanStatus__c` changes | Approved → set Customer `Status__c` = `"Active Customer"`; Rejected → set Customer `Status__c` = `"Requires Additional Review"`; if amount > ₪250,000 → notify manager + create `Audit__c` |
| A3 | LWC Save → Apex create | User clicks Save | Create `LoanRequest__c` via Apex controller; then refresh from Salesforce and update Component B |

**Note (analysis only):** A1 and A2 both address high-amount manager notification and `Audit__c` creation under overlapping but not identical conditions. Overlap and sequencing are an ambiguity for implementation (see §8).

---

## 7. Integrations and External Dependencies

| # | Dependency | Where stated | Nature |
|---|------------|--------------|--------|
| I1 | External loan approval system | Part A | Design/explain integration; no API/protocol/auth details given |
| I2 | Email delivery to customer | Part B | Send approval confirmation email; platform = Salesforce email capabilities (implied) |
| I3 | Manager notification channel (Flow) | Part C | “Automatic notification” — channel not specified (Task, email, bell, Chatter, etc.) |
| I4 | Currency / locale (₪) | Throughout | Israeli Shekel threshold; may imply org locale/currency config |

No third-party product names, endpoints, middleware, or auth schemes are specified.

---

## 8. Ambiguities and Missing Requirements

### Overlapping / conflicting behavior

1. **Duplicate high-amount handling:** Part B Apex creates a Task when amount > ₪250,000; Part C Flow also notifies the manager and creates `Audit__c` when amount > ₪250,000 on status change. Unclear whether both should fire, one should own the behavior, or conditions differ by design.
2. **Duplicate / divergent audit creation:** Apex creates `Audit__c` on any status change; Flow creates `Audit__c` when amount > ₪250,000 on status change. Unclear if two audits are expected, or if scopes should be mutually exclusive.
3. **Part A vs Parts B–C:** Part A says notify manager and record audit for high amounts; Parts B and C implement overlapping pieces differently (Task vs “notification”; always-on status audit vs high-amount audit).

### Missing object / field definitions

4. No full field list for `Customer__c`, `LoanRequest__c`, or `Audit__c`.
5. No specified relationship type or API name between customer and loan request (lookup vs master-detail; required vs optional).
6. How LWC “Customer Name” maps to a customer record is undefined (free text vs lookup vs create/find customer).
7. Customer email address field for approval emails is not specified.
8. `Audit__c` field schema (“loan request details”) is not specified.
9. Manager identification is undefined (named user, queue, custom field, role, Custom Setting/Metadata).

### Process / status gaps

10. Full set of allowed `LoanStatus__c` values is not defined (only Approved/Rejected called out).
11. Whether status can change more than once, and whether re-approval re-sends email / re-updates customer status, is unspecified.
12. Behavior when amount is exactly ₪250,000 is clear (`>` only), but currency type (Number vs Currency) and multi-currency are not stated.
13. Part C Flow runs “whenever status changes” but also checks amount > ₪250,000 — unclear if that amount branch should run only on status change (as written) or also when amount alone changes.
14. Part B Task creation is on create/update whenever amount > ₪250,000 — unclear if Task should be created only once or on every qualifying update.

### LWC / communication gaps

15. Mechanism for Component A ↔ B communication without a shared parent is required but not prescribed (Lightning Message Service, pub/sub, etc.).
16. Whether the form creates only `LoanRequest__c` or also relates/creates `Customer__c` is unclear.
17. “Reload latest data from Salesforce” — query criteria, which fields, and whether Component B binds to Id vs name are unspecified.
18. How to unit-test LWC component communication (Jest vs Apex-only vs manual) is not specified, despite Part E requiring verification.

### Security / integration gaps

19. Which data is “sensitive” and which personas/profiles exist are not defined.
20. External loan approval system: no SLA, payload, sync vs async, error handling, or which Salesforce events should call out.
21. Org edition, sharing model, and whether Experience Cloud / guest users apply are not mentioned.

### Testing / scoring gaps

22. Part E tests customer status update on approval (Flow behavior) — unclear if Flow must be tested via Apex, or if deployment of Flow is assumed.
23. “Incomplete or invalid input” rules (required fields, min/max amount, allowed statuses) are not defined.
24. Submission guidelines repeat “Flow” and mix formats; exact packaging expectations are slightly unclear.
25. Point weighting is only stated for Part E (20 points); other parts have no explicit weights in the provided text.

---

## 9. Assumptions Needed During Implementation

The following assumptions would need to be made (or clarified with the reviewer) before building. They are **not** solution designs—only placeholders the assignment forces.

1. **Data model completeness:** Custom fields and relationship API names beyond those explicitly listed will need to be defined to make Apex, Flow, and LWC runnable.
2. **Customer–loan link:** A relationship from `LoanRequest__c` to `Customer__c` will be assumed so association and customer name/status updates are possible.
3. **Customer Name resolution:** The LWC form’s Customer Name will need a defined mapping (e.g., match existing customer, store text field, or both).
4. **Manager target:** A concrete assignee for Tasks/notifications (specific User, Queue, or configurable Id) will be assumed.
5. **Customer email source:** A field or related contact email will be assumed for approval emails.
6. **Status picklist values:** At least `Approved` and `Rejected` (and any values the form allows) will be assumed as controlled values.
7. **Audit__c shape:** Fields sufficient to store “loan request details” and customer name will be assumed.
8. **Overlap strategy (Apex vs Flow):** An explicit rule will be needed for whether Apex and Flow both run for high-amount notify/audit, or how responsibilities are split—because the assignment states both.
9. **Task idempotency:** Whether repeated updates with amount still > ₪250,000 create additional Tasks will need an assumed rule.
10. **Email vs Flow “notification”:** Flow “automatic notification” may be assumed as email, Task, custom notification, or another channel unless clarified.
11. **LWC messaging:** A Salesforce-supported cross-component channel that works without a shared parent will be assumed (e.g., LMS).
12. **Post-save refresh:** After insert, re-query by new record Id (or equivalent) will be assumed for Component B.
13. **Security model:** Profiles/permission sets, FLS, CRUD/FLS in Apex, and sharing for financial data will be assumed at a level appropriate for a bank CRM demo.
14. **External integration:** A plausible pattern (e.g., callout + auth + async handling) will be assumed for the Part A write-up without a real vendor API.
15. **Currency:** Amounts treated as ILS numeric comparisons against 250000; org currency settings assumed compatible.
16. **Testing approach:** Apex tests cover trigger/controller/domain logic; LWC communication tests may use Jest (or documented manual/proof approach) if Apex cannot fully verify UI messaging.
17. **Flow testing for Part E:** Verifying customer status on approval may assume Flow is active in the test org, or that equivalent automation is testable end-to-end.
18. **Bulk & limits:** Production-ready explanations will assume standard governor-limit and bulk patterns expected in Salesforce interviews.
19. **Deliverable packaging:** Code and docs will be exported into `.txt`/`.docx` (and screenshots) even if developed in a Salesforce DX project.
20. **Coverage:** All Apex written for the assignment is in scope for the 90% coverage requirement.

---

## Document Control

| Item | Value |
|------|--------|
| Analysis type | Requirements extraction only |
| Solution design | Intentionally excluded |
| Code | Intentionally excluded |
|
