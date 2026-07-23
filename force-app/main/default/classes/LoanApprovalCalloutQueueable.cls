/**
 * Performs Named Credential callouts only after the originating loan transaction commits.
 */
public without sharing class LoanApprovalCalloutQueueable implements Queueable, Database.AllowsCallouts {
    private final Set<Id> loanIds;
    private final String correlationId;

    public LoanApprovalCalloutQueueable(Set<Id> loanIds, String correlationId) {
        this.loanIds = loanIds == null ? new Set<Id>() : new Set<Id>(loanIds);
        this.correlationId = correlationId;
    }

    public void execute(QueueableContext context) {
        if (loanIds.isEmpty()) {
            return;
        }
        DomainExecutionContext ctx = new DomainExecutionContext(
            correlationId,
            UserInfo.getUserId(),
            BankCrmSettingsProvider.getSettings(),
            DomainExecutionContext.Source.INTEGRATION
        );
        CorrelationIdUtil.setCurrent(ctx.correlationId);

        List<LoanRequest__c> loans = LoanRequestRepository.getByIds(loanIds);
        LoanApprovalIntegrationOrchestrator.processOutboundBatch(loans, ctx);
    }

    @TestVisible
    public Set<Id> getLoanIds() {
        return new Set<Id>(loanIds);
    }

    @TestVisible
    public String getCorrelationId() {
        return correlationId;
    }
}
