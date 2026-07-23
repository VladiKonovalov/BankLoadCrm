/**
 * Central domain orchestrator for loan insert/update after-save effects.
 * Approval emails and integration callouts enqueue post-commit.
 */
public with sharing class LoanRequestDomainService {
    public static void processAfterInsert(
        List<LoanRequest__c> newRecords,
        DomainExecutionContext ctx
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        List<LoanRequestChange> changes = LoanRequestChange.fromTrigger(newRecords, null);
        applyAfterSaveEffects(changes, context);
    }

    public static void processAfterUpdate(
        List<LoanRequest__c> newRecords,
        Map<Id, LoanRequest__c> oldMap,
        DomainExecutionContext ctx
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        List<LoanRequestChange> changes = LoanRequestChange.fromTrigger(newRecords, oldMap);
        List<LoanRequestChange> actionable = filterActionableUpdates(changes);
        if (actionable.isEmpty()) {
            return;
        }
        applyAfterSaveEffects(actionable, context);
    }

    private static void applyAfterSaveEffects(
        List<LoanRequestChange> changes,
        DomainExecutionContext context
    ) {
        TaskPlan taskPlan = ManagerTaskService.planHighValueTasks(changes, context.settings);
        if (!taskPlan.isEmpty()) {
            ManagerTaskService.commitTasks(taskPlan);
        }

        List<AuditEventDto> audits = AuditService.planStatusChangeAudits(changes, context);
        if (!audits.isEmpty()) {
            AuditService.commitEvents(audits);
        }

        collectDeferredWork(changes, context);
    }

    /**
     * Recursion control: act only when watched business fields changed.
     * Marker-only updates (HighValueTaskCreated__c) produce an empty actionable set.
     */
    private static List<LoanRequestChange> filterActionableUpdates(
        List<LoanRequestChange> changes
    ) {
        List<LoanRequestChange> actionable = new List<LoanRequestChange>();
        if (changes == null) {
            return actionable;
        }
        for (LoanRequestChange change : changes) {
            if (change == null || change.isInsert) {
                continue;
            }
            Boolean amountChanged = change.oldAmount != change.newAmount;
            Boolean statusChanged = change.statusChanged();
            if (amountChanged || statusChanged) {
                actionable.add(change);
            }
        }
        return actionable;
    }

    private static void collectDeferredWork(
        List<LoanRequestChange> changes,
        DomainExecutionContext context
    ) {
        Set<Id> approvedLoanIds = new Set<Id>();
        Set<Id> submittedLoanIds = new Set<Id>();
        for (LoanRequestChange change : changes) {
            if (change == null || change.loanRequestId == null) {
                continue;
            }
            if (change.transitionedToApproved()) {
                approvedLoanIds.add(change.loanRequestId);
            }
            if (change.becameSubmitted() && context.settings.integrationEnabled == true) {
                submittedLoanIds.add(change.loanRequestId);
            }
        }

        if (!approvedLoanIds.isEmpty()) {
            CustomerEmailService.enqueueApprovalEmails(approvedLoanIds, context);
        }

        if (!submittedLoanIds.isEmpty()) {
            LoanApprovalIntegrationOrchestrator.enqueueEligibleLoans(
                submittedLoanIds,
                context
            );
        }

        if (Test.isRunningTest()) {
            deferredApprovedLoanIds = approvedLoanIds;
            deferredSubmittedLoanIds = submittedLoanIds;
        }
    }

    private static DomainExecutionContext resolveContext(DomainExecutionContext ctx) {
        if (ctx != null && ctx.settings != null) {
            return ctx;
        }
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        if (ctx == null) {
            return DomainExecutionContext.forCurrentUser(settings);
        }
        return new DomainExecutionContext(
            ctx.correlationId,
            ctx.actorUserId,
            settings,
            ctx.source
        );
    }

    @TestVisible
    private static Set<Id> deferredApprovedLoanIds;
    @TestVisible
    private static Set<Id> deferredSubmittedLoanIds;
}
