/**
 * Cross-cutting bulk governor proofs for Part E (200-record trigger chunks).
 */
@IsTest
private class LoanRequestBulkTest {
    private static final Decimal THRESHOLD = 250000;
    private static final Integer CHUNK_SIZE = 200;

    private static void enableAutomation() {
        BankCrmTestDataFactory.enableTrigger();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(
                THRESHOLD,
                null,
                'Bank_CRM_Default_Manager'
            )
        );
        EmailGateway.resetTestState();
        CustomerEmailService.testEmailInvocationCapacity = null;
    }

    @IsTest
    static void bulkInsert_200_mixedAmounts_createsTasksOnlyForHighValue() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        List<LoanRequest__c> loans = new List<LoanRequest__c>();
        Integer highValueCount = 0;
        for (Integer i = 0; i < CHUNK_SIZE; i++) {
            Boolean highValue = Math.mod(i, 2) == 0;
            Decimal amount = highValue ? THRESHOLD + 1 + i : THRESHOLD - Math.mod(i, 1000);
            if (highValue) {
                highValueCount++;
            }
            loans.add(
                BankCrmTestDataFactory.buildLoanRequest(customer.Id, amount, 'Draft')
            );
        }

        Test.startTest();
        insert loans;
        Integer queriesAfterInsert = Limits.getQueries();
        Integer dmlAfterInsert = Limits.getDmlStatements();
        Test.stopTest();

        Set<Id> loanIds = new Map<Id, LoanRequest__c>(loans).keySet();
        System.assertEquals(
            highValueCount,
            [SELECT COUNT() FROM Task WHERE WhatId IN :loanIds],
            'One Task per above-threshold insert'
        );
        System.assertEquals(
            highValueCount,
            [
                SELECT COUNT()
                FROM LoanRequest__c
                WHERE Id IN :loanIds AND HighValueTaskCreated__c = TRUE
            ]
        );
        // O(1) per object type: must not scale linearly with 200 rows.
        System.assert(
            queriesAfterInsert < 40,
            'Expected bounded SOQL for 200-row insert; got ' + queriesAfterInsert
        );
        System.assert(
            dmlAfterInsert < 25,
            'Expected bounded DML for 200-row insert; got ' + dmlAfterInsert
        );
    }

    @IsTest
    static void bulkUpdate_200_statusToApproved_writesAudits_andPreservesDecisions() {
        enableAutomation();
        CustomerEmailService.skipEnqueueInTests = true;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        List<LoanRequest__c> loans = new List<LoanRequest__c>();
        for (Integer i = 0; i < CHUNK_SIZE; i++) {
            loans.add(
                BankCrmTestDataFactory.buildLoanRequest(customer.Id, 1000 + i, 'Draft')
            );
        }
        insert loans;

        for (LoanRequest__c loan : loans) {
            loan.LoanStatus__c = 'Submitted';
            loan.SubmissionDate__c = System.now();
        }
        update loans;

        for (LoanRequest__c loan : loans) {
            loan.LoanStatus__c = 'Approved';
        }

        Test.startTest();
        update loans;
        Integer queriesAfterApprove = Limits.getQueries();
        Integer dmlAfterApprove = Limits.getDmlStatements();
        Test.stopTest();

        Set<Id> loanIds = new Map<Id, LoanRequest__c>(loans).keySet();
        System.assertEquals(
            CHUNK_SIZE,
            [
                SELECT COUNT()
                FROM LoanRequest__c
                WHERE Id IN :loanIds AND LoanStatus__c = 'Approved'
            ],
            'All Approved decisions must remain committed'
        );
        // Draft→Submitted and Submitted→Approved each write STATUS_CHANGED.
        System.assertEquals(
            CHUNK_SIZE * 2,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c IN :loanIds AND EventType__c = 'STATUS_CHANGED'
            ]
        );
        System.assertEquals(
            CHUNK_SIZE,
            LoanRequestDomainService.deferredApprovedLoanIds == null
                ? 0
                : LoanRequestDomainService.deferredApprovedLoanIds.size(),
            'Domain should plan approval email enqueue for all Approved loans'
        );
        System.assert(
            queriesAfterApprove < 50,
            'Expected bounded SOQL for 200-row approve; got ' + queriesAfterApprove
        );
        System.assert(
            dmlAfterApprove < 25,
            'Expected bounded DML for 200-row approve; got ' + dmlAfterApprove
        );
        CustomerEmailService.skipEnqueueInTests = false;
    }

    @IsTest
    static void bulkUpdate_200_amountCrossing_oneTaskEach_secondPassNone() {
        enableAutomation();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );

        List<LoanRequest__c> loans = new List<LoanRequest__c>();
        for (Integer i = 0; i < CHUNK_SIZE; i++) {
            loans.add(
                BankCrmTestDataFactory.buildLoanRequest(customer.Id, THRESHOLD, 'Draft')
            );
        }
        insert loans;
        Set<Id> loanIds = new Map<Id, LoanRequest__c>(loans).keySet();
        System.assertEquals(0, [SELECT COUNT() FROM Task WHERE WhatId IN :loanIds]);

        for (LoanRequest__c loan : loans) {
            loan.LoanAmount__c = THRESHOLD + 100;
        }

        Test.startTest();
        update loans;
        Test.stopTest();

        System.assertEquals(CHUNK_SIZE, [SELECT COUNT() FROM Task WHERE WhatId IN :loanIds]);
        List<LoanRequest__c> marked = [
            SELECT Id, LoanAmount__c, HighValueTaskCreated__c
            FROM LoanRequest__c
            WHERE Id IN :loanIds
        ];
        for (LoanRequest__c loan : marked) {
            System.assertEquals(true, loan.HighValueTaskCreated__c);
            loan.LoanAmount__c = THRESHOLD + 500;
        }
        update marked;

        // Still-above updates must not create duplicate Tasks.
        System.assertEquals(CHUNK_SIZE, [SELECT COUNT() FROM Task WHERE WhatId IN :loanIds]);
    }
}
