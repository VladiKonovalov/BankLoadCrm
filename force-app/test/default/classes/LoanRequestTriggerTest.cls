@IsTest
private class LoanRequestTriggerTest {
    private static void enableAutomation() {
        BankCrmTestDataFactory.enableTrigger();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(
                250000,
                null,
                'Bank_CRM_Default_Manager'
            )
        );
    }

    @IsTest
    static void insert_highValue_createsTaskAndSetsMarker() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            250000,
            true
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
        LoanRequest__c reloaded = [
            SELECT HighValueTaskCreated__c, IntegrationStatus__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals(true, reloaded.HighValueTaskCreated__c);
        System.assertEquals('Not Sent', reloaded.IntegrationStatus__c);
    }

    @IsTest
    static void insert_exactThreshold_noTask() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        LoanRequest__c loan = BankCrmTestDataFactory.createBelowThresholdLoan(
            customer.Id,
            250000,
            true
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
        System.assertEquals(
            false,
            [
                SELECT HighValueTaskCreated__c
                FROM LoanRequest__c
                WHERE Id = :loan.Id
            ]
            .HighValueTaskCreated__c
        );
    }

    @IsTest
    static void bulkInsert_mixedAmounts_createsCorrectTaskCount() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        List<LoanRequest__c> loans = new List<LoanRequest__c>{
            BankCrmTestDataFactory.buildLoanRequest(customer.Id, 100000, 'Draft'),
            BankCrmTestDataFactory.buildLoanRequest(customer.Id, 250000, 'Draft'),
            BankCrmTestDataFactory.buildLoanRequest(customer.Id, 250001, 'Draft'),
            BankCrmTestDataFactory.buildLoanRequest(customer.Id, 400000, 'Draft')
        };

        Test.startTest();
        insert loans;
        Test.stopTest();

        Set<Id> loanIds = new Map<Id, LoanRequest__c>(loans).keySet();
        System.assertEquals(2, [SELECT COUNT() FROM Task WHERE WhatId IN :loanIds]);
        List<LoanRequest__c> reloaded = [
            SELECT LoanAmount__c, HighValueTaskCreated__c
            FROM LoanRequest__c
            WHERE Id IN :loanIds
            ORDER BY LoanAmount__c
        ];
        System.assertEquals(false, reloaded[0].HighValueTaskCreated__c);
        System.assertEquals(false, reloaded[1].HighValueTaskCreated__c);
        System.assertEquals(true, reloaded[2].HighValueTaskCreated__c);
        System.assertEquals(true, reloaded[3].HighValueTaskCreated__c);
    }

    @IsTest
    static void update_statusChange_createsStatusChangedAudit() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );

        Test.startTest();
        loan.LoanStatus__c = 'Submitted';
        loan.SubmissionDate__c = System.now();
        update loan;
        Test.stopTest();

        List<Audit__c> audits = [
            SELECT EventType__c, Source__c, OldValue__c, NewValue__c, CustomerNameSnapshot__c
            FROM Audit__c
            WHERE LoanRequest__c = :loan.Id
        ];
        System.assertEquals(1, audits.size());
        System.assertEquals('STATUS_CHANGED', audits[0].EventType__c);
        System.assertEquals('Apex', audits[0].Source__c);
        System.assertEquals('Draft', audits[0].OldValue__c);
        System.assertEquals('Submitted', audits[0].NewValue__c);
        System.assertEquals(customer.Name, audits[0].CustomerNameSnapshot__c);
    }

    @IsTest
    static void update_amountCrossing_createsOneTask_secondUpdateNone() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createBelowThresholdLoan(
            customer.Id,
            250000,
            true
        );

        Test.startTest();
        loan.LoanAmount__c = 300000;
        update loan;
        loan = [
            SELECT Id, LoanAmount__c, HighValueTaskCreated__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals(true, loan.HighValueTaskCreated__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);

        loan.LoanAmount__c = 350000;
        update loan;
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
    }

    @IsTest
    static void update_illegalTransition_fails() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );

        Boolean failed = false;
        try {
            loan.LoanStatus__c = 'Approved';
            loan.SubmissionDate__c = System.now();
            update loan;
        } catch (DmlException ex) {
            failed = true;
            System.assert(ex.getMessage().contains('not allowed') || ex.getNumDml() > 0);
        }
        System.assertEquals(true, failed);
    }

    @IsTest
    static void markerUpdate_doesNotRecurseIntoDuplicateTasks() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        Test.startTest();
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            250000,
            true
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
    static void update_toApproved_writesAudit_andSendsApprovalEmail() {
        enableAutomation();
        EmailGateway.resetTestState();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        loan.LoanStatus__c = 'Submitted';
        loan.SubmissionDate__c = System.now();
        update loan;

        Test.startTest();
        loan.LoanStatus__c = 'Approved';
        update loan;
        Test.stopTest();

        System.assertEquals(
            2,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'STATUS_CHANGED'
            ]
        );
        System.assertEquals('Approved', [SELECT LoanStatus__c FROM LoanRequest__c WHERE Id = :loan.Id].LoanStatus__c);
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
}
