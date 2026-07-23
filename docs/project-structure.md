# Bank CRM Salesforce Project Structure

**Platform:** Salesforce DX source format  
**Sources:** `project_task.md` and all design documents in `docs/`  
**Scope:** Complete repository and metadata organization. This document defines locations and responsibilities only; it contains no implementation code.

---

## 1. Structure Principles

- Use the standard Salesforce DX layout under `force-app/main/default`.
- Keep deployable Salesforce metadata separate from project documentation, environment configuration, manifests, and test tooling.
- Use one trigger on `LoanRequest__c`; all trigger behavior delegates to Apex classes.
- Keep Apex classes in Salesforce's required flat `classes` directory. Architectural layers are expressed through names and this catalog, not unsupported physical subfolders.
- Keep each LWC in its own bundle and place Jest tests inside that bundle's `__tests__` directory.
- Keep each object decomposed into fields, validation rules, record types, and list views so changes remain reviewable.
- Use permission sets and permission set groups for business access. Profiles remain minimal and provide only login/session/application baselines.
- Store policy in Custom Metadata, user-facing text in Custom Labels, and secrets in Named/External Credentials.
- Do not store generated artifacts, credentials, access tokens, org-specific record IDs, or Flow screenshots in deployable metadata.

---

## 2. Top-Level Repository

```text
bankHW/
├── .forceignore
├── .gitignore
├── README.md
├── sfdx-project.json
├── package.json
├── jest.config.js
├── project_task.md
├── config/
│   └── project-scratch-def.json
├── manifest/
│   ├── package.xml
│   └── destructiveChangesPre.xml
├── docs/
│   ├── project-analysis.md
│   ├── system-design.md
│   ├── data-model.md
│   ├── apex-design.md
│   ├── flow-design.md
│   ├── lwc-design.md
│   ├── testing-strategy.md
│   ├── project-structure.md
│   ├── flow/
│   │   ├── loan-request-status-flow.md
│   │   ├── loan-request-status-flow-simplification.md
│   │   └── loan-request-status-flow.png
│   └── submission/
│       └── README.md
├── scripts/
│   ├── apex/
│   └── soql/
└── force-app/
    ├── main/
    │   └── default/
    └── test/
        └── default/
```

### Why these locations exist

| Location | Purpose |
|---|---|
| `sfdx-project.json` | Declares package directories, source API version, and project identity. |
| `.forceignore` | Excludes non-deployable files from Salesforce source operations. |
| `.gitignore` | Excludes local auth, tool caches, coverage output, and generated files from source control. |
| `package.json`, `jest.config.js` | Own LWC Jest commands and test configuration. |
| `config/project-scratch-def.json` | Defines scratch-org features and settings such as Lightning Experience and optional multi-currency. It must contain no credentials. |
| `manifest/package.xml` | Provides an explicit complete deployment/retrieval manifest. |
| `manifest/destructiveChangesPre.xml` | Reserved for reviewed metadata removals; it should normally remain empty. |
| `docs/` | Holds design, Flow explanation, screenshot, and submission packaging guidance. Flow screenshots belong here, not in Static Resources. |
| `scripts/apex`, `scripts/soql` | Optional administrator smoke-test and diagnostic scripts; they are not production classes. |
| `force-app/main/default` | Contains deployable production metadata. |
| `force-app/test/default` | Contains Apex test-only classes in a separate package directory so production packaging can exclude them while CI can deploy both directories. |

`force-app/test` must be declared as a second package directory in `sfdx-project.json`. If the target deployment process requires tests beside production code, the same test files may instead live in `force-app/main/default/classes`; do not duplicate them in both locations.

---

## 3. Production Metadata Tree

```text
force-app/main/default/
├── applications/
├── classes/
├── customMetadata/
├── customNotificationTypes/
├── customPermissions/
├── experiences/                         # reserved; no baseline metadata
├── externalCredentials/
├── flexipages/
├── flows/
├── labels/
├── layouts/
├── lwc/
├── messageChannels/
├── namedCredentials/
├── objects/
├── permissionsetgroups/
├── permissionsets/
├── profiles/
├── queues/
├── sharingRules/
├── staticresources/
├── tabs/
└── triggers/
```

Only metadata required by the design should be committed. Reserved directories may be omitted from Git until they contain a real asset.

---

## 4. Apex Classes

Every Apex implementation has a paired `<ClassName>.cls-meta.xml` file in the same directory. Salesforce requires all classes to be physically flat under `classes/`.

### 4.1 Entry points and controllers

```text
force-app/main/default/classes/
├── LoanRequestController.cls
├── LoanRequestController.cls-meta.xml
├── LoanRequestReadController.cls
├── LoanRequestReadController.cls-meta.xml
├── ApprovalCallbackRestResource.cls
└── ApprovalCallbackRestResource.cls-meta.xml
```

