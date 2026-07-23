/**
 * Authenticates, deduplicates, and applies inbound external approval decisions
 * through normal loan DML so trigger and Flow automations run.
 */
public without sharing class ApprovalCallbackService {
    public static LoanApprovalIntegrationContracts.ApprovalCallbackResult handleDecision(
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request
    ) {
        if (request == null || String.isBlank(request.externalRequestId)) {
            return LoanApprovalIntegrationContracts.callbackRejected(
                'Invalid callback payload.'
            );
        }

        String correlationId = String.isBlank(request.correlationId)
            ? CorrelationIdUtil.currentOrNew()
            : request.correlationId;
        CorrelationIdUtil.setCurrent(correlationId);

        Map<String, LoanRequest__c> byExternalId =
            LoanRequestRepository.getMapByExternalRequestIds(
                new Set<String>{ request.externalRequestId }
            );
        LoanRequest__c loan = byExternalId.get(request.externalRequestId);
        if (loan == null) {
            return LoanApprovalIntegrationContracts.callbackRejected(
                'Unknown request.'
            );
        }

        if (isDuplicate(loan, request)) {
            return LoanApprovalIntegrationContracts.callbackDuplicate(loan.Id);
        }

        String mappedStatus = mapDecision(request.decision);
        if (String.isBlank(mappedStatus)) {
            return LoanApprovalIntegrationContracts.callbackRejected(
                'Unsupported decision.'
            );
        }

        String previousIntegrationStatus = loan.IntegrationStatus__c;
        loan.LoanStatus__c = mappedStatus;
        if (mappedStatus == 'Rejected') {
            loan.DecisionReason__c = String.isBlank(request.decisionReason)
                ? 'Rejected by external approval system'
                : request.decisionReason;
        }
        if (String.isNotBlank(request.externalDecisionReference)) {
            loan.ExternalDecisionReference__c = request.externalDecisionReference;
        } else if (String.isBlank(loan.ExternalDecisionReference__c)) {
            loan.ExternalDecisionReference__c = 'CB-' + request.externalRequestId;
        }
        loan.IntegrationStatus__c = 'Succeeded';
        loan.IntegrationLastAttempt__c = System.now();

        DomainExecutionContext ctx = new DomainExecutionContext(
            correlationId,
            UserInfo.getUserId(),
            BankCrmSettingsProvider.getSettings(),
            DomainExecutionContext.Source.INTEGRATION
        );

        try {
            LoanRequestRepository.DmlOptions options = new LoanRequestRepository.DmlOptions();
            options.enforceSecurity = false;
            options.allOrNone = true;
            LoanRequestTriggerHandler.setForcedSource(
                DomainExecutionContext.Source.INTEGRATION
            );
            LoanRequestRepository.updateLoans(
                new List<LoanRequest__c>{ loan },
                options
            );
        } catch (Exception ex) {
            ApplicationErrorService.ErrorContext errorCtx =
                new ApplicationErrorService.ErrorContext(
                    'ApprovalCallbackService',
                    'handleDecision'
                );
            errorCtx.loanRequestId = loan.Id;
            errorCtx.customerId = loan.Customer__c;
            errorCtx.correlationId = correlationId;
            errorCtx.category = 'Integration Permanent';
            errorCtx.retryable = false;
            ApplicationErrorService.log(ex, errorCtx);
            return LoanApprovalIntegrationContracts.callbackRejected(
                'Unable to apply decision.'
            );
        } finally {
            LoanRequestTriggerHandler.clearForcedSource();
        }

        Customer__c customer = CustomerRepository.getMapByIds(
            new Set<Id>{ loan.Customer__c }
        ).get(loan.Customer__c);
        AuditEventDto audit = new AuditEventDto();
        audit.eventType = 'INTEGRATION_RESULT';
        audit.loanRequestId = loan.Id;
        audit.customerId = loan.Customer__c;
        audit.oldValue = previousIntegrationStatus;
        audit.newValue = 'Succeeded';
        audit.customerNameSnapshot = customer == null ? 'Unknown' : customer.Name;
        audit.loanAmountSnapshot = loan.LoanAmount__c;
        audit.occurredAt = System.now();
        audit.actorUserId = ctx.actorUserId;
        audit.correlationId = correlationId;
        audit.source = 'Integration';
        audit.details = SanitizedMessageUtil.sanitize(
            'Callback decision applied: ' + mappedStatus
        );
        try {
            AuditService.commitEvents(new List<AuditEventDto>{ audit });
        } catch (Exception auditEx) {
            ApplicationErrorService.ErrorContext errorCtx =
                new ApplicationErrorService.ErrorContext(
                    'ApprovalCallbackService',
                    'integrationAudit'
                );
            errorCtx.loanRequestId = loan.Id;
            errorCtx.correlationId = correlationId;
            errorCtx.category = 'Automation';
            ApplicationErrorService.logNonCritical(auditEx, errorCtx);
        }

        return LoanApprovalIntegrationContracts.callbackOk(
            loan.Id,
            'Decision applied.'
        );
    }

    private static Boolean isDuplicate(
        LoanRequest__c loan,
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request
    ) {
        if (loan.IntegrationStatus__c == 'Succeeded') {
            if (
                String.isNotBlank(request.externalDecisionReference)
                && request.externalDecisionReference == loan.ExternalDecisionReference__c
            ) {
                return true;
            }
            if (
                loan.LoanStatus__c == 'Approved'
                || loan.LoanStatus__c == 'Rejected'
            ) {
                return true;
            }
        }
        return false;
    }

    private static String mapDecision(String decision) {
        if (String.isBlank(decision)) {
            return null;
        }
        String normalized = decision.trim().toLowerCase();
        if (normalized == 'approved' || normalized == 'approve') {
            return 'Approved';
        }
        if (normalized == 'rejected' || normalized == 'reject') {
            return 'Rejected';
        }
        if (
            normalized == 'under review'
            || normalized == 'under_review'
            || normalized == 'review'
        ) {
            return 'Under Review';
        }
        return null;
    }
}
