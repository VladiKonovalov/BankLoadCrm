@IsTest
private class AuditServiceTest {
    private static void isolateFromTrigger() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
    }

    @IsTest
    static void statusChange_createsStatusChangedAudit() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanStatus__c = 'Submitted';
        newLoan.SubmissionDate__c = System.now();

        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(settings);

        Test.startTest();
        List<AuditEventDto> planned = AuditService.planStatusChangeAudits(
            new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(newLoan, oldLoan) },
            ctx
        );
        AuditService.commitEvents(planned);
        Test.stopTest();

        System.assertEquals(1, planned.size());
        Audit__c audit = [
            SELECT
                EventType__c,
                Source__c,
                OldValue__c,
                NewValue__c,
                CustomerNameSnapshot__c,
                LoanAmountSnapshot__c,
                CorrelationId__c,
                LoanRequest__c
            FROM Audit__c
            WHERE LoanRequest__c = :oldLoan.Id
            LIMIT 1
        ];
        System.assertEquals('STATUS_CHANGED', audit.EventType__c);
        System.assertEquals('Apex', audit.Source__c);
        System.assertEquals('Draft', audit.OldValue__c);
        System.assertEquals('Submitted', audit.NewValue__c);
        System.assertEquals(customer.Name, audit.CustomerNameSnapshot__c);
        System.assertEquals(1000, audit.LoanAmountSnapshot__c);
        System.assertEquals(ctx.correlationId, audit.CorrelationId__c);
    }

    @IsTest
    static void amountOnlyUpdate_doesNotPlanStatusAudit() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        LoanRequest__c newLoan = oldLoan.clone(true, true, true, true);
        newLoan.LoanAmount__c = 2000;

        List<AuditEventDto> planned = AuditService.planStatusChangeAudits(
            new List<LoanRequestChange>{ LoanRequestChange.fromTrigger(newLoan, oldLoan) },
            BankCrmTestDataFactory.buildContext(BankCrmTestDataFactory.buildSettings(250000))
        );
        System.assertEquals(0, planned.size());
    }

    @IsTest
    static void planEvent_rejectsFlowOwnedHighValueReview() {
        isolateFromTrigger();
        AuditEventDto dto = new AuditEventDto();
        dto.eventType = 'HIGH_VALUE_STATUS_REVIEW';
        dto.loanRequestId = UserInfo.getUserId();
        dto.customerNameSnapshot = 'Ada';
        dto.loanAmountSnapshot = 1;

        Boolean threw = false;
        try {
            AuditService.planEvent(dto);
        } catch (BankCrmException.ValidationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Flow'));
        }
        System.assertEquals(true, threw);
    }

    @IsTest
    static void planEvent_supportsApprovalEmailSentHook() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        AuditEventDto dto = new AuditEventDto();
        dto.eventType = 'APPROVAL_EMAIL_SENT';
        dto.loanRequestId = loan.Id;
        dto.customerId = customer.Id;
        dto.customerNameSnapshot = customer.Name;
        dto.loanAmountSnapshot = 1000;
        dto.details = 'Approval email sent';

        AuditEventDto planned = AuditService.planEvent(dto);
        System.assertEquals('Apex', planned.source);

        Test.startTest();
        AuditService.commitEvents(new List<AuditEventDto>{ planned });
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'APPROVAL_EMAIL_SENT'
            ]
        );
    }

    @IsTest
    static void commitEvents_invalidStatusChange_throwsValidationException() {
        isolateFromTrigger();
        AuditEventDto dto = new AuditEventDto();
        dto.eventType = 'STATUS_CHANGED';
        dto.loanRequestId = UserInfo.getUserId();
        dto.oldValue = 'Draft';
        dto.newValue = 'Draft';
        dto.customerNameSnapshot = 'Ada';
        dto.loanAmountSnapshot = 1000;

        Boolean threw = false;
        try {
            AuditService.commitEvents(new List<AuditEventDto>{ dto });
        } catch (BankCrmException.ValidationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('STATUS_CHANGED'));
        }
        System.assertEquals(true, threw);
    }
}