| Class | Why it exists |
|---|---|
| `LoanRequestController` | `with sharing` LWC save endpoint. Validates a restricted DTO, enforces CRUD/FLS, inserts the loan, and returns record/correlation IDs. |
| `LoanRequestReadController` | `with sharing`, cacheable read endpoint used when LDS is insufficient. Returns only customer name, amount, and status. |
| `ApprovalCallbackRestResource` | Authenticated REST boundary for external approval decisions. It parses a minimal request and delegates all business work. |

### 4.2 Trigger orchestration and domain services

```text
force-app/main/default/classes/
├── LoanRequestTriggerHandler.cls
├── LoanRequestTriggerHandler.cls-meta.xml
├── LoanRequestDomainService.cls
├── LoanRequestDomainService.cls-meta.xml
├── LoanRequestValidationService.cls
├── LoanRequestValidationService.cls-meta.xml
├── ManagerTaskService.cls
├── ManagerTaskService.cls-meta.xml
├── CustomerEmailService.cls
├── CustomerEmailService.cls-meta.xml
├── AuditService.cls
├── AuditService.cls-meta.xml
├── ApplicationErrorService.cls
├── ApplicationErrorService.cls-meta.xml
├── LoanApprovalIntegrationOrchestrator.cls
├── LoanApprovalIntegrationOrchestrator.cls-meta.xml
├── ApprovalCallbackService.cls
└── ApprovalCallbackService.cls-meta.xml
```

| Class | Why it exists |
|---|---|
| `LoanRequestTriggerHandler` | Converts trigger context into bulk before/after phases and delegates once. |
| `LoanRequestDomainService` | Coordinates threshold crossings, status audits, email jobs, and integration enqueue decisions. |
| `LoanRequestValidationService` | Enforces lifecycle, cross-object, protected-field, and LWC input rules in bulk. |
| `ManagerTaskService` | Creates one high-value Task per threshold crossing and maintains the durable marker. |
| `CustomerEmailService` | Plans and sends approval confirmations without owning loan status decisions. |
| `AuditService` | Creates Apex-owned `STATUS_CHANGED`, `APPROVAL_EMAIL_SENT`, and integration audit events. |
| `ApplicationErrorService` | Normalizes, sanitizes, persists, and classifies operational failures. |
| `LoanApprovalIntegrationOrchestrator` | Owns outbound eligibility, technical state, retries, and integration-result audits. |
| `ApprovalCallbackService` | Authenticates, deduplicates, validates, and applies inbound decisions through normal loan DML. |

### 4.3 Repository and configuration classes

```text
force-app/main/default/classes/
├── LoanRequestRepository.cls
├── LoanRequestRepository.cls-meta.xml
├── CustomerRepository.cls
├── CustomerRepository.cls-meta.xml
├── AuditRepository.cls
├── AuditRepository.cls-meta.xml
├── TaskRepository.cls
├── TaskRepository.cls-meta.xml
├── ApplicationErrorRepository.cls
├── ApplicationErrorRepository.cls-meta.xml
├── BankCrmSettingsProvider.cls
└── BankCrmSettingsProvider.cls-meta.xml
```

| Class | Why it exists |
|---|---|
| `LoanRequestRepository` | Centralizes selective loan queries and user/system-mode DML boundaries. |
| `CustomerRepository` | Bulk-loads only customer fields needed by validation, routing, email, and DTO mapping. |
| `AuditRepository` | Provides append-only bulk insertion; no normal update/delete API. |
| `TaskRepository` | Isolates mandatory bulk Task insertion. |
| `ApplicationErrorRepository` | Persists error lifecycle data and retrieves due retries. |
| `BankCrmSettingsProvider` | Loads and caches the `Default` Custom Metadata record once per transaction. |

### 4.4 Asynchronous processing

```text
force-app/main/default/classes/
├── LoanApprovalCalloutQueueable.cls
├── LoanApprovalCalloutQueueable.cls-meta.xml
├── CustomerApprovalEmailQueueable.cls
├── CustomerApprovalEmailQueueable.cls-meta.xml
├── LoanApprovalReconciliationBatch.cls
├── LoanApprovalReconciliationBatch.cls-meta.xml
├── LoanApprovalReconciliationScheduler.cls
└── LoanApprovalReconciliationScheduler.cls-meta.xml
```

| Class | Why it exists |
|---|---|
| `LoanApprovalCalloutQueueable` | Performs Named Credential callouts only after the originating transaction commits. |
| `CustomerApprovalEmailQueueable` | Sends approval emails post-commit so email limits cannot roll back mandatory business state. |
| `LoanApprovalReconciliationBatch` | Processes large, selective sets of aged Pending/Retry Pending loans. |
| `LoanApprovalReconciliationScheduler` | Starts reconciliation on an operations-approved schedule without embedding scheduling in the batch. |

