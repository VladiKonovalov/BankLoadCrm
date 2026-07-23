@IsTest
private class LoanRequestChangeTest {
    private static final Decimal THRESHOLD = 250000;

    @IsTest
    static void fromTrigger_insert_detectsCrossingAndSubmitted() {
        LoanRequest__c newRecord = BankCrmTestDataFactory.buildLoanRequest(
            null,
            300000,
            'Submitted'
        );

        LoanRequestChange change = LoanRequestChange.fromTrigger(newRecord, null);

        System.assertEquals(true, change.isInsert);
        System.assertEquals(true, change.crossedHighValueThreshold(THRESHOLD));
        System.assertEquals(true, change.becameSubmitted());
        System.assertEquals(false, change.transitionedToApproved());
        System.assertEquals(true, change.statusChanged());
    }

    @IsTest
    static void fromTrigger_update_detectsStatusAndCrossing() {
        LoanRequest__c oldRecord = BankCrmTestDataFactory.buildLoanRequest(
            null,
            200000,
            'Draft'
        );
        LoanRequest__c newRecord = BankCrmTestDataFactory.buildLoanRequest(
            null,
            300000,
            'Approved'
        );

        LoanRequestChange change = LoanRequestChange.fromTrigger(newRecord, oldRecord);

        System.assertEquals(false, change.isInsert);
        System.assertEquals(true, change.statusChanged());
        System.assertEquals(true, change.crossedHighValueThreshold(THRESHOLD));
        System.assertEquals(true, change.transitionedToApproved());
        System.assertEquals(false, change.becameSubmitted());
    }

    @IsTest
    static void fromTrigger_alreadyAbove_noCrossing() {
        LoanRequest__c oldRecord = BankCrmTestDataFactory.buildLoanRequest(
            null,
            300000,
            'Submitted'
        );
        LoanRequest__c newRecord = BankCrmTestDataFactory.buildLoanRequest(
            null,
            400000,
            'Submitted'
        );

        LoanRequestChange change = LoanRequestChange.fromTrigger(newRecord, oldRecord);
        System.assertEquals(false, change.crossedHighValueThreshold(THRESHOLD));
        System.assertEquals(false, change.statusChanged());
    }

    @IsTest
    static void fromTrigger_bulkList_buildsChanges() {
        LoanRequest__c first = BankCrmTestDataFactory.buildLoanRequest(null, 100000, 'Draft');
        LoanRequest__c second = BankCrmTestDataFactory.buildLoanRequest(null, 300000, 'Draft');
        List<LoanRequestChange> changes = LoanRequestChange.fromTrigger(
            new List<LoanRequest__c>{ first, second },
            null
        );
        System.assertEquals(2, changes.size());
        System.assertEquals(false, changes[0].crossedHighValueThreshold(THRESHOLD));
        System.assertEquals(true, changes[1].crossedHighValueThreshold(THRESHOLD));
    }

    @IsTest
    static void factory_canCreateMinimalCustomer() {
        Customer__c customer = BankCrmTestDataFactory.createCustomer(true);
        System.assertNotEquals(null, customer.Id);
        System.assert(String.isNotBlank(customer.CustomerNumber__c));
    }
}
