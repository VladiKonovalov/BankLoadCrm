/**
 * Normalized audit event before mapping to Audit__c.
 */
public with sharing class AuditEventDto {
    public String eventType;
    public Id loanRequestId;
    public Id customerId;
    public String oldValue;
    public String newValue;
    public String customerNameSnapshot;
    public Decimal loanAmountSnapshot;
    public Datetime occurredAt;
    public Id actorUserId;
    public String correlationId;
    public String source;
    public String details;

    public AuditEventDto() {
        this.occurredAt = System.now();
    }

    public Audit__c toSObject() {
        return new Audit__c(
            EventType__c = eventType,
            LoanRequest__c = loanRequestId,
            Customer__c = customerId,
            OldValue__c = oldValue,
            NewValue__c = newValue,
            CustomerNameSnapshot__c = customerNameSnapshot,
            LoanAmountSnapshot__c = loanAmountSnapshot,
            OccurredAt__c = occurredAt == null ? System.now() : occurredAt,
            ActorUser__c = actorUserId,
            CorrelationId__c = correlationId,
            Source__c = source,
            Details__c = SanitizedMessageUtil.sanitize(details)
        );
    }
}
