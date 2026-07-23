@IsTest
private class LoanApprovalCalloutQueueableTest {
    @IsTest
    static void execute_skipsWhenNoLongerEligible() {
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildIntegrationEnabledSettings(250000)
        );
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            5000,
            'Draft',
            true
        );
        Test.setMock(
            HttpCalloutMock.class,
            new BankCrmHttpCalloutMock(BankCrmHttpCalloutMock.Mode.SUCCESS)
        );

        Test.startTest();
        System.enqueueJob(
            new LoanApprovalCalloutQueueable(
                new Set<Id>{ loan.Id },
                CorrelationIdUtil.newId()
            )
        );
        Test.stopTest();

        LoanRequest__c refreshed = [
            SELECT IntegrationStatus__c, ExternalRequestId__c
            FROM LoanRequest__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Not Sent', refreshed.IntegrationStatus__c);
        System.assertEquals(null, refreshed.ExternalRequestId__c);
    }

    @IsTest
    static void constructor_storesIdsAndCorrelation() {
        Set<Id> ids = new Set<Id>();
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
        ids.add(loan.Id);
        String correlation = 'corr-test-1';
        LoanApprovalCalloutQueueable job = new LoanApprovalCalloutQueueable(
            ids,
            correlation
        );
        System.assertEquals(1, job.getLoanIds().size());
        System.assertEquals(correlation, job.getCorrelationId());
    }
}