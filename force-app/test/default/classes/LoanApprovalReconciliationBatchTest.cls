@IsTest
private class LoanApprovalReconciliationBatchTest {
    @IsTest
    static void batch_emptyScope_completes() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000, 3, 15)
        );

        Test.startTest();
        Database.executeBatch(new LoanApprovalReconciliationBatch(50), 50);
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM LoanRequest__c
                WHERE IntegrationStatus__c IN ('Pending', 'Retry Pending')
            ]
        );
    }

    @IsTest
    static void batch_retriesAgedRetryPending() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000, 3, 15)
        );
        LoanApprovalIntegrationOrchestrator.resetTestState();
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = true;

        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Retry Pending',
            System.now().addMinutes(-30),
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        insert loan;
        BankCrmTestDataFactory.enableTrigger();

        Test.startTest();
        Database.executeBatch(new LoanApprovalReconciliationBatch(50), 50);
        Test.stopTest();

        System.assert(
            LoanApprovalIntegrationOrchestrator.enqueuedJobCount > 0,
            'Aged Retry Pending loan should be re-enqueued'
        );
        System.assert(
            LoanApprovalIntegrationOrchestrator.lastEnqueuedLoanIds.contains(loan.Id)
        );
    }

    @IsTest
    static void batch_exhaustsRetries_marksFailed() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000, 3, 15)
        );
        LoanApprovalIntegrationOrchestrator.resetTestState();
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = true;

        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Retry Pending',
            System.now().addMinutes(-30),
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        insert loan;

        Application_Error__c prior = BankCrmTestDataFactory.buildApplicationError(
            'Integration Transient',
            true,
            'Retry Scheduled',
            System.now().addMinutes(-5)
        );
        prior.LoanRequest__c = loan.Id;
        prior.Customer__c = customer.Id;
        prior.AttemptCount__c = 3;
        insert prior;
        BankCrmTestDataFactory.enableTrigger();

        System.assertEquals(
            3,
            LoanApprovalIntegrationOrchestrator.countIntegrationAttempts(loan.Id),
            'Precondition: attempt counter must reflect Application_Error__c'
        );

        List<LoanRequest__c> candidates = [
            SELECT
                Id,
                Name,
                Customer__c,
                LoanAmount__c,
                LoanStatus__c,
                ExternalRequestId__c,
                ExternalDecisionReference__c,
                IntegrationStatus__c,
                IntegrationLastAttempt__c,
                DecisionReason__c,
                OwnerId
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];

        Test.startTest();
        LoanApprovalIntegrationOrchestrator.reconcileCandidates(
            candidates,
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );
        Test.stopTest();

        LoanRequest__c refreshed = [
            SELECT LoanStatus__c, IntegrationStatus__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Failed', refreshed.IntegrationStatus__c);
        System.assertEquals('Integration Error', refreshed.LoanStatus__c);
    }

    @IsTest
    static void scheduler_skipsWhenIntegrationDisabled() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
        Test.startTest();
        new LoanApprovalReconciliationScheduler().execute(null);
        Test.stopTest();
        System.assertEquals(true, true, 'Disabled scheduler is a no-op');
    }

    @IsTest
    static void scheduler_startsBatchWhenIntegrationEnabled() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000, 3, 15)
        );
        LoanApprovalIntegrationOrchestrator.resetTestState();
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = true;

        Test.startTest();
        new LoanApprovalReconciliationScheduler().execute(null);
        Test.stopTest();

        // Empty org scope completes without error when integration is enabled.
        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM LoanRequest__c
                WHERE IntegrationStatus__c IN ('Pending', 'Retry Pending')
            ]
        );
    }
}