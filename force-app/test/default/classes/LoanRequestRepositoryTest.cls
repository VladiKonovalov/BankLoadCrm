@IsTest
private class LoanRequestRepositoryTest {
    private static void isolateFromTrigger() {
        BankCrmTestDataFactory.bypassTriggerForServiceTests();
        BankCrmSettingsProvider.setTestOverride(
            BankCrmTestDataFactory.buildSettings(250000)
        );
    }

    @IsTest
    static void insertAndGetByIds_roundTrip() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.buildLoanRequest(
            customer.Id,
            100000,
            'Draft'
        );

        Test.startTest();
        List<Database.SaveResult> results = LoanRequestRepository.insertLoans(
            new List<LoanRequest__c>{ loan },
            null
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess());
        Id loanId = results[0].getId();

        List<LoanRequest__c> loaded = LoanRequestRepository.getByIds(new Set<Id>{ loanId });
        System.assertEquals(1, loaded.size());
        System.assertEquals(100000, loaded[0].LoanAmount__c);
        System.assertEquals('Draft', loaded[0].LoanStatus__c);
        System.assertEquals(
            1,
            LoanRequestRepository.getMapByIds(new Set<Id>{ loanId }).size()
        );
    }

    @IsTest
    static void updateLoans_updatesAmount() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            50000,
            'Draft',
            true
        );
        loan.LoanAmount__c = 75000;

        Test.startTest();
        LoanRequestRepository.updateLoans(
            new List<LoanRequest__c>{ loan },
            new LoanRequestRepository.DmlOptions()
        );
        Test.stopTest();

        LoanRequest__c reloaded = LoanRequestRepository.getByIds(new Set<Id>{ loan.Id })[0];
        System.assertEquals(75000, reloaded.LoanAmount__c);
    }

    @IsTest
    static void getByExternalRequestIds_returnsMatch() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        String externalId = BankCrmTestDataFactory.nextExternalRequestId();
        LoanRequest__c loan = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Pending',
            System.now().addHours(-2),
            externalId
        );
        insert loan;

        Test.startTest();
        List<LoanRequest__c> found = LoanRequestRepository.getByExternalRequestIds(
            new Set<String>{ externalId }
        );
        Map<String, LoanRequest__c> byKey = LoanRequestRepository.getMapByExternalRequestIds(
            new Set<String>{ externalId }
        );
        Test.stopTest();

        System.assertEquals(1, found.size());
        System.assertEquals(loan.Id, found[0].Id);
        System.assertEquals(loan.Id, byKey.get(externalId).Id);
    }

    @IsTest
    static void findIntegrationCandidates_filtersByStatusAndAging() {
        isolateFromTrigger();
        Customer__c customer = BankCrmTestDataFactory.createCustomer(
            UserInfo.getUserId(),
            true
        );
        Datetime oldAttempt = System.now().addHours(-5);
        Datetime recentAttempt = System.now().addMinutes(-10);

        LoanRequest__c agedPending = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Pending',
            oldAttempt,
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        LoanRequest__c recentPending = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Pending',
            recentAttempt,
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        LoanRequest__c succeeded = BankCrmTestDataFactory.buildIntegrationLoan(
            customer.Id,
            'Succeeded',
            oldAttempt,
            BankCrmTestDataFactory.nextExternalRequestId()
        );
        succeeded.ExternalDecisionReference__c = 'DEC-1';
        insert new List<LoanRequest__c>{ agedPending, recentPending, succeeded };

        LoanRequestRepository.IntegrationQueryCriteria criteria =
            new LoanRequestRepository.IntegrationQueryCriteria();
        criteria.statuses = new Set<String>{ 'Pending', 'Retry Pending' };
        criteria.olderThanOrEqual = System.now().addHours(-1);
        criteria.limitSize = 50;

        Test.startTest();
        List<LoanRequest__c> candidates = LoanRequestRepository.findIntegrationCandidates(
            criteria
        );
        Test.stopTest();

        Set<Id> candidateIds = new Map<Id, LoanRequest__c>(candidates).keySet();
        System.assertEquals(true, candidateIds.contains(agedPending.Id));
        System.assertEquals(false, candidateIds.contains(recentPending.Id));
        System.assertEquals(false, candidateIds.contains(succeeded.Id));
    }

    @IsTest
    static void emptyInputs_returnEmptyCollections() {
        isolateFromTrigger();
        System.assertEquals(
            0,
            LoanRequestRepository.insertLoans(new List<LoanRequest__c>(), null).size()
        );
        System.assertEquals(0, LoanRequestRepository.getByIds(new Set<Id>()).size());
        System.assertEquals(
            0,
            LoanRequestRepository.getByExternalRequestIds(new Set<String>()).size()
        );
    }
}
