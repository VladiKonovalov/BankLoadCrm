@IsTest
private class LoanRequestDomainServiceTest {
    private static void isolateFromTrigger() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
    }

    @IsTest
    static void processAfterInsert_highValue_createsTask() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            threshold,
            true
        );
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        Test.startTest();
        LoanRequestDomainService.processAfterInsert(
            new List<LoanRequest__c>{ loan },
            ctx
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
        System.assertEquals(
            true,
            [
                SELECT HighValueTaskCreated__c
                FROM LoanRequest__c
                WHERE Id = :loan.Id
            ]
            .HighValueTaskCreated__c
        );
    }

    @IsTest
    static void processAfterUpdate_statusChange_createsAudit_amountOnly_none() {
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
        DomainExecutionContext ctx = BankCrmTestDataFactory.buildContext(
            BankCrmSettingsProvider.getSettings()
        );

        LoanRequest__c amountOnly = oldLoan.clone(true, true, true, true);
        amountOnly.LoanAmount__c = 2000;
        LoanRequestDomainService.processAfterUpdate(
            new List<LoanRequest__c>{ amountOnly },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            ctx
        );
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Audit__c WHERE LoanRequest__c = :oldLoan.Id]
        );

        LoanRequest__c statusChange = oldLoan.clone(true, true, true, true);
        statusChange.LoanStatus__c = 'Submitted';
        statusChange.SubmissionDate__c = System.now();

        Test.startTest();
        LoanRequestDomainService.processAfterUpdate(
            new List<LoanRequest__c>{ statusChange },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            ctx
        );
        Test.stopTest();

        List<Audit__c> audits = [
            SELECT EventType__c, Source__c, OldValue__c, NewValue__c
            FROM Audit__c
            WHERE LoanRequest__c = :oldLoan.Id
        ];
        System.assertEquals(1, audits.size());
        System.assertEquals('STATUS_CHANGED', audits[0].EventType__c);
        System.assertEquals('Apex', audits[0].Source__c);
        System.assertEquals('Draft', audits[0].OldValue__c);
        System.assertEquals('Submitted', audits[0].NewValue__c);
    }

    @IsTest
    static void processAfterUpdate_markerOnly_isNoOp() {
        isolateFromTrigger();
        Decimal threshold = 250000;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            threshold,
            true
        );
        LoanRequest__c markerOnly = oldLoan.clone(true, true, true, true);
        markerOnly.HighValueTaskCreated__c = true;

        LoanRequestDomainService.processAfterUpdate(
            new List<LoanRequest__c>{ markerOnly },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :oldLoan.Id]);
        System.assertEquals(
            0,
            [SELECT COUNT() FROM Audit__c WHERE LoanRequest__c = :oldLoan.Id]
        );
    }

    @IsTest
    static void processAfterUpdate_approved_enqueuesEmailAndSends() {
        isolateFromTrigger();
        EmailGateway.resetTestState();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c oldLoan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Submitted',
            true
        );
        LoanRequest__c approved = oldLoan.clone(true, true, true, true);
        approved.LoanStatus__c = 'Approved';
        // Persist Approved so the post-commit Queueable re-query sees the final status.
        update approved;

        Test.startTest();
        LoanRequestDomainService.processAfterUpdate(
            new List<LoanRequest__c>{ approved },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan },
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );
        Test.stopTest();

        System.assertNotEquals(null, LoanRequestDomainService.deferredApprovedLoanIds);
        System.assertEquals(
            true,
            LoanRequestDomainService.deferredApprovedLoanIds.contains(oldLoan.Id)
        );
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :oldLoan.Id AND EventType__c = 'STATUS_CHANGED'
            ]
        );
        System.assertEquals(1, EmailGateway.getCapturedMessages().size());
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :oldLoan.Id AND EventType__c = 'APPROVAL_EMAIL_SENT'
            ]
        );
    }
}