### 4.5 Domain contracts, plans, utilities, and exceptions

```text
force-app/main/default/classes/
├── LoanRequestChange.cls
├── LoanRequestChange.cls-meta.xml
├── DomainExecutionContext.cls
├── DomainExecutionContext.cls-meta.xml
├── AuditEventDto.cls
├── AuditEventDto.cls-meta.xml
├── LoanRequestDto.cls
├── LoanRequestDto.cls-meta.xml
├── SaveResultDto.cls
├── SaveResultDto.cls-meta.xml
├── ValidationFailure.cls
├── ValidationFailure.cls-meta.xml
├── TaskPlan.cls
├── TaskPlan.cls-meta.xml
├── EmailPlan.cls
├── EmailPlan.cls-meta.xml
├── BankCrmSettings.cls
├── BankCrmSettings.cls-meta.xml
├── LoanApprovalIntegrationContracts.cls
├── LoanApprovalIntegrationContracts.cls-meta.xml
├── CorrelationIdUtil.cls
├── CorrelationIdUtil.cls-meta.xml
├── CurrencyThresholdUtil.cls
├── CurrencyThresholdUtil.cls-meta.xml
├── EmailMessageBuilder.cls
├── EmailMessageBuilder.cls-meta.xml
├── EmailGateway.cls
├── EmailGateway.cls-meta.xml
├── UserRoutingResolver.cls
├── UserRoutingResolver.cls-meta.xml
├── SanitizedMessageUtil.cls
├── SanitizedMessageUtil.cls-meta.xml
├── ApexSecurityHelper.cls
├── ApexSecurityHelper.cls-meta.xml
├── BankCrmException.cls
└── BankCrmException.cls-meta.xml
```

| Class | Why it exists |
|---|---|
| `LoanRequestChange` | Immutable old/new loan snapshot with status and threshold predicates. |
| `DomainExecutionContext` | Carries actor, correlation ID, source, and settings through services. |
| `AuditEventDto` | Normalizes an audit event before mapping to `Audit__c`. |
| `LoanRequestDto` | Restricts LWC input/output to approved loan fields. |
| `SaveResultDto` | Stable LWC save response containing success, IDs, and structured failures. |
| `ValidationFailure` | User-safe field-level validation contract. |
| `TaskPlan`, `EmailPlan` | Collect side effects before one bulk commit/send. |
| `BankCrmSettings` | Immutable runtime representation of the Custom Metadata policy. |
| `LoanApprovalIntegrationContracts` | Contains request, response, and callback value types as inner classes so vendor payload contracts stay together. |
| `CorrelationIdUtil` | Generates and propagates trace identifiers. |
| `CurrencyThresholdUtil` | Centralizes strict `>` threshold and crossing semantics. |
| `EmailMessageBuilder` | Builds approval messages without mixing message formatting with domain decisions. |
| `EmailGateway` | Small Messaging API boundary that makes success/failure behavior testable. |
| `UserRoutingResolver` | Resolves active relationship managers and metadata-configured fallbacks in bulk. |
| `SanitizedMessageUtil` | Redacts and truncates text before audit/error persistence. |
| `ApexSecurityHelper` | Centralizes CRUD/FLS checks and inaccessible-field stripping. |
| `BankCrmException` | Public base exception with inner `ValidationException`, `AuthorizationException`, `MandatoryAutomationException`, and `IntegrationException` types. |

`LoanApprovalIntegrationContracts` and `BankCrmException` intentionally group tightly coupled inner types. Creating one file per tiny payload or exception subtype would add metadata noise without creating an independent architectural responsibility.

---

## 5. Trigger

```text
force-app/main/default/triggers/
├── LoanRequestTrigger.trigger
└── LoanRequestTrigger.trigger-meta.xml
```

`LoanRequestTrigger` is the only custom trigger. It runs before insert, before update, after insert, and after update on `LoanRequest__c`, then delegates immediately to `LoanRequestTriggerHandler`. No trigger is created for `Customer__c`, `Audit__c`, or `Application_Error__c` because their required behavior is already owned by Flow/services and audit/error records must not introduce recursive automation.

---

## 6. Lightning Web Components and Message Channel

```text
force-app/main/default/lwc/
├── loanRequestForm/
│   ├── loanRequestForm.html
│   ├── loanRequestForm.js
│   ├── loanRequestForm.css
│   ├── loanRequestForm.js-meta.xml
│   └── __tests__/
│       └── loanRequestForm.test.js
└── loanRequestSummary/
    ├── loanRequestSummary.html
    ├── loanRequestSummary.js
    ├── loanRequestSummary.css
    ├── loanRequestSummary.js-meta.xml
    └── __tests__/
        └── loanRequestSummary.test.js

force-app/main/default/messageChannels/
└── Loan_Request_Message_Channel.messageChannel-meta.xml
```

