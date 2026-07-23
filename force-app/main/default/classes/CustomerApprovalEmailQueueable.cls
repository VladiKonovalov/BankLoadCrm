/**
 * Sends approval emails post-commit so email governor issues cannot roll back decisions.
 */
public class CustomerApprovalEmailQueueable implements Queueable {
    private final Set<Id> loanIds;
    private final String correlationId;

    public CustomerApprovalEmailQueueable(Set<Id> loanIds, String correlationId) {
        this.loanIds = loanIds == null ? new Set<Id>() : new Set<Id>(loanIds);
        this.correlationId = correlationId;
    }

    public void execute(QueueableContext context) {
        DomainExecutionContext ctx = new DomainExecutionContext(
            correlationId,
            UserInfo.getUserId(),
            BankCrmSettingsProvider.getSettings(),
            DomainExecutionContext.Source.APEX
        );
        CustomerEmailService.sendForLoanIds(loanIds, ctx);
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
