@IsTest
private class LoanApprovalIntegrationOrchestratorTest {
    private static void enableIntegration() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000)
        );
        LoanApprovalIntegrationOrchestrator.resetTestState();
        CorrelationIdUtil.clearForTest();
    }

    private static void disableIntegration() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
        LoanApprovalIntegrationOrchestrator.resetTestState();
    }

    private static LoanRequest__c createSubmittedLoanWithoutEnqueue() {
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = true;
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Submitted',
            true
        );
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = false;
        LoanApprovalIntegrationOrchestrator.enqueuedJobCount = 0;
        LoanApprovalIntegrationOrchestrator.lastEnqueuedLoanIds = new List<Id>();
        return loan;
    }

    private static void injectHttpResponse(BankCrmHttpCalloutMock.Mode mode) {
        LoanApprovalIntegrationOrchestrator.testHttpResponse = new BankCrmHttpCalloutMock(mode)
            .respond(new HttpRequest());
    }

    @IsTest
    static void enqueueEligibleLoans_disabled_doesNotEnqueue() {
        disableIntegration();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Submitted',
            true
        );

        Test.startTest();
        LoanApprovalIntegrationOrchestrator.enqueueEligibleLoans(
            new Set<Id>{ loan.Id },
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );
        Test.stopTest();

        System.assertEquals(0, LoanApprovalIntegrationOrchestrator.enqueuedJobCount);
        LoanRequest__c refreshed = [
            SELECT IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Not Sent', refreshed.IntegrationStatus__c);
        System.assertEquals(null, refreshed.ExternalRequestId__c);
    }

    @IsTest
    static void enqueueAndCallout_success_setsPendingAndAudit() {
        enableIntegration();
        LoanRequest__c loan = createSubmittedLoanWithoutEnqueue();
        injectHttpResponse(BankCrmHttpCalloutMock.Mode.SUCCESS);

        Test.startTest();
        LoanApprovalIntegrationOrchestrator.enqueueEligibleLoans(
            new Set<Id>{ loan.Id },
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );
        Test.stopTest();

        LoanRequest__c refreshed = [
            SELECT
                IntegrationStatus__c,
                ExternalRequestId__c,
                ExternalDecisionReference__c,
                IntegrationLastAttempt__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Pending', refreshed.IntegrationStatus__c);
        System.assertNotEquals(null, refreshed.ExternalRequestId__c);
        System.assertEquals('EXT-DEC-001', refreshed.ExternalDecisionReference__c);
        System.assertNotEquals(null, refreshed.IntegrationLastAttempt__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE LoanRequest__c = :loan.Id AND EventType__c = 'INTEGRATION_RESULT'
            ]
        );
    }

    @IsTest
    static void callout_transient_setsRetryPending() {
        enableIntegration();
        LoanRequest__c loan = createSubmittedLoanWithoutEnqueue();
        injectHttpResponse(BankCrmHttpCalloutMock.Mode.TRANSIENT_5XX);

        Test.startTest();
        LoanApprovalIntegrationOrchestrator.enqueueEligibleLoans(
            new Set<Id>{ loan.Id },
            BankCrmTestDataFactory.buildContext(BankCrmSettingsProvider.getSettings())
        );
        Test.stopTest();

        LoanRequest__c refreshed = [
            SELECT IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Retry Pending', refreshed.IntegrationStatus__c);
        System.assertNotEquals(null, refreshed.ExternalRequestId__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Application_Error__c
                WHERE
                    LoanRequest__c = :loan.Id
                    AND Category__c = 'Integration Transient'
            ]
        );
    }

    @IsTest
    static void callout_permanent_setsFailedAndIntegrationError() {
        enableIntegration();
        LoanRequest__c loan = createSubmittedLoanWithoutEnqueue();
        injectHttpResponse(BankCrmHttpCalloutMock.Mode.PERMANENT_401);

        Test.startTest();
        LoanApprovalIntegrationOrchestrator.enqueueEligibleLoans(
            new Set<Id>{ loan.Id },
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
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Application_Error__c
                WHERE
                    LoanRequest__c = :loan.Id
                    AND Category__c = 'Integration Permanent'
            ]
        );
    }

    @IsTest
    static void domainSubmit_withIntegrationEnabled_enqueues() {
        enableIntegration();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanApprovalIntegrationOrchestrator.skipEnqueueInTests = true;

        Test.startTest();
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Submitted',
            true
        );
        Test.stopTest();

        System.assertEquals(1, LoanApprovalIntegrationOrchestrator.enqueuedJobCount);
        System.assert(
            LoanApprovalIntegrationOrchestrator.lastEnqueuedLoanIds.contains(loan.Id),
            'Submitted loan should be collected for integration enqueue'
        );
    }
}