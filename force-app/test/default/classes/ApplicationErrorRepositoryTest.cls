@IsTest
private class ApplicationErrorRepositoryTest {
    @IsTest
    static void insertAndFindDueRetries() {
        Application_Error__c due = BankCrmTestDataFactory.buildApplicationError(
            'Integration Transient',
            true,
            'Retry Scheduled',
            System.now().addMinutes(-5)
        );
        Application_Error__c future = BankCrmTestDataFactory.buildApplicationError(
            'Integration Transient',
            true,
            'Retry Scheduled',
            System.now().addDays(1)
        );
        Application_Error__c openOnly = BankCrmTestDataFactory.buildApplicationError(
            'Automation',
            false,
            'Open',
            null
        );

        Test.startTest();
        ApplicationErrorRepository.insertErrors(
            new List<Application_Error__c>{ due, future, openOnly }
        );
        List<Application_Error__c> dueRetries = ApplicationErrorRepository.findDueRetries(
            System.now(),
            50
        );
        Test.stopTest();

        Set<Id> dueIds = new Map<Id, Application_Error__c>(dueRetries).keySet();
        System.assertEquals(true, dueIds.contains(due.Id));
        System.assertEquals(false, dueIds.contains(future.Id));
        System.assertEquals(false, dueIds.contains(openOnly.Id));
    }

    @IsTest
    static void updateErrors_updatesResolution() {
        Application_Error__c error = BankCrmTestDataFactory.buildApplicationError(
            'Notification',
            false,
            'Open',
            null
        );
        insert error;
        error.ResolutionStatus__c = 'Resolved';
        error.ResolvedAt__c = System.now();

        Test.startTest();
        ApplicationErrorRepository.updateErrors(new List<Application_Error__c>{ error });
        Test.stopTest();

        Application_Error__c loaded = [
            SELECT ResolutionStatus__c, ResolvedAt__c
            FROM Application_Error__c
            WHERE Id = :error.Id
        ];
        System.assertEquals('Resolved', loaded.ResolutionStatus__c);
        System.assertNotEquals(null, loaded.ResolvedAt__c);
    }
}
