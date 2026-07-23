@IsTest
private class CustomerEmailServiceTest {
    private static void setupSettings() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
        EmailGateway.resetTestState();
        CustomerEmailService.testEmailInvocationCapacity = null;
    }

    @IsTest
    static void planApprovalEmails_onlyTransitionIntoApproved() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c submitted = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Submitted',
            true
        );
        LoanRequest__c alreadyApproved = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );

        List<LoanRequestChange> changes = new List<LoanRequestChange>{
            LoanRequestChange.fromTrigger(
                cloneWithStatus(submitted, 'Approved'),
                submitted
            ),
            LoanRequestChange.fromTrigger(
                cloneWithStatus(alreadyApproved, 'Approved'),
                alreadyApproved
            )
        };

        EmailPlan plan = CustomerEmailService.planApprovalEmails(changes);
        System.assertEquals(1, plan.size());
        System.assertEquals(submitted.Id, plan.getItems()[0].loanRequestId);
        System.assertEquals(customer.Email__c, plan.getItems()[0].recipientEmail);
    }

    @IsTest
    static void send_success_createsApprovalEmailSentAudit() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        EmailPlan plan = new EmailPlan();
        plan.add(
            new EmailPlan.EmailItem(
                loan.Id,
                customer.Id,
                customer.Email__c,
                customer.Name,
                loan.Name,
                loan.LoanAmount__c,
                ctx.correlationId
            )
        );

        Test.startTest();
        CustomerEmailService.send(plan, ctx);
        Test.stopTest();

        System.assertEquals(1, EmailGateway.getCapturedMessages().size());
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'APPROVAL_EMAIL_SENT'
            ]
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Application_Error__c WHERE LoanRequest__c = :loan.Id]
        );
    }

    @IsTest
    static void send_failure_logsError_withoutThrowing() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        EmailGateway.mockThrow = true;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        EmailPlan plan = new EmailPlan();
        plan.add(
            new EmailPlan.EmailItem(
                loan.Id,
                customer.Id,
                customer.Email__c,
                customer.Name,
                loan.Name,
                loan.LoanAmount__c,
                ctx.correlationId
            )
        );

        Test.startTest();
        CustomerEmailService.send(plan, ctx);
        Test.stopTest();

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Application_Error__c
                WHERE LoanRequest__c = :loan.Id AND Category__c = 'Notification'
            ]
        );
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'APPROVAL_EMAIL_SENT'
            ]
        );
        System.assertEquals('Approved', [SELECT LoanStatus__c FROM LoanRequest__c WHERE Id = :loan.Id].LoanStatus__c);
    }

    @IsTest
    static void send_missingEmail_logsNonCritical() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        EmailPlan plan = new EmailPlan();
        plan.add(
            new EmailPlan.EmailItem(
                loan.Id,
                customer.Id,
                null,
                customer.Name,
                loan.Name,
                loan.LoanAmount__c,
                ctx.correlationId
            )
        );

        CustomerEmailService.send(plan, ctx);

        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Application_Error__c
                WHERE LoanRequest__c = :loan.Id AND Category__c = 'Notification'
            ]
        );
        System.assertEquals(0, EmailGateway.getCapturedMessages().size());
    }

    @IsTest
    static void send_capacityOverflow_logsRetryableErrors() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        CustomerEmailService.testEmailInvocationCapacity = 0;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        EmailPlan plan = new EmailPlan();
        plan.add(
            new EmailPlan.EmailItem(
                loan.Id,
                customer.Id,
                customer.Email__c,
                customer.Name,
                loan.Name,
                loan.LoanAmount__c,
                ctx.correlationId
            )
        );

        CustomerEmailService.send(plan, ctx);

        Application_Error__c error = [
            SELECT IsRetryable__c, ResolutionStatus__c, SanitizedMessage__c
            FROM Application_Error__c
            WHERE LoanRequest__c = :loan.Id
            LIMIT 1
        ];
        System.assertEquals(true, error.IsRetryable__c);
        System.assertEquals('Retry Scheduled', error.ResolutionStatus__c);
        System.assert(error.SanitizedMessage__c.contains('capacity'));
        System.assertEquals(0, EmailGateway.getCapturedMessages().size());
    }

    @IsTest
    static void send_bulkTen_oneGatewayCaptureBatch() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );
        EmailPlan plan = new EmailPlan();
        for (Integer i = 0; i < 10; i++) {
            LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
                customer.Id,
                1000 + i,
                'Approved',
                true
            );
            plan.add(
                new EmailPlan.EmailItem(
                    loan.Id,
                    customer.Id,
                    customer.Email__c,
                    customer.Name,
                    loan.Name,
                    loan.LoanAmount__c,
                    ctx.correlationId
                )
            );
        }

        Test.startTest();
        CustomerEmailService.send(plan, ctx);
        Test.stopTest();

        System.assertEquals(10, EmailGateway.getCapturedMessages().size());
        System.assertEquals(
            10,
            [SELECT COUNT() FROM Audit__c WHERE EventType__c = 'APPROVAL_EMAIL_SENT']
        );
    }

    @IsTest
    static void enqueueAndQueueable_sendsForApprovedLoans() {
        setupSettings();
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Approved',
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        Test.startTest();
        Id jobId = CustomerEmailService.enqueueApprovalEmails(new Set<Id>{ loan.Id }, ctx);
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        System.assertEquals(1, EmailGateway.getCapturedMessages().size());
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
    static void emailMessageBuilder_setsSubjectAndBody() {
        Messaging.SingleEmailMessage message = EmailMessageBuilder.buildApprovalEmail(
            new EmailMessageBuilder.CustomerEmailContext(
                'Ada Lovelace',
                'ada@example.com',
                'LR-1',
                1000,
                'corr-1'
            )
        );
        System.assertEquals(new List<String>{ 'ada@example.com' }, message.getToAddresses());
        System.assert(message.getSubject().contains('LR-1'));
        System.assert(message.getPlainTextBody().contains('Ada Lovelace'));
        System.assert(message.getPlainTextBody().contains('1000'));
        System.assert(!message.getPlainTextBody().toLowerCase().contains('national'));
    }

    private static LoanRequest__c cloneWithStatus(LoanRequest__c source, String status) {
        LoanRequest__c clone = source.clone(true, true, true, true);
        clone.LoanStatus__c = status;
        return clone;
    }
}
