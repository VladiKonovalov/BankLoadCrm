/**
 * Owns outbound eligibility, technical integration state, retries, and INTEGRATION_RESULT audits.
 * Callouts never run in the trigger transaction.
 */
public without sharing class LoanApprovalIntegrationOrchestrator {
    private static final String NAMED_CREDENTIAL_ENDPOINT =
        'callout:Bank_Loan_Approval/submissions';
    /** Test seam: optional absolute URL so HttpCalloutMock works without Named Credential auth. */
    @TestVisible
    private static String testEndpointOverride;
    /** Test seam: inject an HttpResponse and skip Http.send entirely. */
    @TestVisible
    private static HttpResponse testHttpResponse;
    private static final Set<String> OUTBOUND_ELIGIBLE_STATUSES = new Set<String>{
        'Not Sent',
        'Retry Pending'
    };
    private static final Set<String> OUTBOUND_LOAN_STATUSES = new Set<String>{
        'Submitted'
    };

    @TestVisible
    private static Boolean skipEnqueueInTests = false;
    @TestVisible
    private static List<Id> lastEnqueuedLoanIds = new List<Id>();
    @TestVisible
    private static Integer enqueuedJobCount = 0;

    /**
     * Enqueues a post-commit callout job for newly submitted loans when integration is enabled.
     */
    public static void enqueueEligibleLoans(Set<Id> loanIds, DomainExecutionContext ctx) {
        if (loanIds == null || loanIds.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        if (context.settings == null || context.settings.integrationEnabled != true) {
            return;
        }

        Set<Id> eligibleIds = new Set<Id>();
        for (LoanRequest__c loan : LoanRequestRepository.getByIds(loanIds)) {
            if (isOutboundEligible(loan)) {
                eligibleIds.add(loan.Id);
            }
        }
        if (eligibleIds.isEmpty()) {
            return;
        }

        if (Test.isRunningTest()) {
            lastEnqueuedLoanIds = new List<Id>(eligibleIds);
            enqueuedJobCount++;
            if (skipEnqueueInTests == true) {
                return;
            }
        }

        System.enqueueJob(
            new LoanApprovalCalloutQueueable(eligibleIds, context.correlationId)
        );
    }

    /**
     * Performs Named Credential callouts for a re-queried loan set and applies technical outcomes.
     */
    public static void processOutboundBatch(
        List<LoanRequest__c> loans,
        DomainExecutionContext ctx
    ) {
        if (loans == null || loans.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        if (context.settings == null || context.settings.integrationEnabled != true) {
            return;
        }

        Set<Id> customerIds = new Set<Id>();
        for (LoanRequest__c loan : loans) {
            if (loan != null && loan.Customer__c != null) {
                customerIds.add(loan.Customer__c);
            }
        }
        Map<Id, Customer__c> customersById = CustomerRepository.getMapByIds(customerIds);

        List<LoanRequest__c> prepared = prepareForOutbound(loans, context);
        if (!prepared.isEmpty()) {
            updateIntegrationRecords(prepared);
            Map<Id, LoanRequest__c> refreshed = LoanRequestRepository.getMapByIds(
                new Map<Id, LoanRequest__c>(prepared).keySet()
            );
            prepared = new List<LoanRequest__c>();
            for (Id loanId : refreshed.keySet()) {
                prepared.add(refreshed.get(loanId));
            }
        }

        List<AuditEventDto> audits = new List<AuditEventDto>();
        List<LoanRequest__c> toUpdate = new List<LoanRequest__c>();

        for (LoanRequest__c loan : prepared) {
            if (loan == null || !isOutboundEligibleAfterPrepare(loan)) {
                continue;
            }
            Customer__c customer = customersById.get(loan.Customer__c);
            String customerNumber = customer == null ? null : customer.CustomerNumber__c;
            String customerName = customer == null ? null : customer.Name;

            LoanApprovalIntegrationContracts.OutboundRequest request =
                LoanApprovalIntegrationContracts.outboundFromLoan(
                    loan,
                    customerNumber,
                    context.correlationId
                );

            Integer priorAttempts = countIntegrationAttempts(loan.Id);
            Integer attemptNumber = priorAttempts + 1;

            try {
                HttpResponse httpResponse = sendOutbound(request);
                LoanApprovalIntegrationContracts.OutboundResponse response =
                    LoanApprovalIntegrationContracts.outboundFromHttp(httpResponse);

                if (response.success == true) {
                    applyAcceptedResponse(loan, response, context, customerName, audits, toUpdate);
                } else if (response.retryable == true) {
                    scheduleRetry(
                        loan,
                        response,
                        attemptNumber,
                        context,
                        customerName,
                        audits,
                        toUpdate
                    );
                } else {
                    applyPermanentFailure(
                        loan,
                        response,
                        attemptNumber,
                        context,
                        customerName,
                        audits,
                        toUpdate
                    );
                }
            } catch (Exception ex) {
                LoanApprovalIntegrationContracts.OutboundResponse timeoutLike =
                    new LoanApprovalIntegrationContracts.OutboundResponse();
                timeoutLike.success = false;
                timeoutLike.retryable = true;
                timeoutLike.statusCode = 'EXCEPTION';
                timeoutLike.message = SanitizedMessageUtil.sanitize(ex.getMessage());
                scheduleRetry(
                    loan,
                    timeoutLike,
                    attemptNumber,
                    context,
                    customerName,
                    audits,
                    toUpdate
                );
            }
        }

        if (!toUpdate.isEmpty()) {
            updateIntegrationRecords(toUpdate);
        }
        if (!audits.isEmpty()) {
            AuditService.commitEvents(audits);
        }
    }

    public static void applyAcceptedResponse(
        LoanRequest__c loan,
        LoanApprovalIntegrationContracts.OutboundResponse response,
        DomainExecutionContext ctx,
        String customerName,
        List<AuditEventDto> audits,
        List<LoanRequest__c> toUpdate
    ) {
        String previousStatus = loan.IntegrationStatus__c;
        loan.IntegrationStatus__c = 'Pending';
        loan.IntegrationLastAttempt__c = System.now();
        if (
            response != null
            && String.isNotBlank(response.externalDecisionReference)
        ) {
            loan.ExternalDecisionReference__c = response.externalDecisionReference;
        }
        toUpdate.add(loan);
        audits.add(
            buildIntegrationAudit(
                loan,
                customerName,
                previousStatus,
                'Pending',
                ctx,
                'Outbound submission accepted'
            )
        );
    }

    public static void scheduleRetry(
        LoanRequest__c loan,
        LoanApprovalIntegrationContracts.OutboundResponse response,
        Integer attemptNumber,
        DomainExecutionContext ctx,
        String customerName,
        List<AuditEventDto> audits,
        List<LoanRequest__c> toUpdate
    ) {
        DomainExecutionContext context = resolveContext(ctx);
        Integer retryLimit = context.settings.retryLimit == null
            ? 3
            : context.settings.retryLimit;

        if (attemptNumber >= retryLimit) {
            applyPermanentFailure(
                loan,
                response,
                attemptNumber,
                context,
                customerName,
                audits,
                toUpdate
            );
            return;
        }

        String previousStatus = loan.IntegrationStatus__c;
        loan.IntegrationStatus__c = 'Retry Pending';
        loan.IntegrationLastAttempt__c = System.now();
        toUpdate.add(loan);
        audits.add(
            buildIntegrationAudit(
                loan,
                customerName,
                previousStatus,
                'Retry Pending',
                context,
                'Transient outbound failure; retry scheduled (attempt '
                    + attemptNumber
                    + ')'
            )
        );

        ApplicationErrorService.ErrorContext errorCtx = new ApplicationErrorService.ErrorContext(
            'LoanApprovalIntegrationOrchestrator',
            'scheduleRetry'
        );
        errorCtx.loanRequestId = loan.Id;
        errorCtx.customerId = loan.Customer__c;
        errorCtx.correlationId = context.correlationId;
        errorCtx.category = 'Integration Transient';
        errorCtx.retryable = true;
        errorCtx.nextRetryAt = nextRetryAt(attemptNumber, context.settings);

        Exception transientEx = new BankCrmException.IntegrationException(
            response == null || String.isBlank(response.message)
                ? 'Transient integration failure'
                : response.message
        );
        Application_Error__c error = ApplicationErrorService.log(transientEx, errorCtx);
        if (error != null && error.Id != null) {
            error.AttemptCount__c = attemptNumber;
            ApplicationErrorRepository.updateErrors(new List<Application_Error__c>{ error });
        }
    }

    @TestVisible
    private static void applyPermanentFailure(
        LoanRequest__c loan,
        LoanApprovalIntegrationContracts.OutboundResponse response,
        Integer attemptNumber,
        DomainExecutionContext ctx,
        String customerName,
        List<AuditEventDto> audits,
        List<LoanRequest__c> toUpdate
    ) {
        String previousStatus = loan.IntegrationStatus__c;
        loan.IntegrationStatus__c = 'Failed';
        loan.IntegrationLastAttempt__c = System.now();
        if (loan.LoanStatus__c == 'Submitted' || loan.LoanStatus__c == 'Under Review') {
            loan.LoanStatus__c = 'Integration Error';
        }
        escalateToSupportQueue(loan);
        toUpdate.add(loan);
        audits.add(
            buildIntegrationAudit(
                loan,
                customerName,
                previousStatus,
                'Failed',
                ctx,
                'Permanent outbound failure after attempt ' + attemptNumber
            )
        );

        ApplicationErrorService.ErrorContext errorCtx = new ApplicationErrorService.ErrorContext(
            'LoanApprovalIntegrationOrchestrator',
            'permanentFailure'
        );
        errorCtx.loanRequestId = loan.Id;
        errorCtx.customerId = loan.Customer__c;
        errorCtx.correlationId = ctx.correlationId;
        errorCtx.category = 'Integration Permanent';
        errorCtx.retryable = false;
        Exception permanentEx = new BankCrmException.IntegrationException(
            response == null || String.isBlank(response.message)
                ? 'Permanent integration failure'
                : response.message
        );
        ApplicationErrorService.log(permanentEx, errorCtx);
    }

    /**
     * Re-enqueues aged Retry Pending / stuck Pending loans that are still under the retry limit.
     */
    public static void reconcileCandidates(
        List<LoanRequest__c> candidates,
        DomainExecutionContext ctx
    ) {
        if (candidates == null || candidates.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        if (context.settings == null || context.settings.integrationEnabled != true) {
            return;
        }

        Integer retryLimit = context.settings.retryLimit == null
            ? 3
            : context.settings.retryLimit;
        Set<Id> retryIds = new Set<Id>();
        List<LoanRequest__c> exhausted = new List<LoanRequest__c>();
        List<AuditEventDto> audits = new List<AuditEventDto>();

        Map<Id, Customer__c> customersById = CustomerRepository.getMapByIds(
            collectCustomerIds(candidates)
        );

        for (LoanRequest__c loan : candidates) {
            if (loan == null || loan.Id == null) {
                continue;
            }
            Integer attempts = countIntegrationAttempts(loan.Id);
            if (attempts >= retryLimit) {
                String customerName = customersById.containsKey(loan.Customer__c)
                    ? customersById.get(loan.Customer__c).Name
                    : null;
                applyPermanentFailure(
                    loan,
                    null,
                    attempts,
                    context,
                    customerName,
                    audits,
                    exhausted
                );
            } else if (
                loan.IntegrationStatus__c == 'Retry Pending'
                || loan.IntegrationStatus__c == 'Pending'
            ) {
                retryIds.add(loan.Id);
            }
        }

        if (!exhausted.isEmpty()) {
            updateIntegrationRecords(exhausted);
        }
        if (!audits.isEmpty()) {
            AuditService.commitEvents(audits);
        }
        if (!retryIds.isEmpty()) {
            enqueueEligibleLoans(retryIds, context);
        }
    }

    @TestVisible
    private static HttpResponse sendOutbound(
        LoanApprovalIntegrationContracts.OutboundRequest request
    ) {
        if (Test.isRunningTest() && testHttpResponse != null) {
            return testHttpResponse;
        }
        HttpRequest httpRequest = new HttpRequest();
        String endpoint = String.isNotBlank(testEndpointOverride)
            ? testEndpointOverride
            : NAMED_CREDENTIAL_ENDPOINT;
        httpRequest.setEndpoint(endpoint);
        httpRequest.setMethod('POST');
        httpRequest.setHeader('Content-Type', 'application/json');
        httpRequest.setHeader('X-Correlation-Id', request.correlationId);
        httpRequest.setHeader('X-Idempotency-Key', request.externalRequestId);
        httpRequest.setBody(request.toJson());
        httpRequest.setTimeout(120000);
        return new Http().send(httpRequest);
    }

    private static List<LoanRequest__c> prepareForOutbound(
        List<LoanRequest__c> loans,
        DomainExecutionContext context
    ) {
        List<LoanRequest__c> prepared = new List<LoanRequest__c>();
        for (LoanRequest__c loan : loans) {
            if (loan == null || !isOutboundEligible(loan)) {
                continue;
            }
            if (String.isBlank(loan.ExternalRequestId__c)) {
                loan.ExternalRequestId__c = CorrelationIdUtil.newId();
            }
            loan.IntegrationStatus__c = 'Pending';
            loan.IntegrationLastAttempt__c = System.now();
            prepared.add(loan);
        }
        return prepared;
    }

    private static Boolean isOutboundEligible(LoanRequest__c loan) {
        if (loan == null || loan.Id == null) {
            return false;
        }
        if (!OUTBOUND_LOAN_STATUSES.contains(loan.LoanStatus__c)) {
            return false;
        }
        return OUTBOUND_ELIGIBLE_STATUSES.contains(loan.IntegrationStatus__c)
            || (loan.IntegrationStatus__c == 'Pending'
                && String.isNotBlank(loan.ExternalRequestId__c))
            || (loan.IntegrationStatus__c == 'Failed'
                && loan.LoanStatus__c == 'Submitted');
    }

    private static Boolean isOutboundEligibleAfterPrepare(LoanRequest__c loan) {
        return loan != null
            && OUTBOUND_LOAN_STATUSES.contains(loan.LoanStatus__c)
            && loan.IntegrationStatus__c == 'Pending'
            && String.isNotBlank(loan.ExternalRequestId__c);
    }

    private static void updateIntegrationRecords(List<LoanRequest__c> records) {
        LoanRequestRepository.DmlOptions options = new LoanRequestRepository.DmlOptions();
        options.enforceSecurity = false;
        options.allOrNone = false;
        try {
            LoanRequestTriggerHandler.setForcedSource(
                DomainExecutionContext.Source.INTEGRATION
            );
            LoanRequestRepository.updateLoans(records, options);
        } finally {
            LoanRequestTriggerHandler.clearForcedSource();
        }
    }

    private static AuditEventDto buildIntegrationAudit(
        LoanRequest__c loan,
        String customerName,
        String oldValue,
        String newValue,
        DomainExecutionContext ctx,
        String details
    ) {
        AuditEventDto event = new AuditEventDto();
        event.eventType = 'INTEGRATION_RESULT';
        event.loanRequestId = loan.Id;
        event.customerId = loan.Customer__c;
        event.oldValue = oldValue;
        event.newValue = newValue;
        event.customerNameSnapshot = String.isBlank(customerName) ? 'Unknown' : customerName;
        event.loanAmountSnapshot = loan.LoanAmount__c == null ? 0 : loan.LoanAmount__c;
        event.occurredAt = System.now();
        event.actorUserId = ctx == null ? null : ctx.actorUserId;
        event.correlationId = ctx == null
            ? CorrelationIdUtil.currentOrNew()
            : ctx.correlationId;
        event.source = 'Integration';
        event.details = SanitizedMessageUtil.sanitize(details);
        return event;
    }

    @TestVisible
    private static Integer countIntegrationAttempts(Id loanId) {
        if (loanId == null) {
            return 0;
        }
        AggregateResult[] rows = [
            SELECT MAX(AttemptCount__c) maxAttempts
            FROM Application_Error__c
            WHERE LoanRequest__c = :loanId
                AND Category__c IN ('Integration Transient', 'Integration Permanent')
        ];
        if (rows.isEmpty() || rows[0].get('maxAttempts') == null) {
            return 0;
        }
        return Integer.valueOf(rows[0].get('maxAttempts'));
    }

    private static Datetime nextRetryAt(Integer attemptNumber, BankCrmSettings settings) {
        Integer baseMinutes = settings == null || settings.retryBaseDelayMinutes == null
            ? 15
            : settings.retryBaseDelayMinutes;
        Integer safeAttempt = attemptNumber == null || attemptNumber < 1 ? 1 : attemptNumber;
        Integer delay = baseMinutes * (Integer) Math.pow(2, safeAttempt - 1);
        return System.now().addMinutes(delay);
    }

    private static void escalateToSupportQueue(LoanRequest__c loan) {
        List<Group> queues = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
                AND DeveloperName = 'Bank_CRM_Operations_Support'
            LIMIT 1
        ];
        if (!queues.isEmpty()) {
            loan.OwnerId = queues[0].Id;
        }
    }

    private static Set<Id> collectCustomerIds(List<LoanRequest__c> loans) {
        Set<Id> ids = new Set<Id>();
        for (LoanRequest__c loan : loans) {
            if (loan != null && loan.Customer__c != null) {
                ids.add(loan.Customer__c);
            }
        }
        return ids;
    }

    private static DomainExecutionContext resolveContext(DomainExecutionContext ctx) {
        if (ctx != null && ctx.settings != null) {
            return ctx;
        }
        BankCrmSettings settings = BankCrmSettingsProvider.getSettings();
        if (ctx == null) {
            return new DomainExecutionContext(
                CorrelationIdUtil.currentOrNew(),
                UserInfo.getUserId(),
                settings,
                DomainExecutionContext.Source.INTEGRATION
            );
        }
        return new DomainExecutionContext(
            ctx.correlationId,
            ctx.actorUserId,
            settings,
            DomainExecutionContext.Source.INTEGRATION
        );
    }

    @TestVisible
    private static void resetTestState() {
        skipEnqueueInTests = false;
        lastEnqueuedLoanIds = new List<Id>();
        enqueuedJobCount = 0;
        testEndpointOverride = null;
        testHttpResponse = null;
    }
}
