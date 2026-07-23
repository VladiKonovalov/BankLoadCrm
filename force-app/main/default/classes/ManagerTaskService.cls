/**
 * Creates one high-value manager Task per threshold crossing and manages
 * HighValueTaskCreated__c marker set/reset for the current above-threshold period.
 */
public with sharing class ManagerTaskService {
    /** Documented demo fallback until CMDT exposes an SLA field. */
    @TestVisible
    private static final Integer DEFAULT_DUE_DATE_DAYS = 2;

    public static TaskPlan planHighValueTasks(
        List<LoanRequestChange> changes,
        BankCrmSettings settings
    ) {
        TaskPlan plan = new TaskPlan();
        if (changes == null || changes.isEmpty()) {
            return plan;
        }
        BankCrmSettings resolvedSettings = settings == null
            ? BankCrmSettingsProvider.getSettings()
            : settings;
        Decimal threshold = resolvedSettings.highValueThreshold;

        List<LoanRequestChange> crossings = new List<LoanRequestChange>();
        Set<Id> customerIds = new Set<Id>();

        for (LoanRequestChange change : changes) {
            if (change == null || change.loanRequestId == null) {
                continue;
            }

            Boolean currentlyAbove = change.isAboveThreshold(threshold);
            if (!currentlyAbove && change.highValueTaskCreated == true) {
                plan.addMarkerReset(change.loanRequestId);
                continue;
            }

            if (!change.crossedHighValueThreshold(threshold)) {
                continue;
            }
            if (change.highValueTaskCreated == true) {
                continue;
            }
            crossings.add(change);
            if (change.customerId != null) {
                customerIds.add(change.customerId);
            }
        }

        if (crossings.isEmpty()) {
            return plan;
        }

        Map<Id, Customer__c> customersById = CustomerRepository.getMapByIds(customerIds);
        Map<Id, Id> ownersByCustomerId = UserRoutingResolver.resolveOwners(
            customersById,
            resolvedSettings
        );

        Date dueDate = Date.today().addDays(DEFAULT_DUE_DATE_DAYS);
        String thresholdDisplay = String.valueOf(threshold);

        for (LoanRequestChange change : crossings) {
            Customer__c customer = customersById.get(change.customerId);
            if (customer == null) {
                throw new BankCrmException.MandatoryAutomationException(
                    'Unable to create high-value Task because customer was not found for loan '
                    + change.loanRequestId
                );
            }
            Id ownerId = ownersByCustomerId.get(change.customerId);
            if (ownerId == null) {
                throw new BankCrmException.MandatoryAutomationException(
                    'Unable to resolve manager owner for high-value Task on loan '
                    + change.loanRequestId
                );
            }

            String customerName = customer.Name == null ? 'Customer' : customer.Name;
            String loanReference = String.valueOf(change.loanRequestId);
            Task taskRecord = new Task(
                Subject = String.format(
                    Label.Bank_CRM_High_Value_Task_Subject,
                    new List<String>{ loanReference }
                ),
                Description = String.format(
                    Label.Bank_CRM_High_Value_Task_Description,
                    new List<String>{ loanReference, customerName, thresholdDisplay }
                ),
                WhatId = change.loanRequestId,
                OwnerId = ownerId,
                Status = 'Not Started',
                Priority = 'High',
                ActivityDate = dueDate
            );
            plan.add(taskRecord, change.loanRequestId);
        }

        return plan;
    }

    public static void commitTasks(TaskPlan plan) {
        if (plan == null || plan.isEmpty()) {
            return;
        }

        List<Task> tasks = plan.getTasks();
        if (!tasks.isEmpty()) {
            TaskRepository.insertTasks(tasks);
        }

        List<LoanRequest__c> markerUpdates = new List<LoanRequest__c>();
        for (Id loanId : plan.getLoanRequestIds()) {
            markerUpdates.add(
                new LoanRequest__c(Id = loanId, HighValueTaskCreated__c = true)
            );
        }
        for (Id loanId : plan.getMarkerResetLoanIds()) {
            if (plan.getLoanRequestIds().contains(loanId)) {
                continue;
            }
            markerUpdates.add(
                new LoanRequest__c(Id = loanId, HighValueTaskCreated__c = false)
            );
        }

        if (!markerUpdates.isEmpty()) {
            LoanRequestRepository.DmlOptions options = new LoanRequestRepository.DmlOptions();
            options.allOrNone = true;
            options.enforceSecurity = false;
            try {
                LoanRequestRepository.updateLoans(markerUpdates, options);
            } catch (Exception ex) {
                throw new BankCrmException.MandatoryAutomationException(
                    'Failed to update high-value Task markers: ' + ex.getMessage()
                );
            }
        }
    }
}
