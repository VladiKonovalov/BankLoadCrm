/**
 * Orchestrates one bulk pass per LoanRequest__c trigger invocation.
 * Unexpected failures are logged via ApplicationErrorService then rethrown.
 */
public with sharing class LoanRequestTriggerHandler {
    /** Test seam so service-level tests can exercise DML without double side effects. */
    @TestVisible
    private static Boolean bypassTrigger = false;

    /**
     * Allows integration Queueable/callback/batch DML to pass protected-field validation
     * without requiring the interactive user to hold Edit_Bank_CRM_Integration_Fields.
     */
    private static DomainExecutionContext.Source forcedSource;

    public static void setForcedSource(DomainExecutionContext.Source source) {
        forcedSource = source;
    }

    public static void clearForcedSource() {
        forcedSource = null;
    }

    public static void run(
        System.TriggerOperation operation,
        List<LoanRequest__c> newList,
        Map<Id, LoanRequest__c> oldMap
    ) {
        if (bypassTrigger == true || operation == null) {
            return;
        }
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        DomainExecutionContext ctx = forcedSource == null
            ? DomainExecutionContext.forCurrentUser(settings)
            : new DomainExecutionContext(
                CorrelationIdUtil.currentOrNew(),
                UserInfo.getUserId(),
                settings,
                forcedSource
            );
        ApplicationErrorService.ErrorContext errorCtx =
            new ApplicationErrorService.ErrorContext(
                'LoanRequestTriggerHandler',
                String.valueOf(operation)
            );
        errorCtx.correlationId = ctx.correlationId;

        try {
            if (operation == System.TriggerOperation.BEFORE_INSERT) {
                handleBeforeInsert(newList, ctx);
            } else if (operation == System.TriggerOperation.BEFORE_UPDATE) {
                handleBeforeUpdate(newList, oldMap, ctx);
            } else if (operation == System.TriggerOperation.AFTER_INSERT) {
                handleAfterInsert(newList, ctx);
            } else if (operation == System.TriggerOperation.AFTER_UPDATE) {
                handleAfterUpdate(newList, oldMap, ctx);
            }
        } catch (BankCrmException.MandatoryAutomationException ex) {
            ApplicationErrorService.logAndRethrow(ex, errorCtx);
        } catch (BankCrmException ex) {
            ApplicationErrorService.logAndRethrow(ex, errorCtx);
        } catch (Exception ex) {
            ApplicationErrorService.logAndRethrow(ex, errorCtx);
        }
    }

    private static void handleBeforeInsert(
        List<LoanRequest__c> newList,
        DomainExecutionContext ctx
    ) {
        applyInsertDefaults(newList);
        LoanRequestValidationService.validateBeforeInsert(newList, ctx);
    }

    private static void handleBeforeUpdate(
        List<LoanRequest__c> newList,
        Map<Id, LoanRequest__c> oldMap,
        DomainExecutionContext ctx
    ) {
        LoanRequestValidationService.validateBeforeUpdate(newList, oldMap, ctx);
    }

    private static void handleAfterInsert(
        List<LoanRequest__c> newList,
        DomainExecutionContext ctx
    ) {
        LoanRequestDomainService.processAfterInsert(newList, ctx);
    }

    private static void handleAfterUpdate(
        List<LoanRequest__c> newList,
        Map<Id, LoanRequest__c> oldMap,
        DomainExecutionContext ctx
    ) {
        LoanRequestDomainService.processAfterUpdate(newList, oldMap, ctx);
    }

    private static void applyInsertDefaults(List<LoanRequest__c> newList) {
        if (newList == null) {
            return;
        }
        for (LoanRequest__c record : newList) {
            if (record == null) {
                continue;
            }
            if (String.isBlank(record.IntegrationStatus__c)) {
                record.IntegrationStatus__c = 'Not Sent';
            }
            if (record.HighValueTaskCreated__c == null) {
                record.HighValueTaskCreated__c = false;
            }
        }
    }
}
