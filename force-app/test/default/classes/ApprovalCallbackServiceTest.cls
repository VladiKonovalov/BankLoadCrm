@IsTest
private class ApprovalCallbackServiceTest {
    private static LoanRequest__c seedPendingLoan() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000)
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Pending',
            System.now(),
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        // Bypass trigger to seed integration fields without custom permission.
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        insert loan;
        BankCrmTestDataFactory.enableTrigger();
        return loan;
    }

    @IsTest
    static void handleDecision_approved_updatesLoan() {
        LoanRequest__c loan = seedPendingLoan();
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request =
            new LoanApprovalIntegrationContracts.ApprovalCallbackRequest();
        request.externalRequestId = loan.ExternalRequestId__c;
        request.externalDecisionReference = 'DEC-OK-1';
        request.decision = 'Approved';
        request.correlationId = CorrelationIdUtil.newId();

        Test.startTest();
        LoanApprovalIntegrationContracts.ApprovalCallbackResult result =
            ApprovalCallbackService.handleDecision(request);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(false, result.duplicate);
        LoanRequest__c refreshed = [
            SELECT
                LoanStatus__c,
                IntegrationStatus__c,
                ExternalDecisionReference__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Approved', refreshed.LoanStatus__c);
        System.assertEquals('Succeeded', refreshed.IntegrationStatus__c);
        System.assertEquals('DEC-OK-1', refreshed.ExternalDecisionReference__c);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE
                    LoanRequest__c = :loan.Id
                    AND EventType__c = 'STATUS_CHANGED'
            ]
        );
    }

    @IsTest
    static void handleDecision_duplicate_isIdempotent() {
        LoanRequest__c loan = seedPendingLoan();
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request =
            new LoanApprovalIntegrationContracts.ApprovalCallbackRequest();
        request.externalRequestId = loan.ExternalRequestId__c;
        request.externalDecisionReference = 'DEC-DUP-1';
        request.decision = 'Approved';
        request.correlationId = CorrelationIdUtil.newId();

        ApprovalCallbackService.handleDecision(request);

        Test.startTest();
        LoanApprovalIntegrationContracts.ApprovalCallbackResult second =
            ApprovalCallbackService.handleDecision(request);
        Test.stopTest();

        System.assertEquals(true, second.success);
        System.assertEquals(true, second.duplicate);
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM Audit__c
                WHERE
                    LoanRequest__c = :loan.Id
                    AND EventType__c = 'STATUS_CHANGED'
                    AND NewValue__c = 'Approved'
            ]
        );
    }

    @IsTest
    static void handleDecision_unknownExternalId_rejected() {
        seedPendingLoan();
        LoanApprovalIntegrationContracts.ApprovalCallbackRequest request =
            new LoanApprovalIntegrationContracts.ApprovalCallbackRequest();
        request.externalRequestId = 'DOES-NOT-EXIST';
        request.decision = 'Approved';

        LoanApprovalIntegrationContracts.ApprovalCallbackResult result =
            ApprovalCallbackService.handleDecision(request);
        System.assertEquals(false, result.success);
    }
}