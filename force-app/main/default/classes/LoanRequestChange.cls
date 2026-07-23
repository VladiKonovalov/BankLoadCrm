/**
 * Immutable old/new loan snapshot with status and threshold predicates.
 */
public with sharing class LoanRequestChange {
    public final Id loanRequestId;
    public final Id customerId;
    public final Decimal oldAmount;
    public final Decimal newAmount;
    public final String oldStatus;
    public final String newStatus;
    public final Boolean highValueTaskCreated;
    public final String integrationStatus;
    public final String externalRequestId;
    public final Boolean isInsert;

    private LoanRequestChange(
        Id loanRequestId,
        Id customerId,
        Decimal oldAmount,
        Decimal newAmount,
        String oldStatus,
        String newStatus,
        Boolean highValueTaskCreated,
        String integrationStatus,
        String externalRequestId,
        Boolean isInsert
    ) {
        this.loanRequestId = loanRequestId;
        this.customerId = customerId;
        this.oldAmount = oldAmount;
        this.newAmount = newAmount;
        this.oldStatus = oldStatus;
        this.newStatus = newStatus;
        this.highValueTaskCreated = highValueTaskCreated == true;
        this.integrationStatus = integrationStatus;
        this.externalRequestId = externalRequestId;
        this.isInsert = isInsert == true;
    }

    public static LoanRequestChange fromTrigger(LoanRequest__c newRecord, LoanRequest__c oldRecord) {
        if (newRecord == null) {
            throw new BankCrmException.ValidationException('New loan request record is required.');
        }
        Boolean insertContext = oldRecord == null;
        return new LoanRequestChange(
            newRecord.Id,
            newRecord.Customer__c,
            insertContext ? null : oldRecord.LoanAmount__c,
            newRecord.LoanAmount__c,
            insertContext ? null : oldRecord.LoanStatus__c,
            newRecord.LoanStatus__c,
            newRecord.HighValueTaskCreated__c,
            newRecord.IntegrationStatus__c,
            newRecord.ExternalRequestId__c,
            insertContext
        );
    }

    public static List<LoanRequestChange> fromTrigger(
        List<LoanRequest__c> newRecords,
        Map<Id, LoanRequest__c> oldMap
    ) {
        List<LoanRequestChange> changes = new List<LoanRequestChange>();
        if (newRecords == null) {
            return changes;
        }
        for (LoanRequest__c newRecord : newRecords) {
            LoanRequest__c oldRecord =
                oldMap == null || newRecord.Id == null ? null : oldMap.get(newRecord.Id);
            changes.add(fromTrigger(newRecord, oldRecord));
        }
        return changes;
    }

    public Boolean statusChanged() {
        return oldStatus != newStatus;
    }

    public Boolean crossedHighValueThreshold(Decimal threshold) {
        return CurrencyThresholdUtil.crossedThreshold(oldAmount, newAmount, threshold);
    }

    public Boolean transitionedToApproved() {
        return statusChanged() && newStatus == 'Approved';
    }

    public Boolean becameSubmitted() {
        return statusChanged() && newStatus == 'Submitted';
    }

    public Boolean isAboveThreshold(Decimal threshold) {
        return CurrencyThresholdUtil.isAboveThreshold(newAmount, threshold);
    }
}