| Bundle/file | Why it exists |
|---|---|
| `loanRequestForm.html` | Defines customer lookup, amount, status, Save, validation, and spinner presentation. |
| `loanRequestForm.js` | Owns local state, client validation, imperative Apex save, and successful LMS publication. |
| `loanRequestForm.css` | Contains only bundle-specific SLDS-compatible adjustments. |
| `loanRequestForm.js-meta.xml` | Exposes the component independently to Lightning App Builder. |
| `loanRequestForm.test.js` | Verifies validation, spinner, duplicate-submit prevention, Apex contract, and ID-only LMS publication. |
| `loanRequestSummary.html` | Defines empty, loading, populated, and reload-error states. |
| `loanRequestSummary.js` | Subscribes/unsubscribes to LMS and reloads authoritative Salesforce data by ID. |
| `loanRequestSummary.css` | Contains only summary-specific presentation adjustments. |
| `loanRequestSummary.js-meta.xml` | Exposes the summary independently; it does not depend on a wrapper component. |
| `loanRequestSummary.test.js` | Verifies subscription, ID handoff, Salesforce reload, retry, and teardown. |
| `Loan_Request_Message_Channel.messageChannel-meta.xml` | Defines the decoupled `loanRequestId`, `correlationId`, and optional `action` message contract. |

No shared parent LWC is created. Optional presentational child bundles should be added only if either root becomes materially complex; they must stay private to their own root.

---

## 7. Flows

```text
force-app/main/default/flows/
├── Loan_Request_Status_Changed.flow-meta.xml
├── Loan_Request_Flow_Fault_Handler.flow-meta.xml
└── Resolve_Bank_CRM_Settings.flow-meta.xml
```

| Flow | Why it exists |
|---|---|
| `Loan_Request_Status_Changed` | After-save, update-only record-triggered Flow on `LoanRequest__c` when `LoanStatus__c` changes. It updates customer status, sends the high-value custom notification, and creates `HIGH_VALUE_STATUS_REVIEW`. |
| `Loan_Request_Flow_Fault_Handler` | Reusable autolaunched subflow that writes sanitized `Application_Error__c` records and avoids recursive fault handling. |
| `Resolve_Bank_CRM_Settings` | Autolaunched subflow that reads the `Default` `Bank_CRM_Settings__mdt` record and exposes threshold/routing outputs. |

Flow version history is represented inside Salesforce metadata rather than by filenames such as `Flow_v2`. Git history and release tags provide source history; API names remain stable across deployments.

---

## 8. Custom Objects and Fields

Each object root file defines label, plural label, name field, deployment status, sharing model, search status, and other object-level settings. Each field or validation rule has its own source-format file.

### 8.1 `Customer__c`

```text
force-app/main/default/objects/Customer__c/
├── Customer__c.object-meta.xml
├── fields/
│   ├── CustomerNumber__c.field-meta.xml
│   ├── Email__c.field-meta.xml
│   ├── Status__c.field-meta.xml
│   ├── RelationshipManager__c.field-meta.xml
│   ├── NationalIdentifier__c.field-meta.xml
│   └── IsActive__c.field-meta.xml
├── validationRules/
│   ├── Customer_Number_Format.validationRule-meta.xml
│   ├── Active_Status_Consistency.validationRule-meta.xml
│   └── National_Identifier_Format.validationRule-meta.xml
├── listViews/
│   ├── Active_Customers.listView-meta.xml
│   └── Requires_Additional_Review.listView-meta.xml
└── recordTypes/
    └── Bank_Customer.recordType-meta.xml
```

The object root uses `Private` sharing. The fields implement the verified customer key, email destination, controlled CRM status, manager routing, protected identifier, and active flag defined by the data model. A single record type is included only when the org needs persona-specific picklist assignment; otherwise omit it and use the master record type.

### 8.2 `LoanRequest__c`

