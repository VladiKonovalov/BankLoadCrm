@IsTest
private class AuditRepositoryTest {
    @IsTest
    static void insertEvents_roundTrip() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        LoanRequest__c loan = BankCrmTestDataFactory.createLoanRequest(
            customer.Id,
            1000,
            'Draft',
            true
        );
        Audit__c event = BankCrmTestDataFactory.buildStatusChangedAudit(
            loan.Id,
            customer.Id,
            customer.Name
        );

        Test.startTest();
        List<Database.SaveResult> results = AuditRepository.insertEvents(
            new List<Audit__c>{ event }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess());

        Audit__c loaded = [
            SELECT EventType__c, Source__c, OldValue__c, NewValue__c
            FROM Audit__c
            WHERE Id = :results[0].getId()
        ];
        System.assertEquals('STATUS_CHANGED', loaded.EventType__c);
        System.assertEquals('Apex', loaded.Source__c);
        System.assertEquals('Draft', loaded.OldValue__c);
        System.assertEquals('Submitted', loaded.NewValue__c);
    }

    @IsTest
    static void insertEvents_empty_returnsEmpty() {
        System.assertEquals(
            0,
            AuditRepository.insertEvents(new List<Audit__c>()).size()
        );
    }

    @IsTest
    static void insertEvents_invalidMandatory_throwsMandatoryAutomationException() {
        Audit__c invalid = new Audit__c(
            EventType__c = 'STATUS_CHANGED',
            Source__c = 'Apex',
            CustomerNameSnapshot__c = 'Missing Loan',
            LoanAmountSnapshot__c = 1,
            OccurredAt__c = System.now(),
            CorrelationId__c = 'corr-missing-loan',
            OldValue__c = 'Draft',
            NewValue__c = 'Submitted'
            // LoanRequest__c intentionally omitted — validation requires loan for business events
        );

        Boolean threw = false;
        try {
            AuditRepository.insertEvents(new List<Audit__c>{ invalid });
        } catch (BankCrmException.MandatoryAutomationException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('audit'));
        }
        System.assertEquals(true, threw, 'Expected MandatoryAutomationException');
    }
}
