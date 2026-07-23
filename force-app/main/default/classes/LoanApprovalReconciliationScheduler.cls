/**
 * Starts reconciliation on an operations-approved schedule without embedding
 * cron expressions inside the batch class.
 */
public without sharing class LoanApprovalReconciliationScheduler implements Schedulable {
    public void execute(SchedulableContext context) {
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        if (settings == null || settings.integrationEnabled != true) {
            return;
        }
        Database.executeBatch(new LoanApprovalReconciliationBatch(), 50);
    }
}