```text
force-app/main/default/objects/LoanRequest__c/
├── LoanRequest__c.object-meta.xml
├── fields/
│   ├── Customer__c.field-meta.xml
│   ├── LoanAmount__c.field-meta.xml
│   ├── LoanStatus__c.field-meta.xml
│   ├── SubmissionDate__c.field-meta.xml
│   ├── ExternalRequestId__c.field-meta.xml
│   ├── ExternalDecisionReference__c.field-meta.xml
│   ├── IntegrationStatus__c.field-meta.xml
│   ├── IntegrationLastAttempt__c.field-meta.xml
│   ├── HighValueTaskCreated__c.field-meta.xml
│   └── DecisionReason__c.field-meta.xml
├── validationRules/
│   ├── Loan_Amount_Must_Be_Positive.validationRule-meta.xml
│   ├── Submission_Prerequisites.validationRule-meta.xml
│   ├── Submission_Timestamp_Required.validationRule-meta.xml
│   ├── Rejection_Reason_Required.validationRule-meta.xml
│   └── Integration_State_Consistency.validationRule-meta.xml
├── listViews/
│   ├── Draft_Loans.listView-meta.xml
│   ├── Submitted_Loans.listView-meta.xml
│   ├── High_Value_Open_Loans.listView-meta.xml
│   └── Integration_Exceptions.listView-meta.xml
└── recordTypes/
    └── Bank_Loan_Request.recordType-meta.xml
```

The object root uses an auto-number Name and `Private` sharing. Complex transition rules and protected integration-field edits remain in `LoanRequestValidationService`; they should not be duplicated as brittle formulas. The relationship to `Customer__c` is a required lookup, not master-detail, to preserve retained financial history.

### 8.3 `Audit__c`

```text
force-app/main/default/objects/Audit__c/
├── Audit__c.object-meta.xml
├── fields/
│   ├── LoanRequest__c.field-meta.xml
│   ├── Customer__c.field-meta.xml
│   ├── EventType__c.field-meta.xml
│   ├── OldValue__c.field-meta.xml
│   ├── NewValue__c.field-meta.xml
│   ├── CustomerNameSnapshot__c.field-meta.xml
│   ├── LoanAmountSnapshot__c.field-meta.xml
│   ├── OccurredAt__c.field-meta.xml
│   ├── ActorUser__c.field-meta.xml
│   ├── CorrelationId__c.field-meta.xml
│   ├── Source__c.field-meta.xml
│   └── Details__c.field-meta.xml
├── validationRules/
│   ├── Loan_Required_For_Business_Event.validationRule-meta.xml
│   ├── Status_Transition_Values_Required.validationRule-meta.xml
│   └── Audit_Source_Event_Consistency.validationRule-meta.xml
└── listViews/
    ├── Recent_Audit_Events.listView-meta.xml
    └── Integration_Audit_Events.listView-meta.xml
```

The object uses an auto-number Name and `Private` sharing. It has lookup relationships so audit evidence survives parent lifecycle changes. No ordinary profile or business permission set receives update/delete access.

### 8.4 `Application_Error__c`

```text
force-app/main/default/objects/Application_Error__c/
├── Application_Error__c.object-meta.xml
├── fields/
│   ├── SourceComponent__c.field-meta.xml
│   ├── Operation__c.field-meta.xml
│   ├── LoanRequest__c.field-meta.xml
│   ├── Customer__c.field-meta.xml
│   ├── CorrelationId__c.field-meta.xml
│   ├── OccurredAt__c.field-meta.xml
│   ├── Category__c.field-meta.xml
│   ├── IsRetryable__c.field-meta.xml
│   ├── AttemptCount__c.field-meta.xml
│   ├── NextRetryAt__c.field-meta.xml
│   ├── SanitizedMessage__c.field-meta.xml
│   ├── StackFingerprint__c.field-meta.xml
│   ├── ResolutionStatus__c.field-meta.xml
│   └── ResolvedAt__c.field-meta.xml
├── validationRules/
│   ├── Retry_State_Consistency.validationRule-meta.xml
│   ├── Attempt_Count_Nonnegative.validationRule-meta.xml
│   └── Resolution_State_Consistency.validationRule-meta.xml
└── listViews/
    ├── Open_Application_Errors.listView-meta.xml
    └── Due_Retries.listView-meta.xml
```

This object is separate from immutable business audits because support users must update retry and resolution fields. It uses `Private` sharing and queue ownership.

### 8.5 `Bank_CRM_Settings__mdt`

```text
force-app/main/default/objects/Bank_CRM_Settings__mdt/
├── Bank_CRM_Settings__mdt.object-meta.xml
└── fields/
    ├── HighValueThreshold__c.field-meta.xml
    ├── DefaultManagerUsername__c.field-meta.xml
    ├── DefaultQueueDeveloperName__c.field-meta.xml
    ├── ManagerNotificationType__c.field-meta.xml
    ├── RetryLimit__c.field-meta.xml
    ├── IntegrationEnabled__c.field-meta.xml
    └── RetryBaseDelayMinutes__c.field-meta.xml

force-app/main/default/customMetadata/
└── Bank_CRM_Settings.Default.md-meta.xml
```

