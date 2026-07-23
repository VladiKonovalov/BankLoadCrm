@IsTest
private class LoanRequestTriggerHandlerTest {
    @IsTest
    static void beforeInsert_defaultsIntegrationStatus() {
        BankCrmTestDataFactory.enableTrigger();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = new LoanRequest__c(
            Customer__c = customer.Id,
            LoanAmount__c = 1000,
            LoanStatus__c = 'Draft'
        );

        Test.startTest();
        LoanRequestTriggerHandler.run(
            System.TriggerOperation.BEFORE_INSERT,
            new List<LoanRequest__c>{ loan },
            null
        );
        Test.stopTest();

        System.assertEquals('Not Sent', loan.IntegrationStatus__c);
        System.assertEquals(false, loan.HighValueTaskCreated__c);
    }

    @IsTest
    static void beforeUpdate_illegalTransition_addsError() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
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
        newLoan.LoanStatus__c = 'Approved';
        newLoan.SubmissionDate__c = System.now();
        LoanRequestValidationService.capturedTriggerErrors = new List<String>();

        LoanRequestTriggerHandler.bypassTrigger = false;
        LoanRequestTriggerHandler.run(
            System.TriggerOperation.BEFORE_UPDATE,
            new List<LoanRequest__c>{ newLoan },
            new Map<Id, LoanRequest__c>{ oldLoan.Id => oldLoan }
        );

        System.assert(
            String.join(LoanRequestValidationService.capturedTriggerErrors, '|')
                .contains('not allowed')
        );
    }

    @IsTest
    static void afterInsert_delegatesToDomain_highValueTask() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createHighValueLoan(
            customer.Id,
            250000,
            true
        );

        LoanRequestTriggerHandler.bypassTrigger = false;
        Test.startTest();
        LoanRequestTriggerHandler.run(
            System.TriggerOperation.AFTER_INSERT,
            new List<LoanRequest__c>{ loan },
            null
        );
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :loan.Id]);
    }
}
