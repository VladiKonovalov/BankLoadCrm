# Loan Request Status Changed Flow — Steps

**Flow API name:** `Loan_Request_Status_Changed` (F1)  
**Supporting subflows:** `Resolve_Bank_CRM_Settings` (F3), `Loan_Request_Flow_Fault_Handler` (F2)  
**Supporting Apex:** `ManagerNotificationRecipientInvocable` (User-only notification recipient)  
**Source design:** `docs/flow-design.md`  
**Simplification review:** `docs/flow/loan-request-status-flow-simplification.md`  
**Screenshot:** `docs/flow/loan-request-status-flow.png` (capture from Flow Builder after deploy; pending org access)

---

## Trigger

| Attribute | Value |
|---|---|
| Type | Record-triggered, after save |
| Object | `LoanRequest__c` |
| When | Record is **updated** |
| Entry | `LoanStatus__c` Is Changed **AND** `Customer__c` Is Null = False |
| Status in repo | **Draft / inactive** until Flow tests pass |

---

## Main steps (happy path)

1. **SUB_Resolve_Settings (F3)** — Load threshold and notification type into Flow working variables.
2. **DEC_Settings_OK** — If settings missing → fault path (fail closed). Else continue.
3. **GET_Customer** — Load customer name snapshot for the high-value audit.
4. **DEC_Loan_Status (D1)**
   - **Approved** → `UPD_Customer_Active` (`Status__c = Active Customer`)
   - **Rejected** → `UPD_Customer_Review` (`Status__c = Requires Additional Review`)
   - **Other** → skip customer update
5. **DEC_High_Value_Amount (D2)** — `LoanAmount__c` **Greater Than** configured threshold (exact 250000 is not high value).
   - **No** → end
   - **Yes** → resolve User recipient → custom notification → create audit

### High-value branch

6. **ACT_Resolve_Notification_Recipient** — Invocable `ManagerNotificationRecipientInvocable` resolves a **User** Id via Apex `UserRoutingResolver` (RM → CMDT username). Queue-only routing is treated as unresolved (custom notifications require User Ids).
7. **DEC_Recipient_Resolved** — If unresolved → notification fault path (continue to audit). Else continue.
8. Load `CustomNotificationType` by configured developer name (default `High_Value_Loan_Review`).
9. **ACT_Notify_Manager** — Send Custom Notification (title from `Bank_CRM_Notification_Title`; body includes loan name, status, amount). Target = loan Id.
10. **CRT_High_Value_Status_Audit** — Create `Audit__c` with:
    - `EventType__c = HIGH_VALUE_STATUS_REVIEW`
    - `Source__c = Flow`
    - Old/new status, customer name snapshot, amount snapshot, actor, correlation Id (`frmCorrelationId`)

---

## Fault policy

| Failure | Handling |
|---|---|
| Settings missing, customer update, high-value audit | Thin `ASG_Fault_Ctx_*` → `ASG_Fault_Mandatory` → F2 (`Category__c = Flow Fault`), then fail interview |
| Custom notification / missing notification type / unresolved recipient | Thin `ASG_Fault_Ctx_*` → `ASG_Fault_Notification` → F2 (`Category__c = Notification`), **continue**, still create `HIGH_VALUE_STATUS_REVIEW` audit |

Context assignments set only element name + message. Shared policy assignments set category and `varFailParent`, then call F2. F2 creates `Application_Error__c` with interview GUID, element name, sanitized message, and correlation Id. If error insert itself fails, F2 ends without recursion.

---

## Ownership (do not duplicate Apex)

| Concern | Owner |
|---|---|
| High-value **Task** / `HighValueTaskCreated__c` | Apex |
| `STATUS_CHANGED` audit | Apex |
| Approval email | Apex |
| Customer `Status__c` on Approve/Reject | **Flow** |
| Manager **custom notification** on high-value status change | **Flow** |
| `HIGH_VALUE_STATUS_REVIEW` audit | **Flow** |

---

## Activation checklist

1. Deploy F3 and F2 (Active).
2. Deploy F1 (Draft).
3. Run Flow Trigger Tests (see `docs/testing-strategy.md` §6 / milestone M14).
4. Activate F1 only after those tests pass.
5. Capture Builder screenshot to `docs/flow/loan-request-status-flow.png`.
