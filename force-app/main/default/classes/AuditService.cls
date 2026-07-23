/**
 * Creates immutable Apex-owned business audit events.
 * Never writes HIGH_VALUE_STATUS_REVIEW (Flow-owned).
 */
public with sharing class AuditService {
    private static final String EVENT_STATUS_CHANGED = 'STATUS_CHANGED';
    private static final String EVENT_APPROVAL_EMAIL_SENT = 'APPROVAL_EMAIL_SENT';
    private static final String EVENT_INTEGRATION_RESULT = 'INTEGRATION_RESULT';
    private static final String EVENT_HIGH_VALUE_STATUS_REVIEW = 'HIGH_VALUE_STATUS_REVIEW';

    private static final Set<String> ALLOWED_EVENT_TYPES = new Set<String>{
        EVENT_STATUS_CHANGED,
        EVENT_APPROVAL_EMAIL_SENT,
        EVENT_INTEGRATION_RESULT
    };

    public static List<AuditEventDto> planStatusChangeAudits(
        List<LoanRequestChange> changes,
        DomainExecutionContext ctx
    ) {
        List<AuditEventDto> events = new List<AuditEventDto>();
        if (changes == null || changes.isEmpty()) {
            return events;
        }
        DomainExecutionContext context = ctx == null
            ? DomainExecutionContext.forCurrentUser(BankCrmSettingsProvider.getSettings())
            : ctx;

        List<LoanRequestChange> statusChanges = new List<LoanRequestChange>();
        Set<Id> customerIds = new Set<Id>();
        for (LoanRequestChange change : changes) {
            if (
                change == null
                || change.isInsert
                || !change.statusChanged()
                || change.loanRequestId == null
                || String.isBlank(change.oldStatus)
                || String.isBlank(change.newStatus)
            ) {
                continue;
            }
            statusChanges.add(change);
            if (change.customerId != null) {
                customerIds.add(change.customerId);
            }
        }
        if (statusChanges.isEmpty()) {
            return events;
        }

        Map<Id, Customer__c> customersById = CustomerRepository.getMapByIds(customerIds);
        for (LoanRequestChange change : statusChanges) {
            Customer__c customer = customersById.get(change.customerId);
            String customerName = customer == null ? null : customer.Name;
            if (String.isBlank(customerName)) {
                throw new BankCrmException.MandatoryAutomationException(
                    'Unable to build STATUS_CHANGED audit without customer name for loan '
                    + change.loanRequestId
                );
            }

            AuditEventDto event = new AuditEventDto();
            event.eventType = EVENT_STATUS_CHANGED;
            event.loanRequestId = change.loanRequestId;
            event.customerId = change.customerId;
            event.oldValue = change.oldStatus;
            event.newValue = change.newStatus;
            event.customerNameSnapshot = customerName;
            event.loanAmountSnapshot = change.newAmount;
            event.occurredAt = System.now();
            event.actorUserId = context.actorUserId;
            event.correlationId = context.correlationId;
            event.source = 'Apex';
            event.details =
                'Loan status changed from '
                + change.oldStatus
                + ' to '
                + change.newStatus;
            events.add(event);
        }
        return events;
    }

    public static AuditEventDto planEvent(AuditEventDto dto) {
        if (dto == null) {
            throw new BankCrmException.ValidationException('Audit event is required.');
        }
        if (String.isBlank(dto.eventType)) {
            throw new BankCrmException.ValidationException('Audit event type is required.');
        }
        if (dto.eventType == EVENT_HIGH_VALUE_STATUS_REVIEW) {
            throw new BankCrmException.ValidationException(
                'HIGH_VALUE_STATUS_REVIEW audits are owned by Flow and must not be written by Apex.'
            );
        }
        if (!ALLOWED_EVENT_TYPES.contains(dto.eventType)) {
            throw new BankCrmException.ValidationException(
                'Unsupported Apex audit event type: ' + dto.eventType
            );
        }
        if (dto.loanRequestId == null) {
            throw new BankCrmException.ValidationException(
                'Loan request Id is required for audit events.'
            );
        }
        if (String.isBlank(dto.customerNameSnapshot)) {
            throw new BankCrmException.ValidationException(
                'Customer name snapshot is required for audit events.'
            );
        }
        if (dto.loanAmountSnapshot == null) {
            throw new BankCrmException.ValidationException(
                'Loan amount snapshot is required for audit events.'
            );
        }
        if (String.isBlank(dto.correlationId)) {
            dto.correlationId = CorrelationIdUtil.currentOrNew();
        }
        if (dto.occurredAt == null) {
            dto.occurredAt = System.now();
        }
        if (String.isBlank(dto.source)) {
            if (dto.eventType == EVENT_INTEGRATION_RESULT) {
                dto.source = 'Integration';
            } else {
                dto.source = 'Apex';
            }
        }
        if (
            dto.eventType == EVENT_STATUS_CHANGED
            && (String.isBlank(dto.oldValue)
                || String.isBlank(dto.newValue)
                || dto.oldValue == dto.newValue)
        ) {
            throw new BankCrmException.ValidationException(
                'STATUS_CHANGED audits require different old and new values.'
            );
        }
        return dto;
    }

    public static List<Database.SaveResult> commitEvents(List<AuditEventDto> events) {
        if (events == null || events.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        List<Audit__c> records = new List<Audit__c>();
        for (AuditEventDto event : events) {
            AuditEventDto validated = planEvent(event);
            records.add(validated.toSObject());
        }
        return AuditRepository.insertEvents(records);
    }
}
