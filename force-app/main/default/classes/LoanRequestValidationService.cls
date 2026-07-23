/**
 * Enforces loan integrity and lifecycle rules for trigger and LWC create paths.
 */
public with sharing class LoanRequestValidationService {
    private static final Set<String> ALLOWED_CREATE_STATUSES = new Set<String>{
        'Draft',
        'Submitted'
    };
    private static final Set<String> TERMINAL_STATUSES = new Set<String>{
        'Approved',
        'Rejected'
    };

    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS =
        new Map<String, Set<String>>{
            'Draft' => new Set<String>{ 'Submitted' },
            'Submitted' => new Set<String>{
                'Under Review',
                'Approved',
                'Rejected',
                'Integration Error'
            },
            'Under Review' => new Set<String>{
                'Approved',
                'Rejected',
                'Integration Error'
            },
            'Integration Error' => new Set<String>{ 'Submitted' }
        };

    /** Test seam: captures field errors applied via addError outside trigger context. */
    @TestVisible
    private static List<String> capturedTriggerErrors;

    public static void validateBeforeInsert(
        List<LoanRequest__c> records,
        DomainExecutionContext ctx
    ) {
        if (records == null || records.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        Map<Id, Customer__c> customersById = loadCustomers(records, null);
        Boolean canEditIntegration = canEditProtectedIntegrationFields(context);
        Map<Id, UserRoutingResolver.RoutingResult> routingByCustomerId =
            resolveRoutingForReadiness(records, null, customersById, context.settings);

        for (LoanRequest__c record : records) {
            validateCommon(record, customersById.get(record.Customer__c), true, null);
            validateCreateStatus(record);
            validateProtectedIntegrationFieldsOnInsert(record, canEditIntegration);
            if (requiresSubmissionReadiness(record.LoanStatus__c)) {
                validateSubmissionReadiness(
                    record,
                    customersById.get(record.Customer__c),
                    routingByCustomerId
                );
            }
            if (record.LoanStatus__c == 'Rejected' && String.isBlank(record.DecisionReason__c)) {
                addFieldError(record, 'DecisionReason__c', 'A decision reason is required when rejecting a loan.');
            }
        }
    }

    public static void validateBeforeUpdate(
        List<LoanRequest__c> newRecords,
        Map<Id, LoanRequest__c> oldMap,
        DomainExecutionContext ctx
    ) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        Map<Id, Customer__c> customersById = loadCustomers(newRecords, oldMap);
        Boolean canEditIntegration = canEditProtectedIntegrationFields(context);
        Boolean canReopen = ApexSecurityHelper.canReopenFinalLoanDecision()
            || context.source == DomainExecutionContext.Source.INTEGRATION
            || context.source == DomainExecutionContext.Source.SYSTEM_CONTEXT;
        Map<Id, UserRoutingResolver.RoutingResult> routingByCustomerId =
            resolveRoutingForReadiness(newRecords, oldMap, customersById, context.settings);

        for (LoanRequest__c newRecord : newRecords) {
            LoanRequest__c oldRecord = oldMap == null ? null : oldMap.get(newRecord.Id);
            if (oldRecord == null) {
                continue;
            }
            validateCommon(
                newRecord,
                customersById.get(newRecord.Customer__c),
                false,
                oldRecord
            );
            validateStatusTransition(newRecord, oldRecord, canReopen);
            validateProtectedIntegrationFieldsOnUpdate(
                newRecord,
                oldRecord,
                canEditIntegration
            );
            if (
                newRecord.LoanStatus__c != oldRecord.LoanStatus__c
                && requiresSubmissionReadiness(newRecord.LoanStatus__c)
            ) {
                validateSubmissionReadiness(
                    newRecord,
                    customersById.get(newRecord.Customer__c),
                    routingByCustomerId
                );
            }
            if (
                newRecord.LoanStatus__c == 'Rejected'
                && String.isBlank(newRecord.DecisionReason__c)
            ) {
                addFieldError(
                    newRecord,
                    'DecisionReason__c',
                    'A decision reason is required when rejecting a loan.'
                );
            }
        }
    }

    public static List<ValidationFailure> validateForLwcCreate(LoanRequestDto dto) {
        List<ValidationFailure> failures = new List<ValidationFailure>();
        if (dto == null) {
            failures.add(new ValidationFailure(null, 'Loan request details are required.'));
            return failures;
        }

        if (dto.customerId == null) {
            failures.add(new ValidationFailure('customerId', 'Customer is required.'));
        }
        if (dto.loanAmount == null) {
            failures.add(new ValidationFailure('loanAmount', 'Loan amount is required.'));
        } else if (dto.loanAmount <= 0) {
            failures.add(
                new ValidationFailure('loanAmount', 'Loan amount must be greater than zero.')
            );
        }
        if (String.isBlank(dto.loanStatus)) {
            failures.add(new ValidationFailure('loanStatus', 'Loan status is required.'));
        } else if (!ALLOWED_CREATE_STATUSES.contains(dto.loanStatus)) {
            failures.add(
                new ValidationFailure(
                    'loanStatus',
                    'New loan requests may only start as Draft or Submitted.'
                )
            );
        }

        if (dto.customerId != null && requiresSubmissionReadiness(dto.loanStatus)) {
            Map<Id, Customer__c> customers = CustomerRepository.getMapByIds(
                new Set<Id>{ dto.customerId }
            );
            Customer__c customer = customers.get(dto.customerId);
            if (customer == null) {
                failures.add(
                    new ValidationFailure('customerId', 'Selected customer could not be found.')
                );
            } else {
                if (customer.IsActive__c != true) {
                    failures.add(
                        new ValidationFailure(
                            'customerId',
                            'Loans beyond Draft require an active customer.'
                        )
                    );
                }
                if (String.isBlank(customer.Email__c)) {
                    failures.add(
                        new ValidationFailure(
                            'customerId',
                            'Customer email is required before submission or approval.'
                        )
                    );
                }
                BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
                Map<Id, UserRoutingResolver.RoutingResult> routing =
                    UserRoutingResolver.resolveOwnersDetailed(
                        new Map<Id, Customer__c>{ customer.Id => customer },
                        settings
                    );
                UserRoutingResolver.RoutingResult route = routing.get(customer.Id);
                if (route == null || !route.isSuccess()) {
                    failures.add(
                        new ValidationFailure(
                            'customerId',
                            'A relationship manager or configured default owner is required before submission.'
                        )
                    );
                }
            }
        }

        return failures;
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

    private static Map<Id, Customer__c> loadCustomers(
        List<LoanRequest__c> records,
        Map<Id, LoanRequest__c> oldMap
    ) {
        Set<Id> customerIds = new Set<Id>();
        for (LoanRequest__c record : records) {
            if (record.Customer__c != null) {
                customerIds.add(record.Customer__c);
            }
        }
        if (oldMap != null) {
            for (LoanRequest__c oldRecord : oldMap.values()) {
                if (oldRecord.Customer__c != null) {
                    customerIds.add(oldRecord.Customer__c);
                }
            }
        }
        return CustomerRepository.getMapByIds(customerIds);
    }

    private static void validateCommon(
        LoanRequest__c record,
        Customer__c customer,
        Boolean isInsert,
        LoanRequest__c oldRecord
    ) {
        if (record.Customer__c == null) {
            addFieldError(record, 'Customer__c', 'Customer is required.');
        }
        if (record.LoanAmount__c == null || record.LoanAmount__c <= 0) {
            addFieldError(record, 'LoanAmount__c', 'Loan amount must be greater than zero.');
        }
        if (String.isBlank(record.LoanStatus__c)) {
            addFieldError(record, 'LoanStatus__c', 'Loan status is required.');
        }
        if (
            record.LoanStatus__c != null
            && record.LoanStatus__c != 'Draft'
            && record.SubmissionDate__c == null
        ) {
            addFieldError(
                record,
                'SubmissionDate__c',
                'Submission date is required for loans beyond Draft.'
            );
        }
        if (
            !isInsert
            && oldRecord != null
            && oldRecord.SubmissionDate__c != null
            && record.SubmissionDate__c == null
        ) {
            addFieldError(
                record,
                'SubmissionDate__c',
                'Submission date cannot be cleared once set.'
            );
        }
        if (customer == null && record.Customer__c != null) {
            addFieldError(record, 'Customer__c', 'Selected customer could not be found.');
        }
    }

    private static void validateCreateStatus(LoanRequest__c record) {
        if (
            String.isNotBlank(record.LoanStatus__c)
            && !ALLOWED_CREATE_STATUSES.contains(record.LoanStatus__c)
        ) {
            addFieldError(
                record,
                'LoanStatus__c',
                'New loan requests may only start as Draft or Submitted.'
            );
        }
    }

    private static void validateStatusTransition(
        LoanRequest__c newRecord,
        LoanRequest__c oldRecord,
        Boolean canReopen
    ) {
        String oldStatus = oldRecord.LoanStatus__c;
        String newStatus = newRecord.LoanStatus__c;
        if (oldStatus == newStatus) {
            return;
        }
        if (TERMINAL_STATUSES.contains(oldStatus) && !canReopen) {
            addFieldError(
                newRecord,
                'LoanStatus__c',
                'Approved and Rejected loans are final for ordinary users.'
            );
            return;
        }
        Set<String> allowed = ALLOWED_TRANSITIONS.get(oldStatus);
        if (allowed == null || !allowed.contains(newStatus)) {
            if (TERMINAL_STATUSES.contains(oldStatus) && canReopen) {
                return;
            }
            addFieldError(
                newRecord,
                'LoanStatus__c',
                'Status transition from ' + oldStatus + ' to ' + newStatus + ' is not allowed.'
            );
        }
    }

    private static void validateProtectedIntegrationFieldsOnInsert(
        LoanRequest__c record,
        Boolean canEditIntegration
    ) {
        if (canEditIntegration) {
            return;
        }
        if (String.isNotBlank(record.ExternalRequestId__c)) {
            addFieldError(
                record,
                'ExternalRequestId__c',
                'You do not have permission to set integration fields.'
            );
        }
        if (String.isNotBlank(record.ExternalDecisionReference__c)) {
            addFieldError(
                record,
                'ExternalDecisionReference__c',
                'You do not have permission to set integration fields.'
            );
        }
        if (
            String.isNotBlank(record.IntegrationStatus__c)
            && record.IntegrationStatus__c != 'Not Sent'
        ) {
            addFieldError(
                record,
                'IntegrationStatus__c',
                'You do not have permission to set integration fields.'
            );
        }
        if (record.IntegrationLastAttempt__c != null) {
            addFieldError(
                record,
                'IntegrationLastAttempt__c',
                'You do not have permission to set integration fields.'
            );
        }
    }

    private static void validateProtectedIntegrationFieldsOnUpdate(
        LoanRequest__c newRecord,
        LoanRequest__c oldRecord,
        Boolean canEditIntegration
    ) {
        if (canEditIntegration) {
            return;
        }
        if (newRecord.ExternalRequestId__c != oldRecord.ExternalRequestId__c) {
            addFieldError(
                newRecord,
                'ExternalRequestId__c',
                'You do not have permission to edit integration fields.'
            );
        }
        if (newRecord.ExternalDecisionReference__c != oldRecord.ExternalDecisionReference__c) {
            addFieldError(
                newRecord,
                'ExternalDecisionReference__c',
                'You do not have permission to edit integration fields.'
            );
        }
        if (newRecord.IntegrationStatus__c != oldRecord.IntegrationStatus__c) {
            addFieldError(
                newRecord,
                'IntegrationStatus__c',
                'You do not have permission to edit integration fields.'
            );
        }
        if (newRecord.IntegrationLastAttempt__c != oldRecord.IntegrationLastAttempt__c) {
            addFieldError(
                newRecord,
                'IntegrationLastAttempt__c',
                'You do not have permission to edit integration fields.'
            );
        }
    }

    private static void validateSubmissionReadiness(
        LoanRequest__c record,
        Customer__c customer,
        Map<Id, UserRoutingResolver.RoutingResult> routingByCustomerId
    ) {
        if (customer == null) {
            return;
        }
        if (customer.IsActive__c != true) {
            addFieldError(
                record,
                'Customer__c',
                'Loans beyond Draft require an active customer.'
            );
        }
        if (String.isBlank(customer.Email__c)) {
            addFieldError(
                record,
                'Customer__c',
                'Customer email is required before submission or approval.'
            );
        }
        UserRoutingResolver.RoutingResult route = routingByCustomerId == null
            ? null
            : routingByCustomerId.get(customer.Id);
        if (route == null || !route.isSuccess()) {
            addFieldError(
                record,
                'Customer__c',
                'A relationship manager or configured default owner is required before submission.'
            );
        }
    }

    /**
     * Bulk-resolves routing once per trigger chunk for loans entering submission-ready statuses.
     */
    private static Map<Id, UserRoutingResolver.RoutingResult> resolveRoutingForReadiness(
        List<LoanRequest__c> records,
        Map<Id, LoanRequest__c> oldMap,
        Map<Id, Customer__c> customersById,
        BankCrmSettings settings
    ) {
        Map<Id, Customer__c> customersNeedingRouting = new Map<Id, Customer__c>();
        if (records == null || customersById == null) {
            return new Map<Id, UserRoutingResolver.RoutingResult>();
        }
        for (LoanRequest__c record : records) {
            if (record == null || !requiresSubmissionReadiness(record.LoanStatus__c)) {
                continue;
            }
            if (oldMap != null) {
                LoanRequest__c oldRecord = oldMap.get(record.Id);
                if (
                    oldRecord == null
                    || oldRecord.LoanStatus__c == record.LoanStatus__c
                ) {
                    continue;
                }
            }
            Customer__c customer = customersById.get(record.Customer__c);
            if (customer != null && customer.Id != null) {
                customersNeedingRouting.put(customer.Id, customer);
            }
        }
        if (customersNeedingRouting.isEmpty()) {
            return new Map<Id, UserRoutingResolver.RoutingResult>();
        }
        return UserRoutingResolver.resolveOwnersDetailed(customersNeedingRouting, settings);
    }

    private static Boolean requiresSubmissionReadiness(String status) {
        return status != null && status != 'Draft';
    }

    private static Boolean canEditProtectedIntegrationFields(DomainExecutionContext ctx) {
        return ApexSecurityHelper.canEditIntegrationFields()
            || ctx.source == DomainExecutionContext.Source.INTEGRATION
            || ctx.source == DomainExecutionContext.Source.SYSTEM_CONTEXT;
    }

    private static void addFieldError(LoanRequest__c record, String fieldApiName, String message) {
        if (record == null) {
            return;
        }
        if (Test.isRunningTest()) {
            if (capturedTriggerErrors == null) {
                capturedTriggerErrors = new List<String>();
            }
            capturedTriggerErrors.add(fieldApiName + ': ' + message);
        }
        if (fieldApiName == 'Customer__c') {
            record.Customer__c.addError(message);
        } else if (fieldApiName == 'LoanAmount__c') {
            record.LoanAmount__c.addError(message);
        } else if (fieldApiName == 'LoanStatus__c') {
            record.LoanStatus__c.addError(message);
        } else if (fieldApiName == 'SubmissionDate__c') {
            record.SubmissionDate__c.addError(message);
        } else if (fieldApiName == 'DecisionReason__c') {
            record.DecisionReason__c.addError(message);
        } else if (fieldApiName == 'ExternalRequestId__c') {
            record.ExternalRequestId__c.addError(message);
        } else if (fieldApiName == 'ExternalDecisionReference__c') {
            record.ExternalDecisionReference__c.addError(message);
        } else if (fieldApiName == 'IntegrationStatus__c') {
            record.IntegrationStatus__c.addError(message);
        } else if (fieldApiName == 'IntegrationLastAttempt__c') {
            record.IntegrationLastAttempt__c.addError(message);
        } else {
            record.addError(message);
        }
    }
}