The type defines deployable policy fields. The `Default` record provides the stable lookup key. Environment-specific non-secret values may be transformed during deployment; secrets and OAuth material never belong here.

### 8.6 Standard-object extensions

```text
force-app/main/default/objects/Task/
├── fields/
│   └── HighValueDisposition__c.field-meta.xml
└── validationRules/
    └── High_Value_Task_Completeness.validationRule-meta.xml
```

`HighValueDisposition__c` is included only if the bank requires a closure disposition. The validation rule applies only to Tasks classified as high-value loan review. Standard fields `WhatId`, `OwnerId`, `Status`, `Priority`, `ActivityDate`, `Subject`, `Description`, and optional standard `Type` are reused rather than duplicated.

---

## 9. Security Metadata

### 9.1 Permission sets

```text
force-app/main/default/permissionsets/
├── Bank_CRM_Base.permissionset-meta.xml
├── Bank_CRM_Loan_Officer.permissionset-meta.xml
├── Bank_CRM_Relationship_Manager.permissionset-meta.xml
├── Bank_CRM_Approver.permissionset-meta.xml
├── Bank_CRM_Compliance_Auditor.permissionset-meta.xml
├── Bank_CRM_Integration_User.permissionset-meta.xml
├── Bank_CRM_Support_Operator.permissionset-meta.xml
└── Bank_CRM_Restricted_Data.permissionset-meta.xml
```

| Permission set | Access intent |
|---|---|
| `Bank_CRM_Base` | App/tab access and least-privilege read access shared by authenticated bank CRM users. |
| `Bank_CRM_Loan_Officer` | Create/read permitted customers and loans; update ordinary loan fields; execute LWC controllers; no audit mutation or integration-field access. |
| `Bank_CRM_Relationship_Manager` | Read assigned customers/loans, manage escalation Tasks, and receive notifications. |
| `Bank_CRM_Approver` | Update permitted decision/status fields and read required underwriting context. |
| `Bank_CRM_Compliance_Auditor` | Read-only access to loans and immutable audit records, including compliance list views. |
| `Bank_CRM_Integration_User` | API/Apex/REST and narrowly scoped integration-field access; no interactive banking UI. |
| `Bank_CRM_Support_Operator` | Read operational context and update `Application_Error__c` retry/resolution fields. |
| `Bank_CRM_Restricted_Data` | Separately approved access to encrypted national identifier, customer email, and decision reason. |

### 9.2 Permission set groups

```text
force-app/main/default/permissionsetgroups/
├── Bank_CRM_Loan_Operations.permissionsetgroup-meta.xml
├── Bank_CRM_Management.permissionsetgroup-meta.xml
├── Bank_CRM_Compliance.permissionsetgroup-meta.xml
└── Bank_CRM_Support.permissionsetgroup-meta.xml
```

Groups compose the base and persona permissions. Restricted-data access remains a separate assignment and is not automatically included merely because a user has a business role.

### 9.3 Profiles

```text
force-app/main/default/profiles/
├── Bank CRM Minimum Access.profile-meta.xml
└── Bank CRM API Only.profile-meta.xml
```

`Bank CRM Minimum Access` supplies the smallest interactive login/session baseline; `Bank CRM API Only` supplies the non-interactive integration baseline. Business object, field, class, tab, and app permissions belong in permission sets so access is composable and reviewable. Standard Salesforce profiles should not be copied into the repository.

### 9.4 Sharing and custom permissions

```text
force-app/main/default/sharingRules/
├── Customer__c.sharingRules-meta.xml
├── LoanRequest__c.sharingRules-meta.xml
├── Audit__c.sharingRules-meta.xml
└── Application_Error__c.sharingRules-meta.xml

force-app/main/default/customPermissions/
├── Edit_Bank_CRM_Integration_Fields.customPermission-meta.xml
├── Reopen_Final_Loan_Decision.customPermission-meta.xml
└── Manage_Bank_CRM_Retention.customPermission-meta.xml

force-app/main/default/queues/
├── Bank_CRM_Default_Manager.queue-meta.xml
└── Bank_CRM_Operations_Support.queue-meta.xml
```

Object roots set OWD to Private. Sharing rules grant only documented manager, approval-team, compliance, and support access. Custom permissions replace profile-name checks in Apex/validation logic for protected integration edits, exceptional reopening, and controlled retention.

`Bank_CRM_Default_Manager` is the fallback owner for high-value Tasks when no active relationship manager is available. `Bank_CRM_Operations_Support` owns unresolved application errors and exhausted retries. Queue membership is environment-managed unless stable public groups are also deployed; user IDs are never committed.

---

## 10. User-Facing Labels

```text
force-app/main/default/labels/
└── CustomLabels.labels-meta.xml
```

The label file should contain, at minimum:

