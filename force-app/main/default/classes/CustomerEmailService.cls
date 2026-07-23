/**
 * Plans and sends customer approval confirmation emails.
 * Failures are non-critical and must not roll back Approved loan decisions.
 */
public with sharing class CustomerEmailService {
    private static final Integer MAX_MESSAGES_PER_SEND = 10;
    private static final String EVENT_APPROVAL_EMAIL_SENT = 'APPROVAL_EMAIL_SENT';
    private static final String SOURCE_COMPONENT = 'CustomerEmailService';

    @TestVisible
    private static Integer testEmailInvocationCapacity;
    @TestVisible
    private static Boolean skipEnqueueInTests = false;

    public static EmailPlan planApprovalEmails(List<LoanRequestChange> changes) {
        EmailPlan plan = new EmailPlan();
        if (changes == null || changes.isEmpty()) {
            return plan;
        }

        List<LoanRequestChange> approved = new List<LoanRequestChange>();
        Set<Id> customerIds = new Set<Id>();
        Set<Id> loanIds = new Set<Id>();
        for (LoanRequestChange change : changes) {
            if (change == null || !change.transitionedToApproved() || change.loanRequestId == null) {
                continue;
            }
            approved.add(change);
            loanIds.add(change.loanRequestId);
            if (change.customerId != null) {
                customerIds.add(change.customerId);
            }
        }
        if (approved.isEmpty()) {
            return plan;
        }

        Map<Id, CustomerRepository.EmailRoutingData> customersById =
            CustomerRepository.getEmailRoutingData(customerIds);
        Map<Id, LoanRequest__c> loansById = new Map<Id, LoanRequest__c>(
            LoanRequestRepository.getByIds(loanIds)
        );

        for (LoanRequestChange change : approved) {
            CustomerRepository.EmailRoutingData customer = customersById.get(change.customerId);
            LoanRequest__c loan = loansById.get(change.loanRequestId);
            String loanReference = loan == null || String.isBlank(loan.Name)
                ? String.valueOf(change.loanRequestId)
                : loan.Name;
            String recipient = customer == null ? null : customer.email;
            String customerName = customer == null ? null : customer.name;

            plan.add(
                new EmailPlan.EmailItem(
                    change.loanRequestId,
                    change.customerId,
                    recipient,
                    customerName,
                    loanReference,
                    change.newAmount,
                    null
                )
            );
        }
        return plan;
    }

    /**
     * Enqueues post-commit approval email work so email limits cannot roll back decisions.
     */
    public static Id enqueueApprovalEmails(Set<Id> loanIds, DomainExecutionContext ctx) {
        if (loanIds == null || loanIds.isEmpty()) {
            return null;
        }
        if (Test.isRunningTest() && skipEnqueueInTests == true) {
            return null;
        }
        String correlationId = ctx == null ? CorrelationIdUtil.currentOrNew() : ctx.correlationId;
        return System.enqueueJob(new CustomerApprovalEmailQueueable(loanIds, correlationId));
    }

    /**
     * Re-queries Approved loans and sends approval emails (Queueable entry point).
     */
    public static void sendForLoanIds(Set<Id> loanIds, DomainExecutionContext ctx) {
        if (loanIds == null || loanIds.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        List<LoanRequest__c> loans = LoanRequestRepository.getByIds(loanIds);
        EmailPlan plan = new EmailPlan();
        Set<Id> customerIds = new Set<Id>();
        for (LoanRequest__c loan : loans) {
            if (loan == null || loan.LoanStatus__c != 'Approved' || loan.Customer__c == null) {
                continue;
            }
            customerIds.add(loan.Customer__c);
        }
        Map<Id, CustomerRepository.EmailRoutingData> customersById =
            CustomerRepository.getEmailRoutingData(customerIds);

        for (LoanRequest__c loan : loans) {
            if (loan == null || loan.LoanStatus__c != 'Approved') {
                continue;
            }
            CustomerRepository.EmailRoutingData customer = customersById.get(loan.Customer__c);
            plan.add(
                new EmailPlan.EmailItem(
                    loan.Id,
                    loan.Customer__c,
                    customer == null ? null : customer.email,
                    customer == null ? null : customer.name,
                    String.isBlank(loan.Name) ? String.valueOf(loan.Id) : loan.Name,
                    loan.LoanAmount__c,
                    context.correlationId
                )
            );
        }
        send(plan, context);
    }

    public static void send(EmailPlan plan, DomainExecutionContext ctx) {
        if (plan == null || plan.isEmpty()) {
            return;
        }
        DomainExecutionContext context = resolveContext(ctx);
        List<EmailPlan.EmailItem> items = plan.getItems();
        List<EmailPlan.EmailItem> sendable = new List<EmailPlan.EmailItem>();

        for (EmailPlan.EmailItem item : items) {
            if (item == null) {
                continue;
            }
            if (String.isBlank(item.recipientEmail)) {
                ApplicationErrorService.logNonCritical(
                    new BankCrmException('Missing customer email for approval notification.'),
                    buildEmailErrorContext(item, context, 'send-missing-email')
                );
                continue;
            }
            if (String.isBlank(item.correlationId)) {
                item.correlationId = context.correlationId;
            }
            sendable.add(item);
        }
        if (sendable.isEmpty()) {
            return;
        }

        Integer remainingInvocations = remainingEmailInvocations();
        Integer maxMessages = remainingInvocations * MAX_MESSAGES_PER_SEND;
        List<EmailPlan.EmailItem> withinCapacity = new List<EmailPlan.EmailItem>();
        List<EmailPlan.EmailItem> overflow = new List<EmailPlan.EmailItem>();
        for (Integer i = 0; i < sendable.size(); i++) {
            if (i < maxMessages) {
                withinCapacity.add(sendable[i]);
            } else {
                overflow.add(sendable[i]);
            }
        }
        for (EmailPlan.EmailItem item : overflow) {
            ApplicationErrorService.logNonCritical(
                new BankCrmException('Email invocation capacity exceeded for approval notification.'),
                buildEmailErrorContext(item, context, 'send-capacity-overflow')
            );
        }
        if (withinCapacity.isEmpty()) {
            return;
        }

        List<AuditEventDto> successAudits = new List<AuditEventDto>();
        for (Integer offset = 0; offset < withinCapacity.size(); offset += MAX_MESSAGES_PER_SEND) {
            Integer endExclusive = Math.min(offset + MAX_MESSAGES_PER_SEND, withinCapacity.size());
            List<EmailPlan.EmailItem> chunk = new List<EmailPlan.EmailItem>();
            for (Integer i = offset; i < endExclusive; i++) {
                chunk.add(withinCapacity[i]);
            }
            sendChunk(chunk, context, successAudits);
        }

        if (!successAudits.isEmpty()) {
            try {
                AuditService.commitEvents(successAudits);
            } catch (Exception auditEx) {
                ApplicationErrorService.logNonCritical(
                    auditEx,
                    new ApplicationErrorService.ErrorContext(SOURCE_COMPONENT, 'approval-email-audit')
                );
            }
        }
    }

    private static void sendChunk(
        List<EmailPlan.EmailItem> chunk,
        DomainExecutionContext context,
        List<AuditEventDto> successAudits
    ) {
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (EmailPlan.EmailItem item : chunk) {
            messages.add(
                EmailMessageBuilder.buildApprovalEmail(
                    new EmailMessageBuilder.CustomerEmailContext(
                        item.customerName,
                        item.recipientEmail,
                        item.loanReference,
                        item.loanAmount,
                        item.correlationId
                    )
                )
            );
        }

        List<Messaging.SendEmailResult> results;
        try {
            results = EmailGateway.send(messages, false);
        } catch (Exception sendEx) {
            for (EmailPlan.EmailItem item : chunk) {
                ApplicationErrorService.logNonCritical(
                    sendEx,
                    buildEmailErrorContext(item, context, 'send-exception')
                );
            }
            return;
        }

        for (Integer i = 0; i < chunk.size(); i++) {
            EmailPlan.EmailItem item = chunk[i];
            Boolean success = results != null
                && i < results.size()
                && results[i] != null
                && results[i].isSuccess();
            if (success) {
                successAudits.add(buildApprovalEmailAudit(item, context));
            } else {
                String detail = 'Approval email send failed.';
                if (results != null && i < results.size() && results[i] != null) {
                    Messaging.SendEmailError[] errors = results[i].getErrors();
                    if (errors != null && !errors.isEmpty() && errors[0] != null) {
                        detail = errors[0].getMessage();
                    }
                }
                ApplicationErrorService.logNonCritical(
                    new BankCrmException(detail),
                    buildEmailErrorContext(item, context, 'send-result-failure')
                );
            }
        }
    }

    private static AuditEventDto buildApprovalEmailAudit(
        EmailPlan.EmailItem item,
        DomainExecutionContext context
    ) {
        AuditEventDto event = new AuditEventDto();
        event.eventType = EVENT_APPROVAL_EMAIL_SENT;
        event.loanRequestId = item.loanRequestId;
        event.customerId = item.customerId;
        event.customerNameSnapshot = String.isBlank(item.customerName)
            ? 'Customer'
            : item.customerName;
        event.loanAmountSnapshot = item.loanAmount == null ? 0 : item.loanAmount;
        event.occurredAt = System.now();
        event.actorUserId = context.actorUserId;
        event.correlationId = item.correlationId == null
            ? context.correlationId
            : item.correlationId;
        event.source = 'Apex';
        event.details = 'Approval email sent for loan ' + item.loanReference;
        event.oldValue = null;
        event.newValue = 'Sent';
        return event;
    }

    private static ApplicationErrorService.ErrorContext buildEmailErrorContext(
        EmailPlan.EmailItem item,
        DomainExecutionContext context,
        String operation
    ) {
        ApplicationErrorService.ErrorContext errorCtx =
            new ApplicationErrorService.ErrorContext(SOURCE_COMPONENT, operation);
        if (item != null) {
            errorCtx.loanRequestId = item.loanRequestId;
            errorCtx.customerId = item.customerId;
        }
        errorCtx.correlationId = context == null
            ? CorrelationIdUtil.currentOrNew()
            : context.correlationId;
        errorCtx.category = 'Notification';
        errorCtx.retryable = true;
        return errorCtx;
    }

    private static Integer remainingEmailInvocations() {
        if (Test.isRunningTest() && testEmailInvocationCapacity != null) {
            return Math.max(0, testEmailInvocationCapacity);
        }
        return Limits.getLimitEmailInvocations() - Limits.getEmailInvocations();
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
}
