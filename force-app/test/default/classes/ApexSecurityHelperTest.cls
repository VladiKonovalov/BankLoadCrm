@IsTest
private class ApexSecurityHelperTest {
    @IsTest
    static void assertCreateable_null_throwsAuthorization() {
        try {
            ApexSecurityHelper.assertCreateable(null);
            System.assert(false, 'Expected AuthorizationException');
        } catch (BankCrmException.AuthorizationException ex) {
            System.assert(ex.getMessage().contains('create'));
        }
    }

    @IsTest
    static void assertCreateable_customer_doesNotThrowForAdmin() {
        ApexSecurityHelper.assertCreateable(Customer__c.SObjectType);
    }

    @IsTest
    static void stripInaccessible_returnsSameSizeList() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(false);
        List<SObject> stripped = ApexSecurityHelper.stripInaccessible(
            AccessType.CREATABLE,
            new List<SObject>{ customer }
        );
        System.assertEquals(1, stripped.size());
    }

    @IsTest
    static void canEditIntegrationFields_returnsBoolean() {
        Boolean canEdit = ApexSecurityHelper.canEditIntegrationFields();
        System.assertNotEquals(null, canEdit);
    }

    @IsTest
    static void dto_omitsSensitiveFieldsByConstruction() {
        LoanRequestDto dto = new LoanRequestDto();
        dto.customerId = UserInfo.getUserId();
        dto.loanAmount = 1000;
        dto.loanStatus = 'Draft';
        LoanRequest__c record = dto.toSObject();

        Map<String, Object> populated = record.getPopulatedFieldsAsMap();
        System.assert(!populated.containsKey('ExternalRequestId__c'));
        System.assert(!populated.containsKey('DecisionReason__c'));
        System.assert(!populated.containsKey('IntegrationStatus__c'));
    }

    @IsTest
    static void auditEventDto_toSObject_mapsCoreFields() {
        AuditEventDto event = new AuditEventDto();
        event.eventType = 'STATUS_CHANGED';
        event.oldValue = 'Draft';
        event.newValue = 'Submitted';
        event.customerNameSnapshot = 'Ada';
        event.loanAmountSnapshot = 1000;
        event.correlationId = 'corr-1';
        event.source = 'Apex';
        event.details = 'bearer secret-token-value detail';

        Audit__c audit = event.toSObject();
        System.assertEquals('STATUS_CHANGED', audit.EventType__c);
        System.assertEquals('Draft', audit.OldValue__c);
        System.assertEquals('Submitted', audit.NewValue__c);
        System.assertEquals('Ada', audit.CustomerNameSnapshot__c);
        System.assertEquals(1000, audit.LoanAmountSnapshot__c);
        System.assertEquals('corr-1', audit.CorrelationId__c);
        System.assertEquals('Apex', audit.Source__c);
        System.assert(audit.Details__c.contains('[REDACTED]'));
    }

    @IsTest
    static void plans_collectSideEffects() {
        TaskPlan taskPlan = new TaskPlan();
        System.assertEquals(true, taskPlan.isEmpty());
        taskPlan.add(new Task(Subject = 'Review'), UserInfo.getUserId());
        System.assertEquals(1, taskPlan.size());
        System.assertEquals(1, taskPlan.getLoanRequestIds().size());
        taskPlan.addMarkerReset(UserInfo.getUserId());
        System.assertEquals(1, taskPlan.getMarkerResetLoanIds().size());

        EmailPlan emailPlan = new EmailPlan();
        emailPlan.add(
            new EmailPlan.EmailItem(
                UserInfo.getUserId(),
                UserInfo.getUserId(),
                'a@example.com',
                'Ada',
                'LR-1',
                1000,
                'c-1'
            )
        );
        System.assertEquals(1, emailPlan.size());
        System.assertEquals(false, emailPlan.isEmpty());
    }

    @IsTest
    static void domainContext_andContracts_construct() {
        BankCrmSettings settings = BankCrmTestDataFactory.buildSettings(250000);
        DomainExecutionContext ctx = DomainExecutionContext.forCurrentUser(settings);
        System.assertEquals('Apex', ctx.sourceApiValue());
        System.assertEquals(UserInfo.getUserId(), ctx.actorUserId);
        System.assertNotEquals(null, ctx.correlationId);

        LoanApprovalIntegrationContracts.OutboundRequest request =
            new LoanApprovalIntegrationContracts.OutboundRequest();
        request.externalRequestId = 'ext-1';
        request.loanAmount = 1000;
        System.assertEquals('ext-1', request.externalRequestId);

        SaveResultDto ok = SaveResultDto.success(UserInfo.getUserId(), 'c-1');
        System.assertEquals(true, ok.success);
        SaveResultDto fail = SaveResultDto.failure(
            'c-2',
            new List<ValidationFailure>{ new ValidationFailure('LoanAmount__c', 'Required') }
        );
        System.assertEquals(false, fail.success);
        System.assertEquals(1, fail.errors.size());
    }

    @IsTest
    static void canReopenFinalLoanDecision_returnsBoolean() {
        Boolean canReopen = ApexSecurityHelper.canReopenFinalLoanDecision();
        System.assertNotEquals(null, canReopen);
    }
}