- `Bank_CRM_High_Value_Task_Subject`
- `Bank_CRM_High_Value_Task_Description`
- `Bank_CRM_Approval_Email_Subject`
- `Bank_CRM_Approval_Email_Body`
- `Bank_CRM_Save_Success`
- `Bank_CRM_Generic_Save_Error`
- `Bank_CRM_Access_Denied`
- `Bank_CRM_Summary_Empty`
- `Bank_CRM_Summary_Load_Error`
- `Bank_CRM_Notification_Title`
- `Bank_CRM_Notification_Body`

Labels hold translatable, user-visible text used by Apex, Flow, and LWC. API names, picklist values, policy thresholds, routing keys, and credentials do not belong in labels.

---

## 11. Integration and Notification Metadata

```text
force-app/main/default/externalCredentials/
└── Bank_Loan_Approval.externalCredential-meta.xml

force-app/main/default/namedCredentials/
└── Bank_Loan_Approval.namedCredential-meta.xml

force-app/main/default/customNotificationTypes/
└── High_Value_Loan_Review.notiftype-meta.xml
```

| File | Why it exists |
|---|---|
| `Bank_Loan_Approval.externalCredential-meta.xml` | Defines the authentication protocol and principals without committing secret values. Principal assignment is restricted to the integration permission set. |
| `Bank_Loan_Approval.namedCredential-meta.xml` | Defines the HTTPS callout endpoint and binds it to the External Credential. No Remote Site Setting is needed. |
| `High_Value_Loan_Review.notiftype-meta.xml` | Defines the Lightning bell notification type resolved by the Flow through its developer name. |

Environment endpoint URLs and secret material must be provisioned through the deployment platform or org administration. Callback authentication configuration must use platform identity/credential controls, not Custom Labels, Static Resources, or Apex constants.

---

## 12. App, Pages, Tabs, and Layouts

```text
force-app/main/default/applications/
└── Bank_CRM.app-meta.xml

force-app/main/default/flexipages/
├── Bank_CRM_Home.flexipage-meta.xml
├── Customer_Record_Page.flexipage-meta.xml
└── Loan_Request_Record_Page.flexipage-meta.xml

force-app/main/default/tabs/
├── Customer__c.tab-meta.xml
├── LoanRequest__c.tab-meta.xml
├── Audit__c.tab-meta.xml
└── Application_Error__c.tab-meta.xml

force-app/main/default/layouts/
├── Customer__c-Bank Customer Layout.layout-meta.xml
├── LoanRequest__c-Bank Loan Request Layout.layout-meta.xml
├── Audit__c-Bank Audit Layout.layout-meta.xml
├── Application_Error__c-Bank Application Error Layout.layout-meta.xml
└── Task-High Value Loan Task Layout.layout-meta.xml
```

`Bank_CRM_Home` places `loanRequestForm` and `loanRequestSummary` in independent App Builder regions; it does not introduce a shared LWC parent. Record pages expose related loans, Tasks, audits, and operational context according to permissions. Layouts organize fields for administrators and fallback UI, but FLS remains the security boundary.

The Audit and Application Error tabs are hidden by default and exposed only through compliance/support permission sets.

---

## 13. Static Resources

```text
force-app/main/default/staticresources/
└── (empty; omit this directory until an approved resource exists)
```

No Static Resource is required by the baseline solution. Standard Lightning base components and SLDS provide the required UI, and Flow screenshots are documentation artifacts under `docs/flow`.

If the bank later approves branded, non-sensitive assets, add:

```text
force-app/main/default/staticresources/
├── BankCrmBranding.resource-meta.xml
└── BankCrmBranding.zip
```

The archive may contain approved images/fonts only. It must not contain JavaScript libraries unless security review establishes a real requirement, and it must never contain configuration, customer data, credentials, or integration payload samples.

---

## 14. Apex Test Structure

Every Apex test class has a paired `.cls-meta.xml` file under `force-app/test/default/classes/`.

```text
force-app/test/default/classes/
├── BankCrmTestDataFactory.cls
├── CurrencyThresholdUtilTest.cls
├── CorrelationIdUtilTest.cls
├── SanitizedMessageUtilTest.cls
├── LoanRequestChangeTest.cls
├── BankCrmSettingsProviderTest.cls
├── UserRoutingResolverTest.cls
├── ApexSecurityHelperTest.cls
├── LoanRequestValidationServiceTest.cls
├── ManagerTaskServiceTest.cls
├── AuditServiceTest.cls
├── CustomerEmailServiceTest.cls
├── ApplicationErrorServiceTest.cls
├── LoanRequestDomainServiceTest.cls
├── LoanRequestTriggerHandlerTest.cls
├── LoanRequestTriggerTest.cls
├── LoanRequestRepositoryTest.cls
├── CustomerRepositoryTest.cls
├── LoanRequestControllerTest.cls
├── LoanRequestReadControllerTest.cls
├── LoanApprovalIntegrationOrchestratorTest.cls
├── LoanApprovalCalloutQueueableTest.cls
├── ApprovalCallbackServiceTest.cls
├── ApprovalCallbackRestResourceTest.cls
├── LoanApprovalReconciliationBatchTest.cls
├── BankCrmExceptionTest.cls
├── LoanRequestBulkTest.cls
├── LoanRequestSecurityTest.cls
├── LoanRequestNegativeTest.cls
└── LoanRequestE2ETest.cls
```

