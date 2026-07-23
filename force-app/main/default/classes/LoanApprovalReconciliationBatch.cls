/**
 * Processes aged Pending / Retry Pending loans for retry or exhaustion escalation.
 */
public without sharing class LoanApprovalReconciliationBatch
    implements Database.Batchable<SObject>, Database.AllowsCallouts {
    private final Integer scopeSize;

    public LoanApprovalReconciliationBatch() {
        this(50);
    }

    public LoanApprovalReconciliationBatch(Integer scopeSize) {
        this.scopeSize = scopeSize == null || scopeSize <= 0 ? 50 : scopeSize;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        Integer baseMinutes = settings.retryBaseDelayMinutes == null
            ? 15
            : settings.retryBaseDelayMinutes;
        Datetime agedBefore = System.now().addMinutes(-baseMinutes);
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    Customer__c,
                    LoanAmount__c,
                    LoanStatus__c,
                    ExternalRequestId__c,
                    ExternalDecisionReference__c,
                    IntegrationStatus__c,
                    IntegrationLastAttempt__c,
                    DecisionReason__c,
                    OwnerId
                FROM LoanRequest__c
                WHERE IntegrationStatus__c IN ('Pending', 'Retry Pending')
                    AND IntegrationLastAttempt__c <= :agedBefore
                ORDER BY IntegrationLastAttempt__c ASC NULLS LAST
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        if (scope == null || scope.isEmpty()) {
            return;
        }
        List<LoanRequest__c> loans = new List<LoanRequest__c>();
        for (SObject row : scope) {
            loans.add((LoanRequest__c) row);
        }
        DomainExecutionContext ctx = new DomainExecutionContext(
            CorrelationIdUtil.currentOrNew(),
            UserInfo.getUserId(),
            BankCrmSettingsProvider.getSettings(),
            DomainExecutionContext.Source.INTEGRATION
        );
        LoanApprovalIntegrationOrchestrator.reconcileCandidates(loans, ctx);
    }

    public void finish(Database.BatchableContext context) {
        // No-op; operations dashboards use Application_Error__c / list views.
    }

    @TestVisible
    public Integer getScopeSize() {
        return scopeSize;
    }
}