Add one matching `.cls-meta.xml` beside every listed class.

### Test support

`BankCrmTestDataFactory` owns customers, users, loans, and deterministic overrides. HTTP mocks may be inner classes in the integration test classes when local to one suite; if shared by several suites, add:

```text
force-app/test/default/classes/
├── BankCrmHttpCalloutMock.cls
└── BankCrmHttpCalloutMock.cls-meta.xml
```

The suite mirrors `docs/testing-strategy.md`: unit/service tests, real-DML trigger tests, controller/security tests, callout/callback tests, 200-record bulk tests, and an optional Flow-active end-to-end test. LWC Jest tests remain inside their component bundles because Salesforce's Jest tooling discovers them there.

---

## 15. Metadata Deployment Order

Deploy in dependency order:

1. Custom objects, Custom Metadata type, fields, picklists, custom permissions, and labels.
2. External Credential, Named Credential shell, Custom Notification Type, and `Bank_CRM_Settings.Default`.
3. Apex contracts, utilities, repositories, services, async classes, controllers, and trigger.
4. Message Channel and LWC bundles.
5. Fault/settings subflows, then the main record-triggered Flow in inactive state.
6. Permission sets, groups, profiles, sharing rules, layouts, tabs, FlexiPages, and app.
7. Test package directory and all automated tests.
8. Environment-specific credential principals, routing values, queue/user records, and notification configuration.
9. Activate `Loan_Request_Status_Changed` only after dependencies and tests pass.
10. Schedule `LoanApprovalReconciliationScheduler` only after the integration endpoint is enabled and monitored.

The main Flow should not be committed as active until its dependent Apex actions, notification type, fields, settings, and permissions are deployable in the same release.

---

## 16. Metadata Ownership Map

| Requirement | Primary metadata |
|---|---|
| Manage customers and loans | `objects/Customer__c`, `objects/LoanRequest__c`, layouts, tabs, app |
| High-value Task | `LoanRequestTrigger`, handler/domain, `ManagerTaskService`, Task metadata |
| Approval email | `CustomerEmailService`, `CustomerApprovalEmailQueueable`, labels |
| Status audit | `AuditService`, `Audit__c` |
| Approved/rejected customer status | `Loan_Request_Status_Changed` Flow |
| Flow high-value notification/audit | Main Flow, Custom Notification Type, `Audit__c` |
| Flow faults | Fault subflow, `Application_Error__c` |
| LWC create and independent summary | Two LWC bundles, two controllers, LMS channel, FlexiPage |
| External approval | Named/External Credential, orchestrator, Queueable, REST resource, reconciliation classes |
| Security | Private object sharing, permission sets/groups, minimal profiles, sharing rules, custom permissions |
| Configurable policy | `Bank_CRM_Settings__mdt` and `Bank_CRM_Settings.Default` |
| ≥90% Apex coverage | `force-app/test/default/classes` suite |
| LWC communication tests | Bundle-local Jest tests |
| Flow screenshot and explanation | `docs/flow/`, never deployable metadata |

---

## 17. Files Deliberately Not Included

- No shared parent LWC, because Component A and B must communicate without one.
- No `Customer__c` or `Audit__c` trigger, because those objects have no trigger-owned behavior.
- No Flow that creates the high-value Task or `STATUS_CHANGED` audit, because Apex owns those outcomes.
- No Apex that updates customer status or writes `HIGH_VALUE_STATUS_REVIEW`, because Flow owns those outcomes.
- No Remote Site Setting, because the Named Credential owns the endpoint.
- No hard-coded secrets, user IDs, queue IDs, threshold values, or endpoint URLs in source.
- No guest/Experience Cloud metadata, because the solution is for authenticated bank users.
- No baseline Static Resource, third-party JavaScript library, Screen Flow, Scheduled Flow, or Platform Event.
- No generated coverage reports, local Salesforce auth files, build output, or org cache in source control.

This organization keeps each assignment requirement visible, preserves the Apex/Flow ownership boundary, supports independent deployment and testing, and follows Salesforce DX metadata conventions.
